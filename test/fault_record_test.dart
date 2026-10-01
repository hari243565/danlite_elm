/// Phase 1A — A1: the canonical fault record and its adapters.
library;

import 'package:danlite_elm/constants/obd_pids.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/models/vehicle_data.dart';
import 'package:danlite_elm/services/fault_decoders.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime(2026, 10, 1, 9, 30);

void main() {
  group('A1 FaultRecord basics', () {
    test('SAE two-byte encode is the exact inverse of the shared decoder', () {
      for (var hi = 0; hi < 256; hi += 7) {
        for (var lo = 0; lo < 256; lo += 13) {
          final code = ObdParser.decodeDtcPair(hi, lo);
          if (code == null) continue;
          expect(encodeSae2(code), [hi, lo], reason: code);
        }
      }
      expect(encodeSae2('X1234'), isNull);
      expect(encodeSae2('P01'), isNull);
    });

    test('system letter comes from the code', () {
      expect(FaultRecord.fromObdCode('P0133', source: ReadSource.mode03, readAt: t0).system,
          FaultSystem.powertrain);
      expect(FaultRecord.fromObdCode('C1058', source: ReadSource.mode03, readAt: t0).system,
          FaultSystem.chassis);
      expect(FaultRecord.fromObdCode('B0001', source: ReadSource.mode03, readAt: t0).system,
          FaultSystem.body);
      expect(FaultRecord.fromObdCode('U0100', source: ReadSource.mode03, readAt: t0).system,
          FaultSystem.network);
    });

    test('codes are normalised', () {
      final r = FaultRecord.fromObdCode(' p0133 ', source: ReadSource.mode03, readAt: t0);
      expect(r.code, 'P0133');
      expect(r.rawBytes, [0x01, 0x33]);
      expect(r.format, DtcFormat.sae2);
      expect(r.readAt, t0);
    });
  });

  group('A1 status from each read source', () {
    test('Mode 03 is Stored; active is UNKNOWN; never History', () {
      final r = FaultRecord.fromObdCode('P0133', source: ReadSource.mode03, readAt: t0);
      expect(r.status.confirmed, isTrue);
      expect(r.status.active, isNull, reason: 'unknown, not "no"');
      expect(r.status.history, isNull, reason: 'a Mode 03 code is never History');
      expect(r.status.pending, isNull);
      expect(r.status.lampRequested, isNull);
      expect(r.status.permanent, isNull);
    });

    test('Mode 07 is Pending, Mode 0A is Permanent, nothing else claimed', () {
      final p = FaultRecord.fromObdCode('P0301', source: ReadSource.mode07, readAt: t0);
      expect(p.status.pending, isTrue);
      expect(p.status.confirmed, isNull);
      final q = FaultRecord.fromObdCode('P0420', source: ReadSource.mode0A, readAt: t0);
      expect(q.status.permanent, isTrue);
      expect(q.status.confirmed, isNull);
      expect(q.status.active, isNull);
    });

    test('UDS status byte sets every flag, known true or known false', () {
      const rec = Uds19Record(
          code: 'C1058', dtcHigh: 0x50, dtcMid: 0x58, failureType: 0x11, status: 0x89, ecuId: '7B8');
      final r = FaultRecord.fromUds19(rec, readAt: t0, module: 'ABS 0x7B0');
      expect(r.format, DtcFormat.uds3);
      expect(r.source, ReadSource.uds19);
      expect(r.rawBytes, [0x50, 0x58, 0x11]);
      expect(r.failureType, 0x11);
      expect(r.statusByte, 0x89);
      expect(r.status.active, isTrue);
      expect(r.status.confirmed, isTrue);
      expect(r.status.lampRequested, isTrue);
      expect(r.status.pending, isFalse);
      expect(r.status.history, isFalse);
      expect(r.module, 'ABS 0x7B0');
      expect(r.displayCode, 'C1058-11');
    });
  });

  group('A1 adapters from the existing parse results', () {
    test('from UdsDtcRecord (the ABS parser\'s own type)', () {
      const rec = UdsDtcRecord(code: 'C1015', failureTypeByte: 0x04, statusByte: 0x08);
      final r = FaultRecord.fromUdsDtcRecord(rec, readAt: t0);
      expect(r.code, 'C1015');
      expect(r.failureType, 4);
      expect(r.status.history, isTrue);
      expect(r.rawBytes, [0x50, 0x15, 0x04]);
    });

    test('from DtcCode: engine and chassis', () {
      const engine = DtcCode(
          code: 'P0133', description: '', possibleCause: '', severity: 'unknown', action: '');
      final e = FaultRecord.fromDtcCode(engine, readAt: t0);
      expect(e.source, ReadSource.mode03);
      expect(e.status.confirmed, isTrue);

      const chassis = DtcCode(
          code: 'C1058',
          description: '',
          possibleCause: '',
          severity: 'critical',
          action: '',
          module: 'chassis',
          failureTypeByte: 0x00,
          statusByte: 0x2F);
      final c = FaultRecord.fromDtcCode(chassis, readAt: t0);
      expect(c.source, ReadSource.uds19);
      expect(c.status.active, isTrue);
      expect(c.statusByte, 0x2F);
    });

    test('from the typed OBD decoder, module kept', () {
      final d = decodeObdDtcReply('7E8 04 43 01 01 33',
          service: 0x03, framing: DtcFraming.iso15765) as ObdDtcCodes;
      final r = FaultRecord.fromDecodedObd(d.codes.single,
          source: ReadSource.mode03, readAt: t0);
      expect(r.module, '7E8');
      expect(r.rawBytes, [0x01, 0x33]);
    });

    test('manual formats: hex-H and blink', () {
      final h = FaultRecord.manual('C1058', format: DtcFormat.hexH, readAt: t0);
      expect(h.format, DtcFormat.hexH);
      expect(h.source, ReadSource.manual);
      final b = FaultRecord.manual('4-2', format: DtcFormat.blink, readAt: t0);
      expect(b.code, '4-2');
      expect(b.system, isNull);
    });

    test('a DtcCode can carry its record (the screen adapter)', () {
      final r = FaultRecord.fromObdCode('P0133', source: ReadSource.mode03, readAt: t0);
      final c = DtcCode(
          code: 'P0133', description: '', possibleCause: '', severity: 'unknown', action: '',
          record: r);
      expect(c.record, same(r));
    });
  });

  group('A1 merging Mode 03, 07 and 0A', () {
    FaultRecord rec(String code, ReadSource s) =>
        FaultRecord.fromObdCode(code, source: s, readAt: t0);

    test('one card per code; statuses combined; nothing invented', () {
      final merged = mergeEngineRecords(
        stored: [rec('P0133', ReadSource.mode03), rec('P0420', ReadSource.mode03)],
        pending: [rec('P0133', ReadSource.mode07), rec('P0301', ReadSource.mode07)],
        permanent: [rec('P0420', ReadSource.mode0A), rec('P0171', ReadSource.mode0A)],
      );
      final byCode = {for (final r in merged) r.code: r};
      expect(byCode.keys, ['P0133', 'P0420', 'P0301', 'P0171']);

      expect(byCode['P0133']!.status.confirmed, isTrue);
      expect(byCode['P0133']!.status.pending, isTrue);
      expect(byCode['P0133']!.status.permanent, isNull);
      expect(byCode['P0133']!.sources, {ReadSource.mode03, ReadSource.mode07});

      expect(byCode['P0420']!.status.permanent, isTrue);
      expect(byCode['P0420']!.status.confirmed, isTrue);

      expect(byCode['P0301']!.status.pending, isTrue);
      expect(byCode['P0301']!.status.confirmed, isNull,
          reason: 'a pending-only code is not claimed stored');

      expect(byCode['P0171']!.status.permanent, isTrue);
      for (final r in merged) {
        expect(r.status.history, isNull);
        expect(r.status.active, isNull);
      }
    });

    test('empty inputs merge to empty', () {
      expect(mergeEngineRecords(stored: const [], pending: const [], permanent: const []),
          isEmpty);
    });
  });
}
