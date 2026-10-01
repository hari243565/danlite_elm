/// Danlite ELM — typed decoders for fault-code and vehicle-information replies.
///
/// Every function here is pure, never throws, and returns a typed result. The
/// rule that runs through all of them: an answer the bytes do not actually
/// support is never produced. Odd hex, garbage and a multi-frame reply that
/// stopped short come back as `…Unparseable` or `…Truncated`; silence and
/// `NO DATA` come back as no-data; only a real positive response yields codes
/// — and only a real positive response with no codes yields an empty list.
///
/// Byte layouts: SAE J1979 (Mode 01 / 03 / 07 / 09 / 0A) and ISO 14229-1
/// (UDS `19 02`). Frame tokenising and ISO-TP reassembly are the ones the rest
/// of the app already uses ([ObdParser.reassembleFrames]); the two-byte code
/// unpacking is [ObdParser.decodeDtcPair].
library;

import '../constants/obd_pids.dart';
import 'engine_dtc_read.dart';

// ═══════════════════════════════════════════════════════════════════════════
// UDS DTC status byte (ISO 14229-1, DTCStatusMask)
// ═══════════════════════════════════════════════════════════════════════════

/// One UDS status byte, its eight bits, and the labels the app derives.
class UdsStatusByte {
  UdsStatusByte(int byte) : raw = byte & 0xFF;

  final int raw;

  bool _bit(int n) => (raw >> n) & 1 == 1;

  /// Bit 0 — the most recent test failed.
  bool get testFailed => _bit(0);

  /// Bit 1 — a test failed during this operation cycle.
  bool get testFailedThisOperationCycle => _bit(1);

  /// Bit 2 — pendingDTC.
  bool get pendingDtc => _bit(2);

  /// Bit 3 — confirmedDTC.
  bool get confirmedDtc => _bit(3);

  /// Bit 4 — testNotCompletedSinceLastClear.
  bool get testNotCompletedSinceLastClear => _bit(4);

  /// Bit 5 — testFailedSinceLastClear.
  bool get testFailedSinceLastClear => _bit(5);

  /// Bit 6 — testNotCompletedThisOperationCycle.
  bool get testNotCompletedThisOperationCycle => _bit(6);

  /// Bit 7 — warningIndicatorRequested.
  bool get warningIndicatorRequested => _bit(7);

  // ── Derived labels ──────────────────────────────────────────────────────
  /// "Active": failing on the most recent test (bit 0).
  bool get isActive => testFailed;

  /// "Pending": pendingDTC set and NOT yet confirmed (bit 2 and not bit 3). A
  /// confirmed code is shown as Stored even when its pending bit is also set.
  bool get isPending => pendingDtc && !confirmedDtc;

  /// "Stored": confirmed (bit 3).
  bool get isStored => confirmedDtc;

  /// "History": confirmed but not failing now (bit 3 and not bit 0).
  bool get isHistory => confirmedDtc && !testFailed;

  /// "Lamp": the module asked for the warning lamp (bit 7).
  bool get isLampRequested => warningIndicatorRequested;
}

// ═══════════════════════════════════════════════════════════════════════════
// Failure type byte
// ═══════════════════════════════════════════════════════════════════════════

/// The failure type byte (the `-11` in `C1015-11`), described in plain words.
///
/// Source: public extracts of the SAE J2012-DA failure-type list. THESE
/// ENTRIES MUST BE RE-CHECKED AGAINST THE OFFICIAL J2012-DA ANNEX before they
/// are relied on. Only these 28 values are described; every other value is
/// shown as "failure type 0xNN, no description" — never guessed. English and
/// Hindi are written here; other languages fall back to English, as the rest
/// of the fault text does.
class FailureType {
  FailureType._();

