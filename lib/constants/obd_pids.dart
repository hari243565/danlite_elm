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

  // ── Physical module addressing (used only by the chassis/ABS scan) ────────
  // The live-telemetry and Mode 03 paths never touch these: they rely on the
  // adapter's default functional addressing. A chassis module has to be
  // addressed directly, which means overriding the transmit header and the
  // receive filter, then putting both back afterwards.

  /// `ATSH <id>` — set the CAN request header (the ID the adapter transmits
  /// on). Retargets from the OBD functional broadcast to one specific module.
  static String setHeader(String canId) => 'ATSH$canId';

  /// `ATCRA <id>` — set the CAN receive-address filter, so only that module's
  /// replies are accepted and another ECU's traffic cannot be misattributed.
  static String setReceiveFilter(String canId) => 'ATCRA$canId';

  /// `ATCRA` with no argument — clear the receive filter.
  static const String clearReceiveFilter = 'ATCRA';

  /// `ATAR` — restore automatic receive addressing.
  static const String autoReceiveAddress = 'ATAR';

  /// `ATFCSH <id>` — flow-control header. When a reply spans multiple frames
  /// the adapter must send its flow-control frame back to the module it is
  /// talking to, not to the default address.
  static String setFlowControlHeader(String canId) => 'ATFCSH$canId';

  /// `ATFCSD 300000` — flow-control data: ClearToSend, block size 0,
  /// separation time 0. The standard "send it all, no throttling" reply.
  static const String flowControlData = 'ATFCSD300000';

  /// `ATFCSM1` — use the user-supplied flow-control header and data above.
  static const String flowControlMode = 'ATFCSM1';
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

      final b1 = _hexToInt(bytes[3]);
      final b2 = _hexToInt(bytes[4]);
      if (b1 == null || b2 == null) return null;
      return decodeDtcPair(b1, b2);
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
  static const Set<int> serviceResponseBytes = <int>{0x43, 0x47, 0x4A};
  static const List<String> _systemLetters = <String>['P', 'C', 'B', 'U'];
  static const String _hexDigits = '0123456789ABCDEF';
  static final RegExp _powertrainPattern = RegExp(r'^P[0-3][0-9A-F]{3}$');
  static final RegExp _anyDtcPattern = RegExp(r'^[PCBU][0-3][0-9A-F]{3}$');
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _nonHex = RegExp(r'[^0-9A-F]');
  static final RegExp _hexOnly = RegExp(r'^[0-9A-F]+$');
  static const List<String> _noiseMarkers = <String>[
    'SEARCHING', 'NO DATA', 'NODATA', 'UNABLE TO CONNECT', 'UNABLE', 'STOPPED',
    'BUS INIT', 'BUSINIT', 'BUS ERROR', 'BUS BUSY', 'CAN ERROR', 'DATA ERROR',
    'BUFFER FULL', 'RX ERROR', 'FB ERROR', 'LP ALERT', 'LV RESET', 'ACT ALERT',
    'ERR', 'ERROR', 'ELM327', 'OBDII', 'OK', '?',
  ];

  static List<String> parseDtcs(String? response, {DtcCountByteMode countByteMode = DtcCountByteMode.auto}) {
    try { return parseDetailed(response, countByteMode: countByteMode).powertrainCodes; } catch (_) { return const <String>[]; }
  }

  static List<String> parseAllDtcs(String? response, {DtcCountByteMode countByteMode = DtcCountByteMode.auto}) {
    try { return parseDetailed(response, countByteMode: countByteMode).allCodes; } catch (_) { return const <String>[]; }
  }

  static DtcParseResult parseDetailed(String? response, {DtcCountByteMode countByteMode = DtcCountByteMode.auto}) {
    final warnings = <String>[];
    final ordered = <String>[];
    int? reportedCount;
    try {
      if (response == null || response.trim().isEmpty) {
        return DtcParseResult(powertrainCodes: const <String>[], allCodes: const <String>[], warnings: const <String>['Empty response.']);
      }
      final frames = _tokenizeFrames(response, warnings);
      if (frames.isEmpty) {
        return DtcParseResult(powertrainCodes: const <String>[], allCodes: const <String>[], warnings: warnings..add('No usable data.'));
      }
      final grouped = <String, List<_RawFrame>>{};
      for (final frame in frames) { grouped.putIfAbsent(frame.ecuId, () => <_RawFrame>[]).add(frame); }
      for (final entry in grouped.entries) {
        final assembled = _reassembleIsoTp(entry.value, entry.key, warnings);
        if (assembled.payload.isEmpty) continue;
        final decoded = _decodeServicePayload(assembled.payload, entry.key, assembled.sawIsoTpPci, countByteMode, warnings);
        reportedCount = _accumulateCount(reportedCount, decoded.reportedCount);
        ordered.addAll(decoded.codes);
      }
    } catch (e) { warnings.add('Unrecoverable parser error: $e'); }

    final seen = <String>{};
    final unique = <String>[];
    for (final code in ordered) { if (seen.add(code)) unique.add(code); }
    final powertrain = <String>[for (final code in unique) if (_powertrainPattern.hasMatch(code)) code];

    return DtcParseResult(powertrainCodes: List<String>.unmodifiable(powertrain), allCodes: List<String>.unmodifiable(unique), warnings: List<String>.unmodifiable(warnings), reportedCount: reportedCount);
  }

  static String? decodeDtcPair(int byte1, int byte2) {
    final b1 = byte1 & 0xFF;
    final b2 = byte2 & 0xFF;
    if (b1 == 0x00 && b2 == 0x00) return null;
    final letter = _systemLetters[(b1 >> 6) & 0x03];
    final second = (b1 >> 4) & 0x03;
    final third = b1 & 0x0F;
    final fourth = (b2 >> 4) & 0x0F;
    final fifth = b2 & 0x0F;
    final code = '$letter$second${_hexDigits[third]}${_hexDigits[fourth]}${_hexDigits[fifth]}';
    return _anyDtcPattern.hasMatch(code) ? code : null;
  }

  static List<_RawFrame> _tokenizeFrames(String response, List<String> warnings) {
    final frames = <_RawFrame>[];
    final lines = response.toUpperCase().replaceAll('>', '\n').split(RegExp(r'[\r\n]+'));
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (_isNoise(line)) { warnings.add('Ignored: "$line"'); continue; }
      final colon = line.indexOf(':');
      if (colon >= 0) {
        final left = line.substring(0, colon).trim();
        final right = line.substring(colon + 1);
        final leftParts = left.isEmpty ? const <String>[] : left.split(_whitespace);
        final ecuId = leftParts.length > 1 ? leftParts.first : '';
        final bytes = _hexToBytes(right, warnings);
        if (bytes.isNotEmpty) frames.add(_RawFrame(ecuId, bytes, preStripped: true));
        continue;
      }
      final tokens = line.split(_whitespace).where((t) => t.isNotEmpty).toList(growable: false);
      if (tokens.isEmpty) continue;
      if (tokens.length == 1 && tokens.first.length == 3 && _hexOnly.hasMatch(tokens.first)) continue;
      var ecuId = '';
      var dataTokens = tokens;
      final first = tokens.first;
      if (tokens.length >= 2 && (first.length == 3 || first.length == 8) && _hexOnly.hasMatch(first)) {
        ecuId = first;
        dataTokens = tokens.sublist(1);
      }
      final bytes = _hexToBytes(dataTokens.join(), warnings);
      if (bytes.isEmpty) continue;
      frames.add(_RawFrame(ecuId, bytes, preStripped: false));
    }
    return frames;
  }

  static bool _isNoise(String line) {
    for (final marker in _noiseMarkers) { if (line.contains(marker)) return true; }
    return false;
  }

  static List<int> _hexToBytes(String input, List<String> warnings) {
    final cleaned = input.toUpperCase().replaceAll(_nonHex, '');
    if (cleaned.isEmpty) return const <int>[];
    var usable = cleaned;
    if (usable.length.isOdd) { usable = usable.substring(0, usable.length - 1); }
    final out = <int>[];
    for (var i = 0; i + 2 <= usable.length; i += 2) {
      final value = int.tryParse(usable.substring(i, i + 2), radix: 16);
      if (value != null) out.add(value);
    }
    return out;
  }

  static _Reassembly _reassembleIsoTp(List<_RawFrame> frames, String ecuId, List<String> warnings) {
    final out = <int>[];
    var sawPci = false;
    int? declaredLength;
    int? lastSequence;
    var truncated = false;
    if (frames.length == 1 && !frames.first.preStripped) {
      final unwrapped = _unwrapConcatenatedIsoTp(frames.first.bytes);
      if (unwrapped != null) return _Reassembly(unwrapped, true);
    }
    for (final frame in frames) {
      if (truncated) break;
      final bytes = frame.bytes;
      if (bytes.isEmpty) continue;
      if (frame.preStripped) { out.addAll(bytes); continue; }
      final pci = bytes.first;
      final type = pci >> 4;
      switch (type) {
        case 0x0:
          sawPci = true;
          final length = pci & 0x0F;
          var data = bytes.sublist(1);
          if (length > 0 && length <= data.length) data = data.sublist(0, length);
          out.addAll(data);
          break;
        case 0x1:
          if (bytes.length < 2) break;
          sawPci = true;
          declaredLength = ((pci & 0x0F) << 8) | bytes[1];
          out.addAll(bytes.sublist(2));
          lastSequence = 0;
          break;
        case 0x2:
          sawPci = true;
          final sequence = pci & 0x0F;
          if (lastSequence != null && sequence != ((lastSequence + 1) & 0x0F)) { truncated = true; break; }
          lastSequence = sequence;
          out.addAll(bytes.sublist(1));
          break;
        case 0x3: sawPci = true; break;
        default: out.addAll(bytes); break;
      }
    }
    if (declaredLength != null && declaredLength > 0 && out.length > declaredLength) {
      return _Reassembly(out.sublist(0, declaredLength), sawPci);
    }
    return _Reassembly(out, sawPci);
  }

  static List<int>? _unwrapConcatenatedIsoTp(List<int> raw) {
    if (raw.length < 9 || (raw[0] >> 4) != 0x1) return null;
    final declared = ((raw[0] & 0x0F) << 8) | raw[1];
    if (declared <= 0) return null;
    final out = <int>[];
    var index = 2;
    final firstChunk = (raw.length - index) >= 6 ? 6 : (raw.length - index);
    out.addAll(raw.sublist(index, index + firstChunk));
    index += firstChunk;
    var expected = 1;
    while (index < raw.length) {
      final pci = raw[index];
      if ((pci >> 4) != 0x2 || (pci & 0x0F) != (expected & 0x0F)) return null;
      expected++; index += 1;
      final chunk = (raw.length - index) >= 7 ? 7 : (raw.length - index);
      if (chunk <= 0) break;
      out.addAll(raw.sublist(index, index + chunk));
      index += chunk;
    }
    return out.length < declared ? null : out.sublist(0, declared);
  }

  static _ServiceDecode _decodeServicePayload(List<int> payload, String ecuId, bool sawIsoTpPci, DtcCountByteMode countByteMode, List<String> warnings) {
    var start = -1;
    for (var i = 0; i < payload.length; i++) {
      if (serviceResponseBytes.contains(payload[i])) { start = i; break; }
    }
    if (start < 0) return const _ServiceDecode(<String>[], null);
    var body = payload.sublist(start + 1);
    int? reported;
    if (body.isNotEmpty) {
      final strip = countByteMode == DtcCountByteMode.present || (countByteMode == DtcCountByteMode.auto && (sawIsoTpPci || _looksLikeCountByte(body)));
      if (strip) { reported = body.first; body = body.sublist(1); }
    }
    final codes = <String>[];
    for (var i = 0; i + 2 <= body.length; i += 2) {
      final code = decodeDtcPair(body[i], body[i + 1]);
      if (code != null) codes.add(code);
    }
    return _ServiceDecode(codes, reported);
  }

  static bool _looksLikeCountByte(List<int> body) {
    if (body.isEmpty) return false;
    if (body.length.isOdd) return true;
    final candidate = body.first;
    final dataEnd = 1 + candidate * 2;
    if (candidate <= 0 || dataEnd > body.length) return false;
    for (var i = dataEnd; i < body.length; i++) { if (body[i] != 0x00) return false; }
    return true;
  }

  static int? _accumulateCount(int? current, int? incoming) {
    if (incoming == null) return current;
    if (current == null) return incoming;
    return current + incoming;
  }

  // ── UDS (ISO 14229) chassis/ABS fault decode ─────────────────────────────
  /// Positive-response service id for UDS ReadDTCInformation (0x19 + 0x40).
  static const int udsReadDtcResponseByte = 0x59;

  /// UDS negative-response marker; followed by the echoed service id and a
  /// negative response code (NRC).
  static const int udsNegativeResponseByte = 0x7F;

  /// Subfunction 0x02 — reportDTCByStatusMask, the one this app requests.
  static const int udsReportDtcByStatusMask = 0x02;

  /// Decode a UDS `59 02` ReadDTCInformation reply from an ABS/chassis module.
  ///
  /// Format, per ISO 14229-1:
  ///   `59 02 <statusAvailabilityMask> [ <b0> <b1> <b2> <status> ]…`
  /// Each record is **4 bytes**, unlike OBD-II Mode 03's 2-byte pairs: three
  /// DTC bytes plus a status byte. The first two DTC bytes carry the same
  /// bit-packing as an OBD-II pair (top two bits select P/C/B/U), so
  /// [decodeDtcPair] decodes them directly and the app gets the familiar
  /// five-character form the service manual prints. The third byte is the
  /// failure-type byte (the `-04` in `C1015-04`) and is preserved separately
  /// rather than folded into the code.
  ///
  /// Frame tokenisation, ECU grouping and ISO-TP reassembly are shared with
  /// the Mode 03 path — only the payload layout differs.
  static UdsDtcParseResult parseUdsDtcDetailed(String? response) {
    final warnings = <String>[];
    try {
      if (response == null || response.trim().isEmpty) {
        return UdsDtcParseResult(
            records: const <UdsDtcRecord>[],
            warnings: const <String>['Empty response.']);
      }
      final frames = _tokenizeFrames(response, warnings);
      if (frames.isEmpty) {
        return UdsDtcParseResult(
            records: const <UdsDtcRecord>[],
            warnings: warnings..add('No usable data.'));
      }
      final grouped = <String, List<_RawFrame>>{};
      for (final frame in frames) {
        grouped.putIfAbsent(frame.ecuId, () => <_RawFrame>[]).add(frame);
      }

      final records = <UdsDtcRecord>[];
      int? negativeResponseCode;
      var sawPositive = false;

      for (final entry in grouped.entries) {
        final payload = _reassembleIsoTp(entry.value, entry.key, warnings).payload;
        if (payload.isEmpty) continue;

        // Negative response: 7F <serviceId> <NRC>. Report it rather than
        // treating a refusal as "no faults" — they mean very different things.
        for (var i = 0; i + 2 < payload.length; i++) {
          if (payload[i] == udsNegativeResponseByte && payload[i + 1] == 0x19) {
            negativeResponseCode = payload[i + 2];
            warnings.add(
                'Module ${entry.key} refused 19 02 (NRC 0x${payload[i + 2].toRadixString(16).toUpperCase()}).');
            break;
          }
        }

        var start = -1;
        for (var i = 0; i < payload.length; i++) {
          if (payload[i] == udsReadDtcResponseByte) { start = i; break; }
        }
        if (start < 0) continue;

        var cursor = start + 1;
        // Subfunction echo, then the status-availability mask byte.
        if (cursor >= payload.length ||
            payload[cursor] != udsReportDtcByStatusMask) {
          warnings.add('Module ${entry.key}: unexpected 19 subfunction echo.');
          continue;
        }
        sawPositive = true;
        cursor += 1;
        if (cursor >= payload.length) continue;
        cursor += 1; // statusAvailabilityMask

        while (cursor + 4 <= payload.length) {
          final b0 = payload[cursor];
          final b1 = payload[cursor + 1];
          final ftb = payload[cursor + 2];
          final status = payload[cursor + 3];
          cursor += 4;
          if (b0 == 0x00 && b1 == 0x00 && ftb == 0x00) continue; // padding
          final code = decodeDtcPair(b0, b1);
          if (code == null) continue;
          records.add(UdsDtcRecord(
              code: code, failureTypeByte: ftb, statusByte: status));
        }
      }

      final seen = <String>{};
      final unique = <UdsDtcRecord>[];
      for (final r in records) {
        if (seen.add('${r.code}-${r.failureTypeByte}')) unique.add(r);
      }

      return UdsDtcParseResult(
        records: List<UdsDtcRecord>.unmodifiable(unique),
        warnings: List<String>.unmodifiable(warnings),
        negativeResponseCode: negativeResponseCode,
        sawPositiveResponse: sawPositive,
      );
    } catch (e) {
      return UdsDtcParseResult(
          records: const <UdsDtcRecord>[],
          warnings: List<String>.unmodifiable(
              warnings..add('Unrecoverable UDS parser error: $e')));
    }
  }
}

