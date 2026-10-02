/// Phase A-4 (S2, S4) — every new rider-facing string exists in English and
/// Hindi, the owner's own Hindi wording is exactly as given, placeholders
/// match between the two, and the Hindi style sheet holds (Latin digits,
/// "एडेप्टर", "फ़ॉल्ट कोड", units never translated).
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

/// The owner's wording from the brief (S2 and S4), verbatim.
const ownerHindi = <String, String>{
  'snapshotTitle': 'फ़ॉल्ट दर्ज होने के समय का स्नैपशॉट',
  'snapshotNone': 'इस फ़ॉल्ट के लिए कोई स्नैपशॉट सेव नहीं है।',
  'snapshotUnsupported': 'यह बाइक स्नैपशॉट डेटा नहीं देती।',
  'snapshotNoAnswer':
      'बाइक ने जवाब नहीं दिया। इसका मतलब यह नहीं कि स्नैपशॉट नहीं है। फिर से कोशिश करें।',
  'showDetails': 'विवरण दिखाएँ',
  'ctxLampKm': 'चेतावनी लैंप {n} km से चालू है',
  'ctxLampMin': 'चेतावनी लैंप {n} मिनट से चालू है',
  'ctxClearedKm': 'कोड {n} km पहले साफ़ किए गए थे',
  'ctxClearedMin': 'कोड {n} मिनट पहले साफ़ किए गए थे',
  'ctxWarmUps': 'कोड साफ़ होने के बाद इंजन {n} बार गर्म हुआ',
  'ctxAtLeast': 'कम से कम {n}',
  'readinessTitle': 'उत्सर्जन सेल्फ-चेक',
  'readinessComplete': 'पूरा',
  'readinessNotComplete': 'अभी पूरा नहीं',
  'readinessNotSupported': 'इस बाइक में नहीं है',
  'readinessHint': 'कोड साफ़ करने के बाद ये चेक रीसेट हो जाते हैं और कुछ राइड के बाद पूरे होते हैं।',
  'monMisfire': 'मिसफ़ायर',
  'monFuelSystem': 'ईंधन सिस्टम',
  'monComponents': 'कंपोनेंट',
  'monCatalyst': 'कैटेलिस्ट',
  'monHeatedCatalyst': 'हीटेड कैटेलिस्ट',
  'monEvaporative': 'इवैपोरेटिव सिस्टम',
  'monSecondaryAir': 'सेकेंडरी एयर',
  'monOtherSelfCheck': 'अन्य सेल्फ-चेक',
  'monOxygenSensor': 'ऑक्सीजन सेंसर',
  'monOxygenSensorHeater': 'ऑक्सीजन सेंसर हीटर',
  'monEgr': 'EGR / VVT',
  // S2
  'historyClearAttempt': 'कोड साफ़ करने की कोशिश: {time}।',
  'historyClearAfterCodes': 'उसके बाद {n} कोड अब भी दिखे।',
  'historyClearAfterNone': 'उसके बाद कोई कोड नहीं दिखा।',
  'historyClearAfterUnknown': 'उसके बाद जाँच नहीं हो सकी।',
};

const ownerEnglish = <String, String>{
  'historyClearAttempt': 'Clear attempted at {time}.',
  'historyClearAfterCodes': 'After clearing: {n} code(s) were still reported.',
  'historyClearAfterNone': 'After clearing: no codes were reported.',
  'historyClearAfterUnknown': 'After clearing: could not check.',
  'ctxLampKm': 'Warning lamp has been on for {n} km',
  'ctxLampMin': 'Warning lamp has been on for {n} min',
  'ctxClearedKm': 'Codes were cleared {n} km ago',
  'ctxClearedMin': 'Codes were cleared {n} min ago',
};

/// Every key this phase added (the owner's and the proposed ones).
final newKeys = <String>[
  ...ownerHindi.keys,
  'hideDetails', 'snapshotRefused', 'snapshotOtherFault', 'ctxPartial',
  'snapFuelSystem', 'snapShortTrim', 'snapLongTrim', 'snapIntakePressure',
  'snapIntakeAirTemp', 'snapModuleVoltage', 'fuelStatusOpenCold', 'fuelStatusClosed',
  'fuelStatusOpenLoad', 'fuelStatusOpenFault', 'fuelStatusClosedFault',
  'fuelStatusUnknown', 'fuelStatusEngineOff', 'readinessNotApplicable', 'readinessUnavailable',
];

Set<String> placeholders(String s) =>
    RegExp(r'\{[a-z]+\}').allMatches(s).map((m) => m[0]!).toSet();

void main() {
  final en = AppStrings.languageTable('en');
  final hi = AppStrings.languageTable('hi');

  test("the owner's Hindi wording is exactly as given", () {
    ownerHindi.forEach((k, v) => expect(hi[k], v, reason: k));
  });

  test("the owner's English wording is exactly as given", () {
    ownerEnglish.forEach((k, v) => expect(en[k], v, reason: k));
  });

  test('every new key exists in English and Hindi, and Hindi is not English', () {
    for (final k in newKeys) {
      expect(en[k], isNotNull, reason: 'en $k');
      expect(hi[k], isNotNull, reason: 'hi $k');
      expect((en[k] ?? '').trim(), isNotEmpty);
      expect((hi[k] ?? '').trim(), isNotEmpty);
      // EGR / VVT is the owner's wording in both languages (Latin script).
      if (k != 'monEgr') {
        expect(hi[k], isNot(en[k]), reason: '$k: Hindi must be translated');
      }
    }
  });

  test('placeholders match between English and Hindi', () {
    for (final k in newKeys) {
      expect(placeholders(hi[k]!), placeholders(en[k]!), reason: k);
    }
  });

  test('the unit-bearing sentences keep the units Latin and untranslated', () {
    for (final k in ['ctxLampKm', 'ctxClearedKm']) {
      expect(hi[k], contains('km'), reason: k);
    }
  });

  test('no new Hindi string uses Devanagari digits (Latin digits only)', () {
    final devanagariDigit = RegExp(r'[०-९]');
    for (final k in newKeys) {
      expect(devanagariDigit.hasMatch(hi[k]!), isFalse, reason: k);
    }
  });

  test('the sentences that take a number say where it goes', () {
    for (final k in ['ctxLampKm', 'ctxLampMin', 'ctxClearedKm', 'ctxClearedMin', 'ctxWarmUps', 'ctxAtLeast']) {
      expect(en[k], contains('{n}'), reason: 'en $k');
      expect(hi[k], contains('{n}'), reason: 'hi $k');
    }
  });

  test('"at least" slots into every counter sentence, in both languages', () {
    for (final lang in ['en', 'hi']) {
      final atLeast = AppStrings.get('ctxAtLeast', lang).replaceAll('{n}', '65,535');
      for (final k in ['ctxLampKm', 'ctxClearedKm', 'ctxWarmUps']) {
        final s = AppStrings.get(k, lang).replaceAll('{n}', atLeast);
        expect(s.contains('{'), isFalse, reason: '$lang $k');
        expect(s, contains('65,535'));
      }
    }
  });

  test('the old misleading text is gone', () {
    expect(en.containsKey('noFreezeData'), isFalse);
    expect(hi.containsKey('noFreezeData'), isFalse);
  });

  test('other languages fall back to English for the new keys (no half-translations)', () {
    for (final lang in ['bn', 'te', 'mr', 'ta', 'gu', 'kn', 'ml', 'pa', 'ne']) {
      for (final k in newKeys) {
        expect(AppStrings.get(k, lang), en[k], reason: '$lang $k');
      }
    }
  });
}
