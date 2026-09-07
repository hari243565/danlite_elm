/// Danlite ELM — widened ABS/chassis addressing, adapter-timing signal, and
/// learned-address memory
///
/// WHAT THIS PROVES:
///   * the widened candidate list is internally consistent with the published
///     conventions it claims to come from (every response filter is derived
///     from its request by the documented rule, not typed in by hand), that it
///     still excludes the engine, and that it is genuinely probed in the
///     documented order on the wire;
///   * the adapter-timing heuristic classifies real measured latencies the way
///     its documented thresholds say it should, and reaches the scan outcome
///     end to end against a simulated adapter;
///   * an address that genuinely answers is stored against that vehicle's make
///     and model and is genuinely tried first on the next scan.
///
/// WHAT THIS DOES NOT PROVE: that any particular real motorcycle answers at
/// any of these addresses, or that any particular real adapter can reach a
/// non-engine module. Those are properties of hardware. Every adapter here is
/// simulated, and a simulated adapter can be made to do anything.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:danlite_elm/constants/chassis_modules.dart';
import 'package:danlite_elm/constants/obd_pids.dart';
import 'package:danlite_elm/services/bluetooth_classic_service.dart';
import 'package:danlite_elm/services/chassis_address_memory.dart';
import 'package:danlite_elm/services/obd_service.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // 1. THE WIDENED CANDIDATE LIST
  // ══════════════════════════════════════════════════════════════════════════
  group('widened candidate list', () {
    final generic = ChassisModuleProfiles.genericCandidates;

    test('the two originally-shipped candidates are still first, unchanged',
        () {
      // The whole point of the widening is that it is additive. If this ever
      // fails, a scan that used to work may have started behaving differently.
      expect(generic[0].requestHeader, '7B0');
      expect(generic[0].responseFilter, '7B8');
      expect(generic[1].requestHeader, '760');
      expect(generic[1].responseFilter, '768');

      for (final t in <ChassisModuleTarget>[generic[0], generic[1]]) {
        expect(t.requests, <String>['1902FF', '03'],
            reason: 'both original candidates still try UDS then Mode 03');
        expect(t.core, isTrue,
            reason: 'neither may be dropped by the budget or timeout abort');
        expect(t.addressing, ChassisAddressing.elevenBit);
      }

      expect(
        generic[0].wireSequence,
        <String>[
          'ATSH7B0',
          'ATCRA7B8',
          'ATFCSH7B0',
          'ATFCSD300000',
          'ATFCSM1',
          '1902FF',
          '03',
        ],
        reason: 'the first candidate emits byte-for-byte what it always did',
      );
    });

    test('the list is genuinely wider than the two it started with', () {
      expect(generic.length, greaterThan(2));
      expect(ChassisModuleProfiles.extendedCandidates, isNotEmpty);
    });

    test('exactly the two original candidates are marked core', () {
      expect(generic.where((t) => t.core).length, 2);
    });

    test('no candidate address is a legislated OBD ECU or the broadcast', () {
      for (final t in ChassisModuleProfiles.allKnownTargets) {
        final req = t.requestHeader.toUpperCase();
        expect(req.startsWith('7E'), isFalse,
            reason: '$req is in the legislated 0x7E0-0x7E7 OBD ECU block');
        expect(req, isNot('7DF'), reason: '7DF is the OBD functional broadcast');
        // The 29-bit equivalent: 0x10 is the engine's extended-addressing
        // target, so DA10F1 would be the same mistake in the other scheme.
        expect(req, isNot('DA10F1'),
            reason: 'DA10F1 addresses the engine in the 29-bit scheme');
      }
    });

    test('no response filter can catch an engine reply', () {
      for (final t in ChassisModuleProfiles.allKnownTargets) {
        final resp = t.responseFilter.toUpperCase();
        expect(RegExp(r'^7E[89A-F]$').hasMatch(resp), isFalse,
            reason: '$resp is a legislated OBD ECU response ID');
      }
    });

    test('every 11-bit +8 candidate really is request + 8', () {
      final plus8 = ChassisModuleProfiles.allKnownTargets.where(
          (t) => t.convention == ChassisAddressConvention.isoPhysicalPlus8);
      expect(plus8, isNotEmpty);
      for (final t in plus8) {
        final req = int.parse(t.requestHeader, radix: 16);
        final resp = int.parse(t.responseFilter, radix: 16);
        expect(resp, req + 8,
            reason: '${t.label}: the documented rule for this range is '
                'response = request + 8');
        expect(t.requestHeader.length, 3);
        expect(t.responseFilter.length, 3);
        expect(req, inInclusiveRange(0x700, 0x7DF),
            reason: 'the documented 11-bit physical-addressing region');
      }
    });

    test('every VAG candidate really is request + 0x6A', () {
      final vag = ChassisModuleProfiles.allKnownTargets
          .where((t) => t.convention == ChassisAddressConvention.vagPlus6A);
      expect(vag, isNotEmpty);
      for (final t in vag) {
        final req = int.parse(t.requestHeader, radix: 16);
        final resp = int.parse(t.responseFilter, radix: 16);
        expect(resp, req + 0x6A,
            reason: '${t.label}: the documented VW Group offset is +0x6A');
      }
      // The specific published ID this convention was taken from.
      expect(vag.any((t) => t.requestHeader == '713' && t.responseFilter == '77D'),
          isTrue,
          reason: 'the published VAG brake-module ID must be in the list');
    });

    test('every 29-bit candidate swaps target and tester, never adds 8', () {
      final ext = ChassisModuleProfiles.allKnownTargets
          .where((t) => t.convention == ChassisAddressConvention.isoExtended29Bit);
      expect(ext, isNotEmpty);
      for (final t in ext) {
        expect(t.addressing, ChassisAddressing.twentyNineBit);
        expect(t.requestHeader.length, 6,
            reason: 'ATSH takes six hex digits on 29-bit CAN');
        expect(t.responseFilter.length, 8,
            reason: 'ATCRA takes the full eight on 29-bit CAN');
        expect(t.requestHeader.substring(0, 2), 'DA');

        final target = t.requestHeader.substring(2, 4);
        final tester = t.requestHeader.substring(4, 6);
        expect(tester, 'F1', reason: 'F1 is the conventional tester address');
        expect(t.responseFilter, '18DA$tester$target',
            reason: 'extended addressing answers on 18DA<tester><target>');
      }
    });

    test('a 29-bit candidate sets the CAN priority first; an 11-bit one does '
        'not', () {
      final ext = ChassisModuleProfiles.extendedCandidates.first;
      expect(ext.wireSequence.first, 'ATCP18');
      expect(ext.wireSequence, contains('ATSHDA28F1'));
      expect(ext.wireSequence, contains('ATCRA18DAF128'));

      expect(ChassisModuleProfiles.genericCandidates.first.priorityCommands,
          isEmpty,
          reason: 'ATCP must not appear on the 11-bit path at all');
    });

    test('no two candidates address the same module twice', () {
      final ids =
          ChassisModuleProfiles.allKnownTargets.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'a duplicated address is wasted scan time');
    });

    test('29-bit candidates are only offered on a 29-bit bus', () {
      final narrow = ChassisModuleProfiles.candidatesFor(null);
      final wide = ChassisModuleProfiles.candidatesFor(null,
          supportsTwentyNineBit: true);

      expect(
          narrow.any((t) => t.addressing == ChassisAddressing.twentyNineBit),
          isFalse);
      expect(wide.any((t) => t.addressing == ChassisAddressing.twentyNineBit),
          isTrue);
      expect(wide.length,
          narrow.length + ChassisModuleProfiles.extendedCandidates.length);
      // The 11-bit order is untouched by the addition.
      expect(wide.take(narrow.length).toList(), narrow);
    });

    test('unknown manufacturers still get the full widened probe order', () {
      expect(ChassisModuleProfiles.candidatesFor(null), generic);
      expect(ChassisModuleProfiles.candidatesFor('some_other_make'), generic);
    });

    test('targetById round-trips every candidate and rejects an unknown id',
        () {
      for (final t in ChassisModuleProfiles.allKnownTargets) {
        expect(ChassisModuleProfiles.targetById(t.id), same(t));
      }
      expect(ChassisModuleProfiles.targetById('999>9A1'), isNull);
      expect(ChassisModuleProfiles.targetById(''), isNull);
      expect(ChassisModuleProfiles.targetById(null), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 2. THE WIDER LIST IS GENUINELY TRIED, IN ORDER, ON THE WIRE
  // ══════════════════════════════════════════════════════════════════════════
  group('the widened list is actually probed in the documented order', () {
    test('every candidate is addressed, in list order', () async {
      // A bike with no chassis module anywhere: every address answers NO DATA
      // after a realistic delay, so nothing times out and the sweep runs to
      // the end of the list.
      final elm = ProgrammableElm(negativeDelay: const Duration(milliseconds: 60));
      final obd = ObdService(elm,
          chassisAddressMemory:
              ChassisAddressMemory(store: InMemoryChassisAddressStore()));
      await obd.connectBluetooth(const BtDevice(
          name: 'OBDII', address: '00:11:22:33:44:55', bonded: true));

      await obd.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');

      final positions = <int>[];
      for (final t in ChassisModuleProfiles.genericCandidates) {
        final at = elm.wire.indexOf(t.headerCommand);
        expect(at, greaterThanOrEqualTo(0),
            reason: '${t.headerCommand} was never sent — the candidate was '
                'never actually probed');
        positions.add(at);
      }

      final sorted = List<int>.from(positions)..sort();
      expect(positions, sorted,
          reason: 'candidates must go out in the documented tier order');

      // And the honest outcome is unchanged by all the extra addresses.
      expect(obd.chassisDtcCodes, isEmpty);
      expect(obd.chassisScanOutcome, ChassisScanOutcome.noModuleResponse);

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('a 29-bit bus gets the extended candidate; an 11-bit bus does not',
        () async {
      final wideElm = ProgrammableElm(
          protocolNumber: '7',
          negativeDelay: const Duration(milliseconds: 20));
      final wideObd = ObdService(wideElm,
          chassisAddressMemory:
              ChassisAddressMemory(store: InMemoryChassisAddressStore()));
      await wideObd.connectBluetooth(const BtDevice(
          name: 'OBDII', address: '00:11:22:33:44:55', bonded: true));
      await wideObd.readChassisDtcs(vehicleMake: 'Royal Enfield');

      expect(wideElm.wire, contains('ATSHDA28F1'));
      expect(wideElm.wire, contains('ATCP18'));
      await wideObd.disconnect();
      await wideElm.close();

      final narrowElm =
          ProgrammableElm(negativeDelay: const Duration(milliseconds: 20));
      final narrowObd = ObdService(narrowElm,
          chassisAddressMemory:
              ChassisAddressMemory(store: InMemoryChassisAddressStore()));
      await narrowObd.connectBluetooth(const BtDevice(
          name: 'OBDII', address: '00:11:22:33:44:55', bonded: true));
      await narrowObd.readChassisDtcs(vehicleMake: 'Royal Enfield');

      expect(narrowElm.wire, isNot(contains('ATSHDA28F1')),
          reason: 'a 29-bit header on an 11-bit bus is noise, not coverage');
      expect(narrowElm.wire, isNot(contains('ATCP18')));
      await narrowObd.disconnect();
      await narrowElm.close();
    }, timeout: const Timeout(Duration(seconds: 180)));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 3. THE ADAPTER-TIMING HEURISTIC
  // ══════════════════════════════════════════════════════════════════════════
  group('adapter-timing classification', () {
    test('too few samples is honestly reported as unknown', () {
      expect(
        ChassisTiming.classify(negativeLatenciesMs: <int>[1, 1, 1], timedOut: 0),
        ChassisAdapterCapability.unknown,
        reason: 'three implausible probes is noise, not a verdict',
      );
      expect(
        ChassisTiming.classify(negativeLatenciesMs: <int>[], timedOut: 0),
        ChassisAdapterCapability.unknown,
      );
    });

    test('negatives that arrive inside a plausible window read as genuine', () {
      // ~500ms is the ATST7D window the scan configures; the adapter really
      // did wait it out.
      expect(
        ChassisTiming.classify(
            negativeLatenciesMs: <int>[505, 498, 512, 501, 499], timedOut: 0),
        ChassisAdapterCapability.timingLooksGenuine,
      );
    });

    test('a negative faster than the ECU\'s own response window is implausible',
        () {
      // Below ISO 14229-2's P2 window, the adapter cannot yet know that
      // nothing answered.
      expect(
        ChassisTiming.classify(
            negativeLatenciesMs: <int>[2, 1, 3, 2, 1], timedOut: 0),
        ChassisAdapterCapability.timingSuggestsLimited,
      );
    });

    test('the threshold is the documented 50 ms, exclusive', () {
      expect(
        ChassisTiming.classify(
            negativeLatenciesMs: List<int>.filled(
                8, ChassisTiming.implausiblyFastNegativeMs - 1),
            timedOut: 0),
        ChassisAdapterCapability.timingSuggestsLimited,
      );
      expect(
        ChassisTiming.classify(
            negativeLatenciesMs:
                List<int>.filled(8, ChassisTiming.implausiblyFastNegativeMs),
            timedOut: 0),
        ChassisAdapterCapability.timingLooksGenuine,
        reason: 'exactly at the ECU window is plausible, not suspect',
      );
    });

    test('probes that never return at all count as implausible', () {
      expect(
        ChassisTiming.classify(negativeLatenciesMs: <int>[], timedOut: 5),
        ChassisAdapterCapability.timingSuggestsLimited,
      );
    });

    test('a mixed picture stays inconclusive rather than accusing the '
        'hardware', () {
      // 4 implausible out of 8 = 50%, below the 70% share.
      expect(
        ChassisTiming.classify(
            negativeLatenciesMs: <int>[1, 2, 3, 4, 500, 510, 495, 505],
            timedOut: 0),
        ChassisAdapterCapability.timingLooksGenuine,
      );
      // 7 of 10 = exactly the share, which does tip.
      expect(
        ChassisTiming.classify(
            negativeLatenciesMs: <int>[1, 2, 3, 4, 5, 6, 7, 500, 510, 495],
            timedOut: 0),
        ChassisAdapterCapability.timingSuggestsLimited,
      );
    });

    test('median ignores an outlier that describes no real probe', () {
      expect(ChassisTiming.medianMs(<int>[]), isNull);
      expect(ChassisTiming.medianMs(<int>[7]), 7);
      expect(ChassisTiming.medianMs(<int>[500, 510, 490, 5000]), 505,
          reason: 'a mean would be dragged to 1625 by the one outlier');
      expect(ChassisTiming.medianMs(<int>[3, 1, 2]), 2);
    });
  });

  group('the timing signal end to end', () {
    test('an adapter that answers implausibly fast raises the honest capability '
        'notice', () async {
      // Every probe comes back "NO DATA" instantly — far faster than a real
      // bus round trip could conclude anything.
      final elm = ProgrammableElm(negativeDelay: Duration.zero);
      final obd = ObdService(elm,
          chassisAddressMemory:
              ChassisAddressMemory(store: InMemoryChassisAddressStore()));
      await obd.connectBluetooth(const BtDevice(
          name: 'OBDII', address: '00:11:22:33:44:55', bonded: true));

      await obd.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');

      expect(obd.chassisScanOutcome, ChassisScanOutcome.noModuleResponse,
          reason: 'the existing honest outcome is unchanged');
      expect(obd.chassisAdapterCapability,
          ChassisAdapterCapability.timingSuggestsLimited);
      expect(obd.chassisProbeMedianMs, isNotNull);
      expect(obd.chassisProbeMedianMs,
          lessThan(ChassisTiming.implausiblyFastNegativeMs));
      expect(
        obd.chassisScanLog.any((l) =>
            l.contains('Adapter timing') &&
            l.contains('may point at the adapter')),
        isTrue,
        reason: 'the scan log must say why, in words, not just set an enum',
      );
      // Still stated as a possibility, never as a fact about the hardware.
      expect(obd.chassisScanLog.any((l) => l.contains('may point at')), isTrue);

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('an adapter that really waits for the bus is not accused', () async {
      final elm =
          ProgrammableElm(negativeDelay: const Duration(milliseconds: 120));
      final obd = ObdService(elm,
          chassisAddressMemory:
              ChassisAddressMemory(store: InMemoryChassisAddressStore()));
      await obd.connectBluetooth(const BtDevice(
          name: 'OBDII', address: '00:11:22:33:44:55', bonded: true));

      await obd.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');

      expect(obd.chassisScanOutcome, ChassisScanOutcome.noModuleResponse);
      expect(obd.chassisAdapterCapability,
          ChassisAdapterCapability.timingLooksGenuine);
      expect(obd.chassisProbeMedianMs,
          greaterThanOrEqualTo(ChassisTiming.implausiblyFastNegativeMs));

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('a scan that found a module makes no claim about the adapter',
        () async {
      final elm = ProgrammableElm(
        respondingHeader: '7B0',
        negativeDelay: Duration.zero,
      );
      final obd = ObdService(elm,
          chassisAddressMemory:
              ChassisAddressMemory(store: InMemoryChassisAddressStore()));
      await obd.connectBluetooth(const BtDevice(
          name: 'OBDII', address: '00:11:22:33:44:55', bonded: true));

      await obd.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');

      expect(obd.chassisScanOutcome, ChassisScanOutcome.faultsFound);
      expect(obd.chassisAdapterCapability, ChassisAdapterCapability.unknown,
          reason: 'the adapter reached a module — there is nothing to infer');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 120)));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 4. LEARNED-ADDRESS MEMORY
  // ══════════════════════════════════════════════════════════════════════════
  group('learned-address memory scope', () {
    test('the key is make + model and nothing else', () {
      final a = ChassisAddressMemory.vehicleKey('Royal Enfield', 'Classic 350');
      final b = ChassisAddressMemory.vehicleKey('  royal-enfield ', 'CLASSIC350');
      expect(a, isNotNull);
      expect(b, a,
          reason: 'two customers typing the same vehicle differently must '
              'produce the same key, or a discovery benefits nobody else');
    });

    test('a different model is a different vehicle', () {
      expect(ChassisAddressMemory.vehicleKey('Royal Enfield', 'Classic 350'),
          isNot(ChassisAddressMemory.vehicleKey('Royal Enfield', 'Himalayan')));
      expect(ChassisAddressMemory.vehicleKey('Royal Enfield', ''),
          isNot(ChassisAddressMemory.vehicleKey('Royal Enfield', 'Classic 350')));
    });

    test('a blank make has nothing to key on', () {
      expect(ChassisAddressMemory.vehicleKey(null, 'Classic 350'), isNull);
      expect(ChassisAddressMemory.vehicleKey('   ', 'Classic 350'), isNull);
    });

    test('remembering is idempotent and survives a new memory over the same '
        'store', () async {
      final store = InMemoryChassisAddressStore();
      final target = ChassisModuleProfiles.genericCandidates.last;

      final first = ChassisAddressMemory(store: store);
      await first.load();
      expect(
          await first.remember(
              make: 'Royal Enfield', model: 'Classic 350', target: target),
          isTrue);
      expect(
          await first.remember(
              make: 'Royal Enfield', model: 'Classic 350', target: target),
          isFalse,
          reason: 'an unchanged value must not rewrite storage every scan');

      final second = ChassisAddressMemory(store: store);
      await second.load();
      expect(second.knownTarget('Royal Enfield', 'Classic 350'), same(target));
      expect(second.knownTarget('Royal Enfield', 'Himalayan'), isNull,
          reason: 'the memory is scoped to the vehicle it was learned on');
    });

    test('a blank make is not remembered', () async {
      final store = InMemoryChassisAddressStore();
      final memory = ChassisAddressMemory(store: store);
      await memory.load();
      expect(
          await memory.remember(
              make: '',
              model: 'Classic 350',
              target: ChassisModuleProfiles.genericCandidates.first),
          isFalse);
      expect(store.entries, isEmpty);
    });

    test('a stale stored id resolves to nothing rather than a wrong address',
        () async {
      final memory = ChassisAddressMemory(
          store: InMemoryChassisAddressStore(
              <String, String>{'royalenfield|classic350': '999>9A1'}));
      await memory.load();
      expect(memory.knownTargetId('Royal Enfield', 'Classic 350'), '999>9A1');
      expect(memory.knownTarget('Royal Enfield', 'Classic 350'), isNull,
          reason: 'an address dropped by a later release must stay dropped');
    });

    test('ordered() hoists the remembered address and keeps everything else',
        () async {
      final candidates = ChassisModuleProfiles.genericCandidates;
      final learned = candidates[6];
      final memory = ChassisAddressMemory(store: InMemoryChassisAddressStore());
      await memory.load();
      await memory.remember(
          make: 'Royal Enfield', model: 'Classic 350', target: learned);

      final ordered = memory.ordered(candidates,
          make: 'Royal Enfield', model: 'Classic 350');

      expect(ordered.first, same(learned));
      expect(ordered.length, candidates.length,
          reason: 'reorder, never replace — the full sweep still follows');
      expect(ordered.toSet(), candidates.toSet());
      // Relative order of everything else is preserved.
      final rest = ordered.skip(1).toList();
      expect(rest, candidates.where((c) => c.id != learned.id).toList());
    });

    test('ordered() is a no-op when nothing is remembered', () async {
      final memory = ChassisAddressMemory(store: InMemoryChassisAddressStore());
      await memory.load();
      final candidates = ChassisModuleProfiles.genericCandidates;
      expect(
          memory.ordered(candidates,
              make: 'Royal Enfield', model: 'Classic 350'),
          same(candidates));
    });

    test('forget() removes one vehicle without touching the others', () async {
      final store = InMemoryChassisAddressStore();
      final memory = ChassisAddressMemory(store: store);
      await memory.load();
      await memory.remember(
          make: 'Royal Enfield',
          model: 'Classic 350',
          target: ChassisModuleProfiles.genericCandidates[4]);
      await memory.remember(
          make: 'Royal Enfield',
          model: 'Himalayan',
          target: ChassisModuleProfiles.genericCandidates[5]);

      await memory.forget(make: 'Royal Enfield', model: 'Classic 350');
      expect(memory.knownTargetId('Royal Enfield', 'Classic 350'), isNull);
      expect(memory.knownTargetId('Royal Enfield', 'Himalayan'), isNotNull);
    });
  });

  group('a real discovery is stored and reused on the next scan', () {
    test('scan 1 finds a swept address; scan 2 tries it before anything else',
        () async {
      // 0x740 is one of the addresses only added by the widening, so this also
      // proves the wider list is what made the discovery possible at all.
      const discovered = '740';
      final store = InMemoryChassisAddressStore();

      // ── Scan 1: nothing is known, the sweep has to find it ────────────────
      final elm1 = ProgrammableElm(
        respondingHeader: discovered,
        negativeDelay: const Duration(milliseconds: 10),
      );
      final obd1 = ObdService(elm1,
          chassisAddressMemory: ChassisAddressMemory(store: store));
      await obd1.connectBluetooth(const BtDevice(
          name: 'OBDII', address: '00:11:22:33:44:55', bonded: true));
      await obd1.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');

      expect(obd1.chassisScanOutcome, ChassisScanOutcome.faultsFound);
      expect(obd1.chassisRespondingModule, contains('740'));
      expect(
          obd1.chassisScanLog.any((l) => l.startsWith('Remembered ')), isTrue,
          reason: 'the discovery must be reported, not made silently');

      // On the first scan the original candidates are still probed first —
      // nothing was known yet.
      expect(elm1.wire.indexOf('ATSH7B0'),
          lessThan(elm1.wire.indexOf('ATSH$discovered')));

      // It went into the store under the vehicle-shaped key, with no device or
      // user component.
      expect(store.entries, <String, String>{
        'royalenfield|classic350': '$discovered>748',
      });

      await obd1.disconnect();
      await elm1.close();

      // ── Scan 2: a different service instance, same vehicle, same store ────
      final elm2 = ProgrammableElm(
        respondingHeader: discovered,
        negativeDelay: const Duration(milliseconds: 10),
      );
      final obd2 = ObdService(elm2,
          chassisAddressMemory: ChassisAddressMemory(store: store));
      await obd2.connectBluetooth(const BtDevice(
          name: 'OBDII', address: '00:11:22:33:44:55', bonded: true));
      await obd2.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');

      expect(obd2.chassisScanOutcome, ChassisScanOutcome.faultsFound);
      expect(obd2.chassisLearnedModule, contains('740'));

      final learnedAt = elm2.wire.indexOf('ATSH$discovered');
      expect(learnedAt, greaterThanOrEqualTo(0));
      expect(elm2.wire.indexOf('ATSH7B0'), isNot(inInclusiveRange(0, learnedAt)),
          reason: 'the remembered address must be tried before the sweep — on '
              'a hit, 7B0 should not be probed at all');
      expect(obd2.chassisScanLog.any((l) => l.contains('remembered address')),
          isTrue);

      await obd2.disconnect();
      await elm2.close();
    }, timeout: const Timeout(Duration(seconds: 180)));

    test('a different model does not inherit another model\'s address',
        () async {
      final store = InMemoryChassisAddressStore(
          <String, String>{'royalenfield|classic350': '740>748'});

      final elm = ProgrammableElm(
          negativeDelay: const Duration(milliseconds: 10));
      final obd = ObdService(elm,
          chassisAddressMemory: ChassisAddressMemory(store: store));
      await obd.connectBluetooth(const BtDevice(
          name: 'OBDII', address: '00:11:22:33:44:55', bonded: true));
      await obd.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Himalayan');

      expect(obd.chassisLearnedModule, isEmpty);
      expect(elm.wire.indexOf('ATSH7B0'), lessThan(elm.wire.indexOf('ATSH740')),
          reason: 'an unlearned vehicle probes in the plain documented order');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// A PROGRAMMABLE SIMULATED ELM327
// ═══════════════════════════════════════════════════════════════════════════
/// A simulated adapter whose two interesting properties can be dialled:
/// **which physical address (if any) a module answers at**, and **how long a
/// negative answer takes to come back**.
///
/// Those are exactly the two variables the features under test are about: the
/// widened candidate list exists to find the first, and the timing heuristic
/// exists to reason about the second. Everything else it does — addressing
/// state, AT acknowledgement, the protocol report — is modelled only closely
/// enough to make those two behave realistically.
///
/// It is a simulation, and it proves nothing about real hardware.
class ProgrammableElm extends BluetoothClassicService {
  ProgrammableElm({
    this.respondingHeader,
    this.negativeDelay = const Duration(milliseconds: 60),
    this.protocolNumber = '6',
  });

  /// The `ATSH` value at which a module answers `19 02 FF`, or null for a
  /// vehicle where no chassis module answers anywhere.
  final String? respondingHeader;

  /// How long a "nobody is here" reply takes. Below
  /// [ChassisTiming.implausiblyFastNegativeMs] this models a clone that never
  /// waited for the bus; well above it, an adapter that did.
  final Duration negativeDelay;

  /// What `ATDPN` reports. 6 = ISO 15765-4 11-bit; 7 = 29-bit.
  final String protocolNumber;

  final _ctrl = StreamController<String>.broadcast();

  /// Every command written, in order, uppercased and trimmed.
  final List<String> wire = <String>[];

  bool _connected = false;
  String? _header;

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
    final c = cmd.trim().toUpperCase();
    wire.add(c);

    if (c.isEmpty) {
      _reply('\r>', Duration.zero);
      return true;
    }

    // Addressing state, tracked the way a real adapter holds it.
    if (c.startsWith('ATSH')) {
      _header = c.substring(4);
    } else if (c == 'ATZ' || c == ObdPids.autoProtocol || c == 'ATAR') {
      _header = null;
    }

    if (c == 'ATZ') {
      _reply('\r\rELM327 v1.5\r\r>', Duration.zero);
    } else if (c == 'ATDPN') {
      _reply('\r$protocolNumber\r\r>', Duration.zero);
    } else if (c.startsWith('AT')) {
      _reply('\rOK\r\r>', Duration.zero);
    } else if (c == '0100') {
      _reply('\r41 00 BE 3E B8 11\r\r>', Duration.zero);
    } else if (_header == null) {
      // Unaddressed: the functional broadcast, where only the engine answers.
      _reply(c == '03' ? '\r7E8 06 43 01 01 72\r\r>' : '\r>', Duration.zero);
    } else if (_header == respondingHeader && c == '1902FF') {
      // The module answers with one real, documented Classic 350 code (C1058,
      // 0x50 0x58) so the reply travels the full decode path.
      final resp = _plusEight(_header!);
      _reply('\r$resp 07 59 02 FF 50 58 00 2F\r\r>',
          const Duration(milliseconds: 12));
    } else {
      // Addressed at a module that is not there.
      _reply('\rNO DATA\r\r>', negativeDelay);
    }
    return true;
  }

  void _reply(String payload, Duration after) {
    if (after == Duration.zero) {
      scheduleMicrotask(() {
        if (!_ctrl.isClosed) _ctrl.add(payload);
      });
    } else {
      Future<void>.delayed(after, () {
        if (!_ctrl.isClosed) _ctrl.add(payload);
      });
    }
  }

  static String _plusEight(String header) =>
      (int.parse(header, radix: 16) + 8).toRadixString(16).toUpperCase();

  Future<void> close() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }
}
