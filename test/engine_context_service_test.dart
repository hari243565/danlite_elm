/// Phase A-4 (C1–C3, C4) — the on-demand context read, through the REAL
/// [ObdService] over the simulator: Mode 02 supported and unsupported, no
/// snapshot, partial support, 29-bit CAN headers, response pending on both
/// adapter types, silence — and the rules that keep it out of the way (never
/// part of a scan, never during Clear Codes or an ABS scan, a rider's manual
/// read and Clear preempt it, nothing stale is shown).
library;


import 'package:danlite_elm/services/engine_context.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import 'support/context_sim.dart';
import 'support/engine_sim.dart';

const fast = FaultReadTiming.scaled(0.05);

Future<ObdService> start(EngineSim sim, {FaultReadTiming timing = fast}) async {
  final obd = await connectSim(sim, timing: timing);
  return obd;
}

Future<void> finish(ObdService obd, EngineSim sim) async {
  await obd.disconnect();
  await sim.close();
}

FreezeFrameSnapshot answered(ObdService obd) {
  final r = obd.freezeFrameResult;
  expect(r, isA<FreezeFrameAnswered>(), reason: '$r');
  return (r as FreezeFrameAnswered).snapshot;
}

List<String> contextWire(EngineSim sim) =>
    sim.wire.where((c) => isContextCommand(c)).toList();

