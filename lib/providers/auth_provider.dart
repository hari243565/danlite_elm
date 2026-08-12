import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/// Where the user is in the auth flow. [unknown] only lasts until the Supabase
/// SDK reports its first state — the auth gate shows the splash meanwhile.
enum AuthStatus { unknown, signedOut, awaitingOtp, signedIn }

/// Which channel the pending OTP was sent over. Country decides this:
/// India → SMS, everywhere else → email (Phase 6 finalises the providers).
enum OtpChannelKind { email, phone }

class AuthProvider extends ChangeNotifier {
  AuthProvider({SupabaseService? service})
      : _svc = service ?? SupabaseService.instance;

  final SupabaseService _svc;
  StreamSubscription<AuthState>? _sub;

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  bool _busy = false;
  bool get busy => _busy;

  /// AppStrings key for the last error, or null. The UI resolves it with
  /// `context.tr(...)` — this is never a server or exception string.
  String? _errorKey;
  String? get errorKey => _errorKey;

  /// The email or E.164 phone the pending OTP went to.
  String? _pendingIdentifier;
  String? get pendingIdentifier => _pendingIdentifier;

  OtpChannelKind? _pendingChannel;
  OtpChannelKind? get pendingChannel => _pendingChannel;

  /// ISO-3166 alpha-2, e.g. 'IN'. Chosen on the sign-up screen and written to
  /// `profiles.country_code` once, on first sign-in.
  String _countryCode = 'IN';
  String get countryCode => _countryCode;
  set countryCode(String code) {
    if (code == _countryCode) return;
    _countryCode = code;
    notifyListeners();
  }

  /// Stable-ish device identity, held in memory only. Phase 7 (single active
  /// session) is what registers devices; nothing is sent anywhere in Phase 2.
  String? _deviceFingerprint;
  String? get deviceFingerprint => _deviceFingerprint;

  /// User id whose profile row has already been checked this session.
  String? _profileEnsuredFor;

  bool get isConfigured => _svc.isConfigured;
  User? get user => _svc.currentUser;

  /// True when the country routes OTP over SMS rather than email.
  static bool usesPhoneOtp(String countryCode) => countryCode == 'IN';

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Wires up the auth-state stream. Safe to call when Supabase is not
  /// configured: the status settles on [AuthStatus.signedOut] and the gate
  /// leaves the existing app untouched.
  Future<void> init() async {
    unawaited(_loadDeviceFingerprint());

    if (!_svc.isConfigured) {
      _set(AuthStatus.signedOut);
      return;
    }

    _sub = _svc.onAuthStateChange.listen(
      _onAuthState,
      onError: (Object e) {
        debugPrint('[auth] state stream error: $e');
        if (_status == AuthStatus.unknown) _set(AuthStatus.signedOut);
      },
    );

    // The SDK emits `initialSession` once storage recovery finishes, which is
    // what normally resolves `unknown`. If recovery never reports (corrupt
    // Keystore entry, SDK error), fall back rather than hang on the splash.
    Timer(const Duration(seconds: 6), () {
      if (_status == AuthStatus.unknown) {
        _set(_svc.currentSession != null
            ? AuthStatus.signedIn
            : AuthStatus.signedOut);
      }
    });
  }

