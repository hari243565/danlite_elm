/// Phase 4B (B1) — the section cards on the real Fault Codes screen.
///
/// The REAL ObdService runs over the simulator and the REAL DtcScreen renders
/// what its scans left behind. Reply shapes are hand-written from documented
/// ELM327 behaviour, not recorded from a real bike.
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/dtc_screen.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/engine_sim.dart';

const fast = FaultReadTiming.scaled(0.05);

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

/// P0133 and U0100 in one Mode 03 answer.
const twoCodes = '7E8 06 43 02 C1 00 01 33';

/// One C0035 in the ENGINE computer's list.
const cCodeFromEngine = '7E8 04 43 01 40 35';

/// What the screen shows, and the handles to drive it.
class Screen {
  Screen(this.tester, this.obd, this.sim, this.lang);
  final WidgetTester tester;
  final ObdService obd;
  final EngineSim sim;
  final String lang;

  List<String> get texts => tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
      .toList();

  Finder card(String name) => find.byKey(ValueKey('section-card-$name'));

  /// Every Text inside one section card.
  List<String> inCard(String name) => tester
      .widgetList<Text>(find.descendant(of: card(name), matching: find.byType(Text)))
      .map((w) => w.data ?? '')
      .toList();

  Future<void> tap(Finder f) async {
    await tester.tap(f);
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> close() async {
    await tester.runAsync(() async {
      await obd.disconnect();
      await sim.close();
    });
  }
}

Future<Screen> open(
  WidgetTester tester,
  EngineSim sim, {
  String lang = 'en',
  bool readEngine = true,
  bool scanAbs = false,
  bool showAbs = false,
}) async {
  late ObdService obd;
  final settings = SettingsProvider();
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.setLanguage(lang);
    obd = ObdService(sim, faultTiming: fast);
    expect(await obd.connectBluetooth(simDevice), isTrue);
    if (readEngine) {
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
    }
    if (scanAbs) {
      await obd.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');
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
  final s = Screen(tester, obd, sim, lang);
  if (showAbs) await s.tap(find.text(t('moduleAbs', lang)));
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B1 cards on the screen', () {
    testWidgets('six cards and "All", in order, once connected', (tester) async {
      final s = await open(tester, EngineSim(mode03: twoCodes));
      for (final n in ['all', 'engine', 'brakes', 'body', 'network', 'transmission', 'other']) {
        expect(s.card(n), findsOneWidget, reason: n);
      }
      final xs = [
        for (final n in ['engine', 'brakes', 'body', 'network', 'transmission', 'other'])
          tester.getTopLeft(s.card(n)).dx
      ];
      expect([...xs]..sort(), xs, reason: 'left to right in the owner\'s order');
      await s.close();
    });

    testWidgets('no cards while disconnected (nothing could have been scanned)',
        (tester) async {
      final settings = SettingsProvider();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<VehicleProvider>(create: (_) => VehicleProvider()),
          ChangeNotifierProvider<ObdService>(
              create: (_) => ObdService(EngineSim(), faultTiming: fast)),
        ],
        child: const MaterialApp(home: DtcScreen(autoScan: false)),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('section-card-engine')), findsNothing);
    });

    testWidgets('engine answered with codes: N faults, badge, and other cards say so',
        (tester) async {
      final s = await open(tester, EngineSim(mode03: twoCodes));
      expect(s.inCard('engine'), containsAll(['1', t('sectionFaultOne')]));
      expect(s.inCard('network'), containsAll(['1', t('sectionFoundN').replaceAll('{n}', '1')]));
      expect(s.inCard('body'), contains(t('sectionNoneFound')));
      expect(s.inCard('body'), contains(t('sectionBasedOn')));
      expect(s.inCard('transmission'), contains(t('sectionNoneFound')));
      expect(s.inCard('other'), contains(t('sectionNoneFound')));
      // The ABS module was never scanned and must not be called clean.
      expect(s.inCard('brakes'), contains(t('sectionNotScanned')));
      expect(s.inCard('brakes'), isNot(contains(t('sectionNoFaults'))));
      await s.close();
    });

    testWidgets('engine answered with nothing: no faults', (tester) async {
      final s = await open(tester, EngineSim(mode03: '43 00'));
      expect(s.inCard('engine'), contains(t('sectionNoFaults')));
      expect(s.inCard('body'), contains(t('sectionNoneFound')));
      expect(s.inCard('brakes'), contains(t('sectionNotScanned')));
      await s.close();
    });

    testWidgets('bike did not answer: the engine card says so and the rest stay "not scanned yet"',
        (tester) async {
      final s = await open(tester, EngineSim(mode03: 'NO DATA'));
      expect(s.inCard('engine'), contains(t('dtcNoAnswerTitle')));
      expect(s.inCard('engine'), isNot(contains(t('sectionNoFaults'))));
      for (final n in ['body', 'network', 'transmission', 'other']) {
        expect(s.inCard(n), contains(t('sectionNotScannedYet')), reason: n);
        expect(s.inCard(n), isNot(contains(t('sectionNoneFound'))), reason: n);
      }
      await s.close();
    });

    testWidgets('refused request', (tester) async {
      final s = await open(tester, EngineSim(mode03: '7F 03 22'));
      expect(s.inCard('engine'), contains(t('dtcRefusedTitle')));
      await s.close();
    });

    testWidgets('never read: engine and ABS both "not scanned"', (tester) async {
      final s = await open(tester, EngineSim(), readEngine: false);
      expect(s.inCard('engine'), contains(t('sectionNotScanned')));
      expect(s.inCard('brakes'), contains(t('sectionNotScanned')));
      expect(s.inCard('body'), contains(t('sectionNotScannedYet')));
      await s.close();
    });

    testWidgets('ABS module did not reply: "No reply from the ABS module"',
        (tester) async {
      final s = await open(tester, EngineSim(mode03: 'NO DATA'), scanAbs: true);
      expect(s.inCard('brakes'), contains(t('absNoModule')));
      expect(s.inCard('body'), contains(t('sectionNotScannedYet')));
      await s.close();
    });

    testWidgets('ABS faults found: N faults and a badge on Brakes & ABS',
        (tester) async {
      final s = await open(
          tester,
          EngineSim(mode03: '43 00')..udsModules['7B0'] = '7B8 07 59 02 FF 50 58 11 2F',
          scanAbs: true);
      expect(s.obd.chassisDtcCodes, isNotEmpty);
      expect(s.inCard('brakes'), contains(t('sectionFaultOne')));
      expect(s.inCard('brakes'), contains('1'));
      await s.close();
    });

    testWidgets('a C code in the ENGINE list: counted under Brakes & ABS and says the engine scan reported it',
        (tester) async {
      final s = await open(tester, EngineSim(mode03: cCodeFromEngine));
      expect(s.inCard('brakes'), contains(t('sectionFaultOne')));
      expect(s.inCard('brakes'), contains(t('sectionFromEngineScan')));
      expect(s.inCard('brakes'), isNot(contains(t('sectionNoFaults'))));
      await s.close();
    });
  });

  group('B1 filter', () {
    testWidgets('tapping a card shows only that section; All brings everything back',
        (tester) async {
      final s = await open(tester, EngineSim(mode03: twoCodes));
      expect(s.texts, containsAll(['P0133', 'U0100']));

      await s.tap(s.card('network'));
      expect(s.texts, contains('U0100'));
      expect(s.texts, isNot(contains('P0133')));

      await s.tap(s.card('engine'));
      expect(s.texts, contains('P0133'));
      expect(s.texts, isNot(contains('U0100')));

      await s.tap(s.card('all'));
      expect(s.texts, containsAll(['P0133', 'U0100']));
      await s.close();
    });

    testWidgets('tapping the chosen card again also resets', (tester) async {
      final s = await open(tester, EngineSim(mode03: twoCodes));
      await s.tap(s.card('network'));
      expect(s.texts, isNot(contains('P0133')));
      await s.tap(s.card('network'));
      expect(s.texts, containsAll(['P0133', 'U0100']));
      await s.close();
    });

    testWidgets('an empty section says why, in the card\'s own words', (tester) async {
      final s = await open(tester, EngineSim(mode03: twoCodes));
      await s.tap(s.card('body'));
      expect(s.texts, isNot(contains('P0133')));
      expect(s.texts, isNot(contains('U0100')));
      expect(s.texts, contains(t('sectionNoneFound')));
      await s.close();
    });

    testWidgets('a section nobody scanned says "not scanned", not "no codes"',
        (tester) async {
      final s = await open(tester, EngineSim(mode03: 'NO DATA'));
      await s.tap(s.card('brakes'));
      expect(s.texts, contains(t('sectionNotScanned')));
      expect(s.texts, isNot(contains(t('sectionNoFaults'))));
      await s.close();
    });

    testWidgets('engine and ABS codes are one list under their own sections, from either module view',
        (tester) async {
      final s = await open(
          tester,
          EngineSim(mode03: twoCodes)..udsModules['7B0'] = '7B8 07 59 02 FF 50 58 11 2F',
          scanAbs: true);
      // From the ENGINE view, the Brakes & ABS card lists the ABS module's code.
      await s.tap(s.card('brakes'));
      expect(s.texts, contains('C1058'));
      expect(s.texts, isNot(contains('P0133')));
      // From the ABS view, the Network card lists the engine list's U code.
      await s.tap(find.text(t('moduleAbs')));
      await s.tap(s.card('network'));
      expect(s.texts, contains('U0100'));
      expect(s.texts, isNot(contains('C1058')));
      await s.close();
    });

    testWidgets('the filter keeps the module selector, Read Codes and Clear Codes working',
        (tester) async {
      final s = await open(tester, EngineSim(mode03: twoCodes));
      await s.tap(s.card('network'));
      expect(find.text(t('moduleEngine')), findsOneWidget);
      expect(find.text(t('moduleAbs')), findsOneWidget);
      expect(find.text(t('readCodes')), findsOneWidget);
      final clear = tester.widget<ElevatedButton>(
          find.ancestor(of: find.text(t('clearCodes')), matching: find.byType(ElevatedButton)));
      expect(clear.onPressed, isNotNull,
          reason: 'Clear Codes keys on the engine list, not on the filter');
      await s.close();
    });
  });

  group('B1 strings', () {
    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] every card is in the rider\'s language', (tester) async {
        final s = await open(tester, EngineSim(mode03: twoCodes), lang: lang);
        for (final k in [
          'sectionEngine',
          'sectionBrakes',
          'sectionBody',
          'sectionNetwork',
          'sectionTransmission',
          'sectionOther',
          'sectionAll',
        ]) {
          expect(s.texts, contains(t(k, lang)), reason: k);
        }
        expect(s.inCard('engine'), contains(t('sectionFaultOne', lang)));
        expect(s.inCard('body'), contains(t('sectionNoneFound', lang)));
        expect(s.inCard('body'), contains(t('sectionBasedOn', lang)));
        await s.close();
      });
    }

    test('every section string exists in English and Hindi, translated, with the same placeholders', () {
      const keys = [
        'sectionEngine', 'sectionBrakes', 'sectionBody', 'sectionNetwork',
        'sectionTransmission', 'sectionOther', 'sectionAll', 'sectionNotScanned',
        'sectionNotScannedYet', 'sectionScanning', 'sectionFaultOne',
        'sectionFaultsN', 'sectionFoundN', 'sectionNoFaults', 'sectionNoneFound',
        'sectionBasedOn', 'sectionFromEngineScan', 'sectionEngineBusy',
        'sectionNotReadable',
      ];
      final en = AppStrings.languageTable('en');
      final hi = AppStrings.languageTable('hi');
      final ph = RegExp(r'\{[a-z]+\}');
      for (final k in keys) {
        expect(en[k], isNotNull, reason: 'en $k');
        expect(hi[k], isNotNull, reason: 'hi $k');
        if (k != 'sectionNetwork') {
          expect(hi[k], isNot(en[k]), reason: '$k must be translated');
        }
        expect(ph.allMatches(hi[k]!).map((m) => m[0]).toSet(),
            ph.allMatches(en[k]!).map((m) => m[0]).toSet(),
            reason: k);
        expect(RegExp(r'[०-९]').hasMatch(hi[k]!), isFalse, reason: '$k Latin digits');
      }
    });
  });
}
