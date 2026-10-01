/// S9 — tester-mode session recorder.
library;

import 'dart:io';

import 'package:danlite_elm/services/obd_service.dart';
import 'package:danlite_elm/services/session_recorder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_sim.dart';

class _FakeStorage implements RecorderStorage {
  _FakeStorage(this.dir);
  final Directory dir;
  final List<String> shared = <String>[];

  @override
  Future<Directory> directory() async => dir;

  @override
  Future<void> shareText(String text, {required String subject}) async =>
      shared.add(text);
}

/// Fails the test if anything opens an HTTP connection.
class _NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('network access attempted');
  }
}

const _vin = 'MD2A12AZ5LWB12345';

void main() {
  late Directory tmp;
  late _FakeStorage storage;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('danlite_recorder_');
    storage = _FakeStorage(tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ObdService> session(SessionRecorder recorder, EngineSim sim) async {
    final obd = ObdService(sim, recorder: recorder);
    expect(await obd.connectBluetooth(simDevice), isTrue);
    await obd.readEngineDtcs();
    await obd.disconnect();
    return obd;
  }

  test('off by default: a whole session writes nothing', () async {
    final recorder = SessionRecorder(storage: storage);
    expect(recorder.enabled, isFalse);
    final sim = EngineSim(mode03: '43 01 01 33');
    await session(recorder, sim);
    expect(tmp.listSync(), isEmpty);
    expect(recorder.lastRecording, isNull);
    await sim.close();
  });

  test('on: one session writes one file with the whole exchange', () async {
    final recorder = SessionRecorder(storage: storage);
    await recorder.setEnabled(true);
    final sim = EngineSim(mode03: '43 01 01 33', protocol: 'A6');
    await session(recorder, sim);

    final files = tmp.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    final text = files.single.readAsStringSync();
    expect(text, contains('# started: '));
    expect(text, contains('# transport: bluetooth'));
    expect(text, contains('adapter identity (ATZ): ELM327 v1.5'));
    expect(text, contains('protocol (ATDPN): A6'));
    expect(text, contains('TX>ATZ'));
    expect(text, contains('TX>03'));
    expect(text, contains('RX<'));
    expect(text, contains('43 01 01 33'));
    expect(text, contains('engine read: EngineAnswered'));
    expect(text, contains('# ended: '));
    expect(RegExp(r'^\d\d:\d\d:\d\d\.\d{3} TX>', multiLine: true).hasMatch(text),
        isTrue,
        reason: 'every exchange line is timestamped');
    await sim.close();
  });

  test('VINs are masked; adapter hex is not mistaken for one', () async {
    expect(maskVin('VIN $_vin end'), 'VIN [VIN masked] end');
    // 17 hex characters: adapter traffic, kept for fixtures.
    expect(maskVin('7E8100A4304010133'), '7E8100A4304010133');

    final recorder = SessionRecorder(storage: storage);
    await recorder.setEnabled(true);
    recorder.beginSession(transport: 'bluetooth');
    recorder.recordExchange('RX<', 'SOMETHING $_vin');
    recorder.recordExchange('TX>', '0902');
    recorder.recordExchange('RX<', '49 02 01 4D 44 32 41 31 32');
    recorder.recordNote('vehicle $_vin');
    await recorder.endSession();

    final text = recorder.lastRecording!.readAsStringSync();
    expect(text.contains(_vin), isFalse);
    expect(text, contains('[VIN masked]'));
    expect(text, contains('[mode 09 reply masked]'));
    expect(text.contains('4D 44 32'), isFalse);
  });

  test('nothing is sent anywhere: no network, no share without a tap',
      () async {
    final guard = _NoNetwork();
    await HttpOverrides.runZoned(() async {
      final recorder = SessionRecorder(storage: storage);
      await recorder.setEnabled(true);
      final sim = EngineSim(mode03: '43 01 01 33');
      await session(recorder, sim);
      await sim.close();
      expect(storage.shared, isEmpty,
          reason: 'a finished session is never shared automatically');

      // Only an explicit Share hands it on — to the share sheet, not a server.
      expect(await recorder.shareLastRecording(), isTrue);
      expect(storage.shared, hasLength(1));
      expect(storage.shared.single, contains('TX>03'));
    }, createHttpClient: guard.createHttpClient);
    expect(guard.attempts, 0);
  });

  test('the recorder never prints (so it can never reach Sentry)', () async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => printed.add(m ?? '');
    addTearDown(() => debugPrint = original);

    final recorder = SessionRecorder(storage: storage);
    await recorder.setEnabled(true);
    final sim = EngineSim(mode03: '43 01 01 33');
    await session(recorder, sim);
    await sim.close();
    expect(printed.where((l) => l.contains('43 01') || l.contains('TX>')),
        isEmpty);
  });

  test('switching off closes the recording; share with nothing is false',
      () async {
    final recorder = SessionRecorder(storage: storage);
    expect(await recorder.shareLastRecording(), isFalse);
    await recorder.setEnabled(true);
    recorder.beginSession(transport: 'wifi');
    await recorder.setEnabled(false);
    expect(recorder.enabled, isFalse);
    expect(recorder.lastRecording!.readAsStringSync(),
        contains('recorder switched off'));
  });
}
