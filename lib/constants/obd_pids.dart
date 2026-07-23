/// Danlite ELM — OBD2 PID (Parameter ID) Definitions
/// All standard Mode 01 PIDs supported by ELM327 adapters
class ObdPid {
  final String command;
  final String name;
  final String unit;
  final double min;
  final double max;
  final double warningThreshold;
  final double criticalThreshold;
  final String icon;

  const ObdPid({
    required this.command,
    required this.name,
    required this.unit,
    required this.min,
    required this.max,
    this.warningThreshold = double.infinity,
    this.criticalThreshold = double.infinity,
    required this.icon,
  });
}

class ObdPids {
  ObdPids._();

  static const rpm = ObdPid(
      command: '010C',
      name: 'Engine RPM',
      unit: 'RPM',
      min: 0,
      max: 8000,
      warningThreshold: 5500,
      criticalThreshold: 7000,
      icon: '⚙️');

  static const speed = ObdPid(
      command: '010D',
      name: 'Vehicle Speed',
      unit: 'km/h',
      min: 0,
      max: 260,
      warningThreshold: 200,
      criticalThreshold: 240,
      icon: '🚗');

  static const coolantTemp = ObdPid(
      command: '0105',
      name: 'Coolant Temp',
      unit: '°C',
      min: -40,
      max: 215,
      warningThreshold: 100,
      criticalThreshold: 115,
      icon: '🌡️');

  static const intakeTemp = ObdPid(
      command: '010F',
      name: 'Intake Air Temp',
      unit: '°C',
      min: -40,
      max: 215,
      warningThreshold: 60,
      criticalThreshold: 80,
      icon: '💨');

  static const throttle = ObdPid(
      command: '0111',
      name: 'Throttle Position',
      unit: '%',
      min: 0,
      max: 100,
      icon: '🎚️');

  static const engineLoad = ObdPid(
      command: '0104',
      name: 'Engine Load',
      unit: '%',
      min: 0,
      max: 100,
      warningThreshold: 80,
      criticalThreshold: 95,
      icon: '📊');

  static const fuelLevel = ObdPid(
      command: '012F',
      name: 'Fuel Level',
      unit: '%',
      min: 0,
      max: 100,
      warningThreshold: 15,
      criticalThreshold: 5,
      icon: '⛽');

  static const fuelPressure = ObdPid(
      command: '010A',
      name: 'Fuel Pressure',
      unit: 'kPa',
      min: 0,
      max: 765,
      warningThreshold: 600,
      criticalThreshold: 700,
      icon: '🔧');

  static const maf = ObdPid(
      command: '0110',
      name: 'Mass Air Flow',
      unit: 'g/s',
      min: 0,
      max: 655,
      icon: '🌬️');

  static const map = ObdPid(
      command: '010B',
      name: 'Manifold Pressure',
      unit: 'kPa',
      min: 0,
      max: 255,
      icon: '📈');

  static const timingAdvance = ObdPid(
      command: '010E',
      name: 'Timing Advance',
      unit: '°',
      min: -64,
      max: 63.5,
      icon: '⏱️');

  static const voltage = ObdPid(
      command: '0142',
      name: 'Battery Voltage',
      unit: 'V',
      min: 0,
      max: 65.535,
      warningThreshold: 11.5,
      criticalThreshold: 10.5,
      icon: '🔋');

  static const shortFuelTrim1 = ObdPid(
      command: '0106',
      name: 'Short Fuel Trim B1',
      unit: '%',
      min: -100,
      max: 99.2,
      icon: '⚗️');

  static const longFuelTrim1 = ObdPid(
      command: '0107',
      name: 'Long Fuel Trim B1',
      unit: '%',
      min: -100,
      max: 99.2,
      icon: '⚗️');

  static const runTime = ObdPid(
      command: '011F',
      name: 'Engine Run Time',
      unit: 'sec',
      min: 0,
      max: 65535,
      icon: '⏲️');

  static const List<ObdPid> dashboardPids = [
    rpm,
    speed,
    coolantTemp,
    throttle,
    engineLoad,
    fuelLevel,
    voltage,
  ];

  static const List<ObdPid> allPids = [
    rpm,
    speed,
    coolantTemp,
    intakeTemp,
    throttle,
    engineLoad,
    fuelLevel,
    fuelPressure,
    maf,
    map,
    timingAdvance,
    voltage,
    shortFuelTrim1,
    longFuelTrim1,
    runTime,
  ];