void main() {
  group('C1 an answered snapshot', () {
    test('trigger code, the fixed set in order, units, and the time', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      final before = DateTime.now();
      await obd.readEngineContext();
      final s = answered(obd);
      expect(s.triggerCode, 'P0301');
      expect(s.unreadPids, isEmpty);
      expect(s.supportListUnreadable, isFalse);
      expect(s.values.map((v) => v.pid.pid).toList(),
          [0x03, 0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0F, 0x11, 0x42]);
      SnapshotNumber n(SnapshotPid p) =>
          s.values.firstWhere((v) => v.pid == p) as SnapshotNumber;
      expect(n(SnapshotPid.rpm).value, 1000);
      expect(n(SnapshotPid.rpm).unit, 'RPM');
      expect(n(SnapshotPid.coolant).value, 83);
      expect(n(SnapshotPid.speed).value, 60);
      expect(n(SnapshotPid.moduleVoltage).value, closeTo(14.0, 0.001));
      expect((s.values.first as SnapshotFuelSystem).system1, FuelStatusKind.closedLoop);
      expect(s.readAt.isBefore(before), isFalse);
      await finish(obd, sim);
    });

    test('counters and self-checks come from the same read', () async {
      final sim = EngineSim()
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineContext();
      final c = obd.contextCounters!;
      expect((c.lampDistance as ExtraValue<CounterValue>).value.value, 120);
      expect((c.clearedDistance as ExtraValue<CounterValue>).value.value, 480);
      expect((c.lampTime as ExtraValue<CounterValue>).value.value, 95);
      expect((c.clearedTime as ExtraValue<CounterValue>).value.value, 310);
      expect((c.warmUps as ExtraValue<CounterValue>).value.value, 7);
      final r = (obd.readinessRead!.result as ExtraValue<ReadinessReport>).value;
      expect(r.states[Monitor.misfire], MonitorState.complete);
      expect(r.states[Monitor.evaporative], MonitorState.notComplete);
      expect(r.states[Monitor.heatedCatalyst], MonitorState.notSupported);
      expect(obd.contextLampOn, isTrue);
      await finish(obd, sim);
    });

    test('29-bit CAN headers decode the same', () async {
      final sim = EngineSim()
        ..extra.addAll(snapshotBike(can29: true))
        ..extra.addAll(contextBike(can29: true));
      final obd = await start(sim);
      await obd.readEngineContext();
      expect(answered(obd).triggerCode, 'P0301');
      expect(answered(obd).values.length, 11);
      expect((obd.contextCounters!.lampDistance as ExtraValue<CounterValue>).value.value, 120);
      await finish(obd, sim);
    });

    test('only the values the bike keeps are asked for and shown', () async {
      final sim = EngineSim()
        ..extra.addAll(snapshotBike(only: {0x04, 0x05, 0x0C}))
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineContext();
      final s = answered(obd);
      expect(s.values.map((v) => v.pid.pid).toList(), [0x04, 0x05, 0x0C]);
      expect(s.unreadPids, isEmpty, reason: 'not kept is absent, not "unread"');
      // Nothing outside the support list was requested.
      final asked = sim.wire.where((c) => c.startsWith('02')).toSet();
      expect(asked, {'020200', '020000', '020400', '020500', '020C00'});
      await finish(obd, sim);
    });

    test('a value that is kept but never answers is "unread", not absent', () async {
      final sim = EngineSim()
        ..extra.addAll(snapshotBike(only: {0x04, 0x05}, replies: {'020500': null}))
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineContext();
      final s = answered(obd);
      expect(s.values.map((v) => v.pid.pid).toList(), [0x04]);
      expect(s.unreadPids, [0x05]);
      expect(s.incomplete, isTrue);
      await finish(obd, sim);
    });

    test('a support list that cannot be read leaves the trigger code and says so', () async {
      final sim = EngineSim()
        ..extra.addAll(snapshotBike(replies: {'020000': null}))
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineContext();
      final s = answered(obd);
      expect(s.triggerCode, 'P0301');
      expect(s.values, isEmpty);
      expect(s.supportListUnreadable, isTrue);
      await finish(obd, sim);
    });
  });

  group('C1 the four honest outcomes that are not an answer', () {
    test('PID 02 = 0000 is NoSnapshot, and nothing else of Mode 02 is asked', () async {
      final sim = EngineSim()
        ..extra.addAll(noSnapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineContext();
      expect(obd.freezeFrameResult, isA<FreezeFrameNoSnapshot>());
      expect(sim.wire.where((c) => c.startsWith('02')).toList(), ['020200'],
          reason: 'every other Mode 02 value is meaningless without a snapshot');
      // The counters are still read: they do not depend on the snapshot.
      expect(obd.contextCounters, isNotNull);
      await finish(obd, sim);
    });

    test('NO DATA from a bike that has answered is Unsupported', () async {
      final sim = EngineSim()
        ..extra.addAll(mode02Unsupported())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineContext();
      expect(obd.freezeFrameResult, isA<FreezeFrameUnsupported>());
      await finish(obd, sim);
    });

    test('silence is NoAnswer — never "no snapshot", never "unsupported"', () async {
      final sim = EngineSim()
        ..extra['020200'] = null
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineContext();
      final r = obd.freezeFrameResult;
      expect(r, isA<FreezeFrameNoAnswer>());
      expect(r, isNot(isA<FreezeFrameNoSnapshot>()));
      expect(r, isNot(isA<FreezeFrameUnsupported>()));
      await finish(obd, sim);
    });

    test('a refusal that is not "not supported" is Refused with its code', () async {
      final sim = EngineSim()
        ..extra['020200'] = '7E8 03 7F 02 22'
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineContext();
      final r = obd.freezeFrameResult;
      expect(r, isA<FreezeFrameRefused>());
      expect((r as FreezeFrameRefused).nrc, 0x22);
      await finish(obd, sim);
    });

    test('a refusal that says "not supported" is Unsupported', () async {
      final sim = EngineSim()
        ..extra['020200'] = '7E8 03 7F 02 12'
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineContext();
      expect(obd.freezeFrameResult, isA<FreezeFrameUnsupported>());
      await finish(obd, sim);
    });

    test('the link going away is LinkLost', () async {
      final sim = EngineSim()..extra.addAll(snapshotBike());
      final obd = await start(sim);
      sim.dropLink();
      await obd.readEngineContext();
      expect(obd.freezeFrameResult, isA<FreezeFrameLinkLost>());
      await finish(obd, sim);
    });

    test('an older (K-line) bus is not read at all and says so', () async {
      final sim = EngineSim(protocol: 'A3')..extra.addAll(snapshotBike());
      final obd = await start(sim);
      await obd.readEngineContext();
      expect(obd.freezeFrameResult, isA<FreezeFrameGated>());
      expect(contextWire(sim), isEmpty, reason: 'K-line stays off: nothing was sent');
      await finish(obd, sim);
    });
  });

  group('response pending', () {
    for (final personality in AdapterPersonality.values) {
      test('${personality.name}: a module that is busy a while, then answers', () async {
        final sim = EngineSim()
          ..personality = personality
          ..extra.addAll(snapshotBike(only: {0x04}))
          ..extra.addAll(contextBike())
          ..busy['020200'] = const ModuleBusy(times: 2);
        final obd = await start(sim);
        await obd.readEngineContext();
        expect(answered(obd).triggerCode, 'P0301');
        await finish(obd, sim);
      });

      test('${personality.name}: a module that stays busy is NoAnswer (busy), not "no snapshot"',
          () async {
        final sim = EngineSim()
          ..personality = personality
          ..extra.addAll(snapshotBike())
          ..extra.addAll(contextBike())
          ..busy['020200'] = const ModuleBusy.forever();
        final obd = await start(sim);
        await obd.readEngineContext();
        expect(obd.freezeFrameResult, isA<FreezeFrameNoAnswer>());
        await finish(obd, sim);
      });
    }
  });

  group('C2 counters: each is its own state', () {
    test('an unsupported counter is silent, a silent one is not', () async {
      final sim = EngineSim()
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike(replies: {
          '0121': 'NO DATA', // this bike does not have it
          '0131': null, // asked, no answer
        }));
      final obd = await start(sim);
      await obd.readEngineContext();
      final c = obd.contextCounters!;
      expect(c.lampDistance, isA<ExtraUnsupported<CounterValue>>());
      expect(c.clearedDistance, isA<ExtraNoAnswer<CounterValue>>());
      expect(c.lampTime, isA<ExtraValue<CounterValue>>());
      expect(c.anyUnanswered, isTrue);
      await finish(obd, sim);
    });

    test('the maximum is "at least"', () async {
      final sim = EngineSim()
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike(replies: {'0131': frame('41 31 FF FF')}));
      final obd = await start(sim);
      await obd.readEngineContext();
      final v = (obd.contextCounters!.clearedDistance as ExtraValue<CounterValue>).value;
      expect(v.value, 65535);
      expect(v.atLeast, isTrue);
      await finish(obd, sim);
    });
  });

  group('a silent bike costs two windows, not the whole list', () {
    test('only the first requests of each group are sent', () async {
      final sim = EngineSim()
        ..extra.addAll(<String, String?>{
          for (final c in [
            '020200', '020000', '024000', '0101', '0121', '0131', '014D', '014E', '0130'
          ])
            c: null,
        });
      final obd = await start(sim);
      final clock = Stopwatch()..start();
      await obd.readEngineContext();
      clock.stop();
      expect(obd.freezeFrameResult, isA<FreezeFrameNoAnswer>());
      expect(obd.readinessRead!.result, isA<ExtraNoAnswer<ReadinessReport>>());
      final c = obd.contextCounters!;
      for (final k in ContextCounter.values) {
        expect(c.of(k), isA<ExtraNoAnswer<CounterValue>>(), reason: '$k');
      }
      final sent = contextWire(sim);
      expect(sent, ['020200', '0101'], reason: 'two requests, then the verdict');
      expect(clock.elapsed, lessThan(fast.contextReadBudget));
      await finish(obd, sim);
    });
  });

  group('never part of a scan', () {
    test('a plain engine read sends no Mode 02 request and no counter request', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
      final sent = sim.wire.where(isContextCommand).toList();
      // 0101 is the existing lamp extra; nothing else of the context is read.
      expect(sent.where((c) => c != '0101'), isEmpty);
      expect(obd.freezeFrameResult, isNull);
      expect(obd.contextCounters, isNull);
      expect(obd.readinessRead, isNull);
      await finish(obd, sim);
    });

    test('the core stored-code result is out before any context command', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      final core = await obd.readEngineDtcs(withExtras: false);
      expect(core, isA<EngineAnswered>());
      expect(sim.wire.where(isContextCommand), isEmpty,
          reason: 'the core read asked nothing of the context');
      await obd.readEngineContext();
      final firstContext = sim.wire.indexWhere(isContextCommand);
      expect(firstContext, greaterThan(sim.wire.lastIndexOf('03')));
      await finish(obd, sim);
    });
  });

  group('kept out of the way of Clear Codes, the ABS scan and a manual read', () {
    test('it does not start while Clear Codes holds the link between commands', () async {
      // An erase the bike never acknowledges makes Clear wait out a settle
      // period of over a second with NO command in flight — the moment a polite
      // "wait for the pending command" check would let another read in.
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..extra['04'] = null // never acknowledged: a 4 s window, then the settle
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
      sim.wire.clear();
      final clear = obd.clearDtcs();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sim.wire.first, '04', reason: 'the erase is out');
      await obd.readEngineContext(); // asked mid-clear
      expect(contextWire(sim), isEmpty,
          reason: 'nothing of the context went out while Clear Codes ran');
      expect(obd.freezeFrameResult, isNull);
      expect(obd.contextCounters, isNull);
      expect(obd.contextReadInFlight, isFalse);
      await clear;
      await finish(obd, sim);
    });

    test('a Clear that is mid-command is waited for, then the read runs after it', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..extra['04'] = '7E8 01 44'
        ..latency['04'] = const Duration(milliseconds: 300)
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
      sim.wire.clear();
      final clear = obd.clearDtcs();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await obd.readEngineContext();
      expect(await clear, isTrue);
      final erase = sim.wire.indexOf('04');
      final firstContext = sim.wire.indexWhere(isContextCommand);
      expect(erase, 0);
      expect(firstContext, greaterThan(erase), reason: 'never interleaved with the erase');
      // And the Clear invalidated nothing it did not own: this read came after
      // it, so it is current.
      expect(obd.freezeFrameResult, isNotNull);
      await finish(obd, sim);
    });

    test('it does not start while an ABS scan has the link', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..udsModules['7B0'] = '7B8 07 59 02 FF 50 58 11 2F'
        ..latency['1902FF'] = const Duration(milliseconds: 300)
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      final scan = obd.readChassisDtcs(vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(obd.chassisScanInFlight, isTrue);
      await obd.readEngineContext();
      expect(contextWire(sim), isEmpty, reason: 'nothing of the context went out mid-scan');
      expect(obd.freezeFrameResult, isNull);
      await scan;
      await finish(obd, sim);
    });

    test('Clear Codes started during a context read stops it and gets the link', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..extra['04'] = '7E8 01 44'
        ..latency['020200'] = const Duration(milliseconds: 200)
        ..latency['020000'] = const Duration(milliseconds: 200)
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      final read = obd.readEngineContext();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(obd.contextReadInFlight, isTrue);
      final ok = await obd.clearDtcs();
      await read;
      expect(ok, isTrue, reason: 'Clear Codes was not held up past its own bound');
      expect(obd.contextReadInFlight, isFalse);
      // The clear erased the snapshot; nothing from before it is shown.
      expect(obd.freezeFrameResult, isNull);
      await finish(obd, sim);
    });

    test("a rider's manual read stops it and returns the core result", () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..latency['020200'] = const Duration(milliseconds: 200)
        ..latency['020000'] = const Duration(milliseconds: 200)
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      final read = obd.readEngineContext();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final core = await obd.readEngineDtcs(forceExtras: true);
      await read;
      expect(core, isA<EngineAnswered>());
      expect(obd.freezeFrameResult, isNull, reason: 'stopped before the snapshot finished');
      await obd.whenEngineReadSettled();
      await finish(obd, sim);
    });

    test('while it runs the screen-level "extras in flight" flag is set', () async {
      final sim = EngineSim()
        ..latency['020200'] = const Duration(milliseconds: 150)
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      final read = obd.readEngineContext();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(obd.engineExtrasInFlight, isTrue,
          reason: 'the 5-second auto-read pauses for the bounded read');
      await read;
      expect(obd.engineExtrasInFlight, isFalse);
      await finish(obd, sim);
    });

    test('cancel stops it and keeps nothing half-read', () async {
      final sim = EngineSim()
        ..latency['020200'] = const Duration(milliseconds: 150)
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      final read = obd.readEngineContext();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      obd.cancelContextRead();
      await read;
      expect(obd.freezeFrameResult, isNull);
      expect(obd.contextCounters, isNull);
      expect(obd.contextReadInFlight, isFalse);
      // And it can be asked again.
      await obd.readEngineContext();
      expect(obd.freezeFrameResult, isA<FreezeFrameAnswered>());
      await finish(obd, sim);
    });

    test('an isCancelled callback is honoured the same way', () async {
      final sim = EngineSim()
        ..latency['020200'] = const Duration(milliseconds: 150)
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      var closed = false;
      final read = obd.readEngineContext(isCancelled: () => closed);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      closed = true;
      await read;
      expect(obd.freezeFrameResult, isNull);
      await finish(obd, sim);
    });

    test('two callers share one read', () async {
      final sim = EngineSim()
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await Future.wait([obd.readEngineContext(), obd.readEngineContext()]);
      expect(sim.wire.where((c) => c == '020200').length, 1);
      await finish(obd, sim);
    });
  });

  group('nothing stale is shown as current', () {
    test('results are reused while fresh, and force reads again', () async {
      final sim = EngineSim()
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineContext();
      await obd.readEngineContext();
      expect(sim.wire.where((c) => c == '020200').length, 1);
      await obd.readEngineContext(force: true);
      expect(sim.wire.where((c) => c == '020200').length, 2);
      await finish(obd, sim);
    });

    test('a snapshot from before Clear Codes is gone after it', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..extra['04'] = '7E8 01 44'
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineContext();
      expect(obd.freezeFrameResult, isNotNull);
      expect(obd.contextCounters, isNotNull);
      expect(obd.readinessRead, isNotNull);
      await obd.clearDtcs();
      expect(obd.freezeFrameResult, isNull);
      expect(obd.contextCounters, isNull, reason: 'distance since clearing restarts at the erase');
      expect(obd.readinessRead, isNull, reason: 'the self-checks reset when codes are cleared');
      await finish(obd, sim);
    });

    test('even a refused Clear drops them: the next read says what is true now', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..extra['04'] = '7E8 03 7F 04 22'
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineContext();
      await obd.clearDtcs();
      expect(obd.freezeFrameResult, isNull);
      await finish(obd, sim);
    });

    test('another connection never inherits them', () async {
      final sim = EngineSim()
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim);
      await obd.readEngineContext();
      expect(obd.freezeFrameResult, isNotNull);
      await obd.disconnect();
      expect(obd.freezeFrameResult, isNull);
      expect(await obd.connectBluetooth(simDevice), isTrue);
      expect(obd.freezeFrameResult, isNull);
      expect(obd.contextCounters, isNull);
      await finish(obd, sim);
    });

    test('old results are not current any more', () async {
      const tiny = FaultReadTiming.scaled(0.002); // freshness 240 ms
      final sim = EngineSim()
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final obd = await start(sim, timing: tiny);
      await obd.readEngineContext();
      expect(obd.freezeFrameResult, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(obd.freezeFrameResult, isNull);
      expect(obd.contextCounters, isNull);
      await finish(obd, sim);
    });
  });

  group('no vehicle data leaves the service', () {
    test('nothing is printed (a release build turns prints into Sentry breadcrumbs)', () async {
      final printed = <String>[];
      final saved = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => printed.add(m ?? '');
      try {
        // A good read, a silent bike, a refusal, a link that drops mid-read.
        for (final extra in <Map<String, String?>>[
          snapshotBike(),
          snapshotBike(replies: {'020200': null}),
          snapshotBike(replies: {'020200': '7E8 03 7F 02 22'}),
        ]) {
          final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
            ..extra.addAll(extra)
            ..extra.addAll(contextBike());
          final obd = await start(sim);
          await obd.readEngineContext();
          await finish(obd, sim);
        }
        final sim = EngineSim()..extra.addAll(snapshotBike());
        final obd = await start(sim);
        sim.dropLink();
        await obd.readEngineContext();
        await finish(obd, sim);
      } finally {
        debugPrint = saved;
      }
      final text = printed.join('\n');
      // No code, no value, no raw bytes, no header.
      for (final leak in ['P0301', '7E8', '42 02', '4202', '1000', '14.0', '120']) {
        expect(text.contains(leak), isFalse, reason: 'printed "$leak"');
      }
      expect(RegExp(r'\b[0-9A-F]{2} [0-9A-F]{2} [0-9A-F]{2}\b').hasMatch(text), isFalse);
    });

    test('the snapshot types carry no VIN field and print no bytes', () {
      final s = FreezeFrameSnapshot(
          triggerCode: 'P0301', readAt: DateTime(2026), values: const []);
      expect(s.toString().contains('P0301'), isFalse,
          reason: 'default toString: type name only');
    });
  });
}
