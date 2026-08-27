import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_config.dart';
import '../services/error_reporting_service.dart';
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

  /// The email address the pending OTP went to.
  String? _pendingIdentifier;
  String? get pendingIdentifier => _pendingIdentifier;

  /// ISO-3166 alpha-2, e.g. 'IN'. Chosen on the sign-up screen. It decides
  /// pricing only (₹109 India vs $1.10 international) and has never had any
  /// bearing on how a user proves their identity.
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

  /// The name and contact phone typed on the SIGN-UP screen, held in memory
  /// only until the account they belong to has actually been verified.
  ///
  /// Staged rather than sent with the OTP request, deliberately.
  /// [SupabaseService] attaches its signup metadata to the log-in path too, so
  /// that a sign-up and a log-in are byte-identical on the wire and cannot be
  /// used to tell a registered address from an unregistered one — and the
  /// log-in screen has no name field whose value could be put in it. These are
  /// written afterwards instead, by an authenticated update on the user's own
  /// profile row through the grant and policy Phase 1 already created.
  ///
  /// The log-in path never sets them and [login] actively clears them, so a
  /// returning customer's flow writes nothing and is unchanged in every
  /// respect.
  String? _pendingFirstName;
  String? _pendingLastName;
  String? _pendingPhone;

  /// Called by the sign-up screen immediately before [startSignup].
  ///
  /// [phone] is contact data. It is never verified, never messaged, and never
  /// used to identify anybody — no OTP, SMS or notification of any kind is
  /// sent to it anywhere in this app.
  void stageSignupDetails({
    required String firstName,
    String? lastName,
    String? phone,
  }) {
    _pendingFirstName = firstName;
    _pendingLastName = lastName;
    _pendingPhone = phone;
  }

  void _clearStagedSignupDetails() {
    _pendingFirstName = null;
    _pendingLastName = null;
    _pendingPhone = null;
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
          _set(AuthStatus.signedIn);
        } else if (_status != AuthStatus.awaitingOtp) {
          _set(AuthStatus.signedOut);
        }
      case AuthChangeEvent.signedOut:
        _pendingIdentifier = null;
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

  /// Signs up by email OTP — the only way an account is ever created. The
  /// country selector is unrelated: it is written through [countryCode] by the
  /// screen and only affects pricing.
  Future<bool> startSignup({required String identifier}) =>
      _dispatch(identifier.trim(), isSignup: true);

  /// Logs in by email OTP, same identifier rules as [startSignup].
  ///
  /// Clearing the staged sign-up details is the one thing this does that
  /// [startSignup] does not. Someone who opened the sign-up screen, typed a
  /// name, and then went to log in instead is logging into an account that
  /// already exists — that name was for the account this flow is no longer
  /// creating, and must not land on top of the real one. Note that [resendOtp]
  /// calls [_dispatch] directly and therefore does NOT clear them: a resend
  /// during sign-up is still that same sign-up.
  Future<bool> login({required String identifier}) {
    _clearStagedSignupDetails();
    return _dispatch(identifier.trim(), isSignup: false);
  }

  Future<bool> _dispatch(
    String identifier, {
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
    // `countryCode` rides along on both, log-in included: omitting it on
    // log-in would make the two requests differ on the wire. The server only
    // reads it when it creates the auth user, so it is inert on a log-in.
    final AuthResult res = isSignup
        ? await _svc.signUpWithEmailOtp(identifier, countryCode: _countryCode)
        : await _svc.signInWithEmailOtp(identifier, countryCode: _countryCode);

    if (res.ok && res.needsOtp) {
      _pendingIdentifier = identifier;
      _errorKey = null;
      _busy = false;
      _set(AuthStatus.awaitingOtp);
      return true;
    }

    _errorKey = res.messageKey;
    // Report-only (Phase 9). The classification in SupabaseService has already
    // chosen `res.messageKey`, and `_errorKey` is already assigned from it
    // above. This call observes that decision; it cannot alter it, and removing
    // it would leave every surrounding line identical.
    if (!res.ok) {
      ErrorReportingService.reportError(
        'auth dispatch failed',
        StackTrace.current,
        context: {
          'stage': isSignup ? 'signup' : 'login',
          'classification': res.messageKey ?? 'none',
        },
      );
    }
    _busy = false;
    notifyListeners();
    return false;
  }

  /// Re-sends the code to the pending identifier. The screen owns the cooldown.
  Future<bool> resendOtp() async {
    final id = _pendingIdentifier;
    if (id == null) return false;
    return _dispatch(id, isSignup: false);
  }

  /// Verifies the 6-digit code. On success [status] becomes
  /// [AuthStatus.signedIn] immediately; the SDK's own `signedIn` event follows
  /// moments later and is idempotent.
  Future<bool> verifyOtp(String code) async {
    final id = _pendingIdentifier;
    if (id == null) {
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
    final res = await _svc.verifyEmailOtp(email: id, token: code.trim());

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

      // Persist whatever the sign-up screen collected, on exactly the same
      // terms as the claim above: it cannot fail this login, and it reports
      // its own problems. Awaited rather than fired and forgotten because the
      // caller navigates straight back to the gate and the account surfaces
      // that read these columns rebuild moments later. On a log-in nothing is
      // staged, so this returns without making a request.
      await _saveStagedSignupDetails();

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
    // Report-only (Phase 9) — see the note in [_dispatch].
    if (!res.ok) {
      ErrorReportingService.reportError(
        'otp verification failed',
        StackTrace.current,
        context: {
          'classification': res.messageKey ?? 'none',
        },
      );
    }
    notifyListeners();
    return false;
  }

  /// Writes the staged sign-up details, then forgets them either way.
  ///
  /// The result is deliberately not returned and cannot change the outcome of
  /// [verifyOtp]. Somebody who has just proved who they are is signed in
  /// whether or not their name reached the database.
  Future<void> _saveStagedSignupDetails() async {
    if (_pendingFirstName == null &&
        _pendingLastName == null &&
        _pendingPhone == null) {
      return;
    }

    final ok = await _svc.saveProfileDetails(
      firstName: _pendingFirstName,
      lastName: _pendingLastName,
      phone: _pendingPhone,
    );

    // Cleared unconditionally, success or failure. Keeping a customer's name
    // and phone number alive in memory past the one moment they were needed is
    // how they end up somewhere they were never meant to be.
    _clearStagedSignupDetails();

    if (!ok) {
      debugPrint('[auth] signup details were not saved');
      // Report-only (Phase 9) — see the note in [_dispatch]. Note what is NOT
      // in the context map: no name, no phone number, no email address. The
      // event records that a write failed and nothing at all about who it was
      // for. See ErrorReportingService's PII rule.
      ErrorReportingService.reportError(
        'signup profile details write failed',
        StackTrace.current,
        context: const {'stage': 'signup_details'},
      );
    }
  }

  Future<void> logout() async {
    _beginBusy();
    _clearStagedSignupDetails();
    await _sessions.clearSession();
    await _svc.signOut();
    _pendingIdentifier = null;
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
      // Report-only (Phase 9). The existing behaviour — swallow, leave
      // `_deviceFingerprint` null, carry on — is unchanged.
      ErrorReportingService.reportError(
        e,
        StackTrace.current,
        context: {'stage': 'device_fingerprint'},
      );
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