  static const Map<int, List<String>> _table = <int, List<String>>{
    0x00: ['No sub-type', 'कोई उप-प्रकार नहीं'],
    0x02: ['General signal failure', 'सिग्नल में सामान्य खराबी'],
    0x04: ['System internal failure', 'सिस्टम की आंतरिक खराबी'],
    0x05: ['Programming failure', 'प्रोग्रामिंग त्रुटि'],
    0x07: ['Mechanical failure', 'यांत्रिक (मैकेनिकल) खराबी'],
    0x09: ['Component failure', 'कंपोनेंट की खराबी'],
    0x11: ['Circuit short to ground', 'सर्किट ग्राउंड से शॉर्ट'],
    0x12: ['Circuit short to battery supply', 'सर्किट बैटरी सप्लाई से शॉर्ट'],
    0x13: ['Circuit open', 'सर्किट खुला (ओपन)'],
    0x16: ['Circuit voltage below threshold', 'सर्किट वोल्टेज सीमा से कम'],
    0x17: ['Circuit voltage above threshold', 'सर्किट वोल्टेज सीमा से अधिक'],
    0x18: ['Circuit current below threshold', 'सर्किट करंट सीमा से कम'],
    0x19: ['Circuit current above threshold', 'सर्किट करंट सीमा से अधिक'],
    0x1A: ['Circuit resistance above threshold', 'सर्किट प्रतिरोध सीमा से अधिक'],
    0x47: ['Watchdog or safety monitoring failure', 'वॉचडॉग या मॉनिटरिंग विफलता'],
    0x4B: ['Over temperature', 'अत्यधिक तापमान'],
    0x62: ['Signal compare failure', 'सिग्नल तुलना में विफलता'],
    0x64: ['Signal plausibility failure', 'सिग्नल प्लॉज़िबिलिटी विफलता'],
    0x71: ['Actuator stuck', 'एक्चुएटर अटका हुआ'],
    0x72: ['Actuator stuck open', 'एक्चुएटर खुला अटका हुआ'],
    0x73: ['Actuator stuck closed', 'एक्चुएटर बंद अटका हुआ'],
    0x81: ['Invalid serial data received', 'अमान्य सीरियल डेटा मिला'],
    0x85: ['Signal out of range', 'सिग्नल सीमा से बाहर'],
    0x86: ['Invalid CAN signal', 'अमान्य CAN सिग्नल'],
    0x88: ['Bus off', 'बस ऑफ (CAN बस बंद)'],
    0x92: ['Performance or incorrect operation', 'परफ़ॉर्मेंस या गलत संचालन'],
    0x96: ['Component internal failure', 'कंपोनेंट की आंतरिक खराबी'],
    0x97: [
      'Component or system obstructed or blocked',
      'कंपोनेंट या सिस्टम में रुकावट'
    ],
  };

  static Iterable<int> get knownBytes => _table.keys;

  static bool isKnown(int ftb) => _table.containsKey(ftb & 0xFF);

  /// Two-digit upper-case hex, e.g. `0x1A`.
  static String hex(int ftb) =>
      '0x${(ftb & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0')}';

  /// The description in [languageCode] (`hi` gets Hindi, everything else
  /// English), or the explicit "no description" line for any other value.
  static String describe(int ftb, String languageCode) {
    final entry = _table[ftb & 0xFF];
    final hindi = languageCode == 'hi';
    if (entry == null) {
      return hindi
          ? 'फ़ेल्योर टाइप ${hex(ftb)}, कोई विवरण नहीं'
          : 'failure type ${hex(ftb)}, no description';
    }
    return hindi ? entry[1] : entry[0];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared reply handling
// ═══════════════════════════════════════════════════════════════════════════

/// Upper-case the reply, split it on prompts and line breaks, join a spaced
/// 29-bit header into one token, and split a spaces-off line that starts with
/// a 3-digit CAN header (`7E80443…` → `7E8 0443…`) so its bytes stay aligned.
List<String> replyLines(String raw) {
  final lines = <String>[];
  final joined = joinSpacedTwentyNineBitHeaders(
      raw.toUpperCase().replaceAll('>', '\n'));
  for (final rawLine in joined.split(RegExp(r'[\r\n]+'))) {
    var line = rawLine.trim();
    if (line.isEmpty) continue;
    if (!line.contains(' ') &&
        line.length >= 5 &&
        line.length.isOdd &&
        RegExp(r'^[0-9A-F]+$').hasMatch(line)) {
      line = '${line.substring(0, 3)} ${line.substring(3)}';
    }
    lines.add(line);
  }
  return lines;
}

/// The data bytes of one reply line, after any CAN header token: `7E8 03 7F
/// 19 78` → `[03, 7F, 19, 78]`. Empty when the line is not hex.
List<int> lineBytes(String line) {
  var tokens = line.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return const <int>[];
  final hex = RegExp(r'^[0-9A-F]+$');
  if (!tokens.every(hex.hasMatch)) return const <int>[];
  if (tokens.length >= 2 && (tokens.first.length == 3 || tokens.first.length == 8)) {
    tokens = tokens.sublist(1);
  }
  final digits = tokens.join();
  if (digits.length.isOdd) return const <int>[];
  return <int>[
    for (var i = 0; i + 2 <= digits.length; i += 2)
      int.parse(digits.substring(i, i + 2), radix: 16),
  ];
}

/// Is this one line a "request received, response pending" frame —
/// `7F <service> 78` — optionally after a CAN header and a single-frame PCI
/// byte? [serviceId] null matches any service.
bool isResponsePendingLine(String line, {int? serviceId}) {
  final b = lineBytes(line);
  var i = 0;
  if (b.length >= 4 && (b[0] >> 4) == 0 && b[1] == 0x7F) i = 1;
  if (b.length < i + 3 || b[i] != 0x7F || b[i + 2] != 0x78) return false;
  return serviceId == null || b[i + 1] == serviceId;
}

/// Adapter chatter that can share a reply with data. Mirrors the markers the
/// shared tokenizer already ignores.
const List<String> _chatterMarkers = <String>[
  'SEARCHING', 'NO DATA', 'NODATA', 'UNABLE', 'STOPPED', 'BUS INIT', 'BUSINIT',
  'BUS ERROR', 'BUS BUSY', 'CAN ERROR', 'DATA ERROR', 'BUFFER FULL', 'RX ERROR',
  'FB ERROR', 'LP ALERT', 'LV RESET', 'ACT ALERT', 'ERR', 'ELM327', 'OBDII',
  'OK', '?',
];

final RegExp _hexToken = RegExp(r'^[0-9A-F]+$');
final RegExp _indexedLine = RegExp(r'^[0-9A-F]{1,2}:\s*([0-9A-F]{2}\s*)*$');

/// Is [line] something an adapter actually prints as data? Every token hex;
/// with several tokens, an optional 3- or 8-digit header first and two-digit
/// bytes after it (or one unbroken run with spaces off); or the ELM numbered
/// form `0: 49 02 01 …`.
bool _isDataLine(String line) {
  if (_indexedLine.hasMatch(line)) return true;
  final tokens = line.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty || !tokens.every(_hexToken.hasMatch)) return false;
  if (tokens.length == 1) return true;
  final rest = (tokens.first.length == 3 || tokens.first.length == 8)
      ? tokens.sublist(1)
      : tokens;
  return rest.every((t) => t.length.isEven);
}

