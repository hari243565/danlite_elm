/// Phase 1A — A3: "request received, response pending" (7F xx 78).
///
/// Part 1 drives the shared helper with a scripted adapter and a fake clock,
/// so the 20-second bound is tested exactly without waiting for it. Part 2
/// runs the REAL ObdService over the simulator's two adapter personalities —
/// one that waits internally (genuine ELM327 2.1+ / STN) and one that passes
/// the pending frame through and then loses the answer (ELM 1.x clones) — for
/// the engine read and for the ABS reader.
library;

import 'package:danlite_elm/constants/chassis_modules.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:danlite_elm/services/response_pending.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_sim.dart';

/// A scripted adapter on a fake clock.
class Script {
  Script(this.replies, {this.latency = const Duration(milliseconds: 40)});
  final List<String> replies;
  final Duration latency;
  Duration now = Duration.zero;
  final sent = <String>[];
  final windows = <Duration>[];
  final sleeps = <Duration>[];
  final flushes = <bool>[];
  int passes = 0;
  int _i = 0;

  Future<String> send(String cmd, Duration window) async {
    sent.add(cmd);
    windows.add(window);
    final reply = replies[_i < replies.length ? _i : replies.length - 1];
    _i++;
    if (latency > window) {
      // The app's own window runs out first, as on a real link.
      now += window;
      return 'TIMEOUT';
    }
    now += latency;
    return reply;
  }

  Future<void> sleep(Duration d) async {
    sleeps.add(d);
    now += d;
  }

