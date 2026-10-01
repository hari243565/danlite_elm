/// Danlite ELM — DTC Localization Service
///
/// Central, langCode-aware lookup layer that maps a raw fault code
/// (e.g. `P0122`, extracted by ObdService) to the strings shown on a fault
/// card:
///   • the SAE J2012 category   (Powertrain / Chassis / Body / Network)
///   • a localized category header for that category
///   • a localized human-readable description
///
/// ── Engine description sources, and what is no longer used ─────────────
/// `DtcDictionaryHi` (999 Hindi entries, generated from a Torque Pro text
/// file by [parseRawDictionary]) is corrupted by PDF text extraction — 88% of
/// its entries carry broken words (FAULT_ASSET_INVENTORY.md §D4) — and it is
/// NOT used at runtime any more. Every one of its 999 codes has a clean Hindi
/// entry in `assets/dtc_translations.json`, which is what Hindi now reads
/// (verified by `test/fault_text_resolution_test.dart`). The file is kept,
/// not deleted. Both engine sources name Torque Pro and have no recorded
/// licence, so both sit behind [kUseLegacyEngineText], which a store build
/// forces off.
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

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../constants/build_flags.dart';
import '../constants/chassis_dtc_dictionary.dart';
import '../constants/chassis_dtc_dictionary_hi.dart';

/// The four SAE J2012 diagnostic categories, keyed by the first character of
/// the code. This mirrors the bitmask decode already done in the parser and
/// is display-only — it never feeds protocol logic.
enum DtcCategory { powertrain, chassis, body, network, unknown }

/// True when [code]'s meaning is set by the vehicle manufacturer, not by the
/// SAE standard, so a generic table cannot say what it means on this bike.
///
/// Follows the SAE J2012 code-range convention AS UNDERSTOOD here, and must
/// be re-checked against the standard text:
///   * P: second digit 1 (P1xxx), or second digit 3 with third digit 0–3
///     (P30xx–P33xx). P0xxx, P2xxx and P34xx–P39xx are SAE-defined.
///   * B, C, U: second digit 1 or 2 (B1xxx/B2xxx, C1xxx/C2xxx, U1xxx/U2xxx).
///     Second digit 0 (and 3) are SAE-defined.
/// Anything that is not a well-formed five-character code returns false.
bool isManufacturerDefined(String code) {
  final c = code.trim().toUpperCase();
  if (!RegExp(r'^[PCBU][0-3][0-9A-F]{3}$').hasMatch(c)) return false;
  final second = c[1];
  if (c[0] == 'P') {
    if (second == '1') return true;
    return second == '3' && '0123'.contains(c[2]);
  }
  return second == '1' || second == '2';
}

class DtcLocalizations {
  DtcLocalizations._();

  /// Languages that ship a localized category-header set. Any langCode outside
  /// this set (or any missing key) falls back to English via [categoryHeader].
  static const List<String> supportedHeaderLanguages = [
    'en', 'hi', 'bn', 'te', 'mr', 'ta', 'gu', 'kn', 'ml', 'pa',
  ];

  /// en/hi engine descriptions from `assets/dtc_translations.json`, which
  /// holds 1,709 P codes per language (an earlier version held 999). Its
  /// header in the source history names a Torque Pro export; no licence is
  /// recorded. Loaded only while [kUseLegacyEngineText] is on. It carries no
  /// severity/cause/action, so it never replaces the `DtcDatabase` lookup.
  static Map<String, Map<String, String>> _jsonDescriptions = {};

  static Future<void> init() async {
    // A store build never even reads the asset.
    if (!kUseLegacyEngineText) return;
    try {
      final raw = await rootBundle.loadString('assets/dtc_translations.json');
      loadJsonForTesting(raw);
    } catch (e) {
      debugPrint('[DtcLocalizations] Failed to load dtc_translations.json: $e');
    }
  }

  /// Parse the translations asset's `{en:{code:text}, hi:{code:text}}` shape.
  /// Public for tests, which read the real asset from disk.
  @visibleForTesting
  static void loadJsonForTesting(String raw) {
    final decoded = json.decode(raw) as Map<String, dynamic>;
    _jsonDescriptions = decoded.map(
      (lang, entry) => MapEntry(lang, Map<String, String>.from(entry as Map)),
    );
  }

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