/// The reply with every response-pending line removed, plus whether there
/// was one. The rest of the reply — the real answer, when it is already in the
/// same buffer — is returned for the normal decoder.
///
/// Lines that are neither data nor recognised adapter chatter (a stray
/// character inside a hex run, a byte split across tokens) are dropped and
/// reported as [garbage], so they can never be stitched into a response: the
/// shared tokenizer would otherwise strip the stray character and read what is
/// left as hex.
({String rest, bool sawPending, bool onlyPending, bool garbage})
    stripResponsePending(String raw, int serviceId) {
  final kept = <String>[];
  var pending = false;
  var garbage = false;
  var dataLines = 0;
  for (final line in replyLines(raw)) {
    if (isResponsePendingLine(line, serviceId: serviceId)) {
      pending = true;
      continue;
    }
    if (_isDataLine(line)) {
      dataLines++;
      kept.add(line);
    } else if (_chatterMarkers.any(line.contains)) {
      kept.add(line);
    } else {
      garbage = true;
    }
  }
  return (
    rest: kept.join('\n'),
    sawPending: pending,
    onlyPending: pending && dataLines == 0,
    garbage: garbage,
  );
}

bool _mentions(String raw, String marker) =>
    raw.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').contains(marker);

bool _isNoDataReply(String raw) =>
    _mentions(raw, 'NO DATA') || _mentions(raw, 'NODATA');

/// The app's synthetic markers and adapter-level failures that mean "nothing
/// was heard", as distinct from a module saying "not supported" (`NO DATA`,
/// or a negative response with a not-supported code).
bool isSilentReply(String raw) {
  final t = raw.trim().toUpperCase();
  return t.isEmpty ||
      t == 'TIMEOUT' ||
      t == 'DISCONNECTED' ||
      t == 'ERROR' ||
      _mentions(raw, 'UNABLE TO CONNECT') ||
      _mentions(raw, 'BUS INIT') ||
      _mentions(raw, 'CAN ERROR') ||
      _mentions(raw, 'BUS ERROR') ||
      _mentions(raw, 'STOPPED');
}

/// Negative response codes that mean "this module does not do that": service
/// not supported (0x11), sub-function not supported (0x12), request out of
/// range (0x31 — a PID the module does not implement).
bool isNotSupportedNrc(int nrc) => nrc == 0x11 || nrc == 0x12 || nrc == 0x31;

