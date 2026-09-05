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
import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/constants/obd_pids.dart';
import 'package:danlite_elm/models/vehicle_data.dart';
import 'package:danlite_elm/screens/dtc_screen.dart';
import 'package:danlite_elm/services/bluetooth_classic_service.dart';
import 'package:danlite_elm/services/obd_service.dart';

/// Exactly what the rider would read in the snackbar for a finished clear,
/// resolved through the real string table the screen resolves it through.
String riderSees(bool ok, ClearDtcsOutcome outcome) =>
    AppStrings.get(clearOutcomeMessageKey(ok, outcome), 'en');

/// A simulated ELM327 sitting on a simulated single-ECU motorcycle.
class FakeElm extends BluetoothClassicService {
  FakeElm();

  /// Payload the ECU returns for Mode 04. `''` reproduces the bare-prompt
  /// acknowledgement common on single-ECU vehicles; `'44'` is the textbook
  /// car response; `'7F 04 22'` is an ECU actively refusing the erase.
  String mode04Payload = '';

  /// Other modules on the same bus that also answer the Mode 04 broadcast.
  ///
  /// Mode 04 is addressed functionally (0x7DF on ISO 15765-4), so it is not a
  /// question to one ECU — every module on the bus hears it and every module
  /// answers. This motorcycle demonstrably has more than one: the whole of
  /// `ChassisModuleProfiles` exists because the ABS/chassis controller shares
  /// the CAN bus with the engine ECU.
  ///
  /// A module with no emissions fault memory answers `7F 04 11`
  /// (serviceNotSupported). Until this field existed the simulator was a
  /// strictly single-ECU bike and could not produce that reply at all, which
  /// is why a fully passing suite still shipped a clear path that called a
  /// genuinely successful erase a refusal.
  List<String> extraMode04Responders = <String>[];

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

  /// How long the ECU stays unable to service the bus AFTER the Mode 04
  /// request lands — the single most important thing the original simulator
  /// did not model.
  ///
  /// Until this was added, [mode04Latency] delayed the Mode 04 reply but every
  /// other command still answered in about a millisecond, including the Mode
  /// 03 the service sends to confirm an unacknowledged erase. A real ECU does
  /// not behave that way: it stops servicing the bus while it writes flash and
  /// frequently resets afterwards, so the confirmation query is issued at the
  /// exact moment the module is least able to answer it. That divergence is
  /// what let a fully passing test suite ship a clear path that still reported
  /// a false failure on a real motorcycle.
  Duration postEraseRecovery = Duration.zero;

  /// When the erase request landed, used to apply [postEraseRecovery].
  DateTime? _eraseAt;

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
    // Only the engine ECU's own answer decides whether the erase happened.
    // Another module answering "not my service" changes nothing on the wire
    // and must change nothing here either.
    if (c == '04' && eraseActuallyWorks && !_isRefusal(mode04Payload)) {
      faultMemoryHasCodes = false;
    }
    if (c == '04') _eraseAt = DateTime.now();

    // While the ECU is writing flash it is not listening. The request is
    // accepted by the adapter and simply never answered — which is what a
    // confirmation query issued too early actually runs into on a real bike.
    if (c != '04' && _stillRecoveringFromErase) return true;

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

