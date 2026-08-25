import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionsHttpException;

import '../constants/entitlement_public_key.dart';
import 'error_reporting_service.dart';
import 'session_service.dart';
import 'supabase_service.dart';

/// Danlite ELM — entitlement token (Phase 3)
///
/// Fetches a signed statement of the user's licence status from the
/// `/entitlement` Edge Function, verifies its Ed25519 signature locally, and
/// caches it so the app keeps working for 14 days with no network at all.
/// Mechanics work under vehicles and inside garages; requiring a live check
/// would break the app exactly where it is needed most.
///
/// THIS FILE GATES NOTHING. It computes and exposes a status. Phase 8 decides
/// what to do about it.
///
/// ══════════════════════════════════════════════════════════════════════════
/// THE CANONICAL SIGNING STRING — MUST MATCH THE SERVER BYTE FOR BYTE
/// ══════════════════════════════════════════════════════════════════════════
///
/// The signature covers a fixed, positional, pipe-delimited string — NOT the
/// JSON. Signing JSON is the classic way to break cross-language verification:
/// TypeScript and Dart give no matching guarantees on key order, whitespace or
/// unicode escaping, so the bytes differ and the signature fails — and it fails
/// *intermittently*, only for the payloads where the orderings happen to
/// diverge, which is close to undebuggable in the field.
///
///     sub|lic|sid|did|iat|exp
///
/// RULES, all load-bearing:
///   • Field ORDER is fixed and must never be reordered.
///   • Every field is present. A null/absent field is the EMPTY STRING, never
///     the text "null" and never omitted. sid/did are empty until Phase 7
///     assigns a session/device, so today the string contains "||".
///   • Numbers are plain base-10 integers. Unix SECONDS, not milliseconds.
///   • The separator is "|". No field may contain one.
///   • The signed bytes are the UTF-8 encoding of that string.
///
/// The server side lives in supabase/functions/_shared/canonical_payload.ts and
/// carries a copy of this comment. CHANGE ONE, CHANGE BOTH, IN THE SAME COMMIT.
/// ══════════════════════════════════════════════════════════════════════════

/// What the app believes about the current user's licence.
///
/// [expired] and [offlineGraceActive] describe the TOKEN, not the licence:
/// a user can hold a perfectly good `active` licence and still be [expired]
/// here if they have been offline for over 14 days.
enum EntitlementStatus {
  /// Nothing known yet — no user, no cached token, or the first fetch has not
  /// finished. Phase 8 must treat this as "do not decide yet", never as
  /// "not entitled".
  unknown,

  /// Verified: the user has no licence (has not paid).
  inactive,

  /// Verified: the user holds a lifetime licence.
  active,

  /// Verified: the licence was revoked or refunded. See [EntitlementResult.rawLic]
  /// to tell those two apart.
  revoked,

  /// A token exists but is past `exp`, or the device clock was rolled back.
  /// An online refresh is required before anything can be believed again.
  expired,

  /// Running on a cached, still-valid, signature-checked token because the
  /// network was unreachable. This is the normal state in a garage.
  offlineGraceActive,

  /// (Phase 7) The server said, explicitly and unambiguously, that this
  /// account is now signed in on a different device. This is the ONLY status
  /// in this enum that causes the app to sign the user out.
  ///
  /// It is produced by exactly one thing: a successfully-parsed HTTP 409 whose
  /// body is `{"error":"SESSION_SUPERSEDED"}`. Not a timeout, not a 5xx, not a
  /// malformed reply, not a socket error — every one of those is ambiguous,
  /// and an ambiguous signal must never trigger a destructive action.
  supersededSession,
}

/// Where the answer came from — useful to Phase 8 and to support diagnostics.
enum EntitlementSource { network, cache, none }

@immutable
class EntitlementResult {
  const EntitlementResult({
    required this.status,
    required this.source,
    this.rawLic,
    this.sub,
    this.iat,
    this.exp,
    this.diagnostic,
  });

  const EntitlementResult.none(this.diagnostic)
      : status = EntitlementStatus.unknown,
        source = EntitlementSource.none,
        rawLic = null,
        sub = null,
        iat = null,
        exp = null;

  /// (Phase 7) The one result that means "sign this user out".
  const EntitlementResult.superseded()
      : status = EntitlementStatus.supersededSession,
        source = EntitlementSource.network,
        rawLic = null,
        sub = null,
        iat = null,
        exp = null,
        diagnostic = 'session superseded on another device';

