/// S8, first line of defence: a simulated session prints no adapter traffic.
///
/// The Sentry SDK turns `debugPrint` output into breadcrumbs in release
/// builds, so anything printed can ride along on an error event. Before this
/// release every adapter command and reply was printed as a `[WIRE]` line.
///
/// Uses only APIs that existed before the release, so it can be run against
/// the old code to show the leak.
library;

import 'dart:async';

import 'package:danlite_elm/services/bluetooth_classic_service.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sim extends BluetoothClassicService {
  final _ctrl = StreamController<String>.broadcast();
  bool _up = false;
  @override
  Stream<String> get dataStream => _ctrl.stream;
  @override
  bool get isConnected => _up;
  @override
  Future<bool> connect(BtDevice device) async => _up = true;
  @override
  Future<void> disconnect() async => _up = false;
  @override
  Future<bool> write(String cmd) async {
    final c = cmd.trim().toUpperCase();
    final String reply;
    if (c == 'ATZ') {
      reply = '\rELM327 v1.5\r\r>';
    } else if (c == 'ATDPN') {
      reply = '\rA6\r\r>';
    } else if (c.startsWith('AT')) {
      reply = '\rOK\r\r>';
    } else if (c == '0100') {
      reply = '\r41 00 BE 3E B8 11\r\r>';
    } else if (c == '03') {
      reply = '\r43 01 01 33\r\r>';
    } else if (c == '010C') {
      reply = '\r41 0C 0B B8\r\r>';
    } else {
      reply = '\rNO DATA\r\r>';
    }
    scheduleMicrotask(() => _ctrl.add(reply));
    return true;
  }
}

/// Text that only adapter traffic or fault data would produce.
final _traffic = RegExp(
    r'\[WIRE\]|TX>|RX<|ELM327|41 0C|43 01|4300|NO DATA|ATDPN|ATZ|P0133');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a session that reads codes prints no adapter traffic', () async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        printed.add(message ?? '');
    addTearDown(() => debugPrint = original);

    final sim = _Sim();
    final obd = ObdService(sim);
    expect(
        await obd.connectBluetooth(const BtDevice(
            name: 'OBDII', address: '00:11:22:33:44:55', bonded: true)),
        isTrue);
    await obd.readDtcs();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await obd.disconnect();

    // The in-memory ring survives disconnect: proof the session really did
    // exchange traffic, so an empty print log is meaningful.
    expect(obd.wireLog.any((l) => l.contains('43 01 01 33')), isTrue);
    final leaked = printed.where(_traffic.hasMatch).toList();
    expect(leaked, isEmpty, reason: 'printed lines can become Sentry breadcrumbs');
  });
}