/// The first `7F <service> <nrc>` at the start of a module's payload.
int? _negativeIn(List<EcuPayload> payloads, int serviceId) {
  for (final p in payloads) {
    final b = p.bytes;
    if (b.length >= 3 && b[0] == 0x7F && b[1] == serviceId) return b[2];
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// OBD Mode 03 / 07 / 0A
// ═══════════════════════════════════════════════════════════════════════════

/// How codes are laid out inside a Mode 03 / 07 / 0A reply.
enum DtcFraming {
  /// ISO 15765-4 CAN: the response byte is followed by a count of codes.
  iso15765,

  /// ISO 9141-2 / 14230-4 / J1850: no count byte; every frame repeats the
  /// response byte and carries three code slots, unused ones `00 00`; with
  /// headers on, a 3-byte header in front and a checksum byte at the end.
  legacy,

  /// Protocol not known: fall back to the original auto-detecting parser.
  unknown,
}

/// The framing for a bus, from its `ATDPN` answer.
DtcFraming framingFor(ObdProtocol protocol) {
  switch (protocol.family) {
    case ObdProtocolFamily.can:
      return DtcFraming.iso15765;
    case ObdProtocolFamily.kLine:
    case ObdProtocolFamily.j1850:
      return DtcFraming.legacy;
    case ObdProtocolFamily.unknown:
    case ObdProtocolFamily.other:
      return DtcFraming.unknown;
  }
}

/// One two-byte code and where it came from.
class DecodedObdDtc {
  const DecodedObdDtc(this.code, this.high, this.low, this.ecuId);
  final String code;
  final int high;
  final int low;

  /// Responding module's CAN header, or empty when headers were off.
  final String ecuId;
}

sealed class ObdDtcDecode {
  const ObdDtcDecode();
}

/// A positive response. [codes] may be empty: that is "no codes of this kind".
final class ObdDtcCodes extends ObdDtcDecode {
  const ObdDtcCodes(this.codes, {this.reportedCount, this.sawPending = false});
  final List<DecodedObdDtc> codes;

  /// The count byte(s), summed across modules, on CAN. Null on K-line.
  final int? reportedCount;

  /// A response-pending frame came first in the same buffer.
  final bool sawPending;

  bool get countMismatch =>
      reportedCount != null && reportedCount != codes.length;
}

/// `7F <service> <nrc>`.
final class ObdDtcNegative extends ObdDtcDecode {
  const ObdDtcNegative(this.nrc);
  final int nrc;
}

/// `NO DATA`, silence, or only adapter chatter.
final class ObdDtcNoData extends ObdDtcDecode {
  const ObdDtcNoData();
}

/// A positive response that stopped short; [partial] is what did arrive.
final class ObdDtcTruncated extends ObdDtcDecode {
  const ObdDtcTruncated(this.partial);
  final List<DecodedObdDtc> partial;
}

final class ObdDtcUnparseable extends ObdDtcDecode {
  const ObdDtcUnparseable(this.reason);
  final String reason;
}

/// Decode a reply to OBD service [service] (0x03, 0x07 or 0x0A).
ObdDtcDecode decodeObdDtcReply(String? raw,
    {required int service, required DtcFraming framing}) {
  try {
    if (raw == null || isSilentReply(raw)) return const ObdDtcNoData();
    final stripped = stripResponsePending(raw, service);
    if (stripped.onlyPending) return const ObdDtcNegative(0x78);
    final body = stripped.rest;
    final result = switch (framing) {
      DtcFraming.legacy => _decodeLegacy(body, service, stripped.sawPending),
      DtcFraming.iso15765 => _decodeIso15765(body, service, stripped.sawPending),
      DtcFraming.unknown => _decodeAuto(body, service, stripped.sawPending),
    };
    if (result is ObdDtcNoData && stripped.garbage) {
      return const ObdDtcUnparseable('unreadable characters in reply');
    }
    return result;
  } catch (e) {
    return ObdDtcUnparseable('decoder error: ${e.runtimeType}');
  }
}

ObdDtcDecode _decodeIso15765(String body, int service, bool sawPending) {
  final positiveSid = service + 0x40;
  final frames = ObdParser.reassembleFrames(body);
  if (frames.oddLength) return const ObdDtcUnparseable('odd number of hex digits');
  if (frames.failed) return const ObdDtcUnparseable('frames could not be read');

  final codes = <DecodedObdDtc>[];
  final seen = <String>{};
  int? reported;
  var positive = false;
  var truncated = false;

  for (final p in frames.payloads) {
    final b = p.bytes;
    if (b.isEmpty || b[0] != positiveSid) continue;
    positive = true;
    if (p.truncated) truncated = true;
    if (b.length < 2) {
      // The response byte with no count byte at all.
      truncated = true;
      continue;
    }
    reported = (reported ?? 0) + b[1];
    var data = b.sublist(2);
    if (data.length.isOdd) {
      if (data.last != 0x00) {
        return const ObdDtcUnparseable('odd number of code bytes');
      }
      data = data.sublist(0, data.length - 1); // one byte of padding
    }
    for (var i = 0; i + 2 <= data.length; i += 2) {
      final code = ObdParser.decodeDtcPair(data[i], data[i + 1]);
      if (code == null) continue; // 00 00 padding
      if (seen.add(code)) codes.add(DecodedObdDtc(code, data[i], data[i + 1], p.ecuId));
    }
  }

  if (positive) {
    if (truncated) return ObdDtcTruncated(List.unmodifiable(codes));
    return ObdDtcCodes(List.unmodifiable(codes),
        reportedCount: reported, sawPending: sawPending);
  }
  final nrc = _negativeIn(frames.payloads, service);
  if (nrc != null) return ObdDtcNegative(nrc);
  if (frames.payloads.isEmpty) return const ObdDtcNoData();
  if (_isNoDataReply(body)) return const ObdDtcNoData();
  return const ObdDtcUnparseable('no positive response');
}

ObdDtcDecode _decodeLegacy(String body, int service, bool sawPending) {
  final positiveSid = service + 0x40;
  final codes = <DecodedObdDtc>[];
  final seen = <String>{};
  var positive = false;
  int? nrc;
  var sawBytes = false;

  for (final line in replyLines(body)) {
    final tokens = line.split(RegExp(r'\s+'));
    final digits = tokens.join();
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(digits)) continue; // chatter
    if (digits.length.isOdd) {
      return const ObdDtcUnparseable('odd number of hex digits');
    }
    final b = <int>[
      for (var i = 0; i + 2 <= digits.length; i += 2)
        int.parse(digits.substring(i, i + 2), radix: 16),
    ];
    if (b.isEmpty) continue;
    sawBytes = true;

    List<int>? data;
    if (b[0] == positiveSid) {
      data = b.sublist(1);
    } else if (b.length >= 5 && b[3] == positiveSid) {
      // Headers on: 3-byte header, the frame, then a checksum byte.
      data = b.sublist(4, b.length - 1);
    } else if (b.length >= 3 && b[0] == 0x7F && b[1] == service) {
      nrc ??= b[2];
      continue;
    } else if (b.length >= 6 && b[3] == 0x7F && b[4] == service) {
      nrc ??= b[5];
      continue;
    } else {
      continue;
    }
    positive = true;
    if (data.length.isOdd) {
      if (data.last != 0x00) {
        return const ObdDtcUnparseable('odd number of code bytes');
      }
      data = data.sublist(0, data.length - 1);
    }
    for (var i = 0; i + 2 <= data.length; i += 2) {
      final code = ObdParser.decodeDtcPair(data[i], data[i + 1]);
      if (code == null) continue;
      if (seen.add(code)) codes.add(DecodedObdDtc(code, data[i], data[i + 1], ''));
    }
  }

  if (positive) {
    return ObdDtcCodes(List.unmodifiable(codes), sawPending: sawPending);
  }
  if (nrc != null) return ObdDtcNegative(nrc);
  if (!sawBytes || _isNoDataReply(body)) return const ObdDtcNoData();
  return const ObdDtcUnparseable('no positive response');
}

ObdDtcDecode _decodeAuto(String body, int service, bool sawPending) {
  final frames = ObdParser.reassembleFrames(body);
  if (frames.oddLength) return const ObdDtcUnparseable('odd number of hex digits');
  final parsed = ObdParser.parseDetailed(body);
  if (parsed.positiveResponseSeen) {
    return ObdDtcCodes(
      <DecodedObdDtc>[
        for (final code in parsed.allCodes) DecodedObdDtc(code, -1, -1, ''),
      ],
      reportedCount: parsed.reportedCount,
      sawPending: sawPending,
    );
  }
  final nrc = _negativeIn(frames.payloads, service);
  if (nrc != null) return ObdDtcNegative(nrc);
  if (frames.payloads.isEmpty || _isNoDataReply(body)) return const ObdDtcNoData();
  return const ObdDtcUnparseable('no positive response');
}

// ═══════════════════════════════════════════════════════════════════════════
// UDS 19 02 — reportDTCByStatusMask
// ═══════════════════════════════════════════════════════════════════════════

/// One four-byte UDS record: DTC high, DTC mid, failure type, status.
class Uds19Record {
  const Uds19Record({
    required this.code,
    required this.dtcHigh,
    required this.dtcMid,
    required this.failureType,
    required this.status,
    required this.ecuId,
  });
  final String code;
  final int dtcHigh;
  final int dtcMid;
  final int failureType;
  final int status;
  final String ecuId;

  UdsStatusByte get statusBits => UdsStatusByte(status);
}

sealed class Uds19Decode {
  const Uds19Decode();
}

/// A positive `59 02` response. [records] may be empty: the module answered
/// and holds no codes matching the mask.
final class Uds19Records extends Uds19Decode {
  const Uds19Records(this.records,
      {required this.availabilityMask, this.sawPending = false});
  final List<Uds19Record> records;
  final int? availabilityMask;
  final bool sawPending;
}

final class Uds19Negative extends Uds19Decode {
  const Uds19Negative(this.nrc);
  final int nrc;
}

final class Uds19NoData extends Uds19Decode {
  const Uds19NoData();
}

final class Uds19Truncated extends Uds19Decode {
  const Uds19Truncated(this.partial);
  final List<Uds19Record> partial;
}

final class Uds19Unparseable extends Uds19Decode {
  const Uds19Unparseable(this.reason);
  final String reason;
}

/// Decode a reply to `19 02 <mask>`.
Uds19Decode decodeUds19Reply(String? raw) {
  try {
    if (raw == null || isSilentReply(raw)) return const Uds19NoData();
    final stripped = stripResponsePending(raw, 0x19);
    if (stripped.onlyPending) return const Uds19Negative(0x78);
    final frames = ObdParser.reassembleFrames(stripped.rest);
    if (frames.oddLength) return const Uds19Unparseable('odd number of hex digits');

    final records = <Uds19Record>[];
    final seen = <String>{};
    var positive = false;
    var truncated = false;
    int? mask;
    var wrongSubFunction = false;

    for (final p in frames.payloads) {
      final b = p.bytes;
      if (b.isEmpty || b[0] != ObdParser.udsReadDtcResponseByte) continue;
      if (b.length < 2 || b[1] != ObdParser.udsReportDtcByStatusMask) {
        wrongSubFunction = true;
        continue;
      }
      positive = true;
      if (p.truncated) truncated = true;
      if (b.length < 3) continue; // no mask byte: tolerated, no records
      mask ??= b[2];
      var cursor = 3;
      while (cursor + 4 <= b.length) {
        final hi = b[cursor], mid = b[cursor + 1], ftb = b[cursor + 2], st = b[cursor + 3];
        cursor += 4;
        if (hi == 0 && mid == 0 && ftb == 0) continue; // padding record
        final code = ObdParser.decodeDtcPair(hi, mid);
        if (code == null) continue;
        if (!seen.add('$code-$ftb-${p.ecuId}')) continue;
        records.add(Uds19Record(
            code: code, dtcHigh: hi, dtcMid: mid, failureType: ftb, status: st, ecuId: p.ecuId));
      }
      final tail = b.sublist(cursor);
      if (tail.any((x) => x != 0)) truncated = true; // a partial record
    }

    if (positive) {
      if (truncated) return Uds19Truncated(List.unmodifiable(records));
      return Uds19Records(List.unmodifiable(records),
          availabilityMask: mask, sawPending: stripped.sawPending);
    }
    final nrc = _negativeIn(frames.payloads, 0x19);
    if (nrc != null) return Uds19Negative(nrc);
    if (wrongSubFunction) return const Uds19Unparseable('unexpected sub-function');
    if (stripped.garbage) {
      return const Uds19Unparseable('unreadable characters in reply');
    }
    if (_isNoDataReply(stripped.rest)) return const Uds19NoData();
    if (frames.payloads.isEmpty) {
      return _onlyChatter(stripped.rest)
          ? const Uds19NoData()
          : const Uds19Unparseable('no usable bytes');
    }
    return const Uds19Unparseable('no positive response');
  } catch (e) {
    return Uds19Unparseable('decoder error: ${e.runtimeType}');
  }
}

/// True when every line is adapter chatter (SEARCHING, OK, ELM327 …).
bool _onlyChatter(String raw) {
  const markers = <String>[
    'SEARCHING', 'NO DATA', 'NODATA', 'OK', 'ELM327', 'OBDII', 'STOPPED', '?',
  ];
  for (final line in replyLines(raw)) {
    if (!markers.any(line.contains)) return false;
  }
  return true;
}

// ═══════════════════════════════════════════════════════════════════════════
// Small typed results for Mode 01 / AT RV / Mode 09
// ═══════════════════════════════════════════════════════════════════════════

sealed class Decoded<T> {
  const Decoded();
}

final class DecodedValue<T> extends Decoded<T> {
  const DecodedValue(this.value);
  final T value;
}

/// The vehicle (or adapter) does not provide this: `NO DATA`, `?`, or a
/// negative response meaning "not supported". Never a failure, never empty.
final class DecodedUnsupported<T> extends Decoded<T> {
  const DecodedUnsupported([this.nrc]);
  final int? nrc;
}

/// A negative response that is not "not supported" (busy, conditions not
/// correct, security…).
final class DecodedNegative<T> extends Decoded<T> {
  const DecodedNegative(this.nrc);
  final int nrc;
}

/// Nothing was heard: timeout, link failure, bus error.
final class DecodedNoAnswer<T> extends Decoded<T> {
  const DecodedNoAnswer(this.reason);
  final String reason;
}

final class DecodedUnparseable<T> extends Decoded<T> {
  const DecodedUnparseable(this.reason);
  final String reason;
}

/// Decode a Mode 01 (or 09) reply for [pid]: the data bytes after `41 <pid>`
/// from every module that answered, in order. Shared by the PID decoders.
Decoded<List<List<int>>> _decodeServicePid(String? raw,
    {required int service, required int pid, required int minBytes}) {
  try {
    if (raw == null || isSilentReply(raw)) {
      return DecodedNoAnswer<List<List<int>>>(
          raw == null || raw.trim().isEmpty ? 'empty' : raw.trim());
    }
    final stripped = stripResponsePending(raw, service);
    if (stripped.onlyPending) return const DecodedNegative<List<List<int>>>(0x78);
    final body = stripped.rest;
    final frames = ObdParser.reassembleFrames(body);
    if (frames.oddLength) {
      return const DecodedUnparseable<List<List<int>>>('odd number of hex digits');
    }
    final found = <List<int>>[];
    var short = false;
    for (final p in frames.payloads) {
      final b = p.bytes;
      if (b.length < 2 || b[0] != service + 0x40 || b[1] != pid) continue;
      final data = b.sublist(2);
      if (data.length < minBytes || p.truncated) {
        short = true;
        continue;
      }
      found.add(data);
    }
    if (found.isNotEmpty) return DecodedValue<List<List<int>>>(found);
    if (short) return const DecodedUnparseable<List<List<int>>>('reply too short');
    final nrc = _negativeIn(frames.payloads, service);
    if (nrc != null) {
      return isNotSupportedNrc(nrc)
          ? DecodedUnsupported<List<List<int>>>(nrc)
          : DecodedNegative<List<List<int>>>(nrc);
    }
    if (stripped.garbage) {
      return const DecodedUnparseable<List<List<int>>>(
          'unreadable characters in reply');
    }
    if (_isNoDataReply(body) || body.trim() == '?') {
      return const DecodedUnsupported<List<List<int>>>();
    }
    return const DecodedUnparseable<List<List<int>>>('no positive response');
  } catch (e) {
    return DecodedUnparseable<List<List<int>>>('decoder error: ${e.runtimeType}');
  }
}

Decoded<R> _map<R>(Decoded<List<List<int>>> d, R Function(List<List<int>>) f) {
  switch (d) {
    case DecodedValue(:final value):
      return DecodedValue<R>(f(value));
    case DecodedUnsupported(:final nrc):
      return DecodedUnsupported<R>(nrc);
    case DecodedNegative(:final nrc):
      return DecodedNegative<R>(nrc);
    case DecodedNoAnswer(:final reason):
      return DecodedNoAnswer<R>(reason);
    case DecodedUnparseable(:final reason):
      return DecodedUnparseable<R>(reason);
  }
}

/// PID 01 01: byte A bit 7 = warning lamp (MIL) on, bits 0–6 = stored codes.
class MilStatus {
  const MilStatus({required this.lampOn, required this.storedCount});
  final bool lampOn;

  /// Confirmed codes the module(s) say they hold, summed across modules.
  final int storedCount;
}

Decoded<MilStatus> decodeMilStatus(String? raw) => _map(
      _decodeServicePid(raw, service: 0x01, pid: 0x01, minBytes: 1),
      (all) => MilStatus(
        lampOn: all.any((d) => d[0] & 0x80 != 0),
        storedCount: all.fold<int>(0, (sum, d) => sum + (d[0] & 0x7F)),
      ),
    );

/// PID 01 0C: RPM = (256A + B) / 4. The first module that answered.
Decoded<double> decodeRpm(String? raw) => _map(
      _decodeServicePid(raw, service: 0x01, pid: 0x0C, minBytes: 2),
      (all) => (all.first[0] * 256 + all.first[1]) / 4.0,
    );

/// PID 01 42: control module voltage = (256A + B) / 1000 volts.
Decoded<double> decodeModuleVoltage(String? raw) => _map(
      _decodeServicePid(raw, service: 0x01, pid: 0x42, minBytes: 2),
      (all) => (all.first[0] * 256 + all.first[1]) / 1000.0,
    );

/// `ATRV`: the adapter's own reading of the connector's battery pin.
Decoded<double> decodeAdapterVoltage(String? raw) {
  if (raw == null || isSilentReply(raw)) {
    return DecodedNoAnswer<double>(raw?.trim() ?? 'empty');
  }
  if (raw.contains('?')) return const DecodedUnsupported<double>();
  final v = ObdParser.parseAtRvVoltage(raw);
  return v == null
      ? const DecodedUnparseable<double>('not a voltage')
      : DecodedValue<double>(v);
}

// ═══════════════════════════════════════════════════════════════════════════
// Mode 09 — VIN (PID 02) and calibration IDs (PID 04)
// ═══════════════════════════════════════════════════════════════════════════

/// A validated vehicle identification number.
///
/// [toString] is masked on purpose, so a VIN that ends up interpolated into a
/// log line or an error report by accident leaks nothing. Read [value] only
/// where the VIN is genuinely needed.
class Vin {
  Vin._(this.value);

  /// The 17 characters. Never log, print or send this.
  final String value;

  static final RegExp _valid = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');

  /// Exactly 17 characters from A–Z except I, O and Q, and 0–9. The North
  /// American check digit is NOT enforced: Indian VINs need not satisfy it.
  static bool isValid(String s) => _valid.hasMatch(s);

  static Vin? tryParse(String s) => isValid(s) ? Vin._(s) : null;

  /// First three and last two characters, for a support screen if ever
  /// needed: `MA3************89`.
  String get masked =>
      '${value.substring(0, 3)}${'*' * 12}${value.substring(15)}';

  @override
  String toString() => '[VIN masked]';

  @override
  bool operator ==(Object other) => other is Vin && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// The bytes after `49 <pid>` from each module, joining the older
/// multi-message form (`49 02 01 …`, `49 02 02 …`, four data bytes each) and
/// dropping the item-count byte of the CAN form.
Decoded<List<List<int>>> _mode09Items(String? raw, int pid) {
  final d = _decodeServicePid(raw, service: 0x09, pid: pid, minBytes: 0);
  if (d is! DecodedValue<List<List<int>>>) return d;
  final out = <List<int>>[];
  for (final data in d.value) {
    // Older form: [seq, a, b, c, d] repeated with the 49 xx in between. After
    // reassembly the 49 xx of messages 2…n are still inside the data.
    final pieces = <List<int>>[];
    var cursor = 0;
    final legacy = <int>[];
    var isLegacy = data.length >= 5 && data.length % 7 == 5;
    if (isLegacy) {
      for (var seq = 1; cursor < data.length; seq++) {
        final start = seq == 1 ? 0 : cursor;
        if (seq > 1) {
          if (cursor + 2 > data.length ||
              data[cursor] != 0x49 ||
              data[cursor + 1] != pid) {
            isLegacy = false;
            break;
          }
        }
        final s = seq == 1 ? start : start + 2;
        if (s + 5 > data.length || data[s] != seq) {
          isLegacy = false;
          break;
        }
        legacy.addAll(data.sublist(s + 1, s + 5));
        cursor = s + 5;
      }
    }
    if (isLegacy && legacy.isNotEmpty) {
      pieces.add(legacy);
    } else if (data.isNotEmpty) {
      pieces.add(data.sublist(1)); // CAN: item count, then the item(s)
    }
    out.addAll(pieces);
  }
  return DecodedValue<List<List<int>>>(out);
}

/// Why a VIN reply was rejected. The VIN itself is never kept on a rejection.
class InvalidVin {
  const InvalidVin(this.reason);
  final String reason;
}

/// Mode 09 PID 02. Accepts the CAN form `49 02 01` + 17 ASCII bytes, the same
/// with leading `00` padding, the older multi-message form, and replies with
/// or without spaces and line breaks. Validates strictly ([Vin.isValid]); a
/// reply that fails is [DecodedUnparseable] with an [InvalidVin]-style
/// reason, never a value.
Decoded<Vin> decodeVinReply(String? raw) {
  try {
    final items = _mode09Items(raw, 0x02);
    switch (items) {
      case DecodedValue(:final value):
        String? lastReason;
        for (final bytes in value) {
          var b = bytes;
          var start = 0;
          while (start < b.length && b[start] == 0x00) {
            start++;
          }
          b = b.sublist(start);
          if (b.length != 17) {
            lastReason = 'InvalidVin: ${b.length} characters, not 17';
            continue;
          }
          if (b.any((x) => x < 0x20 || x > 0x7E)) {
            lastReason = 'InvalidVin: non-printable byte';
            continue;
          }
          final vin = Vin.tryParse(String.fromCharCodes(b));
          if (vin != null) return DecodedValue<Vin>(vin);
          lastReason = 'InvalidVin: character outside A-Z (no I, O, Q) and 0-9';
        }
        return DecodedUnparseable<Vin>(lastReason ?? 'InvalidVin: empty');
      case DecodedUnsupported(:final nrc):
        return DecodedUnsupported<Vin>(nrc);
      case DecodedNegative(:final nrc):
        return DecodedNegative<Vin>(nrc);
      case DecodedNoAnswer(:final reason):
        return DecodedNoAnswer<Vin>(reason);
      case DecodedUnparseable(:final reason):
        return DecodedUnparseable<Vin>(reason);
    }
  } catch (e) {
    return DecodedUnparseable<Vin>('decoder error: ${e.runtimeType}');
  }
}

/// Mode 09 PID 04: one or more 16-character calibration IDs, `00`-padded.
Decoded<List<String>> decodeCalibrationIds(String? raw) {
  try {
    final items = _mode09Items(raw, 0x04);
    if (items is! DecodedValue<List<List<int>>>) {
      return _map(items, (_) => const <String>[]);
    }
    final ids = <String>[];
    for (final bytes in items.value) {
      for (var i = 0; i + 16 <= bytes.length; i += 16) {
        final block = bytes.sublist(i, i + 16);
        var end = block.length;
        while (end > 0 && block[end - 1] == 0x00) {
          end--;
        }
        final text = block.sublist(0, end);
        if (text.isEmpty) continue;
        if (text.any((x) => x < 0x20 || x > 0x7E)) {
          return const DecodedUnparseable<List<String>>('non-printable byte');
        }
        ids.add(String.fromCharCodes(text).trim());
      }
    }
    return ids.isEmpty
        ? const DecodedUnparseable<List<String>>('no calibration ID')
        : DecodedValue<List<String>>(List.unmodifiable(ids));
  } catch (e) {
    return DecodedUnparseable<List<String>>('decoder error: ${e.runtimeType}');
  }
}
