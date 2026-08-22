import 'package:package_info_plus/package_info_plus.dart';

/// Single source of truth for the app's version string.
///
/// Replaces what used to be three hand-mirrored copies of `'1.0.0'` in
/// about_screen.dart, settings_screen.dart and account_screen.dart, each of
/// which had to be remembered on every version bump and had already drifted
/// (two had silently dropped the build number). The values here come from
/// `PackageInfo.fromPlatform()`, which reads the real versionName /
/// versionCode baked into the APK by Gradle — and those in turn come from
/// pubspec.yaml's `version:` line via `flutter.versionName` /
/// `flutter.versionCode` in android/app/build.gradle. So a pubspec bump now
/// propagates to all three screens on its own.
///
/// The platform channel is queried once per process and the result cached:
/// these labels sit inside `build()` methods that can run many times per
/// second, and the answer cannot change while the process is alive.
///
/// Every accessor is failure-tolerant on purpose. A version label is
/// decorative; it must never be the reason a screen throws. If the channel
/// fails the getters simply report null and callers fall back to rendering
/// their static text without a number.
class AppVersionService {
  AppVersionService._();

  static PackageInfo? _cached;
  static Future<PackageInfo?>? _inFlight;

  /// Completes with the platform package info, or null if it could not be read.
  ///
  /// Concurrent callers share one in-flight request, so three screens built in
  /// the same frame still produce a single platform-channel round trip.
  static Future<PackageInfo?> load() {
    final cached = _cached;
    if (cached != null) return Future<PackageInfo?>.value(cached);
    return _inFlight ??= PackageInfo.fromPlatform().then<PackageInfo?>((info) {
      _cached = info;
      _inFlight = null;
      return info;
    }).catchError((_) {
      // Swallowed deliberately — see the class doc. Clearing the in-flight
      // future lets a later screen retry rather than caching the failure.
      _inFlight = null;
      return null;
    });
  }

  /// The already-resolved info, or null before the first [load] completes.
  ///
  /// Pass this as `initialData` to a [FutureBuilder] so that every visit after
  /// the first paints the real version on the very first frame, with no
  /// placeholder flash.
  static PackageInfo? get cached => _cached;

  /// Marketing version alone, e.g. `1.0.0`.
  static String? versionOf(PackageInfo? info) => info?.version;

  /// Marketing version with build number, e.g. `1.0.0 (1)`.
  static String? versionWithBuildOf(PackageInfo? info) =>
      info == null ? null : '${info.version} (${info.buildNumber})';
}
