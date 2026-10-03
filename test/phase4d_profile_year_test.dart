/// Phase 4D M6 — the vehicle profile's model year can be unknown.
///
/// The year used to be a whole number that defaulted to 2020 (code and saved
/// profiles) or to the current year (the form), so nothing could say "not
/// known". Now it is nullable; the form defaults to "Not set" with an explicit
/// "Year unknown"; a one-time migration sets every EXISTING profile's year to
/// unknown (it only ever held an arbitrary default); nothing asks the rider
/// anything. A missing year keeps the R15 behaviour: the table, with the note.
library;

import 'dart:convert';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/knowledge/fault_resolver.dart';
import 'package:danlite_elm/knowledge/history_recorder.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/vehicle_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'phase1b_screens_test.dart' as screens;
import 'support/engine_sim.dart';

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

const String kMigrationKey = 'vehicleYearUnknownMigrationV1';

String saved(String id, {Object? year = _absent, String make = 'Yamaha', String model = 'R15'}) =>
    jsonEncode(<String, Object?>{
      'id': id, 'name': 'Bike $id', 'make': make, 'model': model,
      if (year != _absent) 'year': year,
      'fuel': 'petrol', 'engL': 1.6, 'bhp': 120, 'wt': 1400,
      'vin': '', 'notes': '', 'ca': '2026-01-01T00:00:00.000',
    });

const Object _absent = Object();

Future<List<Map<String, dynamic>>> storedProfiles() async {
  final prefs = await SharedPreferences.getInstance();
  return [
    for (final s in prefs.getStringList('vehicles') ?? const <String>[])
      jsonDecode(s) as Map<String, dynamic>
  ];
}

