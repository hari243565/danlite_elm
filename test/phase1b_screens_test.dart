/// Phase 1B — what the rider sees: B6 resolved guidance on the fault cards
/// (English, Hindi, fallback, every level), B7 code lookup (offline), B9 the
/// Clear Codes record (rider flow unchanged, three outcomes recorded), B10
/// the small fixes. The REAL ObdService over the simulator, the REAL screens,
/// a REAL KnowledgeService over SQLite with the real bundled pack.
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'dart:convert';
import 'dart:io';

import 'package:danlite_elm/constants/chassis_modules.dart';
import 'package:danlite_elm/knowledge/clear_record.dart';
import 'package:danlite_elm/knowledge/history_recorder.dart';
import 'package:danlite_elm/knowledge/code_lookup.dart';
import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/knowledge/knowledge_service.dart';
import 'package:danlite_elm/knowledge/scan_history.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/code_lookup_screen.dart';
import 'package:danlite_elm/screens/dtc_screen.dart';
import 'package:danlite_elm/screens/home_screen.dart' show ribbonStatusLabel;
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/engine_sim.dart';
import 'support/kb_pack_builder.dart';
import 'support/knowledge_harness.dart';

const fast = FaultReadTiming.scaled(0.05);
String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

class Env {
  Env(this.settings, this.vehicles, this.knowledge, this.obd, this.sim);
  final SettingsProvider settings;
  final VehicleProvider vehicles;
  final KnowledgeService? knowledge;
  final ObdService? obd;
  final EngineSim? sim;

  Widget wrap(Widget home) => MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<VehicleProvider>.value(value: vehicles),
          if (obd != null) ChangeNotifierProvider<ObdService>.value(value: obd!),
          ChangeNotifierProvider<KnowledgeService?>.value(value: knowledge),
        ],
        child: MaterialApp(home: home),
      );

  Future<void> close(WidgetTester tester) => tester.runAsync(() async {
        await obd?.disconnect();
        await sim?.close();
        await knowledge?.store?.close();
      });
}

/// Set up language, vehicle, knowledge (started unless [startKnowledge] is
/// false), and optionally read the engine / ABS over [sim].
Future<Env> setUp(WidgetTester tester,
    {String lang = 'en',
    String? make,
    String? model,
    EngineSim? sim,
    bool abs = false,
    bool knowledge = true,
    bool startKnowledge = true,
    Future<void> Function(KnowledgeService)? beforeRead}) async {
  late Env env;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = SettingsProvider();
    await settings.setLanguage(lang);
    final vehicles = VehicleProvider();
    if (make != null) {
      await vehicles.addVehicle(VehicleProfile(id: 'v1', name: '', make: make, model: model ?? ''));
    }
    KnowledgeService? k;
    if (knowledge) {
      k = knowledgeAt(await tempDbPath());
      if (startKnowledge) await k.start();
      if (beforeRead != null) await beforeRead(k);
    }
    ObdService? obd;
    if (sim != null) {
      obd = await connectSim(sim, timing: fast);
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
      if (abs) await obd.readChassisDtcs(vehicleMake: make, vehicleModel: model);
    }
    env = Env(settings, vehicles, k, obd, sim);
  });
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  return env;
}

List<String> texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .toList();

