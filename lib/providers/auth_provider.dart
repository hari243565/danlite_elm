import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_config.dart';
import '../services/session_service.dart';
import '../services/supabase_service.dart';

/// (Phase 7) AppStrings key shown on the login screen after a forced sign-out.
///
/// Declared here rather than alongside the other keys in [AuthMessages],
/// because that class lives in `supabase_service.dart` — a file this phase is
/// not permitted to touch. It follows the same convention: a key resolved with
/// `context.tr(...)`, never a literal sentence and never server text.
const String kSessionSupersededMessageKey = 'session_superseded_body';

/// Where the user is in the auth flow. [unknown] only lasts until the Supabase
/// SDK reports its first state — the auth gate shows the splash meanwhile.
enum AuthStatus { unknown, signedOut, awaitingOtp, signedIn }

/// How a one-time code is delivered. This is the user's own choice on the
/// sign-up / log-in screens and is deliberately independent of [countryCode],
/// which only drives pricing. SMS is not provisioned in India yet (DLT/TRAI
/// registration pending), so the screens default everyone to email.
enum OtpChannel { email, phone }

class AuthProvider extends ChangeNotifier {
  AuthProvider({SupabaseService? service, SessionService? sessions})
      : _svc = service ?? SupabaseService.instance,
        _sessions = sessions ?? SessionService();

  final SupabaseService _svc;
  final SessionService _sessions;
  StreamSubscription<AuthState>? _sub;

  /// (Phase 7) Why the user is about to find themselves at the login screen,
  /// when it was not their own doing.
  ///
  /// Static, and deliberately so. [EntitlementProvider] is constructed
  /// independently of this class in main.dart and holds no reference to it, so
  /// there is no instance to hand a message to. Rather than introduce a
  /// registry of live providers, the reason is parked here and collected by
  /// whichever AuthProvider is listening when the `signedOut` event arrives —
  /// which is the same stream that drives every other sign-out in the app.
  static String? _pendingForcedLogoutKey;

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

  OtpChannel? _pendingChannel;
  OtpChannel? get pendingChannel => _pendingChannel;

  /// ISO-3166 alpha-2, e.g. 'IN'. Chosen on the sign-up screen. It decides
  /// pricing only (₹109 India vs $1.10 international) and never the OTP
  /// channel.
  ///
  /// The client does not write it: `profiles.country_code` is set by the
  /// server-side `handle_new_user` trigger from the signup metadata, and
  /// `profiles_protect_fields` reverts any later client attempt to change it.
  /// This value reaches that trigger by being passed to the OTP send in
  /// [_dispatch], which puts it in the `data` payload — it is a hint the
  /// server re-validates, not an instruction. An unset or malformed code is
  /// dropped there, leaving the row on the column default 'IN'.
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

  bool get isConfigured => _svc.isConfigured;
  User? get user => _svc.currentUser;

  // ── Backend configuration ─────────────────────────────────────────────────
  //
  // The auth screens read these to decide whether to paint the diagnostic
  // strip. They are computed, not cached, so a rebuild always reflects reality.

  /// Whether the `.env` that shipped in this build is usable.
  ConfigStatus get configStatus => AppConfig.validate();

  bool get configOk => configStatus == ConfigStatus.ok;

