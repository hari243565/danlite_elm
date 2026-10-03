/// Phase 4B (B5) — a fuel-system status of 0 is shown as "Engine off" only
/// when the engine is KNOWN to be off: the snapshot's own engine speed is 0,
/// or (with no engine speed in the snapshot) the engine is otherwise known to
/// be off. A running engine or an unknown state hides the row — a snapshot
/// that says "engine off" next to 2,400 RPM, or on a guess, is a wrong answer.
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/services/engine_context.dart';
import 'package:danlite_elm/services/engine_report.dart';
import 'package:danlite_elm/widgets/engine_context_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _t0 = DateTime(2026, 10, 3, 9);

const _off = SnapshotFuelSystem(FuelStatusKind.engineOff, FuelStatusKind.none);

FreezeFrameSnapshot snapshot(List<SnapshotValue> values) => FreezeFrameSnapshot(
    triggerCode: 'P0133', readAt: _t0, values: values);

SnapshotNumber rpm(double v) => SnapshotNumber(SnapshotPid.rpm, v);

void main() {
  group('B5 the rule, every combination', () {
    // (snapshot rpm, engine state) -> is the "Engine off" row shown?
    final rpms = <double?>[null, 0, 1, 150, 299, 300, 800, 2400];
    final states = <EngineState?>[null, EngineState.unknown, EngineState.running, EngineState.off];

    for (final r in rpms) {
      for (final s in states) {
        // The snapshot's own engine speed wins. Only with none do we fall back
        // to what is otherwise known.
        final expected = r != null ? r == 0 : s == EngineState.off;
        test('status 0, snapshot rpm ${r ?? "absent"}, engine ${s?.name ?? "null"} -> '
            '${expected ? "shown" : "hidden"}', () {
          expect(
              fuelSystemRowIsShown(_off, snapshotRpm: r, engineState: s), expected);
        });
      }
    }

    test('a snapshot that says rpm 0 beats a live reading that says running', () {
      expect(fuelSystemRowIsShown(_off, snapshotRpm: 0, engineState: EngineState.running), isTrue);
    });

    test('a snapshot that says the engine was running beats a live reading that says off', () {
      expect(fuelSystemRowIsShown(_off, snapshotRpm: 900, engineState: EngineState.off), isFalse);
    });

    test('every other status is untouched by engine state and rpm', () {
      for (final kind in FuelStatusKind.values) {
        if (kind == FuelStatusKind.engineOff || kind == FuelStatusKind.none) continue;
        final f = SnapshotFuelSystem(kind, FuelStatusKind.none);
        for (final r in rpms) {
          for (final s in states) {
            expect(fuelSystemRowIsShown(f, snapshotRpm: r, engineState: s), isTrue,
                reason: '${kind.name} rpm $r $s');
          }
        }
      }
    });

    test('a status that reports nothing is never shown (as before)', () {
      const none = SnapshotFuelSystem(FuelStatusKind.none, FuelStatusKind.none);
      expect(fuelSystemRowIsShown(none, snapshotRpm: 0, engineState: EngineState.off), isFalse);
    });

    test('a real second system keeps the row only when the first is not "engine off"', () {
      const mixed = SnapshotFuelSystem(FuelStatusKind.closedLoop, FuelStatusKind.openLoopLoad);
      expect(fuelSystemRowIsShown(mixed, snapshotRpm: 900, engineState: EngineState.running), isTrue);
    });
  });

  group('B5 the snapshot knows its own engine speed', () {
    test('snapshotRpm is the rpm value of the snapshot', () {
      expect(snapshot([rpm(0)]).rpm, 0);
      expect(snapshot([rpm(1750)]).rpm, 1750);
    });
    test('absent when the bike did not report it', () {
      expect(snapshot([_off]).rpm, isNull);
      expect(snapshot(const []).rpm, isNull);
    });
    test('NaN is not a speed', () {
      expect(snapshot([rpm(double.nan)]).rpm, isNull);
    });
  });

  group('B5 on the screen', () {
    Future<List<String>> show(WidgetTester tester, FreezeFrameSnapshot s,
        {EngineState? engineState, String lang = 'en'}) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final settings = SettingsProvider();
      await tester.runAsync(() => settings.setLanguage(lang));
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ContextSnapshotView(
                  result: FreezeFrameAnswered(s), engineState: engineState),
            ),
          ),
        ),
      ));
      await tester.pump();
      return tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .toList();
    }

    for (final lang in ['en', 'hi']) {
      String t(String k) => AppStrings.get(k, lang);

      testWidgets('[$lang] rpm 0 in the snapshot: "Engine off" and the row label are shown',
          (tester) async {
        final xs = await show(tester, snapshot([_off, rpm(0)]), lang: lang);
        expect(xs, contains(t('fuelStatusEngineOff')));
        expect(xs, contains(t('snapFuelSystem')));
      });

      testWidgets('[$lang] rpm 800 in the snapshot: the whole row is hidden, rpm still shown',
          (tester) async {
        final xs = await show(tester, snapshot([_off, rpm(800)]),
            engineState: EngineState.off, lang: lang);
        expect(xs, isNot(contains(t('fuelStatusEngineOff'))));
        expect(xs, isNot(contains(t('snapFuelSystem'))));
        expect(xs, contains('800 RPM'));
      });

      testWidgets('[$lang] no rpm and unknown state: hidden', (tester) async {
        final xs = await show(tester, snapshot([_off]), lang: lang);
        expect(xs, isNot(contains(t('fuelStatusEngineOff'))));
        expect(xs, isNot(contains(t('snapFuelSystem'))));
      });

      testWidgets('[$lang] no rpm, engine otherwise known off: shown', (tester) async {
        final xs = await show(tester, snapshot([_off]),
            engineState: EngineState.off, lang: lang);
        expect(xs, contains(t('fuelStatusEngineOff')));
      });

      testWidgets('[$lang] no rpm, engine known running: hidden', (tester) async {
        final xs = await show(tester, snapshot([_off]),
            engineState: EngineState.running, lang: lang);
        expect(xs, isNot(contains(t('fuelStatusEngineOff'))));
      });
    }

    testWidgets('a real status (closed loop) is shown whatever the engine speed is',
        (tester) async {
      const closed = SnapshotFuelSystem(FuelStatusKind.closedLoop, FuelStatusKind.none);
      final xs = await show(tester, snapshot([closed, rpm(2400)]),
          engineState: EngineState.running);
      expect(xs, contains(AppStrings.get('fuelStatusClosed', 'en')));
    });
  });
}
