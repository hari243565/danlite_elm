import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

/// Danlite ELM — Supabase access layer (Phase 2)
///
/// Everything auth-related that talks to the network lives behind this class.
/// Two rules govern the whole file:
///
///   1. **Tokens never touch the plain-preferences store.** The Supabase SDK
///      persists the session through [SecureLocalStorage] below, which is
///      backed by `flutter_secure_storage` with
///      `encryptedSharedPreferences: true` — an AndroidX
///      EncryptedSharedPreferences file whose master key lives in the
///      hardware-backed Android Keystore. The PKCE code verifier is moved to
///      the same store via [_SecureGotrueAsyncStorage], because the SDK's
///      default for it is the plain, unencrypted preferences XML.
///
///   2. **No raw exception ever reaches the UI.** Every public method returns
///      an [AuthResult] carrying an AppStrings key, so the screens stay fully
///      localised and a network stack trace can never be rendered to a user.
///
/// Account-enumeration note: the "sign up" and "log in" entry points issue the
/// byte-identical request and map every failure to the same generic key, so an
/// attacker cannot tell a registered address from an unregistered one.

/// AppStrings keys returned to the UI. Kept here so the screens never invent
/// their own error copy.
class AuthMessages {
  AuthMessages._();

  static const String otpSent = 'auth_otp_sent';

  /// The app's own `.env` is missing, unbundled or malformed. This is a build
  /// fault, never the user's connection — see [AppConfig].
  static const String config = 'auth_err_config';

  /// A genuine transport failure: no route to the host, DNS failure, timeout.
  /// Nothing else may map here. See [_isTransportFailure].
  static const String network = 'auth_err_network';

  /// The backend rejected the request itself (400/401/403) — a bad anon key or
  /// a disabled provider, not a user error.
  static const String credentials = 'auth_err_credentials';

  static const String otpInvalid = 'auth_err_otp_invalid';
  static const String rateLimited = 'auth_err_rate_limited';
  static const String unknown = 'auth_err_unknown';
}

/// The only thing the UI ever sees. [messageKey] is an AppStrings key that the
/// screen resolves with `context.tr(...)` — never a server string, never an
/// exception message.
@immutable
class AuthResult {
  final bool ok;
  final String? messageKey;
  final bool needsOtp;

  /// The OTP was dispatched (or the address does not exist — indistinguishable
  /// by design). The caller should move the user to the OTP screen.
  const AuthResult.otpSent()
      : ok = true,
        messageKey = AuthMessages.otpSent,
        needsOtp = true;

  const AuthResult.success()
      : ok = true,
        messageKey = null,
        needsOtp = false;

  const AuthResult.failure(String key)
      : ok = false,
        messageKey = key,
        needsOtp = false;
}

/// A [LocalStorage] that keeps the Supabase session in the Android
/// Keystore-backed secure store instead of the SDK default
/// (`SharedPreferencesLocalStorage`, a plaintext XML file that is readable on
/// a rooted device and can be swept up by device backups).
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await accessToken()) != null;

  @override
  Future<String?> accessToken() async {
    try {
      return await _storage.read(key: persistSessionKey);
    } catch (e) {
      // A Keystore entry can become undecryptable after an app restore or a
      // lock-screen credential reset. Treat that as "no session" and clear the
      // dead blob rather than crashing the app on launch.
      debugPrint('[auth] secure read failed, dropping session: $e');
      await removePersistedSession();
      return null;
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _storage.write(key: persistSessionKey, value: persistSessionString);
    } catch (e) {
      debugPrint('[auth] secure write failed: $e');
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _storage.delete(key: persistSessionKey);
    } catch (e) {
      debugPrint('[auth] secure delete failed: $e');
    }
  }
}

