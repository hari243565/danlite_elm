/// Danlite ELM — scan history, on this phone only.
///
/// Every engine and ABS read is saved, including the ones where the bike did
/// not answer: "did not answer" at 09:14 is part of the bike's story. Saved:
/// when, which profile (its id and make/model label), the adapter's class and
/// protocol, what the read established, engine state, voltage band, lamp
/// state, and each code as a `FaultRecord` with the level and content id it
/// resolved to at the time.
///
/// NEVER saved: a VIN (no field for one, and any VIN-shaped text in a saved
/// string is masked), raw adapter traffic, the adapter's device name or
/// address. Nothing leaves the phone: the only way out is the rider tapping
/// Share, which hands plain text to the system share sheet.
///
/// Retention: [kHistoryMaxSessions] sessions and [kHistoryMaxAge], pruned on
/// every save. The count cap goes by insertion order, not by clock, so a phone
/// whose clock jumps cannot reorder history; the age rule is skipped while the
/// clock reads earlier than the newest saved session (a clock set backwards
/// must not wipe history); the session just saved is never pruned.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/fault_record.dart';

const int kHistoryMaxSessions = 50;
const Duration kHistoryMaxAge = Duration(days: 180);

enum SessionKind {
  engine('engine'),
  abs('abs'),

  /// The internal Clear Codes record (B9). Stored, not listed.
  clearCheck('clear_check');

  const SessionKind(this.db);
  final String db;

  static SessionKind fromDb(String v) =>
      values.firstWhere((k) => k.db == v, orElse: () => SessionKind.engine);
}

/// The outcome of the silent re-read after Clear Codes.
enum ClearCheckOutcome {
  /// The bike still (or again) reports stored codes.
  codesReturned('codes_returned'),

  /// The bike answered with an empty stored-code list.
  clearedVerified('cleared_verified'),

  /// No usable answer: silent, refused, busy, link lost, K-line, cancelled.
  couldNotVerify('could_not_verify');

  const ClearCheckOutcome(this.db);
  final String db;

  static ClearCheckOutcome? fromDb(String? v) {
    for (final o in values) {
      if (o.db == v) return o;
    }
    return null;
  }
}

/// One fault to save, with what it resolved to.
class ScanFaultInput {
  const ScanFaultInput(this.record, {this.resolvedLevel, this.resolvedContentId});
  final FaultRecord record;
  final String? resolvedLevel;
  final String? resolvedContentId;
}

/// One read to save.
class ScanSessionInput {
  const ScanSessionInput({
    required this.kind,
    required this.startedAt,
    required this.reachState,
    this.connectionId,
    this.profileId,
    this.vehicleLabel,
    this.adapterClass,
    this.protocol,
    this.engineState,
    this.voltageBand,
    this.lampState,
    this.clearOutcome,
    this.preClear,
    this.faults = const <ScanFaultInput>[],
    this.coalesce = true,
  });

  final SessionKind kind;
  final DateTime startedAt;
  final String reachState;

  /// Identifies one adapter connection; consecutive identical reads on the
  /// same connection are folded into one session.
  final String? connectionId;
  final String? profileId;
  final String? vehicleLabel;
  final String? adapterClass;
  final String? protocol;
  final String? engineState;
  final String? voltageBand;
  final String? lampState;
  final ClearCheckOutcome? clearOutcome;

  /// Clear Codes only: the codes of the last answered read before the clear,
  /// or `{"snapshot": false}` when there was none in the last minute.
  final Map<String, Object?>? preClear;
  final List<ScanFaultInput> faults;

  /// False for a manual read: always its own session.
  final bool coalesce;

  /// Equal for two reads that established the same thing.
  String get signature => jsonEncode(<Object?>[
        kind.db, reachState, engineState, voltageBand, lampState,
        clearOutcome?.db,
        [
          for (final f in faults)
            '${f.record.key}|${f.record.statusByte}|'
                '${f.record.sources.map((s) => s.name).toList()..sort()}'
        ]..sort(),
      ]);
}

class ScanFaultRow {
  const ScanFaultRow({
    required this.code,
    required this.displayCode,
    required this.format,
    required this.source,
    required this.readAt,
    this.system,
    this.rawHex,
    this.failureType,
    this.statusByte,
    this.status = const <String, bool?>{},
    this.module,
    this.resolvedLevel,
    this.resolvedContentId,
  });

  final String code;
  final String displayCode;
  final String? system;
  final String format;
  final String? rawHex;
  final int? failureType;
  final int? statusByte;
  final Map<String, bool?> status;
  final String source;
  final String? module;
  final DateTime readAt;
  final String? resolvedLevel;
  final String? resolvedContentId;

