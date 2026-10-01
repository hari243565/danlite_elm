/// A programmable ELM327 + motorcycle for the fault-code safety tests.
///
/// Like the simulators in the existing suites it extends the real
/// [BluetoothClassicService] and lets the REAL [ObdService] run its real init
/// sequence, framing, link-health logic and engine read over it. Every
/// response shape is hand-written from documented ELM327 behaviour, NOT
/// recorded from a real bike — there are no real-bike transcripts yet (the
/// tester-mode session recorder exists to collect them).
library;

import 'dart:async';

import 'package:danlite_elm/services/bluetooth_classic_service.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter_test/flutter_test.dart';

class EngineSim extends BluetoothClassicService {
  EngineSim({
    this.supportedPids = '41 00 BE 3E B8 11',
    this.mode03 = '43 00',
    this.protocol = 'A6',
    bool vehicleSilent = false,
  }) {
    // A bike whose computer is not answering answers nothing — live PIDs
    // included.
    if (vehicleSilent) livePids = <String, String>{};
  }

  /// Reply to `0100`. Set to e.g. `NO DATA` or `UNABLE TO CONNECT` for a
  /// silent bike.
  String supportedPids;

  /// Reply payload to `03` (without the trailing prompt). `null` means the
  /// adapter never answers at all — the app-side window times out.
  String? mode03;

  /// Reply to `ATDPN`.
  String protocol;

  /// Live PID replies. Anything absent answers `NO DATA`.
  Map<String, String> livePids = <String, String>{
    '010C': '41 0C 0B B8',
    '0105': '41 05 5A',
  };

  final _ctrl = StreamController<String>.broadcast();
  final List<String> wire = <String>[];
  bool _connected = false;

  @override
  Stream<String> get dataStream => _ctrl.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect(BtDevice device) async {
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  /// Simulate the Bluetooth link dropping (rider walks away / BT off).
  void dropLink() {
    _connected = false;
    notifyListeners();
  }

  @override
  Future<bool> write(String cmd) async {
    if (!_connected) return false;
    wire.add(cmd);
    final c = cmd.trim().toUpperCase();
    final reply = _reply(c);
    if (reply == null) return true; // accepted, never answered
    scheduleMicrotask(() {
      if (!_ctrl.isClosed) _ctrl.add(reply);
    });
    return true;
  }

  String? _reply(String c) {
    if (c.isEmpty) return '\r>';
    if (c == 'ATZ') return '\r\rELM327 v1.5\r\r>';
    if (c == 'ATDPN') return '\r$protocol\r\r>';
    if (c.startsWith('AT')) return '\rOK\r\r>';
    if (c == '0100') return '\r$supportedPids\r\r>';
    if (c == '03') {
      final m = mode03;
      if (m == null) return null;
      return m.isEmpty ? '\r>' : '\r$m\r\r>';
    }
    final live = livePids[c];
    return '\r${live ?? 'NO DATA'}\r\r>';
  }

  Future<void> close() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }
}

const BtDevice simDevice =
    BtDevice(name: 'OBDII', address: '00:11:22:33:44:55', bonded: true);

/// Connect a real [ObdService] to [sim]. The adapter always initialises; the
/// vehicle may or may not answer.
Future<ObdService> connectSim(EngineSim sim) async {
  final obd = ObdService(sim);
  final ok = await obd.connectBluetooth(simDevice);
  expect(ok, isTrue, reason: 'the simulated adapter must complete init');
  return obd;
}