  /// A one-line summary safe to render in a release build: presence and shape
  /// only, never any part of the URL or the key. See
  /// [AppConfig.describeForDiagnostics].
  String get configDiagnostics => AppConfig.describeForDiagnostics();

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
        } else if (_status != AuthStatus.awaitingOtp) {
          _set(AuthStatus.signedOut);
        }
      case AuthChangeEvent.signedOut:
        _pendingIdentifier = null;
        _pendingChannel = null;
        // Normally null, and then this is an ordinary sign-out. When Phase 7
        // forced it, the login screen's existing error banner explains why —
        // no screen had to change to say it.
        _errorKey = _pendingForcedLogoutKey;
        _pendingForcedLogoutKey = null;
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

  /// Signs up over the channel the user picked. [identifier] is an email
  /// address for [OtpChannel.email], or an E.164 number (dial code already
  /// attached) for [OtpChannel.phone]. The country selector is unrelated: it
  /// is written through [countryCode] by the screen and only affects pricing.
  Future<bool> startSignup({
    required String identifier,
    required OtpChannel channel,
  }) =>
      _dispatch(identifier.trim(), channel, isSignup: true);

  /// Logs in over the channel the user picked, same identifier rules as
  /// [startSignup].
  Future<bool> login({
    required String identifier,
    required OtpChannel channel,
  }) =>
      _dispatch(identifier.trim(), channel, isSignup: false);

  Future<bool> _dispatch(
    String identifier,
    OtpChannel channel, {
    required bool isSignup,
  }) async {
    _beginBusy();

    // Fail fast and honestly. A build whose `.env` did not survive packaging
    // cannot reach the backend at all, and the resulting socket error used to
    // be reported as "no connection" — blaming the user's phone for a fault in
    // this app. Say what is actually wrong instead, and skip the request.
    if (!configOk) {
      debugPrint('[auth] dispatch blocked — $configDiagnostics');
      _errorKey = AuthMessages.config;
      _busy = false;
      notifyListeners();
      return false;
    }
    // Sign-up and log-in intentionally hit the same endpoint with the same
    // payload; `isSignup` only picks which service method name is used, so the
    // two flows are indistinguishable on the wire.
    //
    // `countryCode` rides along on all four, log-in included: omitting it on
    // log-in would make the two requests differ on the wire. The server only
    // reads it when it creates the auth user, so it is inert on a log-in.
    final AuthResult res;
    if (channel == OtpChannel.email) {
      res = isSignup
          ? await _svc.signUpWithEmailOtp(identifier, countryCode: _countryCode)
          : await _svc.signInWithEmailOtp(identifier, countryCode: _countryCode);
    } else {
      res = isSignup
          ? await _svc.signUpWithPhoneOtp(identifier, countryCode: _countryCode)
          : await _svc.signInWithPhoneOtp(identifier, countryCode: _countryCode);
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
  /// moments later and is idempotent.
  Future<bool> verifyOtp(String code) async {
    final id = _pendingIdentifier;
    final channel = _pendingChannel;
    if (id == null || channel == null) {
      _errorKey = AuthMessages.unknown;
      notifyListeners();
      return false;
    }

    if (!configOk) {
      debugPrint('[auth] verify blocked — $configDiagnostics');
      _errorKey = AuthMessages.config;
      notifyListeners();
      return false;
    }

    _beginBusy();
    final res = channel == OtpChannel.email
        ? await _svc.verifyEmailOtp(email: id, token: code.trim())
        : await _svc.verifyPhoneOtp(phoneE164: id, token: code.trim());

    _busy = false;
    if (res.ok) {
      _errorKey = null;

      // (Phase 7) Register this device as the active session.
      //
      // Awaited so that the very next /entitlement refresh already carries the
      // new session id, but its result is deliberately ignored: a failed claim
      // must NOT fail the login. The user has proved who they are; session
      // bookkeeping is the app's problem, not theirs. On failure the
      // entitlement layer simply runs in the backward-compatible no-session
      // mode until the next successful claim.
      await _sessions.claimSession();

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
    await _sessions.clearSession();
    await _svc.signOut();
    _pendingIdentifier = null;
    _pendingChannel = null;
    _errorKey = null;
    _busy = false;
    _set(AuthStatus.signedOut);
  }

  /// (Phase 7) Sign the user out because the SERVER said so — this account is
  /// now in use on another device.
  ///
  /// Static because the caller ([EntitlementProvider]) has no reference to the
  /// live instance; see [_pendingForcedLogoutKey].
  ///
  /// It deliberately does nothing except sign out through the ordinary
  /// Supabase path. That fires `signedOut` on the auth stream, the listening
  /// AuthProvider moves to [AuthStatus.signedOut], and the Phase 2 AuthGate
  /// redirects to the login screen entirely on its own. No screen was touched
  /// to make this work, and there is no navigation code anywhere in this
  /// phase — the gate that already existed does the whole job.
  static Future<void> forceLogoutSuperseded() async {
    _pendingForcedLogoutKey = kSessionSupersededMessageKey;
    final result = await SupabaseService.instance.signOut();
    if (!result.ok) {
      // The local session is cleared by the SDK even when the server call
      // fails, so the gate still redirects. Nothing to recover here.
      debugPrint('[auth] forced sign-out reported a failure; gate still applies');
    }
  }

  void clearError() {
    if (_errorKey == null) return;
    _errorKey = null;
    notifyListeners();
  }

  // ── Profile row ───────────────────────────────────────────────────────────
  //
  // Nothing here writes it. `public.profiles` is created by the
  // `on_auth_user_created` trigger on `auth.users` the moment the auth user is
  // created, so the row exists before this client ever learns it is signed in.
  //
  // This used to be a client insert on first sign-in. It never once succeeded:
  // `authenticated` has no INSERT grant and no INSERT policy on profiles, so
  // every attempt failed with 42501 — swallowed by a catch that only
  // debugPrint'ed, leaving signup looking clean with an empty profiles table.
  // Granting the client INSERT was the wrong fix: an INSERT policy's WITH
  // CHECK can only pin `id`, so the client could still have chosen its own
  // `country_code` and with it the pricing rail.

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