  /// The record again, for re-resolving in today's language.
  FaultRecord toRecord() {
    final f = DtcFormat.values.firstWhere((x) => x.name == format,
        orElse: () => DtcFormat.sae2);
    final s = ReadSource.values.firstWhere((x) => x.name == source,
        orElse: () => ReadSource.manual);
    return FaultRecord(
      system: FaultSystem.fromCode(code),
      code: code,
      rawBytes: const <int>[],
      format: f,
      failureType: failureType,
      statusByte: statusByte,
      status: FaultStatus(
        active: status['active'],
        pending: status['pending'],
        confirmed: status['confirmed'],
        history: status['history'],
        lampRequested: status['lamp'],
        permanent: status['permanent'],
      ),
      source: s,
      readAt: readAt,
      module: module,
    );
  }
}

class ScanSession {
  const ScanSession({
    required this.id,
    required this.kind,
    required this.startedAt,
    required this.lastSeenAt,
    required this.repeatCount,
    required this.reachState,
    this.profileId,
    this.vehicleLabel,
    this.adapterClass,
    this.protocol,
    this.engineState,
    this.voltageBand,
    this.lampState,
    this.clearOutcome,
    this.preClear,
    this.faults = const <ScanFaultRow>[],
  });

  final int id;
  final SessionKind kind;
  final DateTime startedAt;
  final DateTime lastSeenAt;
  final int repeatCount;
  final String reachState;
  final String? profileId;
  final String? vehicleLabel;
  final String? adapterClass;
  final String? protocol;
  final String? engineState;
  final String? voltageBand;
  final String? lampState;
  final ClearCheckOutcome? clearOutcome;
  final Map<String, Object?>? preClear;
  final List<ScanFaultRow> faults;
}

/// When Clear Codes was attempted, for a `clear_check` record. Records written
/// before Phase A-4 have no stored attempt time; they fall back to the time of
/// the silent re-read, which is a few seconds later.
DateTime clearAttemptedAt(ScanSession s) {
  final raw = s.preClear?['attempted_at'];
  final parsed = raw is String ? DateTime.tryParse(raw) : null;
  return (parsed ?? s.startedAt).toUtc();
}

/// A VIN is 17 characters from this alphabet (no I, O, Q).
final RegExp _vinShaped = RegExp(r'\b[A-HJ-NPR-Z0-9]{17}\b', caseSensitive: false);

/// Mask anything VIN-shaped. A rider can type anything into a profile name or
/// model field; none of it may carry a VIN into history.
String? noVin(String? s) => s?.replaceAll(_vinShaped, '•••');

