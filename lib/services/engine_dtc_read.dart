/// Danlite ELM — what an engine fault-code read actually established.
///
/// The engine read used to return a bare `List<DtcCode>`, and an empty list
/// meant two opposite things: "the engine computer answered and has no stored
/// faults" and "nothing answered at all". The screen could not tell them apart
/// and told a rider whose bike never replied — ignition off, wrong connector,
/// a bike the adapter cannot talk to — "No Fault Codes Found. Great news!".
///
/// [EngineDtcRead] makes that confusion impossible to express. An empty list
/// exists ONLY inside [EngineAnswered], and [classifyEngineDtcReply] produces
/// [EngineAnswered] ONLY for a syntactically valid positive Mode 03 response
/// (service byte `43`), including the valid zero-code reply `43 00`.
library;

import '../constants/obd_pids.dart';
import '../models/vehicle_data.dart';
import 'fault_decoders.dart' show Vin;

/// K-line fault-code reading is switched OFF.
///
/// The Mode 03 parser was built for CAN and is confirmed to mis-decode K-line
/// replies (a single P0133 decodes as P3300, and a headers-on checksum byte
/// becomes a phantom code — FAULT_SYSTEM_AUDIT.md, Additions #8). Until it is
/// fixed, an ISO 9141-2 or ISO 14230-4 bike is shown an honest "not switched on
/// yet" message instead of codes that might be wrong. Live data is unaffected.
///
/// Enable this ONLY after the parser passes fixtures recorded from real K-line
/// bikes (the tester-mode session recorder exists to collect them).
const bool kKLineFaultReadingEnabled = false;

/// The bus family the adapter settled on, from `ATDPN`.
enum ObdProtocolFamily {
  /// `ATDPN` not read yet, unanswered, or still `0` (automatic, undetermined).
  unknown,

  /// SAE J1850 PWM / VPW (1, 2). Cars only; listed for completeness.
  j1850,

  /// ISO 9141-2 (3) and ISO 14230-4 KWP2000 5-baud / fast init (4, 5).
  kLine,

  /// ISO 15765-4 CAN, 11- or 29-bit, 500 or 250 kbit (6–9).
  can,

  /// SAE J1939 (A) and user-defined CAN (B, C).
  other,
}

/// The adapter's protocol answer, kept for the session.
class ObdProtocol {
  /// Exactly what `ATDPN` returned, trimmed (e.g. `A6`, `3`). Null when never
  /// asked or when the adapter gave no usable reply.
  final String? raw;

  /// The protocol digit, without the `A` (automatic) prefix.
  final String? number;

  final ObdProtocolFamily family;

  const ObdProtocol._(this.raw, this.number, this.family);

  static const ObdProtocol unknown =
      ObdProtocol._(null, null, ObdProtocolFamily.unknown);

  /// Parse an `ATDPN` reply.
  ///
  /// The ELM327 answers with one protocol character, prefixed by `A` when the
  /// protocol was reached by automatic search: `A6` is ISO 15765-4 CAN 11-bit
  /// 500k found automatically, `3` is ISO 9141-2 set explicitly. Protocol `A`
  /// itself (J1939) therefore reads `A` or `AA`. Anything that is not one of
  /// those shapes — an error, `?`, a timeout — is [unknown], never guessed.
  factory ObdProtocol.fromAtdpn(String reply) {
    final cleaned = reply.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final m = RegExp(r'^A?([0-9A-C])$').firstMatch(cleaned);
    if (m == null) return unknown;
    final n = m.group(1)!;
    final ObdProtocolFamily family;
    switch (n) {
      case '0':
        family = ObdProtocolFamily.unknown;
        break;
      case '1':
      case '2':
        family = ObdProtocolFamily.j1850;
        break;
      case '3':
      case '4':
      case '5':
        family = ObdProtocolFamily.kLine;
        break;
      case '6':
      case '7':
      case '8':
      case '9':
        family = ObdProtocolFamily.can;
        break;
      default:
        family = ObdProtocolFamily.other;
    }
    return ObdProtocol._(cleaned, n, family);
  }

  bool get isKLine => family == ObdProtocolFamily.kLine;
  bool get isKnown => family != ObdProtocolFamily.unknown;

  @override
  String toString() => raw ?? 'unknown';
}

/// One adapter connection, from connect to disconnect.
class ObdSession {
  ObdSession({required this.transport, DateTime? startedAt})
      : startedAt = startedAt ?? DateTime.now();

  /// `bluetooth` or `wifi`.
  final String transport;
  final DateTime startedAt;

  /// The adapter's own identity line from `ATZ` (e.g. `ELM327 v1.5`).
  String? adapterIdentity;

  /// What `ATDPN` reported most recently.
  ObdProtocol protocol = ObdProtocol.unknown;

