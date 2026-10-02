/// Phase A-4 (S3) — "Codes cleared successfully" must also appear in DEBUG
/// builds.
///
/// `_clearOutcomeMessage` used `context.tr`, which is `context.watch`, from an
/// async handler (after `await obd.clearDtcs()`). Provider asserts that a
/// listening lookup only happens during `build`, so in a debug build the
/// assertion threw before `showSnackBar` ran and the rider saw nothing. Release
/// builds strip the assertion, which is why only debug showed it.
///
/// Flutter's test binding runs with assertions ON — the same condition as a
/// debug build — so running the real flow here is the debug-mode test. The
/// message, its colour, its duration and the moment it appears are unchanged.
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/knowledge/knowledge_service.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/dtc_screen.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/engine_sim.dart';

const _fast = FaultReadTiming.scaled(0.05);

Future<void> _clearFlow(WidgetTester tester, String lang) async {
  late SettingsProvider settings;
  late VehicleProvider vehicles;
  late ObdService obd;
  final sim = EngineSim(mode03: '7E8 04 43 01 01 20')..extra['04'] = '7E8 01 44';
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    settings = SettingsProvider();
    await settings.setLanguage(lang);
    vehicles = VehicleProvider();
    obd = await connectSim(sim, timing: _fast);
    await obd.readEngineDtcs();
    await obd.whenEngineReadSettled();
  });
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<VehicleProvider>.value(value: vehicles),
      ChangeNotifierProvider<ObdService>.value(value: obd),
      ChangeNotifierProvider<KnowledgeService?>.value(value: null),
    ],
    child: const MaterialApp(home: DtcScreen(autoScan: false)),
  ));
  await tester.pump(const Duration(milliseconds: 50));

  final clearLabel = AppStrings.get('clearCodes', lang);
  await tester.tap(find.text(clearLabel));
  await tester.pump(const Duration(milliseconds: 300));
  // The confirmation dialog's own red button.
  await tester.tap(find.descendant(
      of: find.byType(AlertDialog), matching: find.text(clearLabel)));
  // Let the real service run Mode 04 and the refresh read. The message is
  // shown for two seconds, so look for it as time passes rather than once.
  final message = find.text(AppStrings.get('clearSucceeded', lang));
  var shown = false;
  for (var i = 0; i < 100 && !shown; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    shown = message.evaluate().isNotEmpty;
  }

  expect(tester.takeException(), isNull,
      reason: 'the handler must not throw a Provider assertion in debug');
  expect(shown, isTrue, reason: 'the success message must appear');
  expect(message, findsOneWidget);

  // Let the SnackBar's own timer and the silent after-check finish.
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(() async {
    await obd.disconnect();
    await sim.close();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('this run really has assertions enabled (it is a debug-mode test)', () {
    var assertionsOn = false;
    assert(assertionsOn = true);
    expect(assertionsOn, isTrue);
  });

  testWidgets('[en] Codes cleared successfully shows in debug mode', (tester) async {
    await _clearFlow(tester, 'en');
  });

  testWidgets('[hi] Codes cleared successfully shows in debug mode', (tester) async {
    await _clearFlow(tester, 'hi');
  });
}