/// PKCE code-verifier storage. The SDK defaults this to the unencrypted
/// preferences XML; the verifier is a short-lived secret that completes a
/// login, so it belongs in the same encrypted store as the session.
class _SecureGotrueAsyncStorage extends GotrueAsyncStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<String?> getItem({required String key}) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('[auth] pkce read failed: $e');
      return null;
    }
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('[auth] pkce write failed: $e');
    }
  }

  @override
  Future<void> removeItem({required String key}) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('[auth] pkce delete failed: $e');
    }
  }
}

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  bool _configured = false;

  /// False when `.env` is missing or empty. Phase 2 adds no paywall, so an
  /// unconfigured build must still run the diagnostics app exactly as before
  /// rather than crash on launch — see [AuthGate], which sends the user
  /// straight to /home in that case.
  ///
  /// Phase 8 (the paywall) MUST invert this: once entitlement gates the app,
  /// a missing backend has to fail closed, not open.
  bool get isConfigured => _configured;

  /// Loads `.env`, then boots Supabase with secure-storage-backed session
  /// persistence. Call once, after `WidgetsFlutterBinding.ensureInitialized()`
  /// and before `runApp`. Never throws: a broken backend config must not take
  /// the existing app down.
  Future<void> init() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (e) {
      // The asset is missing from the bundle, or unparseable. AppConfig reports
      // this as ConfigStatus.missing rather than throwing, and the auth screens
      // paint the diagnostic strip — so carry on and let that path speak.
      debugPrint('[auth] .env not loadable: ${e.runtimeType}');
      _configured = false;
      return;
    }

    // Sanitisation (quotes, whitespace, trailing slash) and structural checks
    // both live in AppConfig, so the client is never built from a value that
    // this app would then have to blame on the user's internet.
    final status = AppConfig.validate();
    if (status != ConfigStatus.ok) {
      debugPrint('[auth] config unusable ($status) — '
          '${AppConfig.describeForDiagnostics()}');
      _configured = false;
      return;
    }

    final url = AppConfig.supabaseUrl;
    final anonKey = AppConfig.supabaseAnonKey;
    final parsed = Uri.parse(url);

    try {
      await Supabase.initialize(
        url: url,
        // Same anon/publishable key from the dashboard. `anonKey:` is the
        // deprecated spelling of this parameter in supabase_flutter 2.17.
        publishableKey: anonKey,
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          localStorage: SecureLocalStorage(
            // Same key shape the SDK uses by default, so the storage swap is
            // the only thing that changes.
            persistSessionKey: 'sb-${parsed.host.split('.').first}-auth-token',
          ),
          pkceAsyncStorage: _SecureGotrueAsyncStorage(),
          // The app has no deep-link auth callback; leaving the URI observer
          // off keeps an unnecessary entry point closed.
          detectSessionInUri: false,
        ),
        debug: kDebugMode,
      );
      _configured = true;
    } catch (e) {
      debugPrint('[auth] Supabase.initialize failed: $e');
      _configured = false;
    }
  }

  GoTrueClient get _auth => Supabase.instance.client.auth;

  SupabaseClient get client => Supabase.instance.client;

  Session? get currentSession => _configured ? _auth.currentSession : null;

  User? get currentUser => _configured ? _auth.currentUser : null;

  Stream<AuthState> get onAuthStateChange =>
      _configured ? _auth.onAuthStateChange : const Stream<AuthState>.empty();

  /// Run before every auth request. Returns the failure to hand straight back
  /// to the UI, or null when it is safe to hit the network.
  ///
  /// A misconfigured app must say so instead of attempting a call that can only
  /// fail at the socket and then be mistaken for the user's connection. The
  /// config is re-validated here rather than trusting [_configured] alone, so
  /// the strip on screen and the message in the banner can never disagree.
  AuthResult? _configGuard() {
    if (!_configured || AppConfig.validate() != ConfigStatus.ok) {
      debugPrint('[auth] request blocked — '
          '${AppConfig.describeForDiagnostics()}');
      return const AuthResult.failure(AuthMessages.config);
    }
    return null;
  }

  // ── OTP dispatch ──────────────────────────────────────────────────────────
  // Sign-up and log-in are deliberately the same request. With passwordless
  // OTP there is no observable difference between "created" and "logged in",
  // which is precisely what stops address enumeration.
  //
  // That is why [_signupMetadata] is attached to the log-in entry points too:
  // sending it only on sign-up would make the two requests distinguishable on
  // the wire and hand back the enumeration oracle. It costs nothing on log-in —
  // GoTrue applies `data` when it creates the user, and `handle_new_user` fires
  // on INSERT only, so an existing account's profile is never touched by it.

  Future<AuthResult> signUpWithEmailOtp(String email, {String? countryCode}) =>
      _sendEmailOtp(email, countryCode: countryCode);

  Future<AuthResult> signInWithEmailOtp(String email, {String? countryCode}) =>
      _sendEmailOtp(email, countryCode: countryCode);

  /// Signup metadata for the `data:` payload of [GoTrueClient.signInWithOtp].
  ///
  /// GoTrue writes this to `auth.users.raw_user_meta_data` when the row is
  /// created, which is the only channel by which the client can tell the server
  /// anything at signup time. The `on_auth_user_created` trigger
  /// (`handle_new_user`) reads exactly these two keys off that column when it
  /// creates `public.profiles`.
  ///
  /// It is metadata, not authority: the trigger re-validates both keys and the
  /// client has no insert or update path to `profiles.country_code` by any
  /// other route, so a patched APK sending `country_code: 'US'` only changes
  /// what the server was going to derive anyway — it never rewrites an existing
  /// profile. Phase 3 should treat this as a hint and reconcile the pricing rail
  /// against the payment gateway's own country at checkout.
  ///
  /// [countryCode] is omitted rather than guessed when absent or malformed, so
  /// the row falls back to the column default ('IN') instead of carrying a
  /// value this layer invented.
  Map<String, dynamic> _signupMetadata(String? countryCode) {
    final data = <String, dynamic>{'signup_platform': 'android'};
    final code = countryCode?.trim().toUpperCase();
    if (code != null && RegExp(r'^[A-Z]{2}$').hasMatch(code)) {
      data['country_code'] = code;
    }
    return data;
  }

  Future<AuthResult> _sendEmailOtp(String email, {String? countryCode}) async {
    final blocked = _configGuard();
    if (blocked != null) return blocked;
    try {
      await _auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
        data: _signupMetadata(countryCode),
      );
      return const AuthResult.otpSent();
    } catch (e) {
      return AuthResult.failure(_sendErrorKey(e));
    }
  }

  // ── OTP verification ──────────────────────────────────────────────────────

  Future<AuthResult> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final blocked = _configGuard();
    if (blocked != null) return blocked;
    try {
      final res = await _auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );
      return res.session != null
          ? const AuthResult.success()
          : const AuthResult.failure(AuthMessages.otpInvalid);
    } catch (e) {
      return AuthResult.failure(_verifyErrorKey(e));
    }
  }

  Future<AuthResult> signOut() async {
    if (!_configured) return const AuthResult.success();
    try {
      await _auth.signOut();
      return const AuthResult.success();
    } catch (e) {
      // The local session is dropped by the SDK even when the network call
      // fails, so the user is signed out either way.
      debugPrint('[auth] signOut: $e');
      return const AuthResult.success();
    }
  }

  // ── Error translation ─────────────────────────────────────────────────────
  //
  // Read this before touching anything below.
  //
  // gotrue-dart funnels two completely unrelated failures into the *same*
  // exception type, [AuthRetryableFetchException] — "retryable" describes the
  // SDK's own retry policy, not the cause:
  //
  //   * `fetch.dart` throws it with **no statusCode** when the HTTP call itself
  //     threw — a real transport failure (DNS, no route, TLS, timeout).
  //   * `fetch.dart` throws it **with a statusCode** for every response of 500
  //     or above — a server-side fault, on a connection that plainly worked.
  //
  // Treating both as "no connection" is what made a working 5G phone report an
  // internet problem: Supabase returns 500 when GoTrue's *mail sender* fails,
  // so a perfectly healthy device was told to check its internet. The presence
  // of `statusCode` is the discriminator, and it is the only thing separating
  // those two branches: no statusCode is [AuthMessages.network], a statusCode
  // falls through to [AuthMessages.unknown] at the end of [_sendErrorKey].

  /// A genuine transport failure — nothing reached the server. This is the only
  /// condition allowed to produce [AuthMessages.network].
  bool _isTransportFailure(Object e) {
    if (e is SocketException || e is TimeoutException || e is HttpException) {
      return true;
    }
    // No statusCode => gotrue never got a response at all.
    return e is AuthRetryableFetchException && e.statusCode == null;
  }

  bool _isRateLimited(Object e) =>
      e is AuthException &&
      // Covers over_email_send_rate_limit and the generic
      // over_request_rate_limit.
      (e.statusCode == '429' || (e.code ?? '').contains('rate_limit'));

  /// 400/401/403 — the request itself was refused. A bad or revoked anon key, a
  /// disabled provider, a malformed payload. Configuration, not connectivity.
  bool _isRejected(Object e) =>
      e is AuthException &&
      (e.statusCode == '400' ||
          e.statusCode == '401' ||
          e.statusCode == '403');

  /// Codes that would reveal whether an identifier is already registered. They
  /// must never reach a distinct message — see [_sendErrorKey].
  static const Set<String> _enumerationCodes = {
    'email_exists',
    'phone_exists',
    'user_already_exists',
  };

  /// Send path. Sign-up and log-in share this classifier and classify purely on
  /// the shape of the exception, never on which entry point was called, so the
  /// two flows return byte-identical copy. Any code that would betray an
  /// existing account is folded into the generic bucket first.
  String _sendErrorKey(Object e) {
    _log('send', e);

    if (e is AuthException && _enumerationCodes.contains(e.code)) {
      return AuthMessages.unknown;
    }

    if (AppConfig.validate() != ConfigStatus.ok) return AuthMessages.config;
    if (_isTransportFailure(e)) return AuthMessages.network;
    if (_isRateLimited(e)) return AuthMessages.rateLimited;
    if (_isRejected(e)) return AuthMessages.credentials;

    // Everything left over, including a 5xx. That one is almost always GoTrue's
    // mail sender refusing the send; it is a backend problem, so the honest
    // copy is the generic one — never "no connection".
    return AuthMessages.unknown;
  }

  /// Verify path: the identifier is already known to the caller at this point,
  /// so telling the user their code was wrong or expired leaks nothing.
  String _verifyErrorKey(Object e) {
    _log('verify', e);

    if (AppConfig.validate() != ConfigStatus.ok) return AuthMessages.config;
    if (_isTransportFailure(e)) return AuthMessages.network;
    if (_isRateLimited(e)) return AuthMessages.rateLimited;

    // On this endpoint a 4xx means the code itself did not work — wrong or
    // expired, which are not worth distinguishing to the user. This is checked
    // before [_isRejected] precisely because a bad OTP also arrives as a 400,
    // and "that code is wrong" is the far more useful reading here.
    if (e is AuthException && (_isRejected(e) || e.code == 'otp_expired')) {
      return AuthMessages.otpInvalid;
    }
    return AuthMessages.unknown;
  }

  /// Type, status and GoTrue error code only. The message body can echo a
  /// server string or an address, so it never goes to the log.
  void _log(String stage, Object e) {
    if (e is AuthException) {
      debugPrint('[auth] $stage failed: ${e.runtimeType} '
          'status=${e.statusCode ?? "-"} code=${e.code ?? "-"}');
    } else {
      debugPrint('[auth] $stage failed: ${e.runtimeType}');
    }
  }
}
