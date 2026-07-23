import 'package:flutter/widgets.dart';

/// Danlite ELM — Framework Locale Fallback
///
/// `SettingsProvider.supportedLanguages` lists 23 app languages, but Flutter's
/// bundled `flutter_localizations` package (Material/Widgets/Cupertino) only
/// ships translated framework chrome strings (e.g. "OK", drawer semantics,
/// date-picker labels) for a subset of them. Selecting one of the other
/// locales directly on `MaterialApp.locale` leaves `MaterialLocalizations`
/// (and friends) unresolved, crashing widgets like `DrawerController` with
/// "No MaterialLocalizations found".
///
/// Our own in-app strings (see `AppStrings`/`context.tr()`) are unaffected —
/// they are keyed off `SettingsProvider.locale` directly and already fall
/// back to English for missing keys. This file only resolves the *framework*
/// locale so Material/Widgets/Cupertino delegates always have something to
/// load, for any locale we support today or add in the future.
///
/// Verified against the Flutter SDK's generated locale tables
/// (`generated_material_localizations.dart`,
/// `generated_widgets_localizations.dart`,
/// `generated_cupertino_localizations.dart`), which all expose the same set
/// of supported language codes.
const Set<String> kFrameworkSupportedLanguageCodes = {
  'en', 'hi', 'bn', 'te', 'mr', 'ta', 'gu', 'kn', 'ml', 'or', 'pa', 'as', 'ur', 'ne',
};

/// Per-language fallback for app locales that Flutter's framework
/// localizations don't ship. RTL script languages fall back to Urdu (also
/// framework-supported and RTL) to preserve correct text direction; the rest
/// fall back to Hindi.
const Map<String, String> kFrameworkLocaleFallback = {
  'sa': 'hi', 'kok': 'hi', 'mni': 'hi', 'brx': 'hi', 'doi': 'hi', 'mai': 'hi', 'sat': 'hi',
  'ks': 'ur', 'sd': 'ur',
};

/// The concrete [Locale] set to pass as `MaterialApp.supportedLocales` — the
/// locales Flutter's own Material/Widgets/Cupertino delegates can actually
/// load. The full 23-language app picker list stays independent of this.
final List<Locale> kFrameworkSupportedLocales =
    kFrameworkSupportedLanguageCodes.map(Locale.new).toList(growable: false);

/// Resolves any requested app locale to one Flutter's framework
/// localizations natively support, defaulting unknown/future codes to
/// English so a missing delegate can never crash the widget tree.
Locale resolveFrameworkLocale(Locale requested) {
  if (kFrameworkSupportedLanguageCodes.contains(requested.languageCode)) {
    return requested;
  }
  final fallbackCode = kFrameworkLocaleFallback[requested.languageCode] ?? 'en';
  return Locale(fallbackCode);
}
