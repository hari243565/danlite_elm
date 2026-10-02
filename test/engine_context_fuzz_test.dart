/// Phase A-4 (C4) — the context decoders survive noise, and the small pure
/// helpers around them.
///
/// Like the Phase 1A fuzz test: well over 10,000 random and mutated adapter
/// replies through every new decoder; each must return a typed result without
/// throwing, and must never produce a value the input does not contain.
/// Seeded, so a failure is reproducible.
library;

import 'dart:math';

import 'package:danlite_elm/services/engine_context.dart';
import 'package:danlite_elm/services/fault_decoders.dart';
import 'package:flutter_test/flutter_test.dart';

const seeds = <String>[
  '41 21 00 0A',
  '7E8 04 41 21 00 0A',
  '7E8 04 41 31 FF FF',
  '18 DA F1 10 04 41 4D 01 00',
  '18DAF110 04 41 4E 00 05',
  '7E8 03 41 30 FF',
  '7E8 06 41 01 83 07 E5 00',
  '41 01 00 77 FF FF',
  '42 02 00 03 01',
  '7E8 05 42 02 00 03 01',
  '42 02 00 00 00',
  '7E8 07 42 00 00 BE 1F A8 13',
  '42 40 00 40 00 00 00',
  '42 03 00 02 00',
  '42 04 00 80',
  '42 0C 00 0F A0',
  '42 42 00 36 B0',
  '7E8 03 7F 02 12',
  '7E8 03 7F 02 78\r7E8 05 42 02 00 03 01',
  '7E8 03 7F 01 22',
  'NO DATA',
  'SEARCHING...\rUNABLE TO CONNECT',
  'CAN ERROR',
  '?',
  'TIMEOUT',
  'DISCONNECTED',
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
      case 0:
        if (chars.isNotEmpty) {
          chars[r.nextInt(chars.length)] = '0123456789ABCDEF'[r.nextInt(16)];
        }
      case 1:
        if (chars.isNotEmpty) chars.removeAt(r.nextInt(chars.length));
      case 2:
        chars.insert(chars.isEmpty ? 0 : r.nextInt(chars.length + 1),
            noiseWords[r.nextInt(noiseWords.length)]);
      case 3:
        if (chars.isNotEmpty) chars.removeRange(r.nextInt(chars.length), chars.length);
      case 4:
        if (chars.length > 2) {
          final a = r.nextInt(chars.length - 1);
          final b = a + 1 + r.nextInt(chars.length - a - 1);
          chars.insertAll(b, chars.sublist(a, b));
        }
      case 5:
        chars.insert(chars.isEmpty ? 0 : r.nextInt(chars.length + 1),
            String.fromCharCode([0, 7, 9, 27, 127, 0xA0, 0x0900, 0xFFFD][r.nextInt(8)]));
      case 6:
        chars.add(' 00' * (1 + r.nextInt(6)));
      case 7:
        for (var i = 0; i < chars.length; i++) {
          if (chars[i] == '\r') chars[i] = r.nextBool() ? '\n' : '\r\n';
        }
    }
  }
  return chars.join();
}

String randomHexReply(Random r) {
  final lines = 1 + r.nextInt(4);
  final out = <String>[];
  for (var l = 0; l < lines; l++) {
    final header = r.nextInt(3) == 0 ? '' : (r.nextBool() ? '7E8 ' : '18 DA F1 10 ');
    final n = r.nextInt(10);
    final bytes = List.generate(n, (_) {
      const interesting = [0x00, 0x01, 0x02, 0x03, 0x21, 0x30, 0x31, 0x41, 0x42,
        0x4D, 0x4E, 0x7F, 0x78, 0xFF];
      final v = r.nextInt(3) == 0 ? r.nextInt(256) : interesting[r.nextInt(interesting.length)];
      return v.toRadixString(16).toUpperCase().padLeft(2, '0');
    });
    out.add('$header${bytes.join(r.nextInt(4) == 0 ? '' : ' ')}');
  }
  return out.join(r.nextBool() ? '\r' : '\n');
}

String randomText(Random r) => String.fromCharCodes(
    List.generate(r.nextInt(60), (_) => r.nextInt(5) == 0 ? r.nextInt(0x3000) : 32 + r.nextInt(95)));

String compact(String s) => s.toUpperCase().replaceAll(RegExp(r'\s+'), '');
String hex2(int b) => b.toRadixString(16).toUpperCase().padLeft(2, '0');

int exercise(String input) {
  var calls = 0;
  final c = compact(input);

  for (final counter in ContextCounter.values) {
    final d = decodeContextCounter(input, counter);
    calls++;
    if (d is DecodedValue<CounterValue>) {
      expect(d.value.value, inInclusiveRange(0, counter.max), reason: input);
      expect(c.contains('41${hex2(counter.pid)}'), isTrue,
          reason: 'a counter value from bytes that do not contain it: $input');
    }
  }

  final ready = decodeReadiness(input);
  calls++;
  if (ready is DecodedValue<ReadinessReport>) {
    expect(ready.value.states.keys.toSet(), Monitor.values.toSet(), reason: input);
    expect(c.contains('4101'), isTrue, reason: input);
  }

  final trigger = decodeFreezeFrameTrigger(input);
  calls++;
  if (trigger is DecodedValue<FreezeFrameTrigger>) {
    final code = trigger.value.code;
    if (code != null) {
      expect(RegExp(r'^[PCBU][0-9A-F]{4}$').hasMatch(code), isTrue, reason: input);
    }
    expect(c.contains('4202'), isTrue, reason: input);
  }

  for (final service in [1, 2]) {
    for (final base in [0x00, 0x20, 0x40]) {
      final d = decodeSupportedPids(input, service: service, basePid: base);
      calls++;
      if (d is DecodedValue<Set<int>>) {
        for (final p in d.value) {
          expect(p, inInclusiveRange(base + 1, base + 32), reason: input);
        }
      }
    }
  }

  for (final p in SnapshotPid.values) {
    final d = decodeFreezeFrameValue(input, p);
    calls++;
    if (d is DecodedValue<SnapshotValue>) {
      expect(c.contains('42${hex2(p.pid)}'), isTrue,
          reason: 'a snapshot value from bytes that do not contain it: $input');
      final v = d.value;
      if (v is SnapshotNumber) expect(v.value.isFinite, isTrue, reason: input);
    }
  }
  return calls;
}

