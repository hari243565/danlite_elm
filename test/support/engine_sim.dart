/// A programmable ELM327 + motorcycle for the fault-code safety tests.
///
/// Like the simulators in the existing suites it extends the real
/// [BluetoothClassicService] and lets the REAL [ObdService] run its real init
/// sequence, framing, link-health logic and engine read over it. Every
/// response shape is hand-written from documented ELM327 behaviour, NOT
/// recorded from a real bike — there are no real-bike transcripts yet (the
/// tester-mode session recorder exists to collect them).
///
/// Phase 1A adds: ABS/chassis modules reachable by `ATSH` addressing, extra
/// OBD replies (Mode 07 / 0A / 09, PID 01 01 / 0C / 42, `ATRV`), per-command
/// latency, and the two adapter personalities for "response pending":
///
///  * [AdapterPersonality.handlesPending] — a genuine ELM327 2.1+ / STN. It
///    absorbs the module's `7F xx 78` frames, keeps waiting, and returns only
///    the final answer, late.
///  * [AdapterPersonality.passesPending] — an ELM 1.x clone. It prints the
///    `7F xx 78` frame, hands back the prompt, and the real answer is lost;
///    the module answers properly only when the request is repeated.
library;

import 'dart:async';

import 'package:danlite_elm/services/bluetooth_classic_service.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter_test/flutter_test.dart';

enum AdapterPersonality { handlesPending, passesPending }

/// How long a module stays busy on one request: [times] "response pending"
/// frames before the real answer, or [forever].
class ModuleBusy {
  const ModuleBusy({required this.times}) : forever = false;
  const ModuleBusy.forever()
      : times = 0,
        forever = true;
  final int times;
  final bool forever;
}

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

  /// Replies to other OBD requests (`07`, `0A`, `0101`, `0142`, `0902`…).
  /// Checked before [livePids]. A `null` value never answers.
  Map<String, String?> extra = <String, String?>{};

  /// Reply to `ATRV`, e.g. `12.4V`. Null answers `?` (not supported).
  String? atrv;

  /// Chassis modules: `ATSH` header → reply to `19 02 FF` at that address.
  Map<String, String> udsModules = <String, String>{};

  /// Extra latency before a command's reply, by command.
  Map<String, Duration> latency = <String, Duration>{};

  /// Which adapter this is, for "response pending".
  AdapterPersonality personality = AdapterPersonality.handlesPending;

  /// Requests the module is busy on, by command.
  Map<String, ModuleBusy> busy = <String, ModuleBusy>{};

  /// How long each "response pending" period lasts on the module side.
  Duration pendingStep = const Duration(milliseconds: 20);

  final _ctrl = StreamController<String>.broadcast();
  final List<String> wire = <String>[];
  bool _connected = false;
  String? _header;
  final Map<String, int> _busyLeft = <String, int>{};

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

  void _emit(String payload, [Duration delay = Duration.zero]) {
    void add() {
      if (!_ctrl.isClosed) _ctrl.add(payload);
    }

    if (delay > Duration.zero) {
      Future<void>.delayed(delay, add);
    } else {
      scheduleMicrotask(add);
    }
  }

  @override
  Future<bool> write(String cmd) async {
    if (!_connected) return false;
    wire.add(cmd);
    final c = cmd.trim().toUpperCase();

    // Addressing state, tracked the way a real adapter holds it.
    if (c.startsWith('ATSH')) {
      _header = c.substring(4);
    } else if (c == 'ATZ' || c == 'ATSP0' || c == 'ATAR') {
      _header = null;
    }

    final reply = _reply(c);
    if (reply == null) return true; // accepted, never answered

    final delay = latency[c] ?? Duration.zero;
    final b = busy[c];
    if (b != null && reply.isNotEmpty && !_isNoData(reply)) {
      final left = _busyLeft.putIfAbsent(c, () => b.forever ? -1 : b.times);
      if (left != 0) {
        switch (personality) {
          case AdapterPersonality.handlesPending:
            // The adapter waits through every pending frame itself.
            if (b.forever) return true; // never answers
            _busyLeft[c] = 0;
            _emit('\r$reply\r\r>', delay + pendingStep * left);
            return true;
          case AdapterPersonality.passesPending:
            if (!b.forever) _busyLeft[c] = left - 1;
            _emit('\r${_pendingFrame(c, reply)}\r\r>', delay);
            return true;
        }
      }
    }
    _emit(reply.isEmpty ? '\r>' : '\r$reply\r\r>', delay);
    return true;
  }

  bool _isNoData(String r) => r.toUpperCase().contains('NO DATA');

  /// `7F <service> 78` from the same module the final answer comes from.
  String _pendingFrame(String cmd, String finalReply) {
    final sid = cmd.substring(0, 2);
    final first = finalReply.trim().split(RegExp(r'\s+')).first;
    final header = (first.length == 3 || first.length == 8) ? '$first ' : '';
    return header.isEmpty ? '7F $sid 78' : '${header}03 7F $sid 78';
  }

  String? _reply(String c) {
    if (c.isEmpty) return '';
    if (c == 'ATZ') return '\rELM327 v1.5\r';
    if (c == 'ATDPN') return protocol;
    if (c == 'ATRV') return atrv ?? '?';
    if (c.startsWith('AT')) return 'OK';
    if (c == '0100') return supportedPids;

    // Physically addressed at a chassis module.
    if (_header != null) {
      if (c == '1902FF') return udsModules[_header] ?? 'NO DATA';
      return 'NO DATA';
    }

    if (c == '03') return mode03;
    if (extra.containsKey(c)) return extra[c];
    return livePids[c] ?? 'NO DATA';
  }

  Future<void> close() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }
}

const BtDevice simDevice =
    BtDevice(name: 'OBDII', address: '00:11:22:33:44:55', bonded: true);

/// Connect a real [ObdService] to [sim]. The adapter always initialises; the
/// vehicle may or may not answer.
Future<ObdService> connectSim(EngineSim sim, {FaultReadTiming? timing}) async {
  final obd = ObdService(sim, faultTiming: timing);
  final ok = await obd.connectBluetooth(simDevice);
  expect(ok, isTrue, reason: 'the simulated adapter must complete init');
  return obd;
}
