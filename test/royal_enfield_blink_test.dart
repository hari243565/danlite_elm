/// Phase 4B (B4) — the Royal Enfield older-EFI blink-code reference.
///
/// A manual look-up, NOT a scan. The table is the Royal Enfield Bullet Classic
/// EFI service manual, pages 163 to 164 (read in full by the owner's assistant
/// on 2026-10-01). It applies only to the Bullet Classic EFI and Bullet
/// Electra EFI of the UCE era, and says so.
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/constants/royal_enfield_blink.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/blink_references_screen.dart';
import 'package:danlite_elm/screens/dtc_screen.dart';
import 'package:danlite_elm/screens/honda_blink_reference_screen.dart';
import 'package:danlite_elm/screens/royal_enfield_blink_reference_screen.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/engine_sim.dart';

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

/// The owner's table, verbatim: long, short, dealer-tool code, meaning, effect.
const manual = <(int, int, String, String, ReBlinkEffect)>[
  (0, 6, 'P0120', 'Throttle position sensor circuit', ReBlinkEffect.runsUnderperforms),
  (0, 9, 'P0105', 'Manifold pressure sensor circuit', ReBlinkEffect.runsUnderperforms),
  (1, 1, 'P0195', 'Engine oil temperature sensor circuit', ReBlinkEffect.runsUnderperforms),
  (1, 7, 'P0130', 'Oxygen sensor circuit', ReBlinkEffect.runsUnderperforms),
  (4, 5, 'P0135', 'Oxygen sensor heater circuit', ReBlinkEffect.runsUnderperforms),
  (1, 5, 'P1630', 'Rollover (tip-over) sensor circuit', ReBlinkEffect.cranksNoStart),
  (3, 3, 'P0201', 'Fuel injector circuit', ReBlinkEffect.cranksNoStart),
  (3, 7, 'P0351', 'Ignition coil circuit', ReBlinkEffect.cranksNoStart),
  (4, 1, 'P0230', 'Fuel pump circuit', ReBlinkEffect.cranksNoStart),
  (6, 6, 'P0335', 'Crankshaft position sensor circuit', ReBlinkEffect.cranksNoStart),
];

const newKeys = <String>[
  'blinkRefsTitle',
  'blinkRefsIntro',
  'blinkRefsRoyal',
  'blinkRefsRoyalSub',
  'blinkRefsHondaSub',
  'reBlinkTitle',
  'reBlinkAppliesTitle',
  'reBlinkApplies',
  'reBlinkIntro',
  'reBlinkHowTo',
  'reBlinkHowToBody',
  'reBlinkNotGiven',
  'reBlinkChoose',
  'reBlinkNoMatch',
  'reBlinkNoMatchDesc',
  'reBlinkDealerCode',
  'reBlinkMfrCode',
  'reBlinkEffectRuns',
  'reBlinkEffectNoStart',
  'reBlinkSource',
  'reBlinkMeaningTps',
  'reBlinkMeaningMap',
  'reBlinkMeaningEot',
  'reBlinkMeaningO2',
  'reBlinkMeaningO2Heater',
  'reBlinkMeaningRollover',
  'reBlinkMeaningInjector',
  'reBlinkMeaningCoil',
  'reBlinkMeaningFuelPump',
  'reBlinkMeaningCrank',
];

List<String> textsOf(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .toList();

Future<void> openReScreen(WidgetTester tester, {String lang = 'en'}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final settings = SettingsProvider();
  await tester.runAsync(() => settings.setLanguage(lang));
  tester.view.physicalSize = const Size(900, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: const MaterialApp(home: RoyalEnfieldBlinkReferenceScreen())));
  await tester.pump();
}

