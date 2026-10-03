/// Danlite ELM — DTC Localization Service
///
/// Central, langCode-aware lookup layer that maps a raw fault code
/// (e.g. `P0122`, extracted by ObdService) to the strings shown on a fault
/// card:
///   • the SAE J2012 category   (Powertrain / Chassis / Body / Network)
///   • a localized category header for that category
///   • a localized human-readable description
///
/// ── Engine descriptions ────────────────────────────────────────────────
/// This service no longer holds any engine description text. The borrowed
/// Torque-Pro text (a translations asset and a corrupted Hindi dictionary,
/// neither with a recorded licence) was deleted in Phase 4C; engine meanings
/// now come from the knowledge store (`lib/knowledge/`) and the 31-entry
/// `DtcDatabase` (`legacy_text.dart`).
///
/// Manufacturer-defined codes ([isManufacturerDefined]) are never resolved
/// from any of these generic tables: their meaning depends on the maker.
///
/// ── Scale protection (10-language matrix) ────────────────────────────────
/// Translating thousands of DTC *descriptions* into every language exceeds
/// practical limits, so only Hindi currently ships a full description
/// dictionary. For every other language the description falls back to the
/// English master (already resolved into `DtcCode.description`), while the
/// *category header* — a small, closed vocabulary — is localized for all ten
/// supported languages in [_categoryHeaders]. Adding a new language's full
/// description set later is a drop-in: generate its map the same way Hindi
/// was and branch on it in [description].
library;

import '../constants/chassis_dtc_dictionary.dart';
import '../constants/chassis_dtc_dictionary_hi.dart';
import '../constants/dtc_ranges.dart';

export '../constants/dtc_ranges.dart' show isManufacturerDefined;

/// The four SAE J2012 diagnostic categories, keyed by the first character of
/// the code. This mirrors the bitmask decode already done in the parser and
/// is display-only — it never feeds protocol logic.
enum DtcCategory { powertrain, chassis, body, network, unknown }

// isManufacturerDefined and the subsystem grouping live in the pure
// dtc_ranges.dart (the resolver needs them without Flutter); re-exported here
// so every existing caller is unchanged.

class DtcLocalizations {
  DtcLocalizations._();

  /// Languages that ship a localized category-header set. Any langCode outside
  /// this set (or any missing key) falls back to English via [categoryHeader].
  static const List<String> supportedHeaderLanguages = [
    'en', 'hi', 'bn', 'te', 'mr', 'ta', 'gu', 'kn', 'ml', 'pa',
  ];

  /// Classify a raw code by its leading character (P/C/B/U).
  static DtcCategory categoryOf(String code) {
    if (code.isEmpty) return DtcCategory.unknown;
    switch (code[0].toUpperCase()) {
      case 'P':
        return DtcCategory.powertrain;
      case 'C':
        return DtcCategory.chassis;
      case 'B':
        return DtcCategory.body;
      case 'U':
        return DtcCategory.network;
      default:
        return DtcCategory.unknown;
    }
  }

  /// Localized category header for [code] in [langCode].
  ///
  /// Falls back to the English header when the language or the specific
  /// category is not translated, so a card never renders an empty label.
  static String categoryHeader(String code, String langCode) {
    final category = categoryOf(code);
    final table = _categoryHeaders[langCode] ?? _categoryHeaders['en']!;
    return table[category] ?? _categoryHeaders['en']![category]!;
  }

  /// `AppStrings` key naming the subsystem a STANDARD code belongs to, or
  /// null when the code's range has no subsystem grouping this app is
  /// confident of.
  ///
  /// From the SAE J2012 grouping AS UNDERSTOOD here (third character of the
  /// code); re-check against the standard text before extending it. Only
  /// P0/P2 groups 0–7 and U0 groups 0–4 are mapped. Manufacturer-defined
  /// codes return null: their grouping is the maker's too.
  static String? subsystemKey(String code) => subsystemKeyFor(code);

  // ── Chassis / ABS platform dictionary ─────────────────────────────────────
  /// Localized chassis entry for [code] under [platformKey].
  ///
  /// [platformKey] is a manufacturer + model-family key (see
  /// [ChassisPlatforms]), not a bare manufacturer: one manufacturer can ship
  /// several ABS platforms whose code systems disagree, so the model is part
  /// of the identity of a chassis code.
  ///
  /// Resolution mirrors [description] exactly: Hindi is served from the
  /// parallel Hindi map when present, every other language (and any Hindi gap)
  /// falls back to the English master. Returns null when the English master
  /// has no entry — the app must never render a Hindi-only or invented
  /// description for a braking-system fault, so "no data" stays "no data".
  static ChassisDtcResolved? chassisEntry(
    String? platformKey,
    String code,
    String langCode,
  ) {
    final upper = code.toUpperCase();
    final master = ChassisDtcDatabase.lookup(platformKey, upper);
    if (master == null) return null;

    final hi = langCode == 'hi'
        ? ChassisDtcDictionaryHi.lookup(platformKey, upper)
        : null;

    String pick(String? localized, String fallback) =>
        (localized != null && localized.isNotEmpty) ? localized : fallback;

    return ChassisDtcResolved(
      // Component is a manufacturer identifier token, never translated.
      component: master.component,
      description: pick(hi?.description, master.description),
      query: pick(hi?.query, master.query),
      remedy: pick(hi?.remedy, master.remedy),
      severity: master.severity,
      // Carried from the English master only. Whether a source states a
      // code's meaning is a fact about the source, not about the language it
      // is being read in, so a translation can never upgrade an unverified
      // entry into a verified one.
      meaningVerified: master.meaningVerified,
    );
  }

