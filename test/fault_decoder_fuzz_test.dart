/// Phase 1A — A2 robustness: every decoder survives noise.
///
/// Feeds well over 10,000 random and mutated adapter replies through every
/// decoder that reads fault or vehicle data, and asserts each one returns a
/// typed result without throwing. Seeded, so a failure is reproducible.
library;

import 'dart:math';

import 'package:danlite_elm/constants/obd_pids.dart';
import 'package:danlite_elm/services/engine_dtc_read.dart';
import 'package:danlite_elm/services/fault_decoders.dart';
import 'package:flutter_test/flutter_test.dart';

/// Valid replies the mutations start from.
const seeds = <String>[
  '43 00',
  '7E8 02 43 00',
  '7E8 06 43 02 01 33 03 01',
  '43 01 33 00 00 00 00',
  '48 6B 10 43 01 33 00 00 00 00 C0',
  '7E8 10 0A 43 04 01 33 03 01\r7E8 21 01 13 02 34 00 00 00',
  '18 DA F1 10 04 43 01 01 33',
  '7E8 03 7F 03 78\r7E8 04 43 01 01 33',
  '7E8 04 47 01 03 01',
  '7E8 04 4A 01 04 20',
  '7B8 07 59 02 FF 50 58 11 2F',
  '7B8 10 13 59 02 FF 50 58 00\r7B8 21 2F 50 15 04 09 C1 00\r7B8 22 88 08 51 22 13 89 00',
  '7B8 03 7F 19 78',
  '7F 19 22',
  '7E8 06 41 01 83 07 E5 00',
  '7E8 04 41 0C 0F A0',
  '7E8 04 41 42 2E E0',
  '12.4V',
  '014\r0: 49 02 01 4D 41 33\r1: 46 41 4B 45 30 31 32\r2: 33 34 35 36 37 38 39',
  '49 02 01 00 00 00 4D\r49 02 02 41 33 46 41\r49 02 03 4B 45 30 31',
  'NO DATA',
  'SEARCHING...\rUNABLE TO CONNECT',
  'BUS INIT: ...ERROR',
  '?',
  'TIMEOUT',
  '',
];

const noiseWords = <String>[
  'SEARCHING...', 'NO DATA', 'OK', '?', 'STOPPED', 'BUFFER FULL', 'CAN ERROR',
  '>', 'ELM327 v1.5', '7F', '78', '00', 'FF', '\r', '\n', ' ', ':', '0:', '1:',
];

String mutate(String s, Random r) {
  final chars = s.split('');
  final ops = 1 + r.nextInt(4);
  for (var k = 0; k < ops; k++) {
    switch (r.nextInt(8)) {
      case 0: // flip one character to a random hex digit
        if (chars.isNotEmpty) {
          chars[r.nextInt(chars.length)] = '0123456789ABCDEF'[r.nextInt(16)];
        }
        break;
      case 1: // delete a character (makes odd lengths)
        if (chars.isNotEmpty) chars.removeAt(r.nextInt(chars.length));
        break;
      case 2: // insert a noise word
        chars.insert(chars.isEmpty ? 0 : r.nextInt(chars.length + 1),
            noiseWords[r.nextInt(noiseWords.length)]);
        break;
      case 3: // truncate
        if (chars.isNotEmpty) chars.removeRange(r.nextInt(chars.length), chars.length);
        break;
      case 4: // duplicate a slice
        if (chars.length > 2) {
          final a = r.nextInt(chars.length - 1);
          final b = a + 1 + r.nextInt(chars.length - a - 1);
          chars.insertAll(b, chars.sublist(a, b));
        }
        break;
      case 5: // random control or non-ASCII character
        chars.insert(chars.isEmpty ? 0 : r.nextInt(chars.length + 1),
            String.fromCharCode([0, 7, 9, 27, 127, 0xA0, 0x0900, 0xFFFD][r.nextInt(8)]));
        break;
      case 6: // append zero padding
        chars.add(' 00' * (1 + r.nextInt(6)));
        break;
      case 7: // swap line separators
        for (var i = 0; i < chars.length; i++) {
          if (chars[i] == '\r') chars[i] = r.nextBool() ? '\n' : '\r\n';
        }
        break;
    }
  }
  return chars.join();
}

