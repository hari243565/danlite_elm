import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants/chassis_dtc_dictionary.dart';
import '../constants/chassis_modules.dart';
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

  // ── Chassis / ABS module scan state ───────────────────────────────────────
  // Kept separate from _dtcCodes rather than merged into it: these come from a
  // different module via a different service, and conflating them would make
  // "clear codes" (Mode 04, engine-only) look like it applied to ABS faults
  // when it does not.
  List<DtcCode> _chassisDtcCodes = [];
  List<DtcCode> get chassisDtcCodes => _chassisDtcCodes;

  ChassisScanOutcome _chassisScanOutcome = ChassisScanOutcome.idle;
  ChassisScanOutcome get chassisScanOutcome => _chassisScanOutcome;

  /// Which candidate module address actually answered, for display/support.
  String _chassisRespondingModule = '';
  String get chassisRespondingModule => _chassisRespondingModule;

  /// Human-readable probe trace, surfaced in the UI so a failed scan can be
  /// diagnosed (wrong address vs. adapter refusing the command) instead of
  /// being an opaque "nothing found".
  List<String> _chassisScanLog = [];
  List<String> get chassisScanLog => _chassisScanLog;

  bool _chassisScanInFlight = false;
  bool get chassisScanInFlight => _chassisScanInFlight;

  String _lastError = '';
  String get lastError => _lastError;

  bool _linkSynced = true;
  bool get linkSynced => _linkSynced;
  bool _adapterWedged = false;
  bool get adapterWedged => _adapterWedged;

  int _consecutiveParseFailures = 0;
  int _recoveryAttempts = 0;
  DateTime? _lastHeaderRepairAt;

  final List<String> _wireLog = <String>[];
  static const int _wireLogMax = 200;
  List<String> get wireLog => List.unmodifiable(_wireLog);

  void _logWire(String direction, String data) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final printable = data.replaceAll('\r', r'\r').replaceAll('\n', r'\n');
    _wireLog.add('$ts $direction$printable');
    if (_wireLog.length > _wireLogMax) _wireLog.removeAt(0);
    debugPrint('[WIRE] $ts $direction$printable');
  }

  String exportWireLog() => _wireLog.join('\n');

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

  // A chassis/ABS scan is slower again: each candidate address costs a round
  // of ATSH/ATCRA/flow-control setup before the request itself, and a UDS
  // 19 02 reply is routinely multi-frame. Non-engine modules are also simply
  // less prompt than the engine ECU, which is polled continuously and stays
  // warm on the bus.
  static const Duration _chassisScanMinTimeout = Duration(milliseconds: 5000);

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
    _logWire('RX<', frame);

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
      // Init always starts from a clean gate — see _resetDiagnostics().
      _linkSynced = true;
      _adapterWedged = false;
      await _send(ObdPids.reset, delay: const Duration(milliseconds: 300));
      await Future.delayed(const Duration(milliseconds: 500));

      final echo = await _send(ObdPids.echoOff);
      if (_isDeadResponse(echo)) return false;

      await _send(ObdPids.linefeedsOff);
      await _send(ObdPids.spacesOff);
      await _send(ObdPids.headersOff);

      final proto = await _send(ObdPids.autoProtocol);
      if (_isDeadResponse(proto)) return false;

      final at = await _send('ATAT1');
      if (_isDeadResponse(at)) debugPrint('[ObdService] ATAT1 unsupported');
      final st = await _send('ATST32');
      if (_isDeadResponse(st)) debugPrint('[ObdService] ATST32 unsupported');

      for (var attempt = 0; attempt < 2; attempt++) {
        final probe = await _send('0100');
        if (!_isDeadResponse(probe) && !probe.toUpperCase().contains('SEARCHING')) break;
        await Future.delayed(const Duration(milliseconds: 300));
      }

      final dpn = await _send('ATDPN');
      debugPrint('[ObdService] protocol (ATDPN): "$dpn"');
      debugPrint('[ObdService] init OK — live baseline ATH0/ATS0');
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
    if (!_linkSynced) {
      // A blocked write must still count toward the dead-link detector.
      // Without this, _consecutiveTimeouts freezes and _pollLoop's
      // >= 6 check can never fire, leaving the UI stuck on "Connected".
      _consecutiveTimeouts++;
      debugPrint('[ObdService] BLOCKED write "$cmd" — link not synced');
      return 'TIMEOUT';
    }
    if (delay != null) await Future.delayed(delay);
    return await _sendRaw(cmd);
  }

  Future<String> _sendRaw(String cmd) async {
    try {
      if (_transport == ConnectionType.wifi) {
        return await _sendWifi(cmd);
      } else {
        return await _sendBt(cmd);
      }
    } catch (e) {
      return 'ERROR';
    }
  }

  Future<bool> _recoverAdapter() async {
    debugPrint('[ObdService] attempting adapter recovery…');
    _linkSynced = true;
    await Future.delayed(const Duration(milliseconds: 600));

    final saved = _cmdTimeout;
    _cmdTimeout = const Duration(seconds: 2);
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final r = await _sendRaw('');
        if (!_isDeadResponse(r)) {
          debugPrint('[ObdService] adapter responded to CR — resynced');
          _adapterWedged = false;
          _linkSynced = true;
          return true;
        }
        await Future.delayed(const Duration(milliseconds: 400));
      }

      _cmdTimeout = const Duration(seconds: 5);
      final z = await _sendRaw(ObdPids.reset);
      await Future.delayed(const Duration(milliseconds: 900));
      if (!_isDeadResponse(z)) {
        debugPrint('[ObdService] adapter reset — re-running init');
        final ok = await _runInitSequence();
        _adapterWedged = !ok;
        _linkSynced = ok;
        return ok;
      }

      debugPrint('[ObdService] adapter unresponsive — power cycle required');
      _adapterWedged = true;
      _linkSynced = false;
      _handleTransportDrop('Adapter stopped responding. Unplug it, wait 5 seconds, plug it back in and reconnect.');
      return false;
    } finally {
      _cmdTimeout = saved;
    }
  }

  Future<bool> _enableDtcHeaders() async {
    if (!_linkSynced) return false;
    final s = await _send('ATS1');
    if (_isDeadResponse(s)) return false;
    final h = await _send('ATH1');
    if (_isDeadResponse(h)) {
      await _send(ObdPids.spacesOff);
      return false;
    }
    return true;
  }

  Future<void> _restoreLiveHeaders() async {
    if (!_linkSynced) return;
    await _send(ObdPids.headersOff);
    await _send(ObdPids.spacesOff);
  }

  Future<void> _repairLiveMode() async {
    final now = DateTime.now();
    if (_lastHeaderRepairAt != null && now.difference(_lastHeaderRepairAt!) < const Duration(seconds: 20)) return;
    _lastHeaderRepairAt = now;
    _consecutiveParseFailures = 0;
    if (!_linkSynced) {
      await _recoverAdapter();
      return;
    }
    await _send(ObdPids.headersOff);
    await _send(ObdPids.spacesOff);
  }

  Future<String> _sendWifi(String cmd) async {
    if (_wifiSocket == null) return 'DISCONNECTED';

    _wifiBuffer.clear();
    _wifiPendingCmd = Completer<String>();

    try {
      _logWire('TX>', cmd);
      _wifiSocket!.write('$cmd\r');
      await _wifiSocket!.flush();
    } catch (e) {
      _wifiPendingCmd = null;
      return 'ERROR';
    }

    final completer = _wifiPendingCmd!;
    return completer.future.timeout(_cmdTimeout, onTimeout: () {
      _consecutiveTimeouts++;
      _linkSynced = false;
      if (_wifiPendingCmd == completer) _wifiPendingCmd = null;
      return 'TIMEOUT';
    }).then((value) {
      if (value != 'TIMEOUT' && value != 'ERROR' && value.isNotEmpty) {
        _consecutiveTimeouts = 0;
        _linkSynced = true;
        _adapterWedged = false;
        _lastGoodResponseAt = DateTime.now();
      }
      return value;
    });
  }

  Future<String> _sendBt(String cmd) async {
    if (!_btService.isConnected) return 'DISCONNECTED';

    _btBuffer.clear();
    _btPendingCmd = Completer<String>();

    _logWire('TX>', cmd);
    final ok = await _btService.write(cmd);
    if (!ok) {
      _btPendingCmd = null;
      return 'ERROR';
    }

    final completer = _btPendingCmd!;
    return completer.future.timeout(_cmdTimeout, onTimeout: () {
      _consecutiveTimeouts++;
      _linkSynced = false;
      if (_btPendingCmd == completer) _btPendingCmd = null;
      return 'TIMEOUT';
    }).then((value) {
      if (value != 'TIMEOUT' && value != 'ERROR' && value.isNotEmpty) {
        _consecutiveTimeouts = 0;
        _linkSynced = true;
        _adapterWedged = false;
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

      // The link gate closed on a previous timeout. Try to reopen it before
      // writing anything — otherwise every send below is silently discarded
      // and the dashboard freezes while still reporting "Connected".
      if (!_linkSynced) {
        // Bound the retries. A half-wedged adapter can answer a bare CR
        // while never servicing a PID, which would otherwise loop forever
        // with a frozen dashboard still showing "Connected".
        if (_recoveryAttempts >= 3) {
          _handleTransportDrop('Adapter stopped responding');
          return;
        }
        _recoveryAttempts++;
        final recovered = await _recoverAdapter();
        // _recoverAdapter already calls _handleTransportDrop when it gives up.
        if (!recovered) return;
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
            final value = ObdParser.parsePid(pid.command, _stripCanHeaderForLivePid(response));
            if (value != null) {
              _updateData(pid.command, value);
              _consecutiveParseFailures = 0;
              _recoveryAttempts = 0;
            } else {
              _consecutiveParseFailures++;
              if (_consecutiveParseFailures >= 5) await _repairLiveMode();
            }
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
    var headersOn = false;
    var stWidened = false;
    try {
      if (!_linkSynced) {
        final recovered = await _recoverAdapter();
        if (!recovered) return _dtcCodes;
      }

      if (_cmdTimeout < _readDtcsMinTimeout) _cmdTimeout = _readDtcsMinTimeout;

      headersOn = await _enableDtcHeaders();
      final stResp = await _send('ATST7D');
      stWidened = !_isDeadResponse(stResp);

      var response = await _send(ObdPids.readDtcs);

      if (response == 'TIMEOUT') {
        await _recoverAdapter();
        return _dtcCodes;
      }

      if (!_isUsableDtcResponse(response)) return _dtcCodes;

      var parsed = ObdParser.parseDetailed(response);

      if (parsed.countMismatch) {
        await Future.delayed(const Duration(milliseconds: 300));
        final retryResp = await _send(ObdPids.readDtcs);
        if (retryResp != 'TIMEOUT' && _isUsableDtcResponse(retryResp)) {
          final retry = ObdParser.parseDetailed(retryResp);
          if (!retry.countMismatch || retry.allCodes.length > parsed.allCodes.length) {
            parsed = retry;
            response = retryResp;
          }
        }
      }

      _dtcCodes = parsed.powertrainCodes.map((code) {
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
      if (stWidened && _linkSynced) await _send('ATST32');
      if (headersOn) await _restoreLiveHeaders();
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
  // CHASSIS / ABS MODULE SCAN
  // ══════════════════════════════════════════════════════════════════════════
  /// Read stored fault codes from the ABS/chassis module.
  ///
  /// This deliberately does NOT reuse [readDtcs]. Mode 03 goes out on the OBD
  /// functional address, which only emissions ECUs are obliged to answer; an
  /// ABS module is not one, so Mode 03 alone returns nothing from it no matter
  /// how healthy it is. Instead each candidate module address is taken in
  /// turn: `ATSH` retargets the adapter's transmit header at that module,
  /// `ATCRA` filters reception so no other ECU's traffic can be misread as an
  /// ABS reply, flow control is pointed back at the same module, and the UDS
  /// request `19 02 FF` (ReadDTCInformation / reportDTCByStatusMask) is sent.
  /// Plain `03` is then tried against the same physical address, because some
  /// chassis modules implement it once addressed directly.
  ///
  /// Unlike the engine read this is manual-only, never looped: it rewrites the
  /// adapter's addressing state, so it re-runs the init sequence afterwards to
  /// restore known-good live telemetry. Running that every five seconds would
  /// starve the dashboard.
  ///
  /// [vehicleMake] and [vehicleModel] are the free-text fields from the active
  /// vehicle profile. Together they select which platform dictionary the
  /// returned codes are described from, via [ChassisPlatforms.resolve]: the
  /// model is required because one manufacturer can ship several ABS platforms
  /// whose code systems disagree. The make alone still selects the module
  /// probe order, which is a manufacturer-level concern.
  ///
  /// When the platform cannot be identified the scan still runs and still
  /// returns the codes it read — only their descriptions are withheld, because
  /// describing a braking fault from the wrong platform's table is worse than
  /// describing nothing.
  Future<List<DtcCode>> readChassisDtcs({
    String? vehicleMake,
    String? vehicleModel,
  }) async {
    if (!isConnected) {
      _chassisScanOutcome = ChassisScanOutcome.linkUnavailable;
      notifyListeners();
      return _chassisDtcCodes;
    }
    if (_chassisScanInFlight) return _chassisDtcCodes;

    _chassisScanInFlight = true;
    notifyListeners();

    // Two different keys, deliberately: the module probe order is a
    // manufacturer-level concern (which CAN address the ABS ECU sits at),
    // while the fault dictionary is a platform-level one (what a given code
    // number means on this specific model family).
    final manufacturerKey = ChassisManufacturers.resolveKey(vehicleMake);
    final platformKey = ChassisPlatforms.resolve(vehicleMake, vehicleModel);
    final log = <String>[];
    final previousTimeout = _cmdTimeout;

    var headersOn = false;
    var stWidened = false;
    var addressingChanged = false;
    var addressingAccepted = false;

    _acquirePollLock();
    await _waitForLinkIdle();

    try {
      if (!_linkSynced) {
        final recovered = await _recoverAdapter();
        if (!recovered) {
          _chassisScanOutcome = ChassisScanOutcome.linkUnavailable;
          log.add('Adapter link could not be resynced.');
          return _chassisDtcCodes;
        }
      }

      // Chassis modules are slower to answer than the engine ECU, and a UDS
      // reply is usually multi-frame. Widen both the app-side and adapter-side
      // timeouts for the duration of the scan.
      if (_cmdTimeout < _chassisScanMinTimeout) _cmdTimeout = _chassisScanMinTimeout;
      headersOn = await _enableDtcHeaders();
      final stResp = await _send('ATST7D');
      stWidened = !_isDeadResponse(stResp);

      final candidates = ChassisModuleProfiles.candidatesFor(manufacturerKey);
      List<DtcCode>? found;

      for (final target in candidates) {
        if (found != null) break;

        final shResp = await _send(target.headerCommand);
        if (_isDeadResponse(shResp) || shResp.contains('?')) {
          log.add('${target.label}: adapter rejected ${target.headerCommand}.');
          continue;
        }
        addressingChanged = true;
        addressingAccepted = true;

        final craResp = await _send(target.filterCommand);
        if (_isDeadResponse(craResp) || craResp.contains('?')) {
          // Not fatal: without the filter we may also see other ECUs, but the
          // parser groups by ECU id so the reply is still attributable.
          log.add('${target.label}: ATCRA unsupported — reading unfiltered.');
        }

        // Flow control must point back at the module we are addressing, or a
        // multi-frame UDS reply stalls after the first frame.
        for (final cmd in target.flowControlCommands) {
          await _send(cmd);
        }

        for (final request in target.requests) {
          final response = await _send(request);

          if (response == 'TIMEOUT') {
            log.add('${target.label} · $request: timeout.');
            await _recoverAdapter();
            continue;
          }
          if (_isChassisNoReply(response)) {
            log.add('${target.label} · $request: no reply from module.');
            continue;
          }

          if (request.startsWith('19')) {
            final uds = ObdParser.parseUdsDtcDetailed(response);
            if (uds.negativeResponseCode != null) {
              log.add('${target.label} · $request: module refused '
                  '(NRC 0x${uds.negativeResponseCode!.toRadixString(16).toUpperCase()}).');
              continue;
            }
            if (!uds.sawPositiveResponse) {
              log.add('${target.label} · $request: reply not a 59 02 response.');
              continue;
            }
            log.add('${target.label} · $request: answered — '
                '${uds.records.length} code(s).');
            _chassisRespondingModule = target.label;
            found = <DtcCode>[
              for (final r in uds.records)
                _buildChassisDtc(
                  code: r.code,
                  platformKey: platformKey,
                  failureTypeByte: r.failureTypeByte,
                  isConfirmed: r.isConfirmed,
                ),
            ];
            break;
          }

          // Mode 03 fallback against the physically-addressed module.
          if (!_isUsableDtcResponse(response)) {
            log.add('${target.label} · $request: unrecognised reply.');
            continue;
          }
          final parsed = ObdParser.parseDetailed(response);
          log.add('${target.label} · $request (Mode 03): answered — '
              '${parsed.allCodes.length} code(s).');
          _chassisRespondingModule = target.label;
          found = <DtcCode>[
            for (final code in parsed.allCodes)
              _buildChassisDtc(code: code, platformKey: platformKey),
          ];
          break;
        }
      }

      if (found == null) {
        _chassisDtcCodes = <DtcCode>[];
        _chassisScanOutcome = addressingAccepted
            ? ChassisScanOutcome.noModuleResponse
            : ChassisScanOutcome.addressingUnsupported;
      } else {
        _chassisDtcCodes = found;
        _chassisScanOutcome = found.isEmpty
            ? ChassisScanOutcome.clean
            : ChassisScanOutcome.faultsFound;
      }
      return _chassisDtcCodes;
    } catch (e) {
      debugPrint('[ObdService] readChassisDtcs exception: $e');
      log.add('Scan error: $e');
      _chassisScanOutcome = ChassisScanOutcome.noModuleResponse;
      return _chassisDtcCodes;
    } finally {
      _cmdTimeout = previousTimeout;
      // Restoring addressing matters more than saving time here: ATSH/ATCRA
      // persist on the adapter, and leaving them set would silently break
      // every subsequent live PID poll. Re-running the init sequence puts the
      // adapter back to the exact known-good live baseline the rest of the app
      // assumes.
      if (addressingChanged && _linkSynced) {
        await _send(ObdPids.autoReceiveAddress);
        await _send(ObdPids.clearReceiveFilter);
        final restored = await _runInitSequence();
        if (!restored) log.add('Warning: adapter re-init after scan failed.');
      } else {
        if (stWidened && _linkSynced) await _send('ATST32');
        if (headersOn) await _restoreLiveHeaders();
      }
      _chassisScanLog = List<String>.unmodifiable(log);
      _releasePollLock();
      _chassisScanInFlight = false;
      notifyListeners();
    }
  }

  /// Build a chassis [DtcCode], filling the manufacturer columns when the
  /// dictionary has a real entry and leaving them empty when it does not.
  ///
  /// Empty is deliberate: the UI renders an undocumented chassis code honestly
  /// as "no manufacturer description available" rather than inventing one for
  /// a braking-system fault.
  DtcCode _buildChassisDtc({
    required String code,
    required String? platformKey,
    int? failureTypeByte,
    bool isConfirmed = true,
  }) {
    final entry = ChassisDtcDatabase.lookup(platformKey, code);
    return DtcCode(
      code: code,
      description: entry?.description ?? '',
      possibleCause: entry?.query ?? '',
      severity: entry?.severity ?? 'unknown',
      action: entry?.remedy ?? '',
      module: 'chassis',
      component: entry?.component ?? '',
      query: entry?.query ?? '',
      remedy: entry?.remedy ?? '',
      failureTypeByte: failureTypeByte,
      isConfirmed: isConfirmed,
    );
  }

  /// True when a physically-addressed module produced nothing usable.
  ///
  /// "NO DATA" is treated as no-reply here, unlike the engine path: when the
  /// adapter is addressed at one specific module, NO DATA means that module
  /// did not answer at all — not that a healthy module reported zero faults.
  bool _isChassisNoReply(String r) {
    if (r.isEmpty) return true;
    final upper = r.toUpperCase();
    return upper.contains('NO DATA') ||
        upper.contains('NODATA') ||
        upper.contains('UNABLE TO CONNECT') ||
        upper.contains('CAN ERROR') ||
        upper.contains('BUS INIT') ||
        upper.contains('DISCONNECTED') ||
        upper.trim() == '?' ||
        upper.contains('STOPPED');
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
      if (!_linkSynced) {
        final recovered = await _recoverAdapter();
        if (!recovered) return null;
      }

      final responses = <String>[];
      for (final cmd in const [
        ObdPids.freezeFrameDtc,
        ObdPids.freezeFrameRpm,
        ObdPids.freezeFrameSpeed,
        ObdPids.freezeFrameCoolantTemp,
        ObdPids.freezeFrameEngineLoad,
      ]) {
        final r = await _send(cmd);
        if (r == 'TIMEOUT') {
          await _recoverAdapter();
          return null;
        }
        responses.add(r);
      }
      final dtcResponse = responses[0];
      final rpmResponse = responses[1];
      final speedResponse = responses[2];
      final coolantResponse = responses[3];
      final loadResponse = responses[4];

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

  /// Decide whether a Mode 04 (clear DTCs) reply indicates success.
  ///
  /// Deliberately permissive: the clear is treated as successful unless the
  /// reply carries a genuine failure signal. Motorcycles and single-ECU
  /// vehicles frequently acknowledge a successful wipe without emitting the
  /// literal "44" positive-response byte a car sends — a bare prompt, an
  /// echoed request, or an empty line are all valid acknowledgements.
  /// Matching only "44"/"OK"/"NO DATA" caused a false "Connection Failed"
  /// on bikes even though the codes were cleared.
  ///
  /// Still returns false for genuine failures:
  ///   - adapter/bus errors: TIMEOUT, ERROR, UNABLE, DISCONNECTED, STOPPED,
  ///     BUS INIT, BUS BUSY, BUFFER FULL
  ///   - ECU negative response "7F 04" — the ECU actively refused the clear
  ///     (engine running, security lockout); the codes were NOT cleared
  ///   - a reply consisting only of "SEARCHING" chatter, which means no ECU
  ///     acknowledgement was ever received
  bool _isClearDtcsSuccess(String r) {
    final upper = r.toUpperCase();

    if (upper.contains('TIMEOUT')) return false;
    if (upper.contains('ERROR')) return false;
    if (upper.contains('UNABLE')) return false;
    if (upper.contains('DISCONNECTED')) return false;
    if (upper.contains('STOPPED')) return false;
    if (upper.contains('BUS INIT')) return false;
    if (upper.contains('BUS BUSY')) return false;
    if (upper.contains('BUFFER FULL')) return false;

    // Scan per line so a byte-pair boundary cannot create a phantom "7F04"
    // match (e.g. "A7 F0 44"), and so a line that is only protocol chatter
    // is not mistaken for an acknowledgement.
    var sawRealLine = false;
    for (final rawLine in upper.split(RegExp(r'[\r\n]+'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.contains('SEARCHING')) continue; // chatter, not an ack
      sawRealLine = true;

      // ECU negative response frame "7F 04", checked on byte-pair boundaries.
      final compact = line.replaceAll(RegExp(r'[^0-9A-F]'), '');
      for (var i = 0; i + 4 <= compact.length; i += 2) {
        if (compact.substring(i, i + 4) == '7F04') return false;
      }
    }

    // Nothing but SEARCHING chatter — no acknowledgement was received.
    if (!sawRealLine && upper.contains('SEARCHING')) return false;

    return true;
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
    _recoveryAttempts = 0;
    _lastGoodResponseAt = null;
    _cmdTimeout = _cmdTimeoutMin;
    // A fresh session must never inherit a closed link gate from a previous
    // one. Without this, a single timeout permanently blocks all future
    // connection attempts, because _send() refuses to write while
    // _linkSynced is false and nothing else reopens it.
    _linkSynced = true;
    _adapterWedged = false;
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