  static const String reset = 'ATZ';
  static const String echoOff = 'ATE0';
  static const String linefeedsOff = 'ATL0';
  static const String spacesOff = 'ATS0';
  static const String headersOff = 'ATH0';
  static const String autoProtocol = 'ATSP0';
  static const String readDtcs = '03';
  static const String clearDtcs = '04';
  static const String pendingDtcs = '07';
  static const String vehicleInfo = '0902';

  // ── Mode 02 (Freeze Frame) commands ───────────────────────────────────────
  // Byte 3 of every Mode 02 request is the frame number. Vehicles only ever
  // store a single freeze frame (the snapshot taken when the DTC that set it
  // was first detected), so it is always 00.
  static const String freezeFrameDtc = '020200';
  static const String freezeFrameRpm = '020C00';
  static const String freezeFrameSpeed = '020D00';
  static const String freezeFrameCoolantTemp = '020500';
  static const String freezeFrameEngineLoad = '020400';

  /// Hardware voltage read — asks the ELM327 chip itself to sample Pin 16
  /// (the OBD connector's battery-voltage pin) rather than asking the ECU
  /// for Mode 01 PID 42, which a large share of vehicles do not implement.
  /// Response is plain text, e.g. "12.4V", not a hex PID frame.
  static const String readVoltage = 'ATRV';
}

// ═══════════════════════════════════════════════════════════════════════════
// ROBUST PARSING ENGINE
// Handles: extra whitespace, multi-line responses, text echoes, partial
// frames, mode-byte prefixes ("41 0C…"), and any malformed garbage —
// without ever throwing a fatal exception.
// ═══════════════════════════════════════════════════════════════════════════
class ObdParser {
  ObdParser._();

  /// Two-point calibration endpoints for the fuel-level raw byte (PID 2F, A).
  ///
  /// SAE J1979 maps 0x00 → 0 % and 0xFF → 100 %, but real float sensors are
  /// often non-ideal: the voltage can bottom out above 0 at empty and/or cap
  /// below 0xFF at full (e.g. a sensor topping out at ~3.5 V reports 0xB2 / 178
  /// for a full tank). A two-point linear fit corrects this uniformly — set
  /// each constant to the raw byte you actually observe at empty and full for
  /// the target vehicle, and the interpolation in [parseFuelLevel] maps that
  /// span onto 0–100 %. Leave at 0.0 / 255.0 for the SAE default.
  static const double fuelRawEmpty = 0.0; // Raw hex byte for 0%
  static const double fuelRawFull = 255.0; // Raw hex byte for 100%

  /// Extract clean hex byte tokens from a raw ELM327 response line.
  /// Example: "41 0C 1A F8" -> ["41","0C","1A","F8"]
  /// Also handles no-space hex: "410C1AF8" -> ["41","0C","1A","F8"]
  static List<String> _extractHexBytes(String response) {
    try {
      if (response.isEmpty) return [];

      // Take only the first line if multi-line response slipped through
      final firstLine = response
          .split(RegExp(r'[\r\n]'))
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => response);

      // Remove all non-hex characters except spaces
      var cleaned = firstLine.toUpperCase().trim();

      // If response has explicit spaces, split on them
      if (cleaned.contains(' ')) {
        final parts = cleaned
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty && _isHex(p))
            .toList();
        if (parts.isNotEmpty) return parts;
      }