  Future<PendingResult> run({PendingPolicy policy = const PendingPolicy()}) =>
      sendWithPendingHandling(
        request: '1902FF',
        serviceId: 0x19,
        send: send,
        flush: ({required bool afterTimeout}) async => flushes.add(afterTimeout),
        onAdapterPassesPending: () => passes++,
        policy: policy,
        sleep: sleep,
        elapsed: () => now,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A3 named constants', () {
    test('5 s per attempt, 20 s overall, 300 ms between re-sends', () {
      expect(kPendingPerAttemptWindow, const Duration(seconds: 5));
      expect(kPendingOverallBound, const Duration(seconds: 20));
      expect(kPendingRetryDelay, const Duration(milliseconds: 300));
      const p = PendingPolicy();
      expect(p.perAttempt, kPendingPerAttemptWindow);
      expect(p.overall, kPendingOverallBound);
      expect(p.retryDelay, kPendingRetryDelay);
    });
  });

  group('A3 helper', () {
    test('no pending: one send, reply untouched, window is 5 s', () async {
      final s = Script(['7B8 07 59 02 FF 50 58 00 2F']);
      final r = await s.run();
      expect(r, isA<PendingAnswered>());
      expect((r as PendingAnswered).reply, '7B8 07 59 02 FF 50 58 00 2F');
      expect(r.attempts, 1);
      expect(r.sawPending, isFalse);
      expect(s.windows.single, const Duration(seconds: 5));
      expect(s.passes, 0);
    });

    test('adapter passes pending: wait 300 ms, re-send the SAME request', () async {
      final s = Script(['7B8 03 7F 19 78', '7B8 07 59 02 FF 50 58 00 2F']);
      final r = await s.run() as PendingAnswered;
      expect(r.reply, contains('59 02'));
      expect(r.attempts, 2);
      expect(r.sawPending, isTrue);
      expect(s.sent, ['1902FF', '1902FF']);
      expect(s.sleeps, [const Duration(milliseconds: 300)]);
      expect(s.passes, greaterThan(0),
          reason: 'adapterPassesPending is recorded for the session');
    });

    test('pending and the answer in one buffer: the answer is kept', () async {
      final s = Script(['7B8 03 7F 19 78\n7B8 07 59 02 FF 50 58 00 2F']);
      final r = await s.run() as PendingAnswered;
      expect(r.reply, isNot(contains('7F 19 78')));
      expect(r.reply, contains('59 02 FF 50 58 00 2F'));
      expect(r.attempts, 1);
    });

    test('adapter handles pending itself: a slow answer, nothing special', () async {
      final s = Script(['7B8 07 59 02 FF 50 58 00 2F'],
          latency: const Duration(milliseconds: 4200));
      final r = await s.run() as PendingAnswered;
      expect(r.attempts, 1);
      expect(r.sawPending, isFalse);
      expect(s.passes, 0);
      expect(s.sleeps, isEmpty);
    });

    test('pending forever: NoAnswer "module kept reporting busy" by 20 s', () async {
      final s = Script(['7B8 03 7F 19 78']);
      final r = await s.run();
      expect(r, isA<PendingBusy>());
      expect((r as PendingBusy).reason, 'module kept reporting busy');
      expect(s.now, lessThanOrEqualTo(kPendingOverallBound));
      expect(r.attempts, greaterThan(10));
      expect(s.flushes, [false], reason: 'the adapter is flushed when giving up');
    });

    test('pending then a refusal: the refusal is the answer', () async {
      final s = Script(['7B8 03 7F 19 78', '7B8 03 7F 19 22']);
      final r = await s.run() as PendingAnswered;
      expect(r.reply, '7B8 03 7F 19 22');
      expect(r.attempts, 2);
    });

    test('a timeout is returned as such, after flushing the adapter', () async {
      final s = Script(['TIMEOUT']);
      final r = await s.run() as PendingAnswered;
      expect(r.reply, 'TIMEOUT');
      expect(s.flushes, [true]);
    });

    test('pending then silence: timeout, flushed, never an empty success', () async {
      final s = Script(['7B8 03 7F 19 78', 'TIMEOUT']);
      final r = await s.run() as PendingAnswered;
      expect(r.reply, 'TIMEOUT');
      expect(r.sawPending, isTrue);
      expect(s.flushes, [true]);
    });

    test('the per-attempt window is clipped to what is left of the bound', () async {
      final s = Script(['7B8 03 7F 19 78'],
          latency: const Duration(milliseconds: 3000));
      await s.run(
          policy: const PendingPolicy(
              perAttempt: Duration(seconds: 5), overall: Duration(seconds: 8)));
      expect(s.windows.first, const Duration(seconds: 5));
      expect(s.windows.last, lessThan(const Duration(seconds: 5)));
      expect(s.now, lessThanOrEqualTo(const Duration(seconds: 8)));
    });

    test('NRC 0x78 for another service is not treated as pending', () async {
      final s = Script(['7B8 03 7F 22 78']);
      final r = await s.run() as PendingAnswered;
      expect(r.attempts, 1);
      expect(r.sawPending, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Part 2 — the real service over both adapter personalities
  // ══════════════════════════════════════════════════════════════════════════
  const fast = FaultReadTiming.scaled(0.05);

  group('A3 engine read (Mode 03) over both personalities', () {
    for (final personality in AdapterPersonality.values) {
      test('${personality.name}: pending then answer → codes, not a refusal', () async {
        final sim = EngineSim(mode03: '7E8 06 43 02 01 33 03 01')
          ..personality = personality
          ..busy['03'] = const ModuleBusy(times: 2);
        final obd = await connectSim(sim, timing: fast);
        final r = await obd.readEngineDtcs(withExtras: false);
        expect(r, isA<EngineAnswered>());
        expect((r as EngineAnswered).codes.map((c) => c.code), ['P0133', 'P0301']);
        expect(obd.session!.adapterPassesPending,
            personality == AdapterPersonality.passesPending);
        await obd.disconnect();
        await sim.close();
      });

      test('${personality.name}: pending forever → NoAnswer(moduleBusy)', () async {
        final sim = EngineSim(mode03: '7E8 02 43 00')
          ..personality = personality
          ..busy['03'] = const ModuleBusy.forever();
        final obd = await connectSim(sim, timing: fast);
        final r = await obd.readEngineDtcs(withExtras: false);
        expect(r, isA<EngineNoAnswer>());
        expect(obd.dtcCodes, isEmpty, reason: 'never an empty success');
        if (personality == AdapterPersonality.passesPending) {
          expect((r as EngineNoAnswer).reason, EngineNoAnswerReason.moduleBusy);
        }
        await obd.disconnect();
        await sim.close();
      });

      test('${personality.name}: pending then refusal → Refused(0x22)', () async {
        final sim = EngineSim(mode03: '7E8 03 7F 03 22')
          ..personality = personality
          ..busy['03'] = const ModuleBusy(times: 1);
        final obd = await connectSim(sim, timing: fast);
        final r = await obd.readEngineDtcs(withExtras: false);
        expect(r, isA<EngineRefused>());
        expect((r as EngineRefused).nrc, 0x22);
        await obd.disconnect();
        await sim.close();
      });
    }

    test('real constants: a 3.5 s internal wait is not lost (old window was 3 s)',
        () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 01 33')
        ..personality = AdapterPersonality.handlesPending
        ..pendingStep = const Duration(milliseconds: 1750)
        ..busy['03'] = const ModuleBusy(times: 2);
      final obd = await connectSim(sim);
      final r = await obd.readEngineDtcs(withExtras: false);
      expect(r, isA<EngineAnswered>());
      expect((r as EngineAnswered).codes.single.code, 'P0133');
      await obd.disconnect();
      await sim.close();
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('A3 ABS reader (19 02 FF) over both personalities', () {
    for (final personality in AdapterPersonality.values) {
      test('${personality.name}: pending then answer → the ABS code is kept', () async {
        final sim = EngineSim()
          ..personality = personality
          ..udsModules['7B0'] = '7B8 07 59 02 FF 50 58 11 2F'
          ..busy['1902FF'] = const ModuleBusy(times: 2);
        final obd = await connectSim(sim, timing: fast);
        final codes = await obd.readChassisDtcs(
            vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');
        expect(codes.map((c) => c.code), ['C1058']);
        expect(codes.single.failureTypeByte, 0x11);
        expect(codes.single.statusByte, 0x2F);
        expect(obd.chassisScanOutcome, ChassisScanOutcome.faultsFound);
        expect(obd.session!.adapterPassesPending,
            personality == AdapterPersonality.passesPending);
        await obd.disconnect();
        await sim.close();
      });

      test('${personality.name}: pending then refusal → not clean, not found', () async {
        final sim = EngineSim()
          ..personality = personality
          ..udsModules['7B0'] = '7B8 03 7F 19 22'
          ..busy['1902FF'] = const ModuleBusy(times: 1);
        final obd = await connectSim(sim, timing: fast);
        final codes = await obd.readChassisDtcs(
            vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');
        expect(codes, isEmpty);
        expect(obd.chassisScanOutcome, isNot(ChassisScanOutcome.clean));
        expect(obd.chassisScanLog.join('\n'), contains('NRC 0x22'));
        await obd.disconnect();
        await sim.close();
      });
    }

    test('passes pending, pending forever → "module kept reporting busy", '
        'never clean', () async {
      final sim = EngineSim()
        ..personality = AdapterPersonality.passesPending
        ..udsModules['7B0'] = '7B8 07 59 02 FF 50 58 11 2F'
        ..busy['1902FF'] = const ModuleBusy.forever();
      final obd = await connectSim(sim, timing: fast);
      final codes = await obd.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');
      expect(codes, isEmpty);
      expect(obd.chassisScanOutcome, isNot(ChassisScanOutcome.clean));
      expect(obd.chassisScanLog.join('\n'), contains('module kept reporting busy'));
      await obd.disconnect();
      await sim.close();
    });

    test('pending and answer in ONE buffer (audit Additions #9) → code kept', () async {
      final sim = EngineSim()
        ..udsModules['7B0'] = '7B8 03 7F 19 78\r7B8 07 59 02 FF 50 58 00 2F';
      final obd = await connectSim(sim, timing: fast);
      final codes = await obd.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');
      expect(codes.map((c) => c.code), ['C1058']);
      expect(obd.session!.adapterPassesPending, isTrue);
      await obd.disconnect();
      await sim.close();
    });

    test('the probe order and addresses are unchanged by pending handling', () async {
      final plain = EngineSim()..udsModules['760'] = '768 07 59 02 FF 50 58 00 2F';
      final o1 = await connectSim(plain, timing: fast);
      await o1.readChassisDtcs(vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');
      final pend = EngineSim()
        ..personality = AdapterPersonality.passesPending
        ..udsModules['760'] = '768 07 59 02 FF 50 58 00 2F'
        ..busy['1902FF'] = const ModuleBusy(times: 1);
      final o2 = await connectSim(pend, timing: fast);
      await o2.readChassisDtcs(vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');
      List<String> headers(EngineSim s) =>
          s.wire.where((c) => c.startsWith('ATSH')).toList();
      expect(headers(pend), headers(plain));
      await o1.disconnect();
      await o2.disconnect();
      await plain.close();
      await pend.close();
    });
  });
}