void main() {
  test('10,000+ mutated, random-hex and random-text replies: typed results, no throw', () {
    final r = Random(0xA4A4);
    var inputs = 0;
    var calls = 0;
    for (final s in seeds) {
      calls += exercise(s);
      inputs++;
    }
    for (var i = 0; i < 7000; i++) {
      calls += exercise(mutate(seeds[r.nextInt(seeds.length)], r));
      inputs++;
    }
    for (var i = 0; i < 3500; i++) {
      calls += exercise(randomHexReply(r));
      inputs++;
    }
    for (var i = 0; i < 1500; i++) {
      calls += exercise(randomText(r));
      inputs++;
    }
    expect(inputs, greaterThan(10000));
    expect(calls, greaterThan(100000));
  });

  test('null and absurdly long input', () {
    expect(exercise(''), greaterThan(0));
    expect(() => decodeContextCounter(null, ContextCounter.warmUps), returnsNormally);
    expect(() => decodeReadiness('41 01 ' * 5000), returnsNormally);
    expect(() => decodeFreezeFrameTrigger('42 02 00 03 01 ' * 5000), returnsNormally);
  });

  // ══════════════════════════════════════════════════════════════════════
  // The small pure helpers
  // ══════════════════════════════════════════════════════════════════════
  group('formatCount', () {
    test('thousands, Latin digits', () {
      expect(formatCount(0), '0');
      expect(formatCount(1), '1');
      expect(formatCount(255), '255');
      expect(formatCount(256), '256');
      expect(formatCount(1000), '1,000');
      expect(formatCount(65535), '65,535');
      expect(formatCount(1234567), '1,234,567');
    });
  });

  group('lamp counters are only shown when they can be true', () {
    const zero = CounterValue(0, 65535);
    const some = CounterValue(120, 65535);
    test('a zero is never "the lamp has been on for 0 km"', () {
      expect(lampCounterIsShown(zero, lampOn: true), isFalse);
      expect(lampCounterIsShown(zero, lampOn: null), isFalse);
      expect(lampCounterIsShown(zero, lampOn: false), isFalse);
    });
    test('a value with the lamp known OFF is not shown', () {
      expect(lampCounterIsShown(some, lampOn: false), isFalse);
    });
    test('a value with the lamp on, or the lamp state unknown, is shown', () {
      expect(lampCounterIsShown(some, lampOn: true), isTrue);
      expect(lampCounterIsShown(some, lampOn: null), isTrue);
    });
  });

  group('freezeFrameEndsHere: each reply to PID 02 ends the read in its own way', () {
    final at = DateTime(2026, 10, 2, 12);
    FreezeFrameResult? ends(String? raw, {bool vehicleAnswered = true}) =>
        freezeFrameEndsHere(decodeFreezeFrameTrigger(raw), at,
            vehicleAnswered: vehicleAnswered);

    test('a real code lets the read go on', () {
      expect(ends('42 02 00 03 01'), isNull);
    });
    test('0000 is NoSnapshot', () {
      expect(ends('42 02 00 00 00'), isA<FreezeFrameNoSnapshot>());
    });
    test('NO DATA from a vehicle that has answered is Unsupported', () {
      expect(ends('NO DATA'), isA<FreezeFrameUnsupported>());
    });
    test('NO DATA from a vehicle that has NOT answered anything is not "unsupported"', () {
      expect(ends('NO DATA', vehicleAnswered: false), isA<FreezeFrameNoAnswer>());
    });
    test('an explicit "not supported" refusal is Unsupported either way', () {
      expect(ends('7F 02 12', vehicleAnswered: false), isA<FreezeFrameUnsupported>());
    });
    test('silence is NoAnswer — never NoSnapshot, never Unsupported', () {
      for (final s in ['TIMEOUT', '', null, 'UNABLE TO CONNECT', 'BUS INIT: ...ERROR']) {
        expect(ends(s), isA<FreezeFrameNoAnswer>(), reason: '$s');
      }
    });
    test('garbage is NoAnswer, with a reason that says unreadable', () {
      final r = ends('42 02 00 03');
      expect(r, isA<FreezeFrameNoAnswer>());
      expect((r as FreezeFrameNoAnswer).reason, startsWith('unreadable'));
    });
    test('a refusal that is not "not supported" is Refused with its code', () {
      final r = ends('7F 02 22');
      expect(r, isA<FreezeFrameRefused>());
      expect((r as FreezeFrameRefused).nrc, 0x22);
    });
  });
}
