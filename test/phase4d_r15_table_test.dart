/// Phase 4D M3 — the Yamaha R15 maker table (service manual page 8-47, 2022
/// R15 / R15M / YZF155-A). Data, scope, year rule, precedence and strings.
///
/// The table is a static, in-code manufacturer table (the Royal Enfield ABS
/// table pattern), not a knowledge pack: the pack format is AI-guidance only
/// (no maker-manual verification, no vehicle year, no fail-safe columns).
library;

import 'dart:io';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/constants/maker_engine_tables.dart';
import 'package:danlite_elm/knowledge/fault_resolver.dart';
import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:flutter_test/flutter_test.dart';

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

/// The brief, transcribed independently of the code under test:
/// code, English meaning, engine starts, bike can be driven, dealer-tool item
/// (null = none), check mark.
typedef Row = (String, String, bool, bool, String?, String);
const List<Row> brief = [
  ('P0030', 'O2 sensor heater faulty or heater command and feedback do not match', true, true, null, 'none'),
  ('P00D1', 'O2 sensor, no normal signal while driving', true, true, null, 'reconstructed'),
  ('P2195', 'O2 sensor, open circuit', true, true, null, 'reconstructed'),
  ('P0106', 'Intake air pressure sensor, hole clogged or sensor installed wrongly', true, true, '03', 'none'),
  ('P0107', 'Intake air pressure sensor, open circuit or short to ground', true, true, '03', 'none'),
  ('P0108', 'Intake air pressure sensor, short to power', true, true, '03', 'none'),
  ('P0112', 'Intake air temperature sensor, short to ground', true, true, '05', 'none'),
  ('P0113', 'Intake air temperature sensor, open circuit or short to power', true, true, '05', 'none'),
  ('P0117', 'Coolant temperature sensor, short to ground', true, true, '06', 'none'),
  ('P0118', 'Coolant temperature sensor, open circuit or short to power', true, true, '06', 'none'),
  ('P0122', 'Throttle position sensor, open circuit or short to ground', true, true, '01', 'none'),
  ('P0123', 'Throttle position sensor, short to power', true, true, '01', 'none'),
  ('P0132', 'O2 sensor, short to power', true, true, null, 'inferred'),
  ('P0201', 'Fuel injector fault', true, false, '36', 'none'),
  ('P0335', 'Crankshaft position sensor, no normal signal', false, false, null, 'none'),
  ('P0351', 'Ignition coil, no normal signal from the ignition circuit', false, false, '30', 'none'),
  ('P0480', 'Radiator fan motor relay, no normal signal', true, true, '51', 'none'),
  ('P0500', 'Front wheel (speed) sensor, no normal signal', true, true, '07', 'none'),
  ('P0511', 'Fast-idle (FID) solenoid valve, open or short between valve and ECU', true, true, '54', 'none'),
  ('P0560', 'Battery charging voltage abnormal, discharged', true, true, null, 'none'),
  ('P0563', 'Battery charging voltage abnormal, overcharged', true, true, null, 'none'),
];

FaultRecord obd(String code) => FaultRecord.fromObdCode(code,
    source: ReadSource.mode03, readAt: DateTime.utc(2026, 10, 4));

VehicleContext bike(String make, String model, {int? year = 2022}) =>
    VehicleContext.fromProfile(profileId: 'v1', make: make, model: model, year: year);

ResolvedFault resolve(VehicleContext v, String code,
        {String lang = 'en',
        FaultDomain domain = FaultDomain.engine,
        List<KbEntry> store = const <KbEntry>[],
        LegacyTextLookup? legacy}) =>
    FaultResolver(index: KnowledgeIndex(store), legacy: legacy)
        .resolve(obd(code), v, lang, domain: domain);

KbEntry generic(String code, String verification,
        {String lang = 'en', String title = 'Generic title'}) =>
    KbEntry(
      contentId: 'generic:$code:$lang',
      code: code,
      scopeKind: ScopeKind.generic,
      language: lang,
      title: title,
      meaning: verification == 'standard_title_only' ? 'Standard name: $title.' : 'Generic meaning.',
      riderAction:
          verification == 'standard_title_only' ? RiderAction.info : RiderAction.monitor,
      canRide: verification == 'standard_title_only' ? null : CanRide.yes,
      verification: verification,
      packId: 'p',
    );

