/// Phase A-4 (C1–C3) — what the rider sees: "Show details" on a fault card, the
/// Freeze Frame sheet, and the Emission self-checks. The REAL ObdService over
/// the simulator and the REAL screen, English and Hindi.
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/context_harness.dart';
import 'support/context_sim.dart';
import 'support/engine_sim.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the card: collapsed until the rider asks', () {
    testWidgets('nothing is read, and only the button shows', (tester) async {
      final env = await startScreen(tester, bike());
      final xs = texts(tester);
      expect(xs, contains(t('showDetails')));
      expect(xs, isNot(contains(t('snapshotTitle'))));
      expect(env.sim.wire.where((c) => c.startsWith('02')), isEmpty);
      expect(env.sim.wire.where((c) => {'0121', '0131', '014D', '014E', '0130'}.contains(c)),
          isEmpty);
      await env.close(tester);
    });

    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] Show details → snapshot with units, counters, "Read at"',
          (tester) async {
        final env = await startScreen(tester, bike(), lang: lang);
        await openDetails(tester, env);
        final xs = texts(tester);
        expect(xs, contains(t('hideDetails', lang)));
        expect(xs, contains(t('snapshotTitle', lang)));
        expect(xs, contains(t('triggerCode', lang)));
        expect(xs, contains('P0301'));
        expect(xs, contains('1000 RPM'));
        expect(xs, contains('60 km/h'));
        expect(xs, contains('83 °C'));
        expect(xs, contains('99 kPa'));
        expect(xs, contains('14.00 V'));
        expect(xs, contains('12.5 %'), reason: 'short-term trim');
        expect(xs, contains(t('fuelStatusClosed', lang)));
        expect(anyHas(xs, t('dtcReadAt', lang).split('{time}').first), isTrue);
        // The counters, with the lamp on and 120 km / 95 min.
        expect(xs, contains(ta('ctxLampKm', {'n': '120'}, lang)));
        expect(xs, contains(ta('ctxLampMin', {'n': '95'}, lang)));
        expect(xs, contains(ta('ctxClearedKm', {'n': '480'}, lang)));
        expect(xs, contains(ta('ctxClearedMin', {'n': '310'}, lang)));
        expect(xs, contains(ta('ctxWarmUps', {'n': '7'}, lang)));
        // The self-checks are NOT on the card: they are vehicle-level.
        expect(xs, isNot(contains(t('readinessTitle', lang))));
        await env.close(tester);
      });
    }

    testWidgets('Hide details collapses it again, and a second open reuses the read',
        (tester) async {
      final env = await startScreen(tester, bike());
      await openDetails(tester, env);
      await tester.tap(find.byKey(const ValueKey('contextToggle')).first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(texts(tester), isNot(contains(t('snapshotTitle'))));
      await tester.tap(find.byKey(const ValueKey('contextToggle')).first);
      await settle(tester, env.obd);
      expect(texts(tester), contains(t('snapshotTitle')));
      expect(env.sim.wire.where((c) => c == '020200').length, 1,
          reason: 'fresh results are shown, not asked for again');
      await env.close(tester);
    });
  });

  group('the card: every outcome is its own words', () {
    testWidgets('no snapshot stored', (tester) async {
      final env = await startScreen(tester, bike(snapshot: noSnapshotBike()));
      await openDetails(tester, env);
      final xs = texts(tester);
      expect(xs, contains(t('snapshotNone')));
      expect(xs, isNot(contains(t('snapshotNoAnswer'))));
      expect(xs, isNot(contains(t('snapshotUnsupported'))));
      await env.close(tester);
    });

    testWidgets('this bike does not provide snapshots', (tester) async {
      final env = await startScreen(tester, bike(snapshot: mode02Unsupported()));
      await openDetails(tester, env);
      final xs = texts(tester);
      expect(xs, contains(t('snapshotUnsupported')));
      expect(xs, isNot(contains(t('snapshotNone'))));
      await env.close(tester);
    });

    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] silence: its own words, a Retry, and never "no data"', (tester) async {
        final env = await startScreen(tester, bike(snapshot: {'020200': null}), lang: lang);
        await openDetails(tester, env);
        final xs = texts(tester);
        expect(xs, contains(t('snapshotNoAnswer', lang)));
        expect(xs, isNot(contains(t('snapshotNone', lang))));
        expect(xs, isNot(contains(t('snapshotUnsupported', lang))));
        expect(find.byKey(const ValueKey('contextRetry')), findsOneWidget);
        await env.close(tester);
      });
    }

    testWidgets('the bike refused', (tester) async {
      final env = await startScreen(tester, bike(snapshot: {'020200': '7E8 03 7F 02 22'}));
      await openDetails(tester, env);
      expect(texts(tester), contains(t('snapshotRefused')));
      expect(find.byKey(const ValueKey('contextRetry')), findsOneWidget);
      await env.close(tester);
    });

    testWidgets('a value the bike keeps but did not answer → "some details could not be read"',
        (tester) async {
      final env = await startScreen(
          tester, bike(snapshot: snapshotBike(only: {0x04, 0x05}, replies: {'020500': null})));
      await openDetails(tester, env);
      final xs = texts(tester);
      expect(xs, contains(t('ctxPartial')));
      expect(xs, contains('50 %'), reason: 'what did answer is still shown');
      expect(xs, isNot(contains('83 °C')));
      expect(find.byKey(const ValueKey('contextRetry')), findsOneWidget);
      await env.close(tester);
    });

    testWidgets('a snapshot that belongs to a different code says so', (tester) async {
      // The card is P0120; the bike's snapshot was recorded for P0301.
      final env = await startScreen(tester, bike(mode03: '7E8 04 43 01 01 20'));
      await openDetails(tester, env);
      expect(texts(tester), contains(ta('snapshotOtherFault', {'code': 'P0301'})));
      await env.close(tester);
    });

    testWidgets('a snapshot for THIS code carries no such note', (tester) async {
      final env = await startScreen(tester, bike());
      await openDetails(tester, env);
      expect(anyHas(texts(tester), 'not to this fault'), isFalse);
      await env.close(tester);
    });

    testWidgets('the K-line bus is not read and says why', (tester) async {
      // The engine read itself is gated off on K-line, so no card is shown;
      // the Freeze Frame sheet, which is reachable, says it too.
      final sim = EngineSim(protocol: 'A3');
      sim.extra.addAll(snapshotBike());
      final env = await startScreen(tester, sim);
      await openSheet(tester, env);
      expect(texts(tester), contains(t('dtcKLineGated')));
      expect(sim.wire.where(isContextCommand), isEmpty);
      await env.close(tester);
    });
  });

  group('the card: counters are only drawn when they can be true', () {
    testWidgets('the lamp is OFF: no "lamp has been on" lines, the rest stay', (tester) async {
      // 41 01 03 …: lamp bit clear, 3 codes. PID 21 = 120 km would be stale.
      final env = await startScreen(
          tester, bike(context: contextBike(replies: {'0101': frame('41 01 03 07 E5 04')})));
      await openDetails(tester, env);
      final xs = texts(tester);
      expect(anyHas(xs, 'Warning lamp has been on'), isFalse);
      expect(xs, contains(ta('ctxClearedKm', {'n': '480'})));
      await env.close(tester);
    });

    testWidgets('the lamp is on but the distance is 0: not "on for 0 km"', (tester) async {
      final env = await startScreen(
          tester,
          bike(context: contextBike(replies: {
            '0121': frame('41 21 00 00'),
            '014D': frame('41 4D 00 00'),
          })));
      await openDetails(tester, env);
      expect(anyHas(texts(tester), 'Warning lamp has been on'), isFalse);
      await env.close(tester);
    });

    testWidgets('the maximum reads "at least 65,535"', (tester) async {
      final env = await startScreen(tester,
          bike(context: contextBike(replies: {'0131': frame('41 31 FF FF')})));
      await openDetails(tester, env);
      expect(texts(tester),
          contains(ta('ctxClearedKm', {'n': ta('ctxAtLeast', {'n': '65,535'})})));
      await env.close(tester);
    });

    testWidgets('[hi] the maximum reads "कम से कम 65,535"', (tester) async {
      final env = await startScreen(
          tester, bike(context: contextBike(replies: {'0131': frame('41 31 FF FF')})),
          lang: 'hi');
      await openDetails(tester, env);
      expect(texts(tester),
          contains(ta('ctxClearedKm', {'n': ta('ctxAtLeast', {'n': '65,535'}, 'hi')}, 'hi')));
      await env.close(tester);
    });

    testWidgets('a counter the bike does not have is not drawn at all', (tester) async {
      final env = await startScreen(tester,
          bike(context: contextBike(replies: {'014E': 'NO DATA', '0130': 'NO DATA'})));
      await openDetails(tester, env);
      final xs = texts(tester);
      expect(anyHas(xs, 'warmed up'), isFalse);
      expect(anyHas(xs, 'min ago'), isFalse);
      expect(xs, isNot(contains(t('ctxPartial'))), reason: 'unsupported is silent, not an error');
      await env.close(tester);
    });

    testWidgets('a counter that gets no answer is "some details could not be read"',
        (tester) async {
      final env = await startScreen(
          tester, bike(context: contextBike(replies: {'0130': null})));
      await openDetails(tester, env);
      expect(texts(tester), contains(t('ctxPartial')));
      await env.close(tester);
    });
  });

  group('cards that must not offer details', () {
    testWidgets('the greyed earlier list (the bike stopped answering)', (tester) async {
      final sim = bike();
      final env = await startScreen(tester, sim);
      sim.mode03 = 'NO DATA';
      await tester.runAsync(() async {
        await env.obd.readEngineDtcs();
        await env.obd.whenEngineReadSettled();
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(texts(tester), contains('P0301'), reason: 'the earlier code is still listed');
      expect(find.byKey(const ValueKey('contextToggle')), findsNothing);
      await env.close(tester);
    });
  });

  group('the Freeze Frame sheet', () {
    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] snapshot, counters and the emission self-checks', (tester) async {
        final env = await startScreen(tester, bike(), lang: lang);
        await openSheet(tester, env);
        final xs = texts(tester);
        expect(xs, contains(t('freezeFrameTitle', lang)));
        expect(xs, contains(t('snapshotTitle', lang)));
        expect(xs, contains('P0301'));
        expect(xs, contains(ta('ctxLampKm', {'n': '120'}, lang)));
        // Self-checks: catalyst complete, evaporative not complete, heated
        // catalyst not supported — each with its word, not colour alone.
        expect(xs, contains(t('readinessTitle', lang)));
        expect(xs, contains(t('monCatalyst', lang)));
        expect(xs, contains(t('monEvaporative', lang)));
        expect(xs, contains(t('readinessComplete', lang)));
        expect(xs, contains(t('readinessNotComplete', lang)));
        expect(xs, contains(t('readinessNotSupported', lang)));
        expect(xs, contains(t('readinessHint', lang)));
        for (final m in [
          'monMisfire', 'monFuelSystem', 'monComponents', 'monCatalyst',
          'monHeatedCatalyst', 'monEvaporative', 'monSecondaryAir', 'monAcRefrigerant',
          'monOxygenSensor', 'monOxygenSensorHeater', 'monEgr',
        ]) {
          expect(xs, contains(t(m, lang)), reason: m);
        }
        await env.close(tester);
      });
    }

    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] a silent bike: honest words, never the old "No Freeze Data"',
          (tester) async {
        final sim = EngineSim(mode03: '7E8 04 43 01 03 01');
        sim.extra.addAll(<String, String?>{
          for (final c in ['020200', '0101', '0121', '0131', '014D', '014E', '0130']) c: null,
        });
        final env = await startScreen(tester, sim, lang: lang);
        await openSheet(tester, env);
        final xs = texts(tester);
        expect(xs, contains(t('snapshotNoAnswer', lang)));
        expect(xs, contains(t('ctxPartial', lang)));
        expect(find.byKey(const ValueKey('contextRetry')), findsOneWidget);
        expect(xs, isNot(contains(t('snapshotNone', lang))));
        expect(anyHas(xs, 'No Freeze Data'), isFalse);
        await env.close(tester);
      });
    }

    testWidgets('the old "No Freeze Data Available" text is gone from every language', (tester) async {
      for (final lang in SettingsProvider.supportedLanguages.map((l) => l.code)) {
        expect(AppStrings.get('noFreezeData', lang), 'noFreezeData',
            reason: '$lang: the key is gone, so it can never be shown');
      }
    });

    testWidgets('no snapshot → words, and the self-checks are still shown', (tester) async {
      final env = await startScreen(tester, bike(snapshot: noSnapshotBike()));
      await openSheet(tester, env);
      final xs = texts(tester);
      expect(xs, contains(t('snapshotNone')));
      expect(xs, contains(t('readinessTitle')));
      await env.close(tester);
    });

    testWidgets('a bike with no self-check information says so', (tester) async {
      final env = await startScreen(tester, bike(context: contextBike(replies: {'0101': 'NO DATA'})));
      await openSheet(tester, env);
      expect(texts(tester), contains(t('readinessUnavailable')));
      await env.close(tester);
    });

    testWidgets('closing the sheet stops a read that is still running', (tester) async {
      final sim = bike();
      // A 0.2-scaled window is one second: the bike is slow, not silent.
      sim.latency['020200'] = const Duration(milliseconds: 800);
      final env = await startScreen(tester, sim, timing: const FaultReadTiming.scaled(0.2));
      await tester.tap(find.byTooltip(t('freezeFrame')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(env.obd.contextReadInFlight, isTrue);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump(const Duration(milliseconds: 400));
      for (var i = 0; i < 60 && env.obd.contextReadInFlight; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(env.obd.contextReadInFlight, isFalse);
      expect(env.obd.freezeFrameResult, isNull, reason: 'nothing half-read is kept');
      await env.close(tester);
    });
  });
}
