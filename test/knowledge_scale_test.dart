/// Phase 4A H2 — scale. A test only: nothing here is ever bundled.
///
/// 10,000 synthetic English entries and 10,000 synthetic Hindi rows in the
/// real pack format (rows are the real shipped rows as templates, so their
/// size and shape are realistic), imported into a real SQLite file. Measured:
/// import time, typed-code lookup, word search, database size, and whether the
/// main isolate stays responsive while the start-up import runs.
///
/// Budgets (this machine; a phone is slower, see the Phase 4A report):
///   import both packs  < 15 s     lookup (any kind)  < 200 ms
///   main-isolate stall during start-up import  < 250 ms
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:danlite_elm/knowledge/code_lookup.dart';
import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/knowledge/knowledge_service.dart';
import 'package:danlite_elm/knowledge/knowledge_store.dart';
import 'package:danlite_elm/knowledge/pack_signature.dart' show sha256Hex;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/kb_pack_builder.dart';
import 'support/knowledge_harness.dart';

const int kScale = 10000;
const Duration importBudget = Duration(seconds: 15);
const Duration lookupBudget = Duration(milliseconds: 200);
const Duration stallBudget = Duration(milliseconds: 250);

const _parts = ['Throttle', 'Intake', 'Coolant', 'Oxygen', 'Fuel', 'Ignition', 'Crankshaft',
  'Camshaft', 'Knock', 'Idle', 'Battery', 'Injector', 'Pump', 'Gear', 'Clutch'];
const _kinds = ['sensor', 'circuit', 'valve', 'relay', 'switch', 'actuator'];
const _faults = ['low', 'high', 'intermittent', 'range', 'performance'];
const _partsHi = ['थ्रॉटल', 'इनटेक', 'कूलेंट', 'ऑक्सीजन', 'फ़्यूल', 'इग्निशन', 'क्रैंकशाफ़्ट',
  'कैमशाफ़्ट', 'नॉक', 'आइडल', 'बैटरी', 'इंजेक्टर', 'पंप', 'गियर', 'क्लच'];

/// The i-th synthetic code: P0xxx, then P2xxx, then U0xxx (all standard-defined,
/// so a generic pack accepts them).
String codeAt(int i) {
  String hex3(int n) => n.toRadixString(16).toUpperCase().padLeft(3, '0');
  if (i < 4096) return 'P0${hex3(i)}';
  if (i < 8192) return 'P2${hex3(i - 4096)}';
  return 'U0${hex3(i - 8192)}';
}

String englishTitle(int i) =>
    '${_parts[i % _parts.length]} ${_kinds[(i ~/ 3) % _kinds.length]} '
    '${_faults[(i ~/ 7) % _faults.length]} #$i';

String hindiTitle(int i) => '${_partsHi[i % _partsHi.length]} सेंसर ${_faults[(i ~/ 7) % _faults.length]} #$i';

List<Map<String, Object?>> _templates(String dir) => [
      for (final l in File('$dir/entries.jsonl').readAsLinesSync())
        if (l.trim().isNotEmpty) Map<String, Object?>.from(jsonDecode(l) as Map),
    ];

/// [n] synthetic lines for [lang], built from the real shipped rows.
List<String> syntheticLines(String lang, int n,
    {String scope = 'generic', int Function(int)? codeIndex}) {
  final tpl = _templates(lang == 'en' ? kBundledDir : kBundledHiDir);
  return [
    for (var i = 0; i < n; i++)
      () {
        final t = Map<String, Object?>.from(tpl[i % tpl.length]);
        final code = codeAt(codeIndex == null ? i : codeIndex(i));
        t['code'] = code;
        t['content_id'] = '$scope:$code:$lang';
        t['system'] = code.startsWith('U') ? 'network' : 'powertrain';
        t['title_$lang'] = lang == 'en' ? englishTitle(i) : hindiTitle(i);
        return jsonEncode(t);
      }()
  ];
}

Future<BuiltPack> pack(List<String> lines, String lang, {bool gzipped = false}) async {
  final text = '${lines.join('\n')}\n';
  List<int> bytes = utf8.encode(text);
  if (gzipped) bytes = gzip.encode(bytes);
  final manifest = <String, Object?>{
    'pack_id': 'generic_$lang',
    'scope': 'generic',
    'language': lang,
    'version': 1,
    'entries_count': lines.length,
    'content_sha256': await sha256Hex(bytes),
    'created_at': '2026-10-03',
    'min_app_version': '1.0.0',
    'review_state': 'draft',
    'revoked': <String>[],
    'signature': null,
  };
  return BuiltPack(utf8.encode(jsonEncode(manifest)), bytes, manifest);
}

String ms(Duration d) => '${d.inMilliseconds} ms';

