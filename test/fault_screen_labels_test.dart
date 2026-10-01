/// Phase 1A — what the rider sees: small status labels on the cards, the lamp
/// chip, the count-mismatch note, the low-voltage banner, "may be false" on
/// network codes, the running-engine refusal line and the ABS failure type.
///
/// The REAL ObdService runs over the simulator; the REAL DtcScreen renders the
/// state it leaves, in English and in Hindi.
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/dtc_screen.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/engine_sim.dart';

const fast = FaultReadTiming.scaled(0.05);

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

class Rendered {
  Rendered(this.texts, this.obd, this.sim);
  final List<String> texts;
  final ObdService obd;
  final EngineSim sim;
  bool has(String s) => texts.contains(s);
  bool any(String s) => texts.any((x) => x.contains(s));
}

/// Read the engine (and optionally the ABS module) over [sim], let the extras
/// finish, then render the real screen in [lang] on the chosen segment.
Future<Rendered> render(WidgetTester tester, EngineSim sim,
    {String lang = 'en', bool abs = false}) async {
  late ObdService obd;
  final settings = SettingsProvider();
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.setLanguage(lang);
    obd = ObdService(sim, faultTiming: fast);
    expect(await obd.connectBluetooth(simDevice), isTrue);
    await obd.readEngineDtcs();
    await obd.whenEngineReadSettled();
    if (abs) {
      await obd.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');
    }
  });
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<VehicleProvider>(create: (_) => VehicleProvider()),
      ChangeNotifierProvider<ObdService>.value(value: obd),
    ],
    child: const MaterialApp(home: DtcScreen(autoScan: false)),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  if (abs) {
    await tester.tap(find.text(t('moduleAbs', lang)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
      .toList();
  return Rendered(texts, obd, sim);
}

Future<void> finish(WidgetTester tester, Rendered r) async {
  await tester.runAsync(() async {
    await r.obd.disconnect();
    await r.sim.close();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A4 engine cards: Stored / Pending / Permanent, nothing unknown',
      (tester) async {
    final r = await render(
        tester,
        EngineSim(mode03: '7E8 06 43 02 01 33 04 20')
          ..extra['07'] = '7E8 06 47 02 01 33 03 01'
          ..extra['0A'] = '7E8 04 4A 01 04 20');
    expect(r.texts, containsAll(<String>['P0133', 'P0420', 'P0301']));
    expect(r.texts.where((x) => x == t('faultStatusStored')).length, 2);
    expect(r.texts.where((x) => x == t('faultStatusPending')).length, 2);
    expect(r.texts.where((x) => x == t('faultStatusPermanent')).length, 1);
    expect(r.has(t('faultStatusHistory')), isFalse, reason: 'never for OBD');
    expect(r.has(t('faultStatusActive')), isFalse, reason: 'unknown shows nothing');
    expect(r.has('3'), isTrue, reason: 'the CODES chip counts every card');
    await finish(tester, r);
  });

  testWidgets('A4 a pending-only code is not hidden behind "No Fault Codes Found"',
      (tester) async {
    final r = await render(
        tester, EngineSim(mode03: '7E8 02 43 00')..extra['07'] = '7E8 04 47 01 03 01');
    expect(r.has('P0301'), isTrue);
    expect(r.has(t('faultStatusPending')), isTrue);
    expect(r.has(t('noFaultCodes')), isFalse);
    await finish(tester, r);
  });

  testWidgets('A4 lamp chip and count mismatch note', (tester) async {
    final r = await render(
        tester,
        EngineSim(mode03: '7E8 04 43 01 01 33')
          ..extra['0101'] = '7E8 06 41 01 83 07 E5 00');
    expect(r.has(t('dtcEngineLampOn')), isTrue);
    expect(
        r.has(t('dtcCountMismatch')
            .replaceAll('{reported}', '3')
            .replaceAll('{received}', '1')),
        isTrue);
    await finish(tester, r);
  });

  testWidgets('A4 no lamp chip and no note when unknown', (tester) async {
    final r = await render(tester, EngineSim(mode03: '7E8 04 43 01 01 33'));
    expect(r.has(t('dtcEngineLampOn')), isFalse);
    expect(r.any('stored code(s) but sent'), isFalse);
    await finish(tester, r);
  });

  for (final lang in ['en', 'hi']) {
    testWidgets('A5 [$lang] low voltage: banner, and U-codes marked "may be false"',
        (tester) async {
      final r = await render(
          tester,
          EngineSim(mode03: '7E8 06 43 02 C1 00 01 33')
            ..extra['010C'] = '41 0C 00 00'
            ..extra['0142'] = '41 42 2B C0', // 11.2 V, engine off
          lang: lang);
      expect(r.has(t('batteryLowBanner', lang).replaceAll('{v}', '11.2')), isTrue);
      expect(r.texts.where((x) => x == t('mayBeFalseLowVoltage', lang)).length, 1,
          reason: 'only the U-code, not the P-code');
      expect(r.has('U0100'), isTrue);
      expect(r.has('P0133'), isTrue);
      await finish(tester, r);
    });
  }

  testWidgets('A5 normal voltage: no banner, no "may be false"', (tester) async {
    final r = await render(
        tester,
        EngineSim(mode03: '7E8 04 43 01 C1 00')
          ..extra['010C'] = '41 0C 00 00'
          ..extra['0142'] = '41 42 31 38'); // 12.6 V
    expect(r.any('Battery voltage is low'), isFalse);
    expect(r.has(t('mayBeFalseLowVoltage')), isFalse);
    await finish(tester, r);
  });

  testWidgets('A5 voltage unknown: no banner (unknown is never LOW)', (tester) async {
    final r = await render(tester, EngineSim(mode03: '7E8 04 43 01 C1 00'));
    expect(r.any('Battery voltage is low'), isFalse);
    expect(r.has(t('mayBeFalseLowVoltage')), isFalse);
    await finish(tester, r);
  });

  for (final rpm in ['41 0C 0F A0', '41 0C 00 00', null]) {
    testWidgets('A5 refusal wording, RPM reply $rpm', (tester) async {
      final sim = EngineSim(mode03: '7E8 03 7F 03 22');
      if (rpm == null) {
        sim.livePids.remove('010C');
      } else {
        sim.extra['010C'] = rpm;
      }
      final r = await render(tester, sim);
      expect(r.has(t('dtcRefusedTitle')), isTrue);
      expect(r.has(t('dtcRefusedBody')), isTrue);
      expect(r.has(t('dtcRefusedEngineRunning')), rpm == '41 0C 0F A0',
          reason: '"stop the engine" only when it is known to be running');
      await finish(tester, r);
    });
  }

  testWidgets('A3 module busy: its own wording, never "No Fault Codes Found"',
      (tester) async {
    final r = await render(
        tester,
        EngineSim(mode03: '7E8 02 43 00')
          ..personality = AdapterPersonality.passesPending
          ..busy['03'] = const ModuleBusy.forever());
    expect(r.has(t('dtcModuleBusyBody')), isTrue);
    expect(r.has(t('noFaultCodes')), isFalse);
    await finish(tester, r);
  });

  for (final lang in ['en', 'hi']) {
    testWidgets('A2 [$lang] ABS card: failure type and status labels',
        (tester) async {
      final r = await render(
          tester,
          EngineSim(mode03: '7E8 02 43 00')
            ..udsModules['7B0'] = '7B8 07 59 02 FF 50 58 11 89',
          lang: lang,
          abs: true);
      expect(r.has('C1058'), isTrue);
      expect(r.has('0x11 · ${lang == 'hi' ? 'सर्किट ग्राउंड से शॉर्ट' : 'Circuit short to ground'}'),
          isTrue);
      expect(r.has(t('faultStatusActive', lang)), isTrue);
      expect(r.has(t('faultStatusLamp', lang)), isTrue);
      expect(r.has(t('faultStatusHistory', lang)), isFalse);
      await finish(tester, r);
    });
  }

  testWidgets('A2 ABS: failure type 00 adds no row; an unlisted value is not guessed',
      (tester) async {
    final r = await render(
        tester,
        EngineSim(mode03: '7E8 02 43 00')
          ..udsModules['7B0'] = '7B8 0B 59 02 FF 50 58 00 08 50 15 3C 08',
        abs: true);
    expect(r.any('No sub-type'), isFalse);
    expect(r.has('0x3C · failure type 0x3C, no description'), isTrue);
    expect(r.texts.where((x) => x == t('faultStatusHistory')).length, 2);
    await finish(tester, r);
  });
}
