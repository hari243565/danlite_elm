/// Danlite ELM — the knowledge store: packs in, meanings out.
///
/// A pack (manifest + JSONL entries) is checked end to end BEFORE the database
/// is touched — manifest, app version, size, SHA-256, signature (downloaded
/// packs), UTF-8, every line against schema v2, the declared count — and then
/// written in ONE transaction that replaces the older version of the same
/// pack. Anything that fails, at any point, including a crash or power cut
/// mid-write, leaves the previous data exactly as it was: SQLite rolls an
/// unfinished transaction back from its journal the next time the file opens.
///
/// No network: packs arrive as bytes. Downloading them is Phase 3.
library;

import 'dart:convert';
import 'dart:io' show gzip;

import 'package:sqflite/sqflite.dart';

import 'kb_models.dart';
import 'kb_schema.dart';
import 'kb_validator.dart';
import 'pack_signature.dart';

/// Largest entries file accepted as shipped (compressed or not).
const int kMaxPackBytes = 20 * 1024 * 1024;

/// Largest entries file accepted after decompression.
const int kMaxPackDecodedBytes = 50 * 1024 * 1024;

/// SQLite on old Android allows 999 host parameters; stay well under it.
const int _sqlChunk = 400;

enum ImportRefusal {
  manifestInvalid,
  debugNotAllowed,
  appTooOld,
  tooLarge,
  hashMismatch,
  noProductionKey,
  unsigned,
  badSignature,
  notUtf8,
  entriesInvalid,
  duplicateEntry,
  countMismatch,
  notNewer,
  contentIdOwnedElsewhere,
  storageError,
}

class ImportOutcome {
  const ImportOutcome.imported(this.packId, this.version, this.count)
      : refusal = null,
        detail = const <String>[];
  const ImportOutcome.refused(this.refusal, this.detail, {this.packId, this.version})
      : count = 0;

  final ImportRefusal? refusal;
  final List<String> detail;
  final String? packId;
  final int? version;
  final int count;

  bool get imported => refusal == null;

  @override
  String toString() => imported
      ? 'imported $packId v$version ($count entries)'
      : 'refused ${refusal!.name}: ${detail.take(3).join('; ')}';
}

/// A pack already in the store.
class KbPackInfo {
  const KbPackInfo({
    required this.packId,
    required this.version,
    required this.scope,
    required this.language,
    required this.source,
    required this.reviewState,
    required this.contentSha256,
    required this.entriesCount,
    required this.importedAt,
  });

  final String packId;
  final int version;
  final String scope;
  final String language;
  final PackSource source;
  final String reviewState;
  final String contentSha256;
  final int entriesCount;
  final DateTime importedAt;

  factory KbPackInfo.fromRow(Map<String, Object?> r) => KbPackInfo(
        packId: r['pack_id'] as String,
        version: r['version'] as int,
        scope: r['scope'] as String,
        language: r['language'] as String,
        source: PackSource.fromDb(r['source'] as String?) ?? PackSource.downloaded,
        reviewState: r['review_state'] as String,
        contentSha256: r['content_sha256'] as String,
        entriesCount: r['entries_count'] as int,
        importedAt: DateTime.fromMillisecondsSinceEpoch(r['imported_at'] as int, isUtc: true),
      );
}

/// Called inside the import transaction at named points. Tests use it to cut
/// an import off half way (`'half'`), exactly as a power cut would.
typedef ImportHook = Future<void> Function(String phase);

class KnowledgeStore {
  KnowledgeStore._(this.db);

  /// The open database. Shared with the scan history (`scan_history.dart`).
  final Database db;