  /// True once the VEHICLE — not merely the adapter — has given a positive
  /// reply: `41 00` to the supported-PIDs request, any later positive live PID
  /// reply, or a positive Mode 03 answer. Adapter set-up commands answering
  /// `OK` prove nothing about the bike and never set this.
  bool vehicleAnswered = false;

  /// True once a "response pending" frame (`7F xx 78`) reached the app: this
  /// adapter passes them through instead of waiting internally, so a read
  /// that gets one must be repeated to get the answer. Learned from what the
  /// adapter does, never from its version string (clones misreport it).
  bool adapterPassesPending = false;

  /// The vehicle's VIN, read from Mode 09 PID 02 and validated. Memory only,
  /// for this connection: never logged unmasked, never stored, never sent.
  /// [Vin.toString] is masked.
  Vin? vin;

  /// Calibration IDs from Mode 09 PID 04. Memory only, like [vin].
  List<String>? calibrationIds;

  /// Mode 09 was asked and this vehicle does not offer it; not asked again in
  /// this session.
  bool vehicleInfoUnsupported = false;
}

/// Why a read produced no fault data. Never shown as "no faults".
enum EngineNoAnswerReason {
  /// The adapter said `NO DATA`: it asked, and no module replied.
  noData,

  /// Nothing came back inside the window, on a link otherwise alive.
  timeout,

  /// A bare prompt with no payload.
  emptyReply,

  /// `UNABLE TO CONNECT`: automatic protocol search found no bus.
  unableToConnect,

  /// `BUS INIT: ERROR` / `BUS INIT: ...`: K-line wake-up failed.
  busInit,

  /// `CAN ERROR`, `BUS ERROR`, `BUS BUSY`, `DATA ERROR`, `RX ERROR`…
  busError,

  /// `?` — the adapter did not accept the request.
  adapterRejected,

  /// `STOPPED`, `BUFFER FULL` and other adapter-side conditions.
  adapterError,

  /// Only `SEARCHING...` came back.
  searching,

  /// Bytes came back but not a positive Mode 03 answer.
  unrecognised,

  /// The engine computer kept answering "response pending" (`7F 03 78`) and
  /// never sent its answer within the time allowed.
  moduleBusy,
}

/// The result of one engine fault-code read.
sealed class EngineDtcRead {
  const EngineDtcRead(this.at);

  /// When the read finished.
  final DateTime at;
}

/// The engine computer gave a valid positive Mode 03 response. [codes] may be
/// empty — and this is the ONLY place an empty list means "no stored faults".
final class EngineAnswered extends EngineDtcRead {
  const EngineAnswered(this.codes, DateTime at) : super(at);
  final List<DtcCode> codes;
}

/// Nothing usable came back from the vehicle. This does not mean there are no
/// faults.
final class EngineNoAnswer extends EngineDtcRead {
  const EngineNoAnswer(this.reason, DateTime at) : super(at);
  final EngineNoAnswerReason reason;
}

/// The engine computer answered with a negative response (`7F 03 xx`).
final class EngineRefused extends EngineDtcRead {
  const EngineRefused(this.nrc, DateTime at) : super(at);

  /// The negative response code, when one could be read.
  final int? nrc;
}

/// The adapter link itself failed during the read.
final class EngineLinkLost extends EngineDtcRead {
  const EngineLinkLost(DateTime at) : super(at);
}

/// The bike speaks K-line, and K-line fault reading is switched off
/// ([kKLineFaultReadingEnabled]). Nothing was parsed or shown.
final class EngineKLineGated extends EngineDtcRead {
  const EngineKLineGated(this.protocol, DateTime at) : super(at);
  final ObdProtocol protocol;
}

/// How [classifyEngineDtcReply] judged a raw Mode 03 reply, before any code
/// text is attached.
sealed class EngineReplyVerdict {
  const EngineReplyVerdict();
}

final class ReplyPositive extends EngineReplyVerdict {
  const ReplyPositive(this.parsed);
  final DtcParseResult parsed;
}

final class ReplyNoAnswer extends EngineReplyVerdict {
  const ReplyNoAnswer(this.reason);
  final EngineNoAnswerReason reason;
}

final class ReplyRefused extends EngineReplyVerdict {
  const ReplyRefused(this.nrc);
  final int? nrc;
}

final class ReplyLinkLost extends EngineReplyVerdict {
  const ReplyLinkLost();
}

