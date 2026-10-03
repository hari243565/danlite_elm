/// Fault-code safety release — S1 (honest reach result), S2 (stale results
/// never look live), S3 (U/C/B codes kept), S4 (K-line gate).
///
/// The REAL ObdService runs over a simulated adapter (test/support/
/// engine_sim.dart), and the REAL DtcScreen is rendered against the state
/// those reads leave behind. Reply shapes are hand-written from documented
/// ELM327 behaviour, not recorded from a real bike.
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/constants/obd_pids.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/dtc_screen.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/engine_sim.dart';

String en(String key) => AppStrings.get(key, 'en');

Widget screenFor(ObdService obd) => MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>(
            create: (_) => SettingsProvider()),
        ChangeNotifierProvider<VehicleProvider>(
            create: (_) => VehicleProvider()),
        ChangeNotifierProvider<ObdService>.value(value: obd),
      ],
      child: const MaterialApp(home: DtcScreen(autoScan: false)),
    );

/// Render the real screen and return every Text string on it.
Future<List<String>> renderedTexts(WidgetTester tester, ObdService obd) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(screenFor(obd));
  await tester.pump(const Duration(milliseconds: 50));
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .toList();
}

/// One S1 scenario: what the simulated bike says, and what must happen.
class Scenario {
  const Scenario(this.name, this.sim, this.expectKind,
      {this.vehicleAnswers = true, this.reason});
  final String name;
  final EngineSim Function() sim;
  final Type expectKind;
  final bool vehicleAnswers;
  final EngineNoAnswerReason? reason;
}

