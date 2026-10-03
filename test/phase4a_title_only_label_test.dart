/// Phase 4A H4 — the provenance label for content whose verification is
/// "standard_title_only": the standard's code name and nothing more.
///
/// The next content phase ships such entries. The label must say exactly that,
/// the draft line must still show, and no existing label may change.
library;

import 'dart:convert';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/knowledge/fault_resolver.dart';
import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/knowledge/kb_validator.dart';
import 'package:danlite_elm/knowledge/knowledge_store.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phase1b_screens_test.dart' as screens;
import 'support/engine_sim.dart';
import 'support/kb_pack_builder.dart';

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

final _at = DateTime(2026, 10, 3, 12);
FaultRecord obd(String code) =>
    FaultRecord.fromObdCode(code, source: ReadSource.mode03, readAt: _at);

KbEntry entry(String verification,
        {String lang = 'en',
        String? title = 'Throttle Position Sensor A Circuit Malfunction',
        String? meaning,
        bool review = true,
        String? packReviewState = 'draft'}) =>
    KbEntry(
      contentId: 'generic:P0120:$lang',
      code: 'P0120',
      scopeKind: ScopeKind.generic,
      language: lang,
      title: title,
      meaning: meaning,
      verification: verification,
      needsIndependentReview: review,
      packId: 'generic_$lang',
      packReviewState: packReviewState,
    );

