/// Phase 4D M1 + M2 — a name-only card (verification standard_title_only) must
/// not wear the rider-action chip "Info" (it can read as "harmless" on a title
/// that mentions fuel pressure, brakes or misfire), and must show its title
/// once, not again as "Standard name: <same title>.".
///
/// Only the chip, the card colour and the repeated line change. The data, the
/// advice line, the CRITICAL count and the card ordering stay as they were.
library;

import 'dart:io';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/knowledge/fault_resolver.dart';
import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/screens/code_lookup_screen.dart';
import 'package:danlite_elm/widgets/resolved_fault_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phase1b_screens_test.dart' as screens;
import 'support/engine_sim.dart';

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

const String kKey = 'riderActionNameOnly';

// P0001 is a real shipped name-only entry; P0336 and P0121 are shipped guidance
// entries (STOP and SERVICE_SOON).
const String p0001En = 'Fuel Volume Regulator A Control Circuit/Open';
const String p0001Hi = 'फ़्यूल वॉल्यूम रेगुलेटर A कंट्रोल सर्किट/ओपन';

FaultRecord obd(String code) => FaultRecord.fromObdCode(code,
    source: ReadSource.mode03, readAt: DateTime.utc(2026, 10, 4));

String mode03(String code) {
  final n = int.parse(code.substring(1), radix: 16);
  String h(int x) => x.toRadixString(16).toUpperCase().padLeft(2, '0');
  return '7E8 04 43 01 ${h((n >> 8) & 0xFF)} ${h(n & 0xFF)}';
}

KbEntry row(String verification,
        {RiderAction action = RiderAction.info, String lang = 'en'}) =>
    KbEntry(
      contentId: 'generic:P0121:$lang',
      code: 'P0121',
      scopeKind: ScopeKind.generic,
      language: lang,
      title: 'English title',
      meaning: 'English meaning',
      riderAction: action,
      verification: verification,
      packId: 'p',
    );

ResolvedFault resolve(KbEntry e, [String lang = 'en']) =>
    FaultResolver(index: KnowledgeIndex([e]))
        .resolve(obd('P0121'), VehicleContext.generic, lang);

