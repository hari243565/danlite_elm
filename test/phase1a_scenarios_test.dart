/// Phase 1A — A8: one named test per scenario this phase affects (numbering
/// from chore/fault-audit docs/faults/SCENARIO_COVERAGE.md). Each runs the
/// REAL ObdService over a replay fixture or the simulator, and where the
/// scenario is about what the rider reads, renders the REAL DtcScreen.
library;

import 'dart:io';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/dtc_screen.dart';
import 'package:danlite_elm/services/bluetooth_classic_service.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/engine_sim.dart';
import 'support/replay_transport.dart';

const fast = FaultReadTiming.scaled(0.05);

String en(String key) => AppStrings.get(key, 'en');

ReplayTransport fixture(String name, {double scale = 1.0}) => ReplayTransport(
    Transcript.load(File('test/fixtures/replay/$name')),
    timeScale: scale);

Future<ObdService> connect(BluetoothClassicService t,
    {FaultReadTiming timing = fast}) async {
  final obd = ObdService(t, faultTiming: timing);
  expect(await obd.connectBluetooth(simDevice), isTrue);
  return obd;
}

/// Render the real screen against [obd]; [abs] switches to the ABS segment.
Future<List<String>> screenTexts(WidgetTester tester, ObdService obd,
    {bool abs = false}) async {
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>(create: (_) => SettingsProvider()),
      ChangeNotifierProvider<VehicleProvider>(create: (_) => VehicleProvider()),
      ChangeNotifierProvider<ObdService>.value(value: obd),
    ],
    // A fresh screen each time, so a previous render's tab does not carry over.
    child: MaterialApp(home: DtcScreen(key: UniqueKey(), autoScan: false)),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  if (abs) {
    await tester.tap(find.text(en('moduleAbs')));
    await tester.pump(const Duration(milliseconds: 50));
  }
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Scenario 3 — engine running vs off: the refusal says "stop the '
      'engine" only when the engine is known to be running', (tester) async {
    late ObdService running;
    late ObdService off;
    late ReplayTransport t;
    late EngineSim sim;
    await tester.runAsync(() async {
      t = fixture('engine_running_refusal.txt');
      running = await connect(t, timing: const FaultReadTiming());
      await running.readEngineDtcs();
      await running.whenEngineReadSettled();
      sim = EngineSim(mode03: '7E8 03 7F 03 22')..extra['010C'] = '41 0C 00 00';
      off = await connect(sim);
      await off.readEngineDtcs();
      await off.whenEngineReadSettled();
    });
    expect(running.engineReport!.engineState, EngineState.running);
    expect(off.engineReport!.engineState, EngineState.off);

    var texts = await screenTexts(tester, running);
    expect(texts, contains(en('dtcRefusedTitle')));
    expect(texts, contains(en('dtcRefusedEngineRunning')));
    expect(texts, isNot(contains(en('noFaultCodes'))));

    texts = await screenTexts(tester, off);
    expect(texts, contains(en('dtcRefusedTitle')));
    expect(texts, isNot(contains(en('dtcRefusedEngineRunning'))));

    await tester.runAsync(() async {
      await running.disconnect();
      await off.disconnect();
      await t.close();
      await sim.close();
    });
  });

  testWidgets('Scenario 8 — response pending: the real answer is never '
      'discarded, and a module busy for ever is never "no faults"',
      (tester) async {
    late ObdService clone;
    late ObdService genuine;
    late ObdService busy;
    late ReplayTransport t1;
    late ReplayTransport t2;
    late EngineSim sim;
    await tester.runAsync(() async {
      // Clone adapter: passes 7F 19 78 through; the answer comes on re-send.
      t1 = fixture('adapter_passes_pending.txt');
      clone = await connect(t1, timing: const FaultReadTiming());
      await clone.readEngineDtcs();
      await clone.whenEngineReadSettled();
      await clone.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');
      // Genuine adapter: waits internally; the answer is just late.
      t2 = fixture('adapter_handles_pending.txt', scale: 0.2);
      genuine = await connect(t2, timing: const FaultReadTiming.scaled(0.2));
      await genuine.readEngineDtcs();
      await genuine.whenEngineReadSettled();
      await genuine.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');
      // A module that never stops answering "pending".
      sim = EngineSim(mode03: '7E8 02 43 00')
        ..personality = AdapterPersonality.passesPending
        ..busy['03'] = const ModuleBusy.forever();
      busy = await connect(sim);
      await busy.readEngineDtcs();
    });

    expect(clone.chassisDtcCodes.map((c) => c.code), ['C1058']);
    expect(clone.session!.adapterPassesPending, isTrue);
    expect(genuine.chassisDtcCodes.map((c) => c.code), ['C1058']);
    expect(genuine.session!.adapterPassesPending, isFalse);
    expect((genuine.lastEngineRead as EngineAnswered).codes.single.code, 'P0133');
    expect((busy.lastEngineRead as EngineNoAnswer).reason,
        EngineNoAnswerReason.moduleBusy);

    var texts = await screenTexts(tester, clone, abs: true);
    expect(texts, contains('C1058'));
    texts = await screenTexts(tester, busy);
    expect(texts, contains(en('dtcModuleBusyBody')));
    expect(texts, isNot(contains(en('noFaultCodes'))));

    await tester.runAsync(() async {
      for (final o in [clone, genuine, busy]) {
        await o.disconnect();
      }
      await t1.close();
      await t2.close();
      await sim.close();
    });
  });

  testWidgets('Scenario 11 — multi-frame: long code lists and the VIN are '
      'reassembled; a reply cut short is never shown as complete',
      (tester) async {
    late ObdService full;
    late ObdService cut;
    late ObdService vin;
    late EngineSim s1;
    late EngineSim s2;
    late ReplayTransport t;
    await tester.runAsync(() async {
      // Five codes: first frame + one consecutive frame.
      s1 = EngineSim(
          mode03: '7E8 10 0C 43 05 01 33 03 01\r7E8 21 01 13 02 34 C1 00 00');
      full = await connect(s1);
      await full.readEngineDtcs(withExtras: false);
      // The same reply with the consecutive frame missing, twice.
      s2 = EngineSim(mode03: '7E8 10 0C 43 05 01 33 03 01');
      cut = await connect(s2);
      await cut.readEngineDtcs(withExtras: false);
      t = fixture('multiframe_vin.txt');
      vin = await connect(t, timing: const FaultReadTiming());
      await vin.readEngineDtcs();
      await vin.whenEngineReadSettled();
    });

    expect(full.dtcCodes.map((c) => c.code),
        ['P0133', 'P0301', 'P0113', 'P0234', 'U0100']);
    expect(full.engineCountMismatch, isNull);
    expect(cut.engineCountMismatch, isNotNull,
        reason: 'the count byte says 5 and only 2 arrived');
    expect(cut.engineCountMismatch!.reported, 5);
    expect(cut.engineCountMismatch!.received, 2);
    expect(vin.session!.vin!.value, 'MA3FAKE0123456789');

    final texts = await screenTexts(tester, cut);
    expect(
        texts,
        contains(en('dtcCountMismatch')
            .replaceAll('{reported}', '5')
            .replaceAll('{received}', '2')));

    await tester.runAsync(() async {
      for (final o in [full, cut, vin]) {
        await o.disconnect();
      }
      await s1.close();
      await s2.close();
      await t.close();
    });
  });

  testWidgets('Scenario 12 — low battery: banner, and network codes marked as '
      'possibly false; the scan is not blocked', (tester) async {
    late ObdService obd;
    late ReplayTransport t;
    await tester.runAsync(() async {
      t = fixture('low_voltage.txt');
      obd = await connect(t, timing: const FaultReadTiming());
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
    });
    expect(obd.lastEngineRead, isA<EngineAnswered>(), reason: 'never blocked');
    expect(obd.batteryVoltageLow, isTrue);

    final texts = await screenTexts(tester, obd);
    expect(texts, contains(en('batteryLowBanner').replaceAll('{v}', '11.2')));
    expect(texts.where((x) => x == en('mayBeFalseLowVoltage')).length, 1);
    expect(texts, containsAll(<String>['U0100', 'P0133']));

    await tester.runAsync(() async {
      await obd.disconnect();
      await t.close();
    });
  });

  testWidgets('Scenario 14 — pending and permanent codes are read, merged and '
      'labelled; unsupported is neither failure nor empty', (tester) async {
    late ObdService both;
    late ObdService unsupported;
    late EngineSim s1;
    late EngineSim s2;
    await tester.runAsync(() async {
      s1 = EngineSim(mode03: '7E8 04 43 01 01 33')
        ..extra['07'] = '7E8 04 47 01 03 01'
        ..extra['0A'] = '7E8 04 4A 01 01 33';
      both = await connect(s1);
      await both.readEngineDtcs();
      await both.whenEngineReadSettled();
      s2 = EngineSim(mode03: '7E8 04 43 01 01 33');
      unsupported = await connect(s2);
      await unsupported.readEngineDtcs();
      await unsupported.whenEngineReadSettled();
    });

    final records = {for (final r in both.engineFaultRecords) r.code: r};
    expect(records['P0133']!.sources, {ReadSource.mode03, ReadSource.mode0A});
    expect(records['P0301']!.sources, {ReadSource.mode07});

    var texts = await screenTexts(tester, both);
    expect(texts, containsAll(<String>[
      'P0133', 'P0301', en('faultStatusStored'), en('faultStatusPending'),
      en('faultStatusPermanent'),
    ]));
    expect(texts, isNot(contains(en('faultStatusHistory'))));

    expect(unsupported.engineReport!.pending, isA<ExtraUnsupported<List<FaultRecord>>>());
    texts = await screenTexts(tester, unsupported);
    expect(texts, contains('P0133'));
    expect(texts, isNot(contains(en('faultStatusPending'))));
    expect(texts, isNot(contains(en('dtcNoAnswerTitle'))),
        reason: 'unsupported extras are not shown as a failure');

    await tester.runAsync(() async {
      await both.disconnect();
      await unsupported.disconnect();
      await s1.close();
      await s2.close();
    });
  });

  testWidgets('Scenario 17 — two-byte engine codes and three-byte ABS codes on '
      'one bike stay apart, each in its own format', (tester) async {
    late ObdService obd;
    late ReplayTransport t;
    await tester.runAsync(() async {
      t = fixture('mixed_2byte_3byte.txt');
      obd = await connect(t, timing: const FaultReadTiming());
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
      await obd.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');
    });

    final engine = obd.dtcCodes.single.record!;
    expect(engine.format, DtcFormat.sae2);
    expect(engine.rawBytes, [0x01, 0x33]);
    expect(engine.displayCode, 'P0133');
    final abs = obd.chassisDtcCodes.single.record!;
    expect(abs.format, DtcFormat.uds3);
    expect(abs.rawBytes, [0x50, 0x58, 0x11]);
    expect(abs.displayCode, 'C1058-11');
    expect(abs.statusByte, 0x2F);
    expect(obd.dtcCodes.map((c) => c.code), isNot(contains('C1058')));

    final texts = await screenTexts(tester, obd, abs: true);
    expect(texts, contains('C1058'));
    expect(texts, contains('0x11 · Circuit short to ground'));
    expect(texts, contains(en('faultStatusActive')));

    await tester.runAsync(() async {
      await obd.disconnect();
      await t.close();
    });
  });
}