  final EntitlementStatus status;
  final EntitlementSource source;

  /// The licence status string exactly as the server sent it: 'inactive',
  /// 'active', 'revoked' or 'refunded'. Preserved because [EntitlementStatus]
  /// deliberately folds 'refunded' into [EntitlementStatus.revoked], and Phase
  /// 5/6 refund handling will need the distinction.
  final String? rawLic;

  final String? sub;
  final int? iat;
  final int? exp;

  /// Never shown to a user — debug/log only, in the house style where no raw
  /// server or exception text reaches the UI.
  final String? diagnostic;

  /// True when the token is cryptographically verified and unexpired,
  /// regardless of whether the licence itself is active.
  bool get isTrustworthy =>
      status == EntitlementStatus.inactive ||
      status == EntitlementStatus.active ||
      status == EntitlementStatus.revoked ||
      status == EntitlementStatus.offlineGraceActive;

  /// Seconds of offline grace left, or null when there is no usable token.
  int? remainingGraceSeconds(int nowUnix) =>
      exp == null ? null : (exp! - nowUnix).clamp(0, 1 << 31);

  @override
  String toString() =>
      'EntitlementResult($status, source: $source, lic: $rawLic, exp: $exp)';
}

class EntitlementService {
  EntitlementService({
    SupabaseService? service,
    FlutterSecureStorage? storage,
    SessionService? sessions,
  })  : _svc = service ?? SupabaseService.instance,
        _sessions = sessions ?? SessionService(),
        _storage = storage ??
            const FlutterSecureStorage(
              // Same options as the auth session store: an AndroidX
              // EncryptedSharedPreferences file whose master key lives in the
              // hardware-backed Android Keystore.
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final SupabaseService _svc;
  final SessionService _sessions;
  final FlutterSecureStorage _storage;

  /// The Edge Function name, as deployed.
  static const String _functionName = 'entitlement';

  /// Secure-storage keys. Versioned so a future token format change can be
  /// rolled out without misreading an old blob.
  static const String _kTokenKey = 'danlite_entitlement_token_v1';
  static const String _kLastServerTimeKey = 'danlite_entitlement_last_server_time_v1';

  /// A network call must not hang the launch path. Well under the auth
  /// provider's own 6-second fallback timer would be too tight for a slow
  /// garage connection, so this is generous but bounded.
  static const Duration _networkTimeout = Duration(seconds: 15);

  /// Tolerance for an honestly-wrong device clock before we call it tampering.
  /// Five minutes is nothing against a 14-day window, but it stops a phone
  /// whose clock drifted or which just resynced NTP backwards from being
  /// treated as an attack.
  static const int _clockSkewToleranceSeconds = 300;

  static final Ed25519 _ed25519 = Ed25519();

  /// The embedded public key, decoded once.
  static final SimplePublicKey _publicKey = SimplePublicKey(
    base64Decode(kEntitlementPublicKeyBase64),
    type: KeyPairType.ed25519,
  );

  int _nowUnix() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Asks the server for a fresh token, verifies it, and caches it.
  ///
  /// On ANY failure — offline, 401, malformed, bad signature — falls through to
  /// [readCached] so a mechanic mid-job is never dropped because a request
  /// failed. Never throws.
  Future<EntitlementResult> fetchAndVerify() async {
    if (!_svc.isConfigured) {
      return readCached(reason: 'backend not configured');
    }
    if (_svc.currentSession == null) {
      // No signed-in user: there is nothing to ask about. Any cached token
      // belongs to a previous session and must not be reported as this user's.
      return const EntitlementResult.none('no session');
    }

    // (Phase 7) Name the session this device believes it holds. Null on a
    // fresh install or a build upgraded from Phase 3, and the server treats
    // that as "no session check" — so an app that has not claimed yet keeps
    // working exactly as before.
    final sessionId = await _sessions.readSessionId();

    try {
      final res = await _svc.client.functions
          .invoke(
            _functionName,
            body: sessionId == null ? <String, dynamic>{} : {'session_id': sessionId},
          )
          .timeout(_networkTimeout);

      if (res.status != 200) {
        debugPrint('[entitlement] function returned ${res.status}');
        return readCached(reason: 'http ${res.status}');
      }

      final data = res.data;
      final Map<String, dynamic> payload = data is String
          ? jsonDecode(data) as Map<String, dynamic>
          : Map<String, dynamic>.from(data as Map);

      final verified = await _verifyPayload(payload);
      if (verified == null) {
        // A response that does not verify is discarded ENTIRELY — not cached,
        // not partially trusted, not used for this call. An unverified payload
        // is indistinguishable from one an attacker wrote.
        debugPrint('[entitlement] signature verification FAILED — discarding');
        // Report-only (Phase 9). The discard decision is already made above;
        // this observes it. A signature failure is worth surfacing because it
        // is either a backend key mismatch or tampering, and neither is
        // visible from the user-facing behaviour (which is just "cached").
        ErrorReportingService.reportError(
          'entitlement signature verification failed',
          StackTrace.current,
          context: {'stage': 'network_payload'},
        );
        return readCached(reason: 'signature invalid');
      }

      await _persist(payload, verified.iat);

      return EntitlementResult(
        status: _statusFor(verified.rawLic),
        source: EntitlementSource.network,
        rawLic: verified.rawLic,
        sub: verified.sub,
        iat: verified.iat,
        exp: verified.exp,
      );
    } on FunctionsHttpException catch (e) {
      // ══════════════════════════════════════════════════════════════════
      // THE ONLY CODE PATH IN THE APP THAT CAN CAUSE A FORCED LOGOUT.
      // ══════════════════════════════════════════════════════════════════
      //
      // Note this is `on FunctionsHttpException`, not a bare catch on status.
      // The client throws THREE different exception types and only this one
      // means "the Edge Function itself answered":
      //   • FunctionsFetchException — the request never left the phone
      //     (status is 0). Ambiguous. Not this branch.
      //   • FunctionsRelayException — Supabase's relay failed before
      //     reaching our code. It carries a status too, and a relayed 409
      //     would NOT be ours. Ambiguous. Not this branch.
      //   • FunctionsHttpException — our function returned this status.
      //
      // Even then all three of these must hold: the status is exactly 409,
      // the body parsed, and it says SESSION_SUPERSEDED. Anything else —
      // a 409 with an unexpected body, a details field that is a raw string
      // because the JSON did not parse — falls through to the cached path
      // and signs nobody out.
      //
      // This is the Phase 2 lesson applied: a Supabase 500 was once being
      // reported as a network failure, and the fix was to stop letting one
      // ambiguous signal stand in for another. A destructive action needs an
      // unambiguous instruction.
      if (e.status == 409) {
        final details = e.details;
        final Map<String, dynamic>? body = details is Map
            ? Map<String, dynamic>.from(details)
            : null;

        if (body != null && body['error'] == 'SESSION_SUPERSEDED') {
          debugPrint('[entitlement] SESSION_SUPERSEDED — this device is no '
              'longer the active session');
          // Drop both the token and the session id. The token must go because
          // it would otherwise stay valid for its full 14 days and let a
          // superseded device carry on offline; the session id must go
          // because it now names a revoked session.
          await _clearToken();
          await _sessions.clearSession();
          return const EntitlementResult.superseded();
        }
        debugPrint('[entitlement] 409 with an unrecognised body — ignoring');
      }
      debugPrint('[entitlement] http ${e.status}');
      // Report-only (Phase 9). Reached only when the 409/SESSION_SUPERSEDED
      // branch above did NOT apply, so the forced-logout decision has already
      // been made and declined. Status code only — never `e.details`, which
      // can echo server text.
      ErrorReportingService.reportError(
        'entitlement function returned an error status',
        StackTrace.current,
        context: {'stage': 'network', 'status': '${e.status}'},
      );
      return readCached(reason: 'http ${e.status}');
    } catch (e) {
      // Offline is the expected case here, not an exception worth shouting
      // about. Type only — never the message, which can echo server text.
      debugPrint('[entitlement] fetch failed: ${e.runtimeType}');
      // Report-only (Phase 9). Offline is the expected case here and is NOT
      // worth an alert — but this catch is deliberately broad and also swallows
      // jsonDecode and cast failures, which are real bugs that would otherwise
      // be invisible. The exception type is reported so the two can be told
      // apart in Sentry: filter out SocketException / TimeoutException /
      // ClientException and what remains is a genuine defect. Type only, never
      // the message, which can echo server text.
      ErrorReportingService.reportError(
        e,
        StackTrace.current,
        context: {'stage': 'network', 'exception': '${e.runtimeType}'},
      );
      return readCached(reason: 'fetch failed');
    }
  }

  /// Reads the cached token, re-verifies it, and applies the grace window.
  ///
  /// The signature is checked EVERY time, not just on arrival: the cache lives
  /// on the device, and a stored token is only worth what its signature is
  /// still worth. On-disk tampering is exactly what this catches.
  Future<EntitlementResult> readCached({String? reason}) async {
    String? raw;
    try {
      raw = await _storage.read(key: _kTokenKey);
    } catch (e) {
      // A Keystore entry can become undecryptable after a restore or a
      // lock-screen credential reset — same failure mode the auth session
      // store handles. Treat it as "no token".
      debugPrint('[entitlement] secure read failed: ${e.runtimeType}');
      return EntitlementResult.none(reason ?? 'cache unreadable');
    }

    if (raw == null || raw.isEmpty) {
      return EntitlementResult.none(reason ?? 'no cached token');
    }

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      await _clearToken();
      return EntitlementResult.none('cached token unparseable');
    }

    final verified = await _verifyPayload(payload);
    if (verified == null) {
      // Someone edited the stored blob. Drop it: a token that fails its own
      // signature has no value and keeping it only invites confusion later.
      debugPrint('[entitlement] cached token failed verification — clearing');
      await _clearToken();
      // Report-only (Phase 9). The token is already cleared above. Worth
      // surfacing: a stored token that fails its own signature means either
      // on-device tampering or a signing-key rotation that left real customers
      // stranded — and the second one is an outage nobody would otherwise see.
      ErrorReportingService.reportError(
        'cached entitlement token failed verification',
        StackTrace.current,
        context: {'stage': 'cache'},
      );
      return const EntitlementResult.none('cached token tampered');
    }

    final now = _nowUnix();

    // ── Clock-rollback defence ────────────────────────────────────────────
    //
    // THIS IS WHAT STOPS "set the clock back to before it expired".
    //
    // `last_known_server_time` is the highest `iat` this device has ever seen
    // on a VERIFIED token. It only ever moves forward, and only from a
    // server-signed value — never from the device clock, which is precisely
    // the thing under suspicion.
    //
    // If the device now claims a time meaningfully EARLIER than a moment the
    // server has already attested, the clock has been moved backwards. In that
    // case `exp` is meaningless (an expired token would look fresh again), so
    // the token is treated as expired regardless of what it says, and only an
    // online refresh can restore trust.
    final lastServerTime = await _readLastServerTime();
    if (lastServerTime != null && now < lastServerTime - _clockSkewToleranceSeconds) {
      debugPrint('[entitlement] device clock is behind last server time — '
          'treating token as expired');
      return EntitlementResult(
        status: EntitlementStatus.expired,
        source: EntitlementSource.cache,
        rawLic: verified.rawLic,
        sub: verified.sub,
        iat: verified.iat,
        exp: verified.exp,
        diagnostic: 'clock rollback detected',
      );
    }

    // ── The 14-day grace window ───────────────────────────────────────────
    if (now > verified.exp) {
      return EntitlementResult(
        status: EntitlementStatus.expired,
        source: EntitlementSource.cache,
        rawLic: verified.rawLic,
        sub: verified.sub,
        iat: verified.iat,
        exp: verified.exp,
        diagnostic: reason ?? 'token expired',
      );
    }

    // Verified, unexpired, and served from disk because the network was not
    // available. The licence status itself is still reported truthfully in
    // rawLic for Phase 8.
    return EntitlementResult(
      status: EntitlementStatus.offlineGraceActive,
      source: EntitlementSource.cache,
      rawLic: verified.rawLic,
      sub: verified.sub,
      iat: verified.iat,
      exp: verified.exp,
      diagnostic: reason,
    );
  }