List<String> texts(WidgetTester tester) => screens.texts(tester);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M1 the words', () {
    test('exact English and Hindi', () {
      expect(t(kKey, 'en'), 'Name only');
      expect(t(kKey, 'hi'), 'सिर्फ़ नाम');
    });

    test('in both tables, in source; the Hindi is not the English', () {
      final src = File('lib/constants/app_strings.dart').readAsStringSync();
      expect(RegExp("'$kKey':").allMatches(src).length, 2);
      expect(t(kKey, 'hi'), isNot(t(kKey, 'en')));
      expect(t(kKey, 'hi').contains(RegExp(r'[०-९]')), isFalse);
    });

    test('the Info chip keeps its words', () {
      expect(t('riderActionInfo', 'en'), 'Info');
      expect(t('riderActionInfo', 'hi'), 'जानकारी');
    });
  });

  group('M1 the resolver', () {
    test('a name-only answer says so; everything else does not', () {
      expect(resolve(row('standard_title_only')).isNameOnly, isTrue);
      for (final v in ['ai_authored_from_standard_title', 'ai_authored_adapted']) {
        expect(resolve(row(v)).isNameOnly, isFalse, reason: v);
      }
      expect(FaultResolver(index: KnowledgeIndex.empty)
              .resolve(obd('P0134'), VehicleContext.generic, 'en')
              .isNameOnly,
          isFalse);
    });

    test('the data is untouched: a name-only answer is still rider action INFO', () {
      expect(resolve(row('standard_title_only')).riderAction, RiderAction.info);
    });

    test('a guidance entry that happens to be INFO is NOT name-only (its chip stays)', () {
      final r = resolve(row('ai_authored_from_standard_title'));
      expect(r.riderAction, RiderAction.info);
      expect(r.isNameOnly, isFalse);
    });
  });

  group('M1 the chip widget', () {
    Future<void> show(WidgetTester tester, ResolvedFault r, String lang) async {
      final env = await screens.setUp(tester, lang: lang, knowledge: false);
      await tester.pumpWidget(env.wrap(Scaffold(body: FaultActionChip(r))));
      await tester.pump();
    }

    for (final lang in ['en', 'hi']) {
      testWidgets('[$lang] name only: grey, icon plus word, not the Info chip', (tester) async {
        await show(tester, resolve(row('standard_title_only')), lang);
        expect(find.byType(NameOnlyChip), findsOneWidget);
        expect(find.byType(RiderActionChip), findsNothing);
        expect(texts(tester), [t(kKey, lang)]);
        expect(find.byType(Icon), findsOneWidget, reason: 'never colour alone');
        final icon = tester.widget<Icon>(find.byType(Icon));
        expect(icon.color, FaultPalette.textMuted, reason: 'neutral grey, no action colour');
        for (final a in RiderAction.values) {
          expect(icon.color, isNot(riderActionColor(a)));
        }
      });

      testWidgets('[$lang] every other chip is exactly as before', (tester) async {
        for (final a in RiderAction.values) {
          await show(tester, resolve(row('ai_authored_from_standard_title', action: a)), lang);
          expect(find.byType(RiderActionChip), findsOneWidget, reason: '$a');
          expect(find.byType(NameOnlyChip), findsNothing);
          expect(texts(tester), [t(riderActionKey(a), lang)]);
        }
      });
    }

    testWidgets('a legacy-table / structure answer (no rider action) draws no chip here',
        (tester) async {
      await show(
          tester,
          FaultResolver(index: KnowledgeIndex.empty)
              .resolve(obd('P0134'), VehicleContext.generic, 'en'),
          'en');
      expect(find.byType(RiderActionChip), findsNothing);
      expect(find.byType(NameOnlyChip), findsNothing);
    });
  });

  group('M1 + M2 the fault card', () {
    for (final lang in ['en', 'hi']) {
      final title = lang == 'en' ? p0001En : p0001Hi;
      final repeated = lang == 'en' ? 'Standard name:' : 'मानक नाम:';

      testWidgets('[$lang] P0001: neutral chip, no Info word, title once, advice kept',
          (tester) async {
        final env = await screens.setUp(tester, lang: lang, sim: EngineSim(mode03: mode03('P0001')));
        final xs = await screens.showDtc(tester, env);
        expect(find.byType(NameOnlyChip), findsOneWidget);
        expect(find.byType(RiderActionChip), findsNothing);
        expect(xs, contains(t(kKey, lang)));
        expect(xs, isNot(contains(t('riderActionInfo', lang))));
        // M2: the title is shown once and the repeated line is gone.
        expect(xs.where((x) => x.contains(title)), hasLength(1));
        expect(xs.any((x) => x.contains(repeated)), isFalse);
        // The advice line and the provenance label are still there.
        expect(xs, contains(t('faultWhatToDo', lang).toUpperCase()));
        expect(xs.any((x) => x.contains(t('provenanceStandardTitleOnly', lang))), isTrue);
        await env.close(tester);
      });

      testWidgets('[$lang] a guidance card still shows its chip and its meaning line',
          (tester) async {
        final env = await screens.setUp(tester, lang: lang, sim: EngineSim(mode03: mode03('P0336')));
        final xs = await screens.showDtc(tester, env);
        expect(find.byType(RiderActionChip), findsOneWidget);
        expect(find.byType(NameOnlyChip), findsNothing);
        expect(xs, contains(t('riderActionStop', lang)));
        final r = env.knowledge!.resolve(obd('P0336'), VehicleContext.generic, lang);
        expect(r.meaning, isNotEmpty);
        expect(xs, contains(r.meaning), reason: 'M2 hides nothing on a guidance card');
        await env.close(tester);
      });
    }

    testWidgets('the lookup detail: same chip, title once', (tester) async {
      final env = await screens.setUp(tester);
      await tester.pumpWidget(env.wrap(
          const CodeLookupDetailScreen(code: 'P0001', format: DtcFormat.sae2)));
      await tester.pump(const Duration(milliseconds: 50));
      final xs = texts(tester);
      expect(find.byType(NameOnlyChip), findsOneWidget);
      expect(find.byType(RiderActionChip), findsNothing);
      expect(xs.where((x) => x.contains(p0001En)), hasLength(1));
      expect(xs.any((x) => x.contains('Standard name:')), isFalse);
      await env.close(tester);
    });

    testWidgets('the lookup detail of a guidance code keeps its chip and meaning',
        (tester) async {
      final env = await screens.setUp(tester);
      await tester.pumpWidget(env.wrap(
          const CodeLookupDetailScreen(code: 'P0336', format: DtcFormat.sae2)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(RiderActionChip), findsOneWidget);
      expect(find.byType(NameOnlyChip), findsNothing);
      await env.close(tester);
    });
  });

  group('M1 the CRITICAL count and the ordering still treat a name only as not-Stop', () {
    testWidgets('a name-only card alone: CRITICAL is 0', (tester) async {
      final env = await screens.setUp(tester, sim: EngineSim(mode03: mode03('P0001')));
      final xs = await screens.showDtc(tester, env);
      final i = xs.indexOf(t('dtcCriticalChip'));
      expect(i, greaterThanOrEqualTo(0));
      expect(xs[i - 1], '0');
      await env.close(tester);
    });

    testWidgets('a name-only card and a STOP card: CRITICAL is 1, the STOP card is first',
        (tester) async {
      // P0001 is read first on purpose, so only the ordering can put P0336 on top.
      final env = await screens.setUp(tester,
          sim: EngineSim(mode03: '7E8 06 43 02 00 01 03 36'));
      final xs = await screens.showDtc(tester, env);
      final i = xs.indexOf(t('dtcCriticalChip'));
      expect(xs[i - 1], '1');
      final top = tester.getTopLeft(find.text('P0336')).dy;
      final bottom = tester.getTopLeft(find.text('P0001')).dy;
      expect(top, lessThan(bottom), reason: 'a bare name sorts below a STOP');
      await env.close(tester);
    });

    testWidgets('a name-only card sorts below a SERVICE SOON card too (rank unchanged)',
        (tester) async {
      final env = await screens.setUp(tester,
          sim: EngineSim(mode03: '7E8 06 43 02 00 01 01 21'));
      await screens.showDtc(tester, env);
      expect(tester.getTopLeft(find.text('P0121')).dy,
          lessThan(tester.getTopLeft(find.text('P0001')).dy));
      await env.close(tester);
    });
  });
}