final scenarios = <Scenario>[
  Scenario(
    'silent bike: no reply to anything',
    () => EngineSim(
        supportedPids: '', mode03: null, protocol: 'A0', vehicleSilent: true),
    EngineNoAnswer,
    vehicleAnswers: false,
    reason: EngineNoAnswerReason.timeout,
  ),
  Scenario(
    'NO DATA to the fault-code request',
    () => EngineSim(mode03: 'NO DATA'),
    EngineNoAnswer,
    reason: EngineNoAnswerReason.noData,
  ),
  Scenario(
    'UNABLE TO CONNECT',
    () => EngineSim(
        supportedPids: 'SEARCHING...\rUNABLE TO CONNECT',
        mode03: 'SEARCHING...\rUNABLE TO CONNECT',
        protocol: 'A0',
        vehicleSilent: true),
    EngineNoAnswer,
    vehicleAnswers: false,
    reason: EngineNoAnswerReason.unableToConnect,
  ),
  Scenario(
    'adapter up but ignition off (bus init fails)',
    () => EngineSim(
        supportedPids: 'SEARCHING...\rUNABLE TO CONNECT',
        mode03: 'BUS INIT: ...ERROR',
        protocol: 'A0',
        vehicleSilent: true),
    EngineNoAnswer,
    vehicleAnswers: false,
    reason: EngineNoAnswerReason.busInit,
  ),
  Scenario(
    'refused request (7F 03 22)',
    () => EngineSim(mode03: '7F 03 22'),
    EngineRefused,
  ),
  Scenario(
    'positive empty answer (43 00)',
    () => EngineSim(mode03: '43 00'),
    EngineAnswered,
  ),
  Scenario(
    'positive answer with codes',
    () => EngineSim(mode03: '43 02 01 33 03 01'),
    EngineAnswered,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════════
  // S1 — the read result cannot be mistaken for "empty"
  // ══════════════════════════════════════════════════════════════════════════
  group('S1 service: each scenario yields the honest result', () {
    for (final s in scenarios) {
      test(s.name, () async {
        final sim = s.sim();
        final obd = await connectSim(sim);
        final result = await obd.readEngineDtcs();

        expect(result.runtimeType, s.expectKind);
        expect(obd.lastEngineRead, same(result));
        expect(obd.vehicleAnswered, s.vehicleAnswers,
            reason: 'only a positive vehicle reply marks the bike answering');
        if (s.reason != null) {
          expect((result as EngineNoAnswer).reason, s.reason);
        }
        if (result is! EngineAnswered) {
          expect(obd.dtcCodes, isEmpty,
              reason: 'nothing that is not an answer may produce a list');
          expect(await obd.readDtcs(), isEmpty);
        }
        if (!s.vehicleAnswers) {
          expect(obd.statusMessage, contains('bike not answering'),
              reason: 'the status line must not claim the bike connected');
        }
        expect(obd.session!.protocol.raw, isNotNull,
            reason: 'ATDPN is read and kept on the session');

        await obd.disconnect();
        await sim.close();
      }, timeout: const Timeout(Duration(seconds: 60)));
    }

    test('positive answer with codes decodes them', () async {
      final sim = EngineSim(mode03: '43 02 01 33 03 01');
      final obd = await connectSim(sim);
      final r = await obd.readEngineDtcs() as EngineAnswered;
      expect(r.codes.map((c) => c.code), ['P0133', 'P0301']);
      expect(obd.session!.protocol.family, ObdProtocolFamily.can);
      expect(obd.session!.adapterIdentity, 'ELM327 v1.5');
      await obd.disconnect();
      await sim.close();
    });
  });

  group('S1 screen: "No Fault Codes Found" only after a positive answer', () {
    for (final s in scenarios) {
      testWidgets(s.name, (tester) async {
        late ObdService obd;
        late EngineSim sim;
        await tester.runAsync(() async {
          sim = s.sim();
          obd = await connectSim(sim);
          await obd.readEngineDtcs();
        });

        final texts = await renderedTexts(tester, obd);
        final noFaults = texts.contains(en('noFaultCodes'));
        final noAnswer = texts.contains(en('dtcNoAnswerTitle'));
        final refused = texts.contains(en('dtcRefusedTitle'));

        if (s.expectKind == EngineAnswered) {
          expect(noAnswer || refused, isFalse);
          if (s.name.contains('empty')) {
            expect(noFaults, isTrue,
                reason: 'a valid zero-code answer IS an all-clear');
          } else {
            expect(noFaults, isFalse);
            expect(texts, containsAll(<String>['P0133', 'P0301']));
          }
        } else {
          expect(noFaults, isFalse,
              reason: 'never an all-clear without a positive answer');
          expect(texts.contains(en('noFaultCodesDesc')), isFalse);
          if (s.expectKind == EngineNoAnswer) {
            expect(noAnswer, isTrue);
            expect(texts, contains(en('dtcNoAnswerBody')));
            expect(texts, contains(en('dtcNoAnswerChecklist')));
          } else {
            expect(refused, isTrue);
          }
        }

        await tester.runAsync(() async {
          await obd.disconnect();
          await sim.close();
        });
      });
    }
  });

  group('S1 classifier: adapter replies that are never an answer', () {
    EngineReplyVerdict judge(String r) =>
        classifyEngineDtcReply(r, linkFailed: false);

    test('NO DATA, bare prompt, ?, errors, SEARCHING are all no-answer', () {
      final cases = <String, EngineNoAnswerReason>{
        'NO DATA': EngineNoAnswerReason.noData,
        '': EngineNoAnswerReason.emptyReply,
        'TIMEOUT': EngineNoAnswerReason.timeout,
        '?': EngineNoAnswerReason.adapterRejected,
        'UNABLE TO CONNECT': EngineNoAnswerReason.unableToConnect,
        'BUS INIT: ...ERROR': EngineNoAnswerReason.busInit,
        'CAN ERROR': EngineNoAnswerReason.busError,
        'BUFFER FULL': EngineNoAnswerReason.adapterError,
        'STOPPED': EngineNoAnswerReason.adapterError,
        'SEARCHING...': EngineNoAnswerReason.searching,
        '41 00 BE 3E B8 11': EngineNoAnswerReason.unrecognised,
      };
      cases.forEach((reply, reason) {
        final v = judge(reply);
        expect(v, isA<ReplyNoAnswer>(), reason: reply);
        expect((v as ReplyNoAnswer).reason, reason, reason: reply);
      });
    });

    test('positive replies, headers on or off, are answers', () {
      for (final r in <String>[
        '43 00',
        '4300',
        '7E8 02 43 00',
        'SEARCHING...\r43 01 01 33',
        '7E8 04 43 01 01 33',
      ]) {
        expect(judge(r), isA<ReplyPositive>(), reason: r);
      }
    });

    test('29-bit CAN headers, as printed with spaces on, are answers', () {
      // The engine read turns spaces and headers on, so a 29-bit ECU's reply
      // header arrives as four separate bytes.
      final empty = judge('18 DA F1 10 02 43 00');
      expect(empty, isA<ReplyPositive>());
      expect((empty as ReplyPositive).parsed.allCodes, isEmpty);
      final one = judge('18 DA F1 10 04 43 01 01 33');
      expect(one, isA<ReplyPositive>());
      expect((one as ReplyPositive).parsed.allCodes, ['P0133']);
      expect(judge('18 DA F1 10 03 7F 03 22'), isA<ReplyRefused>());
    });

    test('negative responses are refusals, not empty answers', () {
      final v = judge('7E8 03 7F 03 22');
      expect(v, isA<ReplyRefused>());
      expect((v as ReplyRefused).nrc, 0x22);
      expect(judge('7F0311'), isA<ReplyRefused>());
    });

    test('a dead link is link-lost', () {
      expect(judge('DISCONNECTED'), isA<ReplyLinkLost>());
      expect(classifyEngineDtcReply('TIMEOUT', linkFailed: true),
          isA<ReplyLinkLost>());
    });

    test('ATDPN parsing', () {
      expect(ObdProtocol.fromAtdpn('A6').family, ObdProtocolFamily.can);
      expect(ObdProtocol.fromAtdpn('3').family, ObdProtocolFamily.kLine);
      expect(ObdProtocol.fromAtdpn('A5').family, ObdProtocolFamily.kLine);
      expect(ObdProtocol.fromAtdpn('A4').isKLine, isTrue);
      expect(ObdProtocol.fromAtdpn('A0').isKnown, isFalse);
      expect(ObdProtocol.fromAtdpn('?').isKnown, isFalse);
      expect(ObdProtocol.fromAtdpn('NO DATA').isKnown, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S2 — stale results never look live
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets(
      'S2: successful read, then a timed-out read, then a reconnect',
      (tester) async {
    late ObdService obd;
    late EngineSim sim;

    // 1. Successful read: codes, stamped LIVE SCAN.
    await tester.runAsync(() async {
      sim = EngineSim(mode03: '43 01 01 33');
      obd = await connectSim(sim);
      expect(await obd.readEngineDtcs(), isA<EngineAnswered>());
    });
    var texts = await renderedTexts(tester, obd);
    expect(texts, contains('P0133'));
    expect(texts.any((t) => t.startsWith('LIVE SCAN')), isTrue);
    // Phase 4A H3c: the Engine CARD always carries its own read time, so an
    // old result never looks live from another tab. The summary bar is still
    // the LIVE SCAN stamp, never a "Read at" - exactly one, and it is the card's.
    expect(texts.where((t) => t.startsWith('Read at')).length, 1);

    // 2. The adapter stops answering 03: the read times out.
    await tester.runAsync(() async {
      sim.mode03 = null;
      final r = await obd.readEngineDtcs();
      expect(r, isA<EngineNoAnswer>());
      expect((r as EngineNoAnswer).reason, EngineNoAnswerReason.timeout);
    });
    texts = await renderedTexts(tester, obd);
    expect(texts.any((t) => t.startsWith('LIVE SCAN')), isFalse,
        reason: 'a timed-out read must never refresh the LIVE SCAN stamp');
    expect(texts, contains(en('dtcNoAnswerTitle')));
    expect(texts.where((t) => t.startsWith('Read at ')).length,
        greaterThanOrEqualTo(1),
        reason: 'the older list is labelled with the time it was read');
    expect(texts, contains('P0133'), reason: 'shown, but greyed and labelled');
    final opacities = tester.widgetList<Opacity>(find.ancestor(
        of: find.text('P0133'), matching: find.byType(Opacity)));
    expect(opacities.any((o) => o.opacity < 1.0), isTrue,
        reason: 'the older list is greyed out');

    // 3. Reconnect: nothing from the old session survives.
    await tester.runAsync(() async {
      await obd.disconnect();
      sim.mode03 = '43 01 01 33';
      expect(await obd.connectBluetooth(simDevice), isTrue);
      expect(obd.dtcCodes, isEmpty);
      expect(obd.lastEngineRead, isNull);
      expect(obd.dtcCodesReadAt, isNull);
    });
    texts = await renderedTexts(tester, obd);
    expect(texts, isNot(contains('P0133')),
        reason: 'the previous session\'s list is cleared on reconnect');
    expect(texts.any((t) => t.startsWith('LIVE SCAN')), isFalse);

    await tester.runAsync(() async {
      await obd.disconnect();
      await sim.close();
    });
  });

  test('S2: a link drop clears the engine and ABS lists', () async {
    final sim = EngineSim(mode03: '43 01 01 33');
    final obd = await connectSim(sim);
    await obd.readEngineDtcs();
    expect(obd.dtcCodes, isNotEmpty);
    sim.dropLink();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(obd.isConnected, isFalse);
    expect(obd.dtcCodes, isEmpty);
    expect(obd.lastEngineRead, isNull);
    expect(obd.chassisDtcCodes, isEmpty);
    await sim.close();
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S3 — U, C and B codes from the engine computer are kept and labelled
  // ══════════════════════════════════════════════════════════════════════════
  testWidgets('S3: a mixed P/U/C/B list is shown whole, each with its system',
      (tester) async {
    late ObdService obd;
    late EngineSim sim;
    await tester.runAsync(() async {
      // 43, count 4: P0133 (01 33), U0100 (C1 00), C0035 (40 35), B0001
      // (80 01).
      sim = EngineSim(mode03: '43 04 01 33 C1 00 40 35 80 01');
      obd = await connectSim(sim);
      await obd.readEngineDtcs();
    });
    expect(obd.dtcCodes.map((c) => c.code).toSet(),
        {'P0133', 'U0100', 'C0035', 'B0001'});

    final texts = await renderedTexts(tester, obd);
    for (final code in ['P0133', 'U0100', 'C0035', 'B0001']) {
      expect(texts, contains(code));
    }
    for (final system in ['POWERTRAIN', 'NETWORK', 'CHASSIS', 'BODY']) {
      expect(texts, contains(system));
    }
    await tester.runAsync(() async {
      await obd.disconnect();
      await sim.close();
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // S4 — K-line gate
  // ══════════════════════════════════════════════════════════════════════════
  group('S4: K-line bikes get the gate message and no codes', () {
    test('the gate is off in this build', () {
      expect(kKLineFaultReadingEnabled, isFalse);
    });

    // The audit's K-line samples: P0133 alone, with and without headers.
    // Run through the parser they decode to P3300 / P3300+P00C0.
    for (final entry in <String, String>{
      'ISO 9141-2, headers off': '3',
      'ISO 14230-4 KWP fast, headers on': 'A5',
      'ISO 14230-4 KWP 5-baud': 'A4',
    }.entries) {
      testWidgets(entry.key, (tester) async {
        late ObdService obd;
        late EngineSim sim;
        await tester.runAsync(() async {
          sim = EngineSim(
            mode03: entry.value == 'A5'
                ? '48 6B 10 43 01 33 00 00 00 00 C0'
                : '43 01 33 00 00 00 00',
            protocol: entry.value,
          );
          obd = await connectSim(sim);
          final r = await obd.readEngineDtcs();
          expect(r, isA<EngineKLineGated>());
          expect(obd.dtcCodes, isEmpty);
        });
        expect(ObdParser.parseDetailed('43 01 33 00 00 00 00').allCodes,
            contains('P3300'),
            reason: 'proof the gate is needed: the parser mis-decodes this');

        final texts = await renderedTexts(tester, obd);
        expect(texts, contains(en('dtcKLineGated')));
        expect(texts.any((t) => RegExp(r'^[PCBU][0-9A-F]{4}$').hasMatch(t)),
            isFalse,
            reason: 'no code of any kind is displayed');
        expect(texts.contains(en('noFaultCodes')), isFalse);

        // Live data keeps working exactly as before.
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          expect(obd.data.rpm, isNotNull);
          await obd.disconnect();
          await sim.close();
        });
      });
    }

    test('CAN replies are unaffected', () async {
      final sim = EngineSim(mode03: '43 01 01 33', protocol: 'A6');
      final obd = await connectSim(sim);
      final r = await obd.readEngineDtcs();
      expect(r, isA<EngineAnswered>());
      expect((r as EngineAnswered).codes.single.code, 'P0133');
      await obd.disconnect();
      await sim.close();
    });

    test('protocol learned at read time when init could not tell', () async {
      // Ignition switched on after connecting: init sees A0, the first read
      // settles the bus as K-line — the gate must still apply.
      final sim = EngineSim(
          supportedPids: 'SEARCHING...\rUNABLE TO CONNECT',
          mode03: '43 01 33 00 00 00 00',
          protocol: 'A0',
          vehicleSilent: true);
      final obd = await connectSim(sim);
      expect(obd.session!.protocol.isKnown, isFalse);
      sim.protocol = 'A3';
      expect(await obd.readEngineDtcs(), isA<EngineKLineGated>());
      expect(obd.session!.protocol.isKLine, isTrue);
      await obd.disconnect();
      await sim.close();
    });
  });
}
