/// Phase 4A H1 — the shipped content: 308 English entries and 308 Hindi rows,
/// bundled, imported on a fresh install, upgraded cleanly from the old
/// 140-entry pack, shown in Hindi on the fault card, and never mislabelled.
///
/// Everything here reads the REAL files under assets/knowledge/.
library;

import 'dart:convert';
import 'dart:io';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/knowledge/code_lookup.dart';
import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/knowledge/knowledge_service.dart';
import 'package:danlite_elm/knowledge/knowledge_store.dart';
import 'package:danlite_elm/knowledge/pack_signature.dart';
import 'package:danlite_elm/widgets/resolved_fault_view.dart' show kAppliesNoteKeys;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'phase1b_screens_test.dart' as screens;
import 'support/engine_sim.dart';
import 'support/kb_pack_builder.dart';
import 'support/knowledge_harness.dart';

const String kOldPackDir = 'test/fixtures/knowledge_v1_140';

Future<int> count(KnowledgeStore s, [String where = '1=1']) async =>
    (await s.db.rawQuery('SELECT COUNT(*) AS n FROM kb_entry WHERE $where'))
        .first['n'] as int;

List<Map<String, Object?>> linesOf(String dir) => [
      for (final l in File('$dir/entries.jsonl').readAsLinesSync())
        if (l.trim().isNotEmpty) Map<String, Object?>.from(jsonDecode(l) as Map),
    ];

Map<String, dynamic> manifestOf(String dir) =>
    jsonDecode(File('$dir/manifest.json').readAsStringSync()) as Map<String, dynamic>;

