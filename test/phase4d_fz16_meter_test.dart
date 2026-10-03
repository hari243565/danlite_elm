/// Phase 4D M4 — Yamaha FZ-16 FI meter codes (older generation): a small manual
/// reference under "Blink-code references". Source: Yamaha FZ-16 service
/// manual, page 7-24. Two verified rows only (15 and 16); everything else is
/// said plainly to be unlisted because it has not been verified.
library;

import 'dart:io';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/constants/yamaha_fz16_meter.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/blink_references_screen.dart';
import 'package:danlite_elm/screens/yamaha_fz16_meter_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

const String others =
    'Other codes exist on this bike; they are not listed here because they have not been verified. Ask a Yamaha service centre.';

const List<String> keys = [
  'blinkRefsYamaha',
  'blinkRefsYamahaSub',
  'fz16Title',
  'fz16Intro',
  'fz16Applies',
  'fz16Field',
  'fz16Choose',
  'fz16NoMatch',
  'fz16Others',
  'fz16Code15',
  'fz16Code16',
  'fz16Source',
];

Future<void> open(WidgetTester tester, Widget home,
    {String lang = 'en', String? make}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final settings = SettingsProvider();
  final vehicles = VehicleProvider();
  await tester.runAsync(() async {
    await settings.setLanguage(lang);
    if (make != null) {
      await vehicles.addVehicle(VehicleProfile(id: 'v1', name: '', make: make, model: 'x'));
    }
  });
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<VehicleProvider>.value(value: vehicles),
    ],
    child: MaterialApp(home: home),
  ));
  await tester.pump();
}

List<String> texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .toList();

bool has(WidgetTester tester, String s) => texts(tester).any((x) => x.contains(s));

