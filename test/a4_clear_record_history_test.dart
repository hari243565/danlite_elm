/// Phase A-4 (S2) — the internal Clear Codes record is shown in the History
/// DETAIL, with neutral wording, and never on the Clear Codes screen.
///
/// The record itself is Phase 1B's (`clear_check` sessions). What is new is
/// only where it is read: a History row (time only) opening a detail that says
/// when Clear was attempted and what the bike reported afterwards.
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/knowledge/clear_record.dart';
import 'package:danlite_elm/knowledge/history_report.dart';
import 'package:danlite_elm/knowledge/knowledge_service.dart';
import 'package:danlite_elm/knowledge/scan_history.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/dtc_screen.dart';
import 'package:danlite_elm/screens/scan_history_screen.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/engine_sim.dart';
import 'support/knowledge_harness.dart';

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

final _checkedAt = DateTime.utc(2026, 10, 2, 9, 31, 20);
final _attemptedAt = DateTime.utc(2026, 10, 2, 9, 31, 12);

ScanSessionInput _clearRecord(ClearCheckOutcome outcome,
        {List<String> codes = const <String>[], bool withAttemptTime = true}) =>
    ScanSessionInput(
      kind: SessionKind.clearCheck,
      startedAt: _checkedAt,
      reachState: outcome.db,
      clearOutcome: outcome,
      coalesce: false,
      preClear: <String, Object?>{
        'snapshot': true,
        'codes': codes,
        if (withAttemptTime) 'attempted_at': _attemptedAt.toIso8601String(),
      },
      faults: [
        for (final c in codes)
          ScanFaultInput(FaultRecord.fromObdCode(c,
              source: ReadSource.mode03, readAt: _checkedAt)),
      ],
    );

Future<List<String>> _openHistory(WidgetTester tester,
    {required String lang, required List<ScanSessionInput> sessions}) async {
  late SettingsProvider settings;
  late KnowledgeService k;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settings = SettingsProvider();
    await settings.setLanguage(lang);
    k = await startedKnowledge();
    for (final s in sessions) {
      await k.history!.save(s);
    }
  });
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<VehicleProvider>.value(value: VehicleProvider()),
        ChangeNotifierProvider<KnowledgeService?>.value(value: k),
      ],
      child: const MaterialApp(home: ScanHistoryScreen()),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
  addTearDown(() async => tester.runAsync(() async => k.store!.close()));
  return _texts(tester);
}

List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .toList();

