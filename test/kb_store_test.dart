/// Phase 1B — B2 the knowledge store, B3 packs / importer / verifier, B4 the
/// bundled baseline.
///
/// Real SQLite (the desktop build of the same engine, through
/// sqflite_common_ffi), real files on disk, real Ed25519 keys made in the test.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/knowledge/kb_schema.dart';
import 'package:danlite_elm/knowledge/knowledge_store.dart';
import 'package:danlite_elm/knowledge/pack_signature.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/kb_pack_builder.dart';

Future<int> count(KnowledgeStore s, [String where = '1=1']) async =>
    (await s.db.rawQuery('SELECT COUNT(*) AS n FROM kb_entry WHERE $where'))
        .first['n'] as int;

Future<String?> titleOf(KnowledgeStore s, String contentId) async {
  final r = await s.db.query('kb_entry',
      columns: ['title'], where: 'content_id = ?', whereArgs: [contentId]);
  return r.isEmpty ? null : r.first['title'] as String?;
}

Future<ImportOutcome> imp(KnowledgeStore s, BuiltPack p,
        {PackSource source = PackSource.bundled,
        List<int>? key,
        bool allowDebug = false,
        String app = '1.0.0',
        ImportHook? hook}) =>
    s.importPack(
        manifestBytes: p.manifestBytes,
        entriesBytes: p.entriesBytes,
        source: source,
        appVersion: app,
        publicKey: key,
        allowDebug: allowDebug,
        hook: hook);

