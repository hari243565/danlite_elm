/// Phase 4B (B1) — which section a fault code belongs to, and what each
/// section card may honestly say.
///
/// Pure logic: no widgets, no adapter. The rules are the owner's, in order:
///   (a) a code the ABS module scan returned is Brakes & ABS;
///   (b) else the resolved knowledge entry's system, when it names one;
///   (c) else the code's prefix and number range.
/// The cards never claim a module was scanned that was not.
library;

import 'package:danlite_elm/constants/chassis_modules.dart';
import 'package:danlite_elm/knowledge/fault_domain.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/models/vehicle_data.dart';
import 'package:danlite_elm/services/engine_dtc_read.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 3, 9);

FaultRecord rec(String code,
        {ReadSource source = ReadSource.mode03, DtcFormat format = DtcFormat.sae2}) =>
    format == DtcFormat.blink
        ? FaultRecord.manual(code, format: format, readAt: _t0)
        : FaultRecord.fromObdCode(code, source: source, readAt: _t0);

DtcCode engineCode(String code) => DtcCode(
    code: code,
    description: '',
    possibleCause: '',
    severity: 'unknown',
    action: '',
    record: FaultRecord.fromObdCode(code, source: ReadSource.mode03, readAt: _t0));

DtcCode absCode(String code) => DtcCode(
    code: code,
    description: '',
    possibleCause: '',
    severity: 'unknown',
    action: '',
    module: 'chassis',
    record: FaultRecord.fromObdCode(code, source: ReadSource.mode03, readAt: _t0, module: 'ABS'));

SectionSummary of(List<SectionSummary> all, FaultSection s) =>
    all.firstWhere((x) => x.section == s);

List<SectionSummary> summarise({
  EngineDtcRead? read,
  bool engineScanning = false,
  List<DtcCode> engineCodes = const [],
  ChassisScanOutcome abs = ChassisScanOutcome.idle,
  bool absScanning = false,
  List<DtcCode> absCodes = const [],
}) =>
    summariseSections(
      engineRead: read,
      engineScanning: engineScanning,
      engineCodes: engineCodes,
      absOutcome: abs,
      absScanning: absScanning,
      absCodes: absCodes,
    );