  /// True while the ECU is still writing flash and cannot answer anything.
  bool get _stillRecoveringFromErase {
    final erasedAt = _eraseAt;
    if (erasedAt == null || postEraseRecovery == Duration.zero) return false;
    return DateTime.now().isBefore(erasedAt.add(postEraseRecovery));
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

  /// Is this payload a negative response to service 0x04?
  ///
  /// Byte-aware on purpose: the header-prefixed frame shapes used below carry
  /// `7F 04` in the middle of the line, and a naive substring test would also
  /// fire on unrelated bytes such as `A7 F0 44`.
  static bool _isRefusal(String payload) {
    final tokens = payload
        .toUpperCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    for (var i = 0; i + 1 < tokens.length; i++) {
      if (tokens[i] == '7F' && tokens[i + 1] == '04') return true;
    }
    return tokens.length == 1 && tokens.first.contains('7F04');
  }

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
      final lines = <String>[
        if (mode04Payload.isNotEmpty) mode04Payload,
        ...extraMode04Responders,
      ];
      if (lines.isEmpty) return '\r>';
      return '\r${lines.join('\r')}\r\r>';
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

    test(
        'REGRESSION (real hardware): the ECU is still busy when the '
        'confirmation query goes out — the clear is still not a link failure',
        () async {
      // ── The gap the previous fix left, modelled ──────────────────────────
      // Every earlier test let the confirmation Mode 03 answer in about a
      // millisecond, because only Mode 04 was ever given latency. A real ECU
      // stops servicing the bus while it writes flash, so the confirmation
      // lands on a module that is not listening yet.
      //
      // Two things then go wrong at once with the un-widened logic:
      //   * the confirmation's own timeout is spent while the module is still
      //     recovering, so it never gets a second chance; and
      //   * Mode 04 (4s) plus Mode 03 (3s) is seven seconds of wall clock,
      //     which is longer than the six-second proof-of-life window — so the
      //     link is declared FAILED purely because a two-command sequence
      //     outlasted a window sized for one command.
      //
      // The codes really were erased. Reporting "Connection Failed" here is
      // the exact symptom the client is seeing.
      final elm = FakeElm()
        ..mode04Payload = '44'
        ..mode04Latency = const Duration(seconds: 30) // never acks in window
        ..postEraseRecovery = const Duration(milliseconds: 7500);
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 800));

      final ok = await obd.clearDtcs();

      expect(elm.faultMemoryHasCodes, isFalse,
          reason: 'the erase genuinely happened — the ECU was simply busy');
      expect(ok, isTrue,
          reason: 'a busy ECU after a flash write is not a dead connection');
      expect(obd.lastClearOutcome, ClearDtcsOutcome.cleared);
      expect(obd.status, ConnectionStatus.connected,
          reason: 'the link was never actually lost');
      expect(obd.linkSynced, isTrue,
          reason: 'the write gate must not be slammed shut by a slow erase');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 90)));

    test(
        'REGRESSION (client report): a second module on the bus answers '
        '"7F 04 11" while the engine ECU acknowledges — the codes really were '
        'cleared, so this is a success, not a refusal',
        () async {
      // ── The gap this suite could not previously express ──────────────────
      // Every test above models a bike with exactly ONE module answering.
      // Mode 04 is not addressed to one module: it goes to the functional
      // address, so every controller on the bus answers it. This platform has
      // more than one — ChassisModuleProfiles exists solely because the ABS
      // controller shares the bus with the engine ECU.
      //
      // The ABS module holds no emissions fault memory, so it answers the
      // broadcast "7F 04 11" — serviceNotSupported. That is not a refusal of
      // the erase; it is a module saying Mode 04 is not its service. The
      // engine ECU on the same reply answers 44 and genuinely wipes its codes.
      //
      // The old scan returned false on the first line containing 7F 04, so
      // this exact reply reported ClearDtcsOutcome.refused and told the rider
      // to stop the engine and try again — while their codes were already
      // gone. That is the client's report, reproduced.
      final elm = FakeElm()
        ..mode04Payload = '44'
        ..extraMode04Responders = <String>['7F 04 11'];
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      final ok = await obd.clearDtcs();

      expect(elm.faultMemoryHasCodes, isFalse,
          reason: 'the engine ECU genuinely erased its fault memory');
      expect(ok, isTrue,
          reason: 'one module answering "not my service" does not undo an '
              'erase another module positively acknowledged');
      expect(obd.lastClearOutcome, ClearDtcsOutcome.cleared);
      expect(obd.status, ConnectionStatus.connected);

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test(
        'the same multi-module reply in header form (ATH1/ATS0) is also a '
        'success', () async {
      // The live baseline is ATS0, so a frame arrives as one unbroken hex run,
      // and with headers on it is prefixed by an 11-bit CAN header the ELM327
      // prints as THREE nibbles. Reading that in pairs from index 0 puts every
      // byte after the header one nibble out of alignment.
      final elm = FakeElm()
        ..mode04Payload = '7E8034400000000'
        ..extraMode04Responders = <String>['7E9037F0411000000'];
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      expect(await obd.clearDtcs(), isTrue);
      expect(obd.lastClearOutcome, ClearDtcsOutcome.cleared);
      expect(elm.faultMemoryHasCodes, isFalse);

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('bytes that merely spell "7F04" across a boundary are not a refusal',
        () async {
      // "A7 F0 44" contains the characters 7F04 but no such byte pair. The
      // guard is asserted here rather than left to a code comment.
      final elm = FakeElm()..mode04Payload = 'A7 F0 44';
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      expect(await obd.clearDtcs(), isTrue);
      expect(obd.lastClearOutcome, ClearDtcsOutcome.cleared);

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

    test('an erase every responding module refuses still fails', () async {
      // The counterpart to the multi-module success above, and the reason that
      // fix cannot be "ignore 7F 04 when there is more than one line". Here
      // NO module acknowledged: the engine ECU refused and the second module
      // does not implement the service. Nothing was cleared and the rider must
      // still be told so.
      final elm = FakeElm()
        ..mode04Payload = '7F 04 22'
        ..extraMode04Responders = <String>['7F 04 11'];
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      expect(await obd.clearDtcs(), isFalse);
      expect(obd.lastClearOutcome, ClearDtcsOutcome.refused);
      expect(elm.faultMemoryHasCodes, isTrue);

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a refusal carried in a header-prefixed frame is now detected',
        () async {
      // Direction check on the alignment fix. With ATH1/ATS0 the refusal
      // arrives as "7E8 03 7F 04 22 …" run together, and the old pair-scan
      // starting at index 0 stepped straight past it — a genuine refusal was
      // reported to the rider as a successful clear. Byte-aligned parsing
      // catches it.
      final elm = FakeElm()..mode04Payload = '7E8037F0422000000';
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      expect(await obd.clearDtcs(), isFalse,
          reason: 'the ECU refused; a header prefix does not make it a success');
      expect(obd.lastClearOutcome, ClearDtcsOutcome.refused);
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
  // WHY it failed, not just THAT it failed
  //
  // Every unsuccessful clear used to reach the rider as "Connection Failed".
  // Three of these four outcomes have nothing to do with the connection, and
  // telling a rider their link is broken when it is not sends them to re-pair a
  // working adapter instead of addressing the real cause.
  // ══════════════════════════════════════════════════════════════════════════
  group('the reason a clear failed is reported accurately', () {
    test('a genuinely dead link is still reported as a link failure', () async {
      final elm = FakeElm();
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      elm.linkDead = true;
      await Future.delayed(const Duration(seconds: 8));

      final ok = await obd.clearDtcs();
      expect(ok, isFalse);
      expect(obd.lastClearOutcome, ClearDtcsOutcome.linkFailure,
          reason: 'the real "Connection Failed" message must still be the one '
              'a rider sees when the adapter is genuinely gone');
      expect(riderSees(ok, obd.lastClearOutcome), 'Connection Failed');
      expect(elm.wire.where((c) => c == '04'), isEmpty,
          reason: 'a link already known to be stale is reported immediately, '
              'rather than after another four seconds of waiting');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('an ECU refusing the erase is not called a connection failure',
        () async {
      final elm = FakeElm()..mode04Payload = '7F 04 22';
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      final ok = await obd.clearDtcs();
      expect(ok, isFalse);
      expect(obd.lastClearOutcome, ClearDtcsOutcome.refused,
          reason: 'the ECU answered — the link is fine, the erase was refused');
      expect(obd.status, ConnectionStatus.connected);
      // Internally still a refusal; the rider sees the one failure message.
      expect(riderSees(ok, obd.lastClearOutcome), 'Connection Failed');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('an erase that demonstrably did not take is reported as such',
        () async {
      final elm = FakeElm()
        ..eraseActuallyWorks = false
        ..mode04Latency = const Duration(seconds: 30);
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      final ok = await obd.clearDtcs();
      expect(ok, isFalse);
      expect(obd.lastClearOutcome, ClearDtcsOutcome.notCleared,
          reason: 'Mode 03 answered and still reports a stored code');
      expect(riderSees(ok, obd.lastClearOutcome), 'Connection Failed');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('an ECU that never comes back leaves the clear unconfirmed, not failed',
        () async {
      // The module accepts the erase and then stays away past every attempt.
      // Nothing is known, and "nothing is known" is not "the link is broken".
      final elm = FakeElm()
        ..mode04Latency = const Duration(seconds: 30)
        ..postEraseRecovery = const Duration(seconds: 30);
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      final ok = await obd.clearDtcs();
      expect(ok, isFalse,
          reason: 'an unconfirmed clear is never reported as a success');
      expect(obd.lastClearOutcome, ClearDtcsOutcome.unconfirmed,
          reason: 'the link was alive throughout — this is unknown, not failed');
      expect(riderSees(ok, obd.lastClearOutcome), 'Connection Failed');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('a successful clear reports the cleared outcome', () async {
      final elm = FakeElm()..mode04Payload = '44';
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      final ok = await obd.clearDtcs();
      expect(ok, isTrue);
      expect(obd.lastClearOutcome, ClearDtcsOutcome.cleared);
      expect(riderSees(ok, obd.lastClearOutcome), 'Codes cleared successfully ✓');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('the confirmation retries before giving up', () async {
      // One attempt is not enough for a module that is still booting. Two are.
      final elm = FakeElm()
        ..mode04Latency = const Duration(seconds: 30)
        ..postEraseRecovery = const Duration(milliseconds: 7500);
      final obd = await connectedService(elm);
      await Future.delayed(const Duration(milliseconds: 600));

      expect(await obd.clearDtcs(), isTrue);
      expect(elm.wire.where((c) => c == '03').length, greaterThanOrEqualTo(2),
          reason: 'the first confirmation landed on a busy ECU; the clear is '
              'resolved by asking again, not by reporting a dead connection');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 120)));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Five internal outcomes, exactly two rider-facing messages
  //
  // The classification above stays as detailed as it is — Sentry and any future
  // diagnostic tooling still get the real reason. What the rider is shown is
  // deliberately the original v1.0–v1.4 pair: cleared, or "Connection Failed".
  // ══════════════════════════════════════════════════════════════════════════
  group('Clear Codes shows the rider exactly two outcomes', () {
    test('a confirmed erase is the only thing that reads as success', () {
      expect(riderSees(true, ClearDtcsOutcome.cleared),
          'Codes cleared successfully ✓');
    });

    for (final outcome in const [
      ClearDtcsOutcome.linkFailure,
      ClearDtcsOutcome.refused,
      ClearDtcsOutcome.unconfirmed,
      ClearDtcsOutcome.notCleared,
    ]) {
      test('${outcome.name} reaches the rider as "Connection Failed"', () {
        expect(riderSees(false, outcome), 'Connection Failed');
      });
    }

    test('no ClearDtcsOutcome can produce a third message', () {
      final shown = <String>{
        for (final o in ClearDtcsOutcome.values) riderSees(false, o),
        for (final o in ClearDtcsOutcome.values) riderSees(true, o),
      };
      expect(shown, {'Codes cleared successfully ✓', 'Connection Failed'});
    });

    test('the collapse holds in every shipped language', () {
      for (final code in const [
        'en', 'hi', 'bn', 'te', 'mr', 'ta', 'gu', 'kn', 'ml', 'pa', 'ne',
      ]) {
        final failures = <String>{
          for (final o in const [
            ClearDtcsOutcome.linkFailure,
            ClearDtcsOutcome.refused,
            ClearDtcsOutcome.unconfirmed,
            ClearDtcsOutcome.notCleared,
          ])
            AppStrings.get(clearOutcomeMessageKey(false, o), code),
        };
        expect(failures, hasLength(1),
            reason: '$code must show one failure message, not four');
      }
    });
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