  // ── Category-header matrix ────────────────────────────────────────────────
  // Powertrain / Chassis / Body / Network are established automotive loanwords
  // across Indian languages; the native-script forms below are the readings
  // used in local diagnostic contexts. Display-only — safe to localize (unlike
  // gauge units, whose text also drives comparison logic).
  static const Map<String, Map<DtcCategory, String>> _categoryHeaders = {
    'en': {
      DtcCategory.powertrain: 'POWERTRAIN',
      DtcCategory.chassis: 'CHASSIS',
      DtcCategory.body: 'BODY',
      DtcCategory.network: 'NETWORK',
      DtcCategory.unknown: 'UNKNOWN',
    },
    'hi': {
      DtcCategory.powertrain: 'पावरट्रेन',
      DtcCategory.chassis: 'चेसिस',
      DtcCategory.body: 'बॉडी',
      DtcCategory.network: 'नेटवर्क',
      DtcCategory.unknown: 'अज्ञात',
    },
    'bn': {
      DtcCategory.powertrain: 'পাওয়ারট্রেন',
      DtcCategory.chassis: 'চ্যাসিস',
      DtcCategory.body: 'বডি',
      DtcCategory.network: 'নেটওয়ার্ক',
      DtcCategory.unknown: 'অজানা',
    },
    'te': {
      DtcCategory.powertrain: 'పవర్‌ట్రెయిన్',
      DtcCategory.chassis: 'ఛాసిస్',
      DtcCategory.body: 'బాడీ',
      DtcCategory.network: 'నెట్‌వర్క్',
      DtcCategory.unknown: 'తెలియదు',
    },
    'mr': {
      DtcCategory.powertrain: 'पॉवरट्रेन',
      DtcCategory.chassis: 'चेसिस',
      DtcCategory.body: 'बॉडी',
      DtcCategory.network: 'नेटवर्क',
      DtcCategory.unknown: 'अज्ञात',
    },
    'ta': {
      DtcCategory.powertrain: 'பவர்டிரெயின்',
      DtcCategory.chassis: 'சேசிஸ்',
      DtcCategory.body: 'பாடி',
      DtcCategory.network: 'நெட்வொர்க்',
      DtcCategory.unknown: 'தெரியாதது',
    },
    'gu': {
      DtcCategory.powertrain: 'પાવરટ્રેન',
      DtcCategory.chassis: 'ચેસિસ',
      DtcCategory.body: 'બોડી',
      DtcCategory.network: 'નેટવર્ક',
      DtcCategory.unknown: 'અજ્ઞાત',
    },
    'kn': {
      DtcCategory.powertrain: 'ಪವರ್‌ಟ್ರೈನ್',
      DtcCategory.chassis: 'ಚಾಸಿಸ್',
      DtcCategory.body: 'ಬಾಡಿ',
      DtcCategory.network: 'ನೆಟ್‌ವರ್ಕ್',
      DtcCategory.unknown: 'ಅಜ್ಞಾತ',
    },
    'ml': {
      DtcCategory.powertrain: 'പവർട്രെയിൻ',
      DtcCategory.chassis: 'ഷാസി',
      DtcCategory.body: 'ബോഡി',
      DtcCategory.network: 'നെറ്റ്‌വർക്ക്',
      DtcCategory.unknown: 'അജ്ഞാതം',
    },
    'pa': {
      DtcCategory.powertrain: 'ਪਾਵਰਟ੍ਰੇਨ',
      DtcCategory.chassis: 'ਚੈਸਿਸ',
      DtcCategory.body: 'ਬਾਡੀ',
      DtcCategory.network: 'ਨੈੱਟਵਰਕ',
      DtcCategory.unknown: 'ਅਣਜਾਣ',
    },
  };
}

/// A chassis/ABS dictionary entry already resolved into the app's active
/// language, ready for the fault card to render without further lookups.
class ChassisDtcResolved {
  final String component;
  final String description;
  final String query;
  final String remedy;
  final String severity;

  /// False when the source lists this code but does not state what it means —
  /// see [ChassisDtcEntry.meaningVerified]. The fault card must render such an
  /// entry with an explicit "meaning not verified" treatment rather than
  /// presenting the description text as a manufacturer's statement of the
  /// fault.
  final bool meaningVerified;

  const ChassisDtcResolved({
    required this.component,
    required this.description,
    required this.query,
    required this.remedy,
    required this.severity,
    this.meaningVerified = true,
  });
}
