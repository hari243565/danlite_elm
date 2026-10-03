/// Phase 4B (B2, and the entry points of B3 and B4) — the Fault Codes tab
/// reaches the lookup, the scan history, the adapter help and the blink-code
/// references with clear, labelled controls, connected or not.
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/code_lookup_screen.dart';
import 'package:danlite_elm/screens/dtc_screen.dart';
import 'package:danlite_elm/screens/scan_history_screen.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/engine_sim.dart';

const fast = FaultReadTiming.scaled(0.05);

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

/// The real screen, connected (with a settled engine read) or not.
Future<ObdService> openScreen(
  WidgetTester tester, {
  bool connected = true,
  String lang = 'en',
  EngineSim? sim,
}) async {
  late ObdService obd;
  final settings = SettingsProvider();
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.setLanguage(lang);
    obd = ObdService(sim ?? EngineSim(mode03: '43 00'), faultTiming: fast);
    if (connected) {
      expect(await obd.connectBluetooth(simDevice), isTrue);
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
    }
  });
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<VehicleProvider>(create: (_) => VehicleProvider()),
      ChangeNotifierProvider<ObdService>.value(value: obd),
    ],
    child: const MaterialApp(home: DtcScreen(autoScan: false)),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  return obd;
}

Future<void> closeScreen(WidgetTester tester, ObdService obd) async {
  await tester.runAsync(() => obd.disconnect());
}

Finder tool(String name) => find.byKey(ValueKey('tool-$name'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B2 look up a code, scan history', () {
    for (final connected in [true, false]) {
      final where = connected ? 'connected' : 'disconnected';

      testWidgets('[$where] both are labelled controls on the tab', (tester) async {
        final obd = await openScreen(tester, connected: connected);
        expect(tool('lookup'), findsOneWidget);
        expect(tool('history'), findsOneWidget);
        expect(find.descendant(of: tool('lookup'), matching: find.text(t('lookupTitle'))),
            findsOneWidget);
        expect(find.descendant(of: tool('history'), matching: find.text(t('historyTitle'))),
            findsOneWidget);
        await closeScreen(tester, obd);
      });

      testWidgets('[$where] Look up a code opens the existing lookup screen', (tester) async {
        final obd = await openScreen(tester, connected: connected);
        await tester.tap(tool('lookup'));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.byType(CodeLookupScreen), findsOneWidget);
        await closeScreen(tester, obd);
      });

      testWidgets('[$where] Scan history opens the existing history screen', (tester) async {
        final obd = await openScreen(tester, connected: connected);
        await tester.tap(tool('history'));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.byType(ScanHistoryScreen), findsOneWidget);
        await closeScreen(tester, obd);
      });
    }

    testWidgets('[hi] the labels are Hindi', (tester) async {
      final obd = await openScreen(tester, lang: 'hi');
      expect(find.descendant(of: tool('lookup'), matching: find.text(t('lookupTitle', 'hi'))),
          findsOneWidget);
      expect(find.descendant(of: tool('history'), matching: find.text(t('historyTitle', 'hi'))),
          findsOneWidget);
      await closeScreen(tester, obd);
    });

    testWidgets('the older app-bar icons still work', (tester) async {
      final obd = await openScreen(tester);
      await tester.tap(find.byTooltip(t('lookupTitle')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(CodeLookupScreen), findsOneWidget);
      await closeScreen(tester, obd);
    });
  });
}
