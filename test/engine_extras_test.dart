/// Phase 1A — A4 (pending and permanent codes, lamp and count), A5 (engine
/// state and battery voltage) and A6 (VIN), through the REAL ObdService over
/// the simulator. Core first: every extra is optional and bounded.
library;

import 'dart:io';

import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/services/fault_decoders.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:danlite_elm/services/session_recorder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_sim.dart';

const fast = FaultReadTiming.scaled(0.05);
const fakeVin = 'MA3FAKE0123456789';

/// `49 02 01` + the fake VIN as a three-frame CAN reply from 7E8.
const vinReply = '7E8 10 14 49 02 01 4D 41 33\r'
    '7E8 21 46 41 4B 45 30 31 32\r'
    '7E8 22 33 34 35 36 37 38 39';

Future<ObdService> readWithExtras(EngineSim sim,
    {FaultReadTiming timing = fast, SessionRecorder? recorder}) async {
  final obd = ObdService(sim, faultTiming: timing, recorder: recorder);
  expect(await obd.connectBluetooth(simDevice), isTrue);
  await obd.readEngineDtcs();
  await obd.whenEngineReadSettled();
  return obd;
}

Future<void> done(ObdService obd, EngineSim sim) async {
  await obd.disconnect();
  await sim.close();
}

class _Storage implements RecorderStorage {
  _Storage(this.dir);
  final Directory dir;
  @override
  Future<Directory> directory() async => dir;
  @override
  Future<void> shareText(String text, {required String subject}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A4 pending (07) and permanent (0A) merge', () {
    test('one card per code with the right status', () async {
      final sim = EngineSim(mode03: '7E8 06 43 02 01 33 04 20')
        ..extra['07'] = '7E8 06 47 02 01 33 03 01'
        ..extra['0A'] = '7E8 04 4A 01 04 20';
      final obd = await readWithExtras(sim);

      final byCode = {for (final r in obd.engineFaultRecords) r.code: r};
      expect(byCode.keys, ['P0133', 'P0420', 'P0301']);
      expect(byCode['P0133']!.status.confirmed, isTrue);
      expect(byCode['P0133']!.status.pending, isTrue);
      expect(byCode['P0420']!.status.confirmed, isTrue);
      expect(byCode['P0420']!.status.permanent, isTrue);
      expect(byCode['P0301']!.status.pending, isTrue);
      expect(byCode['P0301']!.status.confirmed, isNull);
      expect(byCode['P0301']!.module, '7E8');
      for (final r in byCode.values) {
        expect(r.status.history, isNull, reason: 'never History from OBD');
        expect(r.status.active, isNull, reason: 'active is unknown without UDS');
      }

      // Clear Codes still keys on the Mode 03 list only.
      expect(obd.dtcCodes.map((c) => c.code), ['P0133', 'P0420']);
      expect(obd.engineDisplayCodes.map((c) => c.code),
          ['P0133', 'P0420', 'P0301']);
      expect(obd.engineDisplayCodes.last.isPending, isTrue);
      await done(obd, sim);
    });

    test('unsupported 07 / 0A are Unsupported — not failure, not empty', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 01 33')
        ..extra['07'] = 'NO DATA'
        ..extra['0A'] = '7E8 03 7F 0A 11';
      final obd = await readWithExtras(sim);
      final report = obd.engineReport!;
      expect(report.pending, isA<ExtraUnsupported<List<FaultRecord>>>());
      expect(report.permanent, isA<ExtraUnsupported<List<FaultRecord>>>());
      expect((report.permanent as ExtraUnsupported).nrc, 0x11);
      expect(obd.lastEngineRead, isA<EngineAnswered>());
      expect(obd.engineDisplayCodes.map((c) => c.code), ['P0133']);
      await done(obd, sim);
    });

