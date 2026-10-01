/// Phase 1A — A7: every replay fixture, through the REAL ObdService.
///
/// Each file in test/fixtures/replay is a transcript in the session
/// recorder's format with `# expect` lines (see the README there). This test
/// plays each one and checks every expectation; a fixture without any fails.
library;

import 'dart:io';

import 'package:danlite_elm/services/fault_decoders.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_sim.dart' show simDevice;
import 'support/replay_transport.dart';

final fixtureDir = Directory('test/fixtures/replay');

List<File> fixtures() => fixtureDir
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.txt'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

List<String> words(String s) =>
    s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// Commands the optional extras send; a fixture expecting `extras: none`
/// must see none of them.
const extrasCommands = <String>['0101', '07', '0A', '0902', '0904'];

Future<void> runFixture(Transcript t) async {
  final scale = double.parse(t.directives['timing'] ?? '1.0');
  final transport = ReplayTransport(t, timeScale: scale);
  final obd = ObdService(transport, faultTiming: FaultReadTiming.scaled(scale));
  expect(await obd.connectBluetooth(simDevice), isTrue,
      reason: '${t.name}: the adapter must complete init');

  final read = await obd.readEngineDtcs(forceExtras: true);
  await obd.whenEngineReadSettled();
  final e = t.expect;
  final report = obd.engineReport;

  // ── engine ──
  final engine = e['engine'];
  if (engine != null) {
    final w = words(engine);
    switch (w.first) {
      case 'answered':
        expect(read, isA<EngineAnswered>(), reason: t.name);
        expect((read as EngineAnswered).codes.map((c) => c.code), w.sublist(1),
            reason: t.name);
        break;
      case 'noAnswer':
        expect(read, isA<EngineNoAnswer>(), reason: t.name);
        expect((read as EngineNoAnswer).reason.name, w[1], reason: t.name);
        expect(obd.dtcCodes, isEmpty, reason: t.name);
        break;
      case 'refused':
        expect(read, isA<EngineRefused>(), reason: t.name);
        expect((read as EngineRefused).nrc, int.parse(w[1], radix: 16),
            reason: t.name);
        break;
      case 'klineGated':
        expect(read, isA<EngineKLineGated>(), reason: t.name);
        expect(obd.dtcCodes, isEmpty, reason: '${t.name}: nothing parsed');
        break;
      default:
        fail('${t.name}: unknown engine expectation "$engine"');
    }
  }
  if (e.containsKey('vehicleAnswered')) {
    expect(obd.vehicleAnswered, e['vehicleAnswered'] == 'true', reason: t.name);
  }
  if (e.containsKey('display')) {
    expect(obd.engineDisplayCodes.map((c) => c.code), words(e['display']!),
        reason: t.name);
  }
  if (e.containsKey('module')) {
    expect(obd.dtcCodes.first.record?.module, e['module'], reason: t.name);
  }

  // ── extras ──
  void codesExpect(String key, ExtraRead<Object?>? r) {
    final v = e[key];
    if (v == null) return;
    expect(r, isNotNull, reason: '${t.name}: $key');
    if (v == 'unsupported') {
      expect(r, isA<ExtraUnsupported<Object?>>(), reason: '${t.name}: $key');
    } else {
      expect(r, isA<ExtraValue<Object?>>(), reason: '${t.name}: $key');
      final codes = ((r as ExtraValue).value as List).map((x) => x.code).toList();
      expect(codes, v == 'none' ? isEmpty : words(v), reason: '${t.name}: $key');
    }
  }

  codesExpect('pending', report?.pending);
  codesExpect('permanent', report?.permanent);
  if (e.containsKey('lamp')) {
    expect(report?.lampOn, e['lamp'] == 'on', reason: t.name);
  }
  if (e.containsKey('engineState')) {
    expect(report?.engineState.name, e['engineState'], reason: t.name);
  }
  if (e.containsKey('voltage')) {
    final w = words(e['voltage']!);
    if (w.first == 'unknown') {
      expect(report?.voltage.valueOrNull, isNull, reason: t.name);
    } else {
      expect(report?.voltageLevel?.name, w.first, reason: t.name);
      if (w.length > 1) {
        expect(report!.voltage.valueOrNull!.volts, closeTo(double.parse(w[1]), 0.001),
            reason: t.name);
      }
    }
  }
  if (e.containsKey('mayBeFalse')) {
    expect(obd.batteryVoltageLow, isTrue, reason: t.name);
    final flagged = obd.engineDisplayCodes
        .where((c) => c.code.startsWith('U'))
        .map((c) => c.code)
        .toList();
    expect(flagged, words(e['mayBeFalse']!), reason: t.name);
  }
  if (e.containsKey('vin')) {
    final v = report?.vin;
    switch (e['vin']) {
      case 'valid':
        expect(v, isA<ExtraValue<Vin>>(), reason: t.name);
        expect(Vin.isValid(obd.session!.vin!.value), isTrue);
        expect(obd.wireLog.join('\n'), isNot(contains('4D 41 33')),
            reason: '${t.name}: the VIN reply is masked in the wire log');
        break;
      case 'unsupported':
        expect(v, isA<ExtraUnsupported<Vin>>(), reason: t.name);
        break;
      default:
        expect(v, isNot(isA<ExtraValue<Vin>>()), reason: t.name);
    }
  }
  if (e['extras'] == 'none') {
    expect(report, isNull, reason: t.name);
    expect(transport.wire.where(extrasCommands.contains), isEmpty,
        reason: '${t.name}: no extras on a bike that did not answer');
  }

  // ── ABS ──
  final abs = e['abs'];
  if (abs != null) {
    final vehicle = (t.directives['vehicle'] ?? '').split('/');
    final codes = await obd.readChassisDtcs(
      vehicleMake: vehicle.isNotEmpty ? vehicle.first.trim() : null,
      vehicleModel: vehicle.length > 1 ? vehicle[1].trim() : null,
    );
    if (abs == 'clean' || abs == 'none') {
      expect(codes, isEmpty, reason: t.name);
    } else {
      expect(codes.map((c) => c.record!.displayCode), words(abs), reason: t.name);
      if (e.containsKey('absStatus')) {
        expect(codes.first.statusByte, int.parse(e['absStatus']!, radix: 16),
            reason: t.name);
      }
    }
  }
  if (e.containsKey('passesPending')) {
    expect(obd.session!.adapterPassesPending, e['passesPending'] == 'true',
        reason: t.name);
  }

  await obd.disconnect();
  await transport.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('A7 the fixture set covers everything the brief names', () {
    final names = fixtures().map((f) => f.uri.pathSegments.last).toSet();
    expect(
        names,
        containsAll(<String>[
          'silent_bike.txt',
          'positive_empty.txt',
          'codes_present.txt',
          'pending_then_answer.txt',
          'mixed_2byte_3byte.txt',
          'multiframe_vin.txt',
          'low_voltage.txt',
          'engine_running_refusal.txt',
          'can29_header.txt',
          'kline_samples.txt',
          'adapter_handles_pending.txt',
          'adapter_passes_pending.txt',
          'zero_padded.txt',
        ]));
  });

  test('A7 the transcript parser reads the recorder\'s own output', () {
    const text = '# Danlite ELM session recording\n'
        '09:30:00.000 TX>03\n'
        r'09:30:00.040 RX<\r7E8 04 43 01 01 33\r\r' '\n'
        '# 09:30:00.050 engine read: EngineAnswered\n'
        '09:30:01.000 TX>07\n'
        '09:30:02.000 TX>0A\n'
        r'09:30:03.500 RX<\rNO DATA\r\r' '\n';
    final t = Transcript.parse('inline', text);
    expect(t.entries.map((e) => e.command), ['03', '07', '0A']);
    expect(t.entries[0].reply, '\r7E8 04 43 01 01 33\r\r');
    expect(t.entries[0].delay, const Duration(milliseconds: 40));
    expect(t.entries[1].reply, isNull, reason: 'no RX = silence');
    expect(t.entries[2].delay, const Duration(milliseconds: 1500));
  });

  test('A7 the K-line samples still decode correctly when the gate is lifted '
      '(legacy framing), proving the fixture bytes are right', () {
    final t = Transcript.load(File('${fixtureDir.path}/kline_samples.txt'));
    final replies = t.entries.where((e) => e.command == '03').map((e) => e.reply!);
    final decoded = [
      for (final r in replies)
        (decodeObdDtcReply(r, service: 0x03, framing: DtcFraming.legacy) as ObdDtcCodes)
            .codes
            .map((c) => c.code)
            .toList(),
    ];
    expect(decoded, [
      ['P0133'],
      ['P0133', 'P0301', 'P0113', 'P0234'],
    ]);
  });

  for (final f in fixtures()) {
    final t = Transcript.load(f);
    test('A7 replay ${t.name}', () async {
      expect(t.expect, isNotEmpty,
          reason: '${t.name} has no "# expect" lines — every fixture must be checked');
      await runFixture(t);
    }, timeout: const Timeout(Duration(seconds: 90)));
  }
}