  void _onAuthState(AuthState state) {
    final session = state.session;
    switch (state.event) {
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
      case AuthChangeEvent.initialSession:
        if (session != null) {
          _pendingIdentifier = null;
          _pendingChannel = null;
          _set(AuthStatus.signedIn);
          // Once per signed-in user, not on every hourly token refresh.
          if (_profileEnsuredFor != session.user.id) {
            _profileEnsuredFor = session.user.id;
            unawaited(_ensureProfile(session.user));
          }
        } else if (_status != AuthStatus.awaitingOtp) {
          _set(AuthStatus.signedOut);
        }
      case AuthChangeEvent.signedOut:
        _pendingIdentifier = null;
        _pendingChannel = null;
        _set(AuthStatus.signedOut);
      default:
        break;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Email path — used by every country except India.
  Future<bool> startEmailSignup(String email) =>
      _dispatch(email.trim(), OtpChannelKind.email, isSignup: true);

  /// Phone path — India. [phoneE164] must already carry the dial code.
  Future<bool> startPhoneSignup(String phoneE164, String countryCode) {
    _countryCode = countryCode;
    return _dispatch(phoneE164.trim(), OtpChannelKind.phone, isSignup: true);
  }

  /// Log in with whichever identifier the user typed. An `@` means email;
  /// anything else is treated as a phone number.
  Future<bool> login(String identifier) {
    final id = identifier.trim();
    final channel =
        id.contains('@') ? OtpChannelKind.email : OtpChannelKind.phone;
    return _dispatch(id, channel, isSignup: false);
  }

  Future<bool> _dispatch(
    String identifier,
    OtpChannelKind channel, {
    required bool isSignup,
  }) async {
    _beginBusy();
    // Sign-up and log-in intentionally hit the same endpoint with the same
    // payload; `isSignup` only picks which service method name is used, so the
    // two flows are indistinguishable on the wire.
    final AuthResult res;
    if (channel == OtpChannelKind.email) {
      res = isSignup
          ? await _svc.signUpWithEmailOtp(identifier)
          : await _svc.signInWithEmailOtp(identifier);
    } else {
      res = isSignup
          ? await _svc.signUpWithPhoneOtp(identifier)
          : await _svc.signInWithPhoneOtp(identifier);
    }

    if (res.ok && res.needsOtp) {
      _pendingIdentifier = identifier;
      _pendingChannel = channel;
      _errorKey = null;
      _busy = false;
      _set(AuthStatus.awaitingOtp);
      return true;
    }

    _errorKey = res.messageKey;
    _busy = false;
    notifyListeners();
    return false;
  }

  /// Re-sends the code to the pending identifier. The screen owns the cooldown.
  Future<bool> resendOtp() async {
    final id = _pendingIdentifier;
    final channel = _pendingChannel;
    if (id == null || channel == null) return false;
    return _dispatch(id, channel, isSignup: false);
  }

  /// Verifies the 6-digit code. On success [status] becomes
  /// [AuthStatus.signedIn] immediately; the SDK's own `signedIn` event follows
  /// and is what triggers the profile row.
  Future<bool> verifyOtp(String code) async {
    final id = _pendingIdentifier;
    final channel = _pendingChannel;
    if (id == null || channel == null) {
      _errorKey = AuthMessages.generic;
      notifyListeners();
      return false;
    }

    _beginBusy();
    final res = channel == OtpChannelKind.email
        ? await _svc.verifyEmailOtp(email: id, token: code.trim())
        : await _svc.verifyPhoneOtp(phoneE164: id, token: code.trim());

    _busy = false;
    if (res.ok) {
      _errorKey = null;
      // Set the status here rather than waiting for the SDK's broadcast event:
      // the caller navigates straight back to the gate, and the gate must not
      // still see `awaitingOtp` on that rebuild or it would bounce the user
      // back to the OTP screen. The event lands moments later and is
      // idempotent. It also clears the pending identifier — doing that here
      // would blank the OTP screen's subtitle for one frame first.
      _set(AuthStatus.signedIn);
      return true;
    }
    _errorKey = res.messageKey;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    _beginBusy();
    await _svc.signOut();
    _pendingIdentifier = null;
    _pendingChannel = null;
    _profileEnsuredFor = null;
    _errorKey = null;
    _busy = false;
    _set(AuthStatus.signedOut);
  }

  void clearError() {
    if (_errorKey == null) return;
    _errorKey = null;
    notifyListeners();
  }

  // ── Profile row ───────────────────────────────────────────────────────────

  /// Creates `public.profiles` on first sign-in. An existing row is left alone:
  /// `country_code` is set once and is protected server-side by the Phase 1
  /// trigger, so the client must never try to rewrite it.
  Future<void> _ensureProfile(User user) async {
    if (!_svc.isConfigured) return;
    try {
      final existing = await _svc.client
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();
      if (existing != null) return;

      await _svc.client.from('profiles').insert({
        'id': user.id,
        'email': user.email,
        'phone': user.phone,
        'country_code': _countryCode,
        'signup_platform': 'android',
      });
    } catch (e) {
      // A profile that fails to write must not block a signed-in user. The row
      // is re-attempted on the next sign-in, and Phase 1's server-side trigger
      // is the real backstop.
      debugPrint('[auth] profile upsert skipped: ${e.runtimeType}');
    }
  }

  // ── Device identity (Phase 7 groundwork) ──────────────────────────────────

  Future<void> _loadDeviceFingerprint() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      // Build-level identity only. device_info_plus exposes no per-install
      // ANDROID_ID, so Phase 7 will pair this with a server-issued device id
      // when it actually registers devices.
      _deviceFingerprint =
          '${info.manufacturer}|${info.model}|${info.device}|${info.hardware}|${info.id}';
    } catch (e) {
      debugPrint('[auth] device info unavailable: ${e.runtimeType}');
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  void _beginBusy() {
    _busy = true;
    _errorKey = null;
    notifyListeners();
  }

  /// Always notifies, even when the status is unchanged: [busy] and
  /// [errorKey] usually moved with it (a resend, for instance, re-enters
  /// `awaitingOtp` and must still clear the screen's spinner).
  void _set(AuthStatus s) {
    _status = s;
    notifyListeners();
  }
}
