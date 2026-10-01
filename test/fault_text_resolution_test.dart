/// Fault-code safety release — S5 (manufacturer-defined codes), S6 (cause and
/// advice shown), S7 (legacy-text switch and Hindi lookup order), S10 (C1024).
///
/// Unlike the earlier suites, these load the REAL engine knowledge assets
/// (`assets/dtc_translations.json` and `DtcDictionaryHi`), so the resolution
/// the rider actually sees is what is tested.
library;

import 'dart:convert';
import 'dart:io';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/constants/build_flags.dart';
import 'package:danlite_elm/constants/chassis_dtc_dictionary.dart';
import 'package:danlite_elm/constants/dtc_descriptions.dart';
import 'package:danlite_elm/constants/dtc_dictionary_hi.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/dtc_screen.dart';
import 'package:danlite_elm/services/dtc_service.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/engine_sim.dart';

String en(String key) => AppStrings.get(key, 'en');

final String _jsonRaw = File('assets/dtc_translations.json').readAsStringSync();
final Map<String, dynamic> _json = json.decode(_jsonRaw) as Map<String, dynamic>;
Map<String, String> get jsonEn => Map<String, String>.from(_json['en'] as Map);
Map<String, String> get jsonHi => Map<String, String>.from(_json['hi'] as Map);

// ── The audit's broken-Hindi detectors (FAULT_ASSET_INVENTORY.md §D4) ──────
// A Devanagari token is flagged when it starts with a combining mark, holds
// two dependent vowel signs in a row, ends in a bare virama, or is one of the
// recurring broken forms the audit tabulated (§D4.2).
final _devanagariToken = RegExp(r'[ऀ-ॿ]+');
final _startsWithCombining =
    RegExp(r'^[ऀ-ःऺ-ॏ॑-ॗॢॣ]');
final _twoVowelSigns = RegExp(r'[ा-ौ][ा-ौ]');
final _endsInVirama = RegExp(r'्$');
const _knownBroken = <String>{
  'सतकि', 'वोल्टेर्', 'कं', 'टर', 'ोल', 'तनयंत्रण', 'ऑक्सीर्न', 'तसस्टम',
  'प्रदशिन', 'तसलेंडर', 'इंर्ेक्टर', 'तशफ्ट', 'इंर्न', 'िापमान', 'ईंिन',
  'स्िच', 'तसिल', 'कै', 'रेंर्', 'इतिशन', 'पिा', 'पोर्ीशन', 'इंर्ेक्शन',
  'ररले', 'पोतर्शन', 'इंटरतमटेंट', 'ांसतमशन', 'संदिि', 'डर', 'ाइव', 'ाइवर',
  'कू', 'तलंग', 'टबोचार्िर', 'फै', 'अतिक', 'तमसफायर', 'सीररयल', 'टाइतमंग',
  'बहुि', 'अपयािप्त', 'रीसर्क्ुिलेशन', 'उत्सर्िन', 'टॉकि', 'मैतनफोल्ड', 'पर्ि',
  'इलेस्क्टरकल', 'तगयर', 'तटरम', 'टेतलस्ट', 'गलि', 'अनुपाि', 'तनकास',
  'मीटररंग', 'हातन', 'सहसंबंि', 'गतितवति', 'प्रतितक्रया', 'दक्षिा', 'टतमिनल',
  'सतक्रय', 'क्रूर्', 'र्ेनरेटर',
};

/// The broken tokens in [text]; empty when it is clean.
List<String> brokenHindiTokens(String text) => [
      for (final m in _devanagariToken.allMatches(text))
        if (_startsWithCombining.hasMatch(m.group(0)!) ||
            _twoVowelSigns.hasMatch(m.group(0)!) ||
            _endsInVirama.hasMatch(m.group(0)!) ||
            _knownBroken.contains(m.group(0)!))
          m.group(0)!,
    ];

Widget screenFor(ObdService obd) => MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider()),
        ChangeNotifierProvider<VehicleProvider>(
            create: (_) => VehicleProvider()),
        ChangeNotifierProvider<ObdService>.value(value: obd),
      ],
      child: const MaterialApp(home: DtcScreen(autoScan: false)),
    );

