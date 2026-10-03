/// Phase 4D M3 — what the rider sees for the Yamaha R15 maker table: the fault
/// card, the code lookup (with its mechanic section) and the scan history. The
/// REAL screens, the REAL resolver, the REAL bundled content.
///
/// The two things that must never happen: the Yamaha text on a bike that is
/// not an R15 of 2022 or later, and a generic text passed off as Yamaha's.
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/knowledge/fault_resolver.dart';
import 'package:danlite_elm/knowledge/knowledge_service.dart';
import 'package:danlite_elm/knowledge/scan_history.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/code_lookup_screen.dart';
import 'package:danlite_elm/screens/scan_history_screen.dart';
import 'package:danlite_elm/widgets/resolved_fault_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'phase1b_screens_test.dart' as screens;
import 'support/engine_sim.dart';
import 'support/knowledge_harness.dart';

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

String mode03(String code) {
  final n = int.parse(code.substring(1), radix: 16);
  String h(int x) => x.toRadixString(16).toUpperCase().padLeft(2, '0');
  return '7E8 04 43 01 ${h((n >> 8) & 0xFF)} ${h(n & 0xFF)}';
}

String fill(String key, String lang, {String make = 'Yamaha', String? item}) =>
    t(key, lang)
        .replaceAll('{make}', make)
        .replaceAll('{item}', item ?? '');

const String p0107En = 'Intake air pressure sensor, open circuit or short to ground';
const String p0107Hi = 'इनटेक एयर प्रेशर सेंसर, ओपन सर्किट या ग्राउंड से शॉर्ट';
// What the bundled generic content says about P0107 (it must never be passed
// off as Yamaha's).
const String p0107Generic = 'Intake manifold pressure (MAP) sensor: voltage below threshold';

bool has(List<String> xs, String s) => xs.any((x) => x.contains(s));

