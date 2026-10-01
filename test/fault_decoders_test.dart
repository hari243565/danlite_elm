/// Phase 1A — A2: status byte, failure type, and the typed reply decoders.
///
/// Every vector here is written from the ISO 14229-1 / SAE J1979 byte layouts,
/// not recorded from a real bike.
library;

import 'package:danlite_elm/services/fault_decoders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // UDS status byte
  // ══════════════════════════════════════════════════════════════════════════
  group('A2 UDS status byte: raw bits', () {
    test('every bit is read from its own position', () {
      for (var bit = 0; bit < 8; bit++) {
        final s = UdsStatusByte(1 << bit);
        final bits = [
          s.testFailed,
          s.testFailedThisOperationCycle,
          s.pendingDtc,
          s.confirmedDtc,
          s.testNotCompletedSinceLastClear,
          s.testFailedSinceLastClear,
          s.testNotCompletedThisOperationCycle,
          s.warningIndicatorRequested,
        ];
        for (var i = 0; i < 8; i++) {
          expect(bits[i], i == bit, reason: 'byte 0x${(1 << bit).toRadixString(16)} bit $i');
        }
      }
    });
  });

  group('A2 UDS status byte: the brief\'s test vectors', () {
    // Derived labels: Active = bit 0; Pending = bit 2 and not bit 3;
    // Stored = bit 3; History = bit 3 and not bit 0; Lamp = bit 7.
    void expectLabels(int byte,
        {required bool active,
        required bool pending,
        required bool stored,
        required bool history,
        required bool lamp}) {
      final s = UdsStatusByte(byte);
      final tag = '0x${byte.toRadixString(16).padLeft(2, '0')}';
      expect(s.isActive, active, reason: '$tag active');
      expect(s.isPending, pending, reason: '$tag pending');
      expect(s.isStored, stored, reason: '$tag stored');
      expect(s.isHistory, history, reason: '$tag history');
      expect(s.isLampRequested, lamp, reason: '$tag lamp');
    }

    test('0x00 — none', () {
      expectLabels(0x00,
          active: false, pending: false, stored: false, history: false, lamp: false);
    });
    test('0x04 — pending only', () {
      expectLabels(0x04,
          active: false, pending: true, stored: false, history: false, lamp: false);
    });
    test('0x08 — confirmed, history', () {
      expectLabels(0x08,
          active: false, pending: false, stored: true, history: true, lamp: false);
    });
    test('0x09 — confirmed and active', () {
      expectLabels(0x09,
          active: true, pending: false, stored: true, history: false, lamp: false);
    });
    test('0x2F — active, this cycle, pending, confirmed, failed since clear', () {
      final s = UdsStatusByte(0x2F);
      // The raw bits the brief lists…
      expect(s.testFailed, isTrue);
      expect(s.testFailedThisOperationCycle, isTrue);
      expect(s.pendingDtc, isTrue);
      expect(s.confirmedDtc, isTrue);
      expect(s.testFailedSinceLastClear, isTrue);
      expect(s.testNotCompletedSinceLastClear, isFalse);
      expect(s.testNotCompletedThisOperationCycle, isFalse);
      expect(s.warningIndicatorRequested, isFalse);
      // …and the derived labels: the Pending LABEL is bit 2 AND NOT bit 3, so a
      // confirmed code is shown as Stored, not as Pending, even though its
      // pendingDTC bit is set.
      expectLabels(0x2F,
          active: true, pending: false, stored: true, history: false, lamp: false);
    });
    test('0x80 — lamp requested only', () {
      expectLabels(0x80,
          active: false, pending: false, stored: false, history: false, lamp: true);
    });
    test('0x89 — active, confirmed, lamp', () {
      expectLabels(0x89,
          active: true, pending: false, stored: true, history: false, lamp: true);
    });

    test('values outside a byte never throw and use only the low 8 bits', () {
      expect(UdsStatusByte(0x109).isActive, isTrue);
      expect(UdsStatusByte(-1).raw, 0xFF);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Failure type byte
  // ══════════════════════════════════════════════════════════════════════════
  group('A2 failure type table', () {
    const expected = <int, List<String>>{
      0x00: ['No sub-type', 'कोई उप-प्रकार नहीं'],
      0x02: ['General signal failure', 'सिग्नल में सामान्य खराबी'],
      0x04: ['System internal failure', 'सिस्टम की आंतरिक खराबी'],
      0x05: ['Programming failure', 'प्रोग्रामिंग त्रुटि'],
      0x07: ['Mechanical failure', 'यांत्रिक (मैकेनिकल) खराबी'],
      0x09: ['Component failure', 'कंपोनेंट की खराबी'],
      0x11: ['Circuit short to ground', 'सर्किट ग्राउंड से शॉर्ट'],
      0x12: ['Circuit short to battery supply', 'सर्किट बैटरी सप्लाई से शॉर्ट'],
      0x13: ['Circuit open', 'सर्किट खुला (ओपन)'],
      0x16: ['Circuit voltage below threshold', 'सर्किट वोल्टेज सीमा से कम'],
      0x17: ['Circuit voltage above threshold', 'सर्किट वोल्टेज सीमा से अधिक'],
      0x18: ['Circuit current below threshold', 'सर्किट करंट सीमा से कम'],
      0x19: ['Circuit current above threshold', 'सर्किट करंट सीमा से अधिक'],
      0x1A: ['Circuit resistance above threshold', 'सर्किट प्रतिरोध सीमा से अधिक'],
      0x47: ['Watchdog or safety monitoring failure', 'वॉचडॉग या मॉनिटरिंग विफलता'],
      0x4B: ['Over temperature', 'अत्यधिक तापमान'],
      0x62: ['Signal compare failure', 'सिग्नल तुलना में विफलता'],
      0x64: ['Signal plausibility failure', 'सिग्नल प्लॉज़िबिलिटी विफलता'],
      0x71: ['Actuator stuck', 'एक्चुएटर अटका हुआ'],
      0x72: ['Actuator stuck open', 'एक्चुएटर खुला अटका हुआ'],
      0x73: ['Actuator stuck closed', 'एक्चुएटर बंद अटका हुआ'],
      0x81: ['Invalid serial data received', 'अमान्य सीरियल डेटा मिला'],
      0x85: ['Signal out of range', 'सिग्नल सीमा से बाहर'],
      0x86: ['Invalid CAN signal', 'अमान्य CAN सिग्नल'],
      0x88: ['Bus off', 'बस ऑफ (CAN बस बंद)'],
      0x92: ['Performance or incorrect operation', 'परफ़ॉर्मेंस या गलत संचालन'],
      0x96: ['Component internal failure', 'कंपोनेंट की आंतरिक खराबी'],
      0x97: [
        'Component or system obstructed or blocked',
        'कंपोनेंट या सिस्टम में रुकावट'
      ],
    };

    test('exactly the 28 brief entries, verbatim, in English and Hindi', () {
      expect(FailureType.knownBytes.toSet(), expected.keys.toSet());
      expected.forEach((ftb, text) {
        expect(FailureType.describe(ftb, 'en'), text[0]);
        expect(FailureType.describe(ftb, 'hi'), text[1]);
        expect(FailureType.isKnown(ftb), isTrue);
      });
    });

    test('any other byte is never guessed', () {
      for (var ftb = 0; ftb < 256; ftb++) {
        if (expected.containsKey(ftb)) continue;
        final hex = ftb.toRadixString(16).toUpperCase().padLeft(2, '0');
        expect(FailureType.isKnown(ftb), isFalse);
        expect(FailureType.describe(ftb, 'en'),
            'failure type 0x$hex, no description');
        // Phase 1B (B10c): the Hindi wording now matches the ABS row label
        // 'खराबी का प्रकार'. Same rule tested — never guessed, the byte shown.
        expect(FailureType.describe(ftb, 'hi'),
            'खराबी का प्रकार 0x$hex, कोई विवरण नहीं');
      }
    });

    test('other languages fall back to English, as the rest of the fault text does', () {
      expect(FailureType.describe(0x11, 'ta'), 'Circuit short to ground');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // OBD Mode 03 / 07 / 0A decoder
  // ══════════════════════════════════════════════════════════════════════════
  group('A2 OBD DTC decoder: zero padding', () {
    test('K-line form "43 01 33 00 00 00 00" holds ONE code, not three', () {
      final r = decodeObdDtcReply('43 01 33 00 00 00 00',
          service: 0x03, framing: DtcFraming.legacy);
      expect(r, isA<ObdDtcCodes>());
      expect((r as ObdDtcCodes).codes.map((c) => c.code), ['P0133']);
    });

    test('K-line headers on, checksum byte dropped', () {
      final r = decodeObdDtcReply('48 6B 10 43 01 33 00 00 00 00 C0',
          service: 0x03, framing: DtcFraming.legacy);
      expect((r as ObdDtcCodes).codes.map((c) => c.code), ['P0133']);
    });

    test('K-line two frames carry four codes', () {
      final r = decodeObdDtcReply(
          '43 01 33 03 01 01 13\r43 02 34 00 00 00 00',
          service: 0x03,
          framing: DtcFraming.legacy);
      expect((r as ObdDtcCodes).codes.map((c) => c.code),
          ['P0133', 'P0301', 'P0113', 'P0234']);
    });

    test('CAN single frame padded with 00 after the PCI length', () {
      final r = decodeObdDtcReply('7E8 06 43 01 01 33 00 00 00',
          service: 0x03, framing: DtcFraming.iso15765);
      final codes = r as ObdDtcCodes;
      expect(codes.codes.map((c) => c.code), ['P0133']);
      expect(codes.reportedCount, 1);
      expect(codes.codes.single.ecuId, '7E8');
    });

    test('CAN headers off: count byte present, trailing 00 ignored', () {
      final r = decodeObdDtcReply('43 01 01 33 00 00',
          service: 0x03, framing: DtcFraming.iso15765);
      expect((r as ObdDtcCodes).codes.map((c) => c.code), ['P0133']);
    });

    test('CAN headers on, 29-bit header printed with spaces', () {
      final r = decodeObdDtcReply('18 DA F1 10 04 43 01 01 33',
          service: 0x03, framing: DtcFraming.iso15765);
      final codes = r as ObdDtcCodes;
      expect(codes.codes.map((c) => c.code), ['P0133']);
      expect(codes.codes.single.ecuId, '18DAF110');
    });

    test('CAN headers on, spaces off (3-nibble header)', () {
      final r = decodeObdDtcReply('7E804430101 33'.replaceAll(' ', ''),
          service: 0x03, framing: DtcFraming.iso15765);
      expect((r as ObdDtcCodes).codes.map((c) => c.code), ['P0133']);
    });

    test('positive empty answer is codes = [] (and only that)', () {
      final r = decodeObdDtcReply('7E8 02 43 00',
          service: 0x03, framing: DtcFraming.iso15765);
      expect((r as ObdDtcCodes).codes, isEmpty);
      expect(r.reportedCount, 0);
    });

    test('Mode 07 and 0A use their own response bytes', () {
      final p = decodeObdDtcReply('7E8 04 47 01 03 01',
          service: 0x07, framing: DtcFraming.iso15765);
      expect((p as ObdDtcCodes).codes.map((c) => c.code), ['P0301']);
      final q = decodeObdDtcReply('7E8 04 4A 01 04 20',
          service: 0x0A, framing: DtcFraming.iso15765);
      expect((q as ObdDtcCodes).codes.map((c) => c.code), ['P0420']);
      // A 43 is not an answer to 07.
      expect(
          decodeObdDtcReply('7E8 04 43 01 03 01',
              service: 0x07, framing: DtcFraming.iso15765),
          isA<ObdDtcUnparseable>());
    });

    test('multi-frame CAN, two ECUs, merged with module attribution', () {
      const reply = '7E8 10 0A 43 04 01 33 03 01\r'
          '7E8 21 01 13 02 34 00 00 00\r'
          '7E9 04 43 01 C1 00';
      final r = decodeObdDtcReply(reply,
          service: 0x03, framing: DtcFraming.iso15765) as ObdDtcCodes;
      expect(r.codes.map((c) => '${c.code}@${c.ecuId}'),
          ['P0133@7E8', 'P0301@7E8', 'P0113@7E8', 'P0234@7E8', 'U0100@7E9']);
      expect(r.reportedCount, 5);
      expect(r.countMismatch, isFalse);
    });
  });

  group('A2 OBD DTC decoder: typed results for bad input', () {
    test('negative response', () {
      final r = decodeObdDtcReply('7E8 03 7F 07 11',
          service: 0x07, framing: DtcFraming.iso15765);
      expect(r, isA<ObdDtcNegative>());
      expect((r as ObdDtcNegative).nrc, 0x11);
    });

    test('NO DATA and noise-only are NoData, never codes', () {
      for (final raw in ['NO DATA', 'SEARCHING...\rNO DATA', '', '   ']) {
        expect(
            decodeObdDtcReply(raw, service: 0x03, framing: DtcFraming.iso15765),
            isA<ObdDtcNoData>(),
            reason: raw);
      }
      expect(
          decodeObdDtcReply(null, service: 0x03, framing: DtcFraming.legacy),
          isA<ObdDtcNoData>());
    });

    test('odd number of hex digits is Unparseable', () {
      expect(
          decodeObdDtcReply('43 01 01 3',
              service: 0x03, framing: DtcFraming.iso15765),
          isA<ObdDtcUnparseable>());
      expect(
          decodeObdDtcReply('43 01 33 00 00 0',
              service: 0x03, framing: DtcFraming.legacy),
          isA<ObdDtcUnparseable>());
    });

    test('garbage is Unparseable', () {
      for (final raw in ['ZZZZ', '41 0C 1A F8', '\u0000\u0001', 'ELM327 v1.5']) {
        expect(
            decodeObdDtcReply(raw, service: 0x03, framing: DtcFraming.iso15765),
            anyOf(isA<ObdDtcUnparseable>(), isA<ObdDtcNoData>()),
            reason: raw);
      }
    });

    test('a missing consecutive frame is Truncated, with what did arrive', () {
      const reply = '7E8 10 0A 43 04 01 33 03 01\r'
          '7E8 22 01 13 02 34 00 00 00'; // sequence 1 missing
      final r = decodeObdDtcReply(reply,
          service: 0x03, framing: DtcFraming.iso15765);
      expect(r, isA<ObdDtcTruncated>());
      expect((r as ObdDtcTruncated).partial.map((c) => c.code),
          ['P0133', 'P0301']);
    });

    test('first frame declared longer than what arrived is Truncated', () {
      final r = decodeObdDtcReply('7E8 10 0A 43 04 01 33 03 01',
          service: 0x03, framing: DtcFraming.iso15765);
      expect(r, isA<ObdDtcTruncated>());
    });

    test('count byte larger than the codes sent is flagged, codes kept', () {
      final r = decodeObdDtcReply('7E8 04 43 02 01 33',
          service: 0x03, framing: DtcFraming.iso15765) as ObdDtcCodes;
      expect(r.codes.map((c) => c.code), ['P0133']);
      expect(r.countMismatch, isTrue);
    });

    test('a positive answer wins over a pending frame in the same buffer', () {
      final r = decodeObdDtcReply('7E8 03 7F 03 78\r7E8 04 43 01 01 33',
          service: 0x03, framing: DtcFraming.iso15765);
      expect((r as ObdDtcCodes).codes.map((c) => c.code), ['P0133']);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // UDS 19 02 decoder
  // ══════════════════════════════════════════════════════════════════════════
  group('A2 UDS 59 02 decoder', () {
    test('single record: code, failure type and status kept', () {
      final r = decodeUds19Reply('7B8 07 59 02 FF 50 58 11 2F');
      final recs = (r as Uds19Records).records;
      expect(recs, hasLength(1));
      expect(recs.single.code, 'C1058');
      expect(recs.single.dtcHigh, 0x50);
      expect(recs.single.dtcMid, 0x58);
      expect(recs.single.failureType, 0x11);
      expect(recs.single.status, 0x2F);
      expect(recs.single.ecuId, '7B8');
      expect(r.availabilityMask, 0xFF);
    });

    test('multi-frame, four records', () {
      const reply = '7B8 10 13 59 02 FF 50 58 00\r'
          '7B8 21 2F 50 15 04 09 C1 00\r'
          '7B8 22 88 08 51 22 13 89 00';
      final r = decodeUds19Reply(reply) as Uds19Records;
      expect(r.records.map((x) => '${x.code}-${x.failureType.toRadixString(16)}'),
          ['C1058-0', 'C1015-4', 'U0100-88', 'C1122-13']);
      expect(r.records.map((x) => x.status), [0x2F, 0x09, 0x08, 0x89]);
    });

    test('zero padding records and a padded tail are not codes', () {
      final r = decodeUds19Reply('59 02 FF 50 58 00 2F 00 00 00 00 00 00')
          as Uds19Records;
      expect(r.records.map((x) => x.code), ['C1058']);
    });

    test('positive with no records is an empty list (module answered, clean)', () {
      final r = decodeUds19Reply('7B8 03 59 02 FF') as Uds19Records;
      expect(r.records, isEmpty);
    });

    test('a pending frame before the answer does not discard the answer', () {
      final r = decodeUds19Reply('7B8 03 7F 19 78\r7B8 07 59 02 FF 50 58 00 2F');
      expect((r as Uds19Records).records.map((x) => x.code), ['C1058']);
    });

    test('a non-zero partial record at the end is Truncated', () {
      final r = decodeUds19Reply('59 02 FF 50 58 00 2F 50 15');
      expect(r, isA<Uds19Truncated>());
      expect((r as Uds19Truncated).partial.map((x) => x.code), ['C1058']);
    });

    test('refusal, no data, garbage and odd length are typed', () {
      expect(decodeUds19Reply('7B8 03 7F 19 22'), isA<Uds19Negative>());
      expect((decodeUds19Reply('7F 19 31') as Uds19Negative).nrc, 0x31);
      expect(decodeUds19Reply('NO DATA'), isA<Uds19NoData>());
      expect(decodeUds19Reply(''), isA<Uds19NoData>());
      expect(decodeUds19Reply('59 02 FF 50 5'), isA<Uds19Unparseable>());
      expect(decodeUds19Reply('59 01 FF'), isA<Uds19Unparseable>());
      expect(decodeUds19Reply('hello'), isA<Uds19Unparseable>());
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Mode 01 helpers used by the extras
  // ══════════════════════════════════════════════════════════════════════════
  group('A4/A5 Mode 01 decoders', () {
    test('PID 01 01: lamp bit 7, count bits 0-6', () {
      final on = decodeMilStatus('7E8 06 41 01 83 07 E5 00') as DecodedValue<MilStatus>;
      expect(on.value.lampOn, isTrue);
      expect(on.value.storedCount, 3);
      final off = decodeMilStatus('41 01 00 07 E5 00') as DecodedValue<MilStatus>;
      expect(off.value.lampOn, isFalse);
      expect(off.value.storedCount, 0);
    });

    test('PID 01 01 from two ECUs: lamp is any, counts add', () {
      final r = decodeMilStatus('7E8 06 41 01 81 07 E5 00\r7E9 06 41 01 01 00 00 00')
          as DecodedValue<MilStatus>;
      expect(r.value.lampOn, isTrue);
      expect(r.value.storedCount, 2);
    });

    test('RPM = (256A + B) / 4', () {
      final r = decodeRpm('7E8 04 41 0C 0F A0') as DecodedValue<double>;
      expect(r.value, 1000);
      expect((decodeRpm('41 0C 00 00') as DecodedValue<double>).value, 0);
    });

    test('module voltage = (256A + B) / 1000', () {
      final r = decodeModuleVoltage('7E8 04 41 42 2E E0') as DecodedValue<double>;
      expect(r.value, closeTo(12.0, 1e-9));
    });

    test('unsupported PIDs are Unsupported, refusals are Negative', () {
      expect(decodeRpm('NO DATA'), isA<DecodedUnsupported<double>>());
      expect(decodeModuleVoltage('7E8 03 7F 01 12'),
          isA<DecodedUnsupported<double>>());
      expect(decodeModuleVoltage('7E8 03 7F 01 22'), isA<DecodedNegative<double>>());
      expect(decodeRpm('41 0C 0F'), isA<DecodedUnparseable<double>>());
      expect(decodeRpm('TIMEOUT'), isA<DecodedNoAnswer<double>>());
    });

    test('ATRV adapter voltage', () {
      expect((decodeAdapterVoltage('12.4V') as DecodedValue<double>).value, 12.4);
      expect(decodeAdapterVoltage('?'), isA<DecodedUnsupported<double>>());
      expect(decodeAdapterVoltage('TIMEOUT'), isA<DecodedNoAnswer<double>>());
    });
  });
}