    test('a positive empty 07 is an empty list, and only that', () async {
      final sim = EngineSim(mode03: '7E8 02 43 00')
        ..extra['07'] = '7E8 02 47 00'
        ..extra['0A'] = '7E8 02 4A 00';
      final obd = await readWithExtras(sim);
      expect(obd.engineReport!.pending, isA<ExtraValue<List<FaultRecord>>>());
      expect(obd.engineReport!.pending.valueOrNull, isEmpty);
      expect(obd.engineDisplayCodes, isEmpty);
      await done(obd, sim);
    });

    test('a pending-only code is shown even when Mode 03 is empty', () async {
      final sim = EngineSim(mode03: '7E8 02 43 00')
        ..extra['07'] = '7E8 04 47 01 03 01';
      final obd = await readWithExtras(sim);
      expect(obd.dtcCodes, isEmpty);
      expect(obd.engineDisplayCodes.map((c) => c.code), ['P0301']);
      await done(obd, sim);
    });

    test('after the Mode 03 list changes, stale extras are not merged', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 01 33')
        ..extra['07'] = '7E8 04 47 01 03 01';
      final obd = await readWithExtras(sim);
      expect(obd.engineDisplayCodes.length, 2);
      // A new core read with a different list, extras not run this time.
      sim.mode03 = '7E8 02 43 00';
      await obd.readEngineDtcs(withExtras: false);
      expect(obd.engineDisplayCodes, isEmpty,
          reason: 'pending codes read alongside another list are not shown');
      await done(obd, sim);
    });
  });

  group('A4 lamp and stored-code count (PID 01 01)', () {
    test('lamp on; a count that disagrees with the list is recorded', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 01 33')
        ..extra['0101'] = '7E8 06 41 01 83 07 E5 00';
      final obd = await readWithExtras(sim);
      final r = obd.engineReport!;
      expect(r.lampOn, isTrue);
      expect(r.countMismatch, isNotNull);
      expect(r.countMismatch!.reported, 3);
      expect(r.countMismatch!.received, 1);
      await done(obd, sim);
    });

    test('a matching count is not a mismatch; lamp off is known false', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 01 33')
        ..extra['0101'] = '7E8 06 41 01 01 07 E5 00';
      final obd = await readWithExtras(sim);
      expect(obd.engineReport!.lampOn, isFalse);
      expect(obd.engineReport!.countMismatch, isNull);
      await done(obd, sim);
    });

    test('unsupported 01 01: lamp unknown, no mismatch claimed', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 01 33');
      final obd = await readWithExtras(sim);
      expect(obd.engineReport!.lampOn, isNull);
      expect(obd.engineReport!.countMismatch, isNull);
      await done(obd, sim);
    });
  });

  group('A4 core first, bounded, cancellable', () {
    test('slow extras never delay the core result', () async {
      // Only commands the live-data poll never sends are slowed, so the
      // measurement is about the extras and nothing else.
      const slow = Duration(milliseconds: 300);
      final sim = EngineSim(mode03: '7E8 04 43 01 01 33')
        ..extra['0101'] = '7E8 06 41 01 81 00 00 00'
        ..extra['07'] = '7E8 02 47 00'
        ..latency.addAll({'0101': slow, '07': slow, '0A': slow, '0902': slow});
      final obd = ObdService(sim, faultTiming: const FaultReadTiming.scaled(0.4));
      expect(await obd.connectBluetooth(simDevice), isTrue);

      final watch = Stopwatch()..start();
      final core = await obd.readEngineDtcs();
      final coreMs = watch.elapsedMilliseconds;
      expect(core, isA<EngineAnswered>());
      expect((core as EngineAnswered).codes.single.code, 'P0133');
      expect(obd.engineExtrasInFlight, isTrue,
          reason: 'the core result is out before the extras finish');
      expect(coreMs, lessThan(300), reason: 'core took ${coreMs}ms');

      await obd.whenEngineReadSettled();
      expect(watch.elapsedMilliseconds, greaterThan(coreMs + 1000),
          reason: 'the extras really were slow; the core did not wait for them');
      expect(obd.engineExtrasInFlight, isFalse);
      expect(obd.engineReport!.inProgress, isFalse);
      expect(obd.engineReport!.lampOn, isTrue);
      expect(obd.lastEngineRead, same(core), reason: 'extras never replace the core');
      await done(obd, sim);
    });

    test('extras that never answer: every one accounted for, none a value', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 01 33')
        ..extra.addAll({'0101': null, '07': null, '0A': null, '0902': null});
      final obd = ObdService(sim, faultTiming: fast);
      expect(await obd.connectBluetooth(simDevice), isTrue);
      final watch = Stopwatch()..start();
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
      final total = watch.elapsed;
      expect(total, lessThan(fast.engineReadBudget + const Duration(milliseconds: 400)),
          reason: 'took ${total.inMilliseconds}ms');
      final r = obd.engineReport!;
      expect(r.mil, isA<ExtraNoAnswer<MilStatus>>());
      expect(r.pending, isA<ExtraNoAnswer<List<FaultRecord>>>());
      expect(r.permanent, isA<ExtraNoAnswer<List<FaultRecord>>>());
      expect(r.vin, isA<ExtraNoAnswer<Vin>>());
      expect(obd.lastEngineRead, isA<EngineAnswered>());
      expect(obd.engineDisplayCodes.map((c) => c.code), ['P0133'],
          reason: 'a failing extra never blanks the core result');
      await done(obd, sim);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a module busy for ever on Mode 07 uses up the budget, never more', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 01 33')
        ..personality = AdapterPersonality.passesPending
        ..extra['07'] = '7E8 02 47 00'
        ..busy['07'] = const ModuleBusy.forever();
      final obd = ObdService(sim, faultTiming: fast);
      expect(await obd.connectBluetooth(simDevice), isTrue);
      final watch = Stopwatch()..start();
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
      final total = watch.elapsed;
      // The budget, plus a small allowance for putting the adapter back.
      expect(total, lessThan(fast.engineReadBudget + const Duration(milliseconds: 400)),
          reason: 'took ${total.inMilliseconds}ms');
      final r = obd.engineReport!;
      expect(r.pending, isA<ExtraNoAnswer<List<FaultRecord>>>());
      expect((r.pending as ExtraNoAnswer).reason, 'module kept reporting busy');
      for (final later in <ExtraRead<Object?>>[r.permanent, r.rpm, r.voltage, r.vin]) {
        expect(later, isA<ExtraSkipped<Object?>>());
        expect((later as ExtraSkipped).reason, 'time budget used up');
      }
      expect(obd.lastEngineRead, isA<EngineAnswered>());
      await done(obd, sim);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('the worst-case total is a named 15-second constant', () {
      expect(kEngineReadBudget, const Duration(seconds: 15));
      expect(const FaultReadTiming().engineReadBudget, kEngineReadBudget);
      expect(kExtraCommandWindow, lessThan(kEngineReadBudget));
    });

    test('cancel: extras stop, the core result and adapter state are kept', () async {
      const slow = Duration(milliseconds: 150);
      final sim = EngineSim(mode03: '7E8 04 43 01 01 33')
        ..latency.addAll({'0101': slow, '07': slow, '0A': slow, '010C': slow});
      final obd = ObdService(sim, faultTiming: const FaultReadTiming.scaled(0.4));
      expect(await obd.connectBluetooth(simDevice), isTrue);
      final core = await obd.readEngineDtcs();
      obd.cancelEngineExtras();
      await obd.whenEngineReadSettled();
      expect(obd.lastEngineRead, same(core));
      final r = obd.engineReport!;
      expect(r.inProgress, isFalse);
      expect(r.stoppedEarly, isTrue);
      expect(r.vin, isA<ExtraCancelled<Vin>>());
      // The live baseline is restored after the extras: headers back off.
      final afterCore = sim.wire.sublist(sim.wire.lastIndexOf('03'));
      expect(afterCore, contains('ATH0'));
      expect(afterCore.where((c) => c == '0902'), isEmpty);
      // The next read runs them again, because they were stopped early.
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
      expect(obd.engineReport!.stoppedEarly, isFalse);
      await done(obd, sim);
    });

    test('Clear Codes takes the link from running extras; nothing interleaves', () async {
      const slow = Duration(milliseconds: 120);
      final sim = EngineSim(mode03: '7E8 04 43 01 01 33')
        ..latency.addAll({'0101': slow, '07': slow, '0A': slow, '010C': slow, '0142': slow});
      final obd = ObdService(sim, faultTiming: const FaultReadTiming.scaled(0.4));
      expect(await obd.connectBluetooth(simDevice), isTrue);
      await obd.readEngineDtcs();
      expect(obd.engineExtrasInFlight, isTrue);
      final cleared = await obd.clearDtcs();
      expect(cleared, isTrue);
      expect(obd.lastClearOutcome, ClearDtcsOutcome.cleared);
      final from04 = sim.wire.sublist(sim.wire.indexOf('04'));
      const extras = ['0101', '07', '0A', '010C', '0142', 'ATRV', '0902', '0904'];
      expect(from04.where(extras.contains), isEmpty,
          reason: 'no extra command after the erase was sent');
      await done(obd, sim);
    });

    test('the 5-second auto re-read does not repeat the extras', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 01 33');
      final obd = await readWithExtras(sim);
      final before = sim.wire.where((c) => c == '07').length;
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
      expect(sim.wire.where((c) => c == '07').length, before);
      await obd.readEngineDtcs(forceExtras: true);
      await obd.whenEngineReadSettled();
      expect(sim.wire.where((c) => c == '07').length, before + 1,
          reason: 'a manual read runs them again');
      await done(obd, sim);
    });

    test('no extras when the bike did not answer', () async {
      final sim = EngineSim(mode03: 'NO DATA');
      final obd = await readWithExtras(sim);
      expect(obd.engineReport, isNull);
      expect(sim.wire, isNot(contains('07')));
      await done(obd, sim);
    });
  });

  group('A5 engine state and voltage', () {
    Future<EngineReport> report(Map<String, String> extra, {String? atrv}) async {
      final sim = EngineSim(mode03: '7E8 02 43 00')..atrv = atrv;
      sim.livePids.remove('010C');
      sim.extra.addAll(extra);
      final obd = await readWithExtras(sim);
      final r = obd.engineReport!;
      await done(obd, sim);
      return r;
    }

    test('RPM sets the engine state; no reply is unknown, never "off"', () async {
      expect((await report({'010C': '41 0C 0F A0'})).engineState, EngineState.running);
      expect((await report({'010C': '41 0C 00 00'})).engineState, EngineState.off);
      expect((await report({})).engineState, EngineState.unknown);
    });

    test('PID 01 42 voltage, thresholds by engine state', () async {
      // 12.0 V: fine with the engine off, LOW with it running.
      final off = await report({'010C': '41 0C 00 00', '0142': '41 42 2E E0'});
      expect(off.voltage.valueOrNull!.volts, closeTo(12.0, 1e-9));
      expect(off.voltage.valueOrNull!.source, VoltageSource.modulePid42);
      expect(off.voltageLevel, VoltageLevel.normal);
      final running = await report({'010C': '41 0C 0F A0', '0142': '41 42 2E E0'});
      expect(running.voltageLevel, VoltageLevel.low);
      // 11.5 V with the engine off is LOW; 15.5 V is HIGH.
      expect((await report({'010C': '41 0C 00 00', '0142': '41 42 2C EC'})).lowVoltage,
          isTrue);
      expect((await report({'0142': '41 42 3C 8C'})).voltageLevel, VoltageLevel.high);
    });

    test('falls back to ATRV when PID 01 42 is unsupported', () async {
      final r = await report({'010C': '41 0C 00 00'}, atrv: '11.2V');
      expect(r.voltage.valueOrNull!.source, VoltageSource.adapterAtRv);
      expect(r.voltage.valueOrNull!.volts, 11.2);
      expect(r.lowVoltage, isTrue);
    });

    test('no voltage at all is unknown, never LOW', () async {
      final r = await report({});
      expect(r.voltage.valueOrNull, isNull);
      expect(r.lowVoltage, isFalse);
    });

    test('thresholds are the named constants', () {
      expect(kLowVoltageEngineOff, 11.8);
      expect(kLowVoltageEngineRunning, 12.5);
      expect(kHighVoltage, 15.0);
      expect(classifyVoltage(11.79, EngineState.off), VoltageLevel.low);
      expect(classifyVoltage(11.8, EngineState.off), VoltageLevel.normal);
      expect(classifyVoltage(12.49, EngineState.running), VoltageLevel.low);
      expect(classifyVoltage(11.79, EngineState.unknown), VoltageLevel.low);
      expect(classifyVoltage(15.01, EngineState.off), VoltageLevel.high);
    });

    test('a refused read still learns the engine is running', () async {
      final sim = EngineSim(mode03: '7E8 03 7F 03 22')
        ..extra['010C'] = '41 0C 0F A0';
      final obd = await readWithExtras(sim);
      expect(obd.lastEngineRead, isA<EngineRefused>());
      expect(obd.engineReport!.engineState, EngineState.running);
      await done(obd, sim);
    });
  });

  group('A6 VIN through the service', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('danlite_vin_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('read once per connection, kept in memory, never in any log', () async {
      final printed = <String>[];
      final original = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => printed.add(m ?? '');
      addTearDown(() => debugPrint = original);

      final recorder = SessionRecorder(storage: _Storage(tmp));
      await recorder.setEnabled(true);
      final sim = EngineSim(mode03: '7E8 04 43 01 01 33')..extra['0902'] = vinReply;
      final obd = await readWithExtras(sim, recorder: recorder);

      final vin = obd.session!.vin!;
      expect(vin.value, fakeVin);
      expect(obd.engineReport!.vin.valueOrNull, vin);
      expect('${obd.engineReport!.vin.valueOrNull}', '[VIN masked]');

      // A second read does not ask again.
      await obd.readEngineDtcs(forceExtras: true);
      await obd.whenEngineReadSettled();
      expect(sim.wire.where((c) => c == '0902').length, 1);

      final hexVin = fakeVin.codeUnits
          .map((b) => b.toRadixString(16).toUpperCase())
          .join(' ');
      bool leaks(String s) =>
          s.contains(fakeVin) || s.contains('4D 41 33') || s.contains(hexVin);

      expect(obd.wireLog.where(leaks), isEmpty, reason: 'in-memory wire ring');
      expect(obd.exportWireLog(), isNot(contains('46 41 4B 45')));
      expect(printed.where(leaks), isEmpty, reason: 'debugPrint');
      await obd.disconnect();
      final file = recorder.lastRecording!;
      final text = file.readAsStringSync();
      expect(leaks(text), isFalse, reason: 'recorder file');
      expect(text, contains('vin: read'));
      expect(obd.session, isNull, reason: 'the VIN goes with the session');
      await sim.close();
    });

    test('an invalid VIN is never kept', () async {
      final sim = EngineSim(mode03: '7E8 02 43 00')
        ..extra['0902'] = '7E8 10 14 49 02 01 4D 41 33\r'
            '7E8 21 46 41 4B 45 49 31 32\r' // contains I
            '7E8 22 33 34 35 36 37 38 39';
      final obd = await readWithExtras(sim);
      expect(obd.session!.vin, isNull);
      expect(obd.engineReport!.vin, isA<ExtraNoAnswer<Vin>>());
      await done(obd, sim);
    });

    test('unsupported Mode 09 is asked once per connection', () async {
      final sim = EngineSim(mode03: '7E8 02 43 00');
      final obd = await readWithExtras(sim);
      expect(obd.engineReport!.vin, isA<ExtraUnsupported<Vin>>());
      await obd.readEngineDtcs(forceExtras: true);
      await obd.whenEngineReadSettled();
      expect(sim.wire.where((c) => c == '0902').length, 1);
      await done(obd, sim);
    });
  });
}
