import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'supabase_service.dart';

/// Danlite ELM — single active session (Phase 7)
///
/// Registers this device with the backend once per login and remembers the
/// session id the server hands back. [EntitlementService] then carries that id
/// on every entitlement refresh, which is how the server can tell a device it
/// is no longer the active one.
///
/// THIS FILE GATES NOTHING and never signs anybody out. It records identity;
/// [EntitlementProvider] owns the one path that can act on a supersession.
///
/// ══════════════════════════════════════════════════════════════════════════
/// THE FINGERPRINT — what it is, and what it deliberately is NOT
/// ══════════════════════════════════════════════════════════════════════════
///
/// A random 256-bit secret, generated once on first use, kept in the same
/// Android Keystore-backed store as the auth tokens, and NEVER transmitted.
/// What goes to the server is its SHA-256 — an opaque 64-character hex string
/// that identifies this install and reveals nothing else. Data minimisation,
/// matching the DPDP posture the schema was built around.
///
/// It is NOT derived from any hardware identifier. device_info_plus removed
/// `androidId` in v4 (this project is on 10.1.2) precisely because it is a
/// privacy-sensitive device-wide identifier, and reaching for one via a new
/// dependency would be a worse trade than this: a per-install random value is
/// strictly more private AND strictly more accurate, because it identifies an
/// installation rather than a handset.
///
/// It also deliberately excludes build details — manufacturer, model, build
/// id. Folding those in looks appealing (a restored backup on a new handset
/// would get a new identity) but it fails the wrong way: an ordinary Android
/// OTA changes the build id, which would change the fingerprint, which would
/// read as a DIFFERENT device and sign the user out of their own phone for
/// installing a system update. Given the choice between occasionally failing
/// to supersede and occasionally logging out an innocent user, this phase
/// fails toward not-logging-anyone-out every time.
class SessionService {
  SessionService({SupabaseService? service, FlutterSecureStorage? storage})
      : _svc = service ?? SupabaseService.instance,
        _storage = storage ??
            const FlutterSecureStorage(
              // Same options as the auth session store and the entitlement
              // cache: an AndroidX EncryptedSharedPreferences file whose
              // master key lives in the hardware-backed Android Keystore.
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final SupabaseService _svc;
  final FlutterSecureStorage _storage;

  static const String _functionName = 'claim-session';

  /// Secure-storage keys, versioned like the entitlement ones so a future
  /// format change can roll out without misreading an old value.
  static const String _kSessionIdKey = 'danlite_session_id_v1';
  static const String _kDeviceSecretKey = 'danlite_device_secret_v1';

  /// A claim must not hang the login path. The user is already signed in by
  /// the time this runs, so a slow answer costs bookkeeping, never access.
  static const Duration _networkTimeout = Duration(seconds: 15);

  static final Sha256 _sha256 = Sha256();

  /// Cached for the process lifetime — the value never changes, and hashing on
  /// every entitlement refresh would be pointless work.
  String? _fingerprintCache;

  // ── Public API ────────────────────────────────────────────────────────────

  /// The stored session id, or null if this install has never claimed one.
  ///
  /// Null is a perfectly normal state: a fresh install before its first login,
  /// or a build upgraded from Phase 3. The server treats an absent session id
  /// as "do not check", so nothing breaks.
  Future<String?> readSessionId() async {
    try {
      final v = await _storage.read(key: _kSessionIdKey);
      return (v == null || v.isEmpty) ? null : v;
    } catch (e) {
      // A Keystore entry can become undecryptable after a restore or a
      // lock-screen credential reset — the same failure the auth and
      // entitlement stores already handle. Treat it as "no session".
      debugPrint('[session] secure read failed: ${e.runtimeType}');
      return null;
    }
  }

  /// Tells the backend this device is now the active one.
  ///
  /// Returns true only when a session id came back and was stored. NEVER
  /// throws: [AuthProvider] calls this immediately after a successful OTP and
  /// a failure here must not turn a good login into a bad one.
  Future<bool> claimSession() async {
    if (!_svc.isConfigured) return false;
    if (_svc.currentSession == null) return false;

    try {
      final fingerprint = await _deviceFingerprint();
      if (fingerprint == null) {
        debugPrint('[session] no fingerprint available — skipping claim');
        return false;
      }

      final res = await _svc.client.functions
          .invoke(
            _functionName,
            body: {
              'fingerprint': fingerprint,
              'platform': 'android',
              'model': await _deviceModel(),
            },
          )
          .timeout(_networkTimeout);

      final data = res.data;
      final Map<String, dynamic> payload = data is String
          ? jsonDecode(data) as Map<String, dynamic>
          : Map<String, dynamic>.from(data as Map);

      final sessionId = payload['session_id'];
      if (sessionId is! String || sessionId.isEmpty) {
        debugPrint('[session] claim returned no session id');
        return false;
      }

      await _storage.write(key: _kSessionIdKey, value: sessionId);
      // Logged as a boolean, never the ids themselves.
      debugPrint('[session] claimed (superseded another device: '
          '${payload['superseded'] == true})');
      return true;
    } catch (e) {
      // Offline, 5xx, timeout, malformed — all the same here. The entitlement
      // layer simply keeps operating in the backward-compatible no-session
      // mode until the next successful claim.
      debugPrint('[session] claim failed: ${e.runtimeType}');
      return false;
    }
  }

  /// Forgets the stored session id.
  ///
  /// Called on sign-out and on a supersession. The DEVICE SECRET deliberately
  /// survives: it is a statement about this installation, not about the user,
  /// and regenerating it on every logout would make the same phone look like a
  /// brand-new device on every login — which would defeat the same-device
  /// false-positive guard that [claimSession] depends on.
  Future<void> clearSession() async {
    try {
      await _storage.delete(key: _kSessionIdKey);
    } catch (e) {
      debugPrint('[session] secure delete failed: ${e.runtimeType}');
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  /// SHA-256 of the persisted per-install secret, as lowercase hex.
  Future<String?> _deviceFingerprint() async {
    final cached = _fingerprintCache;
    if (cached != null) return cached;

    final secret = await _deviceSecret();
    if (secret == null) return null;

    final digest = await _sha256.hash(utf8.encode(secret));
    final hex = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    _fingerprintCache = hex;
    return hex;
  }

  /// Reads the per-install secret, generating and persisting one on first use.
  ///
  /// Returns null only if secure storage is unusable, in which case there is
  /// no stable identity to offer and the claim is skipped rather than sending
  /// a value that would change on every launch — a rotating fingerprint would
  /// make the user supersede themselves on every single login.
  Future<String?> _deviceSecret() async {
    try {
      final existing = await _storage.read(key: _kDeviceSecretKey);
      if (existing != null && existing.isNotEmpty) return existing;

      final rng = Random.secure();
      final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
      final secret = base64UrlEncode(bytes);

      await _storage.write(key: _kDeviceSecretKey, value: secret);
      return secret;
    } catch (e) {
      debugPrint('[session] device secret unavailable: ${e.runtimeType}');
      return null;
    }
  }

  /// Human-readable model, for the "which device is signed in" list on the
  /// billing portal. Display only — it is never part of the identity.
  Future<String?> _deviceModel() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final model = '${info.manufacturer} ${info.model}'.trim();
      return model.isEmpty ? null : model;
    } catch (e) {
      debugPrint('[session] device info unavailable: ${e.runtimeType}');
      return null;
    }
  }
}