void main() {
  late List<String> enLines;
  late List<String> hiLines;
  late BuiltPack enPack;
  late BuiltPack hiPack;
  final report = <String, String>{};

  setUpAll(() async {
    enLines = syntheticLines('en', kScale);
    hiLines = syntheticLines('hi', kScale);
    enPack = await pack(enLines, 'en');
    // 10,000 real-size Hindi rows are over the 20 MB as-shipped cap raw, so a
    // pack this size travels gzipped (the importer supports it).
    hiPack = await pack(hiLines, 'hi', gzipped: true);
    report['English pack, raw'] = '${(enPack.entriesBytes.length / 1048576).toStringAsFixed(1)} MB';
    report['Hindi pack, raw / gzipped'] =
        '${(utf8.encode(hiLines.join('\n')).length / 1048576).toStringAsFixed(1)} MB / '
        '${(hiPack.entriesBytes.length / 1048576).toStringAsFixed(1)} MB';
  });

  tearDownAll(() {
    // ignore: avoid_print
    print('\n===== H2 SCALE REPORT (10,000 + 10,000) =====');
    report.forEach((k, v) => print('  $k: $v')); // ignore: avoid_print
  });

  test('the synthetic packs are valid and distinct, realistic in size', () {
    expect(enLines.length, kScale);
    expect({for (final l in enLines) (jsonDecode(l) as Map)['content_id']}.length, kScale);
    expect({for (final l in hiLines) (jsonDecode(l) as Map)['content_id']}.length, kScale);
  });

  group('10,000 + 10,000 rows in a real SQLite file', () {
    late KnowledgeStore store;
    late String path;

    test('import time, database size, row counts', () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('danlite_scale_');
      path = '${dir.path}${Platform.pathSeparator}kb.db';
      store = await KnowledgeStore.open(databaseFactoryFfi, path);

      final sw = Stopwatch()..start();
      final en = await store.importPack(
          manifestBytes: enPack.manifestBytes, entriesBytes: enPack.entriesBytes,
          source: PackSource.bundled, appVersion: '1.0.0');
      final tEn = sw.elapsed;
      final hi = await store.importPack(
          manifestBytes: hiPack.manifestBytes, entriesBytes: hiPack.entriesBytes,
          source: PackSource.bundled, appVersion: '1.0.0');
      final total = sw.elapsed;
      expect(en.imported, isTrue, reason: '$en');
      expect(hi.imported, isTrue, reason: '$hi');
      report['import English 10,000'] = ms(tEn);
      report['import Hindi 10,000 (gzipped)'] = ms(total - tEn);
      report['import total'] = ms(total);
      expect(total, lessThan(importBudget));

      final n = (await store.db.rawQuery('SELECT COUNT(*) AS n FROM kb_entry')).first['n'];
      expect(n, 2 * kScale);
      final size = File(path).lengthSync();
      report['database size'] = '${(size / 1048576).toStringAsFixed(1)} MB';
    });

    test('typed-code lookup, word search and prefix search stay under 200 ms', () async {
      final rnd = [for (var i = 0; i < 150; i++) (i * 6571 + 13) % kScale];
      for (final lang in ['en', 'hi']) {
        var worst = Duration.zero;
        var sum = Duration.zero;
        for (final i in rnd) {
          final sw = Stopwatch()..start();
          final r = await searchCodes(parseLookupQuery(codeAt(i)), store: store, language: lang);
          sw.stop();
          expect(r.items.first.code, codeAt(i));
          sum += sw.elapsed;
          if (sw.elapsed > worst) worst = sw.elapsed;
        }
        report['typed code ($lang): mean / worst of 150'] =
            '${(sum.inMicroseconds / 150 / 1000).toStringAsFixed(1)} ms / ${ms(worst)}';
        expect(worst, lessThan(lookupBudget), reason: 'typed code, $lang');
      }

      Future<void> timed(String label, String query, String lang) async {
        final sw = Stopwatch()..start();
        final r = await searchCodes(parseLookupQuery(query), store: store, language: lang);
        sw.stop();
        report[label] = '${ms(sw.elapsed)} (${r.items.length} shown${r.capped ? ', capped' : ''})';
        expect(sw.elapsed, lessThan(lookupBudget), reason: label);
        expect(r.items, isNotEmpty, reason: label);
      }

      await timed('word search "ignition valve" (en)', 'ignition valve', 'en');
      await timed('word search "sensor" (en, thousands match)', 'sensor', 'en');
      await timed('word search "intermittent pump" (en)', 'intermittent pump', 'en');
      await timed('word search "थ्रॉटल" (hi)', 'थ्रॉटल', 'hi');
      await timed('prefix search "P0" (en)', 'P0', 'en');
      await timed('prefix search "U07" (hi)', 'U07', 'hi');
    });

    test('a word search that matches nothing is fast too', () async {
      final sw = Stopwatch()..start();
      final r = await searchCodes(parseLookupQuery('zzqq'), store: store, language: 'en');
      sw.stop();
      report['word search with no match'] = ms(sw.elapsed);
      expect(r.items, isEmpty);
      expect(sw.elapsed, lessThan(lookupBudget));
    });

    test('loading the resolver index from 20,000 rows', () async {
      final sw = Stopwatch()..start();
      final rows = await store.activeEntries();
      sw.stop();
      report['load all active rows (resolver index input)'] = '${ms(sw.elapsed)} (${rows.length} rows)';
      expect(rows.length, 2 * kScale);
      await store.close();
    });
  });

  test('first screen is not blocked: the main isolate keeps ticking during the start-up import',
      () async {
    final path = await tempDbPath();
    final k = KnowledgeService(
      openStore: () => KnowledgeStore.open(databaseFactoryFfi, path),
      loadAsset: (p) async {
        await Future<void>.delayed(Duration.zero);
        if (p.endsWith('generic_en/manifest.json')) return enPack.manifestBytes;
        if (p.endsWith('generic_en/entries.jsonl')) return enPack.entriesBytes;
        if (p.endsWith('generic_hi/manifest.json')) return hiPack.manifestBytes;
        if (p.endsWith('generic_hi/entries.jsonl')) return hiPack.entriesBytes;
        throw ArgumentError(p);
      },
    );
    var worstGap = Duration.zero;
    var last = DateTime.now();
    final ticker = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final now = DateTime.now();
      final gap = now.difference(last);
      if (gap > worstGap) worstGap = gap;
      last = now;
    });
    final sw = Stopwatch()..start();
    // main.dart does exactly this: start() un-awaited, UI carries on.
    final started = k.start();
    expect(k.state, KnowledgeState.loading, reason: 'start() returns at once');
    await started;
    sw.stop();
    ticker.cancel();
    expect(k.state, KnowledgeState.ready, reason: '${k.bundledImports}');
    report['start() end to end (open, import both, index)'] = ms(sw.elapsed);
    report['longest main-isolate stall during it'] = ms(worstGap);
    expect(await k.store!.db.rawQuery('SELECT COUNT(*) AS n FROM kb_entry'), [
      {'n': 2 * kScale}
    ]);
    expect(worstGap, lessThan(stallBudget));
    await k.store!.close();
  });

  group('50,000 rows do not crash the app', () {
    /// [n] distinct platform-scope lines spread over the four code letters.
    List<String> manyLines(int n, {required bool compact}) {
      final tpl = _templates(kBundledDir);
      final per = (n / 4).ceil();
      return List<String>.generate(n, (i) {
        final m = Map<String, Object?>.from(tpl[i % tpl.length]);
        final letter = 'PCBU'[i ~/ per];
        final j = i % per;
        final code = '$letter${j ~/ 4096}${(j % 4096).toRadixString(16).toUpperCase().padLeft(3, '0')}';
        m['code'] = code;
        m['content_id'] = 'platform:synth:$code:en';
        m['system'] = {'P': 'powertrain', 'C': 'chassis', 'B': 'body', 'U': 'network'}[letter];
        m['title_en'] = 'Synthetic fault $i';
        if (compact) {
          m['meaning_en'] = 'Synthetic meaning.';
          m['rider_advice_en'] = 'Have it checked.';
          m['likely_causes_en'] = ['Cause one', 'Cause two'];
          m['technician_hints_en'] = ['Check wiring'];
        }
        return jsonEncode(m);
      });
    }

    Future<(ImportOutcome, Duration, int, KnowledgeStore)> run(List<String> lines) async {
      sqfliteFfiInit();
      final (store, _) = await openTempStore();
      final text = '${lines.join('\n')}\n';
      final bytes = gzip.encode(utf8.encode(text));
      final m = <String, Object?>{
        'pack_id': 'platform_synth', 'scope': 'platform:synth', 'language': 'en', 'version': 1,
        'entries_count': lines.length, 'content_sha256': await sha256Hex(bytes),
        'created_at': '2026-10-03', 'min_app_version': '1.0.0', 'review_state': 'draft',
        'revoked': <String>[], 'signature': null,
      };
      final sw = Stopwatch()..start();
      final r = await store.importPack(
          manifestBytes: utf8.encode(jsonEncode(m)), entriesBytes: bytes,
          source: PackSource.bundled, appVersion: '1.0.0');
      sw.stop();
      return (r, sw.elapsed, utf8.encode(text).length, store);
    }

    Future<int> rows(KnowledgeStore s) async =>
        (await s.db.rawQuery('SELECT COUNT(*) AS n FROM kb_entry')).first['n'] as int;

    test('rows of the real size: refused cleanly over the size cap, nothing changes', () async {
      final (r, t, decoded, store) = await run(manyLines(50000, compact: false));
      report['50,000 real-size rows (${(decoded / 1048576).toStringAsFixed(0)} MB decoded)'] =
          '${r.imported ? 'imported' : 'refused ${r.refusal!.name}'} in ${ms(t)}';
      expect(r.refusal, ImportRefusal.tooLarge, reason: '$r');
      expect(await rows(store), 0);
      await store.close();
    });

    test('50,000 compact rows (under the cap) import without error', () async {
      final (r, t, decoded, store) = await run(manyLines(50000, compact: true));
      report['50,000 compact rows (${(decoded / 1048576).toStringAsFixed(0)} MB decoded)'] =
          '${r.imported ? 'imported' : 'refused ${r.refusal!.name}: ${r.detail.take(2)}'} in ${ms(t)}';
      expect(r.imported, isTrue, reason: '$r');
      expect(await rows(store), 50000);
      await store.close();
    });
  });
}