void main() {
  group('M3 the data, row by row (brief page 8-47)', () {
    final rows = MakerEngineTables.rowsFor(kYamahaR15TableKey);

    test('exactly the 21 codes of the brief, once each, in order', () {
      expect([for (final r in rows) r.code], [for (final b in brief) b.$1]);
      expect(rows.map((r) => r.code).toSet(), hasLength(rows.length));
    });

    for (final b in brief) {
      test('${b.$1}: meaning, fail-safe columns, dealer item, check mark', () {
        final r = rows.firstWhere((x) => x.code == b.$1);
        expect(r.meaningEn, b.$2);
        expect(r.engineStarts, b.$3, reason: 'engine starts');
        expect(r.canDrive, b.$4, reason: 'bike can be driven');
        expect(r.dealerItem, b.$5);
        expect(r.check.name, b.$6);
      });
    }

    test('every row has Hindi text: Devanagari, Latin digits, no banned spellings', () {
      for (final r in rows) {
        expect(r.meaningHi, isNotEmpty, reason: r.code);
        expect(r.meaningHi, isNot(r.meaningEn), reason: r.code);
        expect(r.meaningHi.contains(RegExp(r'[ऀ-ॿ]')), isTrue, reason: r.code);
        expect(r.meaningHi.contains(RegExp(r'[०-९]')), isFalse, reason: r.code);
        expect(r.meaningHi.contains('एडाप्टर'), isFalse);
        expect(r.meaningHi.contains('फॉल्ट कोड'), isFalse);
      }
    });

    test('no rider text carries a draft mark or a bracket from the brief', () {
      for (final r in rows) {
        for (final s in [r.meaningEn, r.meaningHi]) {
          expect(s.contains('['), isFalse);
          expect(s.toLowerCase().contains('reconstructed'), isFalse);
          expect(s.toLowerCase().contains('inferred'), isFalse);
        }
      }
    });

    test('only the standard P-code shape; no manufacturer P1xxx and no ABS code', () {
      for (final r in rows) {
        expect(RegExp(r'^P[0-3][0-9A-F]{3}$').hasMatch(r.code), isTrue);
        expect(r.code.startsWith('P1'), isFalse);
      }
    });

    test('the three marked rows are exactly the unverified ones', () {
      expect({for (final r in rows) if (r.check != MakerRowCheck.none) r.code},
          {'P00D1', 'P2195', 'P0132'});
    });
  });

  group('M3 scope: which bike gets the table', () {
    for (final m in [
      'R15', 'r15', 'R15M', 'R 15', 'R15 V4', 'YZF-R15', 'YZF R15 V4', 'YZF-R15M', 'YZF155', 'YZF-155-A'
    ]) {
      test('Yamaha "$m" (2022): the maker table', () {
        expect(MakerEngineTables.vehicleKeyFor('Yamaha', m), kYamahaR15TableKey);
        final r = resolve(bike('Yamaha', m), 'P0107');
        expect(r.maker, isNotNull);
        expect(r.title, 'Intake air pressure sensor, open circuit or short to ground');
      });
    }

    for (final make in ['yamaha', 'YAMAHA', ' Yamaha Motor ', 'India Yamaha Motor']) {
      test('make "$make" is the same make', () {
        expect(resolve(bike(make, 'R15'), 'P0107').maker, isNotNull);
      });
    }

    for (final (make, model) in [
      ('Honda', 'R15'),
      ('Honda', 'CB350'),
      ('Royal Enfield', 'R15'),
      ('Bajaj', 'R15'),
      ('', 'R15'),
      ('Foo Motors', 'R15'),
      ('Yamaha', 'FZ-S'),
      ('Yamaha', 'FZ16'),
      ('Yamaha', 'MT-15'),
      ('Yamaha', 'R15 V3'),
      ('Yamaha', 'R15S'),
      ('Yamaha', 'R1'),
      ('Yamaha', 'R125'),
      ('Yamaha', 'R150'),
      ('Yamaha', ''),
      ('Yamaha', 'Classic 350'),
    ]) {
      test('"$make" "$model": never the R15 table', () {
        expect(MakerEngineTables.vehicleKeyFor(make, model), isNull);
        final r = resolve(bike(make, model), 'P0107');
        expect(r.maker, isNull);
        expect(r.provenance, isNot(Provenance.serviceManual));
      });
    }

    test('no vehicle at all, and a context built without a make', () {
      expect(resolve(VehicleContext.generic, 'P0107').maker, isNull);
      expect(resolve(const VehicleContext(model: 'R15', vehicleKey: kYamahaR15TableKey), 'P0107').maker,
          isNull,
          reason: 'a vehicle key without the make is not trusted');
      expect(
          resolve(
                  const VehicleContext(
                      make: 'Honda',
                      model: 'R15',
                      manufacturerKey: 'honda',
                      vehicleKey: kYamahaR15TableKey),
                  'P0107')
              .maker,
          isNull,
          reason: 'a Honda profile never gets a Yamaha table, even if the key is forced');
    });

    test('a code the table does not list is not answered by it', () {
      for (final c in ['P0300', 'P0120', 'P0562', 'P0134']) {
        expect(resolve(bike('Yamaha', 'R15'), c).maker, isNull, reason: c);
      }
    });

    test('an ABS-domain answer never comes from it', () {
      expect(resolve(bike('Yamaha', 'R15'), 'P0107', domain: FaultDomain.abs).maker, isNull);
    });

    test('the platform (ABS) answer for a Yamaha is unchanged', () {
      final v = bike('Yamaha', 'R15');
      expect(v.platformKey, 'yamaha_bosch_abs');
      expect(v.moduleFamily, 'bosch_abs');
      final c = resolve(v, 'C1043', domain: FaultDomain.abs);
      expect(c.maker, isNull);
      expect(c.level, ResolvedLevel.l6Raw);
    });
  });

  group('M3 the year rule (the source manual covers 2022 models only)', () {
    for (final (year, shown) in [
      (1999, false), (2015, false), (2020, false), (2021, false),
      (2022, true), (2023, true), (2025, true), (2031, true),
    ]) {
      test('model year $year: ${shown ? 'shown, no year note' : 'never shown'}', () {
        final r = resolve(bike('Yamaha', 'R15', year: year), 'P0107');
        expect(r.maker != null, shown);
        if (shown) {
          expect(r.maker!.yearUnknown, isFalse);
        } else {
          expect(r.provenance, isNot(Provenance.serviceManual));
        }
      });
    }

    test('missing year: shown, with the check-your-model-year note', () {
      final r = resolve(bike('Yamaha', 'R15', year: null), 'P0107');
      expect(r.maker, isNotNull);
      expect(r.maker!.yearUnknown, isTrue);
    });

    test('the year note words, English and Hindi', () {
      expect(t('makerYearNoteR15'),
          'This table is from the 2022 R15/R15M manual; check your model year.');
      expect(t('makerYearNoteR15', 'hi'), isNot(t('makerYearNoteR15')));
      expect(t('makerYearNoteR15', 'hi'), contains('2022'));
    });

    test('an older year falls back to the ordinary generic answer, not to nothing', () {
      final r = resolve(bike('Yamaha', 'R15', year: 2020), 'P0107',
          store: [generic('P0107', 'ai_authored_from_standard_title')]);
      expect(r.maker, isNull);
      expect(r.provenance, Provenance.aiGuidance);
      expect(r.title, 'Generic title');
    });
  });

  group('M3 precedence', () {
    final both = [
      generic('P0107', 'ai_authored_from_standard_title', title: 'Generic guidance'),
      generic('P0107', 'standard_title_only', lang: 'hi', title: 'हिंदी नाम'),
    ];
    final nameOnly = [generic('P0107', 'standard_title_only', title: 'Bare name')];
    LegacyText? legacy(String code, String lang) => code == 'P0107'
        ? const LegacyText(title: 'Old table title', severity: 'high')
        : null;

    test('for the R15 the maker beats generic guidance, a bare name and the older table', () {
      for (final store in [both, nameOnly, const <KbEntry>[]]) {
        final r = resolve(bike('Yamaha', 'R15'), 'P0107', store: store, legacy: legacy);
        expect(r.level, ResolvedLevel.l1Vehicle);
        expect(r.provenance, Provenance.serviceManual);
        expect(r.provenance.labelKey, 'provenanceManual');
        expect(r.title, 'Intake air pressure sensor, open circuit or short to ground');
        expect(r.title, isNot(contains('Generic')));
        expect(r.title, isNot(contains('Bare')));
        expect(r.title, isNot(contains('Old table')));
      }
    });

    test('for any other bike the generic answer stays, and says generic', () {
      for (final v in [bike('Honda', 'R15'), bike('Yamaha', 'FZ-S'), VehicleContext.generic]) {
        final r = resolve(v, 'P0107', store: both, legacy: legacy);
        expect(r.maker, isNull);
        expect(r.provenance, Provenance.aiGuidance);
        expect(r.title, 'Generic guidance');
        expect(r.level, ResolvedLevel.l4Generic);
      }
      final bare = resolve(bike('Honda', 'CB350'), 'P0107', store: nameOnly, legacy: legacy);
      expect(bare.provenance, Provenance.legacyTable, reason: 'the existing L4 order is untouched');
    });

    test('the maker row is not also a generic answer: nothing from the store leaks in', () {
      final r = resolve(bike('Yamaha', 'R15'), 'P0107', store: both, legacy: legacy);
      expect(r.contentId, isNot(startsWith('generic:')));
      expect(r.causes, isEmpty);
      expect(r.hints, isEmpty);
      expect(r.legacySeverity, isNull);
    });
  });

  group('M3 what each row says about riding', () {
    final v = bike('Yamaha', 'R15');
    for (final b in brief) {
      final stop = !b.$3 || !b.$4;
      test('${b.$1}: ${stop ? 'Stop, cannot ride' : 'Service soon, with care'}', () {
        final r = resolve(v, b.$1);
        expect(r.riderAction, stop ? RiderAction.stop : RiderAction.serviceSoon);
        expect(r.canRide, stop ? CanRide.no : CanRide.withCare);
        expect(r.maker!.engineStarts, b.$3);
        expect(r.maker!.canDrive, b.$4);
        expect(r.maker!.dealerItem, b.$5);
        expect(r.maker!.check.name, b.$6);
        expect(r.draft, b.$6 != 'none', reason: 'the draft line only on the unverified rows');
        expect(r.provenance, Provenance.serviceManual);
        expect(r.level, ResolvedLevel.l1Vehicle);
        expect(r.hasMeaning, isTrue);
        expect(r.causes, isEmpty, reason: 'no cause is invented');
        expect(r.riderAdvice, isNull, reason: 'no advice is invented');
      });
    }

    test('the Stop rows are exactly P0201, P0335 and P0351', () {
      final stops = [
        for (final b in brief)
          if (resolve(v, b.$1).riderAction == RiderAction.stop) b.$1
      ];
      expect(stops, ['P0201', 'P0335', 'P0351']);
    });

    test('every answer obeys the app rule: Stop means cannot ride', () {
      for (final b in brief) {
        final r = resolve(v, b.$1);
        expect(r.riderAction == RiderAction.stop, r.canRide == CanRide.no, reason: b.$1);
      }
    });
  });

  group('M3 Hindi', () {
    final v = bike('Yamaha', 'R15');
    test('Hindi asked: the Hindi meaning, marked machine-translated', () {
      final r = resolve(v, 'P0335', lang: 'hi');
      expect(r.languageUsed, 'hi');
      expect(r.title, MakerEngineTables.rowsFor(kYamahaR15TableKey)
          .firstWhere((x) => x.code == 'P0335')
          .meaningHi);
      expect(r.hindiMachine, isTrue);
      expect(r.languageFallback, isFalse);
    });

    test('English asked: English, no machine line', () {
      final r = resolve(v, 'P0335');
      expect(r.languageUsed, 'en');
      expect(r.hindiMachine, isFalse);
    });

    test('another language falls back to English, with the existing note', () {
      final r = resolve(v, 'P0335', lang: 'bn');
      expect(r.title, 'Crankshaft position sensor, no normal signal');
      expect(r.languageUsed, 'en');
      expect(r.languageFallback, isTrue);
      expect(r.hindiMachine, isFalse);
    });
  });

  group('M3 the strings', () {
    const keys = [
      'makerFailSafeNoStart',
      'makerFailSafeNoDrive',
      'makerFailSafeCanDrive',
      'makerJudgementNote',
      'makerYearNoteR15',
      'makerDealerItem',
      'makerCheckReconstructed',
      'makerCheckInferred',
      'makerSourceR15',
    ];

    test('the three fail-safe lines, word for word, with the make filled in', () {
      String fill(String s) => s.replaceAll('{make}', 'Yamaha');
      expect(fill(t('makerFailSafeNoStart')),
          'Yamaha says the engine will not start and the bike cannot be driven');
      expect(fill(t('makerFailSafeCanDrive')), 'Yamaha says the bike can still be driven');
      expect(fill(t('makerFailSafeNoDrive')), 'Yamaha says the bike cannot be driven');
    });

    test('the check notes carry the required phrase', () {
      for (final k in ['makerCheckReconstructed', 'makerCheckInferred']) {
        expect(t(k).toLowerCase(), contains('to be checked against the manual page'));
      }
    });

    test('the source line names the manual and page', () {
      expect(t('makerSourceR15'), contains('Yamaha R15'));
      expect(t('makerSourceR15'), contains('2022'));
      expect(t('makerSourceR15'), contains('8-47'));
    });

    test('the judgement note says the ride answer is the app\'s reading', () {
      expect(t('makerJudgementNote'), contains('Danlite'));
      expect(t('makerJudgementNote'), contains('fail-safe'));
    });

    test('every key exists in English and in Hindi, in source, and the two differ', () {
      final src = File('lib/constants/app_strings.dart').readAsStringSync();
      for (final k in keys) {
        expect(RegExp("'$k':").allMatches(src).length, 2, reason: k);
        expect(t(k, 'en'), isNot(k));
        expect(t(k, 'hi'), isNot(k));
        expect(t(k, 'hi'), isNot(t(k, 'en')), reason: k);
        expect(t(k, 'hi').contains(RegExp(r'[०-९]')), isFalse, reason: k);
        expect(t(k, 'hi').contains('एडाप्टर'), isFalse);
        // The same placeholders in both languages.
        expect(RegExp(r'\{(\w+)\}').allMatches(t(k, 'hi')).map((m) => m[1]).toSet(),
            RegExp(r'\{(\w+)\}').allMatches(t(k, 'en')).map((m) => m[1]).toSet(),
            reason: k);
      }
    });
  });
}