Future<List<String>> _openFirstRow(WidgetTester tester, [String lang = 'en']) async {
  await tester.tap(find.text(t('clearCodes', lang)).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return _texts(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the three outcomes, in the detail', () {
    for (final (outcome, key, codes) in [
      (ClearCheckOutcome.codesReturned, 'historyClearAfterCodes', ['P0120', 'P0300']),
      (ClearCheckOutcome.clearedVerified, 'historyClearAfterNone', <String>[]),
      (ClearCheckOutcome.couldNotVerify, 'historyClearAfterUnknown', <String>[]),
    ]) {
      for (final lang in ['en', 'hi']) {
        testWidgets('[$lang] ${outcome.db}', (tester) async {
          final list = await _openHistory(tester,
              lang: lang, sessions: [_clearRecord(outcome, codes: codes)]);
          // The row says only that Clear was attempted, and when.
          expect(list, contains(t('clearCodes', lang)));
          expect(list.any((x) => x.contains(t('historyClearAfterNone', lang))), isFalse);
          expect(list.any((x) => x.contains(t('historyClearAfterUnknown', lang))), isFalse);

          final detail = await _openFirstRow(tester, lang);
          final attempt = t('historyClearAttempt', lang)
              .replaceAll('{time}', formatLocal(_attemptedAt));
          final after = t(key, lang).replaceAll('{n}', '${codes.length}');
          // One paragraph: "Clear attempted at …. After clearing: …".
          expect(detail, contains('$attempt $after'));
          // A bike that still reported codes shows them as ordinary rows.
          for (final c in codes) {
            expect(detail, contains(c));
          }
          if (outcome != ClearCheckOutcome.codesReturned) {
            expect(detail.any((x) => x.contains('P0')), isFalse);
          }
        });
      }
    }
  });

  testWidgets('an old record with no stored attempt time falls back to the check time',
      (tester) async {
    await _openHistory(tester, lang: 'en', sessions: [
      _clearRecord(ClearCheckOutcome.clearedVerified, withAttemptTime: false),
    ]);
    final detail = await _openFirstRow(tester);
    expect(
        detail,
        contains('${t('historyClearAttempt').replaceAll('{time}', formatLocal(_checkedAt))} '
            '${t('historyClearAfterNone')}'));
  });

  testWidgets('no neutral sentence is in the History LIST — detail only', (tester) async {
    final list = await _openHistory(tester, lang: 'en', sessions: [
      _clearRecord(ClearCheckOutcome.codesReturned, codes: ['P0120']),
    ]);
    expect(list.any((x) => x.contains('After clearing')), isFalse);
    expect(list.any((x) => x.contains('Clear attempted')), isFalse);
  });

  test('Share never carries the Clear record (unchanged from Phase 1B)', () {
    final text = buildHistoryReport([
      ScanSession(
        id: 1,
        kind: SessionKind.clearCheck,
        startedAt: _checkedAt,
        lastSeenAt: _checkedAt,
        repeatCount: 1,
        reachState: 'codes_returned',
        clearOutcome: ClearCheckOutcome.codesReturned,
      ),
    ], tr: (k) => t(k), meaning: (f, kind) => '');
    expect(text.contains('After clearing'), isFalse);
    expect(text.contains('Clear attempted'), isFalse);
  });

  testWidgets('the Clear Codes screen itself never shows the record', (tester) async {
    late SettingsProvider settings;
    late ObdService obd;
    final sim = EngineSim(mode03: '7E8 04 43 01 01 20');
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      settings = SettingsProvider();
      obd = await connectSim(sim, timing: const FaultReadTiming.scaled(0.05));
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
    });
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<VehicleProvider>.value(value: VehicleProvider()),
        ChangeNotifierProvider<ObdService>.value(value: obd),
        ChangeNotifierProvider<KnowledgeService?>.value(value: null),
      ],
      child: const MaterialApp(home: DtcScreen(autoScan: false)),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    final xs = _texts(tester);
    expect(xs.any((x) => x.contains('After clearing')), isFalse);
    expect(xs.any((x) => x.contains('Clear attempted')), isFalse);
    await tester.runAsync(() async {
      await obd.disconnect();
      await sim.close();
    });
  });

  group('the attempt time is recorded when Clear is attempted', () {
    test('a snapshot carries the time it was taken', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 01 20');
      final obd = await connectSim(sim, timing: const FaultReadTiming.scaled(0.05));
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
      final now = DateTime.now();
      final pre = PreClearSnapshot.capture(obd, now);
      expect(pre.toJson()['attempted_at'], now.toUtc().toIso8601String());
      expect(pre.toJson()['snapshot'], isTrue);
      await obd.disconnect();
      await sim.close();
    });

    test('and so does "no snapshot"', () async {
      final sim = EngineSim(mode03: '7E8 04 43 01 01 20');
      final obd = await connectSim(sim, timing: const FaultReadTiming.scaled(0.05));
      // No read yet → no snapshot, but the attempt time is still kept.
      final now = DateTime.now();
      final pre = PreClearSnapshot.capture(obd, now);
      expect(pre.present, isFalse);
      expect(pre.toJson()['snapshot'], isFalse);
      expect(pre.toJson()['attempted_at'], now.toUtc().toIso8601String());
      await obd.disconnect();
      await sim.close();
    });
  });
}
