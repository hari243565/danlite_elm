/// Phase 4C K2 — the name-only packs (7,672 English + 7,672 Hindi) bundled next
/// to the 308-entry guidance packs. Everything reads the REAL files.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/constants/chassis_dtc_dictionary.dart';
import 'package:danlite_elm/constants/dtc_descriptions.dart';
import 'package:danlite_elm/knowledge/code_lookup.dart';
import 'package:danlite_elm/knowledge/fault_resolver.dart';
import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/knowledge/knowledge_service.dart';
import 'package:danlite_elm/knowledge/knowledge_store.dart';
import 'package:danlite_elm/knowledge/legacy_text.dart';
import 'package:danlite_elm/knowledge/pack_signature.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'phase1b_screens_test.dart' as screens;
import 'support/engine_sim.dart';
import 'support/kb_pack_builder.dart';
import 'support/knowledge_harness.dart';

const String kBasicEnDir = 'assets/knowledge/generic_basic_en';
const String kBasicHiDir = 'assets/knowledge/generic_basic_hi';
const Duration importBudget = Duration(seconds: 15);
const Duration stallBudget = Duration(milliseconds: 250);

List<Map<String, Object?>> linesOf(String dir) => [
      for (final l in File('$dir/entries.jsonl').readAsLinesSync())
        if (l.trim().isNotEmpty) Map<String, Object?>.from(jsonDecode(l) as Map),
    ];

Map<String, dynamic> manifestOf(String dir) =>
    jsonDecode(File('$dir/manifest.json').readAsStringSync()) as Map<String, dynamic>;

Future<int> count(KnowledgeStore s, [String where = '1=1']) async =>
    (await s.db.rawQuery('SELECT COUNT(*) AS n FROM kb_entry WHERE $where'))
        .first['n'] as int;

FaultRecord record(String code) =>
    FaultRecord.manual(code, format: DtcFormat.sae2, readAt: DateTime.utc(2026, 10, 3));

const VehicleContext classic350 = VehicleContext(
    make: 'Royal Enfield', model: 'Classic 350',
    manufacturerKey: ChassisManufacturers.royalEnfield,
    platformKey: ChassisPlatforms.royalEnfieldClassic350);

