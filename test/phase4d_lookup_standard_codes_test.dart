/// Phase 4D M7 — "Look up a code": a code in standard format (P, B, C or U plus
/// the standard's four characters) resolves through the generic path on EVERY
/// make, Bosch-ABS makes included, and also shows this bike's maker-table
/// meaning when the active profile has one. A Bosch raw module code (5043H)
/// keeps its existing handling. A code in a manufacturer range says its meaning
/// can differ by make.
library;

import 'dart:io';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/knowledge/code_lookup.dart';
import 'package:danlite_elm/knowledge/fault_resolver.dart';
import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/screens/code_lookup_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phase1b_screens_test.dart' as screens;

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

const String note = 'Meaning of manufacturer-defined codes can differ by make';
const String p0107Generic = 'Intake manifold pressure (MAP) sensor: voltage below threshold';
const String p0107Yamaha = 'Intake air pressure sensor, open circuit or short to ground';

bool has(List<String> xs, String s) => xs.any((x) => x.contains(s));

FaultRecord record(String code, [DtcFormat f = DtcFormat.sae2]) =>
    lookupRecord(code, f);

ResolvedFault lookup(String? make, String model, String code,
    {int? year, DtcFormat format = DtcFormat.sae2, String lang = 'en'}) {
  final v = make == null
      ? VehicleContext.generic
      : VehicleContext.fromProfile(make: make, model: model, year: year);
  return FaultResolver(index: KnowledgeIndex.empty)
      .resolve(record(code, format), v, lang, domain: FaultDomain.lookup);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M7 the words', () {
    test('English exact, Hindi present, one key in each table', () {
      expect(t('lookupMfrRangeNote'), note);
      expect(t('lookupMfrRangeNote', 'hi'), isNot(t('lookupMfrRangeNote')));
      expect(t('lookupMfrRangeNote', 'hi').contains(RegExp(r'[ऀ-ॿ]')), isTrue);
      expect(t('lookupMfrRangeNote', 'hi').contains(RegExp(r'[०-९]')), isFalse);
      final src = File('lib/constants/app_strings.dart').readAsStringSync();
      expect(RegExp("'lookupMfrRangeNote':").allMatches(src).length, 2);
    });
  });

  group('M7 the resolver in lookup mode', () {
    // One standard-format code, every kind of profile.
    for (final (make, model) in <(String?, String)>[
      (null, ''),
      ('Yamaha', 'FZ-S'),
      ('Yamaha', 'R15'),
      ('Bajaj', 'Pulsar 150'),
      ('Suzuki', 'Gixxer'),
      ('KTM', 'Duke 200'),
      ('Honda', 'CB350'),
      ('Honda', 'Activa'),
      ('Royal Enfield', 'Classic 350'),
      ('Foo', 'Bar'),
    ]) {
      test('P0107 on ${make ?? 'no profile'} $model: the generic path, never "raw only"', () {
        final r = lookup(make, model, 'P0107', year: 2021);
        expect(r.level, isNot(ResolvedLevel.l6Raw), reason: '$make $model');
        expect(r.provenance, isNot(Provenance.rawOnly));
        expect(r.structure != null || r.provenance != Provenance.rawOnly, isTrue);
      });
    }

    test('with the content present, the generic meaning is the answer on a Bosch make', () {
      final entry = FaultResolver(
          index: KnowledgeIndex([
        _generic('P0107', 'Generic P0107'),
      ]));
      for (final (make, model) in [('Yamaha', 'FZ-S'), ('Bajaj', 'Pulsar 150'), ('KTM', 'Duke 200')]) {
        final r = entry.resolve(record('P0107'),
            VehicleContext.fromProfile(make: make, model: model), 'en',
            domain: FaultDomain.lookup);
        expect(r.level, ResolvedLevel.l4Generic, reason: make);
        expect(r.title, 'Generic P0107');
      }
    });

    test('the older modes are unchanged: an engine read and an unknown-module answer on a Bosch make',
        () {
      final bosch = VehicleContext.fromProfile(make: 'Yamaha', model: 'FZ-S');
      final engine = FaultResolver(index: KnowledgeIndex([_generic('P0107', 'Generic P0107')]))
          .resolve(record('P0107'), bosch, 'en', domain: FaultDomain.engine);
      expect(engine.title, 'Generic P0107');
      // Default mode (a chassis-style read of an unknown module): still raw.
      final unknown = FaultResolver(index: KnowledgeIndex.empty)
          .resolve(record('P0107'), bosch, 'en');
      expect(unknown.level, ResolvedLevel.l6Raw);
    });

    test('an R15 (2022 or later) gets the maker meaning first, in lookup mode too', () {
      final r = lookup('Yamaha', 'R15', 'P0107', year: 2022);
      expect(r.maker, isNotNull);
      expect(r.title, p0107Yamaha);
      expect(lookup('Yamaha', 'R15', 'P0107', year: 2021).maker, isNull);
      expect(lookup('Yamaha', 'R15', 'P0107', year: null).maker!.yearUnknown, isTrue);
      expect(lookup('Honda', 'R15', 'P0107', year: 2022).maker, isNull);
    });

    test('a manufacturer-range code is never given a generic meaning, on any make', () {
      for (final make in [null, 'Yamaha', 'Bajaj']) {
        final r = FaultResolver(index: KnowledgeIndex([_generic('P1000', 'Should never show')]))
            .resolve(record('P1000'),
                make == null ? VehicleContext.generic : VehicleContext.fromProfile(make: make, model: 'x'),
                'en',
                domain: FaultDomain.lookup);
        expect(r.title, isNot('Should never show'));
        expect(r.level, ResolvedLevel.l5Structure);
        expect(r.structure!.manufacturerDefined, isTrue);
      }
    });

    test('Bosch raw module codes keep their handling: raw, never generic', () {
      final bosch = VehicleContext.fromProfile(make: 'Yamaha', model: 'FZ-S');
      final r = FaultResolver(index: KnowledgeIndex([_generic('C1043', 'Should never show')]))
          .resolve(record('5043H', DtcFormat.hexH), bosch, 'en', domain: FaultDomain.lookup);
      expect(r.level, ResolvedLevel.l6Raw);
      expect(r.provenance, Provenance.rawOnly);
      expect(r.title, isNull);
      // The derived SAE form listed beside it keeps the same raw treatment.
      final d = FaultResolver(index: KnowledgeIndex([_generic('C1043', 'Should never show')]))
          .resolve(record('C1043', DtcFormat.hexH), bosch, 'en', domain: FaultDomain.lookup);
      expect(d.level, ResolvedLevel.l6Raw);
      expect(d.title, isNull);
    });

    test('0x5200 (sourced at module level) still resolves for a Bosch make', () {
      final r = lookup('Yamaha', 'FZ-S', '5200H', format: DtcFormat.hexH);
      expect(r.level, ResolvedLevel.l3ModuleFamily);
      expect(r.provenance, Provenance.dealerReadout);
    });
  });

  group('M7 the lookup detail screen', () {
    Future<List<String>> detail(WidgetTester tester, screens.Env env, String code,
        [DtcFormat f = DtcFormat.sae2]) async {
      await tester.pumpWidget(env.wrap(CodeLookupDetailScreen(code: code, format: f)));
      await tester.pump(const Duration(milliseconds: 50));
      return screens.texts(tester);
    }

    for (final (make, model) in <(String?, String)>[
      ('Yamaha', 'FZ-S'),
      ('Bajaj', 'Pulsar 150'),
      (null, ''),
    ]) {
      for (final lang in ['en', 'hi']) {
        testWidgets('[$lang] P0107 on ${make ?? 'no profile'}: the generic meaning', (tester) async {
          final env = await screens.setUp(tester, lang: lang, make: make, model: model);
          final xs = await detail(tester, env, 'P0107');
          if (lang == 'en') expect(has(xs, p0107Generic), isTrue);
          expect(has(xs, t('faultRawShowDealer', lang)), isFalse,
              reason: 'not the "show it to your dealer" answer');
          expect(xs, isNot(contains(t('provenanceRaw', lang))));
          expect(has(xs, t('provenanceAi', lang)), isTrue, reason: 'labelled as guidance, not as the maker');
          expect(has(xs, note), isFalse, reason: 'P0107 is in a standard range');
          expect(has(xs, t('lookupMfrRangeNote', lang)), isFalse);
          await env.close(tester);
        });
      }
    }

    testWidgets('a Yamaha R15 (2022): this bike\'s maker meaning, not the generic one', (tester) async {
      final env = await screens.setUp(tester, make: 'Yamaha', model: 'R15', year: 2022);
      final xs = await detail(tester, env, 'P0107');
      expect(xs, contains(p0107Yamaha));
      expect(has(xs, p0107Generic), isFalse);
      expect(has(xs, t('provenanceManual')), isTrue);
      await env.close(tester);
    });

    for (final (make, model) in <(String?, String)>[
      ('Yamaha', 'FZ-S'),
      ('Bajaj', 'Pulsar 150'),
      ('Yamaha', 'R15'),
      (null, ''),
    ]) {
      for (final lang in ['en', 'hi']) {
        testWidgets('[$lang] P1000 on ${make ?? 'no profile'}: structure, the manufacturer note, no generic meaning',
            (tester) async {
          final env = await screens.setUp(tester, lang: lang, make: make, model: model, year: 2022);
          final xs = await detail(tester, env, 'P1000');
          expect(has(xs, t('lookupMfrRangeNote', lang)), isTrue);
          expect(has(xs, t('dtcManufacturerSpecific', lang)), isTrue);
          expect(has(xs, p0107Generic), isFalse);
          await env.close(tester);
        });
      }
    }

    testWidgets('the note also shows for the other manufacturer ranges (P3000, C1043, U2000, B2000)',
        (tester) async {
      final env = await screens.setUp(tester, make: 'Yamaha', model: 'FZ-S');
      for (final c in ['P3000', 'C1043', 'U2000', 'B2000']) {
        final xs = await detail(tester, env, c);
        expect(has(xs, note), isTrue, reason: c);
      }
      for (final c in ['P0300', 'P2195', 'U0100', 'C0035', 'B0001', 'P3400']) {
        final xs = await detail(tester, env, c);
        expect(has(xs, note), isFalse, reason: c);
      }
      await env.close(tester);
    });

    testWidgets('a Bosch raw module code (5043H) on a Yamaha profile: raw handling, no generic, no note',
        (tester) async {
      final env = await screens.setUp(tester, make: 'Yamaha', model: 'FZ-S');
      final xs = await detail(tester, env, '5043H', DtcFormat.hexH);
      expect(has(xs, t('provenanceRaw')), isTrue);
      expect(has(xs, t('faultRawShowDealer')), isTrue);
      expect(has(xs, note), isFalse);
      expect(has(xs, p0107Generic), isFalse);
      await env.close(tester);
    });

    testWidgets('the lookup list: typing P0107 on a Yamaha profile lists the generic meaning',
        (tester) async {
      final env = await screens.setUp(tester, make: 'Yamaha', model: 'FZ-S');
      final res = await tester.runAsync(() => searchCodes(parseLookupQuery('P0107'),
          store: env.knowledge!.store, language: 'en'));
      expect(res!.items.any((i) => i.code == 'P0107' && i.title == p0107Generic), isTrue);
      await env.close(tester);
    });
  });
}

KbEntry _generic(String code, String title) => KbEntry(
      contentId: 'generic:$code:en',
      code: code,
      scopeKind: ScopeKind.generic,
      language: 'en',
      title: title,
      meaning: 'm.',
      riderAction: RiderAction.monitor,
      canRide: CanRide.yes,
      verification: 'ai_authored_from_standard_title',
      packId: 'p',
    );
