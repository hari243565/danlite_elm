/// Phase 4A H3 — honest display. An unreached module is not shown as clean, a
/// "none found" is not read as "those modules were checked", and an old result
/// never looks live.
///
/// (a) the ABS summary bar, every ABS outcome
/// (b) "None in scan results" on Body / Network / Transmission / Other
/// (c) "Read at {time}" on the Engine and ABS cards
library;

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/constants/chassis_modules.dart';
import 'package:danlite_elm/knowledge/fault_domain.dart';
import 'package:danlite_elm/models/vehicle_data.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/providers/vehicle_provider.dart';
import 'package:danlite_elm/screens/dtc_screen.dart';
import 'package:danlite_elm/services/obd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fault_sections_screen_test.dart' as secs;
import 'support/engine_sim.dart';

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

const Color kGreen = Color(0xFF00E39C); // _RC.neonGreen
const Color kRed = Color(0xFFFF3D3D); // _RC.neonRed
const Color kMuted = Color(0xFF607080); // _RC.textMuted

/// A connected service whose ABS outcome is whatever the test says, for the
/// outcomes the simulator cannot produce on demand.
class FixedAbsObd extends ObdService {
  FixedAbsObd(super.link, this._outcome, {super.faultTiming});
  final ChassisScanOutcome _outcome;
  @override
  ChassisScanOutcome get chassisScanOutcome => _outcome;
}

/// The CODES chip on screen: its number text and that text's colour.
({String value, Color? color}) codesChip(WidgetTester tester) {
  final label = find.text(t('dtcCodesChip'));
  expect(label, findsOneWidget);
  final row = find.ancestor(of: label, matching: find.byType(Row)).first;
  final value = tester.widgetList<Text>(find.descendant(of: row, matching: find.byType(Text))).first;
  return (value: value.data ?? '', color: value.style?.color);
}