  /// Localized description for an ENGINE [code] in [langCode], or `''` when
  /// nothing verified-enough exists — the card then shows the code's
  /// structure instead (see [subsystemKey]).
  ///
  /// Order:
  ///   1. A manufacturer-defined code ([isManufacturerDefined]) resolves to
  ///      `''`, always: no generic or engine table may describe it, because
  ///      its meaning depends on the bike's maker.
  ///   2. Hindi, when [useLegacyText] is on: the clean JSON Hindi. The
  ///      corrupted `DtcDictionaryHi` is never consulted.
  ///   3. [englishFallback] — the English already on the code (`DtcDatabase`).
  ///   4. JSON English, when [useLegacyText] is on.
  ///
  /// Hindi with no clean entry falls back to English, never to corrupted text.
  /// [useLegacyText] defaults to [kUseLegacyEngineText]; tests pass it.
  static String description(
    String code,
    String langCode, {
    required String englishFallback,
    bool useLegacyText = kUseLegacyEngineText,
  }) {
    final upper = code.toUpperCase();
    if (isManufacturerDefined(upper)) return '';
    if (langCode == 'hi' && useLegacyText) {
      final jsonHi = _jsonDescriptions['hi']?[upper];
      if (jsonHi != null && jsonHi.isNotEmpty) return jsonHi;
    }
    if (englishFallback.isNotEmpty) return englishFallback;
    if (useLegacyText) {
      final jsonEn = _jsonDescriptions['en']?[upper];
      if (jsonEn != null && jsonEn.isNotEmpty) return jsonEn;
    }
    return '';
  }

  /// `AppStrings` key naming the subsystem a STANDARD code belongs to, or
  /// null when the code's range has no subsystem grouping this app is
  /// confident of.
  ///
  /// From the SAE J2012 grouping AS UNDERSTOOD here (third character of the
  /// code); re-check against the standard text before extending it. Only
  /// P0/P2 groups 0–7 and U0 groups 0–4 are mapped. Manufacturer-defined
  /// codes return null: their grouping is the maker's too.
  static String? subsystemKey(String code) {
    final c = code.trim().toUpperCase();
    if (!RegExp(r'^[PCBU][0-3][0-9A-F]{3}$').hasMatch(c)) return null;
    if (isManufacturerDefined(c)) return null;
    final group = c[2];
    if (c[0] == 'P' && (c[1] == '0' || c[1] == '2')) {
      switch (group) {
        case '0':
        case '1':
        case '2':
          return 'dtcSubFuelAir';
        case '3':
          return 'dtcSubIgnition';
        case '4':
          return 'dtcSubEmission';
        case '5':
          return 'dtcSubSpeedIdle';
        case '6':
          return 'dtcSubComputer';
        case '7':
          return 'dtcSubTransmission';
      }
      if (c[1] == '0' && (group == '8' || group == '9')) {
        return 'dtcSubTransmission';
      }
      return null;
    }
    if (c[0] == 'U' && c[1] == '0') {
      switch (group) {
        case '0':
          return 'dtcSubNetworkElectrical';
        case '1':
        case '2':
          return 'dtcSubNetworkComms';
        case '3':
          return 'dtcSubNetworkSoftware';
        case '4':
          return 'dtcSubNetworkData';
      }
    }
    return null;
  }

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

  // ── Canonical raw-master parser ───────────────────────────────────────────
  /// Parse the `hindi_dtcs_raw.txt` master format into a `code → description`
  /// map. This is the single ingestion routine that produced
  /// [DtcDictionaryHi.descriptions]; feed the raw file's contents through it to
  /// regenerate that map whenever the master text changes.
  ///
  /// Format handled:
  ///   • Entries are separated by blank lines.
  ///   • An entry begins with a `[PCBU]####` code token; the remainder of that
  ///     line plus any following non-blank lines form the description (the
  ///     master wraps long descriptions across physical lines).
  ///   • A leading "- " on the joined description is stripped.
  ///   • Internal runs of whitespace are collapsed to a single space.
  static Map<String, String> parseRawDictionary(String raw) {
    final result = <String, String>{};
    final codeRe = RegExp(r'^([PCBU][0-9A-F]{4})');
    String? currentCode;
    final buffer = StringBuffer();

    void flush() {
      final code = currentCode;
      if (code != null) {
        var desc = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
        if (desc.startsWith('- ')) desc = desc.substring(2).trim();
        if (desc.isNotEmpty) result[code] = desc;
      }
      currentCode = null;
      buffer.clear();
    }

    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        flush();
        continue;
      }
      final m = codeRe.firstMatch(line);
      if (m != null) {
        flush();
        currentCode = m.group(1);
        buffer.write(line.substring(m.end));
      } else if (currentCode != null) {
        buffer
          ..write(' ')
          ..write(line);
      }
    }
    flush();
    return result;
  }
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
