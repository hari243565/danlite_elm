/// Phase 1A — A6: VIN (Mode 09 PID 02) and calibration ID (PID 04) parsing.
///
/// The test VIN is the fake `MA3FAKE0123456789` (17 characters, no I, O or Q).
/// Reply shapes are built from the SAE J1979 / ISO 15765-2 layouts, not
/// recorded from a real bike.
library;

import 'package:danlite_elm/services/fault_decoders.dart';
import 'package:flutter_test/flutter_test.dart';

const fakeVin = 'MA3FAKE0123456789';

String hex(int b) => b.toRadixString(16).toUpperCase().padLeft(2, '0');

/// An ISO-TP reply from [header] carrying [payload], headers on, spaces on.
String canReply(List<int> payload, {String header = '7E8'}) {
  if (payload.length <= 7) {
    return '$header ${hex(payload.length)} ${payload.map(hex).join(' ')}';
  }
  final lines = <String>[];
  final len = payload.length;
  lines.add('$header ${hex(0x10 | (len >> 8))} ${hex(len & 0xFF)} '
      '${payload.sublist(0, 6).map(hex).join(' ')}');
  var seq = 1;
  for (var i = 6; i < len; i += 7, seq++) {
    final chunk = payload.sublist(i, i + 7 > len ? len : i + 7);
    final padded = [...chunk, ...List<int>.filled(7 - chunk.length, 0x00)];
    lines.add('$header ${hex(0x20 | (seq & 0x0F))} ${padded.map(hex).join(' ')}');
  }
  return lines.join('\r');
}

List<int> ascii(String s) => s.codeUnits;

