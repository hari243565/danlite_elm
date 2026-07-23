import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants/dtc_descriptions.dart';
import '../constants/obd_pids.dart';
import '../models/vehicle_data.dart';
import 'bluetooth_classic_service.dart';

enum ConnectionType { wifi, bluetooth }

/// Static sensor snapshot captured by the ECU at the moment a DTC was set
/// (OBD2 Mode 02). Any field may be null if that PID isn't supported by the
/// vehicle or its response didn't parse.
class FreezeFrameData {
  final String? dtcCode;
  final double? rpm;
  final double? speed;
  final double? coolantTemp;
  final double? engineLoad;
  final DateTime capturedAt;

  const FreezeFrameData({
    this.dtcCode,
    this.rpm,
    this.speed,
    this.coolantTemp,
    this.engineLoad,
    required this.capturedAt,
  });

  bool get hasData =>
      dtcCode != null || rpm != null || speed != null || coolantTemp != null || engineLoad != null;
}

class ObdService extends ChangeNotifier {
  ObdService(this._btService) {
    _btService.addListener(_onBtServiceChanged);
  }

  final BluetoothClassicService _btService;

  // ── State ─────────────────────────────────────────────────────────────────
  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionType _transport = ConnectionType.wifi;

  ConnectionStatus get status => _status;
  ConnectionType get transport => _transport;
  bool get isConnected => _status == ConnectionStatus.connected;

  String _statusMessage = 'Not connected';
  String get statusMessage => _statusMessage;

  VehicleData _data = VehicleData.empty();
  VehicleData get data => _data;

  List<DtcCode> _dtcCodes = [];
  List<DtcCode> get dtcCodes => _dtcCodes;

  String _lastError = '';
  String get lastError => _lastError;

  // Diagnostics — exposed for debugging / status UI
  int _consecutiveTimeouts = 0;
  int get consecutiveTimeouts => _consecutiveTimeouts;

  DateTime? _lastGoodResponseAt;
  DateTime? get lastGoodResponseAt => _lastGoodResponseAt;

  // ── WiFi transport ────────────────────────────────────────────────────────
  Socket? _wifiSocket;
  StreamSubscription<List<int>>? _wifiSub;
  final StringBuffer _wifiBuffer = StringBuffer();
  Completer<String>? _wifiPendingCmd;

  static const Duration _wifiConnectTimeout = Duration(seconds: 10);

  // ── BT transport ──────────────────────────────────────────────────────────
  StreamSubscription<String>? _btDataSub;
  Completer<String>? _btPendingCmd;
  final StringBuffer _btBuffer = StringBuffer();

  // ── Command timeout — adaptive, increases on repeated failure ───────────
  Duration _cmdTimeout = const Duration(seconds: 2);
  static const Duration _cmdTimeoutMin = Duration(seconds: 2);
  static const Duration _cmdTimeoutMax = Duration(seconds: 6);

  // ── Polling ───────────────────────────────────────────────────────────────
  bool _isPolling = false;
  bool _dtcReadInFlight = false;
  int _pidIndex = 0;
  // Poll every known PID (not just the 7-PID dashboard subset) so screens
  // like Live Data can surface MAF, MAP, timing advance, fuel trims, etc.
  final _pids = ObdPids.allPids;

  // Held while a foreground command (e.g. clearDtcs) needs exclusive access
  // to the serial link, so _pollLoop() never writes a PID request to the
  // socket while that command is in flight and collides with it on the wire.
  int _pollLockDepth = 0;
  bool get _pollLocked => _pollLockDepth > 0;
  void _acquirePollLock() => _pollLockDepth++;
  void _releasePollLock() {
    if (_pollLockDepth > 0) _pollLockDepth--;
  }

  // ECU flash-memory erasure (04) needs more time to respond than a live
  // PID read does.
  static const Duration _clearDtcsMinTimeout = Duration(milliseconds: 4000);

  // A Mode 03 read can span several ISO-TP frames (up to ~half a second of
  // wire time on a busy CAN bus), so it needs a longer window than a
  // single-frame live PID read to gather every frame before the '>' prompt.
  static const Duration _readDtcsMinTimeout = Duration(milliseconds: 3000);