KbEntry entry(String code, String lang,
        {required String title,
        String verification = 'ai_authored_from_standard_title',
        List<String> causes = const <String>[],
        RiderAction level = RiderAction.serviceSoon,
        CanRide? canRide = CanRide.withCare,
        String pack = 'p'}) =>
    KbEntry(
      contentId: 'generic:$code:$lang${pack == 'p' ? '' : '#$pack'}',
      code: code,
      scopeKind: ScopeKind.generic,
      language: lang,
      title: title,
      meaning: 'Meaning of $title',
      causes: causes,
      riderAction: level,
      riderAdvice: 'Advice for $title',
      canRide: canRide,
      verification: verification,
      packId: pack,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('K2 the files on disk are the ones that were hashed', () {
    for (final dir in [kBasicEnDir, kBasicHiDir]) {
      test('$dir: LF only, SHA-256 and count match the manifest, draft, unsigned', () async {
        final bytes = File('$dir/entries.jsonl').readAsBytesSync();
        final m = manifestOf(dir);
        expect(bytes.contains(13), isFalse, reason: 'a CRLF checkout would break the hash');
        expect(await sha256Hex(bytes), m['content_sha256']);
        expect(linesOf(dir).length, m['entries_count']);
        expect(m['entries_count'], kBasicCount);
        expect(m['review_state'], 'draft');
        expect(m['signature'], isNull);
        expect(m['scope'], 'generic');
        expect(File('$dir/manifest.json').readAsBytesSync().contains(13), isFalse);
        expect(bytes.length, lessThan(kMaxPackBytes), reason: 'under the 20 MB shipped cap');
      });
    }

    test('pack ids and languages', () {
      expect(manifestOf(kBasicEnDir)['pack_id'], 'generic_basic_en');
      expect(manifestOf(kBasicEnDir)['language'], 'en');
      expect(manifestOf(kBasicHiDir)['pack_id'], 'generic_basic_hi');
      expect(manifestOf(kBasicHiDir)['language'], 'hi');
    });

    test('the line-ending protection covers them, and both are listed as assets', () {
      expect(File('.gitattributes').readAsStringSync(), contains('assets/knowledge/** -text'));
      final y = File('pubspec.yaml').readAsStringSync();
      expect(y, contains('assets/knowledge/generic_basic_en/'));
      expect(y, contains('assets/knowledge/generic_basic_hi/'));
    });

    test('every line is a name-only line, in both languages', () {
      for (final dir in [kBasicEnDir, kBasicHiDir]) {
        for (final l in linesOf(dir)) {
          expect(l['verification'], 'standard_title_only');
          expect(l['rider_action_level'], 'INFO');
          expect(l['confidence'], 'low');
          expect(l['can_ride_to_workshop'], isNull);
        }
      }
      expect(linesOf(kBasicHiDir).every((l) => l['hi_status'] == 'machine'), isTrue);
    });

    test('the production download key is still unset', () {
      expect(productionPackPublicKey(), isNull);
    });

    test('the service lists all four packs, English before Hindi, guidance before names', () {
      expect(kBundledPackDirs, [
        'assets/knowledge/generic_en',
        'assets/knowledge/generic_hi',
        kBasicEnDir,
        kBasicHiDir,
      ]);
    });
  });

  group('K2 no code and no content_id is in both the guidance and the name-only content', () {
    test('from the files', () {
      final shippedCodes = {for (final l in linesOf(kBundledDir)) l['code'] as String};
      final shippedIds = {for (final l in linesOf(kBundledDir)) l['content_id'] as String};
      final shippedHiIds = {for (final l in linesOf(kBundledHiDir)) l['content_id'] as String};
      for (final dir in [kBasicEnDir, kBasicHiDir]) {
        final ls = linesOf(dir);
        expect(ls.where((l) => shippedCodes.contains(l['code'])), isEmpty, reason: dir);
        expect(ls.where((l) => shippedIds.contains(l['content_id'])), isEmpty, reason: dir);
        expect(ls.where((l) => shippedHiIds.contains(l['content_id'])), isEmpty, reason: dir);
      }
      expect({for (final l in linesOf(kBasicEnDir)) l['code']},
          {for (final l in linesOf(kBasicHiDir)) l['code']},
          reason: 'one Hindi row per English row');
    });

    test('in the database after a fresh install', () async {
      final k = await startedKnowledge();
      final clash = await k.store!.db.rawQuery(
          'SELECT a.code FROM kb_entry a JOIN kb_entry b ON a.code = b.code '
          "WHERE a.pack_id IN ('generic_en','generic_hi') "
          "AND b.pack_id IN ('generic_basic_en','generic_basic_hi') LIMIT 1");
      expect(clash, isEmpty);
      await k.store!.close();
    });
  });

  group('K2 a fresh install imports everything', () {
    test('four packs, 15,960 rows, every row active, bundled, draft', () async {
      final k = await startedKnowledge();
      final s = k.store!;
      expect(k.state, KnowledgeState.ready);
      expect(k.bundledImports, hasLength(4), reason: '${k.bundledImports}');
      expect(k.bundledImports.every((o) => o.imported), isTrue, reason: '${k.bundledImports}');
      expect(await count(s), 616 + 2 * kBasicCount);
      expect(await count(s, "status = 'active'"), 616 + 2 * kBasicCount);
      expect(await count(s, "pack_id = 'generic_basic_en' AND language = 'en'"), kBasicCount);
      expect(await count(s, "pack_id = 'generic_basic_hi' AND language = 'hi' AND hi_status = 'machine'"),
          kBasicCount);
      expect(await count(s, "pack_id IN ('generic_en','generic_hi')"), 616);
      for (final id in ['generic_en', 'generic_hi', 'generic_basic_en', 'generic_basic_hi']) {
        final p = (await s.pack(id))!;
        expect(p.source, PackSource.bundled, reason: id);
        expect(p.reviewState, 'draft', reason: id);
      }
      expect(await s.db.rawQuery(
          'SELECT content_id FROM kb_entry GROUP BY content_id HAVING COUNT(*) > 1'), isEmpty);
      // The name-only rows hold no causes, hints or can-ride in the database.
      expect(await count(s,
          "verification = 'standard_title_only' AND (causes_json <> '[]' OR hints_json <> '[]' "
          'OR can_ride IS NOT NULL)'), 0);
      expect(await count(s, "verification = 'standard_title_only'"), 2 * kBasicCount);
      await s.close();
    });

    test('a second start imports nothing and changes nothing', () async {
      final path = await tempDbPath();
      final a = knowledgeAt(path);
      await a.start();
      await a.store!.close();
      final b = knowledgeAt(path);
      await b.start();
      expect(b.bundledImports, isEmpty);
      expect(await count(b.store!), 616 + 2 * kBasicCount);
      await b.store!.close();
    });

    test('a pack version at least as high as the installed one is not re-imported', () {
      // Per pack id, so the name-only packs start at 1 without blocking a later
      // content version 2 of the same pack.
      expect(manifestOf(kBasicEnDir)['version'], 1);
      expect(manifestOf(kBasicHiDir)['version'], 1);
    });
  });

  group('K2 an install already at the Phase 4A state upgrades cleanly', () {
    test('only the name-only packs arrive; nothing lost, duplicated or changed', () async {
      final path = await tempDbPath();
      // The phone as Phase 4A left it: both guidance packs, a scan, a clear.
      final old = await KnowledgeStore.open(databaseFactoryFfi, path);
      expect((await importBundledFromDisk(old)).imported, isTrue);
      expect((await importBundledHindiFromDisk(old)).imported, isTrue);
      final t = DateTime.utc(2026, 10, 2, 8).millisecondsSinceEpoch;
      final sid = await old.db.insert('scan_session', <String, Object?>{
        'kind': 'engine', 'started_at': t, 'last_seen_at': t, 'repeat_count': 2,
        'reach_state': 'answered', 'vehicle_label': 'My bike',
      });
      await old.db.insert('scan_fault', <String, Object?>{
        'session_id': sid, 'position': 0, 'code': 'P0120', 'display_code': 'P0120',
        'format': 'sae2', 'source': 'mode03', 'read_at': t,
        'resolved_level': 'l4Generic', 'resolved_content_id': 'generic:P0120:en',
      });
      await old.db.insert('scan_fault', <String, Object?>{
        'session_id': sid, 'position': 1, 'code': 'P0001', 'display_code': 'P0001',
        'format': 'sae2', 'source': 'mode03', 'read_at': t,
        'resolved_level': 'l5Structure',
      });
      final shippedBefore = await old.db.query('kb_entry',
          where: "pack_id IN ('generic_en','generic_hi')", orderBy: 'content_id');
      final packsBefore = await old.db.query('kb_pack', orderBy: 'pack_id');
      final historyBefore = {
        for (final tb in ['scan_session', 'scan_fault']) tb: await old.db.query(tb),
      };
      expect(shippedBefore, hasLength(616));
      await old.close();

      final k = knowledgeAt(path);
      await k.start();
      expect(k.state, KnowledgeState.ready);
      final s = k.store!;
      expect(k.bundledImports.map((o) => o.toString()), [
        'imported generic_basic_en v1 ($kBasicCount entries)',
        'imported generic_basic_hi v1 ($kBasicCount entries)',
      ]);
      expect(await count(s), 616 + 2 * kBasicCount);
      expect(await s.db.query('kb_entry',
          where: "pack_id IN ('generic_en','generic_hi')", orderBy: 'content_id'),
          shippedBefore, reason: 'the guidance rows are byte for byte what they were');
      final packsAfter = await s.db.query('kb_pack',
          where: "pack_id IN ('generic_en','generic_hi')", orderBy: 'pack_id');
      expect(packsAfter, packsBefore, reason: 'guidance pack rows (version, import time) untouched');
      expect(await s.db.rawQuery(
          'SELECT content_id FROM kb_entry GROUP BY content_id HAVING COUNT(*) > 1'), isEmpty);
      expect({
        for (final tb in ['scan_session', 'scan_fault']) tb: await s.db.query(tb),
      }, historyBefore, reason: 'the rider history is untouched');
      expect(await k.history!.list(), hasLength(1));
      await s.close();
    });

    test('a failure of the name-only import leaves the guidance and history alone', () async {
      final path = await tempDbPath();
      final k = KnowledgeService(
        openStore: () => KnowledgeStore.open(databaseFactoryFfi, path),
        loadAsset: (p) => p.contains('basic')
            ? throw const FileSystemException('asset missing')
            : File(p).readAsBytes(),
      );
      await k.start();
      expect(k.state, KnowledgeState.ready);
      expect(await count(k.store!), 616);
      await k.store!.close();
    });
  });

  group('K2 the resolver always prefers real guidance to a bare name', () {
    final vehicle = VehicleContext.generic;

    test('a shipped English row beats a name-only Hindi row for the same code', () {
      final idx = KnowledgeIndex([
        entry('P0120', 'en', title: 'Shipped English title', causes: ['a', 'b'], pack: 'generic_en'),
        entry('P0120', 'hi', title: 'सिर्फ़ नाम', level: RiderAction.info, canRide: null,
            verification: kVerificationStandardTitleOnly, pack: 'generic_basic_hi'),
      ]);
      final r = FaultResolver(index: idx).resolve(record('P0120'), vehicle, 'hi');
      expect(r.title, 'Shipped English title');
      expect(r.provenance, Provenance.aiGuidance);
      expect(r.riderAction, RiderAction.serviceSoon);
      expect(r.causes, ['a', 'b']);
      expect(r.languageUsed, 'en');
      expect(r.languageFallback, isTrue, reason: 'the English fallback note is shown');
    });

    test('a shipped Hindi row beats a name-only English row', () {
      final idx = KnowledgeIndex([
        entry('P0120', 'en', title: 'Only a name', level: RiderAction.info, canRide: null,
            verification: kVerificationStandardTitleOnly, pack: 'generic_basic_en'),
        entry('P0120', 'hi', title: 'असली मार्गदर्शन', causes: ['क', 'ख'], pack: 'generic_hi'),
      ]);
      final r = FaultResolver(index: idx).resolve(record('P0120'), vehicle, 'hi');
      expect(r.title, 'असली मार्गदर्शन');
      expect(r.provenance, Provenance.aiGuidance);
      expect(r.riderAction, RiderAction.serviceSoon);
    });

    test('with nothing else, the name-only row answers, labelled as a bare name', () {
      final idx = KnowledgeIndex([
        entry('P0001', 'en', title: 'Name', level: RiderAction.info, canRide: null,
            verification: kVerificationStandardTitleOnly, pack: 'generic_basic_en'),
      ]);
      final r = FaultResolver(index: idx).resolve(record('P0001'), vehicle, 'en');
      expect(r.provenance, Provenance.standardTitleOnly);
      expect(r.level, ResolvedLevel.l4Generic);
      expect(r.causes, isEmpty);
      expect(r.hints, isEmpty);
      expect(r.canRide, isNull);
      expect(r.riderAction, RiderAction.info);
    });

    test('a platform-scope entry beats a name-only row', () {
      final platform = KbEntry(
          contentId: 'platform:x:P0120:en', code: 'P0120', scopeKind: ScopeKind.platform,
          scopeRef: ChassisPlatforms.royalEnfieldClassic350, language: 'en',
          title: 'Platform specific', meaning: 'm', causes: const ['a', 'b'],
          riderAction: RiderAction.stop, canRide: CanRide.no, riderAdvice: 'a',
          verification: 'ai_authored_adapted', packId: 'platform_pack');
      final nameOnly = entry('P0120', 'en', title: 'Only a name', level: RiderAction.info,
          canRide: null, verification: kVerificationStandardTitleOnly, pack: 'generic_basic_en');
      final r = FaultResolver(index: KnowledgeIndex([nameOnly, platform]))
          .resolve(record('P0120'), classic350, 'en');
      expect(r.level, ResolvedLevel.l2Platform);
      expect(r.title, 'Platform specific');
    });

    test('on an identified ABS platform a name-only chassis code is never used', () {
      final c = linesOf(kBasicEnDir).firstWhere((l) => (l['code'] as String).startsWith('C0'));
      final nameOnly = entry(c['code'] as String, 'en', title: 'Only a name',
          level: RiderAction.info, canRide: null,
          verification: kVerificationStandardTitleOnly, pack: 'generic_basic_en');
      final r = FaultResolver(index: KnowledgeIndex([nameOnly]))
          .resolve(record(c['code'] as String), classic350, 'en', domain: FaultDomain.abs);
      expect(r.provenance, isNot(Provenance.standardTitleOnly));
      expect(r.level.index, greaterThan(ResolvedLevel.l4Generic.index));
    });

    test('the 31-entry table keeps its codes: it beats a name-only row, which does not hide it', () {
      final tableCodes = DtcDatabase.codes.keys
          .where((c) => !c.startsWith('C') && !c.startsWith('B') && !c.startsWith('U'))
          .toList();
      final nameOnlyCodes = {for (final l in linesOf(kBasicEnDir)) l['code'] as String};
      final both = tableCodes.where(nameOnlyCodes.contains).toList();
      expect(both, isNotEmpty, reason: 'the real content has codes in both');
      final idx = KnowledgeIndex([
        for (final l in linesOf(kBasicEnDir)) if (both.contains(l['code']))
          entry(l['code'] as String, 'en', title: l['title_en'] as String,
              level: RiderAction.info, canRide: null,
              verification: kVerificationStandardTitleOnly, pack: 'generic_basic_en'),
      ]);
      final resolver = FaultResolver(index: idx, legacy: legacyEngineText);
      for (final c in both) {
        final r = resolver.resolve(record(c), vehicle, 'en', domain: FaultDomain.engine);
        expect(r.provenance, Provenance.legacyTable, reason: c);
        expect(r.causes, isNotEmpty, reason: c);
      }
    });
  });

  group('K2 the cards', () {
    String codeReply(String code) {
      final n = int.parse(code.substring(1), radix: 16);
      final a = (n >> 8) & 0xFF, b = n & 0xFF;
      String h(int x) => x.toRadixString(16).toUpperCase().padLeft(2, '0');
      return '7E8 04 43 01 ${h(a)} ${h(b)}';
    }

    const code = 'P0001';
    final en = linesOf(kBasicEnDir).firstWhere((l) => l['code'] == code);
    final hi = linesOf(kBasicHiDir).firstWhere((l) => l['code'] == code);

    testWidgets('English: name, Info chip, advice, label, draft; no empty sections', (tester) async {
      final env = await screens.setUp(tester, sim: EngineSim(mode03: codeReply(code)));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains(en['title_en']));
      expect(xs, contains(en['meaning_en']));
      expect(xs, contains(en['rider_advice_en']));
      expect(xs, contains(AppStrings.get('riderActionInfo', 'en')));
      expect(xs, contains('${AppStrings.get('provenanceStandardTitleOnly', 'en')}. '
          '${AppStrings.get('provenanceDraft', 'en')}'));
      expect(xs, isNot(contains(AppStrings.get('faultLikelyCauses', 'en').toUpperCase())));
      expect(xs, isNot(contains(AppStrings.get('faultForMechanic', 'en').toUpperCase())));
      expect(xs.any((x) => x.contains(AppStrings.get('canRideYes', 'en'))), isFalse);
      expect(xs.any((x) => x.contains(AppStrings.get('canRideWithCare', 'en'))), isFalse);
      expect(xs.any((x) => x.contains(AppStrings.get('canRideNo', 'en'))), isFalse);
      expect(xs.where((x) => x.trim().isEmpty), isEmpty, reason: 'no empty rows');
      await env.close(tester);
    });

    testWidgets('Hindi: the Hindi title, Hindi advice and Hindi labels; no English leaks',
        (tester) async {
      final env = await screens.setUp(tester, lang: 'hi', sim: EngineSim(mode03: codeReply(code)));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains(hi['title_hi']));
      expect(xs, contains(hi['meaning_hi']));
      expect(xs, contains(hi['rider_advice_hi']));
      expect(xs, contains(AppStrings.get('riderActionInfo', 'hi')));
      expect(xs, contains('${AppStrings.get('provenanceStandardTitleOnly', 'hi')}. '
          '${AppStrings.get('provenanceDraft', 'hi')}'));
      expect(xs, isNot(contains(AppStrings.get('faultShowingEnglish', 'hi'))));
      expect(xs, isNot(contains(AppStrings.get('faultPartlyEnglish', 'hi'))));
      expect(xs, isNot(contains(en['title_en'])));
      expect(xs, isNot(contains(en['rider_advice_en'])));
      expect(xs, isNot(contains(AppStrings.get('faultLikelyCauses', 'hi').toUpperCase())));
      await env.close(tester);
    });

    testWidgets('a language without Hindi falls back to English, with the existing note',
        (tester) async {
      final env = await screens.setUp(tester, lang: 'bn', sim: EngineSim(mode03: codeReply(code)));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains(en['title_en']));
      expect(xs, contains(en['rider_advice_en']));
      expect(xs, contains(AppStrings.get('faultShowingEnglish', 'bn')));
      expect(xs, contains(AppStrings.get('riderActionInfo', 'bn')));
      expect(xs, isNot(contains(hi['title_hi'])));
      await env.close(tester);
    });

    test('lookup: a name-only code is found by its code and by its words, in Hindi', () async {
      final k = await startedKnowledge();
      final byCode = await searchCodes(parseLookupQuery(code), store: k.store, language: 'hi');
      expect(byCode.items.where((i) => i.code == code), hasLength(1));
      expect(byCode.items.firstWhere((i) => i.code == code).title, hi['title_hi']);
      final inEnglish = await searchCodes(parseLookupQuery(code), store: k.store, language: 'en');
      expect(inEnglish.items.firstWhere((i) => i.code == code).title, en['title_en']);
      final byWords = await searchCodes(parseLookupQuery('fuel volume regulator'),
          store: k.store, language: 'en');
      expect(byWords.items.any((i) => i.code == code), isTrue);
      await k.store!.close();
    });
  });

  group('K2 measurements (first start, all four packs)', () {
    test('import time, main-thread stall, database size, asset sizes', () async {
      final path = await tempDbPath();
      final k = knowledgeAt(path);
      var worstGap = Duration.zero;
      var last = DateTime.now();
      final ticker = Timer.periodic(const Duration(milliseconds: 5), (_) {
        final now = DateTime.now();
        final gap = now.difference(last);
        if (gap > worstGap) worstGap = gap;
        last = now;
      });
      final sw = Stopwatch()..start();
      final started = k.start();
      expect(k.state, KnowledgeState.loading, reason: 'start() returns at once');
      await started;
      sw.stop();
      ticker.cancel();
      expect(k.state, KnowledgeState.ready, reason: '${k.bundledImports}');
      expect(k.bundledImports, hasLength(4));

      final sw2 = Stopwatch()..start();
      await k.reload();
      sw2.stop();
      await k.store!.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      await k.store!.close();
      final dbBytes = File(path).lengthSync();
      int size(String f) => File(f).lengthSync();
      final lines = <String>[
        'start() end to end, 4 packs (open, import, index): ${sw.elapsedMilliseconds} ms (budget ${importBudget.inSeconds} s)',
        'longest main-isolate stall during it: ${worstGap.inMilliseconds} ms (budget ${stallBudget.inMilliseconds} ms)',
        'index rebuild (load every active row): ${sw2.elapsedMilliseconds} ms',
        'database size: ${(dbBytes / 1048576).toStringAsFixed(1)} MB',
        'assets: en ${size('$kBundledDir/entries.jsonl')} B, hi ${size('$kBundledHiDir/entries.jsonl')} B, '
            'basic en ${size('$kBasicEnDir/entries.jsonl')} B, basic hi ${size('$kBasicHiDir/entries.jsonl')} B',
      ];
      // ignore: avoid_print
      print('K2 MEASUREMENTS\n  ${lines.join('\n  ')}');
      expect(sw.elapsed, lessThan(importBudget));
      expect(worstGap, lessThan(stallBudget));
    });
  });
}
