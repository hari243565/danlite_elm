/// Shared harness for the Phase A-4 widget tests: the REAL ObdService over the
/// simulator inside the REAL fault screen, English or Hindi.
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

import 'context_sim.dart';
import 'engine_sim.dart';

const fast = FaultReadTiming.scaled(0.05);
String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);
String ta(String key, Map<String, String> args, [String lang = 'en']) {
  var s = t(key, lang);
  args.forEach((k, v) => s = s.replaceAll('{$k}', v));
  return s;
}

class Env {
  Env(this.settings, this.obd, this.sim);
  final SettingsProvider settings;
  final ObdService obd;
  final EngineSim sim;

  Widget wrap(Widget home) => MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<VehicleProvider>.value(value: VehicleProvider()),
          ChangeNotifierProvider<ObdService>.value(value: obd),
          ChangeNotifierProvider<KnowledgeService?>.value(value: null),
        ],
        child: MaterialApp(home: home),
      );

  Future<void> close(WidgetTester tester) => tester.runAsync(() async {
        await obd.disconnect();
        await sim.close();
      });
}

Future<Env> startScreen(WidgetTester tester, EngineSim sim,
    {String lang = 'en', FaultReadTiming timing = fast}) async {
  late Env env;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsProvider();
    await settings.setLanguage(lang);
    final obd = await connectSim(sim, timing: timing);
    await obd.readEngineDtcs();
    await obd.whenEngineReadSettled();
    env = Env(settings, obd, sim);
  });
  tester.view.physicalSize = const Size(1200, 7000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(env.wrap(const DtcScreen(autoScan: false)));
  await tester.pump(const Duration(milliseconds: 50));
  return env;
}

List<String> texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .toList();

bool anyHas(List<String> xs, String s) => xs.any((x) => x.contains(s));

/// Pump until the context read is over.
Future<void> settle(WidgetTester tester, ObdService obd) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (!obd.contextReadInFlight && i > 2) break;
  }
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> openDetails(WidgetTester tester, Env env) async {
  await tester.tap(find.byKey(const ValueKey('contextToggle')).first);
  await settle(tester, env.obd);
}

Future<void> openSheet(WidgetTester tester, Env env) async {
  await tester.tap(find.byTooltip(t('freezeFrame', env.settings.locale.languageCode)));
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester, env.obd);
}

EngineSim bike({
  String mode03 = '7E8 04 43 01 03 01', // P0301
  Map<String, String?> snapshot = const <String, String?>{},
  Map<String, String?>? context,
}) {
  final sim = EngineSim(mode03: mode03);
  sim.extra
    ..addAll(snapshot.isEmpty ? snapshotBike() : snapshot)
    ..addAll(context ?? contextBike());
  return sim;
}

