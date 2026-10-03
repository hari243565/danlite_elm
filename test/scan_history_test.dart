/// Phase 1B — B4 startup import and B8 scan history: saving, coalescing,
/// retention, clock oddities, no VIN, deletion, the share report, and the
/// recorder that saves real engine and ABS reads over the simulator.
library;

import 'dart:convert';
import 'dart:io';

import 'package:danlite_elm/knowledge/fault_resolver.dart';
import 'package:danlite_elm/knowledge/history_recorder.dart';
import 'package:danlite_elm/knowledge/history_report.dart';
import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/knowledge/knowledge_service.dart';
import 'package:danlite_elm/knowledge/knowledge_store.dart';
import 'package:danlite_elm/knowledge/scan_history.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_sim.dart';
import 'support/kb_pack_builder.dart';
import 'support/knowledge_harness.dart';

const fast = FaultReadTiming.scaled(0.05);
final t0 = DateTime.utc(2026, 10, 2, 12);

ScanSessionInput session(DateTime at,
        {String reach = 'answered',
        List<String> codes = const <String>[],
        String? conn = 'c1',
        bool coalesce = true,
        SessionKind kind = SessionKind.engine,
        String? label}) =>
    ScanSessionInput(
      kind: kind,
      startedAt: at,
      reachState: reach,
      connectionId: conn,
      coalesce: coalesce,
      vehicleLabel: label,
      faults: [
        for (final c in codes)
          ScanFaultInput(FaultRecord.fromObdCode(c, source: ReadSource.mode03, readAt: at)),
      ],
    );

/// Every text value in every table, for the "no VIN anywhere" check.
Future<String> dumpAll(KnowledgeService k) async {
  final db = k.store!.db;
  final b = StringBuffer();
  for (final t in ['scan_session', 'scan_fault']) {
    for (final r in await db.query(t)) {
      b.writeln(jsonEncode(r));
    }
  }
  return b.toString();
}