String randomHexReply(Random r) {
  final lines = 1 + r.nextInt(5);
  final out = <String>[];
  for (var l = 0; l < lines; l++) {
    final header = r.nextInt(3) == 0 ? '' : (r.nextBool() ? '7E8 ' : '18 DA F1 10 ');
    final n = r.nextInt(12);
    final bytes = List.generate(n, (_) {
      // Bias towards meaningful bytes.
      const interesting = [0x00, 0x01, 0x02, 0x03, 0x07, 0x0A, 0x10, 0x21, 0x41,
        0x43, 0x47, 0x49, 0x4A, 0x59, 0x7F, 0x78, 0x19, 0xFF];
      final v = r.nextInt(3) == 0 ? r.nextInt(256) : interesting[r.nextInt(interesting.length)];
      return v.toRadixString(16).toUpperCase().padLeft(2, '0');
    });
    out.add('$header${bytes.join(r.nextInt(4) == 0 ? '' : ' ')}');
  }
  return out.join(r.nextBool() ? '\r' : '\n');
}

String randomText(Random r) => String.fromCharCodes(
    List.generate(r.nextInt(60), (_) => r.nextInt(5) == 0 ? r.nextInt(0x3000) : 32 + r.nextInt(95)));

/// Run every decoder on [input]; any throw fails the test with the input.
int exercise(String input, Random r) {
  var calls = 0;
  void call(Object? Function() f) {
    final result = f();
    expect(result, isNotNull, reason: 'null result for ${input.codeUnits}');
    calls++;
  }

  for (final framing in DtcFraming.values) {
    for (final sid in const [0x03, 0x07, 0x0A]) {
      call(() => decodeObdDtcReply(input, service: sid, framing: framing));
    }
  }
  call(() => decodeUds19Reply(input));
  call(() => decodeMilStatus(input));
  call(() => decodeRpm(input));
  call(() => decodeModuleVoltage(input));
  call(() => decodeAdapterVoltage(input));
  call(() => decodeVinReply(input));
  call(() => decodeCalibrationIds(input));
  call(() => stripResponsePending(input, 0x19));
  call(() => classifyEngineDtcReply(input, linkFailed: false));
  call(() => ObdParser.parseDetailed(input));
  call(() => ObdParser.parseUdsDtcDetailed(input));
  call(() => ObdParser.reassembleFrames(input));
  call(() => UdsStatusByte(r.nextInt(1 << 16) - 100).isHistory);
  call(() => FailureType.describe(r.nextInt(512) - 128, r.nextBool() ? 'hi' : 'en'));

  // Invariants that hold whatever the input was.
  final vin = decodeVinReply(input);
  if (vin is DecodedValue<Vin>) {
    expect(Vin.isValid(vin.value.value), isTrue);
  }
  final obd = decodeObdDtcReply(input, service: 0x03, framing: DtcFraming.iso15765);
  if (obd is ObdDtcCodes) {
    expect(input.toUpperCase().replaceAll(RegExp(r'\s'), ''), contains('43'),
        reason: 'codes only from a positive 43 response: ${input.codeUnits}');
    for (final c in obd.codes) {
      expect(RegExp(r'^[PCBU][0-3][0-9A-F]{3}$').hasMatch(c.code), isTrue);
    }
  }
  return calls;
}

void main() {
  test('A2 fuzz: >= 10,000 random and mutated inputs, no exception, typed result',
      () {
    final r = Random(20261001);
    var inputs = 0;
    var calls = 0;
    for (var i = 0; i < 4000; i++) {
      calls += exercise(mutate(seeds[r.nextInt(seeds.length)], r), r);
      inputs++;
    }
    for (var i = 0; i < 4000; i++) {
      calls += exercise(randomHexReply(r), r);
      inputs++;
    }
    for (var i = 0; i < 2500; i++) {
      calls += exercise(randomText(r), r);
      inputs++;
    }
    for (final s in seeds) {
      calls += exercise(s, r);
      inputs++;
    }
    expect(inputs, greaterThanOrEqualTo(10000));
    // ignore: avoid_print
    print('fuzz: $inputs inputs, $calls decoder calls, all typed, none threw');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