Future<void> type(WidgetTester tester, String s) async {
  await tester.enterText(find.byKey(YamahaFz16MeterScreen.inputKey), s);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M4 the data', () {
    test('exactly the two verified rows: 15 and 16', () {
      expect([for (final e in kFz16MeterTable) e.code], [15, 16]);
    });

    test('15 = throttle position sensor, open or short circuit detected', () {
      expect(lookupFz16Meter(15)!.meaningKey, 'fz16Code15');
      expect(t('fz16Code15'), 'Throttle position sensor: open or short circuit detected');
    });

    test('16 = throttle position sensor, stuck', () {
      expect(lookupFz16Meter(16)!.meaningKey, 'fz16Code16');
      expect(t('fz16Code16'), 'Throttle position sensor: stuck');
    });

    test('every other number is not in the table', () {
      for (var n = -3; n <= 120; n++) {
        if (n == 15 || n == 16) continue;
        expect(lookupFz16Meter(n), isNull, reason: '$n');
      }
    });

    test('what the rider typed: only one or two plain digits count as a number', () {
      expect(parseFz16Code('15'), 15);
      expect(parseFz16Code(' 16 '), 16);
      expect(parseFz16Code('5'), 5);
      expect(parseFz16Code('05'), 5);
      for (final bad in ['', ' ', 'a', '1a', '1.5', '-5', '015', '150', '１５', '१५', '15 16']) {
        expect(parseFz16Code(bad), isNull, reason: '"$bad"');
      }
    });
  });

  group('M4 the words', () {
    test('the required sentences, word for word', () {
      expect(t('fz16Others'), others);
      expect(t('fz16Source'), 'Source: Yamaha FZ-16 service manual, page 7-24');
      expect(t('fz16Applies'), contains('older FZ-16 FI'));
      expect(t('fz16Applies'), contains('newer FZ-S FI'));
      expect(t('fz16Applies').toLowerCase(), contains('not been confirmed'));
      expect(t('fz16Intro'), contains('3 seconds'));
      expect(t('fz16Intro'), contains('key'));
      expect(t('fz16Intro'), contains('meter'));
    });

    test('every key is in English and Hindi, in source, and differs by language', () {
      final src = File('lib/constants/app_strings.dart').readAsStringSync();
      for (final k in keys) {
        expect(RegExp("'$k':").allMatches(src).length, 2, reason: k);
        expect(t(k, 'en'), isNot(k));
        expect(t(k, 'hi'), isNot(k));
        expect(t(k, 'hi'), isNot(t(k, 'en')), reason: k);
        expect(t(k, 'hi').contains(RegExp(r'[०-९]')), isFalse, reason: 'Latin digits: $k');
        expect(t(k, 'hi').contains('एडाप्टर'), isFalse);
      }
    });

    test('the Hindi keeps the same facts: 3, 7-24, FZ-16, FZ-S', () {
      expect(t('fz16Intro', 'hi'), contains('3'));
      expect(t('fz16Source', 'hi'), contains('7-24'));
      expect(t('fz16Source', 'hi'), contains('FZ-16'));
      expect(t('fz16Applies', 'hi'), contains('FZ-16'));
      expect(t('fz16Applies', 'hi'), contains('FZ-S'));
    });
  });

  group('M4 the screen', () {
    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] says it is a manual look-up, who it is for, and what is not listed',
          (tester) async {
        await open(tester, const YamahaFz16MeterScreen(), lang: lang);
        expect(has(tester, t('blinkRefManualBadge', lang)), isTrue);
        expect(has(tester, t('fz16Intro', lang)), isTrue);
        expect(has(tester, t('fz16Applies', lang)), isTrue);
        expect(has(tester, t('fz16Others', lang)), isTrue,
            reason: 'always on screen, not only after a failed look-up');
        expect(has(tester, t('fz16Source', lang)), isTrue);
        expect(has(tester, t('provenanceManual', lang)), isTrue);
        expect(has(tester, t('fz16Choose', lang)), isTrue);
        // Nothing is pre-selected, and nothing is scanned.
        expect(has(tester, t('fz16Code15', lang)), isTrue, reason: 'listed in the table below');
        expect(find.byKey(const ValueKey('fz16Result')), findsNothing);
        expect(find.byType(ElevatedButton), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
      });

      testWidgets('[$lang] 15 and 16 give their meaning', (tester) async {
        await open(tester, const YamahaFz16MeterScreen(), lang: lang);
        await type(tester, '15');
        expect(find.byKey(const ValueKey('fz16Result')), findsOneWidget);
        expect(find.descendant(
                of: find.byKey(const ValueKey('fz16Result')),
                matching: find.text(t('fz16Code15', lang))),
            findsOneWidget);
        expect(find.descendant(
                of: find.byKey(const ValueKey('fz16Result')),
                matching: find.text(t('fz16Code16', lang))),
            findsNothing);
        await type(tester, '16');
        expect(find.descendant(
                of: find.byKey(const ValueKey('fz16Result')),
                matching: find.text(t('fz16Code16', lang))),
            findsOneWidget);
      });

      testWidgets('[$lang] a number not in the table: plainly "not listed", ask a Yamaha centre',
          (tester) async {
        await open(tester, const YamahaFz16MeterScreen(), lang: lang);
        for (final n in ['17', '1', '0', '99', '14']) {
          await type(tester, n);
          expect(find.byKey(const ValueKey('fz16Result')), findsNothing, reason: n);
          expect(find.byKey(const ValueKey('fz16NoMatch')), findsOneWidget, reason: n);
          expect(has(tester, t('fz16NoMatch', lang)), isTrue);
          expect(has(tester, t('fz16Others', lang)), isTrue);
        }
      });
    }

    testWidgets('empty or non-numeric input shows neither a match nor a no-match', (tester) async {
      await open(tester, const YamahaFz16MeterScreen());
      for (final s in ['', 'abc', '  ']) {
        await type(tester, s);
        expect(find.byKey(const ValueKey('fz16Result')), findsNothing, reason: '"$s"');
        expect(find.byKey(const ValueKey('fz16NoMatch')), findsNothing, reason: '"$s"');
      }
    });

    testWidgets('the table lists the two verified rows and no others', (tester) async {
      await open(tester, const YamahaFz16MeterScreen());
      expect(find.byKey(const ValueKey('fz16Row-15')), findsOneWidget);
      expect(find.byKey(const ValueKey('fz16Row-16')), findsOneWidget);
      expect(find.byWidgetPredicate(
              (w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('fz16Row-')),
          findsNWidgets(2));
    });

    testWidgets('tapping a table row fills the input and shows that row', (tester) async {
      await open(tester, const YamahaFz16MeterScreen());
      await tester.tap(find.byKey(const ValueKey('fz16Row-16')));
      await tester.pump();
      expect(find.byKey(const ValueKey('fz16Result')), findsOneWidget);
    });

    testWidgets('no claim about the newer FZ-S beyond "not confirmed"', (tester) async {
      await open(tester, const YamahaFz16MeterScreen());
      final fzs = texts(tester).where((x) => x.contains('FZ-S')).toList();
      expect(fzs, [t('fz16Applies')]);
    });
  });

  group('M4 the references list', () {
    test('the older two-item order is unchanged', () {
      expect(blinkReferenceOrder('Royal Enfield'),
          [BlinkReference.royalEnfield, BlinkReference.honda]);
      expect(blinkReferenceOrder('Yamaha'),
          [BlinkReference.honda, BlinkReference.royalEnfield]);
    });

    test('Yamaha profile: the FZ-16 reference first; everyone else: last', () {
      expect(blinkReferenceTiles('Yamaha').first, BlinkReference.yamahaFz16);
      expect(blinkReferenceTiles(' YAMAHA ').first, BlinkReference.yamahaFz16);
      for (final m in [null, '', 'Honda', 'Royal Enfield', 'Bajaj']) {
        expect(blinkReferenceTiles(m).last, BlinkReference.yamahaFz16, reason: '$m');
        expect(blinkReferenceTiles(m), hasLength(3));
      }
      expect(blinkReferenceTiles('Royal Enfield').first, BlinkReference.royalEnfield);
    });

    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] the tile is there, in the list, and opens the screen', (tester) async {
        await open(tester, const BlinkReferencesScreen(), lang: lang, make: 'Yamaha');
        expect(find.byKey(const ValueKey('blink-ref-yamahaFz16')), findsOneWidget);
        expect(has(tester, t('blinkRefsYamaha', lang)), isTrue);
        expect(has(tester, t('blinkRefsYamahaSub', lang)), isTrue);
        final yamaha = tester.getTopLeft(find.byKey(const ValueKey('blink-ref-yamahaFz16'))).dy;
        final honda = tester.getTopLeft(find.byKey(const ValueKey('blink-ref-honda'))).dy;
        expect(yamaha, lessThan(honda), reason: 'a Yamaha profile sees its own reference first');
        await tester.tap(find.byKey(const ValueKey('blink-ref-yamahaFz16')));
        await tester.pumpAndSettle();
        expect(find.byType(YamahaFz16MeterScreen), findsOneWidget);
        expect(has(tester, t('fz16Title', lang)), isTrue);
      });
    }

    testWidgets('a Honda profile sees Honda first, Royal Enfield second, Yamaha last', (tester) async {
      await open(tester, const BlinkReferencesScreen(), make: 'Honda');
      double y(String k) => tester.getTopLeft(find.byKey(ValueKey('blink-ref-$k'))).dy;
      expect(y('honda'), lessThan(y('royalEnfield')));
      expect(y('royalEnfield'), lessThan(y('yamahaFz16')));
    });
  });
}
