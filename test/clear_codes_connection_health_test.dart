/// Danlite ELM — Clear Codes (Mode 04) connection-health classification tests
///
/// WHAT THIS PROVES: that the REAL ObdService, driven over a simulated ELM327
/// and ECU, tells "this command produced a thin or late reply" apart from "the
/// connection failed" — in BOTH directions. Nothing in ObdService is stubbed:
/// the actual init sequence, poll loop, buffer resolution, link-health
/// tracking, clearDtcs() and the shared reply classifier all run for real.
///
/// WHAT THIS DOES NOT PROVE: that any particular real vehicle behaves like the
/// simulated ECU here. The response shapes are modelled on documented ELM327
/// and OBD-II behaviour, not captured from a specific bike.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:danlite_elm/constants/obd_pids.dart';
import 'package:danlite_elm/models/vehicle_data.dart';
import 'package:danlite_elm/services/bluetooth_classic_service.dart';
import 'package:danlite_elm/services/obd_service.dart';

/// A simulated ELM327 sitting on a simulated single-ECU motorcycle.
class FakeElm extends BluetoothClassicService {
  FakeElm();

  /// Payload the ECU returns for Mode 04. `''` reproduces the bare-prompt
  /// acknowledgement common on single-ECU vehicles; `'44'` is the textbook
  /// car response; `'7F 04 22'` is an ECU actively refusing the erase.
  String mode04Payload = '';

  /// Extra latency before the ECU acknowledges the erase. A real ECU stops
  /// servicing the bus while it writes flash, so Mode 04 is the one command
  /// that routinely answers later than a live PID read does.
  Duration mode04Latency = Duration.zero;

  /// Simulates the adapter going away — Bluetooth switched off, or the rider
  /// walking out of range. Writes are still accepted by the stack; nothing
  /// ever comes back, exactly like a stalled SPP link.
  bool linkDead = false;

  /// The ECU's fault memory. A successful Mode 04 empties it, so Mode 03
  /// afterwards reports the truth rather than a canned answer.
  bool faultMemoryHasCodes = true;

  /// When false, a Mode 04 request does NOT actually erase anything — used to
  /// prove the confirmation step cannot rubber-stamp a clear that failed.
  bool eraseActuallyWorks = true;

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

  @override
  Future<bool> write(String cmd) async {
    if (!_connected) return false;
    wire.add(cmd);
    if (linkDead) return true; // accepted by the stack, never answered

    final c = cmd.trim().toUpperCase();
    // The erase lands on the ECU when the request goes out, not when the
    // acknowledgement comes back — which is precisely why a late or thin
    // acknowledgement must not be read as "nothing happened".
    if (c == '04' &&
        eraseActuallyWorks &&
        !mode04Payload.toUpperCase().startsWith('7F')) {
      faultMemoryHasCodes = false;
    }

    final reply = _reply(c);
    final latency = (c == '04') ? mode04Latency : Duration.zero;
    if (latency > Duration.zero) {
      Future.delayed(latency, () {
        if (!_ctrl.isClosed) _ctrl.add(reply);
      });
    } else {
      scheduleMicrotask(() => _ctrl.add(reply));
    }
    return true;
  }

  /// PIDs this simulated bike's single ECU actually implements. Everything
  /// else in ObdPids.allPids is unsupported, as on a real motorcycle.
  static const _supported = <String, String>{
    '010C': '41 0C 0B B8',
    '010D': '41 0D 00',
    '0105': '41 05 5A',
    '0111': '41 11 33',
    '0104': '41 04 40',
    '012F': '41 2F 80',
  };

  String _reply(String c) {
    if (c.isEmpty) return '\r>'; // bare CR -> prompt only
    if (c == 'ATZ') return '\r\rELM327 v1.5\r\r>';
    if (c == 'ATDPN') return '\r6\r\r>';
    if (c.startsWith('AT')) return '\rOK\r\r>';
    if (c == '0100') return '\r41 00 BE 3E B8 11\r\r>';
    if (c == '03') {
      return faultMemoryHasCodes ? '\r43 01 01 72\r\r>' : '\r43 00\r\r>';
    }
    if (c == '04') {
      return mode04Payload.isEmpty ? '\r>' : '\r$mode04Payload\r\r>';
    }
    final data = _supported[c];
    if (data != null) return '\r$data\r\r>';
    // Unsupported PID: the ECU stays silent and the adapter returns the
    // prompt alone. This is a delivered reply with an empty payload.
    return '\r>';
  }

  Future<void> close() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }
}