void main() {
  group('B1 mapping by prefix and range (rule c)', () {
    const cases = <String, FaultSection>{
      // Engine & emissions: P0000-P0699
      'P0000': FaultSection.engine,
      'P0001': FaultSection.engine,
      'P0133': FaultSection.engine,
      'P0300': FaultSection.engine,
      'P0420': FaultSection.engine,
      'P0600': FaultSection.engine,
      'P0699': FaultSection.engine,
      // the hex tail of a group belongs to the group (P06A0 is computer circuits)
      'P069A': FaultSection.engine,
      'P06FF': FaultSection.engine,
      // Transmission & riding aids: P0700-P0999
      'P0700': FaultSection.transmission,
      'P0701': FaultSection.transmission,
      'P0750': FaultSection.transmission,
      'P0800': FaultSection.transmission,
      'P0999': FaultSection.transmission,
      'P09FF': FaultSection.transmission,
      // P0A00 and up are hybrid/electric ranges: not named, so Other
      'P0A00': FaultSection.other,
      'P0A80': FaultSection.other,
      'P0FFF': FaultSection.other,
      // P1xxx: engine
      'P1000': FaultSection.engine,
      'P1630': FaultSection.engine,
      'P1FFF': FaultSection.engine,
      // P2000-P2699: engine
      'P2000': FaultSection.engine,
      'P2101': FaultSection.engine,
      'P2699': FaultSection.engine,
      // P2700-P2799: transmission
      'P2700': FaultSection.transmission,
      'P2799': FaultSection.transmission,
      // P2800 and up (and hex third digit): Other
      'P2800': FaultSection.other,
      'P2900': FaultSection.other,
      'P2A00': FaultSection.other,
      'P2FFF': FaultSection.other,
      // P3xxx: engine
      'P3000': FaultSection.engine,
      'P3400': FaultSection.engine,
      'P3FFF': FaultSection.engine,
      // C, B, U by letter
      'C0000': FaultSection.brakes,
      'C1015': FaultSection.brakes,
      'C3FFF': FaultSection.brakes,
      'B0000': FaultSection.body,
      'B1234': FaultSection.body,
      'B3FFF': FaultSection.body,
      'U0000': FaultSection.network,
      'U0100': FaultSection.network,
      'U3FFF': FaultSection.network,
      // not a code at all
      'ZZZZZ': FaultSection.other,
      'P4000': FaultSection.other,
      'P0': FaultSection.other,
      '': FaultSection.other,
    };

    for (final e in cases.entries) {
      test('${e.key.isEmpty ? "(empty)" : e.key} -> ${e.value.name}', () {
        expect(faultDomainFor(rec(e.key)), e.value);
      });
    }

    test('lower-case and padded input is normalised, not dropped', () {
      expect(faultDomainFor(rec(' p0750 ')), FaultSection.transmission);
    });

    test('there are 6 sections, in the owner\'s order', () {
      expect(FaultSection.values.map((s) => s.name).toList(),
          ['engine', 'brakes', 'body', 'network', 'transmission', 'other']);
    });
  });

  group('B1 rule (a): the ABS scan overrides the code\'s own number', () {
    test('a P code from the ABS scan is Brakes & ABS', () {
      expect(faultDomainFor(rec('P0133'), fromAbsScan: true), FaultSection.brakes);
    });
    test('a U code from the ABS scan is Brakes & ABS', () {
      expect(faultDomainFor(rec('U0100'), fromAbsScan: true), FaultSection.brakes);
    });
    test('an unreadable code from the ABS scan is Brakes & ABS', () {
      expect(faultDomainFor(rec('0x5043'), fromAbsScan: true), FaultSection.brakes);
    });
    test('the same P code from the engine scan stays Engine', () {
      expect(faultDomainFor(rec('P0133')), FaultSection.engine);
    });
    test('ABS beats a knowledge system that says otherwise', () {
      expect(
          faultDomainFor(rec('P0133'),
              fromAbsScan: true, knowledgeSystem: FaultSystem.network),
          FaultSection.brakes);
    });
  });

  group('B1 rule (b): the resolved knowledge entry\'s system', () {
    test('chassis names Brakes & ABS where the number alone could not', () {
      expect(faultDomainFor(rec('0x5043'), knowledgeSystem: FaultSystem.chassis),
          FaultSection.brakes);
    });
    test('body names Body & instruments', () {
      expect(faultDomainFor(rec('ZZZZZ'), knowledgeSystem: FaultSystem.body),
          FaultSection.body);
    });
    test('network names Network', () {
      expect(faultDomainFor(rec('ZZZZZ'), knowledgeSystem: FaultSystem.network),
          FaultSection.network);
    });
    test('chassis knowledge beats the prefix', () {
      expect(faultDomainFor(rec('B1234'), knowledgeSystem: FaultSystem.chassis),
          FaultSection.brakes);
    });
    test('powertrain is too coarse to say engine OR transmission: the number decides', () {
      expect(faultDomainFor(rec('P0750'), knowledgeSystem: FaultSystem.powertrain),
          FaultSection.transmission);
      expect(faultDomainFor(rec('P0133'), knowledgeSystem: FaultSystem.powertrain),
          FaultSection.engine);
    });
    test('powertrain on a code with no usable number stays Other, never guessed', () {
      expect(faultDomainFor(rec('ZZZZZ'), knowledgeSystem: FaultSystem.powertrain),
          FaultSection.other);
    });
    test('no knowledge system: rule (c)', () {
      expect(faultDomainFor(rec('U0100')), FaultSection.network);
    });
  });

  group('B1 a blink pattern is not a code', () {
    test('a manual blink record has no section from its pattern', () {
      expect(faultDomainFor(rec('4-2', format: DtcFormat.blink)), FaultSection.other);
    });
  });

  group('B1 cards: engine', () {
    test('never scanned', () {
      final s = of(summarise(), FaultSection.engine);
      expect(s.status, SectionStatus.notScanned);
      expect(s.count, 0);
    });
    test('scanning, with no earlier answer', () {
      expect(of(summarise(engineScanning: true), FaultSection.engine).status,
          SectionStatus.scanning);
    });
    test('an earlier answer is kept while the next read runs (the summary bar does the same)', () {
      final s = of(
          summarise(
              read: EngineAnswered([engineCode('P0133')], _t0),
              engineScanning: true,
              engineCodes: [engineCode('P0133')]),
          FaultSection.engine);
      expect(s.status, SectionStatus.found);
      expect(s.count, 1);
    });
    test('no answer: "bike did not answer", never "no faults"', () {
      for (final reason in EngineNoAnswerReason.values) {
        if (reason == EngineNoAnswerReason.moduleBusy) continue;
        final s = of(summarise(read: EngineNoAnswer(reason, _t0)), FaultSection.engine);
        expect(s.status, SectionStatus.noAnswer, reason: reason.name);
        expect(s.count, 0);
      }
    });
    test('a module that stayed busy is its own state', () {
      expect(
          of(summarise(read: EngineNoAnswer(EngineNoAnswerReason.moduleBusy, _t0)),
                  FaultSection.engine)
              .status,
          SectionStatus.moduleBusy);
    });
    test('refused, link lost and K-line are each their own state', () {
      expect(of(summarise(read: EngineRefused(0x22, _t0)), FaultSection.engine).status,
          SectionStatus.refused);
      expect(of(summarise(read: EngineLinkLost(_t0)), FaultSection.engine).status,
          SectionStatus.linkLost);
      expect(
          of(summarise(read: EngineKLineGated(ObdProtocol.fromAtdpn('A4'), _t0)),
                  FaultSection.engine)
              .status,
          SectionStatus.notReadable);
    });
    test('answered with nothing: no faults', () {
      final s = of(summarise(read: EngineAnswered(const [], _t0)), FaultSection.engine);
      expect(s.status, SectionStatus.noFaults);
      expect(s.count, 0);
    });
    test('answered with codes: N faults, counting only engine-domain codes', () {
      final codes = [
        engineCode('P0133'),
        engineCode('P0300'),
        engineCode('P0750'),
        engineCode('U0100')
      ];
      final all = summarise(read: EngineAnswered(codes, _t0), engineCodes: codes);
      expect(of(all, FaultSection.engine).count, 2);
      expect(of(all, FaultSection.engine).status, SectionStatus.found);
      expect(of(all, FaultSection.transmission).count, 1);
      expect(of(all, FaultSection.network).count, 1);
    });
    test('answered, but every code belongs elsewhere: engine says no faults', () {
      final codes = [engineCode('U0100')];
      final all = summarise(read: EngineAnswered(codes, _t0), engineCodes: codes);
      expect(of(all, FaultSection.engine).status, SectionStatus.noFaults);
    });
    test('a list from an earlier answer is NOT counted once the last read failed', () {
      final all = summarise(
          read: EngineNoAnswer(EngineNoAnswerReason.timeout, _t0),
          engineCodes: [engineCode('P0133')]);
      expect(of(all, FaultSection.engine).count, 0);
      expect(of(all, FaultSection.engine).status, SectionStatus.noAnswer);
    });
  });

  group('B1 cards: Brakes & ABS', () {
    test('never scanned', () {
      expect(of(summarise(), FaultSection.brakes).status, SectionStatus.notScanned);
    });
    test('an ABS scan in flight', () {
      expect(
          of(summarise(abs: ChassisScanOutcome.clean, absScanning: true),
                  FaultSection.brakes)
              .status,
          SectionStatus.scanning);
    });
    test('one state per scan outcome', () {
      const expected = <ChassisScanOutcome, SectionStatus>{
        ChassisScanOutcome.idle: SectionStatus.notScanned,
        ChassisScanOutcome.clean: SectionStatus.noFaults,
        ChassisScanOutcome.noModuleResponse: SectionStatus.noAnswer,
        ChassisScanOutcome.addressingUnsupported: SectionStatus.adapterLimited,
        ChassisScanOutcome.linkUnavailable: SectionStatus.linkLost,
        ChassisScanOutcome.moduleBusy: SectionStatus.moduleBusy,
      };
      expected.forEach((outcome, status) {
        expect(of(summarise(abs: outcome), FaultSection.brakes).status, status,
            reason: outcome.name);
      });
    });
    test('faults found: N faults', () {
      final codes = [absCode('C1015'), absCode('C1040')];
      final s = of(
          summarise(abs: ChassisScanOutcome.faultsFound, absCodes: codes),
          FaultSection.brakes);
      expect(s.status, SectionStatus.found);
      expect(s.count, 2);
    });
    test('a P code the ABS module reported is counted under Brakes, not Engine', () {
      final codes = [absCode('P0133')];
      final all = summarise(abs: ChassisScanOutcome.faultsFound, absCodes: codes);
      expect(of(all, FaultSection.brakes).count, 1);
      expect(of(all, FaultSection.engine).count, 0);
    });
    test('stale ABS codes are not counted when the last scan lost the link', () {
      final all = summarise(
          abs: ChassisScanOutcome.linkUnavailable, absCodes: [absCode('C1015')]);
      expect(of(all, FaultSection.brakes).count, 0);
      expect(of(all, FaultSection.brakes).status, SectionStatus.linkLost);
    });
    test('a C code from the ENGINE scan shows on the Brakes card, and says where it came from', () {
      final codes = [engineCode('C0035')];
      final s = of(
          summarise(read: EngineAnswered(codes, _t0), engineCodes: codes),
          FaultSection.brakes);
      expect(s.status, SectionStatus.found);
      expect(s.count, 1);
      expect(s.fromEngineScanOnly, isTrue,
          reason: 'the ABS module was not scanned: the card must not imply it was');
    });
    test('...and not when the ABS scan also found faults', () {
      final all = summarise(
          read: EngineAnswered([engineCode('C0035')], _t0),
          engineCodes: [engineCode('C0035')],
          abs: ChassisScanOutcome.faultsFound,
          absCodes: [absCode('C1015')]);
      expect(of(all, FaultSection.brakes).count, 2);
      expect(of(all, FaultSection.brakes).fromEngineScanOnly, isFalse);
    });
  });

  group('B1 cards: Body, Network, Transmission, Other', () {
    const others = [
      FaultSection.body,
      FaultSection.network,
      FaultSection.transmission,
      FaultSection.other
    ];

    test('before any scan: not scanned yet', () {
      final all = summarise();
      for (final s in others) {
        expect(of(all, s).status, SectionStatus.notScanned, reason: s.name);
      }
    });
    test('an engine scan that did not answer does not make them "none found"', () {
      final all = summarise(read: EngineNoAnswer(EngineNoAnswerReason.noData, _t0));
      for (final s in others) {
        expect(of(all, s).status, SectionStatus.notScanned, reason: s.name);
      }
    });
    test('an ABS scan that did not answer does not either', () {
      for (final o in [
        ChassisScanOutcome.noModuleResponse,
        ChassisScanOutcome.moduleBusy,
        ChassisScanOutcome.addressingUnsupported,
        ChassisScanOutcome.linkUnavailable,
        ChassisScanOutcome.idle,
      ]) {
        final all = summarise(abs: o);
        for (final s in others) {
          expect(of(all, s).status, SectionStatus.notScanned, reason: '${o.name} ${s.name}');
        }
      }
    });
    test('an engine scan that answered with nothing: none found', () {
      final all = summarise(read: EngineAnswered(const [], _t0));
      for (final s in others) {
        expect(of(all, s).status, SectionStatus.noFaults, reason: s.name);
      }
    });
    test('a clean ABS scan alone also answers: none found', () {
      final all = summarise(abs: ChassisScanOutcome.clean);
      for (final s in others) {
        expect(of(all, s).status, SectionStatus.noFaults, reason: s.name);
      }
    });
    test('codes land on the right card', () {
      final codes = [
        engineCode('B1234'),
        engineCode('U0100'),
        engineCode('U0101'),
        engineCode('P0750'),
        engineCode('P0A00'),
        engineCode('P0133')
      ];
      final all = summarise(read: EngineAnswered(codes, _t0), engineCodes: codes);
      expect(of(all, FaultSection.body).count, 1);
      expect(of(all, FaultSection.network).count, 2);
      expect(of(all, FaultSection.transmission).count, 1);
      expect(of(all, FaultSection.other).count, 1);
      expect(of(all, FaultSection.engine).count, 1);
      expect(of(all, FaultSection.body).status, SectionStatus.found);
    });
    test('the six cards are always returned, in order', () {
      expect(summarise().map((s) => s.section).toList(), FaultSection.values);
    });
  });

  group('B1 the list behind a card (filter)', () {
    test('every found code is tagged with its section and source', () {
      final found = foundCodes(
        engineRead: EngineAnswered([engineCode('P0133'), engineCode('U0100')], _t0),
        engineCodes: [engineCode('P0133'), engineCode('U0100')],
        absOutcome: ChassisScanOutcome.faultsFound,
        absCodes: [absCode('C1015')],
      );
      expect(found.map((f) => '${f.code.code}:${f.section.name}:${f.fromAbs}').toList(),
          ['P0133:engine:false', 'U0100:network:false', 'C1015:brakes:true']);
    });
    test('filtering keeps only that section, and All keeps everything', () {
      final found = foundCodes(
        engineRead: EngineAnswered([engineCode('P0133'), engineCode('U0100')], _t0),
        engineCodes: [engineCode('P0133'), engineCode('U0100')],
        absOutcome: ChassisScanOutcome.faultsFound,
        absCodes: [absCode('C1015')],
      );
      expect(filterBySection(found, FaultSection.network).map((f) => f.code.code), ['U0100']);
      expect(filterBySection(found, FaultSection.brakes).map((f) => f.code.code), ['C1015']);
      expect(filterBySection(found, FaultSection.body), isEmpty);
      expect(filterBySection(found, null).length, 3);
    });
    test('nothing is found from a read that did not answer', () {
      expect(
          foundCodes(
              engineRead: EngineNoAnswer(EngineNoAnswerReason.noData, _t0),
              engineCodes: [engineCode('P0133')],
              absOutcome: ChassisScanOutcome.noModuleResponse,
              absCodes: [absCode('C1015')]),
          isEmpty);
    });
    test('the card count always equals the length of its filtered list', () {
      final eng = [
        engineCode('P0133'),
        engineCode('P0750'),
        engineCode('B1234'),
        engineCode('C0035'),
        engineCode('P0A00')
      ];
      final abs = [absCode('C1015'), absCode('U0100')];
      final read = EngineAnswered(eng, _t0);
      final found = foundCodes(
          engineRead: read,
          engineCodes: eng,
          absOutcome: ChassisScanOutcome.faultsFound,
          absCodes: abs);
      final all = summariseSections(
          engineRead: read,
          engineScanning: false,
          engineCodes: eng,
          absOutcome: ChassisScanOutcome.faultsFound,
          absScanning: false,
          absCodes: abs);
      for (final s in FaultSection.values) {
        expect(of(all, s).count, filterBySection(found, s).length, reason: s.name);
      }
    });
  });
}
