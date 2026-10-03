/// Danlite ELM — ABS / chassis DTC logic tests
///
/// WHAT THIS PROVES: that the software constructs the correct request bytes
/// for an ABS-module read, decodes a UDS reply into the correct codes, and
/// resolves those codes to the correct manufacturer descriptions and remedies
/// in both English and Hindi.
///
/// WHAT THIS DOES NOT PROVE: that a real Royal Enfield will answer. These
/// tests feed simulated adapter responses. Whether a real motorcycle's ABS
/// module replies depends on the module's actual CAN address and on whether
/// the specific ELM327 adapter in use supports module addressing at all —
/// neither of which any test on a developer machine can establish.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:danlite_elm/constants/chassis_dtc_dictionary.dart';
import 'package:danlite_elm/constants/chassis_dtc_dictionary_hi.dart';
import 'package:danlite_elm/constants/chassis_modules.dart';
import 'package:danlite_elm/constants/obd_pids.dart';
import 'package:danlite_elm/models/vehicle_data.dart';
import 'package:danlite_elm/services/bluetooth_classic_service.dart';
import 'package:danlite_elm/services/dtc_service.dart';
import 'package:danlite_elm/services/obd_service.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // 1. REQUEST LAYER — the exact bytes sent to address the ABS module
  // ══════════════════════════════════════════════════════════════════════════
  group('ABS request construction', () {
    test('first candidate emits the full physical-addressing sequence', () {
      final target = ChassisModuleProfiles.genericCandidates.first;

      // These are the accessors ObdService.readChassisDtcs() itself calls, so
      // asserting on them asserts on the real wire traffic, not a copy of it.
      expect(target.headerCommand, 'ATSH7B0',
          reason: 'ATSH retargets the transmit header at the ABS module');
      expect(target.filterCommand, 'ATCRA7B8',
          reason: 'ATCRA filters reception to that module only');
      expect(target.flowControlCommands,
          <String>['ATFCSH7B0', 'ATFCSD300000', 'ATFCSM1'],
          reason: 'multi-frame replies need flow control aimed at the module');

      expect(
        target.wireSequence,
        <String>[
          'ATSH7B0',
          'ATCRA7B8',
          'ATFCSH7B0',
          'ATFCSD300000',
          'ATFCSM1',
          '1902FF', // UDS ReadDTCInformation / reportDTCByStatusMask, mask FF
          '03', // OBD-II Mode 03 retried against the addressed module
        ],
      );
    });

    test('second candidate is a genuinely different address, not a repeat', () {
      final second = ChassisModuleProfiles.genericCandidates[1];
      expect(second.headerCommand, 'ATSH760');
      expect(second.filterCommand, 'ATCRA768');
    });

    test('legislated OBD ECU addresses are never probed', () {
      // Probing 7E0-7E7 would get the engine ECU answering 19 02 and its
      // faults would be relabelled as ABS faults.
      for (final t in ChassisModuleProfiles.genericCandidates) {
        expect(t.requestHeader.startsWith('7E'), isFalse,
            reason: '${t.requestHeader} is a legislated OBD ECU address');
      }
    });

    test('the ABS request is UDS 19 02, not OBD-II Mode 03 alone', () {
      expect(ChassisModuleProfiles.udsReadDtcByStatusMask, '1902FF');
      expect(ChassisModuleProfiles.genericCandidates.first.requests.first,
          '1902FF');
    });

    test('engine-path AT commands are untouched by the chassis additions', () {
      expect(ObdPids.readDtcs, '03');
      expect(ObdPids.clearDtcs, '04');
      expect(ObdPids.headersOff, 'ATH0');
    });

    test('unknown manufacturers still get a probe order', () {
      expect(ChassisModuleProfiles.candidatesFor(null),
          ChassisModuleProfiles.genericCandidates);
      expect(ChassisModuleProfiles.candidatesFor('some_other_make'),
          ChassisModuleProfiles.genericCandidates);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 2. RESPONSE LAYER — decoding a simulated ABS module reply
  // ══════════════════════════════════════════════════════════════════════════
  group('UDS 59 02 response decode', () {
    // A simulated multi-frame reply from an ABS module at 0x7B8 reporting all
    // four documented Royal Enfield codes.
    //
    // Payload: 59 02 FF then four 4-byte records (3 DTC bytes + status).
    //   C1015 -> 0x50 0x15   C1019 -> 0x50 0x19
    //   C1021 -> 0x50 0x21   C1024 -> 0x50 0x24
    // Status 0x2F has bit 3 (confirmedDTC) set. Total payload 19 bytes = 0x13,
    // hence the ISO-TP first frame PCI "10 13".
    const multiFrameReply = '7B8 10 13 59 02 FF 50 15 00\r'
        '7B8 21 2F 50 19 00 2F 50 21\r'
        '7B8 22 00 2F 50 24 00 2F\r>';

    test('decodes all four documented codes from a multi-frame reply', () {
      final result = ObdParser.parseUdsDtcDetailed(multiFrameReply);

      expect(result.sawPositiveResponse, isTrue);
      expect(result.negativeResponseCode, isNull);
      expect(result.codes, <String>['C1015', 'C1019', 'C1021', 'C1024']);
    });

    test('preserves the UDS status and failure-type bytes', () {
      final result = ObdParser.parseUdsDtcDetailed(multiFrameReply);
      for (final record in result.records) {
        expect(record.failureTypeByte, 0x00);
        expect(record.statusByte, 0x2F);
        expect(record.isConfirmed, isTrue, reason: 'status bit 3 is set');
        expect(record.isCurrentlyFailing, isTrue, reason: 'status bit 0 is set');
      }
    });

    test('decodes a single-frame reply', () {
      final result =
          ObdParser.parseUdsDtcDetailed('7B8 07 59 02 FF 50 15 00 2F\r>');
      expect(result.sawPositiveResponse, isTrue);
      expect(result.codes, <String>['C1015']);
    });

    test('an unconfirmed fault is decoded as unconfirmed', () {
      // Status 0x01: testFailed set, confirmedDTC (bit 3) clear.
      final result =
          ObdParser.parseUdsDtcDetailed('7B8 07 59 02 FF 50 24 00 01\r>');
      expect(result.records.single.code, 'C1024');
      expect(result.records.single.isConfirmed, isFalse);
    });

    test('a module answering with zero faults is not mistaken for silence', () {
      // 59 02 FF and nothing more: the module replied, it has no stored faults.
      final result = ObdParser.parseUdsDtcDetailed('7B8 03 59 02 FF\r>');
      expect(result.sawPositiveResponse, isTrue,
          reason: 'this is what separates "ABS is clean" from "no reply"');
      expect(result.codes, isEmpty);
    });

    test('a negative response is reported, not silently read as clean', () {
      // 7F 19 11 = serviceNotSupported for ReadDTCInformation.
      final result = ObdParser.parseUdsDtcDetailed('7B8 03 7F 19 11\r>');
      expect(result.negativeResponseCode, 0x11);
      expect(result.sawPositiveResponse, isFalse);
      expect(result.codes, isEmpty);
    });

    test('adapter noise and empty input decode to nothing, never a fake code',
        () {
      for (final noise in <String?>[
        null,
        '',
        'NO DATA\r>',
        'UNABLE TO CONNECT\r>',
        '?\r>',
        'SEARCHING...\r>',
      ]) {
        final result = ObdParser.parseUdsDtcDetailed(noise);
        expect(result.codes, isEmpty, reason: 'input was: $noise');
        expect(result.sawPositiveResponse, isFalse);
      }
    });

    test('padding records are discarded', () {
      final result = ObdParser.parseUdsDtcDetailed(
          '7B8 10 0B 59 02 FF 50 15 00\r7B8 21 2F 00 00 00 00\r>');
      expect(result.codes, <String>['C1015']);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 3. THE ENGINE PATH IS UNCHANGED (regression)
  // ══════════════════════════════════════════════════════════════════════════
  group('engine DTC path regression', () {
    test('Mode 03 still parses powertrain codes exactly as before', () {
      // 43 01 01 22 = one code, P0122.
      final parsed = ObdParser.parseDetailed('7E8 06 43 01 01 22 00 00\r>');
      expect(parsed.powertrainCodes, contains('P0122'));
    });

    test('DtcCode defaults still describe an engine code', () {
      const engine = DtcCode(
        code: 'P0122',
        description: 'Throttle Position Sensor Circuit Low',
        possibleCause: 'Faulty TPS',
        severity: 'high',
        action: 'Check TPS wiring',
      );
      expect(engine.module, 'engine');
      expect(engine.isChassis, isFalse);
      expect(engine.component, '');
      expect(engine.query, '');
      expect(engine.remedy, '');
    });

    test('generic P-code localisation is unaffected', () {
      expect(DtcLocalizations.categoryHeader('P0122', 'en'), 'POWERTRAIN');
      expect(DtcLocalizations.categoryHeader('C1015', 'en'), 'CHASSIS');
      expect(DtcLocalizations.categoryHeader('C1015', 'hi'), 'चेसिस');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 4. PLATFORM KEY — make alone is no longer a safe dictionary key
  // ══════════════════════════════════════════════════════════════════════════
  group('platform resolution (manufacturer + model)', () {
    test('make resolution is still tolerant of free-text spelling', () {
      for (final spelling in <String>[
        'Royal Enfield',
        'royal enfield',
        'RoyalEnfield',
        '  ROYAL-ENFIELD  ',
      ]) {
        expect(ChassisManufacturers.resolveKey(spelling),
            ChassisManufacturers.royalEnfield,
            reason: 'failed on: "$spelling"');
      }
    });

    test('an unknown or blank make resolves to null, never to a guess', () {
      expect(ChassisManufacturers.resolveKey(null), isNull);
      expect(ChassisManufacturers.resolveKey(''), isNull);
      expect(ChassisManufacturers.resolveKey('   '), isNull);
      // TVS and Hero are the two makes the research explicitly found no usable
      // data for: TVS runs Continental ABS with no public DTC information of
      // any kind, and Hero's supplier is unconfirmed per model. Neither may be
      // quietly absorbed into the Bosch group on the strength of being an
      // Indian motorcycle brand — that would put an unverified hex value on a
      // braking fault card for hardware we know nothing about.
      expect(ChassisManufacturers.resolveKey('TVS'), isNull);
      expect(ChassisManufacturers.resolveKey('Hero'), isNull);
      expect(ChassisManufacturers.resolveKey('Hero MotoCorp'), isNull);
      expect(ChassisPlatforms.resolve('TVS', 'Apache RTR 160 4V'), isNull);
      expect(ChassisPlatforms.resolve('Hero', 'Xtreme 160R'), isNull);
    });

    test('Classic 350 spellings resolve to the Classic 350 platform', () {
      for (final model in <String>[
        'Classic 350',
        'classic350',
        'CLASSIC-350',
        '  Classic 350  ',
      ]) {
        expect(ChassisPlatforms.resolve('Royal Enfield', model),
            ChassisPlatforms.royalEnfieldClassic350,
            reason: 'failed on model: "$model"');
      }
    });

    test('Bullet EFI and Continental GT resolve to the Bullet EFI platform',
        () {
      for (final model in <String>[
        'Bullet EFI',
        'bulletefi',
        'Bullet Classic EFI',
        'Continental GT',
        'continental-gt',
      ]) {
        expect(ChassisPlatforms.resolve('Royal Enfield', model),
            ChassisPlatforms.royalEnfieldBulletEfi,
            reason: 'failed on model: "$model"');
      }
    });

    test('a known make with an unknown or blank model resolves to null', () {
      // This is the honest "we cannot identify this model" state. Guessing
      // between two tables that disagree is exactly what must not happen.
      for (final model in <String?>[null, '', '   ', 'Himalayan', 'Meteor']) {
        expect(ChassisPlatforms.resolve('Royal Enfield', model), isNull,
            reason: 'model "$model" should not resolve');
      }
    });

    test('a model name never reaches another make\'s table', () {
      // The property that matters is not that the result is null — it is that
      // a Royal Enfield model name typed under another make can never select
      // a Royal Enfield dictionary. Bajaj is now a supported (Bosch) make, so
      // "Classic 350" under it lands on Bajaj's own platform, which describes
      // nothing and says so; what it must never do is describe the fault from
      // Royal Enfield's Classic 350 table.
      final crossMake = ChassisPlatforms.resolve('Bajaj', 'Classic 350');
      expect(crossMake, isNot(ChassisPlatforms.royalEnfieldClassic350));
      expect(crossMake, isNot(ChassisPlatforms.royalEnfieldBulletEfi));
      expect(crossMake, ChassisPlatforms.bajajBoschAbs);
      expect(DtcLocalizations.chassisEntry(crossMake, 'C1015', 'en'), isNull,
          reason: 'a Classic 350 code must not be described under Bajaj');

      // No make at all still resolves to nothing, unchanged.
      expect(ChassisPlatforms.resolve(null, 'Classic 350'), isNull);
    });

    test('Royal Enfield resolution is byte-for-byte what it always was', () {
      // The make-level fallback added for Honda and the Bosch makes must not
      // reach Royal Enfield: its two platforms disagree about what the same
      // number means, so an unidentified model has to stay unidentified rather
      // than defaulting to either table.
      expect(
          ChassisPlatforms.hasModelIndependentFallback(
              ChassisManufacturers.royalEnfield),
          isFalse);
      for (final model in <String>['Himalayan', 'Meteor', 'Hunter 350', 'x']) {
        expect(ChassisPlatforms.resolve('Royal Enfield', model), isNull,
            reason: '"$model" must not fall back to a Royal Enfield table');
      }
    });

    test('"Bullet Classic EFI" never leaks into the Classic 350 table', () {
      // It contains the substring "classic". Exact-match-only aliasing is what
      // stops that becoming a wrong-platform braking description.
      expect(ChassisPlatforms.resolve('Royal Enfield', 'Bullet Classic EFI'),
          ChassisPlatforms.royalEnfieldBulletEfi);
    });

    test('both platforms belong to the same manufacturer', () {
      final platforms =
          ChassisPlatforms.forManufacturer(ChassisManufacturers.royalEnfield);
      expect(platforms.map((p) => p.key).toSet(), <String>{
        ChassisPlatforms.royalEnfieldClassic350,
        ChassisPlatforms.royalEnfieldBulletEfi,
      });
      expect(ChassisManufacturers.supported,
          contains(ChassisManufacturers.royalEnfield));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 5. DATASET 1 — Royal Enfield Classic 350 (C-code format)
  // ══════════════════════════════════════════════════════════════════════════
  group('Classic 350 dictionary', () {
    const c350 = ChassisPlatforms.royalEnfieldClassic350;

    test('the four originally shipped codes survived the key migration', () {
      // Byte-for-byte identical to what shipped before the restructure.
      const original = <String, List<String>>{
        'C1015': <String>[
          'RFP/RFP_HW',
          'ABS Pump/Motor Failure',
          'Failure in the ABS Pump Motor',
          'Change ABS unit',
        ],
        'C1019': <String>[
          'VR',
          'ABS ECU Relay Fault',
          'Failure in the ABS valve relay',
          'Change ABS unit',
        ],
        'C1021': <String>[
          'ECU',
          'ABS ECU Internal fault',
          'ABS Microcontroller Failure',
          'Change ABS unit',
        ],
        'C1024': <String>[
          'WSS_GENERIC',
          '(GENERIC) ABS Wheel Speed Difference too high',
          'Signal quality from the front/Rear WSS is not good',
          // Completed from the next manual page (S10, fault-code safety
          // release); the original transcription stopped at "Airgap".
          'Check the front toner wheel/ Airgap consistency/WSS bracket',
        ],
      };

      original.forEach((code, fields) {
        final r = DtcLocalizations.chassisEntry(c350, code, 'en');
        expect(r, isNotNull, reason: '$code lost in migration');
        expect(r!.component, fields[0]);
        expect(r.description, fields[1]);
        expect(r.query, fields[2]);
        expect(r.remedy, fields[3]);
        expect(r.severity, 'critical');
      });
    });

    test('the 15 newly added codes decode to their exact English text', () {
      const added = <String, List<String>>{
        'C1031': <String>[
          'WSS_ohmic',
          'ABS Wheel Speed Circuit Open or Shorted (Rear)',
          'Failure in the Rear WSS (electric)',
          'Change Rear WSS or Check wiring from WSS to ABS',
        ],
        'C1032': <String>[
          'WSS_plausibility',
          'ABS Wheel Speed Intermittent (Rear)',
          'Signal quality from the Rear WSS is not good',
          'Check the Rear toner wheel/Airgap consistency/WSS bracket',
        ],
        'C1033': <String>[
          'WSS_ohmic',
          'ABS Wheel Speed Circuit Open or Shorted (Front)',
          'Failure in the Front WSS (electric)',
          'Change Front WSS or Check wiring from WSS to ABS',
        ],
        'C1034': <String>[
          'WSS_plausibility',
          'ABS Wheel Speed Intermittent (Front)',
          'Signal quality from the front WSS is not good',
          'Check the front toner wheel/Airgap consistency/WSS bracket',
        ],
        'C1048': <String>[
          'Valves EV',
          '(AV) ABS Release Solenoid Circuit Open or high Resistance (Rear)',
          'Failure in the rear Outlet Valve',
          'Change ABS unit',
        ],
        'C1049': <String>[
          'Valves EV',
          '(AV) ABS Release Solenoid Circuit Open or high Resistance (Front)',
          'Failure in the front Outlet Valve',
          'Change ABS unit',
        ],
        'C1052': <String>[
          'Valves EV',
          '(EV) ABS Apply Solenoid Circuit Open or high Resistance (Rear)',
          'Failure in the rear Inlet Valve',
          'Change ABS unit',
        ],
        'C1054': <String>[
          'Valves EV',
          '(EV) ABS Apply Solenoid Circuit Open or high Resistance (Front)',
          'Failure in the front Inlet Valve',
          'Change ABS unit',
        ],
        'C1058': <String>[
          'UZ',
          'ABS Voltage Low',
          'Battery Voltage Too Low',
          'Check the Battery',
        ],
        'C1059': <String>[
          'UZ',
          'ABS Voltage High',
          'Battery Voltage Too high',
          'Check the voltage regulator/Battery',
        ],
        'C1334': <String>['ABS ECU', 'Variant not configured in EEPROM', '', ''],
        'C1335': <String>['ABS ECU', 'Variant Information Error', '', ''],
        'U2921': <String>[
          'CAN_GENERIC',
          'CAN Generic monitoring',
          'CAN controller failure. Diagnosis is not possible with tester in '
              'this case.',
          'Change ABS unit',
        ],
        'U2922': <String>[
          'CAN_BUSOFF',
          'High Speed CAN Communications Bus Fault',
          'CAN BusOff failure',
          'Check for CAN lines connection',
        ],
        'U2926': <String>[
          'CAN_COMMUNIC',
          'Cluster DLC / Timeout Failure',
          '',
          '',
        ],
      };

      expect(added.length, 15, reason: 'all 15 new rows must be covered');
      added.forEach((code, fields) {
        final r = DtcLocalizations.chassisEntry(c350, code, 'en');
        expect(r, isNotNull, reason: '$code missing from dictionary');
        expect(r!.component, fields[0], reason: '$code component');
        expect(r.description, fields[1], reason: '$code description');
        expect(r.query, fields[2], reason: '$code query');
        expect(r.remedy, fields[3], reason: '$code remedy');
      });
    });

    test('"N/A" source rows are stored empty, never as the literal string', () {
      for (final code in <String>['C1334', 'C1335', 'U2926']) {
        final r = DtcLocalizations.chassisEntry(c350, code, 'en')!;
        expect(r.query, isEmpty, reason: '$code query should be empty');
        expect(r.remedy, isEmpty, reason: '$code remedy should be empty');
        expect(r.description, isNotEmpty);
      }
    });

    test('the U-codes are decodable from real wire bytes', () {
      // U2922 packs to 0xE9 0x22 under the same standard bit-packing.
      final decoded =
          ObdParser.parseUdsDtcDetailed('7B8 07 59 02 FF E9 22 00 2F\r>');
      expect(decoded.codes, <String>['U2922']);
      expect(DtcLocalizations.chassisEntry(c350, 'U2922', 'en')!.description,
          'High Speed CAN Communications Bus Fault');
    });

    test('every Classic 350 code has real Hindi, not English fallback', () {
      final devanagari = RegExp(r'[ऀ-ॿ]');
      for (final code in ChassisDtcDatabase.byPlatform[c350]!.keys) {
        final hi = DtcLocalizations.chassisEntry(c350, code, 'hi')!;
        final en = DtcLocalizations.chassisEntry(c350, code, 'en')!;

        expect(hi.description, isNot(en.description),
            reason: '$code description was not translated');
        expect(devanagari.hasMatch(hi.description), isTrue,
            reason: '$code description has no Devanagari');

        if (en.remedy.isNotEmpty) {
          expect(hi.remedy, isNot(en.remedy),
              reason: '$code remedy was not translated');
        }
        if (en.query.isNotEmpty) {
          expect(hi.query, isNot(en.query),
              reason: '$code query was not translated');
        }
        // Component is a manufacturer identifier and is never translated.
        expect(hi.component, en.component);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 6. DATASET 2 — Bullet EFI / Continental GT (hex-notation format)
  // ══════════════════════════════════════════════════════════════════════════
  group('Bullet EFI dictionary', () {
    const bullet = ChassisPlatforms.royalEnfieldBulletEfi;

    test('all 19 rows are present with their exact English descriptions', () {
      const expected = <String, String>{
        '5013H': 'Rear Inlet Valve malfunction (EV)',
        '5014H': 'Rear Outlet Valve malfunction (AV)',
        '5017H': 'Front Inlet Valve malfunction (EV)',
        '5018H': 'Front Outlet Valve malfunction (AV)',
        '5019H': 'Valve Relay malfunction (Failsafe relay)',
        '5025H': 'Deviation between Wheel speeds (WSS_GENERIC)',
        '5035H': 'Pump Motor Malfunction',
        '5042H': 'Front wheel speed sensor malfunction - Plausibility',
        '5043H':
            'Front wheel speed sensor Disconnection/ground Short/Uz Short',
        '5044H': 'Rear wheel speed sensor malfunction - Plausibility',
        '5045H': 'Rear wheel speed sensor Disconnection/ground Short/Uz Short',
        '5052H': 'Power Supply Malfunction (Low Voltage)',
        '5053H': 'Power Supply Malfunction (High Voltage)',
        '5055H': 'ECU malfunction',
        '5122H': 'Varcode EEPROM ReadError',
        '5223H': 'VarCode EEPROM Out Of Range',
        '5331H': 'Front Wheel Pressure sensor ohmic fault',
        '5332H': 'Front wheel pressure sensor offset/Test Pulse/POT fault',
        '5333H': 'External Supply for Pressure sensor failure',
      };

      expect(expected.length, 19);
      expect(ChassisDtcDatabase.byPlatform[bullet]!.keys.toSet(),
          expected.keys.toSet());

      expected.forEach((code, description) {
        final r = DtcLocalizations.chassisEntry(bullet, code, 'en');
        expect(r, isNotNull, reason: '$code missing');
        expect(r!.description, description);
      });
    });

    test('every entry carries the single safe generic remedy', () {
      // The source has no remedy column; inventing 19 specific technical fixes
      // would be fabrication, so one honest instruction is used throughout.
      for (final code in ChassisDtcDatabase.byPlatform[bullet]!.keys) {
        final r = DtcLocalizations.chassisEntry(bullet, code, 'en')!;
        expect(r.remedy, ChassisDtcDatabase.bulletEfiGenericRemedy);
        expect(r.remedy,
            'Have this inspected by an authorised Royal Enfield service center');
        // No component or query column exists in this manual.
        expect(r.component, isEmpty);
        expect(r.query, isEmpty);
      }
    });

    test('every entry has real Hindi for description and remedy', () {
      final devanagari = RegExp(r'[ऀ-ॿ]');
      for (final code in ChassisDtcDatabase.byPlatform[bullet]!.keys) {
        final hi = DtcLocalizations.chassisEntry(bullet, code, 'hi')!;
        final en = DtcLocalizations.chassisEntry(bullet, code, 'en')!;
        expect(hi.description, isNot(en.description), reason: '$code');
        expect(devanagari.hasMatch(hi.description), isTrue, reason: '$code');
        expect(hi.remedy, isNot(en.remedy), reason: '$code remedy');
        expect(devanagari.hasMatch(hi.remedy), isTrue, reason: '$code remedy');
      }
    });

    // ── The hex-notation to SAE conversion ────────────────────────────────
    test('deriveSaeCode reads the manual notation as the byte pair it is', () {
      const expected = <String, String>{
        '5013H': 'C1013',
        '5019H': 'C1019',
        '5035H': 'C1035',
        '5043H': 'C1043',
        '5052H': 'C1052',
        '5122H': 'C1122',
        '5223H': 'C1223',
        '5331H': 'C1331',
        '5333H': 'C1333',
      };
      expected.forEach((raw, sae) {
        expect(ChassisDtcDatabase.deriveSaeCode(raw), sae, reason: raw);
      });
    });

    test('deriveSaeCode ignores anything not in hex-suffix notation', () {
      for (final notHex in <String>['C1015', 'U2922', '5043', 'ZZZZH', '']) {
        expect(ChassisDtcDatabase.deriveSaeCode(notHex), isNull,
            reason: notHex);
      }
    });

    test('a scanned SAE code resolves onto the manual hex entry', () {
      // What the wire actually produces for 5043H is "C1043".
      final decoded =
          ObdParser.parseUdsDtcDetailed('7B8 07 59 02 FF 50 43 00 2F\r>');
      expect(decoded.codes, <String>['C1043']);

      final r = DtcLocalizations.chassisEntry(bullet, 'C1043', 'en')!;
      expect(r.description,
          'Front wheel speed sensor Disconnection/ground Short/Uz Short');
      expect(r.remedy, ChassisDtcDatabase.bulletEfiGenericRemedy);
      expect(ChassisDtcDatabase.canonicalCode(bullet, 'C1043'), '5043H');
    });

    test('the two manuals independently agree on the valve-relay fault', () {
      // Corroboration for reading "H" as hexadecimal: the Bullet EFI manual's
      // 5019H converts to C1019, and the separately-sourced Classic 350 manual
      // calls C1019 the ABS valve relay fault. Same value, same fault, two
      // independent documents.
      expect(ChassisDtcDatabase.deriveSaeCode('5019H'), 'C1019');
      expect(DtcLocalizations.chassisEntry(bullet, '5019H', 'en')!.description,
          'Valve Relay malfunction (Failsafe relay)');
      expect(
          DtcLocalizations.chassisEntry(
                  ChassisPlatforms.royalEnfieldClassic350, 'C1019', 'en')!
              .query,
          'Failure in the ABS valve relay');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 7. CROSS-PLATFORM SAFETY — the same number must not cross datasets
  // ══════════════════════════════════════════════════════════════════════════
  group('platform isolation', () {
    const c350 = ChassisPlatforms.royalEnfieldClassic350;
    const bullet = ChassisPlatforms.royalEnfieldBulletEfi;

    test('C1052 means genuinely different things on the two platforms', () {
      // The colliding case. On the Classic 350 it is a rear inlet valve fault;
      // on the Bullet EFI platform the same value is a low-supply-voltage
      // fault. Resolving it against the wrong table would mis-describe a
      // braking fault, which is the whole reason the key includes the model.
      final onClassic = DtcLocalizations.chassisEntry(c350, 'C1052', 'en')!;
      final onBullet = DtcLocalizations.chassisEntry(bullet, 'C1052', 'en')!;

      expect(onClassic.description,
          '(EV) ABS Apply Solenoid Circuit Open or high Resistance (Rear)');
      expect(onClassic.query, 'Failure in the rear Inlet Valve');

      expect(onBullet.description, 'Power Supply Malfunction (Low Voltage)');
      expect(onBullet.description, isNot(onClassic.description));
    });

    test(
        'a Classic 350 profile and a Bullet EFI profile decode C1052 '
        'differently end to end', () {
      // Identical wire bytes, two vehicle profiles, two correct answers.
      final decoded =
          ObdParser.parseUdsDtcDetailed('7B8 07 59 02 FF 50 52 00 2F\r>');
      expect(decoded.codes, <String>['C1052']);
      final code = decoded.records.single.code;

      final classicKey =
          ChassisPlatforms.resolve('Royal Enfield', 'Classic 350');
      final bulletKey = ChassisPlatforms.resolve('Royal Enfield', 'Bullet EFI');
      expect(classicKey, isNot(bulletKey));

      expect(ChassisDtcDatabase.lookup(classicKey, code)!.query,
          'Failure in the rear Inlet Valve');
      expect(ChassisDtcDatabase.lookup(bulletKey, code)!.description,
          'Power Supply Malfunction (Low Voltage)');
    });

    test('Classic 350 codes do not resolve on the Bullet EFI platform', () {
      // C1334/C1335/U292x exist only in the Classic 350 table.
      for (final code in <String>[
        'C1334',
        'C1335',
        'U2921',
        'U2922',
        'U2926'
      ]) {
        expect(ChassisDtcDatabase.lookup(bullet, code), isNull, reason: code);
      }
    });

    test('Bullet EFI-only codes do not resolve on the Classic 350 platform',
        () {
      // 5122H -> C1122 and 5223H -> C1223 are not in the Classic 350 table.
      for (final code in <String>['5122H', 'C1122', '5223H', 'C1223']) {
        expect(ChassisDtcDatabase.lookup(c350, code), isNull, reason: code);
      }
    });

    test('the hex alias never leaks across platforms', () {
      // The Classic 350 table has no hex-notation keys at all, so it must
      // build no alias index and match no H-code.
      expect(ChassisDtcDatabase.canonicalCode(c350, '5043H'), isNull);
      expect(ChassisDtcDatabase.canonicalCode(bullet, '5043H'), '5043H');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 8. NO FABRICATION — the safety property that matters most here
  // ══════════════════════════════════════════════════════════════════════════
  group('chassis dictionary never invents braking-system data', () {
    const c350 = ChassisPlatforms.royalEnfieldClassic350;
    const bullet = ChassisPlatforms.royalEnfieldBulletEfi;

    test('exactly the documented codes exist, and no others', () {
      expect(ChassisDtcDatabase.byPlatform[c350]!.keys.toSet(), <String>{
        'C1015', 'C1019', 'C1021', 'C1024', 'C1031', 'C1032', 'C1033',
        'C1034', 'C1048', 'C1049', 'C1052', 'C1054', 'C1058', 'C1059',
        'C1334', 'C1335', 'U2921', 'U2922', 'U2926',
      });
      expect(ChassisDtcDatabase.byPlatform[c350]!.length, 19);
      expect(ChassisDtcDatabase.byPlatform[bullet]!.length, 19);
    });

    test('an undocumented code returns null rather than a plausible guess', () {
      for (final code in <String>['C1016', 'C1020', 'C1099', 'C0035']) {
        expect(DtcLocalizations.chassisEntry(c350, code, 'en'), isNull,
            reason: '$code is not in the service manual page we have');
      }
      for (final code in <String>['5000H', 'C1000', 'C1099']) {
        expect(DtcLocalizations.chassisEntry(bullet, code, 'en'), isNull,
            reason: '$code is not in the Bullet EFI manual page');
      }
    });

    test('a known code under an unresolved platform returns null', () {
      // Make known, model not: describing the fault from either table would be
      // a guess between two tables that disagree.
      expect(DtcLocalizations.chassisEntry(null, 'C1015', 'en'), isNull);
      expect(DtcLocalizations.chassisEntry('some_other_platform', 'C1015', 'en'),
          isNull);
      final unresolved = ChassisPlatforms.resolve('Royal Enfield', 'Himalayan');
      expect(unresolved, isNull);
      expect(DtcLocalizations.chassisEntry(unresolved, 'C1015', 'en'), isNull);
    });

    test(
        'C0035 in the generic engine table is not reused for a platform '
        'lookup', () {
      expect(ChassisDtcDatabase.lookup(c350, 'C0035'), isNull);
      expect(ChassisDtcDatabase.lookup(bullet, 'C0035'), isNull);
    });

    test('hasDictionary distinguishes "unknown platform" from "unknown code"',
        () {
      expect(ChassisDtcDatabase.hasDictionary(c350), isTrue);
      expect(ChassisDtcDatabase.hasDictionary(bullet), isTrue);
      expect(ChassisDtcDatabase.hasDictionary('royal_enfield'), isFalse,
          reason: 'bare manufacturer is no longer a dictionary key');
      expect(ChassisDtcDatabase.hasDictionary(null), isFalse);
    });

    test('adding a code stays a data-only change: the shape is uniform', () {
      final saeCode = RegExp(r'^[PCBU][0-3][0-9A-F]{3}$');
      final hexCode = RegExp(r'^[0-9A-F]{4}H$');
      // Honda's table is keyed by blink pattern — long flashes, dash, short
      // flashes — because that is literally what the rider counts. It is a
      // third real notation, not a malformed code.
      final blinkCode = RegExp(r'^[0-9]-[0-9]$');

      ChassisDtcDatabase.byPlatform.forEach((platform, table) {
        expect(table, isNotEmpty, reason: '$platform is empty');
        table.forEach((code, entry) {
          expect(
              saeCode.hasMatch(code) ||
                  hexCode.hasMatch(code) ||
                  blinkCode.hasMatch(code),
              isTrue,
              reason: '$platform/$code is not a recognised code notation');
          // Description is the one field every real source row always has.
          expect(entry.description, isNotEmpty,
              reason: '$platform/$code description');
          expect(entry.severity, isNotEmpty, reason: '$platform/$code severity');
          // "N/A" must have been stored as genuinely empty.
          for (final field in <String>[
            entry.component,
            entry.description,
            entry.query,
            entry.remedy,
          ]) {
            expect(field.trim().toUpperCase(), isNot('N/A'),
                reason: '$platform/$code holds a literal N/A placeholder');
          }
        });
      });
    });

    test('English and Hindi tables cover exactly the same codes, per platform',
        () {
      expect(ChassisDtcDictionaryHi.byPlatform.keys.toSet(),
          ChassisDtcDatabase.byPlatform.keys.toSet());
      for (final platform in ChassisDtcDatabase.byPlatform.keys) {
        expect(
          ChassisDtcDictionaryHi.byPlatform[platform]!.keys.toSet(),
          ChassisDtcDatabase.byPlatform[platform]!.keys.toSet(),
          reason: '$platform EN/HI key mismatch',
        );
      }
    });

    test('a language with no chassis translations falls back to English', () {
      final ta = DtcLocalizations.chassisEntry(c350, 'C1031', 'ta')!;
      final en = DtcLocalizations.chassisEntry(c350, 'C1031', 'en')!;
      expect(ta.description, en.description);
      expect(ta.remedy, en.remedy);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 9. END TO END — simulated reply through to a rendered fault card's fields
  // ══════════════════════════════════════════════════════════════════════════
  group('simulated ABS reply resolves to displayable fault cards', () {
    /// Mirrors exactly what ObdService._buildChassisDtc assembles.
    DtcCode buildCard(UdsDtcRecord record, String? platformKey) {
      final master = ChassisDtcDatabase.lookup(platformKey, record.code);
      return DtcCode(
        code: record.code,
        description: master?.description ?? '',
        possibleCause: master?.query ?? '',
        severity: master?.severity ?? 'unknown',
        action: master?.remedy ?? '',
        module: 'chassis',
        component: master?.component ?? '',
        query: master?.query ?? '',
        remedy: master?.remedy ?? '',
        failureTypeByte: record.failureTypeByte,
        isConfirmed: record.isConfirmed,
      );
    }

    test('DATASET 1: a Classic 350 C1058 reply produces the manual fields', () {
      final decoded =
          ObdParser.parseUdsDtcDetailed('7B8 07 59 02 FF 50 58 00 2F\r>');
      final record = decoded.records.single;
      expect(record.code, 'C1058');

      final key = ChassisPlatforms.resolve('Royal Enfield', 'Classic 350');
      final card = buildCard(record, key);

      expect(card.isChassis, isTrue);
      expect(card.component, 'UZ');
      expect(card.description, 'ABS Voltage Low');
      expect(card.query, 'Battery Voltage Too Low');
      expect(card.remedy, 'Check the Battery');
      expect(card.severity, 'critical');
      expect(card.isConfirmed, isTrue);
    });

    test(
        'DATASET 1: a multi-code reply decodes new and original codes '
        'together', () {
      // C1031 (50 31) and C1334 (53 34) alongside the original C1015 (50 15).
      final decoded = ObdParser.parseUdsDtcDetailed('7B8 10 0F 59 02 FF 50 15 00\r'
          '7B8 21 2F 50 31 00 2F 53\r'
          '7B8 22 34 00 2F\r>');
      expect(decoded.codes, <String>['C1015', 'C1031', 'C1334']);

      final key = ChassisPlatforms.resolve('Royal Enfield', 'Classic 350');
      final cards =
          decoded.records.map((r) => buildCard(r, key)).toList(growable: false);
      expect(cards[0].description, 'ABS Pump/Motor Failure');
      expect(
          cards[1].description, 'ABS Wheel Speed Circuit Open or Shorted (Rear)');
      expect(cards[1].remedy, 'Change Rear WSS or Check wiring from WSS to ABS');
      expect(cards[2].description, 'Variant not configured in EEPROM');
      expect(cards[2].query, isEmpty, reason: 'source printed N/A');
      expect(cards[2].remedy, isEmpty, reason: 'source printed N/A');
    });

    test(
        'DATASET 2: a Bullet EFI 5035H reply produces the description and '
        'the generic remedy', () {
      // 5035H is 0x50 0x35 on the wire, which decodes to C1035.
      final decoded =
          ObdParser.parseUdsDtcDetailed('7B8 07 59 02 FF 50 35 00 2F\r>');
      final record = decoded.records.single;
      expect(record.code, 'C1035');

      final key = ChassisPlatforms.resolve('Royal Enfield', 'Continental GT');
      expect(key, ChassisPlatforms.royalEnfieldBulletEfi);

      final card = buildCard(record, key);
      expect(card.isChassis, isTrue);
      expect(card.description, 'Pump Motor Malfunction');
      expect(card.remedy,
          'Have this inspected by an authorised Royal Enfield service center');
      expect(card.component, isEmpty, reason: 'no component column in source');
      expect(card.query, isEmpty, reason: 'no query column in source');
    });

    test('DATASET 2: the same reply renders in Hindi', () {
      final decoded =
          ObdParser.parseUdsDtcDetailed('7B8 07 59 02 FF 50 35 00 2F\r>');
      final key = ChassisPlatforms.resolve('Royal Enfield', 'Bullet EFI');
      final hi = DtcLocalizations.chassisEntry(
          key, decoded.records.single.code, 'hi')!;
      final devanagari = RegExp(r'[ऀ-ॿ]');
      expect(devanagari.hasMatch(hi.description), isTrue);
      expect(devanagari.hasMatch(hi.remedy), isTrue);
      expect(hi.remedy, ChassisDtcDictionaryHi.bulletEfiGenericRemedyHi);
    });

    test('an unidentified model still shows the code, without invented text',
        () {
      final decoded =
          ObdParser.parseUdsDtcDetailed('7B8 07 59 02 FF 50 35 00 2F\r>');
      final record = decoded.records.single;
      final key = ChassisPlatforms.resolve('Royal Enfield', 'Himalayan');

      expect(key, isNull);
      final card = buildCard(record, key);
      expect(card.code, 'C1035', reason: 'the code itself is still read');
      expect(card.description, isEmpty,
          reason: 'but nothing is claimed about its meaning');
      expect(card.remedy, isEmpty);
      expect(card.severity, 'unknown');
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // 8. PROBE STATE across an adapter recovery
  // ════════════════════════════════════════════════════════════════════════
  group('a mid-probe adapter recovery does not un-address the module', () {
    test('addressing is re-applied before the next request goes out', () async {
      final elm = FakeChassisElm();
      final obd = ObdService(elm);
      expect(
          await obd.connectBluetooth(const BtDevice(
              name: 'OBDII', address: '00:11:22:33:44:55', bonded: true)),
          isTrue);

      await obd.readChassisDtcs(
          vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');

      final wire = elm.wire;
      final firstUds = wire.indexOf(ChassisModuleProfiles.udsReadDtcByStatusMask);
      expect(firstUds, greaterThanOrEqualTo(0),
          reason: 'the UDS request must have been attempted');

      final modeThree = wire.indexOf(ChassisModuleProfiles.obdModeThree, firstUds);
      expect(modeThree, greaterThan(firstUds),
          reason: 'the Mode 03 fallback is still tried after the UDS timeout');

      // The recovery between those two requests re-runs the init sequence,
      // which restores the adapter's live baseline and drops ATSH. Unless the
      // addressing is put back, this Mode 03 goes out on the functional
      // broadcast where the engine ECU answers it.
      final reAddressed =
          wire.lastIndexOf(ObdPids.setHeader('7B0'), modeThree);
      expect(reAddressed, greaterThan(firstUds),
          reason: 'ATSH7B0 must be re-sent after the recovery and before the '
              'Mode 03 fallback, or that request is no longer addressed at the '
              'ABS module at all');

      // The decisive assertion: no engine code may surface as a chassis fault.
      expect(obd.chassisDtcCodes, isEmpty,
          reason: 'no ABS module answered, so nothing may be reported');
      expect(obd.chassisScanOutcome, ChassisScanOutcome.noModuleResponse,
          reason: 'the honest outcome is "nothing answered", not a fake read');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}

// ══════════════════════════════════════════════════════════════════════════
// 8. PROBE STATE — an adapter recovery must not silently un-address the module
// ══════════════════════════════════════════════════════════════════════════
/// A simulated ELM327 on a bike whose ABS module is at neither probed address.
///
/// It models the one thing that makes the recovery path dangerous: **the
/// adapter's addressing state**. `03` is answered only when no ATSH is set,
/// because that is the functional broadcast the engine ECU listens on. Ask it
/// while addressed at a chassis ID and nothing answers, exactly as on a bike
/// with no module there.
///
/// The first recovery is forced down the ATZ path (a bare CR is ignored twice),
/// because only that path re-runs the init sequence — which restores the live
/// baseline and wipes the ATSH/ATCRA the probe had just set.
class FakeChassisElm extends BluetoothClassicService {
  final _ctrl = StreamController<String>.broadcast();
  final List<String> wire = <String>[];
  bool _connected = false;

  /// The adapter's current transmit header — null means the functional
  /// broadcast, which is where the engine ECU answers.
  String? _header;

  /// A bare CR is ignored this many more times, to wedge the first recovery
  /// hard enough that it has to reset the adapter.
  int _crIgnoresLeft = 2;

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
      if (_crIgnoresLeft > 0) {
        _crIgnoresLeft--;
        return true; // wedged: no prompt comes back
      }
      scheduleMicrotask(() => _ctrl.add('\r>'));
      return true;
    }

    // Addressing state, tracked exactly as a real adapter holds it.
    if (c.startsWith('ATSH')) {
      _header = c.substring(4);
    } else if (c == 'ATZ' || c == 'ATSP0' || c == 'ATAR') {
      _header = null; // reset / auto — back to the functional broadcast
    }

    // The ABS module is not at any probed address, so a physically-addressed
    // request is met with silence.
    if (_header != null && !c.startsWith('AT')) return true;

    late final String reply;
    if (c == 'ATZ') {
      reply = '\r\rELM327 v1.5\r\r>';
    } else if (c == 'ATDPN') {
      reply = '\r6\r\r>';
    } else if (c.startsWith('AT')) {
      reply = '\rOK\r\r>';
    } else if (c == '0100') {
      reply = '\r41 00 BE 3E B8 11\r\r>';
    } else if (c == '03') {
      // The ENGINE ECU's stored code, on the functional broadcast. If this
      // ever lands in the chassis list, an engine fault has been relabelled a
      // braking fault — the exact outcome ChassisModuleProfiles excludes the
      // 0x7E0-0x7E7 addresses to prevent.
      reply = '\r7E8 06 43 01 01 72\r\r>';
    } else {
      reply = '\r>';
    }
    scheduleMicrotask(() => _ctrl.add(reply));
    return true;
  }

  Future<void> close() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }
}