void main() {
  late KnowledgeStore store;
  late String path;

  setUp(() async {
    (store, path) = await openTempStore();
  });
  tearDown(() async {
    await store.close();
  });

  group('B2 schema', () {
    test('creates every table and index and records schema version 1', () async {
      expect(await store.schemaVersion(), kKnowledgeSchemaVersion);
      final names = [
        for (final r in await store.db
            .rawQuery("SELECT name FROM sqlite_master WHERE type IN ('table','index')"))
          r['name'] as String
      ];
      expect(
          names,
          containsAll(<String>[
            'schema_version', 'kb_pack', 'kb_entry', 'kb_revoked',
            'scan_session', 'scan_fault', 'kb_entry_lookup', 'kb_entry_language',
          ]));
      final cols = [
        for (final r in await store.db.rawQuery('PRAGMA table_info(kb_entry)'))
          r['name'] as String
      ];
      expect(
          cols,
          containsAll(<String>[
            'content_id', 'code', 'scope_kind', 'scope_ref', 'language', 'title',
            'meaning', 'causes_json', 'rider_action_level', 'rider_action_basis',
            'rider_advice', 'hints_json', 'flags_json', 'can_ride',
            'can_ride_reason', 'applies_when_json', 'confidence', 'verification',
            'needs_independent_review', 'source_json', 'updated_at', 'pack_id',
            'status', 'hi_status',
          ]));
    });

    test('reopening keeps data and does not re-run the migration', () async {
      expect((await importBundledFromDisk(store)).imported, isTrue);
      await store.close();
      store = await KnowledgeStore.open(databaseFactoryFfi, path);
      expect(await count(store), 140);
      expect(await store.schemaVersion(), 1);
    });

    test('only SQL that Android 5 SQLite understands', () {
      // UPSERT 3.24, RETURNING 3.35, JSON1, FTS, window functions: none.
      final banned = RegExp(
          r'ON\s+CONFLICT[^;]*DO\s|\bRETURNING\b|\bjson_\w+\(|\bfts[345]\b|\bOVER\s*\(|GENERATED\s+ALWAYS|STRICT\b',
          caseSensitive: false);
      for (final f in Directory('lib/knowledge').listSync().whereType<File>()) {
        // Code only: the doc comments name the banned syntax on purpose.
        final src = f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(banned.firstMatch(src)?.group(0), isNull, reason: f.path);
      }
    });
  });

  group('B4 bundled baseline', () {
    test('the asset on disk is the hashed one: LF only, hash and count match', () async {
      final bytes = File('$kBundledDir/entries.jsonl').readAsBytesSync();
      final manifest = jsonDecode(File('$kBundledDir/manifest.json').readAsStringSync()) as Map;
      expect(bytes.contains(13), isFalse, reason: 'a CRLF checkout would break the hash');
      expect(await sha256Hex(bytes), manifest['content_sha256']);
      expect(seedLines().length, manifest['entries_count']);
      expect(manifest['review_state'], 'draft');
      expect(manifest['signature'], isNull);
      expect(File('.gitattributes').readAsStringSync(), contains('assets/knowledge/** -text'));
    });

    test('imports all 140 entries, active, as source bundled', () async {
      final r = await importBundledFromDisk(store);
      expect(r.imported, isTrue, reason: '$r');
      expect(r.count, 140);
      expect(await count(store, "status = 'active'"), 140);
      final info = await store.pack('generic_en');
      expect(info!.source, PackSource.bundled);
      expect(info.version, 1);
      expect(info.reviewState, 'draft');
      final e = (await store.activeEntries()).firstWhere((e) => e.code == 'P0120');
      expect(e.title, 'Throttle position sensor A: circuit fault');
      expect(e.riderAction, RiderAction.serviceSoon);
      expect(e.canRide, CanRide.withCare);
      expect(e.causes, hasLength(3));
      expect(e.verification, 'ai_authored_from_standard_title');
      expect(e.isDraft, isTrue);
      expect(e.hiStatus, HiStatus.none);
    });

    test('the bundled pack is not re-imported at the same version', () async {
      expect((await importBundledFromDisk(store)).imported, isTrue);
      final again = await importBundledFromDisk(store);
      expect(again.refusal, ImportRefusal.notNewer);
      expect(await count(store), 140);
    });

    test('a manifest claiming "bundled" does not change how it is treated', () async {
      // The bundled manifest says "source": "bundled"; sent as a download it is
      // unsigned, so it is refused.
      final r = await store.importPack(
          manifestBytes: File('$kBundledDir/manifest.json').readAsBytesSync(),
          entriesBytes: File('$kBundledDir/entries.jsonl').readAsBytesSync(),
          source: PackSource.downloaded,
          appVersion: '1.0.0');
      expect(r.imported, isFalse);
      expect(await count(store), 0);
    });
  });

  group('B3 versions', () {
    test('a newer version replaces the old one; dropped entries go', () async {
      final lines = seedLines();
      expect((await imp(store, await buildPack(lines: lines.take(10).toList()))).imported, isTrue);
      final changed = Map<String, Object?>.from(lines[0])
        ..['title_en'] = 'Updated title for the same code';
      final v2 = await buildPack(lines: [changed, ...lines.skip(1).take(4)], version: 2);
      final r = await imp(store, v2);
      expect(r.imported, isTrue, reason: '$r');
      expect(await count(store), 5);
      expect(await titleOf(store, lines[0]['content_id'] as String),
          'Updated title for the same code');
      expect((await store.pack('generic_en'))!.version, 2);
    });

    test('equal and lower versions are refused and change nothing', () async {
      final lines = seedLines().take(5).toList();
      expect((await imp(store, await buildPack(lines: lines, version: 3))).imported, isTrue);
      for (final v in [3, 2, 1]) {
        final r = await imp(store, await buildPack(lines: seedLines().take(2).toList(), version: v));
        expect(r.refusal, ImportRefusal.notNewer, reason: 'v$v');
      }
      expect(await count(store), 5);
    });

    test('an updated content file imports with no code change', () async {
      // The seed will be replaced by better versions: same schema, new text,
      // new codes, a different count.
      expect((await importBundledFromDisk(store)).imported, isTrue);
      final lines = seedLines();
      final next = [
        for (final l in lines.skip(3))
          Map<String, Object?>.from(l)..['updated_at'] = '2026-11-01',
      ];
      final r = await imp(store, await buildPack(lines: next, version: 2));
      expect(r.imported, isTrue, reason: '$r');
      expect(await count(store), 137);
    });
  });

  group('B3 a killed import leaves the previous data untouched', () {
    test('power cut half way: the crash image reopens with v1 intact', () async {
      expect((await importBundledFromDisk(store)).imported, isTrue);
      final crashDir = await Directory.systemTemp.createTemp('danlite_crash_');
      final crashPath = '${crashDir.path}${Platform.pathSeparator}kb.db';
      final v2lines = [
        for (final l in seedLines())
          Map<String, Object?>.from(l)..['title_en'] = 'HALF-WRITTEN ${l['code']}',
      ];
      final r = await imp(store, await buildPack(lines: v2lines, version: 2), hook: (phase) async {
        if (phase != 'half') return;
        // The exact bytes on disk at this instant: database file and its
        // rollback journal, as a sudden power loss would leave them.
        File(path).copySync(crashPath);
        for (final suffix in ['-journal', '-wal']) {
          final j = File('$path$suffix');
          if (j.existsSync()) j.copySync('$crashPath$suffix');
        }
        throw const FileSystemException('power cut');
      });
      expect(r.refusal, ImportRefusal.storageError);
      // The live database rolled back.
      expect(await count(store), 140);
      expect(await count(store, "title LIKE 'HALF-WRITTEN%'"), 0);
      expect((await store.pack('generic_en'))!.version, 1);
      // The crash image, opened fresh (SQLite replays the hot journal).
      final crashed = await KnowledgeStore.open(databaseFactoryFfi, crashPath);
      expect(await count(crashed), 140);
      expect(await count(crashed, "title LIKE 'HALF-WRITTEN%'"), 0);
      expect((await crashed.pack('generic_en'))!.version, 1);
      await crashed.close();
    });

    test('a failure just before commit rolls everything back', () async {
      expect((await imp(store, await buildPack(lines: seedLines().take(3).toList()))).imported, isTrue);
      final r = await imp(store, await buildPack(lines: seedLines(), version: 2),
          hook: (phase) async {
        if (phase == 'before-commit') throw StateError('killed');
      });
      expect(r.refusal, ImportRefusal.storageError);
      expect(await count(store), 3);
      expect((await store.pack('generic_en'))!.version, 1);
    });
  });

  group('B3 bad packs are refused and change nothing', () {
    setUp(() async {
      expect((await importBundledFromDisk(store)).imported, isTrue);
    });

    Future<void> refused(BuiltPack p, ImportRefusal want,
        {PackSource source = PackSource.bundled, List<int>? key}) async {
      final r = await imp(store, p, source: source, key: key);
      expect(r.refusal, want, reason: '$r');
      expect(await count(store), 140);
      expect((await store.pack('generic_en'))!.version, 1);
    }

    test('entries altered after the manifest was made', () async {
      final p = await buildPack(lines: seedLines(), version: 2);
      final bytes = [...p.entriesBytes]..[10] ^= 1;
      await refused(BuiltPack(p.manifestBytes, bytes, p.manifest), ImportRefusal.hashMismatch);
    });

    test('a line missing a required field', () async {
      final bad = Map<String, Object?>.from(seedLines().first)..remove('meaning_en');
      await refused(await buildPack(lines: [bad], version: 2), ImportRefusal.entriesInvalid);
    });

    test('an enum value out of range, and a D4 can-ride mismatch', () async {
      final a = Map<String, Object?>.from(seedLine('P0120'))..['rider_action_level'] = 'PANIC';
      await refused(await buildPack(lines: [a], version: 2), ImportRefusal.entriesInvalid);
      final b = Map<String, Object?>.from(seedLine('P0120'))..['can_ride_to_workshop'] = 'no';
      await refused(await buildPack(lines: [b], version: 2), ImportRefusal.entriesInvalid);
    });

    test('very long text is refused, not truncated onto the screen', () async {
      final l = Map<String, Object?>.from(seedLine('P0120'))..['meaning_en'] = '${'x' * 400}.';
      await refused(await buildPack(lines: [l], version: 2), ImportRefusal.entriesInvalid);
    });

    test('a manufacturer-defined code can never ride in a generic pack', () async {
      final l = Map<String, Object?>.from(seedLine('P0120'))
        ..['code'] = 'P1120'
        ..['content_id'] = 'generic:P1120:en';
      await refused(await buildPack(lines: [l], version: 2), ImportRefusal.entriesInvalid);
    });

    test('the word "verified" in any text is refused (D6)', () async {
      final l = Map<String, Object?>.from(seedLine('P0120'))
        ..['rider_advice_en'] = 'This meaning is verified by the maker.';
      await refused(await buildPack(lines: [l], version: 2), ImportRefusal.entriesInvalid);
    });

    test('content_id that does not match the code, scope or language', () async {
      final l = Map<String, Object?>.from(seedLine('P0120'))..['content_id'] = 'generic:P0120:hi';
      await refused(await buildPack(lines: [l], version: 2), ImportRefusal.entriesInvalid);
    });

    test('the declared count disagrees with the file', () async {
      await refused(await buildPack(lines: seedLines().take(4).toList(), version: 2, entriesCount: 5),
          ImportRefusal.countMismatch);
    });

    test('the same content_id twice', () async {
      final l = seedLine('P0120');
      await refused(await buildPack(lines: [l, l], version: 2), ImportRefusal.duplicateEntry);
    });

    test('a pack trying to take over another pack\'s entries', () async {
      final r = await imp(store,
          await buildPack(lines: [seedLine('P0120')], packId: 'generic_en_extra'));
      expect(r.refusal, ImportRefusal.contentIdOwnedElsewhere);
      expect(await store.pack('generic_en_extra'), isNull);
      expect(await count(store), 140);
    });

    test('broken manifest JSON and a missing manifest field', () async {
      final p = await buildPack(lines: seedLines(), version: 2);
      await refused(BuiltPack(utf8.encode('{nope'), p.entriesBytes, p.manifest),
          ImportRefusal.manifestInvalid);
      final q = await buildPack(lines: seedLines(), version: 2,
          tamperManifest: (m) => m.remove('content_sha256'));
      await refused(q, ImportRefusal.manifestInvalid);
    });

    test('a pack needing a newer app', () async {
      await refused(await buildPack(lines: seedLines(), version: 2, minAppVersion: '9.0.0'),
          ImportRefusal.appTooOld);
    });

    test('not UTF-8', () async {
      final bytes = [0xff, 0xfe, 0x00, 0x41];
      await refused(
          await buildPack(lines: seedLines(), version: 2, entriesOverride: bytes),
          ImportRefusal.notUtf8);
    });

    test('a debug pack outside a debug path', () async {
      await refused(await buildPack(lines: seedLines(), version: 2), ImportRefusal.debugNotAllowed,
          source: PackSource.debug);
    });

    test('a gzip file that expands past the cap', () async {
      final bomb = gzip.encode(List<int>.filled(kMaxPackDecodedBytes + 1024, 0x20));
      await refused(await buildPack(lines: seedLines(), version: 2, entriesOverride: bomb),
          ImportRefusal.tooLarge);
    });
  });

  group('B3 downloaded packs: fail closed on signatures', () {
    late SimpleKeyPair key;
    late List<int> pub;
    setUp(() async {
      key = await Ed25519().newKeyPair();
      pub = (await key.extractPublicKey()).bytes;
    });

    test('the production key is not set, and nothing placeholder-like is', () {
      expect(kKnowledgePackPublicKeyBase64, isNull);
      expect(productionPackPublicKey(), isNull);
    });

    test('with no production key every downloaded pack is refused, even a signed one', () async {
      final p = await buildPack(lines: seedLines().take(3).toList(), signWith: key);
      final r = await store.importPack(
          manifestBytes: p.manifestBytes,
          entriesBytes: p.entriesBytes,
          source: PackSource.downloaded,
          appVersion: '1.0.0');
      expect(r.refusal, ImportRefusal.noProductionKey);
      expect(await count(store), 0);
    });

    test('a correctly signed pack imports under the test key', () async {
      final p = await buildPack(lines: seedLines().take(3).toList(), signWith: key, gzipped: true);
      final r = await imp(store, p, source: PackSource.downloaded, key: pub);
      expect(r.imported, isTrue, reason: '$r');
      expect((await store.pack('generic_en'))!.source, PackSource.downloaded);
      expect(await count(store), 3);
    });

    test('unsigned', () async {
      final p = await buildPack(lines: seedLines().take(3).toList());
      expect((await imp(store, p, source: PackSource.downloaded, key: pub)).refusal,
          ImportRefusal.unsigned);
    });

    test('signed by someone else', () async {
      final other = await Ed25519().newKeyPair();
      final p = await buildPack(lines: seedLines().take(3).toList(), signWith: other);
      expect((await imp(store, p, source: PackSource.downloaded, key: pub)).refusal,
          ImportRefusal.badSignature);
    });

    test('a signed manifest edited afterwards (version bumped, revocation added)', () async {
      for (final tamper in <void Function(Map<String, Object?>)>[
        (m) => m['version'] = 99,
        (m) => m['revoked'] = ['generic:P0120:en'],
        (m) => m['review_state'] = 'reviewed',
      ]) {
        final p = await buildPack(
            lines: seedLines().take(3).toList(), signWith: key, tamperManifest: tamper);
        expect((await imp(store, p, source: PackSource.downloaded, key: pub)).refusal,
            ImportRefusal.badSignature);
      }
      expect(await count(store), 0);
    });

    test('verifyPackSignature on its own: every refusal reason', () async {
      final p = await buildPack(lines: seedLines().take(2).toList(), signWith: key);
      final m = PackManifest.parse(p.manifest, <String>[])!;
      expect(await verifyPackSignature(m, p.entriesBytes, pub), PackSignatureCheck.valid);
      expect(await verifyPackSignature(m, p.entriesBytes, null),
          PackSignatureCheck.noKeyConfigured);
      expect(await verifyPackSignature(m, [...p.entriesBytes, 10], pub),
          PackSignatureCheck.hashMismatch);
      expect(await verifyPackSignature(m, p.entriesBytes, pub.sublist(0, 31)),
          PackSignatureCheck.malformed);
      final unsigned = PackManifest.parse({...p.manifest, 'signature': null}, <String>[])!;
      expect(await verifyPackSignature(unsigned, p.entriesBytes, pub),
          PackSignatureCheck.noSignature);
    });
  });

  group('B3 revocations and languages', () {
    test('revoked ids are applied and survive another pack\'s import', () async {
      expect((await importBundledFromDisk(store)).imported, isTrue);
      final v2 = await buildPack(lines: seedLines(), version: 2, revoked: ['generic:P0120:en']);
      expect((await imp(store, v2)).imported, isTrue);
      expect(await count(store, "status = 'revoked'"), 1);
      expect((await store.activeEntries()).any((e) => e.code == 'P0120'), isFalse);
      final hi = await buildPack(
          packId: 'generic_hi',
          language: 'hi',
          lines: [translatedLine('P0105', 'hi', {'title_hi': 'MAP सेंसर: सर्किट में खराबी'})]);
      expect((await imp(store, hi)).imported, isTrue);
      expect(await count(store, "status = 'revoked'"), 1);
    });

    test('a Hindi pack fills in as separate rows, partial rows allowed', () async {
      expect((await importBundledFromDisk(store)).imported, isTrue);
      final hi = await buildPack(packId: 'generic_hi', language: 'hi', lines: [
        translatedLine('P0120', 'hi', {
          'title_hi': 'थ्रॉटल पोज़िशन सेंसर A: सर्किट में खराबी',
          'meaning_hi': 'बाइक का कंप्यूटर (ECU) थ्रॉटल कितना खुला है, यह ठीक से नहीं पढ़ पा रहा।',
          'hi_status': 'reviewed',
        }),
        translatedLine('P0105', 'hi', {'title_hi': 'MAP सेंसर: सर्किट में खराबी'}),
      ]);
      final r = await imp(store, hi);
      expect(r.imported, isTrue, reason: '$r');
      final rows = (await store.activeEntries()).where((e) => e.language == 'hi').toList();
      expect(rows, hasLength(2));
      final p0120 = rows.firstWhere((e) => e.code == 'P0120');
      expect(p0120.hiStatus, HiStatus.reviewed);
      expect(p0120.riderAdvice, isNull, reason: 'missing fields stay empty for fallback');
      expect(rows.firstWhere((e) => e.code == 'P0105').hiStatus, HiStatus.machine);
      expect(await count(store, "language = 'en'"), 140);
    });
  });
}
