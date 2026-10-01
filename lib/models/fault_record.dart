/// Danlite ELM — the canonical fault record.
///
/// One [FaultRecord] is one OBSERVATION: which code a module reported, in which
/// byte format, with which status, from which request, at what time. It holds
/// no text — descriptions, severity and advice are knowledge, resolved
/// separately — so the same record can be described in any language, by any
/// future knowledge source, without re-reading the bike.
///
/// Pure Dart: no Flutter or UI imports. The existing screen keeps rendering
/// [DtcCode]; a [DtcCode] now carries the [FaultRecord] it was built from.
library;

import '../constants/obd_pids.dart';
import '../services/fault_decoders.dart';
import 'vehicle_data.dart';

/// The SAE system letter.
enum FaultSystem {
  powertrain('P'),
  chassis('C'),
  body('B'),
  network('U');

  const FaultSystem(this.letter);
  final String letter;

  static FaultSystem? fromCode(String code) {
    if (code.isEmpty) return null;
    for (final s in values) {
      if (s.letter == code[0]) return s;
    }
    return null;
  }
}

/// How the code was carried.
enum DtcFormat {
  /// Two bytes, SAE J2012 (`01 33` → `P0133`): OBD Mode 03 / 07 / 0A.
  sae2,

  /// Three bytes plus status, ISO 14229 (`50 58 11` + status → `C1058-11`).
  uds3,

  /// A manufacturer manual's hex-H notation (`5058H`), entered by hand.
  hexH,

  /// A lamp blink pattern (`4-2`), counted by the rider.
  blink,
}

/// Which request produced the record.
enum ReadSource {
  /// OBD Mode 03 — stored (confirmed) emissions codes.
  mode03,

  /// OBD Mode 07 — pending codes (this or the last drive cycle).
  mode07,

  /// OBD Mode 0A — permanent codes (cannot be cleared by Mode 04).
  mode0A,

  /// UDS `19 02` — reportDTCByStatusMask.
  uds19,

  /// Not read electronically: hex-H or blink entered by hand. (Beyond the
  /// four electronic sources, so the manual formats have a home.)
  manual,
}

/// What is known about a code's status. Every flag is nullable: null means
/// UNKNOWN, and the screen shows nothing for an unknown flag — never "No".
class FaultStatus {
  const FaultStatus({
    this.active,
    this.pending,
    this.confirmed,
    this.history,
    this.lampRequested,
    this.permanent,
  });

  /// Failing on the most recent test.
  final bool? active;

  /// Seen but not yet confirmed (UDS), or reported by OBD Mode 07.
  final bool? pending;

  /// Confirmed and stored.
  final bool? confirmed;

  /// Confirmed but not failing now. Never set for an OBD code.
  final bool? history;

  /// The module asked for the warning lamp for THIS code (UDS bit 7). The
  /// engine-level lamp from PID 01 01 is not per code and is not set here.
  final bool? lampRequested;

  /// Reported by OBD Mode 0A.
  final bool? permanent;

  static const FaultStatus unknown = FaultStatus();

  /// Every flag known, from a UDS status byte, using the derived labels in
  /// [UdsStatusByte].
  factory FaultStatus.fromUdsStatusByte(int byte) {
    final s = UdsStatusByte(byte);
    return FaultStatus(
      active: s.isActive,
      pending: s.isPending,
      confirmed: s.isStored,
      history: s.isHistory,
      lampRequested: s.isLampRequested,
    );
  }

  /// What a given OBD service establishes, and nothing more.
  factory FaultStatus.forObdSource(ReadSource source) {
    switch (source) {
      case ReadSource.mode03:
        return const FaultStatus(confirmed: true);
      case ReadSource.mode07:
        return const FaultStatus(pending: true);
      case ReadSource.mode0A:
        return const FaultStatus(permanent: true);
      case ReadSource.uds19:
      case ReadSource.manual:
        return unknown;
    }
  }