  // ══════════════════════════════════════════════════════════════════════════
  // WIFI CONNECTION
  // ══════════════════════════════════════════════════════════════════════════
  Future<bool> connectWifi({
    String ip = '192.168.0.10',
    int port = 35000,
  }) async {
    _setStatus(ConnectionStatus.connecting, 'Connecting to $ip:$port…');
    _resetDiagnostics();

    try {
      _wifiSocket =
          await Socket.connect(ip, port, timeout: _wifiConnectTimeout);
      _wifiSocket!.encoding = latin1;

      _wifiBuffer.clear();
      _wifiSub?.cancel();
      _wifiSub = _wifiSocket!.listen(
        _onWifiRawBytes,
        onError: (e) {
          _lastError = e.toString();
          if (isConnected) _handleTransportDrop('Wi-Fi stream error');
        },
        onDone: () {
          if (isConnected) _handleTransportDrop('Wi-Fi connection closed');
        },
        cancelOnError: false,
      );

      _transport = ConnectionType.wifi;
      _setStatus(ConnectionStatus.connecting, 'Initialising ELM327…');

      final initOk = await _initElm327WithRetry();
      if (!initOk) {
        await disconnect();
        _setStatus(ConnectionStatus.error,
            'ELM327 did not respond. Check adapter power / IP.');
        return false;
      }

      _setStatus(ConnectionStatus.connected, 'Connected via Wi-Fi · $ip');
      _startPolling();
      return true;
    } on SocketException catch (e) {
      _setStatus(ConnectionStatus.error, 'Wi-Fi connection failed');
      _lastError = e.message;
      return false;
    } catch (e) {
      _setStatus(ConnectionStatus.error, 'Error: $e');
      _lastError = e.toString();
      return false;
    }
  }