Finder pick(Key row, int n) => find.descendant(
    of: find.byKey(row), matching: find.text('$n'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B4 the table is the manual\'s table, row for row', () {
    test('exactly ten rows, in the owner\'s order', () {
      expect(kRoyalEnfieldBlinkTable.length, 10);
      for (var i = 0; i < manual.length; i++) {
        final m = manual[i];
        final e = kRoyalEnfieldBlinkTable[i];
        expect((e.longFlashes, e.shortFlashes, e.dealerCode, e.effect),
            (m.$1, m.$2, m.$3, m.$5),
            reason: 'row $i');
        expect(t(e.meaningKey), m.$4, reason: 'row $i meaning');
      }
    });

    for (final m in manual) {
      test('${m.$1},${m.$2} -> ${m.$3} ${m.$4}', () {
        final e = lookupRoyalEnfieldBlink(m.$1, m.$2);
        expect(e, isNotNull);
        expect(e!.dealerCode, m.$3);
        expect(e.effect, m.$5);
        expect(t(e.meaningKey), m.$4);
      });
    }

    test('P1630 is the only manufacturer code', () {
      expect([
        for (final e in kRoyalEnfieldBlinkTable)
          if (e.manufacturerCode) e.dealerCode
      ], ['P1630']);
    });

    test('five run but under-perform, five crank but will not start', () {
      expect(kRoyalEnfieldBlinkTable.where((e) => e.effect == ReBlinkEffect.runsUnderperforms).length, 5);
      expect(kRoyalEnfieldBlinkTable.where((e) => e.effect == ReBlinkEffect.cranksNoStart).length, 5);
    });

    test('no two rows share a pattern or a dealer code', () {
      expect({for (final e in kRoyalEnfieldBlinkTable) e.pattern}.length, 10);
      expect({for (final e in kRoyalEnfieldBlinkTable) e.dealerCode}.length, 10);
    });
  });

  group('B4 no match and input limits', () {
    test('every pattern 0..9 x 0..9 that is not a row has no match', () {
      final rows = {for (final e in kRoyalEnfieldBlinkTable) '${e.longFlashes}-${e.shortFlashes}'};
      var misses = 0;
      for (var l = 0; l <= kReBlinkMaxCount; l++) {
        for (var s = 0; s <= kReBlinkMaxCount; s++) {
          final e = lookupRoyalEnfieldBlink(l, s);
          if (rows.contains('$l-$s')) {
            expect(e, isNotNull, reason: '$l-$s');
          } else {
            expect(e, isNull, reason: '$l-$s');
            misses++;
          }
        }
      }
      expect(misses, 90);
    });

    test('the order matters: long first, short second', () {
      expect(lookupRoyalEnfieldBlink(6, 0), isNull);
      expect(lookupRoyalEnfieldBlink(0, 6)?.dealerCode, 'P0120');
      expect(lookupRoyalEnfieldBlink(1, 4), isNull);
      expect(lookupRoyalEnfieldBlink(4, 1)?.dealerCode, 'P0230');
    });

    test('counts outside 0..9 never match', () {
      expect(kReBlinkMaxCount, 9);
      for (final bad in [-1, 10, 11, 99, 100, -100]) {
        expect(lookupRoyalEnfieldBlink(bad, 6), isNull, reason: 'long $bad');
        expect(lookupRoyalEnfieldBlink(0, bad), isNull, reason: 'short $bad');
      }
      expect(lookupRoyalEnfieldBlink(-1, -1), isNull);
    });

    test('a count that would only match as a string ("06", "1,1") does not exist', () {
      // The API takes integers; there is no text parsing to fool.
      expect(lookupRoyalEnfieldBlink(0, 6)?.pattern, '0-6');
    });
  });

  group('B4 the screen', () {
    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] says what it is, which bikes, how, and what it does not know',
          (tester) async {
        await openReScreen(tester, lang: lang);
        final xs = textsOf(tester);
        for (final k in [
          'blinkRefManualBadge', // existing: "manual reference, not a live scan"
          'reBlinkAppliesTitle',
          'reBlinkApplies',
          'reBlinkIntro',
          'reBlinkHowTo',
          'reBlinkHowToBody',
          'reBlinkNotGiven',
          'reBlinkChoose',
        ]) {
          expect(xs, contains(t(k, lang)), reason: '$lang $k');
        }
        // The table's heading is shown in capitals, as on the Honda screen.
        expect(xs, contains(t('blinkRefFullTable', lang).toUpperCase()));
        // The provenance is the existing "manufacturer's service manual" label,
        // and the source line names the manual and the pages.
        expect(xs, contains(t('provenanceManual', lang)));
        expect(xs, contains(t('reBlinkSource', lang)));
        await tester.pump();
      });
    }

    test('the applicability statement names exactly the right bikes', () {
      final applies = AppStrings.get('reBlinkApplies', 'en');
      expect(applies, contains('Bullet Classic EFI'));
      expect(applies, contains('Bullet Electra EFI'));
      expect(applies, contains('UCE'));
      expect(applies, contains('does NOT apply'));
      expect(applies, contains('BS6 Classic 350'));
      expect(applies, contains('Meteor'));
      expect(applies, contains('Hunter'));
    });

    test('the procedure is the manual\'s, and the gaps are stated', () {
      final how = AppStrings.get('reBlinkHowToBody', 'en');
      expect(how, contains('single-pole test-pin connector'));
      expect(how, contains('engine control unit'));
      expect(how, contains('ground'));
      expect(how, contains('LONG'));
      expect(how, contains('SHORT'));
      final gaps = AppStrings.get('reBlinkNotGiven', 'en');
      expect(gaps, contains('how long'));
      expect(gaps, contains('clear'));
      expect(gaps, contains('Royal Enfield service centre'));
      expect(AppStrings.get('reBlinkSource', 'en'), contains('163'));
      expect(AppStrings.get('reBlinkSource', 'en'), contains('164'));
      expect(AppStrings.get('reBlinkSource', 'en'), contains('service manual'));
    });

    testWidgets('nothing is chosen at first: no pre-selected "match" the rider did not enter',
        (tester) async {
      await openReScreen(tester);
      final xs = textsOf(tester);
      expect(xs, contains(t('reBlinkChoose')));
      expect(xs, isNot(contains(t('reBlinkNoMatch'))));
      // The table is listed, but no result card (no "Dealer-tool code" label on a result).
      expect(find.byKey(const ValueKey('reBlinkResult')), findsNothing);
    });

    testWidgets('each row, entered as long then short counts, shows its code, meaning and effect',
        (tester) async {
      await openReScreen(tester);
      for (final m in manual) {
        await tester.tap(pick(RoyalEnfieldBlinkReferenceScreen.longRowKey, m.$1));
        await tester.pump();
        await tester.tap(pick(RoyalEnfieldBlinkReferenceScreen.shortRowKey, m.$2));
        await tester.pump();
        final result = find.byKey(const ValueKey('reBlinkResult'));
        expect(result, findsOneWidget, reason: '${m.$1}-${m.$2}');
        final inside = tester
            .widgetList<Text>(find.descendant(of: result, matching: find.byType(Text)))
            .map((w) => w.data ?? '')
            .toList();
        expect(inside, contains(m.$3), reason: '${m.$1}-${m.$2} code');
        expect(inside, contains(m.$4), reason: '${m.$1}-${m.$2} meaning');
        expect(inside, contains(t(m.$5.labelKey)), reason: '${m.$1}-${m.$2} effect');
        expect(inside, contains('${m.$1}-${m.$2}'), reason: 'pattern shown');
        expect(inside.contains(t('reBlinkMfrCode')), m.$3 == 'P1630',
            reason: '${m.$1}-${m.$2}: manufacturer-code label only on P1630');
      }
    });

    testWidgets('a pattern not in the table says so and sends the rider to a service centre',
        (tester) async {
      await openReScreen(tester);
      await tester.tap(pick(RoyalEnfieldBlinkReferenceScreen.longRowKey, 2));
      await tester.pump();
      await tester.tap(pick(RoyalEnfieldBlinkReferenceScreen.shortRowKey, 2));
      await tester.pump();
      final xs = textsOf(tester);
      expect(xs, contains(t('reBlinkNoMatch')));
      expect(xs, contains(t('reBlinkNoMatchDesc')));
      expect(find.byKey(const ValueKey('reBlinkResult')), findsNothing);
    });

    testWidgets('only one count chosen is not yet a pattern', (tester) async {
      await openReScreen(tester);
      await tester.tap(pick(RoyalEnfieldBlinkReferenceScreen.longRowKey, 3));
      await tester.pump();
      expect(textsOf(tester), contains(t('reBlinkChoose')));
      expect(textsOf(tester), isNot(contains(t('reBlinkNoMatch'))));
    });

    testWidgets('the pickers offer exactly 0 to 9 each (the input limit)', (tester) async {
      await openReScreen(tester);
      for (final row in [
        RoyalEnfieldBlinkReferenceScreen.longRowKey,
        RoyalEnfieldBlinkReferenceScreen.shortRowKey
      ]) {
        for (var n = 0; n <= 9; n++) {
          expect(pick(row, n), findsOneWidget, reason: '$row $n');
        }
        expect(pick(row, 10), findsNothing);
      }
    });

    testWidgets('tapping a row of the full table fills in the pattern', (tester) async {
      await openReScreen(tester);
      await tester.tap(find.byKey(const ValueKey('reBlinkRow-4-5')));
      await tester.pump();
      final result = find.byKey(const ValueKey('reBlinkResult'));
      expect(result, findsOneWidget);
      expect(
          find.descendant(of: result, matching: find.text('P0135')), findsOneWidget);
    });

    testWidgets('the full table lists every row with its code', (tester) async {
      await openReScreen(tester);
      for (final m in manual) {
        final row = find.byKey(ValueKey('reBlinkRow-${m.$1}-${m.$2}'));
        expect(row, findsOneWidget);
        expect(find.descendant(of: row, matching: find.text(m.$4)), findsOneWidget);
        expect(find.descendant(of: row, matching: find.text(m.$3)), findsOneWidget);
      }
    });

    testWidgets('there is no scan or read button anywhere on it', (tester) async {
      await openReScreen(tester);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(textsOf(tester).any((x) => x.toLowerCase().contains('scan now')), isFalse);
    });
  });

  group('B4 strings', () {
    test('every new key exists in English and Hindi, translated, same placeholders', () {
      final en = AppStrings.languageTable('en');
      final hi = AppStrings.languageTable('hi');
      final ph = RegExp(r'\{[a-z]+\}');
      for (final k in newKeys) {
        expect(en[k], isNotNull, reason: 'en $k');
        expect(hi[k], isNotNull, reason: 'hi $k');
        expect((hi[k] ?? '').trim(), isNotEmpty);
        expect(hi[k], isNot(en[k]), reason: '$k must be translated');
        expect(ph.allMatches(hi[k]!).map((m) => m[0]).toSet(),
            ph.allMatches(en[k]!).map((m) => m[0]).toSet(),
            reason: k);
        expect(RegExp(r'[०-९]').hasMatch(hi[k]!), isFalse, reason: '$k Latin digits');
      }
    });

    test('the Hindi keeps the names the style sheet keeps in Latin script', () {
      final hi = AppStrings.languageTable('hi');
      expect(hi['reBlinkApplies'], allOf(contains('Bullet Classic EFI'), contains('Bullet Electra EFI'), contains('BS6 Classic 350'), contains('Meteor'), contains('Hunter')));
      expect(hi['reBlinkHowToBody'], contains('ECU'));
      expect(hi['reBlinkNotGiven'], contains('Royal Enfield'));
    });

    test('other languages fall back to English for the new keys (no half-translations)', () {
      for (final lang in ['bn', 'te', 'mr', 'ta', 'gu', 'kn', 'ml', 'pa', 'ne']) {
        for (final k in newKeys) {
          expect(AppStrings.languageTable(lang).containsKey(k), isFalse, reason: '$lang $k');
        }
      }
    });
  });

  group('B4 the list of references', () {
    test('Royal Enfield profile: Royal Enfield first; otherwise Honda first (as before)', () {
      expect(blinkReferenceOrder('Royal Enfield'),
          [BlinkReference.royalEnfield, BlinkReference.honda]);
      expect(blinkReferenceOrder('  ROYAL-ENFIELD '),
          [BlinkReference.royalEnfield, BlinkReference.honda]);
      expect(blinkReferenceOrder('RE'),
          [BlinkReference.royalEnfield, BlinkReference.honda]);
      for (final make in [null, '', 'Honda', 'Bajaj', 'Unknown', 'Royal']) {
        expect(blinkReferenceOrder(make),
            [BlinkReference.honda, BlinkReference.royalEnfield],
            reason: '$make');
      }
    });

    Future<void> openList(WidgetTester tester, {String? make, String lang = 'en'}) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final settings = SettingsProvider();
      final vehicles = VehicleProvider();
      await tester.runAsync(() async {
        await settings.setLanguage(lang);
        if (make != null) {
          await vehicles.addVehicle(VehicleProfile(id: 'v', name: 'Bike', make: make));
        }
      });
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<VehicleProvider>.value(value: vehicles),
        ],
        child: const MaterialApp(home: BlinkReferencesScreen()),
      ));
      await tester.pump();
    }

    testWidgets('a Royal Enfield profile sees the Royal Enfield reference first', (tester) async {
      await openList(tester, make: 'Royal Enfield');
      final re = tester.getTopLeft(find.byKey(const ValueKey('blink-ref-royalEnfield'))).dy;
      final honda = tester.getTopLeft(find.byKey(const ValueKey('blink-ref-honda'))).dy;
      expect(re, lessThan(honda));
    });

    testWidgets('any other profile sees Honda first', (tester) async {
      await openList(tester, make: 'Honda');
      final re = tester.getTopLeft(find.byKey(const ValueKey('blink-ref-royalEnfield'))).dy;
      final honda = tester.getTopLeft(find.byKey(const ValueKey('blink-ref-honda'))).dy;
      expect(honda, lessThan(re));
    });

    testWidgets('no profile at all still lists both', (tester) async {
      await openList(tester);
      expect(find.byKey(const ValueKey('blink-ref-royalEnfield')), findsOneWidget);
      expect(find.byKey(const ValueKey('blink-ref-honda')), findsOneWidget);
    });

    testWidgets('each entry opens its own screen', (tester) async {
      await openList(tester, make: 'Honda');
      await tester.tap(find.byKey(const ValueKey('blink-ref-royalEnfield')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(RoyalEnfieldBlinkReferenceScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(RoyalEnfieldBlinkReferenceScreen))).pop();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('blink-ref-honda')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(HondaBlinkReferenceScreen), findsOneWidget);
    });

    testWidgets('[hi] the list is in Hindi', (tester) async {
      await openList(tester, make: 'Royal Enfield', lang: 'hi');
      final xs = textsOf(tester);
      expect(xs, contains(t('blinkRefsTitle', 'hi')));
      expect(xs, contains(t('blinkRefsRoyal', 'hi')));
      expect(xs, contains(t('blinkRefTitle', 'hi')));
    });
  });

  group('B4 reachable from the Fault Codes tab', () {
    for (final connected in [true, false]) {
      testWidgets('[${connected ? "connected" : "disconnected"}] "Blink-code references" opens the list',
          (tester) async {
        late ObdService obd;
        final settings = SettingsProvider();
        await tester.runAsync(() async {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          obd = ObdService(EngineSim(mode03: '43 00'),
              faultTiming: const FaultReadTiming.scaled(0.05));
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
        final chip = find.byKey(const ValueKey('tool-blink-refs'));
        expect(chip, findsOneWidget);
        expect(find.descendant(of: chip, matching: find.text(t('blinkRefsTitle'))), findsOneWidget);
        await tester.tap(chip);
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
        expect(find.byType(BlinkReferencesScreen), findsOneWidget);
        await tester.runAsync(() => obd.disconnect());
      });
    }
  });
}
