/// Phase 4C K5 — softer notes for the conditions the app cannot decide.
///
/// 104 shipped entries carry a condition about parts the bike profile does not
/// say (EVAP, CAN bus, knock sensor, …). The note stays, in softer words:
/// "May not apply to your bike. Applies only to bikes with <X>." The four
/// conditions the profile can decide keep exactly today's text.
library;

import 'dart:convert';
import 'dart:io';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/widgets/resolved_fault_view.dart' show kAppliesNoteKeys;
import 'package:flutter_test/flutter_test.dart';

import 'phase1b_screens_test.dart' as screens;
import 'support/engine_sim.dart';

const String kSoftEn = 'May not apply to your bike. ';
const String kSoftHi = 'आपकी बाइक पर लागू न भी हो सकता है। ';

/// (applies_when key, <X> in English, <X> in Hindi).
const List<(String, String, String)> kUndecidable = [
  ('knock_sensor_fitted', 'a knock sensor', 'नॉक सेंसर'),
  ('camshaft_sensor_fitted', 'a camshaft position sensor', 'कैमशाफ़्ट पोज़ीशन सेंसर'),
  ('oil_temp_sensor_fitted', 'an oil temperature sensor', 'ऑयल टेम्परेचर सेंसर'),
  ('closed_throttle_switch_fitted', 'a closed-throttle switch', 'क्लोज़्ड-थ्रॉटल स्विच'),
  ('evap_fitted', 'an EVAP (fuel vapour) system', 'EVAP (फ़्यूल वेपर) सिस्टम'),
  ('secondary_air_fitted', 'a secondary air system', 'सेकेंडरी एयर सिस्टम'),
  ('cooling_fan_fitted', 'a cooling fan', 'कूलिंग फ़ैन'),
  ('oil_pressure_sensor_fitted', 'an oil pressure sensor', 'ऑयल प्रेशर सेंसर'),
  ('ambient_temp_sensor_fitted', 'an outside-air temperature sensor',
      'बाहरी हवा का टेम्परेचर सेंसर'),
  ('fuel_level_sensor_fitted', 'a fuel level sensor', 'फ़्यूल लेवल सेंसर'),
  ('gear_position_sensor_fitted', 'a gear position sensor', 'गियर पोज़ीशन सेंसर'),
  ('clutch_switch_fitted', 'a clutch switch', 'क्लच स्विच'),
  ('downstream_o2_sensor_fitted', 'a downstream (after-catalyst) O2 sensor',
      'डाउनस्ट्रीम (कैटेलिस्ट के बाद वाला) O2 सेंसर'),
  ('can_bus_fitted', 'a CAN bus', 'CAN बस'),
];

/// The four the profile can decide, and the text they have always had.
const Map<String, (String, String)> kDecidable = {
  'cylinders_min': (
    'Applies only to bikes with two or more cylinders.',
    'यह सिर्फ़ दो या ज़्यादा सिलेंडर वाली बाइक पर लागू होता है।',
  ),
  'liquid_cooled': (
    'Applies only to liquid-cooled bikes.',
    'यह सिर्फ़ लिक्विड-कूल्ड बाइक पर लागू होता है।',
  ),
  'ride_by_wire': (
    'Applies only to bikes with a ride-by-wire throttle.',
    'यह सिर्फ़ राइड-बाय-वायर थ्रॉटल वाली बाइक पर लागू होता है।',
  ),
  'abs_fitted': (
    'Applies only to bikes fitted with ABS.',
    'यह सिर्फ़ ABS वाली बाइक पर लागू होता है।',
  ),
};

List<Map<String, Object?>> shipped() => [
      for (final l in File('assets/knowledge/generic_en/entries.jsonl').readAsLinesSync())
        if (l.trim().isNotEmpty) Map<String, Object?>.from(jsonDecode(l) as Map),
    ];