FaultResolver resolverOf(List<KbEntry> e) =>
    FaultResolver(index: KnowledgeIndex(e), legacy: null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('H4 the strings', () {
    test('exact English and Hindi wording', () {
      expect(t('provenanceStandardTitleOnly'),
          'Standard code name only; no further guidance yet');
      expect(t('provenanceStandardTitleOnly', 'hi'),
          'सिर्फ़ मानक कोड नाम; अभी आगे की जानकारी नहीं है');
      expect(Provenance.standardTitleOnly.labelKey, 'provenanceStandardTitleOnly');
    });
  });

  group('H4 the resolver', () {
    test('an entry with verification standard_title_only carries the new label, '
        'and is still a draft', () {
      final r = resolverOf([entry('standard_title_only')])
          .resolve(obd('P0120'), VehicleContext.generic, 'en');
      expect(r.level, ResolvedLevel.l4Generic);
      expect(r.provenance, Provenance.standardTitleOnly);
      expect(r.title, 'Throttle Position Sensor A Circuit Malfunction');
      expect(r.draft, isTrue);
      expect(r.meaning, isNull, reason: 'no guidance is invented around a bare name');
    });

    test('the draft flag follows the entry or its pack, as before', () {
      final byPack = resolverOf([entry('standard_title_only', review: false)])
          .resolve(obd('P0120'), VehicleContext.generic, 'en');
      expect(byPack.draft, isTrue);
      final reviewed = resolverOf(
              [entry('standard_title_only', review: false, packReviewState: 'reviewed')])
          .resolve(obd('P0120'), VehicleContext.generic, 'en');
      expect(reviewed.draft, isFalse);
      expect(reviewed.provenance, Provenance.standardTitleOnly);
    });

    test('no existing label changes', () {
      for (final v in ['ai_authored_from_standard_title', 'ai_authored_adapted', '']) {
        final r = resolverOf([entry(v, meaning: 'm.')])
            .resolve(obd('P0120'), VehicleContext.generic, 'en');
        expect(r.provenance, Provenance.aiGuidance, reason: 'verification "$v"');
        expect(r.provenance.labelKey, 'provenanceAi');
      }
      expect(Provenance.values.map((p) => p.labelKey).toList(), [
        'provenanceAi', 'provenanceManual', 'provenanceManualNoMeaning',
        'provenanceDealerReadout', 'provenanceLegacyTable', 'provenanceLegacyImported',
        'provenanceStructure', 'provenanceRaw', 'provenanceStandardTitleOnly',
      ], reason: 'the eight old keys keep their order and names; the new one is last');
    });

    test('Hindi asked: the less-claiming label wins if either language row says title only',
        () {
      final r = resolverOf([
        entry('ai_authored_from_standard_title', meaning: 'English meaning.'),
        entry('standard_title_only', lang: 'hi', title: 'थ्रॉटल पोज़ीशन सेंसर A'),
      ]).resolve(obd('P0120'), VehicleContext.generic, 'hi');
      expect(r.provenance, Provenance.standardTitleOnly);
      final r2 = resolverOf([
        entry('standard_title_only', meaning: 'x.'),
        entry('ai_authored_from_standard_title', lang: 'hi', title: 'थ्रॉटल', meaning: 'म.'),
      ]).resolve(obd('P0120'), VehicleContext.generic, 'hi');
      expect(r2.provenance, Provenance.standardTitleOnly);
    });

    test('only guidance entries count as store guidance for the screens', () {
      expect([for (final p in Provenance.values) if (p.isStoreGuidance) p],
          [Provenance.aiGuidance, Provenance.standardTitleOnly]);
    });
  });

  group('H4 the importer', () {
    test('accepts the new verification value and still refuses every other unknown one',
        () async {
      final base = seedLine('P0120');
      final good = Map<String, Object?>.from(base)..['verification'] = 'standard_title_only';
      final (store, _) = await openTempStore();
      final ok = await buildPack(lines: [good]);
      expect((await store.importPack(
              manifestBytes: ok.manifestBytes, entriesBytes: ok.entriesBytes,
              source: PackSource.bundled, appVersion: '1.0.0'))
          .imported, isTrue);
      expect((await store.activeEntries()).single.verification, 'standard_title_only');
      expect(kAllowedVerification, containsAll(<String>[
        'ai_authored_from_standard_title', 'ai_authored_adapted', 'standard_title_only',
      ]));
      for (final bad in ['verified', 'manual', 'standard_title', 'STANDARD_TITLE_ONLY']) {
        final line = Map<String, Object?>.from(base)..['verification'] = bad;
        final p = await buildPack(lines: [line], packId: 'generic_en', version: 2);
        final r = await store.importPack(
            manifestBytes: p.manifestBytes, entriesBytes: p.entriesBytes,
            source: PackSource.bundled, appVersion: '1.0.0');
        expect(r.refusal, ImportRefusal.entriesInvalid, reason: bad);
      }
      await store.close();
    });
  });

  group('H4 on the fault card', () {
    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] shows the new label and the draft line, not the AI-guidance label',
          (tester) async {
        final env = await screens.setUp(tester,
            lang: lang,
            sim: EngineSim(mode03: '7E8 04 43 01 01 20'), beforeRead: (k) async {
          // P0120 re-issued as title-only (English and Hindi rows), a newer version.
          final en = Map<String, Object?>.from(seedLine('P0120'))
            ..['verification'] = 'standard_title_only';
          final pack = await buildPack(
              lines: [for (final l in seedLines()) l['code'] == 'P0120' ? en : l],
              version: kBundledEnVersion + 1);
          expect((await k.store!.importPack(
                  manifestBytes: pack.manifestBytes, entriesBytes: pack.entriesBytes,
                  source: PackSource.debug, appVersion: '1.0.0', allowDebug: true))
              .imported, isTrue);
          final hiLine = (jsonDecode(jsonEncode(
                  (await k.store!.db.query('kb_entry', where: "content_id = 'generic:P0120:hi'"))
                      .first)) as Map)
              .cast<String, Object?>();
          expect(hiLine['language'], 'hi');
          await k.store!.db.update('kb_entry', {'verification': 'standard_title_only'},
              where: "content_id = 'generic:P0120:hi'");
          await k.reload();
        });
        final xs = await screens.showDtc(tester, env);
        expect(xs, contains('${t('provenanceStandardTitleOnly', lang)}. ${t('provenanceDraft', lang)}'));
        expect(xs.any((x) => x.contains(t('provenanceAi', lang))), isFalse);
        await env.close(tester);
      });
    }

    testWidgets('an ordinary entry still shows the AI-guidance label (nothing else moved)',
        (tester) async {
      final env = await screens.setUp(tester, sim: EngineSim(mode03: '7E8 04 43 01 01 20'));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains('${t('provenanceAi')}. ${t('provenanceDraft')}'));
      expect(xs.any((x) => x.contains(t('provenanceStandardTitleOnly'))), isFalse);
      await env.close(tester);
    });
  });
}