void main() {
  group('A6 VIN validator', () {
    test('the fake VIN passes; I, O, Q and wrong lengths fail', () {
      expect(Vin.isValid(fakeVin), isTrue);
      expect(Vin.isValid('MA3FAKE012345678'), isFalse); // 16
      expect(Vin.isValid('MA3FAKE01234567890'), isFalse); // 18
      expect(Vin.isValid('MA3FAKEI123456789'), isFalse);
      expect(Vin.isValid('MA3FAKEO123456789'), isFalse);
      expect(Vin.isValid('MA3FAKEQ123456789'), isFalse);
      expect(Vin.isValid('ma3fake0123456789'), isFalse);
    });

    test('the North American check digit is not enforced', () {
      // Position 9 here is '1', not a valid check digit for this VIN under
      // the 49 CFR 565 rule; Indian VINs need not satisfy it.
      expect(Vin.isValid(fakeVin), isTrue);
    });

    test('a Vin never prints itself', () {
      final v = Vin.tryParse(fakeVin)!;
      expect(v.toString(), '[VIN masked]');
      expect('$v', isNot(contains('FAKE')));
      expect(v.masked, 'MA3************89');
      expect(v.value, fakeVin);
    });
  });

  group('A6 VIN reply forms that must parse', () {
    void expectVin(String reply) {
      final r = decodeVinReply(reply);
      expect(r, isA<DecodedValue<Vin>>(), reason: reply);
      expect((r as DecodedValue<Vin>).value.value, fakeVin);
    }

    test('CAN multi-frame, headers on: 49 02 01 + 17 bytes', () {
      expectVin(canReply([0x49, 0x02, 0x01, ...ascii(fakeVin)]));
    });

    test('CAN multi-frame, headers off (ELM numbered lines)', () {
      expectVin('014\r'
          '0: 49 02 01 4D 41 33\r'
          '1: 46 41 4B 45 30 31 32\r'
          '2: 33 34 35 36 37 38 39');
    });

    test('leading zero padding before the 17 characters', () {
      expectVin(canReply([0x49, 0x02, 0x01, 0x00, 0x00, 0x00, ...ascii(fakeVin)]));
    });

    test('older multi-message form (49 02 01 … 49 02 05)', () {
      expectVin('49 02 01 00 00 00 4D\r'
          '49 02 02 41 33 46 41\r'
          '49 02 03 4B 45 30 31\r'
          '49 02 04 32 33 34 35\r'
          '49 02 05 36 37 38 39');
    });

    test('spaces off', () {
      expectVin(canReply([0x49, 0x02, 0x01, ...ascii(fakeVin)])
          .replaceAll(' ', ''));
    });

    test('line feeds instead of carriage returns, and a trailing prompt', () {
      expectVin('${canReply([0x49, 0x02, 0x01, ...ascii(fakeVin)]).replaceAll('\r', '\n')}\n>');
    });

    test('29-bit header printed with spaces', () {
      final r = canReply([0x49, 0x02, 0x01, ...ascii(fakeVin)], header: '18DAF110')
          .replaceAll('18DAF110', '18 DA F1 10');
      expectVin(r);
    });
  });

  group('A6 VIN replies that must be rejected (never a value)', () {
    void expectRejected(String reply, String why) {
      final r = decodeVinReply(reply);
      expect(r, isNot(isA<DecodedValue<Vin>>()), reason: why);
    }

    test('16 characters', () {
      expectRejected(canReply([0x49, 0x02, 0x01, ...ascii('MA3FAKE012345678')]), '16');
    });
    test('18 characters', () {
      expectRejected(canReply([0x49, 0x02, 0x01, ...ascii('MA3FAKE01234567890')]), '18');
    });
    test('contains the letter I', () {
      expectRejected(canReply([0x49, 0x02, 0x01, ...ascii('MA3FAKEI123456789')]), 'I');
    });
    test('contains a non-printable byte', () {
      final bytes = ascii(fakeVin).toList()..[7] = 0x07;
      expectRejected(canReply([0x49, 0x02, 0x01, ...bytes]), 'BEL');
    });
    test('a truncated multi-frame reply', () {
      final full = canReply([0x49, 0x02, 0x01, ...ascii(fakeVin)]);
      expectRejected(full.split('\r').take(2).join('\r'), 'truncated');
    });
    test('unsupported and silent are typed, not errors', () {
      expect(decodeVinReply('NO DATA'), isA<DecodedUnsupported<Vin>>());
      expect(decodeVinReply('7E8 03 7F 09 11'), isA<DecodedUnsupported<Vin>>());
      expect(decodeVinReply('TIMEOUT'), isA<DecodedNoAnswer<Vin>>());
      expect(decodeVinReply(null), isA<DecodedNoAnswer<Vin>>());
    });
    test('the rejection reason never contains the characters', () {
      final r = decodeVinReply(
          canReply([0x49, 0x02, 0x01, ...ascii('MA3FAKE01234567890')]));
      expect((r as DecodedUnparseable<Vin>).reason, isNot(contains('FAKE')));
      expect(r.reason, startsWith('InvalidVin'));
    });
  });

  group('A6 calibration IDs (Mode 09 PID 04)', () {
    test('one 16-character ID, 00 padded', () {
      final id = ascii('DL123456').toList();
      final payload = [0x49, 0x04, 0x01, ...id, ...List<int>.filled(8, 0)];
      final r = decodeCalibrationIds(canReply(payload));
      expect((r as DecodedValue<List<String>>).value, ['DL123456']);
    });
    test('two IDs', () {
      final a = [...ascii('CAL-A-0001'), ...List<int>.filled(6, 0)];
      final b = [...ascii('CAL-B-0002'), ...List<int>.filled(6, 0)];
      final r = decodeCalibrationIds(canReply([0x49, 0x04, 0x02, ...a, ...b]));
      expect((r as DecodedValue<List<String>>).value, ['CAL-A-0001', 'CAL-B-0002']);
    });
    test('unsupported', () {
      expect(decodeCalibrationIds('NO DATA'),
          isA<DecodedUnsupported<List<String>>>());
    });
  });
}
