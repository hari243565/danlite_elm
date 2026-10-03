/// Phase 4C K3 — the borrowed engine text is gone. What is left: the shipped
/// guidance, the name-only packs, the 31-entry table (kept by the Phase 0
/// decision) and, for any code none of them describes, its structure, its raw
/// value and "show it to your dealer".
library;

import 'dart:io';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/constants/chassis_dtc_dictionary_hi.dart';
import 'package:danlite_elm/constants/dtc_descriptions.dart';
import 'package:danlite_elm/knowledge/fault_resolver.dart';
import 'package:danlite_elm/knowledge/legacy_text.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/screens/code_lookup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phase1b_screens_test.dart' as screens;
import 'support/engine_sim.dart';
import 'support/knowledge_harness.dart';

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

FaultRecord obd(String code) => FaultRecord.fromObdCode(code,
    source: ReadSource.mode03, readAt: DateTime.utc(2026, 10, 3));

/// Pieces are joined so this file does not match its own search.
String j(String a, String b) => '$a$b';

/// A standard code in none of the content: not in the 308, not in the
/// name-only packs (the content owner holds it out), not in the 31-entry table.
const String kNoContentCode = 'P0134';
const String kNoContentReply = '7E8 04 43 01 01 34';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('K3 everything borrowed is gone', () {
    test('the files', () {
      for (final f in [
        'assets/dtc_translations.json',
        'lib/constants/dtc_dictionary_hi.dart',
        'lib/constants/build_flags.dart',
        'test/store_build_guard_test.dart',
      ]) {
        expect(File(f).existsSync(), isFalse, reason: f);
      }
      expect(File('pubspec.yaml').readAsStringSync(),
          isNot(contains(j('dtc_trans', 'lations'))));
    });

    test('no source file in lib/ or test/ mentions anything that was deleted', () {
      final forbidden = <RegExp>[
        RegExp(j('kUseLegacy', 'EngineText')),
        RegExp(j('legacyEngineText', 'Allowed')),
        RegExp(j('dtc_trans', 'lations')),
        RegExp('\\b${j('DtcDictionary', 'Hi')}\\b'),
        RegExp('(?<![a-z_])${j('dtc_dictionary', '_hi')}'),
        RegExp(j('legacy', 'Imported')),
        RegExp(j('provenanceLegacy', 'Imported')),
        RegExp(j('useImportedLegacy', 'Text')),
        RegExp(j('load', 'JsonForTesting')),
        RegExp(j('DtcLocalizations', '.init')),
        RegExp(j('DtcLocalizations', '.description')),
        RegExp(j('STORE', '_BUILD')),
        RegExp(j('kStore', 'Build')),
        RegExp(j('build', '_flags')),
        RegExp(j('parseRaw', 'Dictionary')),
      ];
      final hits = <String>[];
      for (final root in ['lib', 'test']) {
        for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
          if (!f.path.endsWith('.dart') || f.path.endsWith('phase4c_legacy_retirement_test.dart')) continue;
          final text = f.readAsStringSync();
          for (final re in forbidden) {
            if (re.hasMatch(text)) hits.add('${f.path}: ${re.pattern}');
          }
        }
      }
      expect(hits, isEmpty);
    });

    test('the "older imported text" label is gone from the strings, in English and Hindi', () {
      final key = j('provenanceLegacy', 'Imported');
      expect(AppStrings.get(key, 'en'), key);
      expect(AppStrings.get(key, 'hi'), key);
    });

    test('the provenance labels are the six that remain, plus the name-only one', () {
      expect(Provenance.values.map((p) => p.labelKey).toList(), [
        'provenanceAi', 'provenanceManual', 'provenanceManualNoMeaning',
        'provenanceDealerReadout', 'provenanceLegacyTable',
        'provenanceStructure', 'provenanceRaw', 'provenanceStandardTitleOnly',
      ]);
    });
  });

  group('K3 what is kept', () {
    test('the 31-entry table', () {
      expect(DtcDatabase.codes.length, 31);
      expect(DtcDatabase.codes['P0400'], isNotNull);
    });

    test('the Hindi text of the ABS tables', () {
      expect(ChassisDtcDictionaryHi.byPlatform, isNotEmpty);
      final all = ChassisDtcDictionaryHi.byPlatform.values.expand((m) => m.values).toList();
      expect(all, isNotEmpty);
      expect(all.any((e) => e.description.contains(RegExp(r'[ऀ-ॿ]'))), isTrue);
    });

    test('a table code outside the content is still answered, in English, as older text', () {
      // P0400 is in the 31-entry table and in neither content set.
      final resolver = FaultResolver(index: KnowledgeIndex.empty, legacy: legacyEngineText);
      for (final lang in ['en', 'hi']) {
        final r = resolver.resolve(obd('P0400'), VehicleContext.generic, lang,
            domain: FaultDomain.engine);
        expect(r.provenance, Provenance.legacyTable, reason: lang);
        expect(r.title, DtcDatabase.codes['P0400']!['desc']);
        expect(r.languageUsed, 'en');
        expect(r.languageFallback, lang == 'hi', reason: 'Hindi riders are told it is English');
        expect(r.causes, [DtcDatabase.codes['P0400']!['cause']]);
      }
    });

    test('a manufacturer-defined code is never described, whatever the table holds', () {
      final resolver = FaultResolver(index: KnowledgeIndex.empty, legacy: legacyEngineText);
      for (final c in ['P1100', 'P1ABC', 'P3000', 'B1000', 'C1015', 'U1000']) {
        final r = resolver.resolve(obd(c), VehicleContext.generic, 'en', domain: FaultDomain.engine);
        expect(r.title, isNull, reason: c);
        expect(r.level, ResolvedLevel.l5Structure, reason: c);
        expect(legacyEngineText(c, 'en'), isNull, reason: c);
      }
    });
  });

  group('K3 a code in none of the content', () {
    final resolver = FaultResolver(index: KnowledgeIndex.empty, legacy: legacyEngineText);

    test('the resolver gives structure only: no title, no meaning, no cause', () {
      final r = resolver.resolve(obd(kNoContentCode), VehicleContext.generic, 'en',
          domain: FaultDomain.engine);
      expect(r.level, ResolvedLevel.l5Structure);
      expect(r.provenance, Provenance.structureOnly);
      expect(r.title, isNull);
      expect(r.meaning, isNull);
      expect(r.causes, isEmpty);
      expect(r.riderAdvice, isNull);
      expect(r.structure!.system, FaultSystem.powertrain);
      expect(r.structure!.subsystemKey, isNotNull);
      expect(r.code, kNoContentCode);
    });

    test('a value that is not a code at all is raw only', () {
      final r = resolver.resolve(FaultRecord.manual('XYZ1', format: DtcFormat.sae2,
              readAt: DateTime.utc(2026, 10, 3)), VehicleContext.generic, 'en');
      expect(r.level, ResolvedLevel.l6Raw);
    });

    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] the fault card: the raw code, its structure, and the dealer line',
          (tester) async {
        final env = await screens.setUp(tester, lang: lang, sim: EngineSim(mode03: kNoContentReply));
        final xs = await screens.showDtc(tester, env);
        expect(xs, contains(kNoContentCode));
        expect(xs, contains(DtcLocalizationsHeader.of(kNoContentCode, lang)));
        expect(xs, contains(t('dtcSubFuelAir', lang)));
        expect(xs, contains(t('faultRawShowDealer', lang)));
        expect(xs, contains(t('provenanceStructure', lang)));
        // Nothing is claimed: no title, no cause, no advice, no can-ride, no chip.
        expect(xs, isNot(contains(t('faultLikelyCauses', lang).toUpperCase())));
        expect(xs, isNot(contains(t('faultWhatToDo', lang).toUpperCase())));
        expect(xs.any((x) => x.contains(t('canRideYes', lang))), isFalse);
        expect(xs, isNot(contains(t('riderActionInfo', lang))));
        expect(xs.where((x) => x.trim().isEmpty), isEmpty);
        await env.close(tester);
      });

      testWidgets('[$lang] the lookup detail says the same', (tester) async {
        final env = await screens.setUp(tester, lang: lang);
        await tester.pumpWidget(env.wrap(const CodeLookupDetailScreen(
            code: kNoContentCode, format: DtcFormat.sae2)));
        await tester.pump(const Duration(milliseconds: 50));
        final xs = tester.widgetList<Text>(find.byType(Text)).map((x) => x.data ?? '').toList();
        expect(xs, contains(t('faultRawShowDealer', lang)));
        expect(xs, contains(t('provenanceStructure', lang)));
        await env.close(tester);
      });
    }

    testWidgets('the manufacturer-specific message is unchanged', (tester) async {
      final env = await screens.setUp(tester, sim: EngineSim(mode03: '7E8 04 43 01 11 00'));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains(t('dtcManufacturerSpecific')));
      await env.close(tester);
    });
  });

  group('K3 the content covers what the borrowed text used to explain, almost', () {
    test('the codes the borrowed text explained and the content does not are the held-out ones',
        () async {
      // The 244 are listed in docs/faults/PHASE_4C_K3_CODES_LOST.csv (written
      // before the text was deleted); the app now gives each of them structure,
      // its raw value and the dealer line.
      final lines = File('docs/faults/PHASE_4C_K3_CODES_LOST.csv').readAsLinesSync();
      expect(lines.first, 'code,reason_held_out_of_the_content');
      final codes = [for (final l in lines.skip(1)) if (l.trim().isNotEmpty) l.split(',').first];
      expect(codes, hasLength(244));
      final k = await startedKnowledge();
      final inStore = await k.store!.db.rawQuery(
          "SELECT code FROM kb_entry WHERE code IN (${List.filled(codes.length, '?').join(',')}) LIMIT 1",
          codes);
      expect(inStore, isEmpty, reason: 'none of the 244 is in the shipped or name-only content');
      for (final c in codes) {
        final r = k.resolve(obd(c), VehicleContext.generic, 'en', domain: FaultDomain.engine);
        expect(r.provenance, Provenance.structureOnly, reason: c);
      }
      await k.store!.close();
    });
  });
}

/// The category header the card shows, from the same source the screen uses.
class DtcLocalizationsHeader {
  static String of(String code, String lang) =>
      lang == 'hi' ? 'पावरट्रेन' : 'POWERTRAIN';
}