void main() {
  group('B4 startup import', () {
    test('first start imports the bundled pack; the second start does not', () async {
      final path = await tempDbPath();
      final k1 = knowledgeAt(path);
      expect(k1.state, KnowledgeState.loading);
      await k1.start();
      expect(k1.state, KnowledgeState.ready);
      expect(k1.bundledImport!.imported, isTrue);
      expect(k1.resolve(FaultRecord.manual('P0120', format: DtcFormat.sae2, readAt: t0),
              VehicleContext.generic, 'en').level,
          ResolvedLevel.l4Generic);
      await k1.store!.close();
      final k2 = knowledgeAt(path);
      await k2.start();
      expect(k2.bundledImport, isNull, reason: 'installed version is current');
      expect(k2.state, KnowledgeState.ready);
      expect((await k2.store!.activeEntries()).length, 616);
      await k2.store!.close();
    });

    test('a newer installed (downloaded) version is never downgraded by the bundled one', () async {
      final path = await tempDbPath();
      final k = knowledgeAt(path);
      await k.start();
      final v5 = await buildPack(lines: seedLines().take(3).toList(), version: 5);
      expect((await k.store!.importPack(
              manifestBytes: v5.manifestBytes, entriesBytes: v5.entriesBytes,
              source: PackSource.debug, appVersion: '1.0.0', allowDebug: true))
          .imported, isTrue);
      await k.store!.close();
      final again = knowledgeAt(path);
      await again.start();
      expect(again.bundledImport, isNull);
      expect((await again.store!.pack('generic_en'))!.version, 5);
      await again.store!.close();
    });

    test('if the store cannot open, the resolver still answers honestly', () async {
      final k = KnowledgeService(
          openStore: () async => throw const FileSystemException('disk'),
          loadAsset: (p) => File(p).readAsBytes());
      await k.start();
      expect(k.state, KnowledgeState.failed);
      expect(k.history, isNull);
      final r = k.resolve(FaultRecord.manual('P1120', format: DtcFormat.sae2, readAt: t0),
          VehicleContext.generic, 'en');
      expect(r.structure!.manufacturerDefined, isTrue);
    });

    test('the database lives in the no-backup folder (Kotlin channel)', () {
      final kt = File('android/app/src/main/kotlin/com/danlite/elm/MainActivity.kt')
          .readAsStringSync();
      expect(kt, contains('"knowledgeDirectory"'));
      expect(kt, contains('File(noBackupFilesDir, "knowledge")'));
      final dart = File('lib/knowledge/knowledge_service.dart').readAsStringSync();
      expect(dart, contains("invokeMethod<String>('knowledgeDirectory')"));
      expect(dart, contains('return inMemoryDatabasePath;'),
          reason: 'never fall back to a backed-up folder on Android');
    });
  });

  group('B8 saving', () {
    late KnowledgeService k;
    var now = t0;
    setUp(() async {
      now = t0;
      k = await startedKnowledge(clock: () => now);
    });
    tearDown(() => k.store!.close());

    test('a read is saved with its codes, and reads back', () async {
      final id = await k.history!.save(session(t0, codes: ['P0120', 'U0100']));
      final s = (await k.history!.session(id))!;
      expect(s.reachState, 'answered');
      expect(s.faults.map((f) => f.code), ['P0120', 'U0100']);
      expect(s.faults.first.toRecord().status.confirmed, isTrue);
    });

    test('a did-not-answer read is saved too', () async {
      await k.history!.save(session(t0, reach: 'no_answer'));
      expect((await k.history!.list()).single.reachState, 'no_answer');
    });

    test('identical automatic re-reads on one connection fold into one session', () async {
      for (var i = 0; i < 10; i++) {
        await k.history!.save(session(t0.add(Duration(seconds: 5 * i)), codes: ['P0120']));
      }
      final all = await k.history!.list();
      expect(all, hasLength(1));
      expect(all.single.repeatCount, 10);
      expect(all.single.lastSeenAt, t0.add(const Duration(seconds: 45)));
    });

    test('a change, a new connection, or a non-coalescing save starts a new session', () async {
      await k.history!.save(session(t0, codes: ['P0120']));
      await k.history!.save(session(t0, codes: ['P0120', 'P0300']));
      await k.history!.save(session(t0, codes: ['P0120', 'P0300'], conn: 'c2'));
      await k.history!.save(session(t0, codes: ['P0120', 'P0300'], conn: 'c2', coalesce: false));
      expect(await k.history!.list(), hasLength(4));
    });

    test('Clear Codes records are internal: stored, not listed', () async {
      await k.history!.save(session(t0, kind: SessionKind.clearCheck, reach: 'codes_returned'));
      expect(await k.history!.list(), isEmpty);
      expect(await k.history!.list(includeInternal: true), hasLength(1));
    });

    test('no VIN can be stored, even typed into the vehicle name', () async {
      await k.history!.save(session(t0, label: 'Classic 350 ME3U3K5C1KD012345'));
      final dump = await dumpAll(k);
      expect(dump.contains('ME3U3K5C1KD012345'), isFalse);
      expect((await k.history!.list()).single.vehicleLabel, 'Classic 350 •••');
    });

    test('Delete all removes every session and every code', () async {
      await k.history!.save(session(t0, codes: ['P0120']));
      await k.history!.save(session(t0, kind: SessionKind.clearCheck, reach: 'x'));
      await k.history!.deleteAll();
      expect(await k.history!.list(includeInternal: true), isEmpty);
      expect(await k.store!.db.query('scan_fault'), isEmpty);
    });
  });

  group('B8 retention and clock oddities', () {
    late KnowledgeService k;
    var now = t0;
    setUp(() async {
      now = t0;
      k = await startedKnowledge(clock: () => now);
    });
    tearDown(() => k.store!.close());

    test('keeps the newest 50 sessions, faults of pruned sessions go too', () async {
      for (var i = 0; i < 60; i++) {
        now = t0.add(Duration(minutes: i));
        await k.history!.save(session(now, codes: ['P0120'], coalesce: false));
      }
      final all = await k.history!.list();
      expect(all, hasLength(kHistoryMaxSessions));
      expect(all.last.startedAt, t0.add(const Duration(minutes: 10)));
      final faults = await k.store!.db.query('scan_fault');
      expect(faults, hasLength(kHistoryMaxSessions));
    });

    test('drops sessions older than 180 days', () async {
      await k.history!.save(session(t0, coalesce: false));
      now = t0.add(const Duration(days: 181));
      await k.history!.save(session(now, coalesce: false));
      final all = await k.history!.list();
      expect(all, hasLength(1));
      expect(all.single.startedAt, now);
    });

    test('a clock set backwards does not wipe history', () async {
      await k.history!.save(session(t0, coalesce: false));
      now = t0.subtract(const Duration(days: 400)); // phone clock reset to 2025
      await k.history!.save(session(now, coalesce: false));
      expect(await k.history!.list(), hasLength(2));
    });

    test('the count cap goes by insertion order, not by clock', () async {
      for (var i = 0; i < 55; i++) {
        // Wildly jumping timestamps inside the 180-day window.
        now = t0.subtract(Duration(days: (i * 37) % 170));
        await k.history!.save(session(now, codes: ['P0${100 + i}'], coalesce: false));
      }
      final all = await k.history!.list();
      expect(all, hasLength(50));
      expect(all.first.faults.single.code, 'P0154', reason: 'the last one saved');
    });

    test('the session just saved is never pruned', () async {
      now = t0;
      final id = await k.history!.save(
          session(t0.subtract(const Duration(days: 300)), coalesce: false));
      expect(await k.history!.session(id), isNotNull);
    });

    test('times are stored as UTC, so a timezone change does not move them', () async {
      final local = DateTime(2026, 10, 2, 18, 30); // phone-local time
      final id = await k.history!.save(session(local));
      final s = (await k.history!.session(id))!;
      expect(s.startedAt.isUtc, isTrue);
      expect(s.startedAt, local.toUtc());
    });
  });

  test('B8 a bundled import and a history save at the same moment both land', () async {
    final k = await startedKnowledge();
    final v2 = await buildPack(lines: seedLines(), version: kBundledEnVersion + 1);
    final results = await Future.wait<Object>([
      k.store!.importPack(
          manifestBytes: v2.manifestBytes, entriesBytes: v2.entriesBytes,
          source: PackSource.debug, appVersion: '1.0.0', allowDebug: true),
      for (var i = 0; i < 5; i++)
        k.history!.save(session(t0.add(Duration(seconds: i)), codes: ['P0120'], coalesce: false)),
    ]);
    expect((results.first as ImportOutcome).imported, isTrue);
    expect(await k.history!.list(), hasLength(5));
    expect((await k.store!.activeEntries()).length, 616);
    await k.store!.close();
  });

  test('B8 Share text: plain, no VIN, no internal records, codes with meanings', () async {
    final k = await startedKnowledge();
    await k.history!.save(session(t0, codes: ['P0120'], label: 'Royal Enfield Classic 350'));
    await k.history!.save(session(t0, kind: SessionKind.clearCheck, reach: 'codes_returned'));
    await k.history!.save(session(t0, reach: 'no_answer', conn: 'c9'));
    final text = buildHistoryReport(await k.history!.list(includeInternal: true),
        tr: (key) => key, meaning: (f, _) => 'M(${f.code})');
    expect(text, contains('historyShareHeader'));
    expect(text, contains('P0120: M(P0120)'));
    expect(text, contains('historyReach_no_answer'));
    expect(text, contains('Royal Enfield Classic 350'));
    expect(text.contains('codes_returned'), isFalse, reason: 'clear records stay internal');
    await k.store!.close();
  });

  group('B8 the recorder saves real reads over the simulator', () {
    test('engine answered, then silent; ABS scan; never a VIN', () async {
      final k = await startedKnowledge();
      final sim = EngineSim(mode03: '7E8 04 43 01 01 20')
        ..extra['0902'] = '7E8 10 14 49 02 01 4D 45 33\r7E8 21 55 33 4B 35 43 31 4B\r7E8 22 44 30 31 32 33 34 35'
        ..udsModules['7B0'] = '7B8 07 59 02 FF 50 15 00 2F';
      final obd = await connectSim(sim, timing: fast);
      final rec = HistoryRecorder(
          obd: obd,
          knowledge: k,
          vehicle: () => VehicleSnapshot(
              profileId: 'p1',
              label: 'Royal Enfield Classic 350',
              context: VehicleContext.fromProfile(make: 'Royal Enfield', model: 'Classic 350')))
        ..attach();
      await obd.readEngineDtcs(forceExtras: true);
      await obd.whenEngineReadSettled();
      sim.mode03 = null; // the bike stops answering
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
      await obd.readChassisDtcs(vehicleMake: 'Royal Enfield', vehicleModel: 'Classic 350');
      await rec.idle;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await rec.idle;
      final all = await k.history!.list();
      expect(all.map((s) => '${s.kind.db}:${s.reachState}'),
          ['abs:faults_found', 'engine:no_answer', 'engine:answered']);
      final engine = all.last;
      expect(engine.faults.single.code, 'P0120');
      expect(engine.faults.single.resolvedLevel, 'l4Generic');
      expect(engine.faults.single.resolvedContentId, 'generic:P0120:en');
      expect(engine.profileId, 'p1');
      expect(engine.adapterClass, 'ELM327 v1.5');
      expect(all.first.faults.single.resolvedLevel, 'l2Platform');
      expect(obd.engineReport?.vin.valueOrNull, isNotNull, reason: 'the VIN WAS read');
      final dump = await dumpAll(k);
      expect(dump.contains('ME3U3K5C1KD012345'), isFalse);
      expect(dump.toUpperCase().contains('VIN'), isFalse);
      rec.detach();
      await obd.disconnect();
      await sim.close();
      await k.store!.close();
    });
  });
}
