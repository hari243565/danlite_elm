/// Phase 4B (B3) — "Which adapter works best?": a short static screen, reached
/// from the Fault Codes tab help icon and from the two "nothing answered"
/// states, and saying only what the app already says.
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/constants/chassis_modules.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/adapter_help_screen.dart';
import 'package:danlite_elm/screens/dtc_screen.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/engine_sim.dart';

const fast = FaultReadTiming.scaled(0.05);

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

const helpKeys = <String>[
  'adapterHelpTitle',
  'adapterHelpIntro',
  'adapterHelpEngineTitle',
  'adapterHelpEngineBody',
  'adapterHelpOtherTitle',
  'adapterHelpOtherBody',
  'adapterHelpConnTitle',
  'adapterHelpConnBody',
  'adapterHelpCableTitle',
  'adapterHelpCableBody',
  'adapterHelpOlderTitle',
  'adapterHelpOlderBody',
  'adapterHelpBlinkTitle',
  'adapterHelpBlinkBody',
];

Future<ObdService> openTab(WidgetTester tester,
    {EngineSim? sim,
    bool connected = true,
    bool scanAbs = false,
    bool showAbs = false,
    String lang = 'en'}) async {
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
      if (scanAbs) {
        await obd.readChassisDtcs(
            vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');
      }
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
  if (showAbs) {
    await tester.tap(find.text(t('moduleAbs', lang)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  return obd;
}

Future<void> done(WidgetTester tester, ObdService obd) =>
    tester.runAsync(() => obd.disconnect());

List<String> textsOf(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B3 the screen says only what is known, briefly', () {
    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] every statement from the brief, and nothing else', (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final settings = SettingsProvider();
        await tester.runAsync(() => settings.setLanguage(lang));
        tester.view.physicalSize = const Size(900, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
            value: settings,
            child: const MaterialApp(home: AdapterHelpScreen())));
        await tester.pump();
        final xs = textsOf(tester);
        for (final k in helpKeys) {
          expect(xs, contains(t(k, lang)), reason: '$lang $k');
        }
        // Short: one title, one intro, six headings, six bodies.
        expect(xs.length, 14);
      });
    }

    test('the facts are exactly the ones the app already states', () {
      final en = AppStrings.languageTable('en');
      expect(en['adapterHelpEngineBody'], allOf(contains('ELM327'), contains('OBD-II'), contains('ignition is ON')));
      expect(en['adapterHelpOtherBody'], allOf(contains('other modules'), contains('cheap clones'), contains('STN11xx')));
      expect(en['adapterHelpConnBody'], allOf(contains('classic Bluetooth'), contains('Wi-Fi')));
      expect(en['adapterHelpCableBody'], allOf(contains('2, 3, 4 or 6-pin'), contains('16-pin')));
      expect(en['adapterHelpOlderBody'], contains('cannot read yet'));
      expect(en['adapterHelpBlinkBody'], allOf(contains('blink code'), contains('dealer tool')));
    });

    test('no brand, price, link or promise in either language', () {
      final banned = RegExp(
          r'(https?:|www\.|\.com|₹|\$|\brs\.|\brs |price|cheapest|buy |best choice|recommend|vgate|veepeak|obdlink|bafx|konnwei|amazon|flipkart)',
          caseSensitive: false);
      for (final lang in ['en', 'hi']) {
        for (final k in helpKeys) {
          expect(banned.hasMatch(t(k, lang)), isFalse, reason: '$lang $k: ${t(k, lang)}');
        }
      }
    });

    test('English and Hindi both exist, are translated, and follow the Hindi style sheet', () {
      final en = AppStrings.languageTable('en');
      final hi = AppStrings.languageTable('hi');
      for (final k in helpKeys) {
        expect(en[k], isNotNull, reason: 'en $k');
        expect(hi[k], isNotNull, reason: 'hi $k');
        expect(hi[k], isNot(en[k]), reason: '$k must be translated');
        expect(RegExp(r'[०-९]').hasMatch(hi[k]!), isFalse, reason: '$k Latin digits');
      }
      // Latin digits and the Latin-script names the style sheet keeps.
      final body = hi['adapterHelpCableBody']!;
      expect(body, contains('2, 3, 4'));
      expect(body, contains('16'));
      expect(hi['adapterHelpOtherBody'], contains('STN11xx'));
      expect(hi['adapterHelpOtherTitle'], contains('ABS'));
      expect(hi['adapterHelpEngineBody'], allOf(contains('ELM327'), contains('OBD-II')));
    });
  });

  group('B3 when the link is offered', () {
    test('the bike did not answer: yes — but not for a busy module, an answer, a refusal or a lost link', () {
      final t0 = DateTime(2026, 10, 3);
      for (final r in EngineNoAnswerReason.values) {
        expect(engineReadOffersAdapterHelp(EngineNoAnswer(r, t0)),
            r != EngineNoAnswerReason.moduleBusy,
            reason: r.name);
      }
      expect(engineReadOffersAdapterHelp(null), isFalse);
      expect(engineReadOffersAdapterHelp(EngineAnswered(const [], t0)), isFalse);
      expect(engineReadOffersAdapterHelp(EngineRefused(0x22, t0)), isFalse);
      expect(engineReadOffersAdapterHelp(EngineLinkLost(t0)), isFalse);
    });

    test('the ABS module did not reply, or the adapter cannot address it: yes; nothing else', () {
      const yes = {
        ChassisScanOutcome.noModuleResponse,
        ChassisScanOutcome.addressingUnsupported,
      };
      for (final o in ChassisScanOutcome.values) {
        expect(absOutcomeOffersAdapterHelp(o), yes.contains(o), reason: o.name);
      }
    });
  });

  group('B3 how it is reached', () {
    testWidgets('the help icon opens it — connected', (tester) async {
      final obd = await openTab(tester);
      await tester.tap(find.byKey(const ValueKey('adapter-help-icon')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(AdapterHelpScreen), findsOneWidget);
      await done(tester, obd);
    });

    testWidgets('the help icon opens it — disconnected', (tester) async {
      final obd = await openTab(tester, connected: false);
      await tester.tap(find.byKey(const ValueKey('adapter-help-icon')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(AdapterHelpScreen), findsOneWidget);
      await done(tester, obd);
    });

    testWidgets('the help icon has a spoken label', (tester) async {
      final obd = await openTab(tester);
      expect(find.byTooltip(t('adapterHelpTitle')), findsOneWidget);
      await done(tester, obd);
    });

    testWidgets('"The bike did not answer" links to it', (tester) async {
      final obd = await openTab(tester, sim: EngineSim(mode03: 'NO DATA'));
      expect(find.text(t('dtcNoAnswerTitle')), findsWidgets);
      final link = find.byKey(const ValueKey('adapter-help-link'));
      expect(link, findsOneWidget);
      await tester.tap(link);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(AdapterHelpScreen), findsOneWidget);
      await done(tester, obd);
    });

    testWidgets('an answered read (with or without codes) shows no link', (tester) async {
      final obd = await openTab(tester);
      expect(find.byKey(const ValueKey('adapter-help-link')), findsNothing);
      await done(tester, obd);
    });

    testWidgets('"No reply from the ABS module" links to it', (tester) async {
      final obd = await openTab(tester,
          sim: EngineSim(mode03: '43 00'), scanAbs: true, showAbs: true);
      expect(obd.chassisScanOutcome, ChassisScanOutcome.noModuleResponse);
      final link = find.byKey(const ValueKey('adapter-help-link'));
      expect(link, findsOneWidget);
      await tester.tap(link);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(AdapterHelpScreen), findsOneWidget);
      await done(tester, obd);
    });

    testWidgets('an ABS module that answered shows no link', (tester) async {
      final obd = await openTab(
          tester,
          sim: EngineSim(mode03: '43 00')
            ..udsModules['7B0'] = '7B8 07 59 02 FF 50 58 11 2F',
          scanAbs: true,
          showAbs: true);
      expect(find.byKey(const ValueKey('adapter-help-link')), findsNothing);
      await done(tester, obd);
    });

    testWidgets('an ABS tab never scanned shows no link', (tester) async {
      final obd = await openTab(tester, showAbs: true);
      expect(find.byKey(const ValueKey('adapter-help-link')), findsNothing);
      await done(tester, obd);
    });
  });
}