  /// Open (creating or migrating) the database at [path]. A file written by a
  /// NEWER build is deleted and recreated: knowledge is re-imported from the
  /// bundled pack, and an unreadable history is worse than none.
  static Future<KnowledgeStore> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: kKnowledgeSchemaVersion,
        onCreate: (db, v) => runMigrations(db, 0, v),
        onUpgrade: (db, from, to) => runMigrations(db, from, to),
        onDowngrade: onDatabaseDowngradeDelete,
      ),
    );
    return KnowledgeStore._(db);
  }

  Future<void> close() => db.close();

  Future<int> schemaVersion() async {
    final rows = await db.query('schema_version');
    return rows.isEmpty ? 0 : rows.first['version'] as int;
  }

  Future<KbPackInfo?> pack(String packId) async {
    final rows = await db.query('kb_pack', where: 'pack_id = ?', whereArgs: [packId]);
    return rows.isEmpty ? null : KbPackInfo.fromRow(rows.first);
  }

  Future<List<KbPackInfo>> packs() async =>
      [for (final r in await db.query('kb_pack', orderBy: 'pack_id')) KbPackInfo.fromRow(r)];

  /// Every active entry, with its pack's review state.
  Future<List<KbEntry>> activeEntries() async => _entries(
      "SELECT e.*, p.review_state AS pack_review_state FROM kb_entry e "
      "LEFT JOIN kb_pack p ON p.pack_id = e.pack_id WHERE e.status = 'active'",
      const <Object?>[]);

  /// How many languages the active entries are written in. A code has one
  /// row per language, so a search that wants N codes must fetch up to
  /// N times this many rows.
  Future<int> languageCount() async => (await db.rawQuery(
          "SELECT COUNT(DISTINCT language) AS n FROM kb_entry WHERE status = 'active'"))
      .first['n'] as int;

  /// Active entries whose code is one of [codes] or starts with one of
  /// [prefixes], then entries whose title or meaning contains every word in
  /// [words]. At most [limit] rows overall.
  Future<List<KbEntry>> search({
    List<String> codes = const <String>[],
    List<String> prefixes = const <String>[],
    List<String> words = const <String>[],
    int limit = 50,
  }) async {
    final out = <KbEntry>[];
    final seen = <String>{};
    void add(List<KbEntry> rows) {
      for (final e in rows) {
        if (out.length >= limit) return;
        if (seen.add(e.contentId)) out.add(e);
      }
    }

    const base = "SELECT e.*, p.review_state AS pack_review_state FROM kb_entry e "
        "LEFT JOIN kb_pack p ON p.pack_id = e.pack_id WHERE e.status = 'active' ";
    if (codes.isNotEmpty) {
      add(await _entries(
          '${base}AND e.code IN (${List.filled(codes.length, '?').join(',')}) '
          'ORDER BY e.code LIMIT $limit',
          codes));
    }
    for (final p in prefixes) {
      if (out.length >= limit) break;
      add(await _entries(
          "${base}AND e.code LIKE ? ESCAPE '\\' ORDER BY e.code LIMIT $limit",
          ['${_escapeLike(p)}%']));
    }
    if (words.isNotEmpty && out.length < limit) {
      final clause = List.filled(words.length,
              "(e.title LIKE ? ESCAPE '\\' OR e.meaning LIKE ? ESCAPE '\\')")
          .join(' AND ');
      add(await _entries('${base}AND $clause ORDER BY e.code LIMIT $limit', [
        for (final w in words) ...['%${_escapeLike(w)}%', '%${_escapeLike(w)}%'],
      ]));
    }
    return out;
  }

  static String _escapeLike(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');

  Future<List<KbEntry>> _entries(String sql, List<Object?> args) async =>
      [for (final r in await db.rawQuery(sql, args)) KbEntry.fromRow(r)];

  // ══════════════════════════════════════════════════════════════════════
  // Import
  // ══════════════════════════════════════════════════════════════════════

  /// Import one pack.
  ///
  /// [source] says how the bytes arrived; the manifest cannot change it.
  /// A [PackSource.downloaded] pack must be signed under [publicKey], which
  /// defaults to the production key — not set, so every downloaded pack is
  /// refused today. [allowDebug] must be true for a [PackSource.debug] pack
  /// (only ever passed by a debug-build developer path or a test).
  /// [appVersion] is this app's version (`1.0.0`); [now] the import time.
  Future<ImportOutcome> importPack({
    required List<int> manifestBytes,
    required List<int> entriesBytes,
    required PackSource source,
    required String appVersion,
    List<int>? publicKey,
    bool useProductionKey = true,
    bool allowDebug = false,
    DateTime? now,
    ImportHook? hook,
  }) async {
    // ── manifest ────────────────────────────────────────────────────────
    final manifestErrors = <String>[];
    PackManifest? m;
    try {
      m = PackManifest.parse(
          jsonDecode(utf8.decode(manifestBytes)), manifestErrors);
    } on FormatException catch (e) {
      manifestErrors.add('manifest is not JSON: ${e.message}');
    }
    if (m == null) {
      return ImportOutcome.refused(ImportRefusal.manifestInvalid, manifestErrors);
    }
    ImportOutcome refuse(ImportRefusal r, [List<String> d = const <String>[]]) =>
        ImportOutcome.refused(r, d, packId: m!.packId, version: m.version);

    if (source == PackSource.debug && !allowDebug) {
      return refuse(ImportRefusal.debugNotAllowed);
    }
    if (!appVersionAtLeast(appVersion, m.minAppVersion)) {
      return refuse(ImportRefusal.appTooOld, ['needs ${m.minAppVersion}, app is $appVersion']);
    }
    if (entriesBytes.length > kMaxPackBytes) return refuse(ImportRefusal.tooLarge);

    // ── integrity and signature ─────────────────────────────────────────
    if (await sha256Hex(entriesBytes) != m.contentSha256) {
      return refuse(ImportRefusal.hashMismatch);
    }
    if (source == PackSource.downloaded) {
      final key = publicKey ?? (useProductionKey ? productionPackPublicKey() : null);
      switch (await verifyPackSignature(m, entriesBytes, key)) {
        case PackSignatureCheck.valid:
          break;
        case PackSignatureCheck.noKeyConfigured:
          return refuse(ImportRefusal.noProductionKey);
        case PackSignatureCheck.noSignature:
          return refuse(ImportRefusal.unsigned);
        case PackSignatureCheck.hashMismatch:
          return refuse(ImportRefusal.hashMismatch);
        case PackSignatureCheck.badSignature:
        case PackSignatureCheck.malformed:
          return refuse(ImportRefusal.badSignature);
      }
    }

    // ── decode and validate every line ──────────────────────────────────
    final List<int> raw;
    try {
      raw = _maybeGunzip(entriesBytes);
    } on _TooLarge {
      return refuse(ImportRefusal.tooLarge);
    } catch (e) {
      return refuse(ImportRefusal.entriesInvalid, ['entries file cannot be decompressed']);
    }
    final String text;
    try {
      text = utf8.decode(raw);
    } on FormatException {
      return refuse(ImportRefusal.notUtf8);
    }
    final entries = <KbEntry>[];
    final errors = <String>[];
    final ids = <String>{};
    var lineNo = 0;
    for (final line in const LineSplitter().convert(text)) {
      lineNo++;
      if (line.trim().isEmpty) continue;
      Object? json;
      try {
        json = jsonDecode(line);
      } on FormatException {
        errors.add('line $lineNo: not JSON');
        continue;
      }
      final v = validateEntry(json, m);
      if (!v.ok) {
        errors.addAll(v.errors.map((e) => 'line $lineNo: $e'));
        continue;
      }
      if (!ids.add(v.entry!.contentId)) {
        return refuse(ImportRefusal.duplicateEntry, ['line $lineNo: ${v.entry!.contentId} twice']);
      }
      entries.add(v.entry!);
    }
    if (errors.isNotEmpty) return refuse(ImportRefusal.entriesInvalid, errors.take(20).toList());
    if (entries.length != m.entriesCount) {
      return refuse(ImportRefusal.countMismatch,
          ['manifest says ${m.entriesCount}, file has ${entries.length}']);
    }

    // ── write: one transaction, all or nothing ──────────────────────────
    final installed = await pack(m.packId);
    if (installed != null && m.version <= installed.version) {
      return refuse(ImportRefusal.notNewer, ['installed v${installed.version}']);
    }
    try {
      await db.transaction((txn) async {
        // Re-checked inside the transaction: another import may have landed.
        final again = await txn.query('kb_pack',
            columns: ['version'], where: 'pack_id = ?', whereArgs: [m!.packId]);
        if (again.isNotEmpty && m.version <= (again.first['version'] as int)) {
          throw const _Refused(ImportRefusal.notNewer);
        }
        final idList = ids.toList();
        for (var i = 0; i < idList.length; i += _sqlChunk) {
          final chunk = idList.sublist(i, (i + _sqlChunk).clamp(0, idList.length));
          final clash = await txn.rawQuery(
              'SELECT content_id, pack_id FROM kb_entry WHERE pack_id <> ? AND content_id IN '
              '(${List.filled(chunk.length, '?').join(',')}) LIMIT 1',
              [m.packId, ...chunk]);
          if (clash.isNotEmpty) {
            throw _Refused(ImportRefusal.contentIdOwnedElsewhere,
                '${clash.first['content_id']} belongs to ${clash.first['pack_id']}');
          }
        }
        await txn.delete('kb_entry', where: 'pack_id = ?', whereArgs: [m.packId]);
        await txn.delete('kb_revoked', where: 'pack_id = ?', whereArgs: [m.packId]);
        final half = entries.length ~/ 2;
        Future<void> insert(Iterable<KbEntry> rows) async {
          final b = txn.batch();
          for (final e in rows) {
            b.insert('kb_entry', e.toRow());
          }
          await b.commit(noResult: true);
        }

        await insert(entries.take(half));
        if (hook != null) await hook('half');
        await insert(entries.skip(half));
        final rb = txn.batch();
        for (final id in m.revoked) {
          rb.insert('kb_revoked', <String, Object?>{'content_id': id, 'pack_id': m.packId});
        }
        await rb.commit(noResult: true);
        await txn.rawUpdate("UPDATE kb_entry SET status = CASE WHEN content_id IN "
            "(SELECT content_id FROM kb_revoked) THEN 'revoked' ELSE 'active' END");
        await txn.insert(
            'kb_pack',
            <String, Object?>{
              'pack_id': m.packId,
              'version': m.version,
              'scope': m.scope,
              'language': m.language,
              'source': source.db,
              'review_state': m.reviewState,
              'content_sha256': m.contentSha256,
              'entries_count': m.entriesCount,
              'min_app_version': m.minAppVersion,
              'imported_at': (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        if (hook != null) await hook('before-commit');
      });
    } on _Refused catch (r) {
      return refuse(r.refusal, [if (r.detail != null) r.detail!]);
    } catch (e) {
      return refuse(ImportRefusal.storageError, ['${e.runtimeType}']);
    }
    return ImportOutcome.imported(m.packId, m.version, entries.length);
  }

  static List<int> _maybeGunzip(List<int> bytes) {
    if (bytes.length < 2 || bytes[0] != 0x1f || bytes[1] != 0x8b) return bytes;
    final out = <int>[];
    final sink = ChunkedConversionSink<List<int>>.withCallback((chunks) {});
    final conv = gzip.decoder.startChunkedConversion(_CappedSink(out, sink));
    conv.add(bytes);
    conv.close();
    return out;
  }
}

class _Refused implements Exception {
  const _Refused(this.refusal, [this.detail]);
  final ImportRefusal refusal;
  final String? detail;
}

class _TooLarge implements Exception {}

/// Collects decompressed bytes and stops at [kMaxPackDecodedBytes], so a
/// small file that expands enormously cannot exhaust memory.
class _CappedSink implements Sink<List<int>> {
  _CappedSink(this.out, this.inner);
  final List<int> out;
  final Sink<List<int>> inner;

  @override
  void add(List<int> data) {
    if (out.length + data.length > kMaxPackDecodedBytes) throw _TooLarge();
    out.addAll(data);
  }

  @override
  void close() => inner.close();
}