/// Anything that only the maker table can put on screen.
List<String> makerMarkers(String lang) => [
      fill('makerFailSafeCanDrive', lang),
      fill('makerFailSafeNoDrive', lang),
      fill('makerFailSafeNoStart', lang),
      fill('makerFailSafeCanDrive', lang, make: 'यामाहा'),
      fill('makerFailSafeNoDrive', lang, make: 'यामाहा'),
      fill('makerFailSafeNoStart', lang, make: 'यामाहा'),
      t('makerYearNoteR15', lang),
      t('makerSourceR15', lang),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M3 the fault card for a Yamaha R15 (2022)', () {
    testWidgets('[en] P0107: the maker meaning, one fail-safe line, Service soon, "with care"',
        (tester) async {
      final env = await screens.setUp(tester,
          make: 'Yamaha', model: 'R15', year: 2022, sim: EngineSim(mode03: mode03('P0107')));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains(p0107En));
      expect(xs, contains(fill('makerFailSafeCanDrive', 'en')));
      expect(xs, contains('Yamaha says the bike can still be driven'));
      expect(xs, contains(t('riderActionServiceSoon')));
      expect(find.byType(RiderActionChip), findsOneWidget);
      expect(find.byType(NameOnlyChip), findsNothing);
      expect(xs.any((x) => x.contains(t('canRideWithCare'))), isTrue);
      expect(xs, contains(t('provenanceManual')));
      expect(xs, contains(fill('makerJudgementNote', 'en')),
          reason: 'the ride answer is the app\'s reading, and the card says so');
      // Not the generic text, and no mechanic-only item on the card.
      expect(has(xs, p0107Generic), isFalse);
      expect(has(xs, 'dealer-tool item'), isFalse);
      expect(has(xs, t('makerSourceR15')), isFalse);
      expect(has(xs, t('makerYearNoteR15')), isFalse, reason: 'the year is known');
      expect(has(xs, t('provenanceDraft')), isFalse, reason: 'a row read from the page is no draft');
      await env.close(tester);
    });

    testWidgets('[en] P0335: engine will not start, Stop, cannot ride', (tester) async {
      final env = await screens.setUp(tester,
          make: 'Yamaha', model: 'R15', year: 2022, sim: EngineSim(mode03: mode03('P0335')));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains('Crankshaft position sensor, no normal signal'));
      expect(xs, contains('Yamaha says the engine will not start and the bike cannot be driven'));
      expect(xs, contains(t('riderActionStop')));
      expect(xs.any((x) => x.contains(t('canRideNo'))), isTrue);
      expect(has(xs, 'says the bike can still be driven'), isFalse);
      await env.close(tester);
    });

    testWidgets('[en] P0201: engine starts but the bike cannot be driven', (tester) async {
      final env = await screens.setUp(tester,
          make: 'Yamaha', model: 'R15M', year: 2023, sim: EngineSim(mode03: mode03('P0201')));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains('Fuel injector fault'));
      expect(xs, contains('Yamaha says the bike cannot be driven'));
      expect(has(xs, 'will not start'), isFalse);
      expect(xs, contains(t('riderActionStop')));
      await env.close(tester);
    });

    testWidgets('[en] an unverified row (P2195) shows the Draft line on the card, not the check note',
        (tester) async {
      final env = await screens.setUp(tester,
          make: 'Yamaha', model: 'R15', year: 2022, sim: EngineSim(mode03: mode03('P2195')));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains('O2 sensor, open circuit'));
      expect(xs, contains('${t('provenanceManual')}. ${t('provenanceDraft')}'));
      expect(has(xs, 'to be checked against the manual page'), isFalse,
          reason: 'that note is for the mechanic section');
      await env.close(tester);
    });

    testWidgets('[hi] Hindi meaning, Hindi lines, and the machine-translated line', (tester) async {
      final env = await screens.setUp(tester,
          lang: 'hi',
          make: 'Yamaha',
          model: 'R15',
          year: 2022,
          sim: EngineSim(mode03: mode03('P0107')));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains(p0107Hi));
      expect(xs, contains(fill('makerFailSafeCanDrive', 'hi', make: 'यामाहा')));
      expect(xs, contains(t('riderActionServiceSoon', 'hi')));
      expect(xs, contains(t('faultHindiMachine', 'hi')));
      expect(xs, contains(t('provenanceManual', 'hi')));
      expect(has(xs, p0107En), isFalse);
      expect(has(xs, 'says the bike'), isFalse);
      await env.close(tester);
    });

    testWidgets('[bn] falls back to English with the existing note', (tester) async {
      final env = await screens.setUp(tester,
          lang: 'bn',
          make: 'Yamaha',
          model: 'R15',
          year: 2022,
          sim: EngineSim(mode03: mode03('P0107')));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains(p0107En));
      expect(xs, contains(t('faultShowingEnglish', 'bn')));
      await env.close(tester);
    });

    testWidgets('a name-only code the table does not list still gets the neutral chip',
        (tester) async {
      final env = await screens.setUp(tester,
          make: 'Yamaha', model: 'R15', year: 2022, sim: EngineSim(mode03: mode03('P0001')));
      final xs = await screens.showDtc(tester, env);
      expect(find.byType(NameOnlyChip), findsOneWidget);
      for (final m in makerMarkers('en')) {
        expect(has(xs, m), isFalse);
      }
      await env.close(tester);
    });
  });

  group('M3 the same code on any other bike never shows the Yamaha text', () {
    for (final (make, model, year) in [
      ('Honda', 'R15', 2022),
      ('Honda', 'CB350', 2023),
      ('Royal Enfield', 'Classic 350', 2022),
      ('Yamaha', 'FZ-S', 2022),
      ('Yamaha', 'MT-15', 2023),
      ('Yamaha', 'R15 V3', 2022),
      ('Yamaha', 'R15', 2021),
      ('Yamaha', 'R15', 2020),
      ('Yamaha', '', 2022),
      ('Foo', 'R15', 2022),
    ]) {
      for (final lang in ['en', 'hi']) {
        testWidgets('[$lang] $make "$model" $year', (tester) async {
          final env = await screens.setUp(tester,
              lang: lang,
              make: make,
              model: model,
              year: year,
              sim: EngineSim(mode03: mode03('P0107')));
          final xs = await screens.showDtc(tester, env);
          expect(has(xs, p0107En), isFalse);
          expect(has(xs, p0107Hi), isFalse);
          for (final m in makerMarkers(lang)) {
            expect(has(xs, m), isFalse, reason: m);
          }
          expect(has(xs, t('makerJudgementNote', lang).split('{make}').first), isFalse);
          // The ordinary generic answer is what is on screen, labelled as such.
          expect(xs, contains('${t('provenanceAi', lang)}. ${t('provenanceDraft', lang)}'));
          expect(xs, isNot(contains(t('provenanceManual', lang))));
          await env.close(tester);
        });
      }
    }

    testWidgets('no vehicle profile at all', (tester) async {
      final env = await screens.setUp(tester, sim: EngineSim(mode03: mode03('P0107')));
      final xs = await screens.showDtc(tester, env);
      expect(has(xs, p0107En), isFalse);
      expect(xs, isNot(contains(t('provenanceManual'))));
      await env.close(tester);
    });
  });

  group('M3 the guidance widget with a missing model year', () {
    testWidgets('shows the check-your-model-year note, English and Hindi', (tester) async {
      for (final lang in ['en', 'hi']) {
        final env = await screens.setUp(tester, lang: lang, knowledge: false);
        final r = FaultResolver(index: KnowledgeIndex.empty).resolve(
            FaultRecord.fromObdCode('P0107',
                source: ReadSource.mode03, readAt: DateTime.utc(2026, 10, 4)),
            VehicleContext.fromProfile(make: 'Yamaha', model: 'R15', year: null),
            lang,
            domain: FaultDomain.engine);
        expect(r.maker!.yearUnknown, isTrue);
        await tester.pumpWidget(env.wrap(Scaffold(body: SingleChildScrollView(child: ResolvedGuidance(r)))));
        await tester.pump();
        expect(has(screens.texts(tester), t('makerYearNoteR15', lang)), isTrue, reason: lang);
      }
    });

    testWidgets('a known year shows no such note', (tester) async {
      final env = await screens.setUp(tester, knowledge: false);
      final r = FaultResolver(index: KnowledgeIndex.empty).resolve(
          FaultRecord.fromObdCode('P0107',
              source: ReadSource.mode03, readAt: DateTime.utc(2026, 10, 4)),
          VehicleContext.fromProfile(make: 'Yamaha', model: 'R15', year: 2022),
          'en',
          domain: FaultDomain.engine);
      await tester.pumpWidget(env.wrap(Scaffold(body: SingleChildScrollView(child: ResolvedGuidance(r)))));
      await tester.pump();
      expect(has(screens.texts(tester), t('makerYearNoteR15')), isFalse);
    });
  });

  group('M3 the lookup detail and its mechanic section', () {
    Future<List<String>> detail(WidgetTester tester, screens.Env env, String code) async {
      await tester.pumpWidget(env.wrap(CodeLookupDetailScreen(code: code, format: DtcFormat.sae2)));
      await tester.pump(const Duration(milliseconds: 50));
      return screens.texts(tester);
    }

    testWidgets('[en] P0107 for an R15 (2022): the maker meaning and the mechanic rows', (tester) async {
      final env = await screens.setUp(tester, make: 'Yamaha', model: 'R15', year: 2022);
      final xs = await detail(tester, env, 'P0107');
      expect(xs, contains(p0107En));
      expect(xs, contains('Yamaha says the bike can still be driven'));
      expect(xs, contains(t('faultForMechanic').toUpperCase()));
      expect(xs.any((x) => x.contains('Yamaha dealer-tool item: 03')), isTrue);
      expect(xs.any((x) => x.contains(t('makerSourceR15'))), isTrue);
      expect(has(xs, p0107Generic), isFalse);
      await env.close(tester);
    });

    testWidgets('[en] a row with no dealer item has no empty line, just the source', (tester) async {
      final env = await screens.setUp(tester, make: 'Yamaha', model: 'R15', year: 2022);
      final xs = await detail(tester, env, 'P0560');
      expect(xs, contains('Battery charging voltage abnormal, discharged'));
      expect(has(xs, 'dealer-tool item'), isFalse);
      expect(has(xs, t('makerSourceR15')), isTrue);
      expect(xs.where((x) => x.trim().isEmpty), isEmpty);
      await env.close(tester);
    });

    testWidgets('[en] reconstructed and inferred rows say they are to be checked', (tester) async {
      final env = await screens.setUp(tester, make: 'Yamaha', model: 'R15', year: 2022);
      var xs = await detail(tester, env, 'P00D1');
      expect(has(xs, t('makerCheckReconstructed')), isTrue);
      expect(has(xs, t('provenanceDraft')), isTrue);
      xs = await detail(tester, env, 'P2195');
      expect(has(xs, t('makerCheckReconstructed')), isTrue);
      xs = await detail(tester, env, 'P0132');
      expect(has(xs, t('makerCheckInferred')), isTrue);
      expect(has(xs, t('provenanceDraft')), isTrue);
      xs = await detail(tester, env, 'P0030');
      expect(has(xs, 'to be checked against the manual page'), isFalse);
      await env.close(tester);
    });

    testWidgets('[hi] Hindi detail', (tester) async {
      final env = await screens.setUp(tester, lang: 'hi', make: 'Yamaha', model: 'R15', year: 2022);
      final xs = await detail(tester, env, 'P0107');
      expect(xs, contains(p0107Hi));
      expect(xs.any((x) => x.contains(fill('makerDealerItem', 'hi', make: 'यामाहा', item: '03'))),
          isTrue);
      expect(has(xs, t('makerSourceR15', 'hi')), isTrue);
      expect(xs, contains(t('faultHindiMachine', 'hi')));
      await env.close(tester);
    });

    testWidgets('a Honda, a non-R15 Yamaha, an R15 of 2021 and no profile: the generic answer only',
        (tester) async {
      for (final (make, model, year) in [
        ('Honda', 'R15', 2022),
        ('Yamaha', 'FZ-S', 2022),
        ('Yamaha', 'R15', 2021),
        (null, null, null),
      ]) {
        final env = await screens.setUp(tester, make: make, model: model, year: year);
        final xs = await detail(tester, env, 'P0107');
        expect(has(xs, p0107En), isFalse, reason: '$make $model $year');
        expect(has(xs, 'dealer-tool item'), isFalse);
        expect(has(xs, t('makerSourceR15')), isFalse);
        expect(xs, isNot(contains(t('provenanceManual'))));
        // (A Yamaha profile's lookup of an engine code resolves as "raw" today,
        // because the lookup does not know the module; that is the older
        // behaviour and is listed in the 4D report, not changed here.)
        if (make != 'Yamaha') {
          expect(has(xs, p0107Generic), isTrue, reason: 'the generic answer is there for $make $model $year');
        }
        await env.close(tester);
      }
    });
  });

  group('M3 the scan history never explains another bike\'s scan with this bike\'s table', () {
    ScanSessionInput saved(String? profileId) => ScanSessionInput(
          kind: SessionKind.engine,
          startedAt: DateTime.utc(2026, 10, 4, 9),
          reachState: 'answered',
          profileId: profileId,
          coalesce: false,
          faults: [
            ScanFaultInput(FaultRecord.fromObdCode('P0107',
                source: ReadSource.mode03, readAt: DateTime.utc(2026, 10, 4, 9))),
          ],
        );

    Future<(List<String>, String?)> open(WidgetTester tester, String? sessionProfile) async {
      String? shared;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('com.danlite.elm/session_recorder'), (call) async {
        if (call.method == 'shareText') shared = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.danlite.elm/session_recorder'), null));
      late Widget app;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final settings = SettingsProvider();
        final vehicles = VehicleProvider();
        await vehicles.addVehicle(VehicleProfile(
            id: 'v1', name: '', make: 'Yamaha', model: 'R15', year: 2022));
        final k = await startedKnowledge();
        await k.history!.save(saved(sessionProfile));
        addTearDown(() async => tester.runAsync(() async => k.store!.close()));
        app = MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<VehicleProvider>.value(value: vehicles),
            ChangeNotifierProvider<KnowledgeService?>.value(value: k),
          ],
          child: const MaterialApp(home: ScanHistoryScreen()),
        );
      });
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(app);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      // Share (built from the same resolution as the rows).
      await tester.tap(find.byTooltip(t('historyShare')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(InkWell).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return (screens.texts(tester), shared);
    }

    testWidgets('a scan saved on this R15 profile: the maker meaning, in the detail and the share',
        (tester) async {
      final (xs, shared) = await open(tester, 'v1');
      expect(xs, contains(p0107En));
      expect(shared, contains(p0107En));
    });

    testWidgets('a scan saved on another profile: the generic meaning only', (tester) async {
      final (xs, shared) = await open(tester, 'someone-elses-bike');
      expect(has(xs, p0107En), isFalse);
      expect(has(xs, p0107Generic), isTrue);
      expect(shared, isNotNull);
      expect(shared!.contains(p0107En), isFalse);
      expect(shared.contains(p0107Generic), isTrue);
    });

    testWidgets('a scan saved with no profile: the generic meaning only', (tester) async {
      final (xs, shared) = await open(tester, null);
      expect(has(xs, p0107En), isFalse);
      expect(shared!.contains(p0107En), isFalse);
    });
  });
}
