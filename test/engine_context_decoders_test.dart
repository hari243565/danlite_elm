/// Phase A-4 (C1–C3) — the pure decoders for the context reads.
///
/// SAE J1979, as published in public references (re-check against the
/// standard before release):
///   Mode 01 PID 21 distance with the lamp on, 31 distance since codes cleared
///   (256A+B km); 4D time with the lamp on, 4E time since cleared (256A+B
///   minutes); 30 warm-ups since cleared (A). Maximum 65,535.
///   Mode 02 returns the same PIDs as when the last fault was recorded; the
///   reply is `42 <pid> <frame> <data>`; PID 02 is the trigger code and
///   `0000` means there is NO snapshot.
///   PID 01 01 bytes B, C, D: the emission self-check support / not-complete
///   flags.
library;

import 'package:danlite_elm/services/engine_context.dart';
import 'package:danlite_elm/services/fault_decoders.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every way the same four bytes reach the app: spaces off or on, with an
/// 11-bit header and a length byte, with a 29-bit header (joined or spaced),
/// and with the numbered multi-line form's single-frame equivalent.
List<String> shapes(String payload) {
  final bytes = payload.split(' ');
  final len = bytes.length.toRadixString(16).padLeft(2, '0').toUpperCase();
  return [
    payload,
    payload.replaceAll(' ', ''),
    '7E8 $len $payload',
    '7E8$len${payload.replaceAll(' ', '')}',
    '18DAF110 $len $payload',
    '18 DA F1 10 $len $payload',
    'SEARCHING...\r7E8 $len $payload\r\r',
  ];
}

