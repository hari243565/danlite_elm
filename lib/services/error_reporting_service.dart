import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Danlite ELM — error reporting (Phase 9)
///
/// A deliberately thin wrapper over Sentry. Two rules govern everything here:
///
/// 1. **It never changes behaviour.** Every method is fire-and-forget and
///    swallows its own failures. Call sites report *that* something happened
///    after they have already decided *what to do* about it; nothing in this
///    file is allowed to influence that decision. If Sentry is misconfigured,
///    unreachable, or disabled, the app behaves exactly as it did before this
///    file existed.
///
/// 2. **It never carries PII.** [SentryOptions.sendDefaultPii] stays `false`,
///    HTTP request bodies are never captured, and the only structured data this
///    class forwards is the small `context` map its callers build by hand —
///    which is scrubbed by [_scrub] before it leaves the device.
///
/// The DSN is read from the same gitignored `.env` asset that already carries
/// `SUPABASE_URL` and `SUPABASE_ANON_KEY` (see `AppConfig`). A Sentry DSN is a
/// client-side ingest key, not a secret — it is safe to ship inside the APK, in
/// the same way the Supabase anon key is — but it is environment-specific, so
/// it belongs in `.env` rather than in source.
///
/// **If `SENTRY_DSN` is absent or empty, reporting is silently disabled and the
/// app runs completely unchanged.** That is the intended state for a developer
/// checkout, and it is what makes this integration safe to ship before the DSN
/// is provisioned.
class ErrorReportingService {
  ErrorReportingService._();

  static const String _dsnVar = 'SENTRY_DSN';

  /// Fraction of transactions sampled for performance tracing.
  ///
  /// 5%. Chosen low on purpose: this integration exists to catch *errors*, not
  /// to profile a diagnostics app that spends most of its life idle on a
  /// Bluetooth read loop. Sentry's free tier meters performance units on the
  /// same allowance as errors, and a tracing rate high enough to be
  /// statistically interesting would spend that allowance on data nobody reads
  /// — crowding out the error events that are the whole point. 5% is still
  /// enough to show a trend if a screen becomes pathologically slow.
  static const double _tracesSampleRate = 0.05;

  static bool _enabled = false;

  /// True once [init] has run and a usable DSN was found.
  static bool get isEnabled => _enabled;

  /// Reads the DSN defensively, exactly as `AppConfig` does: a missing `.env`
  /// asset, a missing key and an empty value all collapse to the empty string.
  /// `dotenv.env` throws rather than returning an empty map when the asset
  /// never loaded, so the `isInitialized` guard is load-bearing.
  static String get _dsn {
    if (!dotenv.isInitialized) return '';
    try {
      return (dotenv.env[_dsnVar] ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  /// Initialises Sentry and then runs [appRunner].
  ///
  /// [appRunner] is invoked exactly once whether or not Sentry starts, so the
  /// app launches identically in both cases. A DSN that is absent, or an SDK
  /// that throws on start-up, must never be the reason the app fails to boot.
  static Future<void> init({required VoidCallback appRunner}) async {
    final dsn = _dsn;

    if (dsn.isEmpty) {
      debugPrint('[sentry] SENTRY_DSN not set — error reporting disabled');
      appRunner();
      return;
    }

    try {
      await SentryFlutter.init(
        (options) {
          options.dsn = dsn;

          // ── PII controls ────────────────────────────────────────────────
          // Never attach the user's IP address, device identifiers, cookies,
          // or request headers to an event.
          options.sendDefaultPii = false;

          // The separate body-capture control. This is NOT implied by
          // `sendDefaultPii` — it is an independent setting, and it is the one
          // that decides whether an OTP request's payload (an email address or
          // a phone number, in this app) could ride along on a breadcrumb.
          // `never` is the SDK default; it is set explicitly so that a future
          // reader can see it was a decision rather than an omission.
          options.maxRequestBodySize = MaxRequestBodySize.never;

          options.tracesSampleRate = _tracesSampleRate;
          options.environment = kReleaseMode ? 'release' : 'debug';
          options.debug = false;
        },
        appRunner: appRunner,
      );
      _enabled = true;
      debugPrint('[sentry] error reporting enabled');
    } catch (e) {
      // Starting Sentry must never stop the app starting.
      debugPrint('[sentry] init failed (${e.runtimeType}) — reporting disabled');
      _enabled = false;
      appRunner();
    }
  }

  /// Reports an error that the caller has **already handled**.
  ///
  /// Fire-and-forget by design: it returns immediately, never throws, and never
  /// reports a result. A call site must be able to add or remove a call to this
  /// method without any other line of that call site changing.
  ///
  /// [context] is a small map of non-PII facts that make the event diagnosable
  /// — which classification was chosen, which screen, which status code. Do not
  /// put an email address, a phone number, an OTP or a token in it; [_scrub]
  /// is a backstop, not a licence.
  static void reportError(
    Object error,
    StackTrace? stackTrace, {
    Map<String, String>? context,
  }) {
    if (!_enabled) return;
    try {
      Sentry.captureException(
        error,
        stackTrace: stackTrace,
        withScope: (scope) {
          if (context != null && context.isNotEmpty) {
            scope.setContexts('danlite', _scrub(context));
          }
        },
      );
    } catch (_) {
      // Reporting an error must never itself raise one.
    }
  }

  /// Backstop redaction for anything that looks like an email address or a
  /// phone number, in case a caller ever passes one by accident.
  static Map<String, String> _scrub(Map<String, String> context) {
    return context.map((k, v) => MapEntry(k, _redact(v)));
  }

  static final RegExp _emailLike = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');
  static final RegExp _phoneLike = RegExp(r'\+?\d[\d\s-]{7,}\d');

  static String _redact(String value) => value
      .replaceAll(_emailLike, '[email]')
      .replaceAll(_phoneLike, '[phone]');
}