  /// Drops the cached token AND the stored session id. Called on sign-out so
  /// one user's state can never be read as the next user's.
  ///
  /// (Phase 7) The session id must go with the token, and this is not
  /// housekeeping — it closes a real false-positive logout. The stored id
  /// names a session belonging to the user who just left. If it survived, the
  /// NEXT user to sign in on this phone would have that stranger's session id
  /// attached to their first /entitlement call, before their own claim had
  /// landed. For a new user with no active session that is harmless, but for
  /// one who is already signed in on another phone it does not match their
  /// active session — so the server would correctly answer 409 and this app
  /// would sign them out moments after they successfully signed in.
  ///
  /// `last_known_server_time` deliberately SURVIVES this. It is a statement
  /// about this DEVICE's clock, not about the user, and clearing it would hand
  /// an attacker a trivial reset: sign out, roll the clock back, sign in again.
  /// The device secret survives for the same kind of reason — see
  /// [SessionService.clearSession].
  Future<void> clear() async {
    await _clearToken();
    await _sessions.clearSession();
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _clearToken() async {
    try {
      await _storage.delete(key: _kTokenKey);
    } catch (e) {
      debugPrint('[entitlement] secure delete failed: ${e.runtimeType}');
    }
  }

  Future<void> _persist(Map<String, dynamic> payload, int iat) async {
    try {
      await _storage.write(key: _kTokenKey, value: jsonEncode(payload));
    } catch (e) {
      // A failed cache write costs offline grace, not correctness. The live
      // result still stands for this session.
      debugPrint('[entitlement] secure write failed: ${e.runtimeType}');
    }
    await _advanceLastServerTime(iat);
  }

  Future<int?> _readLastServerTime() async {
    try {
      final v = await _storage.read(key: _kLastServerTimeKey);
      return v == null ? null : int.tryParse(v);
    } catch (e) {
      debugPrint('[entitlement] last-server-time read failed: ${e.runtimeType}');
      return null;
    }
  }

  /// Monotonic: only ever moves forward. A replayed or reordered older token
  /// can never lower the watermark, which is what keeps the rollback check
  /// meaningful.
  Future<void> _advanceLastServerTime(int iat) async {
    try {
      final current = await _readLastServerTime();
      if (current != null && current >= iat) return;
      await _storage.write(key: _kLastServerTimeKey, value: iat.toString());
    } catch (e) {
      debugPrint('[entitlement] last-server-time write failed: ${e.runtimeType}');
    }
  }

  EntitlementStatus _statusFor(String lic) {
    switch (lic) {
      case 'active':
        return EntitlementStatus.active;
      case 'inactive':
        return EntitlementStatus.inactive;
      case 'revoked':
      case 'refunded':
        // Folded together: both mean "this user is not entitled any more".
        // The exact string stays available on EntitlementResult.rawLic for the
        // refund flows in Phase 5/6.
        return EntitlementStatus.revoked;
      default:
        // An unrecognised status is not assumed to be safe. Fail closed to
        // "unknown" and let Phase 8 decide, rather than guessing 'active'.
        debugPrint('[entitlement] unrecognised licence status: $lic');
        return EntitlementStatus.unknown;
    }
  }

  /// Verifies the Ed25519 signature over the canonical string.
  ///
  /// Returns the parsed claims on success, or null if ANYTHING is wrong —
  /// missing field, wrong type, bad signature. Callers must treat null as
  /// "this payload does not exist".
  Future<_VerifiedClaims?> _verifyPayload(Map<String, dynamic> payload) async {
    try {
      final sub = payload['sub'];
      final lic = payload['lic'];
      final sid = payload['sid'];
      final did = payload['did'];
      final iat = payload['iat'];
      final exp = payload['exp'];
      final sig = payload['sig'];

      if (sub is! String ||
          lic is! String ||
          iat is! int ||
          exp is! int ||
          sig is! String) {
        debugPrint('[entitlement] payload shape rejected');
        return null;
      }

      // Null and absent both normalise to '' — must match the server, which
      // renders a null sid/did as the empty string.
      final sidStr = sid is String ? sid : '';
      final didStr = did is String ? did : '';

      final canonical = '$sub|$lic|$sidStr|$didStr|$iat|$exp';
      final message = utf8.encode(canonical);

      final signature = Signature(
        _base64UrlDecode(sig),
        publicKey: _publicKey,
      );

      final ok = await _ed25519.verify(message, signature: signature);
      if (!ok) return null;

      return _VerifiedClaims(
        sub: sub,
        rawLic: lic,
        iat: iat,
        exp: exp,
      );
    } catch (e) {
      debugPrint('[entitlement] verification error: ${e.runtimeType}');
      return null;
    }
  }

  /// The server sends base64url without padding; Dart's decoder needs it back.
  Uint8List _base64UrlDecode(String input) {
    final normalised = input.replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalised.padRight(
      normalised.length + ((4 - normalised.length % 4) % 4),
      '=',
    );
    return base64Decode(padded);
  }
}

@immutable
class _VerifiedClaims {
  const _VerifiedClaims({
    required this.sub,
    required this.rawLic,
    required this.iat,
    required this.exp,
  });

  final String sub;
  final String rawLic;
  final int iat;
  final int exp;
}
