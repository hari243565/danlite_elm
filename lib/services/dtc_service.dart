/// Danlite ELM — DTC Localization Service
///
/// Central, langCode-aware lookup layer that maps a raw fault code
/// (e.g. `P0122`, extracted by ObdService) to the strings shown on a fault
/// card:
///   • the SAE J2012 category   (Powertrain / Chassis / Body / Network)
///   • a localized category header for that category
///   • a localized human-readable description
///
/// ── Master file ingestion ────────────────────────────────────────────────
/// The Hindi descriptions originate from the Torque Pro master text file
/// `hindi_dtcs_raw.txt`. That file is ingested by [parseRawDictionary] (the
/// canonical parser below) and the result is checked in as the generated,
/// compile-time-verified map [DtcDictionaryHi.descriptions]. We read Hindi
/// from that pre-parsed map rather than re-parsing the raw asset at runtime:
/// it is the same data, but with zero file-I/O on the UI build path and a
/// single source of truth. If the raw master changes, regenerate the map by
/// feeding the file through [parseRawDictionary] again.
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
import '../constants/dtc_dictionary_hi.dart';

/// The four SAE J2012 diagnostic categories, keyed by the first character of
/// the code. This mirrors the bitmask decode already done in the parser and
/// is display-only — it never feeds protocol logic.
enum DtcCategory { powertrain, chassis, body, network, unknown }

class DtcLocalizations {
  DtcLocalizations._();

  /// Languages that ship a localized category-header set. Any langCode outside
  /// this set (or any missing key) falls back to English via [categoryHeader].
  static const List<String> supportedHeaderLanguages = [
    'en', 'hi', 'bn', 'te', 'mr', 'ta', 'gu', 'kn', 'ml', 'pa',
  ];

  /// Supplemental en/hi description source generated from a verified
  /// Torque Pro P-code export (`assets/dtc_translations.json`, 999 entries).
  /// Used only to fill gaps left by [DtcDictionaryHi] (Hindi) and the sparse
  /// `DtcDatabase` table (English) — it does not carry severity/cause/action,
  /// so it must never replace those lookups.
  static Map<String, Map<String, String>> _jsonDescriptions = {};

  static Future<void> init() async {
    try {
      final raw = await rootBundle.loadString('assets/dtc_translations.json');
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _jsonDescriptions = decoded.map(
        (code, entry) => MapEntry(code, Map<String, String>.from(entry as Map)),
      );
    } catch (e) {
      debugPrint('[DtcLocalizations] Failed to load dtc_translations.json: $e');
    }
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

  /// Localized description for [code] in [langCode].
  ///
  /// Hindi is served from the ingested master ([DtcDictionaryHi]); every other
  /// language falls back to [englishFallback] — the English description already
  /// resolved by ObdService — until that language ships its own dictionary.
  static String description(
    String code,
    String langCode, {
    required String englishFallback,
  }) {
    final upper = code.toUpperCase();
    if (langCode == 'hi') {
      final hi = DtcDictionaryHi.descriptions[upper];
      if (hi != null && hi.isNotEmpty) return hi;
      final jsonHi = _jsonDescriptions['hi']?[upper];
      if (jsonHi != null && jsonHi.isNotEmpty) return jsonHi;
    }
    if (englishFallback.isNotEmpty) return englishFallback;
    final jsonEn = _jsonDescriptions['en']?[upper];
    if (jsonEn != null && jsonEn.isNotEmpty) return jsonEn;
    return englishFallback;
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
