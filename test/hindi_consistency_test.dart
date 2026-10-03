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

  // The old word for "fault code" ("दोष कोड"), spelled with escapes. Where it is
  // still used it is listed here on purpose: KNOWN AND DEFERRED to a later
  // wording pass, because those strings belong to the Clear Codes dialog (or to
  // the generated l10n file), whose wording this phase must not change.
  const oldFaultCode = 'दोष कोड';
  const deferredAppStrings = <String>{'clearAllQ'};
  const deferredGenerated = <String>{'faultCodes', 'noFaultCodes', 'clearAllCodesQ'};

  test('"फ़ॉल्ट कोड" is the accepted form in the DTC title and the empty state', () {
    expect(hi['faultCodesDtc'], '$_fault कोड (DTC)');
    expect(hi['noFaultCodes'], 'कोई $_fault कोड नहीं मिला');
    for (final k in ['faultCodesDtc', 'noFaultCodes']) {
      expect(hi[k]!.contains(oldFaultCode), isFalse, reason: k);
    }
  });

  test('the remaining old "दोष कोड" strings are exactly the known, deferred ones', () {
    final found = <String>{
      for (final e in hi.entries)
        if (e.value.contains(oldFaultCode)) e.key,
    };
    expect(found, deferredAppStrings,
        reason: 'a new "दोष कोड" must use "फ़ॉल्ट कोड"; a deferred one must be listed here');
    // The Clear Codes dialog is untouched.
    expect(hi['clearAllQ'], 'सभी दोष कोड साफ करें?');
  });

  test('the generated Hindi l10n file keeps its old wording (deferred, not changed)', () {
    final src = File('lib/generated/app_localizations_hi.dart').readAsStringSync();
    final found = <String>{
      for (final m in RegExp(r"String get (\w+) => '[^']*" + oldFaultCode).allMatches(src))
        m[1]!,
    };
    expect(found, deferredGenerated);
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
