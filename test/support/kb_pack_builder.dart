/// Builds knowledge packs for tests: manifest + entries, optionally gzipped
/// and signed with a key pair created inside the test. Starts from the real
/// bundled seed lines, so tests exercise the real content shape.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/knowledge/knowledge_store.dart';
import 'package:danlite_elm/knowledge/pack_signature.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String kBundledDir = 'assets/knowledge/generic_en';
const String kBundledHiDir = 'assets/knowledge/generic_hi';

/// What the shipped packs contain (Phase 4A: the final 308-entry content).
/// Hard-coded on purpose: a pack that quietly changes size fails a test.
const int kBundledEnCount = 308;
const int kBundledEnVersion = 2;
const int kBundledHiCount = 308;
const int kBundledHiVersion = 1;

/// The real bundled seed lines, decoded.
List<Map<String, Object?>> seedLines() => [
      for (final l in File('$kBundledDir/entries.jsonl').readAsLinesSync())
        if (l.trim().isNotEmpty) Map<String, Object?>.from(jsonDecode(l) as Map),
    ];

Map<String, Object?> seedLine(String code) =>
    seedLines().firstWhere((l) => l['code'] == code);

class BuiltPack {
  BuiltPack(this.manifestBytes, this.entriesBytes, this.manifest);
  final List<int> manifestBytes;
  final List<int> entriesBytes;
  final Map<String, Object?> manifest;
}

/// A pack of [lines]. [mutateManifest] runs after the hash is computed and
/// BEFORE signing (so a signed pack stays valid), [tamperManifest] after
/// signing (to break it).
Future<BuiltPack> buildPack({
  required List<Map<String, Object?>> lines,
  String packId = 'generic_en',
  int version = 1,
  String scope = 'generic',
  String language = 'en',
  List<String> revoked = const <String>[],
  bool gzipped = false,
  SimpleKeyPair? signWith,
  int? entriesCount,
  String minAppVersion = '1.0.0',
  void Function(Map<String, Object?>)? tamperManifest,
  List<int>? entriesOverride,
}) async {
  final text = '${lines.map(jsonEncode).join('\n')}\n';
  List<int> bytes = utf8.encode(text);
  if (gzipped) bytes = gzip.encode(bytes);
  if (entriesOverride != null) bytes = entriesOverride;
  final manifest = <String, Object?>{
    'pack_id': packId,
    'scope': scope,
    'language': language,
    'version': version,
    'entries_count': entriesCount ?? lines.length,
    'content_sha256': await sha256Hex(bytes),
    'created_at': '2026-10-02',
    'min_app_version': minAppVersion,
    'review_state': 'draft',
    'revoked': revoked,
    'signature': null,
  };
  if (signWith != null) {
    final m = PackManifest.parse(manifest, <String>[])!;
    final sig = await Ed25519().sign(canonicalPackBytes(m), keyPair: signWith);
    manifest['signature'] = base64Url.encode(sig.bytes).replaceAll('=', '');
  }
  tamperManifest?.call(manifest);
  return BuiltPack(utf8.encode(jsonEncode(manifest)), bytes, manifest);
}

/// A fresh file-backed store in its own temp folder.
Future<(KnowledgeStore, String)> openTempStore() async {
  sqfliteFfiInit();
  final dir = await Directory.systemTemp.createTemp('danlite_kb_');
  final path = '${dir.path}${Platform.pathSeparator}kb.db';
  final store = await KnowledgeStore.open(databaseFactoryFfi, path);
  return (store, path);
}

Future<ImportOutcome> importBundledFromDisk(KnowledgeStore store) =>
    store.importPack(
      manifestBytes: File('$kBundledDir/manifest.json').readAsBytesSync(),
      entriesBytes: File('$kBundledDir/entries.jsonl').readAsBytesSync(),
      source: PackSource.bundled,
      appVersion: '1.0.0',
    );

Future<ImportOutcome> importBundledHindiFromDisk(KnowledgeStore store) =>
    store.importPack(
      manifestBytes: File('$kBundledHiDir/manifest.json').readAsBytesSync(),
      entriesBytes: File('$kBundledHiDir/entries.jsonl').readAsBytesSync(),
      source: PackSource.bundled,
      appVersion: '1.0.0',
    );

/// A line for [code] in [language] with only [fields] filled in, for Hindi
/// and other partial packs. Non-text facts are copied from the English seed.
Map<String, Object?> translatedLine(String code, String language,
    Map<String, Object?> fields, {String scopePrefix = 'generic:'}) {
  final en = seedLine(code);
  return <String, Object?>{
    for (final k in const [
      'schema_version', 'code', 'system', 'rider_action_level',
      'can_ride_to_workshop', 'flags', 'applies_when', 'confidence',
      'derived_from', 'verification', 'needs_independent_review', 'updated_at',
    ])
      k: en[k],
    'content_id': '$scopePrefix$code:$language',
    ...fields,
  };
}