class ScanHistoryStore {
  ScanHistoryStore(this.db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database db;
  final DateTime Function() _clock;

  /// Save [s] (or fold it into the previous identical session of the same
  /// connection), then prune. Returns the session id.
  Future<int> save(ScanSessionInput s) async {
    final now = _clock().toUtc().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final sig = s.signature;
      if (s.coalesce && s.connectionId != null) {
        final last = await txn.query('scan_session',
            columns: ['id', 'connection_id', 'signature'],
            where: 'kind = ?',
            whereArgs: [s.kind.db],
            orderBy: 'id DESC',
            limit: 1);
        if (last.isNotEmpty &&
            last.first['connection_id'] == s.connectionId &&
            last.first['signature'] == sig) {
          final id = last.first['id'] as int;
          await txn.rawUpdate(
              'UPDATE scan_session SET last_seen_at = ?, repeat_count = repeat_count + 1 '
              'WHERE id = ?',
              [s.startedAt.toUtc().millisecondsSinceEpoch, id]);
          return id;
        }
      }
      final newest = (await txn.rawQuery('SELECT MAX(started_at) AS m FROM scan_session'))
          .first['m'] as int?;
      final started = s.startedAt.toUtc().millisecondsSinceEpoch;
      final id = await txn.insert('scan_session', <String, Object?>{
        'kind': s.kind.db,
        'started_at': started,
        'last_seen_at': started,
        'repeat_count': 1,
        'connection_id': s.connectionId,
        'signature': sig,
        'profile_id': noVin(s.profileId),
        'vehicle_label': noVin(s.vehicleLabel),
        'adapter_class': noVin(s.adapterClass),
        'protocol': s.protocol,
        'reach_state': s.reachState,
        'engine_state': s.engineState,
        'voltage_band': s.voltageBand,
        'lamp_state': s.lampState,
        'clear_outcome': s.clearOutcome?.db,
        'pre_clear_json': s.preClear == null ? null : jsonEncode(s.preClear),
      });
      final b = txn.batch();
      var i = 0;
      for (final f in s.faults) {
        final r = f.record;
        b.insert('scan_fault', <String, Object?>{
          'session_id': id,
          'position': i++,
          'code': r.code,
          'display_code': r.displayCode,
          'system': r.system?.letter,
          'format': r.format.name,
          'raw_hex': r.rawBytes.isEmpty
              ? null
              : r.rawBytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join(),
          'failure_type': r.failureType,
          'status_byte': r.statusByte,
          'status_json': jsonEncode(<String, bool?>{
            'active': r.status.active,
            'pending': r.status.pending,
            'confirmed': r.status.confirmed,
            'history': r.status.history,
            'lamp': r.status.lampRequested,
            'permanent': r.status.permanent,
          }),
          'source': r.source.name,
          'module': noVin(r.module),
          'read_at': r.readAt.toUtc().millisecondsSinceEpoch,
          'resolved_level': f.resolvedLevel,
          'resolved_content_id': f.resolvedContentId,
        });
      }
      await b.commit(noResult: true);
      await _prune(txn, now: now, keepId: id, newestBefore: newest);
      return id;
    });
  }

  Future<void> _prune(Transaction txn,
      {required int now, required int keepId, required int? newestBefore}) async {
    final clockBehind = newestBefore != null && now < newestBefore;
    if (!clockBehind) {
      await txn.delete('scan_session',
          where: 'started_at < ? AND id <> ?',
          whereArgs: [now - kHistoryMaxAge.inMilliseconds, keepId]);
    }
    await txn.rawDelete(
        'DELETE FROM scan_session WHERE id NOT IN '
        '(SELECT id FROM scan_session ORDER BY id DESC LIMIT $kHistoryMaxSessions)');
    await txn.rawDelete(
        'DELETE FROM scan_fault WHERE session_id NOT IN (SELECT id FROM scan_session)');
  }

  /// Sessions newest first. Clear-Codes records are internal and left out
  /// unless [includeInternal].
  Future<List<ScanSession>> list({bool includeInternal = false}) async {
    final rows = await db.query('scan_session',
        where: includeInternal ? null : 'kind <> ?',
        whereArgs: includeInternal ? null : [SessionKind.clearCheck.db],
        orderBy: 'id DESC');
    if (rows.isEmpty) return const <ScanSession>[];
    final ids = [for (final r in rows) r['id'] as int];
    final faults = await db.rawQuery(
        'SELECT * FROM scan_fault WHERE session_id IN (${List.filled(ids.length, '?').join(',')}) '
        'ORDER BY session_id, position',
        ids);
    final bySession = <int, List<ScanFaultRow>>{};
    for (final f in faults) {
      (bySession[f['session_id'] as int] ??= <ScanFaultRow>[]).add(_faultRow(f));
    }
    return [for (final r in rows) _session(r, bySession[r['id'] as int] ?? const <ScanFaultRow>[])];
  }

  Future<ScanSession?> session(int id) async {
    final all = await list(includeInternal: true);
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> deleteAll() => db.transaction((txn) async {
        await txn.delete('scan_fault');
        await txn.delete('scan_session');
      });

  static ScanFaultRow _faultRow(Map<String, Object?> f) {
    Map<String, bool?> status = const <String, bool?>{};
    try {
      final d = jsonDecode((f['status_json'] as String?) ?? '{}');
      if (d is Map) status = {for (final e in d.entries) e.key as String: e.value as bool?};
    } on FormatException {
      // An unreadable status is unknown, never "no".
    }
    return ScanFaultRow(
      code: f['code'] as String,
      displayCode: f['display_code'] as String,
      system: f['system'] as String?,
      format: f['format'] as String,
      rawHex: f['raw_hex'] as String?,
      failureType: f['failure_type'] as int?,
      statusByte: f['status_byte'] as int?,
      status: status,
      source: f['source'] as String,
      module: f['module'] as String?,
      readAt: DateTime.fromMillisecondsSinceEpoch(f['read_at'] as int, isUtc: true),
      resolvedLevel: f['resolved_level'] as String?,
      resolvedContentId: f['resolved_content_id'] as String?,
    );
  }

  static ScanSession _session(Map<String, Object?> r, List<ScanFaultRow> faults) {
    Map<String, Object?>? pre;
    final raw = r['pre_clear_json'] as String?;
    if (raw != null) {
      try {
        pre = Map<String, Object?>.from(jsonDecode(raw) as Map);
      } catch (_) {
        pre = null;
      }
    }
    return ScanSession(
      id: r['id'] as int,
      kind: SessionKind.fromDb(r['kind'] as String),
      startedAt: DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int, isUtc: true),
      lastSeenAt: DateTime.fromMillisecondsSinceEpoch(r['last_seen_at'] as int, isUtc: true),
      repeatCount: r['repeat_count'] as int,
      reachState: r['reach_state'] as String,
      profileId: r['profile_id'] as String?,
      vehicleLabel: r['vehicle_label'] as String?,
      adapterClass: r['adapter_class'] as String?,
      protocol: r['protocol'] as String?,
      engineState: r['engine_state'] as String?,
      voltageBand: r['voltage_band'] as String?,
      lampState: r['lamp_state'] as String?,
      clearOutcome: ClearCheckOutcome.fromDb(r['clear_outcome'] as String?),
      preClear: pre,
      faults: faults,
    );
  }
}