Future<List<String>> absBarTexts(WidgetTester tester) async => tester
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ════════════════════════════════════════════════════════════════════════
  // (a) the ABS summary bar
  // ════════════════════════════════════════════════════════════════════════
  group('H3a absSummaryFor: green only when the module answered with no codes', () {
    test('every ABS outcome', () {
      final want = <ChassisScanOutcome, (SummaryTone, String?)>{
        ChassisScanOutcome.idle: (SummaryTone.neutral, 'sectionNotScanned'),
        ChassisScanOutcome.clean: (SummaryTone.clean, null),
        ChassisScanOutcome.faultsFound: (SummaryTone.faults, null),
        ChassisScanOutcome.noModuleResponse: (SummaryTone.neutral, 'absNoModule'),
        ChassisScanOutcome.moduleBusy: (SummaryTone.neutral, 'absModuleBusyTitle'),
        ChassisScanOutcome.addressingUnsupported:
            (SummaryTone.neutral, 'absAddressingUnsupported'),
        ChassisScanOutcome.linkUnavailable: (SummaryTone.neutral, 'connectionFailed'),
      };
      expect(want.keys.toSet(), ChassisScanOutcome.values.toSet(),
          reason: 'a new outcome must be decided here');
      want.forEach((o, w) {
        final s = absSummaryFor(o, scanning: false);
        expect(s.tone, w.$1, reason: o.name);
        expect(s.noteKey, w.$2, reason: o.name);
        expect(s.showsCount, w.$1 != SummaryTone.neutral, reason: o.name);
      });
    });

    test('a scan in progress is neutral whatever the last result was', () {
      for (final o in ChassisScanOutcome.values) {
        final s = absSummaryFor(o, scanning: true);
        expect(s.tone, SummaryTone.neutral, reason: o.name);
        expect(s.noteKey, 'sectionScanning', reason: o.name);
      }
    });

    test('the only way to green is clean', () {
      final green = [
        for (final o in ChassisScanOutcome.values)
          if (absSummaryFor(o, scanning: false).tone == SummaryTone.clean) o
      ];
      expect(green, [ChassisScanOutcome.clean]);
    });
  });

  group('H3a the ABS summary bar on the real screen', () {
    testWidgets('ABS never scanned: neutral dash and "Not scanned", not a green 0',
        (tester) async {
      final s = await secs.open(tester, EngineSim(mode03: '43 00'), showAbs: true);
      expect(s.obd.chassisScanOutcome, ChassisScanOutcome.idle);
      final chip = codesChip(tester);
      expect(chip.value, '—');
      expect(chip.color, kMuted);
      expect(await absBarTexts(tester), contains(t('sectionNotScanned')));
      await s.close();
    });

    testWidgets('ABS answered with no codes: green 0', (tester) async {
      final s = await secs.open(
          tester, EngineSim(mode03: '43 00')..udsModules['7B0'] = '7B8 03 59 02 FF',
          scanAbs: true, showAbs: true);
      expect(s.obd.chassisScanOutcome, ChassisScanOutcome.clean);
      final chip = codesChip(tester);
      expect(chip.value, '0');
      expect(chip.color, kGreen);
      await s.close();
    });

    testWidgets('ABS answered with a code: red 1', (tester) async {
      final s = await secs.open(
          tester,
          EngineSim(mode03: '43 00')..udsModules['7B0'] = '7B8 07 59 02 FF 50 58 11 2F',
          scanAbs: true, showAbs: true);
      expect(s.obd.chassisScanOutcome, ChassisScanOutcome.faultsFound);
      final chip = codesChip(tester);
      expect(chip.value, '1');
      expect(chip.color, kRed);
      await s.close();
    });

    testWidgets('no module replied: neutral dash and "No reply", never green',
        (tester) async {
      final s = await secs.open(tester, EngineSim(mode03: 'NO DATA'),
          scanAbs: true, showAbs: true);
      expect(s.obd.chassisScanOutcome, ChassisScanOutcome.noModuleResponse);
      final chip = codesChip(tester);
      expect(chip.value, '—');
      expect(chip.color, kMuted);
      expect(await absBarTexts(tester), contains(t('absNoModule')));
      await s.close();
    });

    testWidgets('module busy: neutral dash and the busy title', (tester) async {
      final s = await secs.open(
          tester,
          EngineSim()
            ..personality = AdapterPersonality.passesPending
            ..udsModules['7B0'] = '7B8 07 59 02 FF 50 58 11 2F'
            ..busy['1902FF'] = const ModuleBusy.forever(),
          scanAbs: true, showAbs: true);
      expect(s.obd.chassisScanOutcome, ChassisScanOutcome.moduleBusy);
      final chip = codesChip(tester);
      expect(chip.value, '—');
      expect(chip.color, kMuted);
      expect(await absBarTexts(tester), contains(t('absModuleBusyTitle')));
      await s.close();
    });

    for (final o in [
      ChassisScanOutcome.addressingUnsupported,
      ChassisScanOutcome.linkUnavailable,
    ]) {
      testWidgets('${o.name}: neutral dash and its own words', (tester) async {
        final settings = SettingsProvider();
        final sim = EngineSim(mode03: '43 00');
        late FixedAbsObd obd;
        await tester.runAsync(() async {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          obd = FixedAbsObd(sim, o, faultTiming: secs.fast);
          expect(await obd.connectBluetooth(simDevice), isTrue);
        });
        tester.view.physicalSize = const Size(1200, 5000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<VehicleProvider>(create: (_) => VehicleProvider()),
            ChangeNotifierProvider<ObdService>.value(value: obd),
          ],
          child: const MaterialApp(home: DtcScreen(autoScan: false)),
        ));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text(t('moduleAbs')));
        await tester.pump(const Duration(milliseconds: 50));
        final chip = codesChip(tester);
        expect(chip.value, '—');
        expect(chip.color, kMuted);
        final key = absSummaryFor(o, scanning: false).noteKey!;
        expect(await absBarTexts(tester), contains(t(key)));
        await tester.runAsync(() async {
          await obd.disconnect();
          await sim.close();
        });
      });
    }

    testWidgets('in Hindi the neutral words are Hindi', (tester) async {
      final s = await secs.open(tester, EngineSim(mode03: 'NO DATA'),
          lang: 'hi', scanAbs: true, showAbs: true);
      expect(await absBarTexts(tester), contains(t('absNoModule', 'hi')));
      expect(t('absNoModule', 'hi'), isNot(t('absNoModule')));
      await s.close();
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // (b) "None in scan results"
  // ════════════════════════════════════════════════════════════════════════
  group('H3b "None in scan results"', () {
    test('the strings: exact wording, English and Hindi', () {
      expect(t('sectionNoneInResults'), 'None in scan results');
      expect(t('sectionNoneInResults', 'hi'), 'स्कैन के नतीजों में कोई नहीं');
      expect(AppStrings.languageTable('en').values, isNot(contains('None found')),
          reason: 'the old wording is gone, not just unused');
      expect(AppStrings.languageTable('hi').values, isNot(contains('कोई नहीं मिला')));
    });

    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] Body, Network, Transmission, Other say it after a scan, '
          'with the caption kept', (tester) async {
        final s = await secs.open(tester, EngineSim(mode03: '43 00'), lang: lang);
        for (final n in ['body', 'network', 'transmission', 'other']) {
          expect(s.inCard(n), contains(t('sectionNoneInResults', lang)), reason: n);
          expect(s.inCard(n), contains(t('sectionBasedOn', lang)), reason: '$n caption kept');
        }
        expect(s.texts.where((x) => x == 'None found' || x == 'कोई नहीं मिला'), isEmpty);
        await s.close();
      });
    }

    testWidgets('before any scan the four cards still say "not scanned yet"', (tester) async {
      final s = await secs.open(tester, EngineSim(), readEngine: false);
      for (final n in ['body', 'network', 'transmission', 'other']) {
        expect(s.inCard(n), contains(t('sectionNotScannedYet')), reason: n);
        expect(s.inCard(n), isNot(contains(t('sectionNoneInResults'))), reason: n);
      }
      await s.close();
    });

    testWidgets('tapping an empty card repeats the wording', (tester) async {
      final s = await secs.open(tester, EngineSim(mode03: '43 00'));
      await s.tap(s.card('body'));
      expect(s.texts, contains(t('sectionNoneInResults')));
      await s.close();
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // (c) "Read at {time}" on the Engine and ABS cards
  // ════════════════════════════════════════════════════════════════════════
  group('H3c summariseSections carries the read time (fake clock)', () {
    final t1 = DateTime(2026, 10, 3, 14, 5, 9);
    final t2 = DateTime(2026, 10, 3, 14, 7, 31);

    SectionSummary of(List<SectionSummary> all, FaultSection s) =>
        all.firstWhere((x) => x.section == s);

    List<SectionSummary> summarise({
      EngineDtcRead? read,
      ChassisScanOutcome abs = ChassisScanOutcome.idle,
      DateTime? absAt,
      bool absScanning = false,
      bool engineScanning = false,
      List<DtcCode> absCodes = const [],
    }) =>
        summariseSections(
          engineRead: read,
          engineScanning: engineScanning,
          engineCodes: const [],
          absOutcome: abs,
          absScanning: absScanning,
          absCodes: absCodes,
          absReadAt: absAt,
        );

    test('engine: the time of the latest read, answered or not', () {
      expect(of(summarise(read: EngineAnswered(const [], t1)), FaultSection.engine).readAt, t1);
      expect(of(summarise(read: EngineNoAnswer(EngineNoAnswerReason.noData, t2)), FaultSection.engine).readAt, t2);
      expect(of(summarise(read: EngineRefused(null, t1)), FaultSection.engine).readAt, t1);
    });

    test('engine: no stamp when never read, or while a read is running', () {
      expect(of(summarise(), FaultSection.engine).readAt, isNull);
      expect(of(summarise(read: EngineAnswered(const [], t1), engineScanning: true), FaultSection.engine).readAt,
          isNull, reason: 'the number is about to change; do not stamp it');
    });

    test('ABS: the time of its own scan, only once it has a result', () {
      expect(of(summarise(abs: ChassisScanOutcome.clean, absAt: t2), FaultSection.brakes).readAt, t2);
      expect(of(summarise(abs: ChassisScanOutcome.noModuleResponse, absAt: t2), FaultSection.brakes).readAt, t2);
      expect(of(summarise(abs: ChassisScanOutcome.idle, absAt: t2), FaultSection.brakes).readAt, isNull,
          reason: 'never scanned');
      expect(of(summarise(abs: ChassisScanOutcome.clean, absAt: t2, absScanning: true), FaultSection.brakes).readAt,
          isNull);
    });

    test('the four other cards never carry a stamp', () {
      final all = summarise(read: EngineAnswered(const [], t1), abs: ChassisScanOutcome.clean, absAt: t2);
      for (final s in [FaultSection.body, FaultSection.network, FaultSection.transmission, FaultSection.other]) {
        expect(of(all, s).readAt, isNull, reason: s.name);
      }
    });
  });

  group('H3c the cards on screen', () {
    String two(int n) => n.toString().padLeft(2, '0');
    String stamp(DateTime d, [String lang = 'en']) => t('dtcReadAt', lang)
        .replaceAll('{time}', '${two(d.hour)}:${two(d.minute)}:${two(d.second)}');

    testWidgets('Engine card shows the time of the engine read', (tester) async {
      final s = await secs.open(tester, EngineSim(mode03: secs.twoCodes));
      final at = s.obd.lastEngineRead!.at;
      expect(s.inCard('engine'), contains(stamp(at)));
      // The ABS card has no scan of its own and must not borrow that time as an ABS result.
      expect(s.inCard('brakes').where((x) => x.startsWith(t('dtcReadAt').split('{').first)), isEmpty);
      await s.close();
    });

    testWidgets('ABS card shows the time of the ABS scan', (tester) async {
      final s = await secs.open(
          tester, EngineSim(mode03: '43 00')..udsModules['7B0'] = '7B8 03 59 02 FF',
          scanAbs: true);
      expect(s.inCard('brakes'), contains(stamp(s.obd.chassisReadAt!)));
      expect(s.inCard('engine'), contains(stamp(s.obd.lastEngineRead!.at)));
      await s.close();
    });

    testWidgets('an engine read that failed carries ITS time, not the older answer\'s',
        (tester) async {
      final sim = EngineSim(mode03: secs.twoCodes);
      final s = await secs.open(tester, sim);
      final first = s.obd.lastEngineRead!.at;
      sim.mode03 = 'NO DATA';
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        await s.obd.readEngineDtcs();
        await s.obd.whenEngineReadSettled();
      });
      await tester.pump(const Duration(milliseconds: 50));
      final second = s.obd.lastEngineRead!.at;
      expect(s.obd.lastEngineRead, isA<EngineNoAnswer>());
      expect(second.isAfter(first), isTrue);
      expect(s.inCard('engine'), contains(stamp(second)));
      expect(s.inCard('engine'), contains(t('dtcNoAnswerTitle')));
      await s.close();
    });

    testWidgets('never scanned: no stamp on either card', (tester) async {
      final s = await secs.open(tester, EngineSim(), readEngine: false);
      for (final n in ['engine', 'brakes']) {
        expect(s.inCard(n).where((x) => x.contains(t('dtcReadAt').split('{').first)), isEmpty,
            reason: n);
      }
      await s.close();
    });

    testWidgets('[hi] the stamp is in Hindi', (tester) async {
      final s = await secs.open(tester, EngineSim(mode03: secs.twoCodes), lang: 'hi');
      expect(s.inCard('engine'), contains(stamp(s.obd.lastEngineRead!.at, 'hi')));
      expect(t('dtcReadAt', 'hi'), isNot(t('dtcReadAt')));
      await s.close();
    });

    testWidgets('the card still fits: no overflow with state, caption and stamp',
        (tester) async {
      final s = await secs.open(
          tester,
          EngineSim(mode03: secs.cCodeFromEngine)..udsModules['7B0'] = '7B8 03 59 02 FF',
          scanAbs: true, lang: 'hi');
      expect(tester.takeException(), isNull);
      await s.close();
    });
  });
}
