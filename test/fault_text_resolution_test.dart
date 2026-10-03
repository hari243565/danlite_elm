/// Fault-code safety release — S5 (manufacturer-defined codes), S6 (cause and
/// advice shown), S7 (what a code with no text shows), S10 (C1024).
///
/// Phase 4C: the borrowed engine text (the translations asset and the Hindi
/// dictionary) is gone, so the tests that read it are gone with it; what is
/// left checks the rules that outlive it.
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/constants/chassis_dtc_dictionary.dart';
import 'package:danlite_elm/constants/dtc_descriptions.dart';
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
      final texts = await renderedTexts(tester, obd);
      expect(texts, contains(en('dtcManufacturerSpecific')));
      // P0198 has no text anywhere now: structure and the dealer line.
      expect(texts, contains(en('faultRawShowDealer')));
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
  // S7 — a code with no text shows its structure, not a guess
  // ══════════════════════════════════════════════════════════════════════════
  group('S7', () {
    test('subsystem names for standard codes; none for manufacturer codes', () {
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

    testWidgets('an unknown standard code shows system, subsystem, no text, and the dealer line',
        (tester) async {
      late ObdService obd;
      late EngineSim sim;
      await tester.runAsync(() async {
        // P0017: a standard code no content describes.
        sim = EngineSim(mode03: '43 01 00 17');
        obd = await connectSim(sim);
        await obd.readEngineDtcs();
      });
      final texts = await renderedTexts(tester, obd);
      expect(texts, contains('POWERTRAIN'));
      expect(texts, contains(en('dtcSubsystem').toUpperCase()));
      expect(texts, contains(en('dtcSubFuelAir')));
      expect(texts, contains(en('faultRawShowDealer')));
      await tester.runAsync(() async {
        await obd.disconnect();
        await sim.close();
      });
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