/// One DTC record from a UDS `59 02` reply.
class UdsDtcRecord {
  /// Five-character SAE form (e.g. `C1015`), as printed in service manuals.
  final String code;

  /// ISO 14229 failure-type byte — the `-04` suffix form. Kept separate so the
  /// code still matches the manual's bare five-character table key.
  final int failureTypeByte;

  /// ISO 14229 DTC status byte.
  final int statusByte;

  const UdsDtcRecord({
    required this.code,
    required this.failureTypeByte,
    required this.statusByte,
  });

  /// Bit 3 — confirmedDTC: the fault has been stored, not merely seen once.
  bool get isConfirmed => (statusByte & 0x08) != 0;

  /// Bit 0 — testFailed on the most recent test.
  bool get isCurrentlyFailing => (statusByte & 0x01) != 0;
}

class UdsDtcParseResult {
  final List<UdsDtcRecord> records;
  final List<String> warnings;

  /// Set when the module answered `7F 19 <NRC>` — an explicit refusal, which
  /// is not the same as a healthy module reporting zero faults.
  final int? negativeResponseCode;

  /// True when a well-formed `59 02` header was seen, even if it carried no
  /// DTC records. This is what distinguishes "ABS module answered, no faults"
  /// from "nothing on the bus answered at all".
  final bool sawPositiveResponse;

  const UdsDtcParseResult({
    required this.records,
    required this.warnings,
    this.negativeResponseCode,
    this.sawPositiveResponse = false,
  });

  List<String> get codes =>
      <String>[for (final r in records) r.code];
}

enum DtcCountByteMode { auto, present, absent }

class DtcParseResult {
  final List<String> powertrainCodes;
  final List<String> allCodes;
  final List<String> warnings;
  final int? reportedCount;

  const DtcParseResult({
    required this.powertrainCodes,
    required this.allCodes,
    required this.warnings,
    this.reportedCount,
  });

  bool get countMismatch => reportedCount != null && reportedCount != allCodes.length;
}

class _RawFrame {
  final String ecuId;
  final List<int> bytes;
  final bool preStripped;
  const _RawFrame(this.ecuId, this.bytes, {required this.preStripped});
}

class _Reassembly {
  final List<int> payload;
  final bool sawIsoTpPci;
  const _Reassembly(this.payload, this.sawIsoTpPci);
}

class _ServiceDecode {
  final List<String> codes;
  final int? reportedCount;
  const _ServiceDecode(this.codes, this.reportedCount);
}
