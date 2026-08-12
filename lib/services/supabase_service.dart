import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  static const String generic = 'auth_err_generic';
  static const String network = 'auth_err_network';
  static const String rateLimited = 'auth_err_rate_limited';
  static const String invalidOtp = 'auth_err_invalid_otp';
  static const String notConfigured = 'auth_err_not_configured';
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
      debugPrint('[auth] .env not loadable: $e');
      _configured = false;
      return;
    }

    final url = dotenv.env['SUPABASE_URL']?.trim() ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';

    final parsed = Uri.tryParse(url);
    if (url.isEmpty || anonKey.isEmpty || parsed == null || parsed.host.isEmpty) {
      debugPrint('[auth] SUPABASE_URL / SUPABASE_ANON_KEY not set — auth disabled.');
      _configured = false;
      return;
    }

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

  // ── OTP dispatch ──────────────────────────────────────────────────────────
  // Sign-up and log-in are deliberately the same request. With passwordless
  // OTP there is no observable difference between "created" and "logged in",
  // which is precisely what stops address enumeration.

  Future<AuthResult> signUpWithEmailOtp(String email) => _sendEmailOtp(email);

  Future<AuthResult> signInWithEmailOtp(String email) => _sendEmailOtp(email);

  Future<AuthResult> signUpWithPhoneOtp(String phoneE164) =>
      _sendPhoneOtp(phoneE164);

  Future<AuthResult> signInWithPhoneOtp(String phoneE164) =>
      _sendPhoneOtp(phoneE164);

  Future<AuthResult> _sendEmailOtp(String email) async {
    if (!_configured) return const AuthResult.failure(AuthMessages.notConfigured);
    try {
      await _auth.signInWithOtp(email: email, shouldCreateUser: true);
      return const AuthResult.otpSent();
    } catch (e) {
      return AuthResult.failure(_sendErrorKey(e));
    }
  }

  Future<AuthResult> _sendPhoneOtp(String phoneE164) async {
    if (!_configured) return const AuthResult.failure(AuthMessages.notConfigured);
    try {
      await _auth.signInWithOtp(phone: phoneE164, shouldCreateUser: true);
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
    if (!_configured) return const AuthResult.failure(AuthMessages.notConfigured);
    try {
      final res = await _auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.email,
      );
      return res.session != null
          ? const AuthResult.success()
          : const AuthResult.failure(AuthMessages.invalidOtp);
    } catch (e) {
      return AuthResult.failure(_verifyErrorKey(e));
    }
  }

  Future<AuthResult> verifyPhoneOtp({
    required String phoneE164,
    required String token,
  }) async {
    if (!_configured) return const AuthResult.failure(AuthMessages.notConfigured);
    try {
      final res = await _auth.verifyOTP(
        phone: phoneE164,
        token: token,
        type: OtpType.sms,
      );
      return res.session != null
          ? const AuthResult.success()
          : const AuthResult.failure(AuthMessages.invalidOtp);
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

  bool _isNetwork(Object e) =>
      e is AuthRetryableFetchException ||
      e is SocketException ||
      e is TimeoutException ||
      e is HttpException;

  bool _isRateLimited(Object e) =>
      e is AuthException &&
      // Covers over_email_send_rate_limit, over_sms_send_rate_limit and the
      // generic over_request_rate_limit.
      (e.statusCode == '429' || (e.code ?? '').contains('rate_limit'));

  /// Send path: everything that is not a transport failure or an explicit rate
  /// limit collapses to one generic key. "User exists" and "user does not
  /// exist" must be indistinguishable here.
  String _sendErrorKey(Object e) {
    debugPrint('[auth] send failed: ${e.runtimeType}');
    if (_isNetwork(e)) return AuthMessages.network;
    if (_isRateLimited(e)) return AuthMessages.rateLimited;
    return AuthMessages.generic;
  }

  /// Verify path: the identifier is already known to the caller at this point,
  /// so telling the user their code was wrong or expired leaks nothing.
  String _verifyErrorKey(Object e) {
    debugPrint('[auth] verify failed: ${e.runtimeType}');
    if (_isNetwork(e)) return AuthMessages.network;
    if (_isRateLimited(e)) return AuthMessages.rateLimited;
    // Every remaining GoTrue rejection on this endpoint means the same thing
    // to the user: that code did not work. Expired and wrong are not worth
    // distinguishing, and doing so would only add copy to translate.
    if (e is AuthException) return AuthMessages.invalidOtp;
    return AuthMessages.generic;
  }
}