Future<ObdService> connectedService(FakeElm elm) async {
  final obd = ObdService(elm);
  final ok = await obd.connectBluetooth(
      const BtDevice(name: 'OBDII', address: '00:11:22:33:44:55', bonded: true));
  expect(ok, isTrue, reason: 'the simulated ELM327 must complete init');
  expect(obd.status, ConnectionStatus.connected);
  return obd;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════════
  // DIRECTION 1 — a successful clear must never be reported as a failure
  // ══════════════════════════════════════════════════════════════════════════
  group('a successful clear is not reported as a connection failure', () {
    test('bare-prompt acknowledgement (single-ECU motorcycle) succeeds',
        () async {
      final elm = FakeElm()..mode04Payload = '';
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 1200));

      expect(await obd.clearDtcs(), isTrue);
      expect(elm.wire.contains('04'), isTrue, reason: '04 reached the wire');
      expect(elm.faultMemoryHasCodes, isFalse);
      expect(obd.status, ConnectionStatus.connected);
      expect(obd.dtcCodes, isEmpty);

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('textbook "44" acknowledgement still succeeds', () async {
      final elm = FakeElm()..mode04Payload = '44';
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      expect(await obd.clearDtcs(), isTrue);
      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test(
        'REGRESSION (client report): the ECU acknowledges the erase after its '
        'window — codes cleared and link fine, so no failure is reported',
        () async {
      // The reported bug, reproduced exactly. Before the fix this returned
      // false and the Fault Codes screen showed "Connection Failed" while the
      // codes had in fact been erased and the link was healthy throughout.
      final elm = FakeElm()
        ..mode04Payload = '44'
        ..mode04Latency = const Duration(milliseconds: 4500);
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 800));

      final ok = await obd.clearDtcs();

      expect(ok, isTrue, reason: 'the erase happened and the link is alive');
      expect(elm.wire.contains('04'), isTrue);
      expect(elm.faultMemoryHasCodes, isFalse, reason: 'genuinely cleared');
      expect(elm.wire.where((c) => c == '03').isNotEmpty, isTrue,
          reason: 'the unacknowledged clear was confirmed by observing Mode 03,'
              ' not assumed');
      expect(obd.status, ConnectionStatus.connected,
          reason: 'the connection was never actually lost');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a run of empty-payload replies does not age the link out', () async {
      // Most of ObdPids.allPids is unsupported on this bike, so most poll
      // replies are a bare prompt. Those are delivered replies and must keep
      // proving the link alive, or the dead-link detector fires on a
      // perfectly healthy connection.
      final elm = FakeElm();
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(seconds: 4));

      expect(obd.status, ConnectionStatus.connected);
      expect(obd.linkSynced, isTrue);
      expect(obd.consecutiveTimeouts, 0);
      expect(obd.lastGoodResponseAt, isNotNull);
      expect(
          DateTime.now().difference(obd.lastGoodResponseAt!).inMilliseconds <
              800,
          isTrue,
          reason: 'empty-payload replies refresh the proof-of-life timestamp');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // DIRECTION 2 — a genuine failure must still be reported as one
  // ══════════════════════════════════════════════════════════════════════════
  group('a genuine failure is still detected', () {
    test('Bluetooth switched off before the tap still fails', () async {
      final elm = FakeElm();
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      elm.linkDead = true; // rider walks out of range / turns BT off
      // Let the link go quiet long enough to stop proving itself, the way it
      // would while the user lines up the tap.
      await Future.delayed(const Duration(seconds: 8));

      final ok = await obd.clearDtcs();
      expect(ok, isFalse,
          reason: 'the real "Connection Failed" message must still appear');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('the link dying at the instant of the tap still fails', () async {
      final elm = FakeElm();
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      elm.linkDead = true;
      final ok = await obd.clearDtcs();

      // The clear may land in the brief window where the link has not yet
      // been proven stale — but the follow-up confirmation cannot succeed
      // against an adapter that answers nothing, so the outcome is still a
      // reported failure rather than a false green tick.
      expect(ok, isFalse);

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('the dead-link detector still drops a silent connection', () async {
      final elm = FakeElm();
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      elm.linkDead = true;
      await Future.delayed(const Duration(seconds: 25));

      expect(obd.status, ConnectionStatus.disconnected,
          reason: 'a link that answers nothing is still declared dead');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('an ECU that refuses the erase (7F 04) still fails', () async {
      final elm = FakeElm()..mode04Payload = '7F 04 22';
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      expect(await obd.clearDtcs(), isFalse,
          reason: 'a negative response means the codes were NOT cleared');
      expect(elm.faultMemoryHasCodes, isTrue);

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('an unacknowledged clear that did NOT erase is not rubber-stamped',
        () async {
      // Link alive, request sent, no acknowledgement inside the window — but
      // the ECU's fault memory is still populated. The confirmation step must
      // catch this and report failure rather than assume the best.
      final elm = FakeElm()
        ..eraseActuallyWorks = false
        ..mode04Latency = const Duration(seconds: 30);
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      final ok = await obd.clearDtcs();

      expect(ok, isFalse,
          reason: 'Mode 03 still reports a stored code, so nothing is claimed');
      expect(elm.faultMemoryHasCodes, isTrue);

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 90)));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // The rule is general, not a Clear Codes carve-out
  // ══════════════════════════════════════════════════════════════════════════
  test('Mode 04 is not special-cased in the command set', () {
    // The classifier is reached through the shared transport path, so it
    // applies to every command. These stay the plain OBD-II commands.
    expect(ObdPids.clearDtcs, '04');
    expect(ObdPids.readDtcs, '03');
  });
}