  /// Combine two observations of the same code: a flag either source knows to
  /// be true is true; a flag known false by one and unknown to the other stays
  /// false; unknown to both stays unknown.
  FaultStatus merge(FaultStatus other) {
    bool? m(bool? a, bool? b) {
      if (a == true || b == true) return true;
      if (a == null && b == null) return null;
      return false;
    }

    return FaultStatus(
      active: m(active, other.active),
      pending: m(pending, other.pending),
      confirmed: m(confirmed, other.confirmed),
      history: m(history, other.history),
      lampRequested: m(lampRequested, other.lampRequested),
      permanent: m(permanent, other.permanent),
    );
  }
}

/// `P0133` → `[0x01, 0x33]`: the exact inverse of [ObdParser.decodeDtcPair].
/// Null for anything that is not a five-character SAE code.
List<int>? encodeSae2(String code) {
  final c = code.trim().toUpperCase();
  if (!RegExp(r'^[PCBU][0-3][0-9A-F]{3}$').hasMatch(c)) return null;
  final letter = 'PCBU'.indexOf(c[0]);
  final second = int.parse(c[1]);
  final third = int.parse(c[2], radix: 16);
  final low = int.parse(c.substring(3), radix: 16);
  return <int>[(letter << 6) | (second << 4) | third, low];
}

class FaultRecord {
  const FaultRecord({
    required this.system,
    required this.code,
    required this.rawBytes,
    required this.format,
    required this.status,
    required this.source,
    required this.readAt,
    this.failureType,
    this.statusByte,
    this.module,
    Set<ReadSource>? sources,
  }) : _sources = sources;

  /// P / C / B / U; null for a blink pattern, which has no system letter.
  final FaultSystem? system;

  /// Normalised five-character SAE form (`P0133`), or the blink pattern.
  final String code;

  /// The bytes the code arrived as: two for SAE, three for UDS (without the
  /// status byte, which is [statusByte]).
  final List<int> rawBytes;

  final DtcFormat format;

  /// ISO 14229 failure type byte, for UDS records.
  final int? failureType;

  final FaultStatus status;

  /// The raw UDS status byte, when there was one.
  final int? statusByte;

  /// The responding module's name or address (`7E8`, `ABS 0x7B0`), when known.
  final String? module;

  /// The request that first produced this record.
  final ReadSource source;

  final Set<ReadSource>? _sources;

  /// Every request that reported this code, after merging.
  Set<ReadSource> get sources => _sources ?? <ReadSource>{source};

  final DateTime readAt;

  /// `C1058-11` for a UDS record, else the code.
  String get displayCode => format == DtcFormat.uds3 && failureType != null
      ? '$code-${FailureType.hex(failureType!).substring(2)}'
      : code;

  /// One record per code (and failure type, for UDS).
  String get key => failureType == null ? code : '$code/$failureType';

  // ── Adapters ─────────────────────────────────────────────────────────────

  /// A two-byte code from OBD Mode 03, 07 or 0A.
  factory FaultRecord.fromObdCode(String code,
      {required ReadSource source, required DateTime readAt, String? module}) {
    final c = code.trim().toUpperCase();
    return FaultRecord(
      system: FaultSystem.fromCode(c),
      code: c,
      rawBytes: List<int>.unmodifiable(encodeSae2(c) ?? const <int>[]),
      format: DtcFormat.sae2,
      status: FaultStatus.forObdSource(source),
      source: source,
      readAt: readAt,
      module: module,
    );
  }

  /// From the typed OBD decoder, keeping the responding module.
  factory FaultRecord.fromDecodedObd(DecodedObdDtc d,
          {required ReadSource source, required DateTime readAt}) =>
      FaultRecord.fromObdCode(d.code,
          source: source,
          readAt: readAt,
          module: d.ecuId.isEmpty ? null : d.ecuId);