/// Judge one raw Mode 03 reply.
///
/// [reply] is the sanitised adapter text, or one of the service's synthetic
/// markers (`TIMEOUT`, `DISCONNECTED`, `ERROR`). [linkFailed] is the service's
/// own verdict on the link for that reply ([ObdReplyClass.linkFailure]).
///
/// Order matters and is deliberately conservative: a positive `43` response
/// anywhere in the reply wins (a leading `SEARCHING...` line is normal on the
/// first request after power-up); otherwise a negative response is a refusal;
/// otherwise every adapter error or silence is "no answer". Nothing that is
/// not a positive response can ever become an empty fault list.
///
/// [countByteMode] comes from the bus: on ISO 15765-4 CAN the response byte is
/// always followed by a count of codes ([DtcCountByteMode.present]); when the
/// protocol is not known the parser's original auto-detection is used.
EngineReplyVerdict classifyEngineDtcReply(String reply,
    {required bool linkFailed,
    DtcCountByteMode countByteMode = DtcCountByteMode.auto}) {
  final upper = reply.toUpperCase().trim();

  if (linkFailed) return const ReplyLinkLost();
  if (upper == 'DISCONNECTED' || upper == 'ERROR') return const ReplyLinkLost();
  if (upper == 'TIMEOUT') {
    return const ReplyNoAnswer(EngineNoAnswerReason.timeout);
  }
  if (upper.isEmpty) return const ReplyNoAnswer(EngineNoAnswerReason.emptyReply);

  final parsed = ObdParser.parseDetailed(joinSpacedTwentyNineBitHeaders(reply),
      countByteMode: countByteMode);
  if (parsed.positiveResponseSeen) return ReplyPositive(parsed);

  final nrc = _negativeResponseTo03(upper);
  if (nrc != null) return ReplyRefused(nrc < 0 ? null : nrc);

  final compact = upper.replaceAll(RegExp(r'\s+'), ' ');
  if (compact.contains('NO DATA') || compact.contains('NODATA')) {
    return const ReplyNoAnswer(EngineNoAnswerReason.noData);
  }
  if (compact.contains('UNABLE TO CONNECT')) {
    return const ReplyNoAnswer(EngineNoAnswerReason.unableToConnect);
  }
  if (compact.contains('BUS INIT') || compact.contains('BUSINIT')) {
    return const ReplyNoAnswer(EngineNoAnswerReason.busInit);
  }
  if (compact.contains('CAN ERROR') ||
      compact.contains('BUS ERROR') ||
      compact.contains('BUS BUSY') ||
      compact.contains('DATA ERROR') ||
      compact.contains('RX ERROR') ||
      compact.contains('FB ERROR')) {
    return const ReplyNoAnswer(EngineNoAnswerReason.busError);
  }
  if (compact.contains('STOPPED') ||
      compact.contains('BUFFER FULL') ||
      compact.contains('LV RESET') ||
      compact.contains('ERR')) {
    return const ReplyNoAnswer(EngineNoAnswerReason.adapterError);
  }
  if (compact.split(RegExp(r'[\r\n ]+')).every((t) => t == '?' || t.isEmpty)) {
    return const ReplyNoAnswer(EngineNoAnswerReason.adapterRejected);
  }
  if (compact.contains('?')) {
    return const ReplyNoAnswer(EngineNoAnswerReason.adapterRejected);
  }
  if (compact.contains('SEARCHING')) {
    return const ReplyNoAnswer(EngineNoAnswerReason.searching);
  }
  return const ReplyNoAnswer(EngineNoAnswerReason.unrecognised);
}

/// Rewrites a 29-bit CAN response header printed with spaces on
/// (`18 DA F1 10 …`, as the engine read's `ATS1 ATH1` produces) into the
/// single 8-character token (`18DAF110 …`) the shared frame tokenizer already
/// recognises as a header. Without this the header bytes are read as data,
/// the reply never looks like a positive response, and a 29-bit engine ECU
/// that did answer would be reported as not answering.
///
/// Done here, for the engine read only, so the tokenizer the ABS scan also
/// uses is left exactly as it is.
String joinSpacedTwentyNineBitHeaders(String reply) => reply.replaceAllMapped(
      RegExp(r'(^|[\r\n])([ \t]*)18 DA ([0-9A-F]{2}) ([0-9A-F]{2})(?= )',
          caseSensitive: false),
      (m) => '${m[1]}${m[2]}18DA${m[3]}${m[4]}',
    );

/// Finds a negative response to service 0x03 (`7F 03 <nrc>`) on real byte
/// boundaries, line by line. Returns the NRC, -1 when the NRC byte is missing,
/// or null when there is no negative response.
int? _negativeResponseTo03(String upper) {
  for (final rawLine in upper.split(RegExp(r'[\r\n]+'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    var tokens = line.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    // Spaces off: one unbroken hex run, optionally led by a 3-nibble header.
    if (tokens.length == 1 && RegExp(r'^[0-9A-F]+$').hasMatch(tokens.first)) {
      final h = tokens.first;
      final start = h.length.isOdd ? 3 : 0;
      tokens = [
        for (var i = start; i + 2 <= h.length; i += 2) h.substring(i, i + 2)
      ];
    }
    for (var i = 0; i + 1 < tokens.length; i++) {
      if (tokens[i] == '7F' && tokens[i + 1] == '03') {
        if (i + 2 < tokens.length) {
          return int.tryParse(tokens[i + 2], radix: 16) ?? -1;
        }
        return -1;
      }
    }
  }
  return null;
}
