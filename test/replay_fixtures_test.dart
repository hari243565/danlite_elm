/// Phase 1A — A7: every replay fixture, through the REAL ObdService.
///
/// Each file in test/fixtures/replay is a transcript in the session
/// recorder's format with `# expect` lines (see the README there). This test
/// plays each one and checks every expectation; a fixture without any fails.
library;

import 'dart:io';

import 'package:danlite_elm/services/engine_context.dart';
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

/// Requests only the on-demand context read sends (not 0101, which the
/// automatic extras also send).
const contextCommands = <String>[
  '020200', '020000', '024000', '0121', '0131', '014D', '014E', '0130',
];

/// `# expect snapshot: answered P0301` | `noSnapshot` | `unsupported` |
/// `noAnswer` | `refused 22` | `gated`; `snapshotValues: 04=50.2 0C=1000`
/// (hex PID = value); `snapshotUnread: 05`; `counters: lampKm=120
/// clearedKm=unsupported warmUps=noAnswer clearedKm=atLeast`; `readiness:
/// misfire=complete evaporative=notComplete heatedCatalyst=notSupported`.
void checkContext(Transcript t, ObdService obd) {
  final e = t.expect;

  final snap = e['snapshot'];
  if (snap != null) {
    final w = words(snap);
    final r = obd.freezeFrameResult;
    switch (w.first) {
      case 'answered':
        expect(r, isA<FreezeFrameAnswered>(), reason: '${t.name}: snapshot is $r');
        expect((r as FreezeFrameAnswered).snapshot.triggerCode, w[1], reason: t.name);
      case 'noSnapshot':
        expect(r, isA<FreezeFrameNoSnapshot>(), reason: t.name);
      case 'unsupported':
        expect(r, isA<FreezeFrameUnsupported>(), reason: t.name);
      case 'noAnswer':
        expect(r, isA<FreezeFrameNoAnswer>(), reason: t.name);
      case 'refused':
        expect(r, isA<FreezeFrameRefused>(), reason: t.name);
        expect((r as FreezeFrameRefused).nrc, int.parse(w[1], radix: 16), reason: t.name);
      case 'gated':
        expect(r, isA<FreezeFrameGated>(), reason: t.name);
      default:
        fail('${t.name}: unknown snapshot expectation "$snap"');
    }
  }
  final values = e['snapshotValues'];
  if (values != null) {
    final r = obd.freezeFrameResult as FreezeFrameAnswered;
    final got = <String, double>{
      for (final v in r.snapshot.values)
        if (v is SnapshotNumber)
          v.pid.pid.toRadixString(16).toUpperCase().padLeft(2, '0'): v.value,
    };
    final want = {
      for (final p in words(values)) p.split('=')[0].toUpperCase(): double.parse(p.split('=')[1]),
    };
    expect(got.keys.toSet(), want.keys.toSet(), reason: '${t.name}: which values');
    want.forEach((k, v) => expect(got[k], closeTo(v, 0.06), reason: '${t.name}: PID $k'));
  }
  final unread = e['snapshotUnread'];
  if (unread != null) {
    final r = obd.freezeFrameResult as FreezeFrameAnswered;
    expect(
        r.snapshot.unreadPids
            .map((p) => p.toRadixString(16).toUpperCase().padLeft(2, '0'))
            .toList(),
        unread == 'none' ? isEmpty : words(unread).map((x) => x.toUpperCase()).toList(),
        reason: t.name);
  }

  final counters = e['counters'];
  if (counters != null) {
    final c = obd.contextCounters;
    expect(c, isNotNull, reason: '${t.name}: counters were read');
    const byName = <String, ContextCounter>{
      'lampKm': ContextCounter.lampDistance,
      'clearedKm': ContextCounter.clearedDistance,
      'lampMin': ContextCounter.lampTime,
      'clearedMin': ContextCounter.clearedTime,
      'warmUps': ContextCounter.warmUps,
    };
    for (final p in words(counters)) {
      final kv = p.split('=');
      final r = c!.of(byName[kv[0]]!);
      switch (kv[1]) {
        case 'unsupported':
          expect(r, isA<ExtraUnsupported<CounterValue>>(), reason: '${t.name}: ${kv[0]}');
        case 'noAnswer':
          expect(r, isA<ExtraNoAnswer<CounterValue>>(), reason: '${t.name}: ${kv[0]}');
        case 'atLeast':
          expect((r as ExtraValue<CounterValue>).value.atLeast, isTrue, reason: kv[0]);
        default:
          expect(r, isA<ExtraValue<CounterValue>>(), reason: '${t.name}: ${kv[0]} is $r');
          expect((r as ExtraValue<CounterValue>).value.value, int.parse(kv[1]),
              reason: '${t.name}: ${kv[0]}');
      }
    }
  }

  final readiness = e['readiness'];
  if (readiness != null) {
    final r = obd.readinessRead?.result;
    if (readiness == 'unsupported') {
      expect(r, isA<ExtraUnsupported<ReadinessReport>>(), reason: t.name);
    } else if (readiness == 'noAnswer') {
      expect(r, isA<ExtraNoAnswer<ReadinessReport>>(), reason: t.name);
    } else {
      expect(r, isA<ExtraValue<ReadinessReport>>(), reason: '${t.name}: readiness is $r');
      final report = (r as ExtraValue<ReadinessReport>).value;
      for (final p in words(readiness)) {
        final kv = p.split('=');
        final m = Monitor.values.firstWhere((x) => x.name == kv[0]);
        expect(report.states[m]!.name, kv[1], reason: '${t.name}: ${kv[0]}');
      }
    }
  }
}

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
  // ── context reads (Phase A-4): only when the fixture expects something ──
  if (e.keys.any(const {'snapshot', 'snapshotValues', 'snapshotUnread', 'counters', 'readiness'}.contains)) {
    await obd.readEngineContext();
    checkContext(t, obd);
  }
  if (e['contextWire'] == 'none') {
    expect(transport.wire.where(contextCommands.contains), isEmpty,
        reason: '${t.name}: no context request on a plain scan');
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
          // Phase A-4
          'context_full_snapshot.txt',
          'context_can29.txt',
          'context_no_snapshot.txt',
          'context_mode02_unsupported.txt',
          'context_partial_support.txt',
          'context_pending_passes.txt',
          'context_silent.txt',
          'context_refused.txt',
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
