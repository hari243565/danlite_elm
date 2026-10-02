/// Phase A-4 (S1) — one spelling per word across the Hindi text.
///
/// The owner has no translator, so the style sheet is the authority: "एडेप्टर"
/// for adapter, "फ़ॉल्ट कोड" (with the nukta) for fault code, and "सर्विस
/// मैनुअल" is masculine ("के सर्विस मैनुअल"). This test fails if an old
/// spelling comes back anywhere in the Hindi strings.
library;

import 'dart:io';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/services/fault_decoders.dart';
import 'package:flutter_test/flutter_test.dart';

// Spelled with escapes so no editor can silently normalise them.
const _oldAdapterA = 'अडैप्टर'; // अडैप्टर
const _oldAdapterB = 'एडाप्टर'; // एडाप्टर
const _adapter = 'एडेप्टर'; // एडेप्टर
const _oldFault = 'फॉल्ट'; // फॉल्ट (no nukta)
const _fault = 'फ़ॉल्ट'; // फ़ॉल्ट (nukta)

void main() {
  final hi = AppStrings.languageTable('hi');

  test('the Hindi table is the whole Hindi block (guards the helper itself)', () {
    expect(hi.length, greaterThan(500));
    expect(hi['faultCodesDtc'], isNotNull);
  });

  test('no Hindi string uses an old adapter spelling', () {
    final bad = <String>[
      for (final e in hi.entries)
        if (e.value.contains(_oldAdapterA) || e.value.contains(_oldAdapterB)) e.key,
    ];
    expect(bad, isEmpty, reason: 'use $_adapter: $bad');
  });

  test('no Hindi string spells fault without the nukta', () {
    final bad = <String>[
      for (final e in hi.entries)
        if (e.value.contains(_oldFault)) e.key,
    ];
    expect(bad, isEmpty, reason: 'use $_fault: $bad');
  });

  test('"फ़ॉल्ट कोड" is spelled with the nukta wherever it appears', () {
    final withNukta = hi.values.where((v) => v.contains('$_fault कोड'));
    expect(withNukta, isNotEmpty);
  });

  test('the main tab label is "फ़ॉल्ट कोड" (the visible change the owner asked for)', () {
    expect(AppStrings.get('faultCodes', 'hi'), '$_fault कोड');
    // Other languages are not touched by this phase.
    expect(AppStrings.get('faultCodes', 'en'), 'Fault Codes');
  });

  test('service manual is masculine in the two provenance lines', () {
    expect(
        AppStrings.get('provenanceManual', 'hi'),
        'निर्माता के '
        'सर्विस मैनुअल से');
    expect(
        AppStrings.get('provenanceManualNoMeaning', 'hi'),
        'निर्माता के '
        'सर्विस मैनुअल में '
        'यह कोड है, पर इसका '
        'मतलब नहीं दिया गया');
    // "की सर्विस मैनुअल" (feminine) must not survive anywhere.
    final feminine = 'की सर्विस मैनुअल';
    expect(hi.values.where((v) => v.contains(feminine)), isEmpty);
  });

  test('the other Hindi sources (dictionaries, failure types) carry no old spelling', () {
    for (final path in const [
      'lib/constants/dtc_dictionary_hi.dart',
      'lib/constants/chassis_dtc_dictionary_hi.dart',
      'lib/services/fault_decoders.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains(_oldAdapterA), isFalse, reason: path);
      expect(src.contains(_oldAdapterB), isFalse, reason: path);
      expect(src.contains('$_oldFault कोड'), isFalse, reason: path);
    }
    for (var b = 0; b < 256; b++) {
      final text = FailureType.describe(b, 'hi');
      expect(text.contains(_oldAdapterA) || text.contains(_oldAdapterB), isFalse);
    }
  });
}
