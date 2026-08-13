import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Danlite ELM — backend configuration guard (Phase 2)
///
/// Everything the app needs from `.env` is read through here, exactly once per
/// call site, and always after sanitisation. The point of this class is that a
/// *configuration* fault can never again be reported to the user as a
/// *network* fault: [validate] answers "is the backend config usable" as a
/// plain, cheap, synchronous question, and [describeForDiagnostics] renders
/// the answer as a line that is safe to paint on screen in a release build.
///
/// Nothing here logs, returns or exposes a secret. The only facts that leave
/// this class are presence, structural shape, and the anon key's length.

/// Outcome of checking the backend configuration shipped in `.env`.
enum ConfigStatus {
  /// Both values are present and structurally sound.
  ok,

  /// One or both values are absent or empty — including the case where the
  /// `.env` asset never loaded at all, which is what happens if the file is
  /// not bundled into the APK.
  missing,

  /// Present, but unusable: the URL will not parse, is not https, is not a
  /// Supabase host — or the anon key is not JWT-shaped.
  malformed,
}

class AppConfig {
  AppConfig._();

  static const String _urlVar = 'SUPABASE_URL';
  static const String _anonKeyVar = 'SUPABASE_ANON_KEY';

  /// Three dot-separated base64url segments.
  ///
  /// Caveat for a future maintainer: Supabase's newer *publishable* keys
  /// (`sb_publishable_…`) are deliberately NOT JWTs, so swapping the project
  /// over to one would make this check report [ConfigStatus.malformed] and the
  /// app would refuse to sign anyone in. If that migration ever happens, this
  /// regex is the one line that has to change with it.
  static final RegExp _jwtShape =
      RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$');

  /// True once `dotenv.load` has succeeded. Read it before touching
  /// [dotenv.env], which throws `NotInitializedError` rather than returning an
  /// empty map when the asset never loaded.
  static bool get envLoaded => dotenv.isInitialized;

  static String get supabaseUrl => _sanitiseUrl(_read(_urlVar));

  static String get supabaseAnonKey => _sanitise(_read(_anonKeyVar));

  // ── Reading and sanitisation ──────────────────────────────────────────────

  /// Never throws. A missing `.env` asset, a missing key and an empty value
  /// all collapse to the empty string, which [validate] reports as
  /// [ConfigStatus.missing].
  static String _read(String name) {
    if (!dotenv.isInitialized) return '';
    try {
      return dotenv.env[name] ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Trims, then strips one surrounding pair of matching quotes. A value
  /// written as `SUPABASE_URL="https://…"` in a shell-habit `.env` would
  /// otherwise parse as a relative path with an empty host.
  static String _sanitise(String value) {
    var s = value.trim();
    if (s.length >= 2) {
      final first = s[0];
      final last = s[s.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        s = s.substring(1, s.length - 1).trim();
      }
    }
    return s;
  }

  /// As [_sanitise], plus every trailing `/`. The Supabase client appends its
  /// own `/auth/v1/…` path, so a trailing slash yields a double-slash URL that
  /// the gateway does not route.
  static String _sanitiseUrl(String value) {
    var s = _sanitise(value);
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  // ── Validation ────────────────────────────────────────────────────────────

  /// Cheap, synchronous, and safe to call on every build and before every auth
  /// request. Never throws.
  static ConfigStatus validate() {
    final url = supabaseUrl;
    final key = supabaseAnonKey;

    if (url.isEmpty || key.isEmpty) return ConfigStatus.missing;
    if (!_urlIsSound(url)) return ConfigStatus.malformed;
    if (!_keyIsSound(key)) return ConfigStatus.malformed;
    return ConfigStatus.ok;
  }

  static bool get isReady => validate() == ConfigStatus.ok;

  /// Caveat for a future maintainer: the `.supabase.co` test is what makes a
  /// typo'd host detectable, but it also rejects a self-hosted GoTrue or a
  /// custom auth domain. Widen it here — not at the call sites — if the
  /// project ever moves off the managed host.
  static bool _urlIsSound(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    return uri.host.endsWith('.supabase.co');
  }

  static bool _keyIsSound(String key) => _jwtShape.hasMatch(key);

  // ── Safe diagnostics ──────────────────────────────────────────────────────

  /// A one-line, screenshot-able summary for the owner. Reports presence,
  /// structural shape and the anon key's length — never any part of either
  /// value, and never the host itself.
  ///
  /// Examples:
  ///   `url: set (host ok) · key: set (jwt shape ok, 208 chars)`
  ///   `env: NOT LOADED · url: MISSING · key: MISSING`
  static String describeForDiagnostics() {
    final parts = <String>[];
    if (!envLoaded) parts.add('env: NOT LOADED');

    final url = supabaseUrl;
    parts.add(url.isEmpty
        ? 'url: MISSING'
        : _urlIsSound(url)
            ? 'url: set (host ok)'
            : 'url: set (BAD FORM)');

    final key = supabaseAnonKey;
    parts.add(key.isEmpty
        ? 'key: MISSING'
        : _keyIsSound(key)
            ? 'key: set (jwt shape ok, ${key.length} chars)'
            : 'key: set (BAD SHAPE, ${key.length} chars)');

    return parts.join(' · ');
  }
}