  void _onWifiRawBytes(List<int> bytes) {
    try {
      final chunk = latin1.decode(bytes);
      _wifiBuffer.write(chunk);
      _tryResolveBuffer(isWifi: true);
    } catch (e) {
      debugPrint('[ObdService] WiFi decode error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BLUETOOTH CONNECTION
  // ══════════════════════════════════════════════════════════════════════════
  Future<bool> connectBluetooth(BtDevice device) async {
    _setStatus(ConnectionStatus.connecting, 'Connecting via Bluetooth…');
    _resetDiagnostics();

    final ok = await _btService.connect(device);
    if (!ok) {
      _setStatus(ConnectionStatus.error, _btService.statusMessage);
      return false;
    }

    _btBuffer.clear();
    _btDataSub?.cancel();
    _btDataSub = _btService.dataStream.listen(
      _onBtRawChunk,
      onError: (e) {
        _lastError = e.toString();
        if (isConnected) _handleTransportDrop('Bluetooth stream error: $e');
      },
      onDone: () {
        if (isConnected) _handleTransportDrop('Bluetooth connection closed');
      },
      cancelOnError: false,
    );

    _transport = ConnectionType.bluetooth;
    _setStatus(ConnectionStatus.connecting, 'Initialising ELM327…');

    final initOk = await _initElm327WithRetry();
    if (!initOk) {
      await disconnect();
      _setStatus(ConnectionStatus.error,
          'ELM327 did not respond over Bluetooth. Try reconnecting.');
      return false;
    }

    _setStatus(ConnectionStatus.connected, 'Connected via BT · ${device.name}');
    _startPolling();
    return true;
  }

  void _onBtRawChunk(String chunk) {
    if (chunk.isEmpty) return;
    try {
      _btBuffer.write(chunk);
      _tryResolveBuffer(isWifi: false);
    } catch (e) {
      debugPrint('[ObdService] BT buffer error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UNIFIED TERMINATOR RESOLUTION
  // Dart is the SINGLE source of truth for detecting the ELM327 prompt '>'.
  // Both WiFi and Bluetooth funnel into this exact same logic.
  // ══════════════════════════════════════════════════════════════════════════
  void _tryResolveBuffer({required bool isWifi}) {
    final buffer = isWifi ? _wifiBuffer : _btBuffer;
    final raw = buffer.toString();

    if (!raw.contains('>')) return; // Not yet terminated — wait for more data

    // Extract everything up to (and including) the first '>' prompt.
    final idx = raw.indexOf('>');
    final frame = raw.substring(0, idx);

    // Keep any leftover bytes after '>' for the next command's buffer
    final remainder = raw.substring(idx + 1);
    buffer.clear();
    if (remainder.isNotEmpty) buffer.write(remainder);

    final cleaned = _sanitizeResponse(frame);

    final pending = isWifi ? _wifiPendingCmd : _btPendingCmd;
    if (pending != null && !pending.isCompleted) {
      pending.complete(cleaned);
      if (isWifi) {
        _wifiPendingCmd = null;
      } else {
        _btPendingCmd = null;
      }
    }
    // If no pending completer (e.g. stray data), we simply discard the frame.
    // This prevents "ghost" responses from being misattributed to the wrong command.
  }

  /// Strip echoes, CR/LF, excess whitespace. Never throw.
  String _sanitizeResponse(String raw) {
    try {
      final lines = raw.replaceAll('\r', '\n').split('\n');
      final out = <String>[];
      for (final line in lines) {
        final t = line.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
        if (t.isNotEmpty) out.add(t);
      }
      return out.join('\n');
    } catch (_) {
      return '';
    }
  }

  String _stripCanHeaderForLivePid(String response) {
    try {
      if (response.isEmpty) return response;
      final hexToken = RegExp(r'^[0-9A-Fa-f]+$');

      for (final rawLine in response.split(RegExp(r'[\r\n]+'))) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;

        var tokens = line.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

        if (tokens.length == 1 && hexToken.hasMatch(tokens.first)) {
          final h = tokens.first.toUpperCase();
          if (h.length.isOdd && h.length >= 5) {
            tokens = [h.substring(0, 3)];
            for (var i = 3; i + 2 <= h.length; i += 2) {
              tokens.add(h.substring(i, i + 2));
            }
          } else {
            tokens = [for (var i = 0; i + 2 <= h.length; i += 2) h.substring(i, i + 2)];
          }
        }

        if (tokens.length >= 2 && (tokens.first.length == 3 || tokens.first.length == 8) && hexToken.hasMatch(tokens.first)) {
          tokens = tokens.sublist(1);
        }

        if (tokens.length >= 2) {
          final b0 = int.tryParse(tokens.first, radix: 16);
          final b1 = int.tryParse(tokens[1], radix: 16);
          if (b0 != null && b1 != null && (b0 >> 4) == 0x0 && (b1 == 0x41 || b1 == 0x42 || b1 == 0x49)) {
            tokens = tokens.sublist(1);
          }
        }

        if (tokens.isEmpty) continue;
        final head = int.tryParse(tokens.first, radix: 16);
        if (head == null) continue;
        if (head == 0x41 || head == 0x42 || head == 0x49 || head == 0x7F) {
          return tokens.join(' ');
        }
      }
      return response;
    } catch (_) {
      return response;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TRANSPORT DROP HANDLER
  // ══════════════════════════════════════════════════════════════════════════
  void _handleTransportDrop(String reason) {
    _stopPolling();
    _completeAllPending('DISCONNECTED');
    _data = VehicleData.empty();
    _setStatus(ConnectionStatus.disconnected, reason);
  }

  void _onBtServiceChanged() {
    if (_transport == ConnectionType.bluetooth &&
        _status == ConnectionStatus.connected &&
        !_btService.isConnected) {
      _handleTransportDrop('Bluetooth link lost');
    }
  }

  void _completeAllPending(String value) {
    if (_wifiPendingCmd != null && !_wifiPendingCmd!.isCompleted) {
      _wifiPendingCmd!.complete(value);
    }
    _wifiPendingCmd = null;
    if (_btPendingCmd != null && !_btPendingCmd!.isCompleted) {
      _btPendingCmd!.complete(value);
    }
    _btPendingCmd = null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ELM327 INITIALISATION — with adaptive retry
  // ══════════════════════════════════════════════════════════════════════════
  Future<bool> _initElm327WithRetry() async {
    const maxAttempts = 3;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      _cmdTimeout = Duration(
          seconds: (_cmdTimeoutMin.inSeconds +
                  (attempt - 1) *
                      ((_cmdTimeoutMax.inSeconds - _cmdTimeoutMin.inSeconds) /
                              (maxAttempts - 1))
                          .round())
              .clamp(_cmdTimeoutMin.inSeconds, _cmdTimeoutMax.inSeconds));

      _setStatus(ConnectionStatus.connecting,
          'Initialising ELM327 (attempt $attempt/$maxAttempts, timeout ${_cmdTimeout.inSeconds}s)…');

      final ok = await _runInitSequence();
      if (ok) {
        _cmdTimeout = _cmdTimeoutMin; // reset for normal polling
        return true;
      }

      if (attempt < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
    return false;
  }

  Future<bool> _runInitSequence() async {
    try {
      await _send(ObdPids.reset, delay: const Duration(milliseconds: 300));
      await Future.delayed(const Duration(milliseconds: 500));

      final echo = await _send(ObdPids.echoOff);
      if (_isDeadResponse(echo)) return false;

      await _send(ObdPids.linefeedsOff);
      await _send('ATS1');    // Spaces ON
      await _send('ATH1');    // Headers ON
      await _send('ATCAF0');  // Raw ISO-TP frames
      await _send('ATAT1');   // Adaptive timing
      await _send('ATST32');  // 200ms normal window

      final proto = await _send(ObdPids.autoProtocol);
      if (_isDeadResponse(proto)) return false;

      for (var attempt = 0; attempt < 3; attempt++) {
        final probe = await _send('0100');
        if (!_isDeadResponse(probe) && !probe.toUpperCase().contains('SEARCHING')) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }

      final dpn = await _send('ATDPN');
      if (_isDeadResponse(dpn)) return false;

      debugPrint('[ObdService] ELM327 initialised (ATH1/ATS1/ATCAF0)');
      return true;
    } catch (e) {
      debugPrint('[ObdService] Init sequence exception: $e');
      return false;
    }
  }

  bool _isDeadResponse(String r) {
    if (r.isEmpty) return true;
    final upper = r.toUpperCase();
    return upper.contains('TIMEOUT') ||
        upper == 'DISCONNECTED' ||
        upper.contains('ERROR');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COMMAND SEND — routes to correct transport
  // ══════════════════════════════════════════════════════════════════════════
  Future<String> _send(String cmd, {Duration? delay}) async {
    if (delay != null) await Future.delayed(delay);
    try {
      if (_transport == ConnectionType.wifi) {
        return await _sendWifi(cmd);
      } else {
        return await _sendBt(cmd);
      }
    } catch (e) {
      debugPrint('[ObdService] _send exception for "$cmd": $e');
      return 'ERROR';
    }
  }

  Future<String> _sendWifi(String cmd) async {
    if (_wifiSocket == null) return 'DISCONNECTED';

    _wifiBuffer.clear();
    _wifiPendingCmd = Completer<String>();

    try {
      _wifiSocket!.write('$cmd\r');
      await _wifiSocket!.flush();
    } catch (e) {
      _wifiPendingCmd = null;
      return 'ERROR';
    }

    final completer = _wifiPendingCmd!;
    return completer.future.timeout(_cmdTimeout, onTimeout: () {
      _consecutiveTimeouts++;
      if (_wifiPendingCmd == completer) _wifiPendingCmd = null;
      return 'TIMEOUT';
    }).then((value) {
      if (value != 'TIMEOUT' && value != 'ERROR' && value.isNotEmpty) {
        _consecutiveTimeouts = 0;
        _lastGoodResponseAt = DateTime.now();
      }
      return value;
    });
  }

  Future<String> _sendBt(String cmd) async {
    if (!_btService.isConnected) return 'DISCONNECTED';

    _btBuffer.clear();
    _btPendingCmd = Completer<String>();

    final ok = await _btService.write(cmd);
    if (!ok) {
      _btPendingCmd = null;
      return 'ERROR';
    }

    final completer = _btPendingCmd!;
    return completer.future.timeout(_cmdTimeout, onTimeout: () {
      _consecutiveTimeouts++;
      if (_btPendingCmd == completer) _btPendingCmd = null;
      return 'TIMEOUT';
    }).then((value) {
      if (value != 'TIMEOUT' && value != 'ERROR' && value.isNotEmpty) {
        _consecutiveTimeouts = 0;
        _lastGoodResponseAt = DateTime.now();
      }
      return value;
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // POLLING LOOP
  // ══════════════════════════════════════════════════════════════════════════
  void _startPolling() {
    if (_isPolling) return;
    _isPolling = true;
    _pidIndex = 0;
    unawaited(_pollLoop());
  }

  void _stopPolling() {
    _isPolling = false;
  }

  Future<void> _pollLoop() async {
    while (_isPolling && isConnected) {
      if (_pollLocked) {
        // A foreground command (e.g. clearDtcs) owns the socket right now —
        // back off instead of writing a PID request on top of it.
        await Future.delayed(const Duration(milliseconds: 50));
        continue;
      }

      final pid = _pids[_pidIndex % _pids.length];
      _pidIndex++;

      try {
        if (pid.command == ObdPids.voltage.command) {
          await _pollBatteryVoltage();
        } else {
          final response = await _send(pid.command);

          if (_isUsableResponse(response)) {
            final value = ObdParser.parsePid(
                pid.command, _stripCanHeaderForLivePid(response));
            if (value != null) _updateData(pid.command, value);
          }
        }

        // If we've had too many consecutive timeouts, the link is likely dead.
        if (_consecutiveTimeouts >= 6) {
          debugPrint(
              '[ObdService] 6 consecutive timeouts — link considered dead');
          _handleTransportDrop('Lost connection to adapter (no response)');
          return;
        }
      } catch (e) {
        debugPrint('[ObdService] Poll loop exception: $e');
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // ── Battery voltage: Mode 01 PID 0142 primary, AT RV secondary ───────────
  // PID 0142 (Control Module Voltage) comes straight from the ECU's own
  // sense line, bypassing the ELM327's ADC entirely, so it's the source of
  // truth whenever a vehicle implements it. Most don't, so the fallback is
  // the adapter's own "AT RV" Pin-16 read — which on cheap/uncalibrated
  // clone adapters can under-report by a roughly constant factor.
  Future<void> _pollBatteryVoltage() async {
    final pidResponse = await _send(ObdPids.voltage.command);
    if (_isUsableResponse(pidResponse)) {
      final pidValue = ObdParser.parsePid(
          ObdPids.voltage.command, _stripCanHeaderForLivePid(pidResponse));
      // Sanity band, not a narrow "expected normal" band: PID 0142 is
      // ECU-reported, so a low-but-plausible value here is real fault data
      // (dying battery/alternator), not adapter noise — it must not be
      // discarded or handed to the clone-compensation heuristic below.
      if (pidValue != null && pidValue >= _voltageNoiseFloor && pidValue <= _voltageNoiseCeiling) {
        _data = _data.copyWith(batteryVoltage: pidValue);
        notifyListeners();
        return;
      }
    }

    final rvResponse = await _send(ObdPids.readVoltage);
    double? value = ObdParser.parseAtRvVoltage(rvResponse);
    if (value == null) return;

    // Noise guard: implausible readings are line noise, not data.
    if (value < _voltageNoiseFloor || value > _voltageNoiseCeiling) return;

    // Clone ADC compensation: an uncalibrated divider resistor under-reports
    // by a roughly constant factor. Only apply it while the engine is
    // confirmed running (RPM > 500, alternator charging) and the raw reading
    // sits in the "dead battery while running" band that's characteristic of
    // divider miscalibration rather than a real fault. Scale multiplicatively
    // rather than clamp to a fixed "normal" value, so a genuine failing
    // alternator/battery still reads low after correction instead of being
    // masked as healthy.
    final rpm = _data.rpm;
    if (value >= 8.0 && value <= 11.0 && rpm != null && rpm > 500) {
      value = value * 1.35;
    }

    _data = _data.copyWith(batteryVoltage: value);
    notifyListeners();
  }

  static const double _voltageNoiseFloor = 6.0;
  static const double _voltageNoiseCeiling = 18.0;

  bool _isUsableResponse(String r) {
    if (r.isEmpty) return false;
    final upper = r.toUpperCase();
    if (upper.contains('TIMEOUT')) return false;
    if (upper.contains('ERROR')) return false;
    if (upper.contains('NO DATA')) return false;
    if (upper.contains('NODATA')) return false;
    if (upper.contains('UNABLE')) return false;
    if (upper.contains('DISCONNECTED')) return false;
    if (upper.contains('STOPPED')) return false;
    if (upper.contains('SEARCHING')) return false;
    if (upper.contains('BUS INIT')) return false;
    return true;
  }

  bool _isUsableDtcResponse(String r) {
    if (r.isEmpty) return false;
    final upper = r.toUpperCase();

    if (upper.contains('TIMEOUT') || upper.contains('DISCONNECTED') ||
        upper.contains('UNABLE TO CONNECT') || upper.contains('BUS INIT: ERROR') ||
        upper.contains('CAN ERROR')) {
      return false;
    }

    final lines = upper.split(RegExp(r'[\r\n]+'));
    final hasNoData = lines.any((l) => l.trim() == 'NO DATA');
    if (hasNoData && lines.length <= 2) return true;

    final serviceLine = RegExp(r'\b4[37A]\b|4[37A][0-9A-F]{2}');
    return lines.any((l) => serviceLine.hasMatch(l.replaceAll(' ', '')) || serviceLine.hasMatch(l));
  }

  void _updateData(String command, double value) {
    switch (command) {
      case '010C':
        _data = _data.copyWith(rpm: value);
        break;
      case '010D':
        _data = _data.copyWith(speed: value);
        break;
      case '0105':
        _data = _data.copyWith(coolantTemp: value);
        break;
      case '010F':
        _data = _data.copyWith(intakeTemp: value);
        break;
      case '0111':
        _data = _data.copyWith(throttle: value);
        break;
      case '0104':
        _data = _data.copyWith(engineLoad: value);
        break;
      case '012F':
        _data = _data.copyWith(fuelLevel: value);
        break;
      case '010A':
        _data = _data.copyWith(fuelPressure: value);
        break;
      case '0110':
        _data = _data.copyWith(maf: value);
        break;
      case '010B':
        _data = _data.copyWith(manifoldPressure: value);
        break;
      case '010E':
        _data = _data.copyWith(timingAdvance: value);
        break;
      case '0142':
        _data = _data.copyWith(batteryVoltage: value);
        break;
      case '0106':
        _data = _data.copyWith(shortFuelTrim: value);
        break;
      case '0107':
        _data = _data.copyWith(longFuelTrim: value);
        break;
      case '011F':
        _data = _data.copyWith(runTime: value);
        break;
      default:
        break;
    }
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DTC READ / CLEAR
  // ══════════════════════════════════════════════════════════════════════════
  Future<List<DtcCode>> readDtcs() async {
    if (!isConnected) return [];
    if (_dtcReadInFlight) return _dtcCodes;
    _dtcReadInFlight = true;

    _acquirePollLock();
    await _waitForLinkIdle();

    final previousTimeout = _cmdTimeout;
    try {
      if (_cmdTimeout < _readDtcsMinTimeout) {
        _cmdTimeout = _readDtcsMinTimeout;
      }

      await _send('ATAT0');
      await _send('ATST7D');

      final response = await _send(ObdPids.readDtcs);

      if (!_isUsableDtcResponse(response)) {
        debugPrint('[ObdService] readDtcs unusable response: "$response" — keeping previous codes');
        return _dtcCodes;
      }

      final codes = ObdParser.parseDtcs(response);

      _dtcCodes = codes.map((code) {
        final info = _dtcInfo(code);
        return DtcCode(
          code: code,
          description: info['desc']!,
          possibleCause: info['cause']!,
          severity: info['severity']!,
          action: info['action']!,
        );
      }).toList();

      notifyListeners();
      return _dtcCodes;
    } catch (e) {
      debugPrint('[ObdService] readDtcs exception: $e');
      return _dtcCodes;
    } finally {
      await _send('ATST32');
      await _send('ATAT1');
      _cmdTimeout = previousTimeout;
      _releasePollLock();
      _dtcReadInFlight = false;
    }
  }

  Future<bool> clearDtcs() async {
    if (!isConnected) return false;

    // Lock the poll loop out of the socket, then wait for whatever PID
    // request it may already have in flight to finish, so 04 never lands
    // on the wire concurrently with a live poll (the serial collision that
    // caused "Connection Failed" on real vehicles).
    _acquirePollLock();
    await _waitForLinkIdle();

    final previousTimeout = _cmdTimeout;
    try {
      if (_cmdTimeout < _clearDtcsMinTimeout) {
        _cmdTimeout = _clearDtcsMinTimeout;
      }

      final response = await _send(ObdPids.clearDtcs);
      if (_isClearDtcsSuccess(response)) {
        _dtcCodes = [];
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[ObdService] clearDtcs exception: $e');
      return false;
    } finally {
      _cmdTimeout = previousTimeout;
      _releasePollLock();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FREEZE FRAME (Mode 02) — sensor snapshot captured when a DTC was set
  // ══════════════════════════════════════════════════════════════════════════
  /// Fetches the Mode 02 freeze frame snapshot (DTC, RPM, speed, coolant
  /// temp, engine load) using the same serial-safety mechanism as
  /// clearDtcs(): lock the poll loop out of the socket, wait for any
  /// in-flight live PID request to finish, run the freeze frame batch, then
  /// always release the lock so live telemetry resumes immediately.
  Future<FreezeFrameData?> fetchFreezeFrame() async {
    if (!isConnected) return null;

    _acquirePollLock();
    await _waitForLinkIdle();

    try {
      final dtcResponse = await _send(ObdPids.freezeFrameDtc);
      final rpmResponse = await _send(ObdPids.freezeFrameRpm);
      final speedResponse = await _send(ObdPids.freezeFrameSpeed);
      final coolantResponse = await _send(ObdPids.freezeFrameCoolantTemp);
      final loadResponse = await _send(ObdPids.freezeFrameEngineLoad);

      final dtc = _isUsableResponse(dtcResponse)
          ? ObdParser.parseFreezeFrameDtc(_stripCanHeaderForLivePid(dtcResponse))
          : null;
      final rpm = _isUsableResponse(rpmResponse)
          ? ObdParser.parseFreezeFramePid(
              ObdPids.freezeFrameRpm, _stripCanHeaderForLivePid(rpmResponse))
          : null;
      final speed = _isUsableResponse(speedResponse)
          ? ObdParser.parseFreezeFramePid(
              ObdPids.freezeFrameSpeed, _stripCanHeaderForLivePid(speedResponse))
          : null;
      final coolantTemp = _isUsableResponse(coolantResponse)
          ? ObdParser.parseFreezeFramePid(ObdPids.freezeFrameCoolantTemp,
              _stripCanHeaderForLivePid(coolantResponse))
          : null;
      final engineLoad = _isUsableResponse(loadResponse)
          ? ObdParser.parseFreezeFramePid(
              ObdPids.freezeFrameEngineLoad, _stripCanHeaderForLivePid(loadResponse))
          : null;

      final snapshot = FreezeFrameData(
        dtcCode: dtc,
        rpm: rpm,
        speed: speed,
        coolantTemp: coolantTemp,
        engineLoad: engineLoad,
        capturedAt: DateTime.now(),
      );

      return snapshot.hasData ? snapshot : null;
    } catch (e) {
      debugPrint('[ObdService] fetchFreezeFrame exception: $e');
      return null;
    } finally {
      _releasePollLock();
    }
  }

  /// Wait for any PID request the poll loop already had in flight to
  /// complete, capped so a stuck link can't hang clearDtcs() forever.
  Future<void> _waitForLinkIdle() async {
    final deadline = DateTime.now().add(_cmdTimeout + const Duration(seconds: 1));
    while ((_wifiPendingCmd != null && !_wifiPendingCmd!.isCompleted) ||
        (_btPendingCmd != null && !_btPendingCmd!.isCompleted)) {
      if (DateTime.now().isAfter(deadline)) break;
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  /// ELM327 replies to 04 with "44", "44 00", "OK", or "NO DATA" (already
  /// clean) — all of those mean the wipe succeeded.
  bool _isClearDtcsSuccess(String r) {
    if (r.isEmpty) return false;
    final upper = r.toUpperCase();
    if (upper.contains('TIMEOUT')) return false;
    if (upper.contains('ERROR')) return false;
    if (upper.contains('UNABLE')) return false;
    if (upper.contains('DISCONNECTED')) return false;
    return upper.contains('44') || upper.contains('OK') || upper.contains('NO DATA');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DISCONNECT
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> disconnect() async {
    _stopPolling();
    _completeAllPending('DISCONNECTED');

    _wifiSub?.cancel();
    _wifiSub = null;
    _btDataSub?.cancel();
    _btDataSub = null;

    if (_transport == ConnectionType.wifi) {
      try {
        await _wifiSocket?.close();
      } catch (_) {}
      _wifiSocket = null;
    } else {
      try {
        await _btService.disconnect();
      } catch (_) {}
    }

    _wifiBuffer.clear();
    _btBuffer.clear();
    _data = VehicleData.empty();
    _dtcCodes = [];
    _resetDiagnostics();
    _setStatus(ConnectionStatus.disconnected, 'Disconnected');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════
  void _resetDiagnostics() {
    _consecutiveTimeouts = 0;
    _lastGoodResponseAt = null;
    _cmdTimeout = _cmdTimeoutMin;
  }

  void _setStatus(ConnectionStatus s, String msg) {
    _status = s;
    _statusMessage = msg;
    notifyListeners();
  }

  Map<String, String> _dtcInfo(String code) => DtcDatabase.lookup(code);

  @override
  void dispose() {
    _btService.removeListener(_onBtServiceChanged);
    _stopPolling();
    _wifiSub?.cancel();
    _btDataSub?.cancel();
    super.dispose();
  }
}

void unawaited(Future<void> future) {}