      // No-space hex string — split into byte pairs
      cleaned = cleaned.replaceAll(RegExp(r'[^0-9A-F]'), '');
      if (cleaned.length < 2) return [];
      final bytes = <String>[];
      for (int i = 0; i + 2 <= cleaned.length; i += 2) {
        bytes.add(cleaned.substring(i, i + 2));
      }
      return bytes;
    } catch (e) {
      return [];
    }
  }

  static bool _isHex(String s) {
    if (s.isEmpty) return false;
    return RegExp(r'^[0-9A-Fa-f]+$').hasMatch(s);
  }

  static int? _hexToInt(String hex) {
    try {
      return int.parse(hex, radix: 16);
    } catch (_) {
      return null;
    }
  }

  /// True if the raw response is anything other than a real data frame:
  /// adapter/protocol chatter ("NO DATA", "SEARCHING", "ERROR", "TIMEOUT",
  /// "UNABLE...", "BUS INIT", "STOPPED") or the bare zero-byte stub some
  /// ELM327 clones send instead of a proper "NO DATA" for an unsupported PID.
  static bool _isInvalidResponse(String response) {
    final trimmed = response.trim();
    if (trimmed.isEmpty) return true;
    final upper = trimmed.toUpperCase();
    if (upper.contains('NO DATA') ||
        upper.contains('NODATA') ||
        upper.contains('SEARCHING') ||
        upper.contains('ERROR') ||
        upper.contains('UNABLE') ||
        upper.contains('STOPPED') ||
        upper.contains('TIMEOUT') ||
        upper.contains('BUS INIT')) {
      return true;
    }
    if (upper == '00' || upper == '0X00') return true;
    return false;
  }

  /// Confirms the byte frame actually answers the PID we asked for: the
  /// mode byte must be (requestMode + 0x40) and the PID byte must echo
  /// back. Rejects ECU negative-response frames (mode 7F — "PID not
  /// supported") and any stray/mis-attributed bytes, so we never run the
  /// scaling formula on data that isn't really this PID's response.
  static bool _matchesRequestedPid(String command, List<String> bytes) {
    if (command.length < 4 || bytes.length < 2) return false;
    final expectedMode = _hexToInt(command.substring(0, 2));
    final expectedPid = command.substring(2, 4).toUpperCase();
    if (expectedMode == null) return false;
    final gotMode = _hexToInt(bytes[0]);
    if (gotMode == null) return false;
    if (gotMode == 0x7F) return false; // negative response — not supported
    if (gotMode != expectedMode + 0x40) return false;
    if (bytes[1].toUpperCase() != expectedPid) return false;
    return true;
  }

  // ── Individual PID parsers ────────────────────────────────────────────────
  // Standard OBD2 response format: [Mode+40] [PID] [DataBytes...]
  // e.g. "41 0C 1A F8" = Mode 41 (response to 01), PID 0C (RPM), data A=1A B=F8

  static double? parseRpm(String response) {
    final b = _extractHexBytes(response);
    if (b.length < 4) return null;
    final a = _hexToInt(b[2]);
    final c = _hexToInt(b[3]);
    if (a == null || c == null) return null;
    return ((a * 256) + c) / 4.0;
  }

  static double? parseSpeed(String response) {
    final b = _extractHexBytes(response);
    if (b.length < 3) return null;
    final a = _hexToInt(b[2]);
    if (a == null) return null;
    return a.toDouble();
  }

  static double? parseTempC(String response) {
    final b = _extractHexBytes(response);
    if (b.length < 3) return null;
    final a = _hexToInt(b[2]);
    if (a == null) return null;
    return (a - 40).toDouble();
  }

  static double? parsePercent(String response) {
    final b = _extractHexBytes(response);
    if (b.length < 3) return null;
    final a = _hexToInt(b[2]);
    if (a == null) return null;
    return a * 100 / 255.0;
  }

  /// Fuel Level Input — Mode 01 PID 2F (SAE J1979).
  /// `A` is the single data byte after the `41 2F` header (b[2]). Mapped onto
  /// 0–100 % by a two-point linear interpolation between the calibrated raw
  /// endpoints [fuelRawEmpty] and [fuelRawFull], in floating-point — Dart's `/`
  /// never truncates. The clamp handles floats that drop below the Empty
  /// threshold or spike above the Full threshold.
  static double? parseFuelLevel(String response) {
    final b = _extractHexBytes(response);
    if (b.length < 3) return null;
    final a = _hexToInt(b[2]);
    if (a == null) return null;
    final pct = ((a - fuelRawEmpty) / (fuelRawFull - fuelRawEmpty)) * 100.0;
    return pct.clamp(0.0, 100.0);
  }

  static double? parseVoltage(String response) {
    final b = _extractHexBytes(response);
    if (b.length < 4) return null;
    final a = _hexToInt(b[2]);
    final c = _hexToInt(b[3]);
    if (a == null || c == null) return null;
    return ((a * 256) + c) * 0.001;
  }

  static double? parseFuelPressure(String response) {
    final b = _extractHexBytes(response);
    if (b.length < 3) return null;
    final a = _hexToInt(b[2]);
    if (a == null) return null;
    return a * 3.0;
  }

  static double? parseMaf(String response) {
    final b = _extractHexBytes(response);
    if (b.length < 4) return null;
    final a = _hexToInt(b[2]);
    final c = _hexToInt(b[3]);
    if (a == null || c == null) return null;
    return ((a * 256) + c) / 100.0;
  }

  static double? parseTimingAdvance(String response) {
    final b = _extractHexBytes(response);
    if (b.length < 3) return null;
    final a = _hexToInt(b[2]);
    if (a == null) return null;
    return a / 2.0 - 64;
  }

  static double? parseFuelTrim(String response) {
    final b = _extractHexBytes(response);
    if (b.length < 3) return null;
    final a = _hexToInt(b[2]);
    if (a == null) return null;
    return (a - 128) * 100 / 128.0;
  }

  static double? parseRunTime(String response) {
    final b = _extractHexBytes(response);
    if (b.length < 4) return null;
    final a = _hexToInt(b[2]);
    final c = _hexToInt(b[3]);
    if (a == null || c == null) return null;
    return ((a * 256) + c).toDouble();
  }

  /// Dispatch parse for a specific PID command. Never throws.
  /// Strictly sanitized: adapter/protocol chatter, unsupported-PID stubs,
  /// and negative-response frames all return null instead of feeding the
  /// scaling formula garbage bytes — callers must treat null as "N/A".
  static double? parsePid(String command, String response) {
    try {
      if (_isInvalidResponse(response)) return null;
      if (!_matchesRequestedPid(command, _extractHexBytes(response))) {
        return null;
      }
      switch (command) {
        case '010C':
          return parseRpm(response);
        case '010D':
          return parseSpeed(response);
        case '0105':
          return parseTempC(response);
        case '010F':
          return parseTempC(response);
        case '0111':
          return parsePercent(response);
        case '0104':
          return parsePercent(response);
        case '012F':
          return parseFuelLevel(response);
        case '0142':
          return parseVoltage(response);
        case '010A':
          return parseFuelPressure(response);
        case '0110':
          return parseMaf(response);
        case '010B':
          return parsePercent(response) == null
              ? _parseMapKpa(response)
              : _parseMapKpa(response);
        case '010E':
          return parseTimingAdvance(response);
        case '0106':
          return parseFuelTrim(response);
        case '0107':
          return parseFuelTrim(response);
        case '011F':
          return parseRunTime(response);
        default:
          return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Parses the ELM327 "AT RV" hardware voltage read — a plain-text reply
  /// like "12.4V" or "12.4 V" (the chip's own Pin 16 sense reading), not a
  /// hex PID frame. Rejects adapter chatter and clamps to a sane 12V-system
  /// range so a garbled reply can't surface as a fake battery value.
  static double? parseAtRvVoltage(String response) {
    try {
      if (_isInvalidResponse(response)) return null;
      final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(response);
      if (match == null) return null;
      final value = double.tryParse(match.group(1)!);
      if (value == null) return null;
      if (value <= 0 || value > 30) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  // ── Freeze Frame (Mode 02 / response Mode 42) parsing ─────────────────────
  // SAE J1979 frame layout: [42][PID][FrameNo][data bytes...] — identical to
  // the Mode 01/41 live-data shape except for the extra frame-number byte
  // inserted right after the PID. Rather than re-deriving the scaling math,
  // we strip that one byte and re-dispatch through parsePid() so freeze
  // frame values are always computed with the exact same formulas as live
  // data for the same PID.
  static const Map<String, String> _freezeFramePidToLivePid = {
    '0C': '010C',
    '0D': '010D',
    '05': '0105',
    '04': '0104',
  };

  static double? parseFreezeFramePid(String command, String response) {
    try {
      if (_isInvalidResponse(response)) return null;
      final bytes = _extractHexBytes(response);
      if (!_matchesRequestedPid(command, bytes)) return null;
      if (bytes.length < 4) return null;

      final pidByte = command.substring(2, 4).toUpperCase();
      final livePid = _freezeFramePidToLivePid[pidByte];
      if (livePid == null) return null;

      final dataBytes = bytes.sublist(3); // drop the frame-number byte
      final synthetic = (['41', pidByte, ...dataBytes]).join(' ');
      return parsePid(livePid, synthetic);
    } catch (e) {
      return null;
    }
  }

  /// Parses the Mode 02 PID 02 response — the single DTC that triggered the
  /// stored freeze frame. Frame layout: [42][02][FrameNo][DTC byte1][byte2],
  /// so the trailing two bytes are handed to the existing DTC nibble-math
  /// decoder used for Mode 03/43 responses.
  static String? parseFreezeFrameDtc(String response) {
    try {
      if (_isInvalidResponse(response)) return null;
      final bytes = _extractHexBytes(response);
      if (!_matchesRequestedPid('0202', bytes)) return null;
      if (bytes.length < 5) return null;

      final codes = parseDtcs('${bytes[3]} ${bytes[4]}');
      return codes.isNotEmpty ? codes.first : null;
    } catch (e) {
      return null;
    }
  }

  static double? _parseMapKpa(String response) {
    final b = _extractHexBytes(response);
    if (b.length < 3) return null;
    final a = _hexToInt(b[2]);
    if (a == null) return null;
    return a.toDouble(); // kPa direct
  }

  // ── DTC (Diagnostic Trouble Code) parsing ─────────────────────────────────
  /// Parses a Mode 03 / 07 / 0A response into standard P/C/B/U codes.
  ///
  /// Handles, without ever throwing:
  ///   • Multi-frame ISO-TP (CAN / ISO 15765-4) responses — several frames
  ///     that the transport layer has already concatenated into one string
  ///     terminated by the ELM327 '>' prompt.
  ///   • The CAN DTC-count byte that immediately follows the "43" mode byte
  ///     (e.g. "43 0F …" = 15 codes). It is stripped before pairing, so it is
  ///     never mis-decoded as half of a DTC (the root cause of the phantom
  ///     C0xxx / dropped-codes bug).
  ///   • ISO-TP framing artifacts: the leading total-length byte and the
  ///     per-frame sequence markers ("0:", "1:", …) some adapters emit.
  ///   • Legacy ISO 9141 / KWP2000 line-oriented responses that repeat the
  ///     "43" header on every frame (no count byte).
  ///   • NO DATA / TIMEOUT / ERROR chatter and malformed / odd-length hex.
  // Known ELM327 chatter tokens that can appear inside a Mode 03 reply
  // (typically a leading protocol-search line before the adapter settles on
  // ISO 15765-4, or a mid-stream retry). Ordered so a compound phrase is
  // stripped whole before any single word it contains is matched separately.
  static const List<String> _dtcChatterPhrases = [
    'UNABLE TO CONNECT',
    'BUS INIT',
    'CAN ERROR',
    'DATA ERROR',
    'BUFFER FULL',
    'NO DATA',
    'NODATA',
    'SEARCHING',
    'STOPPED',
    'TIMEOUT',
    'ERROR',
  ];

  static List<String> parseDtcs(String response) {
    final codes = <String>[];
    try {
      if (response.isEmpty) return codes;

      // Deliberately NOT bailing out on a whole-response chatter check here
      // (unlike parsePid's single-frame path): a multi-frame DTC response can
      // legitimately have a "SEARCHING..." protocol-search line ahead of the
      // real 43-header frames, and discarding the entire response because of
      // that one line is exactly what drops otherwise-valid codes. Chatter
      // words are stripped token-by-token in _extractDtcHexBytes instead, and
      // we only give up if nothing usable survives that.
      final bytes = _extractDtcHexBytes(response);
      if (bytes.isEmpty) return codes;

      // Split the byte stream at each positive-response header (43/47/4A).
      // CAN yields a single segment (count byte + codes); the line-oriented
      // legacy protocols yield one segment per frame (codes only, no count).
      for (final segment in _splitOnDtcHeaders(bytes)) {
        _decodeDtcSegment(segment, codes);
      }
    } catch (e) {
      // Return whatever parsed cleanly rather than throwing.
    }
    codes.retainWhere((c) => c.toUpperCase().startsWith('P'));
    return codes;
  }

  /// DTC-specific hex tokenizer. Unlike [_extractHexBytes] (which is tuned for
  /// single-frame PID replies and deliberately reads only the first line),
  /// this aggregates EVERY frame of a multi-frame response and rejects the
  /// non-byte artifacts that ISO-TP framing injects.
  static List<String> _extractDtcHexBytes(String response) {
    try {
      var s = response.toUpperCase();
      // Unify line breaks so multi-frame lines merge into one token stream.
      s = s.replaceAll('\r', ' ').replaceAll('\n', ' ');
      // Strip known ELM327 chatter phrases as whole words BEFORE the hex
      // char-class filter below. Several of these words contain letters that
      // are themselves valid hex digits (the 'A'/'B' in "UNABLE", the 'D'/'A'
      // in "NODATA", the 'E'/'D' in "STOPPED", the 'C'/'A'/'E' in
      // "SEARCHING..."), so blindly keeping [0-9A-F] would let stray
      // fragments of these words survive as fake data bytes and corrupt the
      // frame — this is what silently drops/mutates real codes when a
      // "SEARCHING..." or "NODATA" line is interleaved with genuine frames
      // in a multi-frame response. Longer/compound phrases are listed before
      // the shorter words they contain (e.g. "CAN ERROR" before "ERROR") so
      // nothing is left half-stripped.
      for (final phrase in _dtcChatterPhrases) {
        s = s.replaceAll(phrase, ' ');
      }
      // Drop ISO-TP per-frame sequence markers ("0:", "1:", "A:") that appear
      // when the adapter is left auto-formatting (CAF1). Removing them here
      // keeps the frame-index digit from gluing onto the following data byte.
      s = s.replaceAll(RegExp(r'[0-9A-F]+\s*:'), ' ');
      // Keep only hex digits and separators.
      s = s.replaceAll(RegExp(r'[^0-9A-F ]'), ' ');
      s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (s.isEmpty) return [];

      final bytes = <String>[];
      for (final token in s.split(' ')) {
        if (token.isEmpty) continue;
        if (token.length.isEven) {
          // Clean run of bytes (spaced "43" or packed "430F2176…").
          for (int i = 0; i + 2 <= token.length; i += 2) {
            bytes.add(token.substring(i, i + 2));
          }
        }
        // Odd-length token = the ISO-TP total-length header (e.g. "020"/"014")
        // or a truncated partial frame. It cannot be a clean byte sequence, so
        // discard it wholesale rather than misalign every subsequent pair.
      }
      return bytes;
    } catch (_) {
      return [];
    }
  }

  static const Set<String> _dtcResponseHeaders = {'43', '47', '4A'};

  /// Splits the byte stream into per-header segments. Anything before the
  /// first header (a stray length byte the tokenizer let through) is dropped.
  /// If no header is present at all — e.g. a bare freeze-frame DTC pair handed
  /// in as "xx yy" — the whole stream is returned as a single segment.
  static List<List<String>> _splitOnDtcHeaders(List<String> bytes) {
    final segments = <List<String>>[];
    List<String>? current;
    for (final b in bytes) {
      if (_dtcResponseHeaders.contains(b)) {
        current = <String>[];
        segments.add(current);
        continue;
      }
      current?.add(b);
    }
    if (segments.isEmpty) return [bytes];
    return segments;
  }

  /// Decodes one header-delimited segment, appending unique codes to [codes].
  static void _decodeDtcSegment(List<String> segment, List<String> codes) {
    var data = segment;
    // A CAN (ISO 15765-4) response prefixes the DTC list with a one-byte
    // count, which makes the payload length odd (1 count byte + 2 bytes per
    // DTC). Strip it so the following 2-byte pairs realign; otherwise the
    // count byte is consumed as half a DTC, every code shifts, a phantom
    // (typically a bogus C0xxx) is fabricated and a real code is lost.
    if (data.length.isOdd) {
      data = data.sublist(1);
    }

    for (int i = 0; i + 2 <= data.length; i += 2) {
      final byte1 = _hexToInt(data[i]);
      final byte2 = data[i + 1];
      if (byte1 == null || byte2.length != 2) continue; // incomplete — discard
      if (byte1 == 0 && byte2 == '00') continue; // padding / empty slot

      final code = _decodeDtc(byte1, byte2);
      if (code != null && !codes.contains(code)) codes.add(code);
    }
  }

  /// Converts a 2-byte DTC into its SAE J2012 string form.
  /// Prefix comes from the top two bits of the high byte:
  ///   00 -> P (Powertrain), 01 -> C (Chassis),
  ///   10 -> B (Body),       11 -> U (Network).
  static String? _decodeDtc(int byte1, String byte2) {
    final firstNibble = (byte1 >> 4) & 0x0F;
    final secondNibble = byte1 & 0x0F;

    const prefixes = ['P', 'C', 'B', 'U'];
    final prefix = prefixes[(firstNibble >> 2) & 0x03];
    final digit1 = firstNibble & 0x03;

    final code = '$prefix$digit1'
        '${secondNibble.toRadixString(16).toUpperCase()}'
        '${byte2.toUpperCase()}';
    return code.length == 5 ? code : null;
  }
}
