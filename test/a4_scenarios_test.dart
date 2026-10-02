/// Phase A-4 — scenario status, proven with the simulator and the real screen.
/// Scenario numbers and definitions are those of
/// `chore/fault-audit:docs/faults/SCENARIO_COVERAGE.md`.
///
///  3   Engine off vs running
///  13  Intermittent faults — show the context
///  14  Pending, history and permanent codes — unchanged
///
/// NOT on a real bike: the brief places live testing at the end of the project.
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/services/engine_context.dart';
import 'package:danlite_elm/services/engine_report.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/context_harness.dart';
import 'support/context_sim.dart';
import 'support/engine_sim.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════
  // 3 — engine off vs running
  // ══════════════════════════════════════════════════════════════════════
  group('Scenario 3 — engine off vs running', () {
    testWidgets('the snapshot says what the engine was doing WHEN THE FAULT WAS RECORDED, '
        'not now: the engine is off now and the live reading says so', (tester) async {
      // The snapshot holds 3000 RPM and 60 km/h. Right now the engine is off.
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..livePids['010C'] = '41 0C 00 00'
        ..extra.addAll(snapshotBike(replies: {'020C00': frame('42 0C 00 2E E0')}))
        ..extra.addAll(contextBike());
      final env = await startScreen(tester, sim);
      expect(env.obd.engineReport!.engineState, EngineState.off);
      final reportBefore = env.obd.engineReport;
      await openDetails(tester, env);
      final xs = texts(tester);
      expect(xs, contains(t('snapshotTitle')), reason: 'labelled as the snapshot');
      expect(xs, contains('3000 RPM'));
      // The context read never touched the live engine-state reading.
      expect(identical(env.obd.engineReport, reportBefore), isTrue);
      expect(env.obd.engineReport!.engineState, EngineState.off);
      await env.close(tester);
    });

    testWidgets('a bike that refuses the snapshot while running is "refused", never '
        '"no snapshot"; the existing engine-state notice logic is untouched', (tester) async {
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..livePids['010C'] = '41 0C 0B B8' // 750 RPM: running
        ..extra.addAll(snapshotBike(replies: {'020200': '7E8 03 7F 02 22'}))
        ..extra.addAll(contextBike());
      final env = await startScreen(tester, sim);
      expect(env.obd.engineReport!.engineState, EngineState.running);
      await openDetails(tester, env);
      final xs = texts(tester);
      expect(xs, contains(t('snapshotRefused')));
      expect(xs, isNot(contains(t('snapshotNone'))));
      expect(find.byKey(const ValueKey('contextRetry')), findsOneWidget);
      expect(env.obd.engineReport!.engineState, EngineState.running);
      await env.close(tester);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 13 — intermittent faults: show the context
  // ══════════════════════════════════════════════════════════════════════
  group('Scenario 13 — intermittent faults', () {
    testWidgets('a stored code whose lamp has gone out: the snapshot and "cleared N km ago" '
        'are shown, "lamp has been on" is not (it would be untrue)', (tester) async {
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..extra.addAll(snapshotBike())
        // Lamp bit CLEAR, one stored code: the fault is not currently lit.
        ..extra.addAll(contextBike(replies: {'0101': frame('41 01 01 07 E5 00')}));
      final env = await startScreen(tester, sim);
      await openDetails(tester, env);
      final xs = texts(tester);
      expect(xs, contains(t('snapshotTitle')));
      expect(xs, contains('P0301'));
      expect(xs, contains('83 °C'), reason: 'the coolant temperature when it happened');
      expect(xs, contains(ta('ctxClearedKm', {'n': '480'})));
      expect(xs, contains(ta('ctxWarmUps', {'n': '7'})));
      expect(anyHas(xs, 'Warning lamp has been on'), isFalse);
      await env.close(tester);
    });

    testWidgets('a fault that keeps the lamp lit: how long, by distance and by time',
        (tester) async {
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final env = await startScreen(tester, sim);
      await openDetails(tester, env);
      final xs = texts(tester);
      expect(xs, contains(ta('ctxLampKm', {'n': '120'})));
      expect(xs, contains(ta('ctxLampMin', {'n': '95'})));
      await env.close(tester);
    });

    testWidgets('a code with NO snapshot (it came and went before one was kept): '
        'the card says so and still gives the counters', (tester) async {
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..extra.addAll(noSnapshotBike())
        ..extra.addAll(contextBike());
      final env = await startScreen(tester, sim);
      await openDetails(tester, env);
      final xs = texts(tester);
      expect(xs, contains(t('snapshotNone')));
      expect(xs, contains(ta('ctxClearedKm', {'n': '480'})));
      await env.close(tester);
    });

    testWidgets('after Clear Codes the old context is gone, not repeated', (tester) async {
      final sim = EngineSim(mode03: '7E8 04 43 01 03 01')
        ..extra['04'] = '7E8 01 44'
        ..extra.addAll(snapshotBike())
        ..extra.addAll(contextBike());
      final env = await startScreen(tester, sim);
      await openDetails(tester, env);
      expect(env.obd.freezeFrameResult, isNotNull);
      await tester.runAsync(() => env.obd.clearDtcs());
      expect(env.obd.freezeFrameResult, isNull);
      expect(env.obd.contextCounters, isNull);
      await env.close(tester);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 14 — pending and permanent codes are unchanged
  // ══════════════════════════════════════════════════════════════════════
  group('Scenario 14 — pending and permanent: unchanged', () {
    EngineSim threeKinds() => EngineSim(mode03: '7E8 04 43 01 01 33')
      ..extra['07'] = '7E8 04 47 01 03 01'
      ..extra['0A'] = '7E8 04 4A 01 01 33'
      ..extra.addAll(snapshotBike())
      ..extra.addAll(contextBike());

    testWidgets('the cards, chips and merged records are identical before and after a '
        'context read', (tester) async {
      final env = await startScreen(tester, threeKinds());
      final recordsBefore = [
        for (final r in env.obd.engineFaultRecords) '${r.code}:${(r.sources.map((s) => s.name).toList()..sort()).join(',')}'
      ];
      final reportBefore = env.obd.engineReport;
      final before = texts(tester).where((x) => x != t('showDetails')).toList();
      await openDetails(tester, env);
      expect(env.obd.freezeFrameResult, isNotNull);
      expect([
        for (final r in env.obd.engineFaultRecords) '${r.code}:${(r.sources.map((s) => s.name).toList()..sort()).join(',')}'
      ], recordsBefore);
      expect(identical(env.obd.engineReport, reportBefore), isTrue,
          reason: 'the automatic extras report is not rewritten by the context read');
      final xs = texts(tester);
      expect(xs, containsAll(<String>[
        'P0133', 'P0301', t('faultStatusStored'), t('faultStatusPending'),
        t('faultStatusPermanent'),
      ]));
      expect(xs, isNot(contains(t('faultStatusHistory'))));
      // Everything that was on the screen is still on it (plus the details).
      for (final b in before) {
        if (b.contains('·')) continue; // the live-scan stamp moves with time
        expect(xs, contains(b), reason: 'unchanged: "$b"');
      }
      await env.close(tester);
    });

    test('a plain scan sends exactly the commands it sent before this phase', () async {
      final sim = threeKinds();
      final obd = await connectSim(sim, timing: fast);
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
      final scan = sim.wire.where((c) => !c.startsWith('AT') && c.isNotEmpty).toList();
      // The core, then the automatic extras — and no Mode 02, no counter PID.
      // (After init, the first request is the core read.)
      expect(scan.sublist(scan.indexOf('03')).first, '03');
      expect(scan.indexOf('03'), greaterThanOrEqualTo(0));
      expect(scan.where((c) => c.startsWith('02')), isEmpty);
      expect(scan.where((c) => {'0121', '0131', '014D', '014E', '0130'}.contains(c)), isEmpty);
      expect(scan, containsAll(<String>['0101', '07', '0A', '010C']));
      await obd.disconnect();
      await sim.close();
    });

    test('the automatic re-read never starts a context read', () async {
      final sim = threeKinds();
      final obd = await connectSim(sim, timing: fast);
      for (var i = 0; i < 3; i++) {
        await obd.readEngineDtcs(); // the screen\'s 5-second auto-read
        await obd.whenEngineReadSettled();
      }
      expect(obd.freezeFrameResult, isNull);
      expect(obd.contextCounters, isNull);
      expect(sim.wire.where((c) => c.startsWith('02')), isEmpty);
      await obd.disconnect();
      await sim.close();
    });

    test('a pending-only code is still shown when the context read finds a snapshot for another',
        () async {
      final sim = EngineSim(mode03: '7E8 02 43 00')
        ..extra['07'] = '7E8 04 47 01 03 01'
        ..extra.addAll(snapshotBike(trigger: '01 33'))
        ..extra.addAll(contextBike());
      final obd = await connectSim(sim, timing: fast);
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
      await obd.readEngineContext();
      expect(obd.engineFaultRecords.map((r) => r.code), ['P0301']);
      expect((obd.freezeFrameResult as FreezeFrameAnswered).snapshot.triggerCode, 'P0133');
      expect(obd.engineFaultRecords.single.sources, {ReadSource.mode07});
      await obd.disconnect();
      await sim.close();
    });
  });

  test('the strings used by these scenarios exist in English and Hindi', () {
    for (final k in [
      'snapshotTitle', 'snapshotNone', 'snapshotRefused', 'ctxClearedKm', 'ctxWarmUps',
      'ctxLampKm', 'ctxLampMin', 'showDetails',
    ]) {
      expect(AppStrings.get(k, 'en'), isNot(k));
      expect(AppStrings.get(k, 'hi'), isNot(k));
      expect(AppStrings.get(k, 'hi'), isNot(AppStrings.get(k, 'en')));
    }
  });
}