Future<List<String>> renderedTexts(WidgetTester tester, ObdService obd) async {
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(screenFor(obd));
  await tester.pump(const Duration(milliseconds: 50));
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => DtcLocalizations.loadJsonForTesting(_jsonRaw));

  // ══════════════════════════════════════════════════════════════════════════
  // S5 — manufacturer-defined codes never get another make's meaning
  // ══════════════════════════════════════════════════════════════════════════
  group('S5', () {
    test('isManufacturerDefined follows the stated J2012 convention', () {
      const yes = ['P1100', 'P1ABC', 'P3000', 'P3300', 'P33FF', 'B1000',
        'B2000', 'C1015', 'C2000', 'U1000', 'U2922'];
      const no = ['P0133', 'P2176', 'P3400', 'P3900', 'B0001', 'C0035',
        'U0100', 'U3000', 'C3000', 'garbage', ''];
      for (final c in yes) {
        expect(isManufacturerDefined(c), isTrue, reason: c);
      }
      for (final c in no) {
        expect(isManufacturerDefined(c), isFalse, reason: c);
      }
    });

    test('none of the 436 P1 asset entries is ever returned', () {
      final p1 = jsonEn.keys.where((k) => k.startsWith('P1')).toList();
      expect(p1.length, 436, reason: 'the audit counted 436');
      for (final code in p1) {
        for (final lang in ['en', 'hi', 'ta']) {
          expect(
              DtcLocalizations.description(code, lang, englishFallback: ''),
              isEmpty,
              reason: '$code/$lang');
        }
      }
      // The corrupted Hindi file's 391 P1 entries are equally unreachable.
      for (final code
          in DtcDictionaryHi.descriptions.keys.where((k) => k.startsWith('P1'))) {
        expect(DtcLocalizations.description(code, 'hi', englishFallback: ''),
            isEmpty,
            reason: code);
      }
    });

    test('a standard P0 code resolves exactly as before', () {
      expect(DtcLocalizations.description('P0198', 'en', englishFallback: ''),
          jsonEn['P0198']);
      expect(DtcLocalizations.description('P0100', 'en',
              englishFallback: DtcDatabase.codes['P0100']!['desc']!),
          DtcDatabase.codes['P0100']!['desc']);
    });

    test('Royal Enfield ABS codes still resolve from their platform table', () {
      final c350 = ChassisPlatforms.resolve('Royal Enfield', 'Classic 350');
      final entry = DtcLocalizations.chassisEntry(c350, 'C1015', 'en');
      expect(entry, isNotNull);
      expect(entry!.description, isNotEmpty);
      expect(isManufacturerDefined('C1015'), isTrue,
          reason: 'platform tables are exactly where these ARE described');
    });

    testWidgets('the card shows the manufacturer-specific message for P1xxx',
        (tester) async {
      late ObdService obd;
      late EngineSim sim;
      await tester.runAsync(() async {
        // P1100 (11 00) and P0198 (01 98).
        sim = EngineSim(mode03: '43 02 11 00 01 98');
        obd = await connectSim(sim);
        await obd.readEngineDtcs();
      });
      expect(jsonEn['P1100'], isNotNull,
          reason: 'there IS a fixed asset text it must not show');
      final texts = await renderedTexts(tester, obd);
      expect(texts, contains(en('dtcManufacturerSpecific')));
      expect(texts, isNot(contains(jsonEn['P1100'])));
      expect(texts, contains(jsonEn['P0198']));
      await tester.runAsync(() async {
        await obd.disconnect();
        await sim.close();
      });
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S6 — the cause and advice that already exist are shown
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('S6: a table code shows cause and advice; others show no empty rows',
      (tester) async {
    late ObdService obd;
    late EngineSim sim;
    await tester.runAsync(() async {
      // P0100 (in DtcDatabase) and P0198 (not in it).
      sim = EngineSim(mode03: '43 02 01 00 01 98');
      obd = await connectSim(sim);
      await obd.readEngineDtcs();
    });
    final texts = await renderedTexts(tester, obd);
    final p0100 = DtcDatabase.codes['P0100']!;
    expect(texts, contains(p0100['cause']));
    expect(texts, contains(p0100['action']));
    expect(texts, contains(en('possibleCause').toUpperCase()));
    expect(texts, contains(en('recommendedAction').toUpperCase()));
    expect(texts, contains(en('dtcSeverityGuidance')));
    // One table code on screen → exactly one of each row and one note.
    expect(texts.where((t) => t == en('possibleCause').toUpperCase()).length, 1);
    expect(texts.where((t) => t == en('recommendedAction').toUpperCase()).length,
        1);
    expect(texts.where((t) => t == en('dtcSeverityGuidance')).length, 1);
    expect(texts.where((t) => t.isEmpty), isEmpty);
    await tester.runAsync(() async {
      await obd.disconnect();
      await sim.close();
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S7 — the legacy-text switch and the Hindi lookup order
  // ══════════════════════════════════════════════════════════════════════════
  group('S7', () {
    test('the switch is on in this (non-store) build', () {
      expect(kStoreBuild, isFalse);
      expect(kUseLegacyEngineText, isTrue);
    });

    test('a store build can never have it on', () {
      expect(legacyEngineTextAllowed(storeBuild: true), isFalse);
      expect(legacyEngineTextAllowed(storeBuild: false), isTrue);
      expect(kUseLegacyEngineText,
          legacyEngineTextAllowed(storeBuild: kStoreBuild));
    });

    test('script: every corrupted-dictionary code has clean JSON Hindi', () {
      final dict = DtcDictionaryHi.descriptions;
      expect(dict.length, 999);
      final missing = [
        for (final code in dict.keys)
          if ((jsonHi[code] ?? '').trim().isEmpty) code
      ];
      expect(missing, isEmpty);
      expect(jsonEn.length, 1709);
      expect(jsonHi.length, 1709);
    });

    test('the detectors do find the corruption they were built for', () {
      final flagged = DtcDictionaryHi.descriptions.values
          .where((t) => brokenHindiTokens(t).isNotEmpty)
          .length;
      expect(flagged / DtcDictionaryHi.descriptions.length,
          greaterThan(0.85),
          reason: 'the audit measured 88.3% of entries with a broken token');
      final cleanFlagged = jsonHi.values
          .where((t) => brokenHindiTokens(t).isNotEmpty)
          .toList();
      expect(cleanFlagged, isEmpty,
          reason: 'and find nothing in the clean JSON Hindi');
    });

    test('no corrupted Hindi token is ever returned', () {
      final codes = <String>{...DtcDictionaryHi.descriptions.keys, ...jsonHi.keys};
      final bad = <String, List<String>>{};
      for (final code in codes) {
        final shown =
            DtcLocalizations.description(code, 'hi', englishFallback: '');
        final broken = brokenHindiTokens(shown);
        if (broken.isNotEmpty) bad[code] = broken;
      }
      expect(bad, isEmpty);
    });

    test('Hindi with the switch on: clean JSON Hindi, never the old file', () {
      // P0198: the audit's own trace example.
      final shown =
          DtcLocalizations.description('P0198', 'hi', englishFallback: '');
      expect(shown, jsonHi['P0198']);
      expect(shown, isNot(DtcDictionaryHi.descriptions['P0198']));
    });

    test('Hindi falls back to English, never to corrupted text', () {
      // DtcDatabase-only codes have no Hindi anywhere.
      final u0100 = DtcDatabase.codes['U0100']!['desc']!;
      expect(
          DtcLocalizations.description('U0100', 'hi', englishFallback: u0100),
          u0100);
    });

    test('switch off: legacy text is not used; structure instead', () {
      expect(
          DtcLocalizations.description('P0198', 'en',
              englishFallback: '', useLegacyText: false),
          isEmpty);
      expect(
          DtcLocalizations.description('P0198', 'hi',
              englishFallback: '', useLegacyText: false),
          isEmpty);
      // The 31-entry table is not Torque-derived and stays.
      final p0100 = DtcDatabase.codes['P0100']!['desc']!;
      expect(
          DtcLocalizations.description('P0100', 'hi',
              englishFallback: p0100, useLegacyText: false),
          p0100);
      expect(DtcLocalizations.subsystemKey('P0198'), 'dtcSubFuelAir');
      expect(DtcLocalizations.subsystemKey('P0301'), 'dtcSubIgnition');
      expect(DtcLocalizations.subsystemKey('U0100'), 'dtcSubNetworkComms');
      expect(DtcLocalizations.subsystemKey('P1100'), isNull);
      for (final key in [
        'dtcSubFuelAir', 'dtcSubIgnition', 'dtcSubEmission', 'dtcSubSpeedIdle',
        'dtcSubComputer', 'dtcSubTransmission', 'dtcSubNetworkElectrical',
        'dtcSubNetworkComms', 'dtcSubNetworkSoftware', 'dtcSubNetworkData',
      ]) {
        expect(AppStrings.get(key, 'en'), isNot(key));
        expect(AppStrings.get(key, 'hi'), isNot(AppStrings.get(key, 'en')));
      }
    });

    testWidgets('an unknown standard code shows system, subsystem, no text',
        (tester) async {
      late ObdService obd;
      late EngineSim sim;
      await tester.runAsync(() async {
        // P0017: a standard code no asset describes.
        sim = EngineSim(mode03: '43 01 00 17');
        obd = await connectSim(sim);
        await obd.readEngineDtcs();
      });
      expect(jsonEn['P0017'], isNull);
      final texts = await renderedTexts(tester, obd);
      expect(texts, contains('POWERTRAIN'));
      expect(texts, contains(en('dtcSubsystem').toUpperCase()));
      expect(texts, contains(en('dtcSubFuelAir')));
      expect(texts, contains(en('dtcNoVerifiedDescription')));
      await tester.runAsync(() async {
        await obd.disconnect();
        await sim.close();
      });
    });

    test('the stale "999 entries" comment is gone', () {
      final src = File('lib/services/dtc_service.dart').readAsStringSync();
      expect(src.contains('999 entries'), isFalse);
      expect(src.contains('1,709'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S10 — Classic 350 C1024 remedy, completed
  // ══════════════════════════════════════════════════════════════════════════
  test('S10: C1024 carries the full manual remedy in English and Hindi', () {
    final c350 = ChassisPlatforms.resolve('Royal Enfield', 'Classic 350');
    final enEntry = DtcLocalizations.chassisEntry(c350, 'C1024', 'en')!;
    expect(enEntry.remedy,
        'Check the front toner wheel/ Airgap consistency/WSS bracket');
    final hiEntry = DtcLocalizations.chassisEntry(c350, 'C1024', 'hi')!;
    // Same wording as C1034, whose English remedy is the same instruction.
    expect(hiEntry.remedy,
        DtcLocalizations.chassisEntry(c350, 'C1034', 'hi')!.remedy);
    expect(hiEntry.remedy, contains('WSS ब्रैकेट'));
  });
}
