/// Phase 1B — one named test per scenario moved by this phase (numbers and
/// definitions: chore/fault-audit:docs/faults/SCENARIO_COVERAGE.md). See
/// docs/faults/PHASE1B_SCENARIOS.md. Simulators and the real bundled pack;
/// no real bike.
library;

import 'dart:io';

import 'package:danlite_elm/knowledge/clear_record.dart';
import 'package:danlite_elm/knowledge/code_lookup.dart';
import 'package:danlite_elm/knowledge/fault_resolver.dart';
import 'package:danlite_elm/knowledge/history_recorder.dart';
import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/knowledge/knowledge_service.dart';
import 'package:danlite_elm/knowledge/knowledge_store.dart';
import 'package:danlite_elm/knowledge/legacy_text.dart';
import 'package:danlite_elm/knowledge/scan_history.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/screens/dtc_screen.dart' show clearOutcomeMessageKey;
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_sim.dart';
import 'support/kb_pack_builder.dart';
import 'support/knowledge_harness.dart';

const fast = FaultReadTiming.scaled(0.05);
FaultRecord obd(String c) =>
    FaultRecord.fromObdCode(c, source: ReadSource.mode03, readAt: DateTime.utc(2026, 10, 2));

void main() {
  test('Scenario 15: a refused or ineffective clear is now recorded, '
      'while the rider still reads the one success message', () async {
    final k = await startedKnowledge();
    final sim = EngineSim(mode03: '7E8 04 43 01 01 20')..extra['04'] = '7E8 03 7F 04 22';
    final o = await connectSim(sim, timing: fast);
    await o.readEngineDtcs();
    await o.whenEngineReadSettled();
    final pre = PreClearSnapshot.capture(o, DateTime.now());
    final ok = await o.clearDtcs();
    expect(ok, isFalse);
    expect(o.lastClearOutcome, ClearDtcsOutcome.refused);
    expect(clearOutcomeMessageKey(ok, o.lastClearOutcome), 'clearSucceeded',
        reason: 'owner rule: the rider-visible message is unchanged');
    final outcome = await ClearCodesRecorder(obd: o, knowledge: k, vehicle: VehicleSnapshot.none)
        .verifyAndRecord(pre, clearOutcome: o.lastClearOutcome);
    expect(outcome, ClearCheckOutcome.codesReturned);
    final rec = (await k.history!.list(includeInternal: true)).single;
    expect(rec.kind, SessionKind.clearCheck);
    expect(rec.preClear!['codes'], ['P0120']);
    expect(rec.preClear!['clear_service_outcome'], 'refused');
    await o.disconnect();
    await sim.close();
    await k.store!.close();
  });

  test('Scenario 18: a language missing for a code falls back to English, '
      'visibly, and never to corrupted text', () async {
    final k = await startedKnowledge();
    // Hindi asked; take the bundled Hindi pack away so the store has only
    // English: English with the note.
    await k.store!.db.delete('kb_entry', where: "language = 'hi'");
    await k.store!.db.delete('kb_pack', where: "pack_id = 'generic_hi'");
    await k.reload();
    final hi = k.resolve(obd('P0120'), VehicleContext.generic, 'hi');
    expect(hi.languageUsed, 'en');
    expect(hi.languageFallback, isTrue);
    // A language with nothing at all (Bengali) behaves the same way.
    expect(k.resolve(obd('P0120'), VehicleContext.generic, 'bn').languageFallback, isTrue);
    // A partial Hindi row: missing fields named, still from English.
    final p = await buildPack(packId: 'generic_hi', language: 'hi', lines: [
      translatedLine('P0120', 'hi', {'title_hi': 'थ्रॉटल पोज़िशन सेंसर A: सर्किट में खराबी'}),
    ]);
    expect((await k.store!.importPack(
            manifestBytes: p.manifestBytes, entriesBytes: p.entriesBytes,
            source: PackSource.debug, appVersion: '1.0.0', allowDebug: true))
        .imported, isTrue);
    await k.reload();
    final partial = k.resolve(obd('P0120'), VehicleContext.generic, 'hi');
    expect(partial.languageUsed, 'hi');
    expect(partial.englishFields, contains('meaning'));
    await k.store!.close();
  });

  test('Scenario 19: offline, the bundled baseline answers and lookup works; '
      'updates are refused until signed packs arrive (Phase 3)', () async {
    // No adapter, no network: a fresh install.
    final k = await startedKnowledge();
    expect(k.state, KnowledgeState.ready);
    expect((await k.store!.pack('generic_en'))!.source, PackSource.bundled);
    final found = await searchCodes(parseLookupQuery('P0120'), store: k.store, language: 'en');
    expect(found.items.first.code, 'P0120');
    expect(k.resolve(obd('P0120'), VehicleContext.generic, 'en').level, ResolvedLevel.l4Generic);
    // A newer pack arriving as a download is refused: no production key yet.
    final newer = await buildPack(lines: seedLines(), version: kBundledEnVersion + 1);
    final r = await k.store!.importPack(
        manifestBytes: newer.manifestBytes, entriesBytes: newer.entriesBytes,
        source: PackSource.downloaded, appVersion: '1.0.0');
    expect(r.refusal, ImportRefusal.noProductionKey);
    expect((await k.store!.pack('generic_en'))!.version, kBundledEnVersion);
    // The app makes no network call for knowledge.
    for (final f in Directory('lib/knowledge').listSync().whereType<File>()) {
      expect(f.readAsStringSync().contains(RegExp(r'HttpClient|package:http|Supabase|functions\.invoke')),
          isFalse, reason: f.path);
    }
    await k.store!.close();
  });

  test('Scenario 20: an unknown or wrong model never borrows another make\'s meaning', () {
    final r = FaultResolver(
        index: KnowledgeIndex([
          for (final l in seedLines())
            KbEntry(
                contentId: l['content_id'] as String, code: l['code'] as String,
                scopeKind: ScopeKind.generic, language: 'en',
                title: l['title_en'] as String, verification: 'ai_authored_from_standard_title',
                packId: 'generic_en'),
        ]),
        legacy: legacyEngineText);
    // The default profile identifies nothing.
    final unknown = VehicleContext.fromProfile(make: 'Unknown', model: 'Vehicle');
    expect(unknown.platformKey, isNull);
    // Engine P1xxx: never the legacy JSON's fixed (often GM) text.
    final p1 = r.resolve(obd('P1100'), unknown, 'en', domain: FaultDomain.engine);
    expect(p1.title, isNull);
    expect(p1.structure!.manufacturerDefined, isTrue);
    // A Classic 350 ABS code read on a bike typed as an unknown RE model.
    final himalayan = VehicleContext.fromProfile(make: 'Royal Enfield', model: 'Himalayan');
    expect(r.resolve(obd('C1015'), himalayan, 'en', domain: FaultDomain.abs).title, isNull);
    // The same number on two Royal Enfield platforms: each its own meaning.
    final c = r.resolve(obd('C1052'),
        VehicleContext.fromProfile(make: 'Royal Enfield', model: 'Classic 350'), 'en',
        domain: FaultDomain.abs);
    final b = r.resolve(obd('C1052'),
        VehicleContext.fromProfile(make: 'Royal Enfield', model: 'Bullet EFI'), 'en',
        domain: FaultDomain.abs);
    expect(c.title, isNot(b.title));
    // A Honda blink pattern on a Royal Enfield profile: raw only.
    final blink = r.resolve(FaultRecord.manual('4-3', format: DtcFormat.blink, readAt: DateTime.now()),
        himalayan, 'en');
    expect(blink.level, ResolvedLevel.l6Raw);
  });
}