Future<List<String>> showDtc(WidgetTester tester, Env env, {bool abs = false}) async {
  await tester.pumpWidget(env.wrap(const DtcScreen(autoScan: false)));
  await tester.pump(const Duration(milliseconds: 50));
  if (abs) {
    await tester.tap(find.text(t('moduleAbs', env.settings.locale.languageCode)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  return texts(tester);
}

/// The bundled Hindi pack removed, so the store holds English only (the
/// "this entry has no Hindi yet" case, which the real content no longer has).
Future<void> dropBundledHindi(KnowledgeService k) async {
  await k.store!.db.delete('kb_entry', where: "language = 'hi'");
  await k.store!.db.delete('kb_pack', where: "pack_id = 'generic_hi'");
  await k.reload();
}

bool anyHas(List<String> xs, String s) => xs.any((x) => x.contains(s));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════════════
  // B6 fault cards
  // ══════════════════════════════════════════════════════════════════════
  group('B6 resolved guidance on the card', () {
    testWidgets('[en] store answer: title, meaning, causes, what to do, chip, '
        'can-ride, provenance + draft', (tester) async {
      final env = await setUp(tester, sim: EngineSim(mode03: '7E8 04 43 01 01 20'));
      final xs = await showDtc(tester, env);
      final e = seedLine('P0120');
      expect(xs, contains(e['title_en']));
      expect(xs, contains(e['meaning_en']));
      expect(xs, contains('• ${(e['likely_causes_en'] as List).first}'));
      expect(xs, contains(e['rider_advice_en']));
      expect(xs, contains(t('faultLikelyCauses').toUpperCase()));
      expect(xs, contains(t('riderActionServiceSoon')));
      expect(find.byIcon(Icons.build_rounded), findsOneWidget, reason: 'icon + word, not colour alone');
      expect(anyHas(xs, t('canRideWithCare')), isTrue);
      expect(xs, contains('${t('provenanceAi')}. ${t('provenanceDraft')}'));
      expect(xs, isNot(contains(t('severityUnknown'))));
      expect(xs.where((x) => x.isEmpty), isEmpty, reason: 'no empty rows');
      await env.close(tester);
    });

    testWidgets('[hi] English-only entry: Hindi chip and labels, "showing English" note',
        (tester) async {
      final env = await setUp(tester,
          lang: 'hi',
          sim: EngineSim(mode03: '7E8 04 43 01 01 20'),
          beforeRead: dropBundledHindi);
      final xs = await showDtc(tester, env);
      expect(xs, contains(seedLine('P0120')['title_en']));
      expect(xs, contains(t('riderActionServiceSoon', 'hi')));
      expect(xs, contains(t('faultShowingEnglish', 'hi')));
      expect(xs, contains('${t('provenanceAi', 'hi')}. ${t('provenanceDraft', 'hi')}'));
      await env.close(tester);
    });

    testWidgets('[hi] a partial Hindi pack: Hindi title, English rest, "partly English" note',
        (tester) async {
      const hiTitle = 'थ्रॉटल पोज़िशन सेंसर A: सर्किट में खराबी';
      final env = await setUp(tester,
          lang: 'hi',
          sim: EngineSim(mode03: '7E8 04 43 01 01 20'), beforeRead: (k) async {
        await dropBundledHindi(k);
        final p = await buildPack(packId: 'generic_hi', language: 'hi', lines: [
          translatedLine('P0120', 'hi', {'title_hi': hiTitle}),
        ]);
        expect((await k.store!.importPack(
                manifestBytes: p.manifestBytes, entriesBytes: p.entriesBytes,
                source: PackSource.debug, appVersion: '1.0.0', allowDebug: true))
            .imported, isTrue);
        await k.reload();
      });
      final xs = await showDtc(tester, env);
      expect(xs, contains(hiTitle));
      expect(xs, contains(seedLine('P0120')['meaning_en']));
      expect(xs, contains(t('faultPartlyEnglish', 'hi')));
      await env.close(tester);
    });

    testWidgets('L2: Classic 350 ABS code from the service manual', (tester) async {
      final env = await setUp(tester,
          make: 'Royal Enfield', model: 'Classic 350', abs: true,
          sim: EngineSim()..udsModules['7B0'] = '7B8 07 59 02 FF 50 15 00 2F');
      final xs = await showDtc(tester, env, abs: true);
      expect(xs, contains('ABS Pump/Motor Failure'));
      expect(xs, contains('Change ABS unit'));
      expect(xs, contains(t('provenanceManual')));
      await env.close(tester);
    });

    testWidgets('L3: Bosch 0x5200 from a dealer readout', (tester) async {
      final env = await setUp(tester,
          make: 'Bajaj', model: 'Dominar 400', abs: true,
          sim: EngineSim()..udsModules['7B0'] = '7B8 07 59 02 FF 52 00 00 2F');
      final xs = await showDtc(tester, env, abs: true);
      expect(anyHas(xs, 'EEPROM'), isTrue);
      expect(xs, contains(t('provenanceDealerReadout')));
      await env.close(tester);
    });

    testWidgets('L6: any other Bosch value is raw only, with the dealer note', (tester) async {
      final env = await setUp(tester,
          make: 'Yamaha', model: 'R15', abs: true,
          sim: EngineSim()..udsModules['7B0'] = '7B8 07 59 02 FF 50 43 00 2F');
      final xs = await showDtc(tester, env, abs: true);
      expect(xs, contains(t('absRawUnverifiedDesc')));
      expect(xs, contains('0x5043'));
      expect(xs, contains(t('provenanceRaw')));
      await env.close(tester);
    });

    testWidgets('L4 older table (no store entry): old rows kept, labelled as older text',
        (tester) async {
      final env = await setUp(tester, sim: EngineSim(mode03: '7E8 04 43 01 01 00'));
      final xs = await showDtc(tester, env);
      expect(xs, contains(t('possibleCause').toUpperCase()));
      expect(xs, contains(t('provenanceLegacyTable')));
      await env.close(tester);
    });

    testWidgets('L5: a standard code nobody describes shows structure only', (tester) async {
      final env = await setUp(tester, sim: EngineSim(mode03: '7E8 04 43 01 00 17'));
      final xs = await showDtc(tester, env);
      expect(xs, contains(t('dtcSubFuelAir')));
      expect(xs, contains(t('provenanceStructure')));
      await env.close(tester);
    });

    testWidgets('a STOP code counts as CRITICAL and sorts first', (tester) async {
      final stop = seedLines().firstWhere((l) => l['rider_action_level'] == 'STOP');
      final bytes = encodeSae2(stop['code'] as String)!
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
      // P0420 (MONITOR / SERVICE_SOON) first on the wire, the STOP code second.
      final env = await setUp(tester, sim: EngineSim(mode03: '7E8 06 43 02 04 20 $bytes'));
      final xs = await showDtc(tester, env);
      expect(xs, contains(t('riderActionStop')));
      final codes = xs.where((x) => x == 'P0420' || x == stop['code']).toList();
      expect(codes.first, stop['code']);
      final critIdx = xs.indexOf(t('dtcCriticalChip'));
      expect(xs[critIdx - 1], '1');
      await env.close(tester);
    });

    testWidgets('while the store loads, the card says so instead of guessing', (tester) async {
      final env = await setUp(tester,
          startKnowledge: false, sim: EngineSim(mode03: '7E8 04 43 01 01 20'));
      final xs = await showDtc(tester, env);
      expect(xs, contains(t('knowledgeLoading')));
      expect(xs, isNot(contains(t('provenanceStructure'))));
      await env.close(tester);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // B7 lookup
  // ══════════════════════════════════════════════════════════════════════
  group('B7 query parsing', () {
    test('what riders type', () {
      expect(parseLookupQuery('p0120').codes, ['P0120']);
      expect(parseLookupQuery('  P 0120 ').codes, ['P0120']);
      expect(parseLookupQuery('PO120').codes, ['P0120'], reason: 'letter O for zero');
      expect(parseLookupQuery('u0100').codes, ['U0100']);
      expect(parseLookupQuery('4-3').codes, ['4-3']);
      expect(parseLookupQuery('4 3').codes, ['4-3']);
      expect(parseLookupQuery('4-3').format, DtcFormat.blink);
      expect(parseLookupQuery('5043h').codes, ['5043H', 'C1043']);
      expect(parseLookupQuery('0x5200').codes, ['5200H', 'C1200']);
      expect(parseLookupQuery('P01').prefixes, ['P01']);
      expect(parseLookupQuery('Oil  Temperature').words, ['oil', 'temperature']);
      expect(parseLookupQuery('   ').isEmpty, isTrue);
    });

    test('search: exact, words, prefix cap, blink table; offline, no adapter', () async {
      final k = await startedKnowledge();
      final exact = await searchCodes(parseLookupQuery('p0120'), store: k.store, language: 'en');
      expect(exact.items.first.code, 'P0120');
      final words = await searchCodes(parseLookupQuery('oil temperature'), store: k.store, language: 'en');
      expect(words.items, isNotEmpty);
      expect(words.items.every((r) => r.title.toLowerCase().contains('oil') ||
          r.title.toLowerCase().contains('temperature') || r.code.startsWith('P0')), isTrue);
      final all = await searchCodes(parseLookupQuery('P0'), store: k.store, language: 'en');
      expect(all.items.length, kLookupMaxResults);
      expect(all.capped, isTrue);
      final blink = await searchCodes(parseLookupQuery('4-3'), store: k.store, language: 'en');
      expect(blink.items.single.title, 'Rear wheel lock');
      expect(blink.items.single.scope, LookupScope.platform);
      final bosch = await searchCodes(parseLookupQuery('5200H'), store: k.store, language: 'en');
      expect(bosch.items.single.scope, LookupScope.moduleFamily);
      final injection = await searchCodes(parseLookupQuery("%'; DROP TABLE kb_entry; --"),
          store: k.store, language: 'en');
      expect(injection.items, isEmpty);
      expect((await k.store!.activeEntries()).length, 616);
      await k.store!.close();
    });
  });

  group('B7 lookup screen', () {
    Future<List<String>> type(WidgetTester tester, Env env, String q) async {
      await tester.pumpWidget(env.wrap(const CodeLookupScreen(debounce: Duration.zero)));
      await tester.pump();
      await tester.enterText(find.byType(TextField), q);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      return texts(tester);
    }

    testWidgets('[en] empty, a code, its detail — no adapter anywhere', (tester) async {
      final env = await setUp(tester);
      await tester.pumpWidget(env.wrap(const CodeLookupScreen(debounce: Duration.zero)));
      await tester.pump();
      expect(texts(tester), contains(t('lookupIntro')));
      expect(texts(tester), contains(t('lookupGenericOnly')));
      final xs = await type(tester, env, 'p0120');
      expect(xs, contains('P0120'));
      expect(xs, contains(seedLine('P0120')['title_en']));
      await tester.tap(find.text('P0120'));
      await tester.pumpAndSettle();
      final d = texts(tester);
      expect(d, contains(t('riderActionServiceSoon')));
      expect(d, contains(t('faultForMechanic').toUpperCase()));
      expect(d, contains(t('lookupNotReadNote')));
      await env.close(tester);
    });

    testWidgets('[hi] no-result and manufacturer-code states in Hindi', (tester) async {
      final env = await setUp(tester, lang: 'hi');
      var xs = await type(tester, env, 'zzqq words');
      expect(xs, contains(t('lookupNoResults', 'hi').replaceAll('{q}', 'zzqq words')));
      xs = await type(tester, env, 'P1234');
      expect(xs, contains(t('dtcManufacturerSpecific', 'hi')));
      await env.close(tester);
    });

    testWidgets('a Honda blink code on a Royal Enfield profile is not borrowed', (tester) async {
      final env = await setUp(tester, make: 'Royal Enfield', model: 'Classic 350');
      final xs = await type(tester, env, '4-3');
      expect(xs, contains(t('lookupForVehicle').replaceAll('{v}', 'Royal Enfield Classic 350')));
      await tester.tap(find.text('4-3').last); // the result, not the search field
      await tester.pumpAndSettle();
      final d = texts(tester);
      expect(d, isNot(contains('Rear wheel lock')));
      expect(d, contains(t('faultRawShowDealer')));
      expect(anyHas(d, t('lookupOtherScope').split('{scope}').first), isTrue);
      await env.close(tester);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // B9 Clear Codes record
  // ══════════════════════════════════════════════════════════════════════
  group('B9 the clear record (rider flow unchanged)', () {
    /// Exactly what DtcScreen._clearCodes runs, in order, through the REAL
    /// service: snapshot, Mode 04, the existing refresh, then the record.
    Future<ScanSession> clearAndRecord(EngineSim sim,
        {Duration snapshotAge = Duration.zero}) async {
      final k = await startedKnowledge();
      final obd = await connectSim(sim, timing: fast);
      await obd.readEngineDtcs();
      await obd.whenEngineReadSettled();
      final pre = PreClearSnapshot.capture(obd, DateTime.now().add(snapshotAge));
      final ok = await obd.clearDtcs();
      if (ok) await obd.readDtcs();
      final listAfter = obd.dtcCodes.map((c) => c.code).toList();
      final readAfter = obd.lastEngineRead;
      final outcome = await ClearCodesRecorder(
              obd: obd, knowledge: k, vehicle: VehicleSnapshot.none)
          .verifyAndRecord(pre, clearOutcome: obd.lastClearOutcome);
      // The silent re-read touched nothing the screen renders.
      expect(obd.dtcCodes.map((c) => c.code).toList(), listAfter);
      expect(identical(obd.lastEngineRead, readAfter), isTrue);
      final s = (await k.history!.list(includeInternal: true))
          .firstWhere((x) => x.kind == SessionKind.clearCheck);
      expect(s.clearOutcome, outcome);
      expect(await k.history!.list(), isNot(contains(s)), reason: 'internal, not listed');
      await obd.disconnect();
      await sim.close();
      await k.store!.close();
      return s;
    }

    test('codes returned (the erase did not take)', () async {
      final s = await clearAndRecord(
          EngineSim(mode03: '7E8 04 43 01 01 20')..extra['04'] = '7E8 01 44');
      expect(s.clearOutcome, ClearCheckOutcome.codesReturned);
      expect(s.faults.single.code, 'P0120');
      expect(s.preClear!['snapshot'], isTrue);
      expect(s.preClear!['codes'], ['P0120']);
    });

    test('cleared and verified', () async {
      final s = await clearAndRecord(_ClearingSim());
      expect(s.clearOutcome, ClearCheckOutcome.clearedVerified);
      expect(s.faults, isEmpty);
    });

    test('could not verify (the bike goes silent); no snapshot when the read is stale',
        () async {
      final s = await clearAndRecord(_ClearingSim(after: 'NO DATA'),
          snapshotAge: const Duration(seconds: 61));
      expect(s.clearOutcome, ClearCheckOutcome.couldNotVerify);
      expect(s.preClear!['snapshot'], isFalse);
      expect(s.preClear!['check_reason'], isNotNull);
    });

    test('a refused clear is recorded honestly while the rider still reads success', () async {
      final s = await clearAndRecord(
          EngineSim(mode03: '7E8 04 43 01 01 20')..extra['04'] = '7E8 03 7F 04 22');
      expect(s.preClear!['clear_service_outcome'], ClearDtcsOutcome.refused.name);
      expect(s.clearOutcome, ClearCheckOutcome.codesReturned);
      expect(clearOutcomeMessageKey(false, ClearDtcsOutcome.refused), 'clearSucceeded');
    });

    test('the rider-visible Clear Codes code is byte-identical to main', () {
      String norm(String x) => x.replaceAll('\r\n', '\n');
      final now = norm(File('lib/screens/dtc_screen.dart').readAsStringSync());
      final main = norm(Process.runSync(
              'git', ['show', 'main:lib/screens/dtc_screen.dart'],
              stdoutEncoding: utf8)
          .stdout as String);
      String between(String src, String a, String b) =>
          src.substring(src.indexOf(a), src.indexOf(b, src.indexOf(a)));
      // Dialog, button, message key, colour, duration, message text.
      // Phase A-4 (S3) is the ONE allowed difference: `_clearOutcomeMessage`
      // read the language with `context.tr` (a listening lookup) from an async
      // handler, which asserts in debug builds and stopped the message from
      // showing there. It now reads it with `context.read`. Same key, same
      // text, same moment — see clear_codes_debug_message_test.dart. Every
      // other byte of the function must still equal `main`.
      const mainMessageLine =
          '      context.tr(clearOutcomeMessageKey(ok, outcome));';
      const debugSafeMessageLine =
          '      AppStrings.get(clearOutcomeMessageKey(ok, outcome), '
          'context.read<SettingsProvider>().locale.languageCode);';
      for (final pair in [
        ['String clearOutcomeMessageKey', 'class DtcScreen'],
        ['  Future<void> _clearCodes() async {', '    setState(() => _clearing = true);'],
        ['    ScaffoldMessenger.of(context).showSnackBar(SnackBar(', '    ));'],
        ['  String _clearOutcomeMessage(', '  Future<void> _showFreezeFrame'],
      ]) {
        var expected = between(main, pair[0], pair[1]);
        if (pair[0] == '  String _clearOutcomeMessage(') {
          // Before A-4 is merged `main` has the old line; after, it already
          // has the new one. Either way the function must equal the new form.
          expect(
              expected.contains(mainMessageLine) ||
                  expected.contains(debugSafeMessageLine),
              isTrue,
              reason: 'main has a form of the message line this guard knows');
          expected = expected.replaceFirst(mainMessageLine, debugSafeMessageLine);
        }
        expect(between(now, pair[0], pair[1]), expected, reason: pair[0]);
      }
      // The erase and the existing refresh, unchanged and in order.
      expect(now, contains('    final ok = await obd.clearDtcs();\n'
          '    if (ok) await obd.readDtcs(); // refresh — should come back empty'));
      // The record is started only for the frame after the message.
      expect(now, contains('addPostFrameCallback((_) =>\n'
          '        unawaited(recorder.verifyAndRecord('));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // B10 small fixes
  // ══════════════════════════════════════════════════════════════════════
  group('B10', () {
    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] a) a busy ABS module has its own message', (tester) async {
        final env = await setUp(tester,
            lang: lang, make: 'Royal Enfield', model: 'Classic 350', abs: true,
            sim: EngineSim()
              ..personality = AdapterPersonality.passesPending
              ..udsModules['7B0'] = '7B8 07 59 02 FF 50 58 11 2F'
              ..busy['1902FF'] = const ModuleBusy.forever());
        expect(env.obd!.chassisScanOutcome, ChassisScanOutcome.moduleBusy);
        final xs = await showDtc(tester, env, abs: true);
        expect(xs, contains(t('absModuleBusyTitle', lang)));
        expect(xs, contains(t('absModuleBusyDesc', lang)));
        expect(xs, isNot(contains(t('absNoModule', lang))));
        expect(xs, isNot(contains(t('absNoFaults', lang))));
        await env.close(tester);
      });

      testWidgets('[$lang] b) high battery voltage banner above 15.0 V', (tester) async {
        final env = await setUp(tester,
            lang: lang,
            sim: EngineSim(mode03: '7E8 02 43 00')
              ..extra['0142'] = '41 42 3E 80'); // 16.0 V
        final xs = await showDtc(tester, env);
        expect(xs, contains(t('batteryHighBanner', lang).replaceAll('{v}', '16.0')));
        await env.close(tester);
      });

      testWidgets('[$lang] d) no hard-coded English left on the fault screen', (tester) async {
        final env = await setUp(tester, lang: lang, sim: EngineSim(mode03: '7E8 04 43 01 01 20'));
        final xs = await showDtc(tester, env);
        expect(xs, contains(t('dtcCodesChip', lang)));
        expect(xs, contains(t('dtcCriticalChip', lang)));
        expect(anyHas(xs, '${t('dtcLiveScan', lang)} · ${t('timeJustNow', lang)}'), isTrue);
        await env.close(tester);
        final off = await setUp(tester, lang: lang);
        // An adapter service that never connected: the disconnected state.
        await tester.pumpWidget(off.wrap(ChangeNotifierProvider<ObdService>(
            create: (_) => ObdService(EngineSim(), faultTiming: fast),
            child: const DtcScreen(autoScan: false))));
        await tester.pump();
        final ys = texts(tester);
        expect(ys, contains(t('dtcAdapterNotConnected', lang)));
        expect(ys, contains(t('lookupTitle', lang)));
      });

      testWidgets('[$lang] e) adapter up, bike silent: the banner says so', (tester) async {
        final env = await setUp(tester, lang: lang, sim: EngineSim(vehicleSilent: true, supportedPids: 'NO DATA', mode03: 'NO DATA'));
        expect(env.obd!.vehicleAnswered, isFalse);
        late String label;
        await tester.pumpWidget(env.wrap(Builder(builder: (c) {
          label = ribbonStatusLabel(c, env.obd!);
          return const SizedBox();
        })));
        expect(label, t('connectedViaBtSilent', lang));
        await env.close(tester);
      });
    }
  });
}

/// A bike whose stored codes empty when Mode 04 arrives ([after] = what Mode
/// 03 answers then).
class _ClearingSim extends EngineSim {
  _ClearingSim({this.after = '7E8 02 43 00'}) : super(mode03: '7E8 04 43 01 01 20') {
    extra['04'] = '7E8 01 44';
  }
  final String after;

  @override
  Future<bool> write(String cmd) {
    if (cmd.trim().toUpperCase() == '04') mode03 = after;
    return super.write(cmd);
  }
}