T value<T>(Decoded<T> d) {
  expect(d, isA<DecodedValue<T>>(), reason: '$d');
  return (d as DecodedValue<T>).value;
}

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // C2 counters
  // ══════════════════════════════════════════════════════════════════════
  group('C2 counters: the vectors the brief names (0, 1, 255, 256, 65,535)', () {
    const twoByte = <(String, int)>[
      ('00 00', 0),
      ('00 01', 1),
      ('00 FF', 255),
      ('01 00', 256),
      ('FF FE', 65534),
      ('FF FF', 65535),
    ];
    for (final c in [
      ContextCounter.lampDistance,
      ContextCounter.clearedDistance,
      ContextCounter.lampTime,
      ContextCounter.clearedTime,
    ]) {
      final pid = c.pid.toRadixString(16).toUpperCase().padLeft(2, '0');
      for (final (data, expected) in twoByte) {
        test('${c.name} 41 $pid $data = $expected', () {
          for (final shape in shapes('41 $pid $data')) {
            final v = value(decodeContextCounter(shape, c));
            expect(v.value, expected, reason: shape);
            expect(v.max, 65535);
            expect(v.atLeast, expected == 65535, reason: 'only the maximum is "at least"');
          }
        });
      }
    }

    for (final (data, expected) in const [('00', 0), ('01', 1), ('FE', 254), ('FF', 255)]) {
      test('warm-ups 41 30 $data = $expected', () {
        for (final shape in shapes('41 30 $data')) {
          final v = value(decodeContextCounter(shape, ContextCounter.warmUps));
          expect(v.value, expected, reason: shape);
          expect(v.max, 255);
          expect(v.atLeast, expected == 255);
        }
      });
    }

    test('256A+B uses the first byte as the high byte', () {
      expect(value(decodeContextCounter('41 21 12 34', ContextCounter.lampDistance)).value,
          0x1234);
    });
  });

  group('C2 counters: every non-answer is its own typed state', () {
    final c = ContextCounter.lampDistance;
    test('NO DATA and not-supported refusals are "unsupported"', () {
      expect(decodeContextCounter('NO DATA', c), isA<DecodedUnsupported<CounterValue>>());
      expect(decodeContextCounter('7F 01 12', c), isA<DecodedUnsupported<CounterValue>>());
      expect(decodeContextCounter('7E8 03 7F 01 31', c), isA<DecodedUnsupported<CounterValue>>());
      expect(decodeContextCounter('?', c), isA<DecodedUnsupported<CounterValue>>());
    });
    test('silence is NOT "unsupported"', () {
      for (final s in ['TIMEOUT', '', null, 'DISCONNECTED', 'UNABLE TO CONNECT', 'CAN ERROR']) {
        expect(decodeContextCounter(s, c), isA<DecodedNoAnswer<CounterValue>>(), reason: '$s');
      }
    });
    test('a refusal that is not "not supported" is a refusal', () {
      expect(decodeContextCounter('7F 01 22', c), isA<DecodedNegative<CounterValue>>());
      expect(decodeContextCounter('7F 01 21', c), isA<DecodedNegative<CounterValue>>());
    });
    test('a reply for another PID is not this PID', () {
      expect(decodeContextCounter('41 31 00 05', c), isNot(isA<DecodedValue<CounterValue>>()));
      expect(decodeContextCounter('41 21', c), isNot(isA<DecodedValue<CounterValue>>()));
    });
    test('too short, odd hex and garbage are unparseable, never a number', () {
      for (final s in ['41 21 05', '41 21 0', '4121 0G00', 'ZZ', '41 21 05 0']) {
        expect(decodeContextCounter(s, c), isNot(isA<DecodedValue<CounterValue>>()), reason: s);
      }
    });
    test('two modules that agree give the value; two that disagree give nothing', () {
      expect(value(decodeContextCounter('7E8 04 41 21 00 0A\r7E9 04 41 21 00 0A', c)).value, 10);
      expect(decodeContextCounter('7E8 04 41 21 00 0A\r7E9 04 41 21 00 0B', c),
          isA<DecodedUnparseable<CounterValue>>());
    });
    test('two unrelated lines are never stitched into one answer (found by the fuzz test)', () {
      // "7E8 41" then a stray continuation frame "7E8 23 21 00 41 00 00 31":
      // the shared reassembler would join them into `41 21 00 41` = 65.
      const stitched = '18 DA F1 10 7C B1 42 01\r7E8 41\r7E8 23 21 00 41 00 00 31';
      expect(decodeContextCounter(stitched, c), isNot(isA<DecodedValue<CounterValue>>()));
      expect(decodeContextCounter('7E8 41\r7E8 23 21 00 41', c),
          isNot(isA<DecodedValue<CounterValue>>()));
    });
    test('a response-pending frame ahead of the answer is skipped', () {
      expect(value(decodeContextCounter('7E8 03 7F 01 78\r7E8 04 41 21 00 07', c)).value, 7);
      expect(decodeContextCounter('7E8 03 7F 01 78', c), isA<DecodedNegative<CounterValue>>());
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // C3 readiness
  // ══════════════════════════════════════════════════════════════════════
  group('C3 readiness: the pure bit decode (byte B, C, D)', () {
    MonitorState s(ReadinessReport r, Monitor m) => r.states[m]!;

    test('everything supported and complete', () {
      final r = decodeReadinessBytes(0x00, 0x07, 0xFF, 0x00);
      for (final m in Monitor.values) {
        expect(s(r, m), MonitorState.complete, reason: '$m');
      }
      expect(r.compressionIgnition, isFalse);
    });

    test('everything supported and NOT complete', () {
      final r = decodeReadinessBytes(0x00, 0x77, 0xFF, 0xFF);
      for (final m in Monitor.values) {
        expect(s(r, m), MonitorState.notComplete, reason: '$m');
      }
    });

    test('nothing supported: every monitor says so, whatever the other bits are', () {
      final r = decodeReadinessBytes(0x00, 0x70, 0x00, 0xFF);
      for (final m in Monitor.values) {
        expect(s(r, m), MonitorState.notSupported, reason: '$m');
      }
    });

    test('byte B: bit 0/1/2 supported, bit 4/5/6 not complete (one at a time)', () {
      // misfire supported + not complete; fuel system unsupported; components
      // supported + complete.
      final r = decodeReadinessBytes(0x00, 0x15, 0x00, 0x00);
      expect(s(r, Monitor.misfire), MonitorState.notComplete);
      expect(s(r, Monitor.fuelSystem), MonitorState.notSupported);
      expect(s(r, Monitor.components), MonitorState.complete);
      // A stale "not complete" bit on a monitor the bike does not support is
      // not a statement about that monitor.
      final stale = decodeReadinessBytes(0x00, 0x20, 0x00, 0x00);
      expect(s(stale, Monitor.fuelSystem), MonitorState.notSupported);
    });

    test('bytes C and D: each bit is its own monitor, in the documented order', () {
      const order = [
        Monitor.catalyst, // bit 0
        Monitor.heatedCatalyst, // 1
        Monitor.evaporative, // 2
        Monitor.secondaryAir, // 3
        Monitor.acRefrigerant, // 4
        Monitor.oxygenSensor, // 5
        Monitor.oxygenSensorHeater, // 6
        Monitor.egr, // 7
      ];
      for (var bit = 0; bit < 8; bit++) {
        // Only this monitor supported, and complete.
        final supportedOnly = decodeReadinessBytes(0x00, 0x00, 1 << bit, 0x00);
        // Only this monitor supported, and not complete.
        final incomplete = decodeReadinessBytes(0x00, 0x00, 1 << bit, 1 << bit);
        // Not supported, but the bike set its not-complete bit anyway.
        final staleOnly = decodeReadinessBytes(0x00, 0x00, 0x00, 1 << bit);
        for (var i = 0; i < 8; i++) {
          final m = order[i];
          expect(s(supportedOnly, m),
              i == bit ? MonitorState.complete : MonitorState.notSupported,
              reason: 'bit $bit monitor $m');
          expect(s(incomplete, m),
              i == bit ? MonitorState.notComplete : MonitorState.notSupported);
          expect(s(staleOnly, m), MonitorState.notSupported);
        }
      }
    });

    test('byte A carries the lamp and the stored count', () {
      final r = decodeReadinessBytes(0x83, 0x00, 0x00, 0x00);
      expect(r.lampOn, isTrue);
      expect(r.storedCount, 3);
      final off = decodeReadinessBytes(0x02, 0x00, 0x00, 0x00);
      expect(off.lampOn, isFalse);
      expect(off.storedCount, 2);
    });

    test('compression ignition: the spark-ignition monitors do not apply', () {
      final r = decodeReadinessBytes(0x00, 0x0F, 0xFF, 0xFF);
      expect(r.compressionIgnition, isTrue);
      for (final m in [
        Monitor.catalyst, Monitor.heatedCatalyst, Monitor.evaporative,
        Monitor.secondaryAir, Monitor.acRefrigerant, Monitor.oxygenSensor,
        Monitor.oxygenSensorHeater, Monitor.egr,
      ]) {
        expect(s(r, m), MonitorState.notApplicable, reason: '$m');
      }
      // The three continuous monitors read the same way for both engine types.
      expect(s(r, Monitor.misfire), MonitorState.complete);
    });
  });

  group('C3 readiness: from the wire', () {
    test('41 01 83 07 E5 00 in every shape', () {
      // A=83 (lamp, 3 codes) B=07 (3 supported, spark, all complete)
      // C=E5 D=00 (supported: catalyst, evap, O2 sensor, O2 heater, EGR;
      // all complete)
      for (final shape in shapes('41 01 83 07 E5 00')) {
        final r = value(decodeReadiness(shape));
        expect(r.lampOn, isTrue, reason: shape);
        expect(r.states[Monitor.catalyst], MonitorState.complete);
        expect(r.states[Monitor.heatedCatalyst], MonitorState.notSupported);
        expect(r.states[Monitor.evaporative], MonitorState.complete);
        expect(r.states[Monitor.secondaryAir], MonitorState.notSupported);
        expect(r.states[Monitor.egr], MonitorState.complete);
      }
    });
    test('a bike that only sends A (no B, C, D) is unparseable, never "all complete"', () {
      expect(decodeReadiness('41 01 83'), isA<DecodedUnparseable<ReadinessReport>>());
      expect(decodeReadiness('41 01 83 07'), isA<DecodedUnparseable<ReadinessReport>>());
    });
    test('silence, NO DATA, refusals', () {
      expect(decodeReadiness('NO DATA'), isA<DecodedUnsupported<ReadinessReport>>());
      expect(decodeReadiness('TIMEOUT'), isA<DecodedNoAnswer<ReadinessReport>>());
      expect(decodeReadiness('7F 01 22'), isA<DecodedNegative<ReadinessReport>>());
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // C1 freeze frame
  // ══════════════════════════════════════════════════════════════════════
  group('C1 trigger code (mode 02, PID 02)', () {
    test('42 02 00 03 01 is P0301, in every shape', () {
      for (final shape in shapes('42 02 00 03 01')) {
        expect(value(decodeFreezeFrameTrigger(shape)).code, 'P0301', reason: shape);
      }
    });
    test('the other three families', () {
      expect(value(decodeFreezeFrameTrigger('42 02 00 40 35')).code, 'C0035');
      expect(value(decodeFreezeFrameTrigger('42 02 00 80 12')).code, 'B0012');
      expect(value(decodeFreezeFrameTrigger('42 02 00 C1 00')).code, 'U0100');
    });
    test('0000 means there is NO snapshot — not a code called P0000', () {
      for (final shape in shapes('42 02 00 00 00')) {
        final t = value(decodeFreezeFrameTrigger(shape));
        expect(t.code, isNull, reason: shape);
        expect(t.hasSnapshot, isFalse);
      }
    });
    test('NO DATA and not-supported refusals are unsupported', () {
      expect(decodeFreezeFrameTrigger('NO DATA'), isA<DecodedUnsupported<FreezeFrameTrigger>>());
      expect(decodeFreezeFrameTrigger('7F 02 12'), isA<DecodedUnsupported<FreezeFrameTrigger>>());
      expect(decodeFreezeFrameTrigger('7E8 03 7F 02 31'), isA<DecodedUnsupported<FreezeFrameTrigger>>());
    });
    test('silence is no answer; a real refusal is a refusal', () {
      expect(decodeFreezeFrameTrigger('TIMEOUT'), isA<DecodedNoAnswer<FreezeFrameTrigger>>());
      expect(decodeFreezeFrameTrigger(null), isA<DecodedNoAnswer<FreezeFrameTrigger>>());
      expect(decodeFreezeFrameTrigger('7F 02 22'), isA<DecodedNegative<FreezeFrameTrigger>>());
    });
    test('another frame number is not frame 0', () {
      expect(decodeFreezeFrameTrigger('42 02 01 03 01'),
          isA<DecodedUnparseable<FreezeFrameTrigger>>());
    });
    test('truncated and odd hex are unparseable', () {
      for (final s in ['42 02 00 03', '42 02 00', '42 02 00 03 0']) {
        expect(decodeFreezeFrameTrigger(s), isNot(isA<DecodedValue<FreezeFrameTrigger>>()),
            reason: s);
      }
    });
    test('a mode 01 reply is not a mode 02 reply', () {
      expect(decodeFreezeFrameTrigger('41 02 00 03 01'),
          isNot(isA<DecodedValue<FreezeFrameTrigger>>()));
    });
    test('two modules naming different codes → nothing is claimed', () {
      expect(decodeFreezeFrameTrigger('7E8 05 42 02 00 03 01\r7E9 05 42 02 00 03 02'),
          isA<DecodedUnparseable<FreezeFrameTrigger>>());
    });
  });

  group('C1 support list (mode 02, PID 00 / 40)', () {
    test('42 00 00 BE 1F A8 13', () {
      final set = value(decodeSupportedPids('42 00 00 BE 1F A8 13', service: 2, basePid: 0x00));
      expect(set, {1, 3, 4, 5, 6, 7, 12, 13, 14, 15, 16, 17, 19, 21, 28, 31, 32});
    });
    test('the 0x40 block holds PID 0x42', () {
      final set = value(decodeSupportedPids('42 40 00 40 00 00 00', service: 2, basePid: 0x40));
      expect(set, {0x42});
    });
    test('mode 01 uses the same bits, with no frame byte', () {
      final set = value(decodeSupportedPids('41 00 BE 3E B8 11', service: 1, basePid: 0x00));
      expect(set.containsAll([1, 3, 4, 5, 6, 7]), isTrue);
      expect(set.contains(2), isFalse);
    });
    test('NO DATA is unsupported, silence is no answer, short is unparseable', () {
      expect(decodeSupportedPids('NO DATA', service: 2, basePid: 0), isA<DecodedUnsupported<Set<int>>>());
      expect(decodeSupportedPids('TIMEOUT', service: 2, basePid: 0), isA<DecodedNoAnswer<Set<int>>>());
      expect(decodeSupportedPids('42 00 00 BE 1F', service: 2, basePid: 0),
          isA<DecodedUnparseable<Set<int>>>());
    });
  });

  group('C1 snapshot values reuse the live-data formulas and units', () {
    SnapshotNumber num_(String raw, SnapshotPid p) {
      final v = value(decodeFreezeFrameValue(raw, p));
      expect(v, isA<SnapshotNumber>());
      return v as SnapshotNumber;
    }

    test('engine load 42 04 00 80 → 50.2 %', () {
      final v = num_('42 04 00 80', SnapshotPid.engineLoad);
      expect(v.value, closeTo(50.2, 0.05));
      expect(v.unit, '%');
    });
    test('coolant 42 05 00 7B → 83 °C; 00 → -40 °C', () {
      expect(num_('42 05 00 7B', SnapshotPid.coolant).value, 83);
      expect(num_('42 05 00 7B', SnapshotPid.coolant).unit, '°C');
      expect(num_('42 05 00 00', SnapshotPid.coolant).value, -40);
    });
    test('fuel trims 80 = 0 %, 90 = +12.5 %, 70 = -12.5 %', () {
      expect(num_('42 06 00 80', SnapshotPid.shortTrim).value, 0);
      expect(num_('42 06 00 90', SnapshotPid.shortTrim).value, closeTo(12.5, 0.01));
      expect(num_('42 07 00 70', SnapshotPid.longTrim).value, closeTo(-12.5, 0.01));
    });
    test('intake pressure 42 0B 00 63 → 99 kPa', () {
      final v = num_('42 0B 00 63', SnapshotPid.intakePressure);
      expect(v.value, 99);
      expect(v.unit, 'kPa');
    });
    test('RPM 42 0C 00 0F A0 → 1000', () {
      final v = num_('42 0C 00 0F A0', SnapshotPid.rpm);
      expect(v.value, 1000);
      expect(v.unit, 'RPM');
    });
    test('speed 42 0D 00 3C → 60 km/h', () {
      final v = num_('42 0D 00 3C', SnapshotPid.speed);
      expect(v.value, 60);
      expect(v.unit, 'km/h');
    });
    test('intake air 42 0F 00 41 → 25 °C', () {
      expect(num_('42 0F 00 41', SnapshotPid.intakeTemp).value, 25);
    });
    test('throttle 42 11 00 FF → 100 %', () {
      expect(num_('42 11 00 FF', SnapshotPid.throttle).value, 100);
    });
    test('module voltage 42 42 00 36 B0 → 14.0 V', () {
      final v = num_('42 42 00 36 B0', SnapshotPid.moduleVoltage);
      expect(v.value, closeTo(14.0, 0.0005));
      expect(v.unit, 'V');
    });

    test('every shape of one value', () {
      for (final shape in shapes('42 0C 00 0F A0')) {
        expect(num_(shape, SnapshotPid.rpm).value, 1000, reason: shape);
      }
    });

    group('fuel system status (PID 03)', () {
      SnapshotFuelSystem fuel(String raw) {
        final v = value(decodeFreezeFrameValue(raw, SnapshotPid.fuelSystem));
        expect(v, isA<SnapshotFuelSystem>());
        return v as SnapshotFuelSystem;
      }

      test('each documented value', () {
        expect(fuel('42 03 00 01 00').system1, FuelStatusKind.openLoopCold);
        expect(fuel('42 03 00 02 00').system1, FuelStatusKind.closedLoop);
        expect(fuel('42 03 00 04 00').system1, FuelStatusKind.openLoopLoad);
        expect(fuel('42 03 00 08 00').system1, FuelStatusKind.openLoopFault);
        expect(fuel('42 03 00 10 00').system1, FuelStatusKind.closedLoopFault);
      });
      test('system 2 is shown only when the bike reports one', () {
        expect(fuel('42 03 00 02 00').system2, FuelStatusKind.none);
        expect(fuel('42 03 00 02 04').system2, FuelStatusKind.openLoopLoad);
      });
      test('a value outside the table is "unknown", never a guess', () {
        expect(fuel('42 03 00 03 00').system1, FuelStatusKind.unknown);
        expect(fuel('42 03 00 40 00').system1, FuelStatusKind.unknown);
      });
      test('zero means the bike reports no status', () {
        expect(fuel('42 03 00 00 00').system1, FuelStatusKind.none);
      });
    });

    test('short, wrong-PID and silent replies never become a number', () {
      expect(decodeFreezeFrameValue('42 0C 00 0F', SnapshotPid.rpm),
          isA<DecodedUnparseable<SnapshotValue>>());
      expect(decodeFreezeFrameValue('42 0D 00 3C', SnapshotPid.rpm),
          isNot(isA<DecodedValue<SnapshotValue>>()));
      expect(decodeFreezeFrameValue('NO DATA', SnapshotPid.rpm),
          isA<DecodedUnsupported<SnapshotValue>>());
      expect(decodeFreezeFrameValue('TIMEOUT', SnapshotPid.rpm),
          isA<DecodedNoAnswer<SnapshotValue>>());
      expect(decodeFreezeFrameValue('42 0C 02 0F A0', SnapshotPid.rpm),
          isA<DecodedUnparseable<SnapshotValue>>(),
          reason: 'frame 2 is not the frame that was asked for');
    });

    test('the fixed set is exactly the brief\'s, in this order', () {
      expect(SnapshotPid.values.map((p) => p.pid).toList(),
          [0x03, 0x04, 0x05, 0x06, 0x07, 0x0B, 0x0C, 0x0D, 0x0F, 0x11, 0x42]);
    });
  });
}