/// A STOP entry that has its own Hindi row, as a Mode 03 reply.
const String stopCode = 'P0336';
const String stopReply = '7E8 04 43 01 03 36';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('H1 the files on disk are the ones that were hashed', () {
    for (final dir in [kBundledDir, kBundledHiDir]) {
      test('$dir: LF only, SHA-256 and count match the manifest, draft, unsigned', () async {
        final bytes = File('$dir/entries.jsonl').readAsBytesSync();
        final m = manifestOf(dir);
        expect(bytes.contains(13), isFalse, reason: 'a CRLF checkout would break the hash');
        expect(await sha256Hex(bytes), m['content_sha256']);
        expect(linesOf(dir).length, m['entries_count']);
        expect(m['review_state'], 'draft');
        expect(m['signature'], isNull);
        expect(File('$dir/manifest.json').readAsBytesSync().contains(13), isFalse);
      });
    }

    test('the line-ending protection covers both packs and the old-pack fixture', () {
      final ga = File('.gitattributes').readAsStringSync();
      expect(ga, contains('assets/knowledge/** -text'));
      expect(ga, contains('test/fixtures/knowledge_v1_140/** -text'));
    });

    test('both packs are listed as app assets', () {
      final y = File('pubspec.yaml').readAsStringSync();
      expect(y, contains('assets/knowledge/generic_en/'));
      expect(y, contains('assets/knowledge/generic_hi/'));
    });

    test('the sizes are what the content branch shipped (308 and 308)', () {
      expect(manifestOf(kBundledDir)['entries_count'], kBundledEnCount);
      expect(manifestOf(kBundledHiDir)['entries_count'], kBundledHiCount);
      expect(manifestOf(kBundledDir)['version'], kBundledEnVersion);
      expect(manifestOf(kBundledHiDir)['version'], kBundledHiVersion);
    });

    test('rollback protection: the English pack is newer than the 140-entry one', () {
      final old = manifestOf(kOldPackDir);
      expect(old['entries_count'], 140);
      expect(manifestOf(kBundledDir)['version'] as int, greaterThan(old['version'] as int));
    });

    test('every English entry has exactly one Hindi row, and nothing else', () {
      final en = {for (final l in linesOf(kBundledDir)) l['content_id'] as String};
      final hi = {
        for (final l in linesOf(kBundledHiDir))
          (l['content_id'] as String).replaceFirst(RegExp(r':hi$'), ':en')
      };
      expect(hi, en);
    });

    test('the production download key is still unset', () {
      expect(productionPackPublicKey(), isNull);
    });

    test('a condition the screen has no sentence for would be dropped: none is', () {
      // Every applies_when key a shipped pack uses needs a note, in English and
      // Hindi, or the rider is shown guidance with its condition missing.
      final keys = <String>{
        for (final l in linesOf(kBundledDir))
          ...((l['applies_when'] as Map?)?.keys.cast<String>() ?? const <String>[]),
      };
      expect(keys, isNotEmpty);
      for (final k in keys) {
        final noteKey = kAppliesNoteKeys[k];
        expect(noteKey, isNotNull, reason: 'applies_when "$k" has no rider note');
        final en = AppStrings.get(noteKey!, 'en');
        final hi = AppStrings.get(noteKey, 'hi');
        expect(en, isNot(noteKey), reason: '$noteKey missing in English');
        expect(hi, isNot(noteKey), reason: '$noteKey missing in Hindi');
        expect(hi, isNot(en), reason: '$noteKey has no Hindi');
        expect(hi, contains('लागू'), reason: noteKey);
      }
    });
  });

  group('H1 (a) a fresh install imports both packs', () {
    test('308 English + 308 Hindi rows, active, as bundled drafts', () async {
      final k = await startedKnowledge();
      final s = k.store!;
      expect(k.state, KnowledgeState.ready);
      expect(k.bundledImports.every((o) => o.imported), isTrue, reason: '${k.bundledImports}');
      expect(await count(s), 616);
      expect(await count(s, "language = 'en' AND status = 'active'"), 308);
      expect(await count(s, "language = 'hi' AND status = 'active'"), 308);
      for (final id in ['generic_en', 'generic_hi']) {
        final p = (await s.pack(id))!;
        expect(p.source, PackSource.bundled);
        expect(p.reviewState, 'draft');
        expect(p.entriesCount, 308);
      }
      expect((await s.pack('generic_en'))!.version, kBundledEnVersion);
      expect((await s.pack('generic_hi'))!.version, kBundledHiVersion);
      // The resolver's index is built from both.
      final dupIds = await s.db.rawQuery(
          'SELECT content_id FROM kb_entry GROUP BY content_id HAVING COUNT(*) > 1');
      expect(dupIds, isEmpty);
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
      expect(await count(b.store!), 616);
      await b.store!.close();
    });
  });

  group('H1 (b) an install that has the old 140-entry pack upgrades cleanly', () {
    test('no duplicate or lost rows, the history untouched', () async {
      final path = await tempDbPath();
      // 1. The phone as an earlier build left it: the old pack + a scan record.
      final old = await KnowledgeStore.open(databaseFactoryFfi, path);
      final oldImport = await old.importPack(
          manifestBytes: File('$kOldPackDir/manifest.json').readAsBytesSync(),
          entriesBytes: File('$kOldPackDir/entries.jsonl').readAsBytesSync(),
          source: PackSource.bundled,
          appVersion: '1.0.0');
      expect(oldImport.imported, isTrue, reason: '$oldImport');
      expect(await count(old), 140);
      final t = DateTime.utc(2026, 9, 30, 8).millisecondsSinceEpoch;
      final sid = await old.db.insert('scan_session', <String, Object?>{
        'kind': 'engine', 'started_at': t, 'last_seen_at': t, 'repeat_count': 3,
        'reach_state': 'answered', 'vehicle_label': 'My bike',
      });
      await old.db.insert('scan_fault', <String, Object?>{
        'session_id': sid, 'position': 0, 'code': 'P0120', 'display_code': 'P0120',
        'format': 'sae2', 'source': 'mode03', 'read_at': t,
        'resolved_level': 'l4Generic', 'resolved_content_id': 'generic:P0120:en',
      });
      await old.db.insert('scan_fault', <String, Object?>{
        'session_id': sid, 'position': 1, 'code': 'C0035', 'display_code': 'C0035',
        'format': 'sae2', 'source': 'mode03', 'read_at': t,
        'resolved_level': 'l4Generic', 'resolved_content_id': 'generic:C0035:en',
      });
      final before = {
        for (final tb in ['scan_session', 'scan_fault']) tb: await old.db.query(tb),
      };
      await old.close();

      // 2. The new build starts on that file.
      final k = knowledgeAt(path);
      await k.start();
      expect(k.state, KnowledgeState.ready);
      final s = k.store!;
      expect(k.bundledImports.map((o) => o.toString()), [
        'imported generic_en v$kBundledEnVersion (308 entries)',
        'imported generic_hi v$kBundledHiVersion (308 entries)',
      ]);
      expect(await count(s), 616);
      expect(await count(s, "pack_id = 'generic_en'"), 308, reason: 'old rows replaced, not added');
      expect(await count(s, "language = 'en'"), 308);
      expect(await count(s, "language = 'hi'"), 308);
      expect(await s.db.rawQuery(
          'SELECT content_id FROM kb_entry GROUP BY content_id HAVING COUNT(*) > 1'), isEmpty);

      // 3. Nothing the old pack carried was lost, except the one entry the
      //    content owner held out on purpose (C0035).
      final oldIds = {for (final l in linesOf(kOldPackDir)) l['content_id'] as String};
      final nowIds = {
        for (final r in await s.db.query('kb_entry', columns: ['content_id'])) r['content_id'] as String
      };
      expect(oldIds.difference(nowIds), {'generic:C0035:en'});
      expect(await s.pack('generic_en').then((p) => p!.version), kBundledEnVersion);

      // 4. The rider's history is byte for byte what it was.
      final after = {
        for (final tb in ['scan_session', 'scan_fault']) tb: await s.db.query(tb),
      };
      expect(after, before);
      expect(await k.history!.list(), hasLength(1));
      await s.close();
    });

    test('upgrading twice in a row is a no-op the second time', () async {
      final path = await tempDbPath();
      final old = await KnowledgeStore.open(databaseFactoryFfi, path);
      await old.importPack(
          manifestBytes: File('$kOldPackDir/manifest.json').readAsBytesSync(),
          entriesBytes: File('$kOldPackDir/entries.jsonl').readAsBytesSync(),
          source: PackSource.bundled,
          appVersion: '1.0.0');
      await old.close();
      for (final expectImports in [2, 0]) {
        final k = knowledgeAt(path);
        await k.start();
        expect(k.bundledImports, hasLength(expectImports));
        expect(await count(k.store!), 616);
        await k.store!.close();
      }
    });

    test('one pack failing to load does not stop the other', () async {
      final path = await tempDbPath();
      final k = KnowledgeService(
        openStore: () => KnowledgeStore.open(databaseFactoryFfi, path),
        loadAsset: (p) => p.contains('generic_en')
            ? throw const FileSystemException('asset missing')
            : File(p).readAsBytes(),
      );
      await k.start();
      expect(k.state, KnowledgeState.ready);
      expect(await count(k.store!, "language = 'hi'"), 308);
      expect(await count(k.store!, "language = 'en'"), 0);
      await k.store!.close();
    });
  });

  group('H1 (d) the Hindi rows', () {
    test('every imported Hindi row is machine-status, none reviewed or unmarked', () async {
      final k = await startedKnowledge();
      final rows = await k.store!.db.query('kb_entry', where: "language = 'hi'");
      expect(rows, hasLength(308));
      expect(rows.every((r) => r['hi_status'] == 'machine'), isTrue);
      expect(rows.every((r) => r['needs_independent_review'] == 1), isTrue,
          reason: 'machine Hindi is always flagged for a person to read');
      await k.store!.close();
    });

    test('the importer rejects any other hi_status name', () async {
      final (store, _) = await openTempStore();
      final base = linesOf(kBundledHiDir).first;
      for (final bad in ['human', 'none', 'MACHINE', '', 7]) {
        final line = Map<String, Object?>.from(base)..['hi_status'] = bad;
        final p = await buildPack(packId: 'generic_hi', language: 'hi', lines: [line]);
        final r = await store.importPack(
            manifestBytes: p.manifestBytes, entriesBytes: p.entriesBytes,
            source: PackSource.bundled, appVersion: '1.0.0');
        expect(r.refusal, ImportRefusal.entriesInvalid, reason: 'hi_status=$bad');
      }
      await store.close();
    });
  });

  group('H1 (c) the fault card in Hindi', () {
    testWidgets('a Stop entry: Hindi title, advice, Stop chip, can-ride line, draft line',
        (tester) async {
      final hi = linesOf(kBundledHiDir).firstWhere((l) => l['code'] == stopCode);
      final en = linesOf(kBundledDir).firstWhere((l) => l['code'] == stopCode);
      expect(en['rider_action_level'], 'STOP');
      final env = await screens.setUp(tester, lang: 'hi', sim: EngineSim(mode03: stopReply));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains(hi['title_hi']));
      expect(xs, contains(hi['meaning_hi']));
      expect(xs, contains(hi['rider_advice_hi']));
      expect(xs, contains('• ${(hi['likely_causes_hi'] as List).first}'));
      expect(xs, contains(AppStrings.get('riderActionStop', 'hi')));
      expect(xs.any((x) => x.contains(AppStrings.get('canRideNo', 'hi'))), isTrue);
      expect(xs, contains(
          '${AppStrings.get('provenanceAi', 'hi')}. ${AppStrings.get('provenanceDraft', 'hi')}'));
      // Hindi all the way: nothing falls back to English, and the English text
      // is not on the screen.
      expect(xs, isNot(contains(AppStrings.get('faultShowingEnglish', 'hi'))));
      expect(xs, isNot(contains(AppStrings.get('faultPartlyEnglish', 'hi'))));
      expect(xs, isNot(contains(en['title_en'])));
      expect(xs, isNot(contains(en['rider_advice_en'])));
      await env.close(tester);
    });

    testWidgets('a language with no Hindi-style pack falls back to English, with the note',
        (tester) async {
      final en = linesOf(kBundledDir).firstWhere((l) => l['code'] == stopCode);
      // Bengali: the store has no 'bn' rows at all.
      final env = await screens.setUp(tester, lang: 'bn', sim: EngineSim(mode03: stopReply));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains(en['title_en']));
      expect(xs, contains(en['rider_advice_en']));
      expect(xs, contains(AppStrings.get('faultShowingEnglish', 'bn')));
      expect(xs, contains(AppStrings.get('riderActionStop', 'bn')));
      await env.close(tester);
    });

    testWidgets('English still shows the same entry in English (no Hindi leaks in)',
        (tester) async {
      final hi = linesOf(kBundledHiDir).firstWhere((l) => l['code'] == stopCode);
      final en = linesOf(kBundledDir).firstWhere((l) => l['code'] == stopCode);
      final env = await screens.setUp(tester, sim: EngineSim(mode03: stopReply));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains(en['title_en']));
      expect(xs, isNot(contains(hi['title_hi'])));
      await env.close(tester);
    });
  });

  group('H1 (e) the resolver labels survive the bigger content', () {
    testWidgets('English card: the AI-guidance label and the draft line', (tester) async {
      final env = await screens.setUp(tester, sim: EngineSim(mode03: stopReply));
      final xs = await screens.showDtc(tester, env);
      expect(xs, contains('${AppStrings.get('provenanceAi', 'en')}. '
          '${AppStrings.get('provenanceDraft', 'en')}'));
      expect(AppStrings.get('provenanceDraft', 'en'), 'Draft: not yet independently reviewed.');
      await env.close(tester);
    });
  });

  group('H1 lookup with two languages in the store', () {
    test('a prefix search still fills a full page of distinct codes, and says it is capped',
        () async {
      final k = await startedKnowledge();
      for (final lang in ['en', 'hi']) {
        final r = await searchCodes(parseLookupQuery('P0'), store: k.store, language: lang);
        expect(r.items.length, kLookupMaxResults, reason: lang);
        expect(r.capped, isTrue);
        expect(r.items.map((i) => i.key).toSet().length, r.items.length,
            reason: 'one line per code, not one per language');
      }
      await k.store!.close();
    });

    test('a code is listed once, in the asked language', () async {
      final k = await startedKnowledge();
      final hi = linesOf(kBundledHiDir).firstWhere((l) => l['code'] == 'P0120');
      final inHindi = await searchCodes(parseLookupQuery('P0120'), store: k.store, language: 'hi');
      expect(inHindi.items.where((i) => i.code == 'P0120'), hasLength(1));
      expect(inHindi.items.first.title, hi['title_hi']);
      final inEnglish = await searchCodes(parseLookupQuery('P0120'), store: k.store, language: 'en');
      expect(inEnglish.items.first.title, 'Throttle position sensor A: circuit fault');
      await k.store!.close();
    });
  });

  group('H1 a pack line with a value of the wrong type is refused, never a crash', () {
    test('numbers, lists and maps where text belongs', () async {
      final (store, _) = await openTempStore();
      final base = linesOf(kBundledDir).first;
      for (final field in ['rider_action_level', 'can_ride_to_workshop', 'verification']) {
        for (final bad in [7, <Object?>[], <String, Object?>{}, true]) {
          final line = Map<String, Object?>.from(base)..[field] = bad;
          final p = await buildPack(lines: [line]);
          final r = await store.importPack(
              manifestBytes: p.manifestBytes, entriesBytes: p.entriesBytes,
              source: PackSource.bundled, appVersion: '1.0.0');
          expect(r.refusal, ImportRefusal.entriesInvalid, reason: '$field=$bad');
        }
      }
      expect(await count(store), 0);
      await store.close();
    });
  });
}