  /// From the typed UDS decoder.
  factory FaultRecord.fromUds19(Uds19Record r,
          {required DateTime readAt, String? module}) =>
      FaultRecord(
        system: FaultSystem.fromCode(r.code),
        code: r.code,
        rawBytes: List<int>.unmodifiable(<int>[r.dtcHigh, r.dtcMid, r.failureType]),
        format: DtcFormat.uds3,
        failureType: r.failureType,
        statusByte: r.status,
        status: FaultStatus.fromUdsStatusByte(r.status),
        source: ReadSource.uds19,
        readAt: readAt,
        module: module ?? (r.ecuId.isEmpty ? null : r.ecuId),
      );

  /// From the ABS reader's existing [UdsDtcRecord].
  factory FaultRecord.fromUdsDtcRecord(UdsDtcRecord r,
      {required DateTime readAt, String? module}) {
    final two = encodeSae2(r.code) ?? const <int>[0, 0];
    return FaultRecord(
      system: FaultSystem.fromCode(r.code),
      code: r.code,
      rawBytes: List<int>.unmodifiable(<int>[...two, r.failureTypeByte]),
      format: DtcFormat.uds3,
      failureType: r.failureTypeByte,
      statusByte: r.statusByte,
      status: FaultStatus.fromUdsStatusByte(r.statusByte),
      source: ReadSource.uds19,
      readAt: readAt,
      module: module,
    );
  }

  /// From the screen model. An engine code is Mode 03 unless it says it is
  /// pending; a chassis code with a failure type byte is UDS.
  factory FaultRecord.fromDtcCode(DtcCode c, {required DateTime readAt}) {
    final existing = c.record;
    if (existing != null) return existing;
    if (c.isChassis && c.failureTypeByte != null) {
      final two = encodeSae2(c.code) ?? const <int>[0, 0];
      return FaultRecord(
        system: FaultSystem.fromCode(c.code),
        code: c.code.trim().toUpperCase(),
        rawBytes: List<int>.unmodifiable(<int>[...two, c.failureTypeByte!]),
        format: DtcFormat.uds3,
        failureType: c.failureTypeByte,
        statusByte: c.statusByte,
        status: c.statusByte == null
            ? FaultStatus(confirmed: c.isConfirmed)
            : FaultStatus.fromUdsStatusByte(c.statusByte!),
        source: ReadSource.uds19,
        readAt: readAt,
      );
    }
    return FaultRecord.fromObdCode(c.code,
        source: c.isPending ? ReadSource.mode07 : ReadSource.mode03,
        readAt: readAt);
  }

  /// A code entered by hand from a manual (hex-H) or counted from a lamp
  /// (blink). No status is known.
  factory FaultRecord.manual(String code,
      {required DtcFormat format, required DateTime readAt}) {
    final c = code.trim().toUpperCase();
    return FaultRecord(
      system: format == DtcFormat.blink ? null : FaultSystem.fromCode(c),
      code: c,
      rawBytes: List<int>.unmodifiable(encodeSae2(c) ?? const <int>[]),
      format: format,
      status: FaultStatus.unknown,
      source: ReadSource.manual,
      readAt: readAt,
    );
  }

  FaultRecord _mergedWith(FaultRecord other) => FaultRecord(
        system: system,
        code: code,
        rawBytes: rawBytes,
        format: format,
        failureType: failureType,
        statusByte: statusByte ?? other.statusByte,
        status: status.merge(other.status),
        source: source,
        readAt: readAt,
        module: module ?? other.module,
        sources: <ReadSource>{...sources, ...other.sources},
      );
}

/// One record per code from the engine's Mode 03 ([stored]), 07 ([pending])
/// and 0A ([permanent]) answers, in that order of first appearance. Statuses
/// are combined with [FaultStatus.merge]; nothing is inferred from a code's
/// absence from a list.
List<FaultRecord> mergeEngineRecords({
  required List<FaultRecord> stored,
  required List<FaultRecord> pending,
  required List<FaultRecord> permanent,
}) {
  final byKey = <String, FaultRecord>{};
  for (final r in [...stored, ...pending, ...permanent]) {
    final existing = byKey[r.key];
    byKey[r.key] = existing == null ? r : existing._mergedWith(r);
  }
  return List<FaultRecord>.unmodifiable(byKey.values);
}