String mode03(String code) {
  final n = int.parse(code.substring(1), radix: 16);
  String h(int x) => x.toRadixString(16).toUpperCase().padLeft(2, '0');
  return '7E8 04 43 01 ${h((n >> 8) & 0xFF)} ${h(n & 0xFF)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('K5 the fourteen undecidable conditions', () {
    test('there are fourteen, and each has a note', () {
      expect(kUndecidable, hasLength(14));
      for (final (k, _, _) in kUndecidable) {
        expect(kAppliesNoteKeys[k], isNotNull, reason: k);
      }
    });

    for (final (k, en, hi) in kUndecidable) {
      test('$k: exact English and Hindi words', () {
        final key = kAppliesNoteKeys[k]!;
        expect(AppStrings.get(key, 'en'), '${kSoftEn}Applies only to bikes with $en.');
        expect(AppStrings.get(key, 'hi'), '$kSoftHi' 'यह सिर्फ़ $hi वाली बाइक पर लागू होता है।');
      });
    }

    test('Hindi uses the owner\'s fixed spellings and Latin digits', () {
      for (final (k, _, _) in kUndecidable) {
        final hi = AppStrings.get(kAppliesNoteKeys[k]!, 'hi');
        expect(hi.contains(RegExp(r'[०-९]')), isFalse, reason: k);
        expect(hi.contains('एडाप्टर'), isFalse, reason: k);
        expect(hi.contains('फॉल्ट'), isFalse, reason: k);
      }
    });
  });

  group('K5 the four the profile can decide keep today\'s text', () {
    for (final e in kDecidable.entries) {
      test('${e.key}: unchanged, no "may not apply"', () {
        final key = kAppliesNoteKeys[e.key]!;
        expect(AppStrings.get(key, 'en'), e.value.$1);
        expect(AppStrings.get(key, 'hi'), e.value.$2);
        expect(AppStrings.get(key, 'en'), isNot(contains('May not apply')));
        expect(AppStrings.get(key, 'hi'), isNot(contains('न भी हो सकता')));
      });
    }

    test('every shipped condition is one of the eighteen, and has a note in both languages', () {
      final used = <String>{
        for (final l in shipped())
          ...((l['applies_when'] as Map?)?.keys.cast<String>() ?? const <String>[]),
      };
      final known = {for (final (k, _, _) in kUndecidable) k, ...kDecidable.keys};
      expect(used.difference(known), isEmpty);
      for (final k in known) {
        expect(AppStrings.get(kAppliesNoteKeys[k]!, 'en'), isNot(kAppliesNoteKeys[k]));
        expect(AppStrings.get(kAppliesNoteKeys[k]!, 'hi'), isNot(kAppliesNoteKeys[k]));
      }
    });

    test('104 shipped entries carry an undecidable condition; none carries two', () {
      final undecidable = {for (final (k, _, _) in kUndecidable) k};
      var n = 0;
      for (final l in shipped()) {
        final aw = l['applies_when'] as Map?;
        if (aw == null) continue;
        expect(aw.length, 1, reason: '${l['code']}');
        if (undecidable.contains(aw.keys.single)) n++;
      }
      expect(n, 104);
    });
  });

  group('K5 on the card', () {
    final entries = shipped();
    String codeWith(String key) => entries.firstWhere(
        (l) => (l['applies_when'] as Map?)?.containsKey(key) ?? false)['code'] as String;

    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] an EVAP entry shows the soft note', (tester) async {
        final code = codeWith('evap_fitted');
        final env = await screens.setUp(tester, lang: lang, sim: EngineSim(mode03: mode03(code)));
        final xs = await screens.showDtc(tester, env);
        final note = AppStrings.get('appliesEvap', lang);
        expect(xs, contains(note));
        expect(note, startsWith(lang == 'en' ? kSoftEn : kSoftHi));
        await env.close(tester);
      });

      testWidgets('[$lang] a ride-by-wire entry keeps today\'s note', (tester) async {
        final code = codeWith('ride_by_wire');
        final env = await screens.setUp(tester, lang: lang, sim: EngineSim(mode03: mode03(code)));
        final xs = await screens.showDtc(tester, env);
        expect(xs, contains(AppStrings.get('appliesRideByWire', lang)));
        expect(xs.any((x) => x.contains(lang == 'en' ? 'May not apply' : 'न भी हो सकता')), isFalse);
        await env.close(tester);
      });
    }
  });
}