FaultRecord obd(String code) => FaultRecord.fromObdCode(code,
    source: ReadSource.mode03, readAt: DateTime.utc(2026, 10, 4));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M6 the profile model', () {
    test('a new profile has no year', () {
      expect(VehicleProfile(id: 'a', name: 'A').year, isNull);
    });

    test('an unknown year is saved as null, not as a default', () {
      final j = VehicleProfile(id: 'a', name: 'A').toJson();
      expect(j.containsKey('year'), isTrue);
      expect(j['year'], isNull);
    });

    test('reading: missing, null and a real year', () {
      Map<String, dynamic> j(Object? y, {bool has = true}) => {
            'id': 'a', 'name': 'A', 'make': '', 'model': '',
            if (has) 'year': y,
          };
      expect(VehicleProfile.fromJson(j(null, has: false)).year, isNull);
      expect(VehicleProfile.fromJson(j(null)).year, isNull);
      expect(VehicleProfile.fromJson(j(2022)).year, 2022);
    });

    test('a bad saved year (text, zero, negative) reads as unknown, never crashes', () {
      for (final y in <Object>['2022', 'x', 0, -4, 1.5]) {
        final p = VehicleProfile.fromJson({'id': 'a', 'name': 'A', 'year': y});
        expect(p.year, isNull, reason: '$y');
      }
    });

    test('the display name never says "null" and never shows a made-up year', () {
      final p = VehicleProfile(id: 'a', name: '', make: 'Yamaha', model: 'R15');
      expect(p.displayName, 'Yamaha R15');
      expect(p.displayName.contains('null'), isFalse);
      expect(VehicleProfile(id: 'a', name: '', make: 'Yamaha', model: 'R15', year: 2022).displayName,
          '2022 Yamaha R15');
      expect(VehicleProfile(id: 'a', name: '').displayName.contains('null'), isFalse);
      expect(VehicleProfile(id: 'a', name: 'Mine').displayName, 'Mine');
    });

    test('copyWith keeps the year, sets it, and can clear it', () {
      final p = VehicleProfile(id: 'a', name: 'A', year: 2023);
      expect(p.copyWith(name: 'B').year, 2023);
      expect(p.copyWith(year: 2024).year, 2024);
      expect(p.copyWith(clearYear: true).year, isNull);
      expect(VehicleProfile(id: 'a', name: 'A').copyWith(name: 'B').year, isNull);
    });
  });

  group('M6 the one-time migration', () {
    test('every existing profile (any saved year, or none) becomes unknown, and it is saved',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'vehicles': <String>[
          saved('a', year: 2020),
          saved('b', year: 2022),
          saved('c', year: 2025),
          saved('d'), // an older save with no year key
        ],
        'activeVehicle': 'b',
      });
      final p = VehicleProvider();
      await p.init();
      expect(p.vehicles.map((v) => v.year), [null, null, null, null]);
      expect(p.active!.id, 'b', reason: 'the active profile is kept');
      expect([for (final j in await storedProfiles()) j['year']], [null, null, null, null],
          reason: 'written back to storage');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kMigrationKey), isTrue);
      // Nothing else about the profiles changed.
      expect(p.vehicles.map((v) => v.make).toSet(), {'Yamaha'});
      expect(p.vehicles.map((v) => v.name), ['Bike a', 'Bike b', 'Bike c', 'Bike d']);
    });

    test('it runs once: a year the rider sets afterwards survives the next start', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'vehicles': <String>[saved('a', year: 2020)],
      });
      final first = VehicleProvider();
      await first.init();
      expect(first.vehicles.single.year, isNull);
      await first.updateVehicle(first.vehicles.single.copyWith(year: 2023));
      final second = VehicleProvider();
      await second.init();
      expect(second.vehicles.single.year, 2023);
      final third = VehicleProvider();
      await third.init();
      expect(third.vehicles.single.year, 2023);
    });

    test('a fresh install: the default profile has no year, and profiles added later keep theirs',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final p = VehicleProvider();
      await p.init();
      expect(p.vehicles.single.year, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kMigrationKey), isTrue,
          reason: 'a new install has nothing to migrate and must not wipe what it saves next');
      await p.addVehicle(VehicleProfile(id: 'n', name: 'New', make: 'Yamaha', model: 'R15', year: 2024));
      final again = VehicleProvider();
      await again.init();
      expect(again.vehicles.firstWhere((v) => v.id == 'n').year, 2024);
    });

    test('profiles saved by this version, with the flag already set, are never wiped', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kMigrationKey: true,
        'vehicles': <String>[saved('a', year: 2022), saved('b', year: null)],
      });
      final p = VehicleProvider();
      await p.init();
      expect(p.vehicles.map((v) => v.year), [2022, null]);
    });

    test('a profile with a bad stored year does not stop the others loading', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'vehicles': <String>[saved('a', year: 'oops'), saved('b', year: 2022)],
      });
      final p = VehicleProvider();
      await p.init();
      expect(p.vehicles, hasLength(2));
      expect(p.vehicles.map((v) => v.year), [null, null]);
    });

    test('init never asks anything: it finishes with no UI and notifies once it is done', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'vehicles': <String>[saved('a', year: 2020)],
      });
      final p = VehicleProvider();
      var calls = 0;
      p.addListener(() => calls++);
      await p.init();
      expect(calls, greaterThanOrEqualTo(1));
    });
  });

  group('M6 the form', () {
    Future<VehicleProvider> open(WidgetTester tester, {List<VehicleProfile> existing = const []}) async {
      SharedPreferences.setMockInitialValues(<String, Object>{kMigrationKey: true});
      final p = VehicleProvider();
      await tester.runAsync(() async {
        for (final v in existing) {
          await p.addVehicle(v);
        }
      });
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<VehicleProvider>.value(value: p),
          ChangeNotifierProvider<SettingsProvider>(create: (_) => SettingsProvider()),
        ],
        child: const MaterialApp(home: VehicleProfileScreen()),
      ));
      await tester.pump();
      return p;
    }

    Future<void> pickYear(WidgetTester tester, String label) async {
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    Future<void> saveWithName(WidgetTester tester, String name) async {
      await tester.enterText(find.byType(TextFormField).first, name);
      await tester.tap(find.text('Add Vehicle').last);
      await tester.pumpAndSettle();
    }

    testWidgets('a new profile starts at "Not set", not the current year', (tester) async {
      await open(tester);
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      expect(find.text('Not set'), findsOneWidget);
      expect(find.text('${DateTime.now().year}'), findsNothing,
          reason: 'the current year is not pre-selected');
    });

    testWidgets('saving without touching the year saves it as unknown', (tester) async {
      final p = await open(tester);
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await saveWithName(tester, 'Mine');
      expect(p.vehicles.single.year, isNull);
    });

    testWidgets('the explicit "Year unknown" choice saves as unknown and shows as chosen',
        (tester) async {
      final p = await open(tester);
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await pickYear(tester, 'Year unknown');
      expect(find.text('Year unknown'), findsOneWidget);
      expect(find.text('Not set'), findsNothing);
      await saveWithName(tester, 'Mine');
      expect(p.vehicles.single.year, isNull);
    });

    testWidgets('a real year is saved as that year', (tester) async {
      final p = await open(tester);
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await pickYear(tester, '2022');
      await saveWithName(tester, 'Mine');
      expect(p.vehicles.single.year, 2022);
    });

    testWidgets('editing: a known year is shown; an unknown one is "Not set" and stays unknown',
        (tester) async {
      final p = await open(tester, existing: [
        VehicleProfile(id: 'a', name: 'Known', year: 2023),
        VehicleProfile(id: 'b', name: 'Unknown'),
      ]);
      // Edit the known one.
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      expect(find.text('2023'), findsWidgets);
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(p.vehicles.firstWhere((v) => v.id == 'a').year, 2023);
      // Edit the unknown one and save: still unknown, not the current year.
      await tester.tap(find.byIcon(Icons.edit_outlined).last);
      await tester.pumpAndSettle();
      expect(find.text('Not set'), findsOneWidget);
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(p.vehicles.firstWhere((v) => v.id == 'b').year, isNull);
    });

    testWidgets('a saved year far outside the list still opens the form (no crash)', (tester) async {
      final p = await open(tester, existing: [VehicleProfile(id: 'a', name: 'Old', year: 1975)]);
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(p.vehicles.single.year, 1975);
    });

    testWidgets('the profile card never says "null" and says "Year unknown"', (tester) async {
      await open(tester, existing: [
        VehicleProfile(id: 'a', name: 'Known', year: 2023),
        VehicleProfile(id: 'b', name: 'Unknown'),
      ]);
      final xs = screens.texts(tester);
      expect(xs.any((x) => x.contains('null')), isFalse);
      expect(xs.any((x) => x.startsWith('2023 ·')), isTrue);
      expect(xs.any((x) => x.startsWith('Year unknown ·')), isTrue);
    });
  });

  group('M6 the R15 table with a year that may be unknown', () {
    ResolvedFault resolve(int? year, {String code = 'P0107'}) {
      final profile = VehicleProfile(id: 'v', name: '', make: 'Yamaha', model: 'R15', year: year);
      final ctx = activeVehicleSnapshot(profile).context;
      return FaultResolver(index: KnowledgeIndex.empty)
          .resolve(obd(code), ctx, 'en', domain: FaultDomain.engine);
    }

    test('unknown: the table, with the check-your-model-year note flag', () {
      final r = resolve(null);
      expect(r.maker, isNotNull);
      expect(r.maker!.yearUnknown, isTrue);
    });

    test('2021: never', () => expect(resolve(2021).maker, isNull));
    test('2022: shown, no note', () {
      final r = resolve(2022);
      expect(r.maker, isNotNull);
      expect(r.maker!.yearUnknown, isFalse);
    });
    test('2025: shown, no note', () {
      final r = resolve(2025);
      expect(r.maker, isNotNull);
      expect(r.maker!.yearUnknown, isFalse);
    });

    test('the snapshot carries no year when the profile has none', () {
      final snap = activeVehicleSnapshot(VehicleProfile(id: 'v', name: '', make: 'Yamaha', model: 'R15'));
      expect(snap.context.modelYear, isNull);
      expect(snap.label, 'Yamaha R15');
    });

    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] the card with an unknown year shows the table and the note', (tester) async {
        final env = await screens.setUp(tester,
            lang: lang,
            make: 'Yamaha',
            model: 'R15',
            yearUnknown: true,
            sim: EngineSim(mode03: '7E8 04 43 01 01 07'));
        final xs = await screens.showDtc(tester, env);
        expect(xs.any((x) => x.contains(t('makerYearNoteR15', lang))), isTrue);
        expect(xs.any((x) => x.contains(t('provenanceManual', lang))), isTrue);
        expect(xs.any((x) => x.contains('null')), isFalse);
        await env.close(tester);
      });
    }

    testWidgets('the old default year of 2020 is gone: an untouched profile is "unknown", not 2020',
        (tester) async {
      final env = await screens.setUp(tester,
          make: 'Yamaha', model: 'R15', yearUnknown: true, sim: EngineSim(mode03: '7E8 04 43 01 01 07'));
      expect(env.vehicles.active!.year, isNull);
      await env.close(tester);
    });
  });
}
