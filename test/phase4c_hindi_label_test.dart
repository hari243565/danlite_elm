/// Phase 4C K4 — a card that shows Hindi text from a row marked "machine" says
/// so, on one short line under the draft line. Never on an English card, a
/// card in a language that fell back to English, a human-reviewed Hindi row,
/// or any screen of the app's own.
library;

import 'dart:io';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/knowledge/fault_resolver.dart';
import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:danlite_elm/screens/code_lookup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phase1b_screens_test.dart' as screens;
import 'support/engine_sim.dart';

const String kKey = 'faultHindiMachine';
const String kEnglish = 'Hindi is machine-translated and has not been checked by a person.';
const String kHindi = 'यह हिंदी मशीन से अनुवादित है और अभी किसी व्यक्ति ने इसे जाँचा नहीं है।';

String t(String key, [String lang = 'en']) => AppStrings.get(key, lang);

FaultRecord obd(String code) => FaultRecord.fromObdCode(code,
    source: ReadSource.mode03, readAt: DateTime.utc(2026, 10, 3));

KbEntry row(String lang,
        {HiStatus hi = HiStatus.none, String verification = 'ai_authored_from_standard_title'}) =>
    KbEntry(
      contentId: 'generic:P0121:$lang',
      code: 'P0121',
      scopeKind: ScopeKind.generic,
      language: lang,
      title: lang == 'hi' ? 'हिंदी शीर्षक' : 'English title',
      meaning: lang == 'hi' ? 'हिंदी मतलब' : 'English meaning',
      riderAction: RiderAction.serviceSoon,
      canRide: CanRide.withCare,
      verification: verification,
      hiStatus: hi,
      packId: 'p',
    );

String mode03(String code) {
  final n = int.parse(code.substring(1), radix: 16);
  String h(int x) => x.toRadixString(16).toUpperCase().padLeft(2, '0');
  return '7E8 04 43 01 ${h((n >> 8) & 0xFF)} ${h(n & 0xFF)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('K4 the words', () {
    test('exact English and Hindi', () {
      expect(t(kKey, 'en'), kEnglish);
      expect(t(kKey, 'hi'), kHindi);
    });

    test('a key in both languages, and the Hindi is not the English', () {
      expect(t(kKey, 'en'), isNot(kKey));
      expect(t(kKey, 'hi'), isNot(kKey));
      expect(t(kKey, 'hi'), isNot(t(kKey, 'en')));
    });

    test('the Hindi uses the owner\'s fixed spellings and Latin digits only', () {
      final hi = t(kKey, 'hi');
      expect(hi.contains(RegExp(r'[०-९]')), isFalse);
      expect(hi.contains('एडाप्टर'), isFalse);
    });

    test('the new key is in the English and Hindi tables, in source', () {
      final src = File('lib/constants/app_strings.dart').readAsStringSync();
      expect(RegExp("'$kKey':").allMatches(src).length, 2);
    });
  });

  group('K4 the resolver says when Hindi from a machine row is shown', () {
    final vehicle = VehicleContext.generic;
    ResolvedFault resolve(List<KbEntry> rows, String lang) =>
        FaultResolver(index: KnowledgeIndex(rows)).resolve(obd('P0121'), vehicle, lang);

    test('machine Hindi asked for in Hindi: yes', () {
      final r = resolve([row('en'), row('hi', hi: HiStatus.machine)], 'hi');
      expect(r.languageUsed, 'hi');
      expect(r.hindiMachine, isTrue);
    });

    test('machine Hindi with no English row: yes', () {
      expect(resolve([row('hi', hi: HiStatus.machine)], 'hi').hindiMachine, isTrue);
    });

    test('Hindi a person has read: no', () {
      expect(resolve([row('en'), row('hi', hi: HiStatus.reviewed)], 'hi').hindiMachine, isFalse);
    });

    test('English asked for: no, even when a machine Hindi row exists', () {
      expect(resolve([row('en'), row('hi', hi: HiStatus.machine)], 'en').hindiMachine, isFalse);
    });

    test('Hindi asked for but only English exists: no (the English fallback note covers it)', () {
      final r = resolve([row('en')], 'hi');
      expect(r.languageUsed, 'en');
      expect(r.hindiMachine, isFalse);
    });

    test('another language falls back to English: no', () {
      expect(resolve([row('en'), row('hi', hi: HiStatus.machine)], 'bn').hindiMachine, isFalse);
    });

    test('structure-only and raw answers: no', () {
      final r = FaultResolver(index: KnowledgeIndex.empty).resolve(obd('P0134'), vehicle, 'hi');
      expect(r.hindiMachine, isFalse);
    });
  });

  group('K4 the cards', () {
    // P0336 is a shipped guidance entry with a Hindi row; P0001 is a name-only one.
    for (final code in ['P0336', 'P0001']) {
      testWidgets('[hi] $code: the line is there, directly after the draft line', (tester) async {
        final env = await screens.setUp(tester, lang: 'hi', sim: EngineSim(mode03: mode03(code)));
        final xs = await screens.showDtc(tester, env);
        expect(xs.where((x) => x == kHindi), hasLength(1));
        final draft = xs.indexWhere((x) => x.contains(t('provenanceDraft', 'hi')));
        expect(draft, greaterThanOrEqualTo(0));
        expect(xs.indexOf(kHindi), draft + 1, reason: 'one line below the draft line');
        await env.close(tester);
      });

      testWidgets('[en] $code: no such line', (tester) async {
        final env = await screens.setUp(tester, sim: EngineSim(mode03: mode03(code)));
        final xs = await screens.showDtc(tester, env);
        expect(xs, isNot(contains(kEnglish)));
        expect(xs, isNot(contains(kHindi)));
        await env.close(tester);
      });

      testWidgets('[bn] $code: English fallback, no such line', (tester) async {
        final env = await screens.setUp(tester, lang: 'bn', sim: EngineSim(mode03: mode03(code)));
        final xs = await screens.showDtc(tester, env);
        expect(xs, contains(t('faultShowingEnglish', 'bn')));
        expect(xs, isNot(contains(kEnglish)));
        expect(xs, isNot(contains(kHindi)));
        await env.close(tester);
      });
    }

    testWidgets('[hi] two Hindi cards: one line each', (tester) async {
      final env = await screens.setUp(tester,
          lang: 'hi', sim: EngineSim(mode03: '7E8 06 43 02 03 36 00 01'));
      final xs = await screens.showDtc(tester, env);
      expect(xs.where((x) => x == kHindi), hasLength(2));
      await env.close(tester);
    });

    testWidgets('[hi] a Hindi row a person has read: no line', (tester) async {
      final env = await screens.setUp(tester,
          lang: 'hi', sim: EngineSim(mode03: mode03('P0336')), beforeRead: (k) async {
        await k.store!.db.update('kb_entry', {'hi_status': 'reviewed'},
            where: "content_id = 'generic:P0336:hi'");
        await k.reload();
      });
      final xs = await screens.showDtc(tester, env);
      expect(xs.any((x) => x.contains(t('provenanceDraft', 'hi'))), isTrue,
          reason: 'still a draft; only the machine-translation line goes');
      expect(xs, isNot(contains(kHindi)));
      await env.close(tester);
    });

    testWidgets('[hi] a code with no content, and the empty fault screen: no line',
        (tester) async {
      final env = await screens.setUp(tester, lang: 'hi', sim: EngineSim(mode03: mode03('P0134')));
      final xs = await screens.showDtc(tester, env);
      expect(xs, isNot(contains(kHindi)));
      await env.close(tester);
      final none = await screens.setUp(tester, lang: 'hi', sim: EngineSim(mode03: '7E8 02 43 00'));
      final ys = await screens.showDtc(tester, none);
      expect(ys, isNot(contains(kHindi)));
      await none.close(tester);
    });

    testWidgets('[hi] the lookup detail shows it for a Hindi answer, not for structure only',
        (tester) async {
      final env = await screens.setUp(tester, lang: 'hi');
      await tester.pumpWidget(env.wrap(const CodeLookupDetailScreen(
          code: 'P0336', format: DtcFormat.sae2)));
      await tester.pump(const Duration(milliseconds: 50));
      List<String> texts() =>
          tester.widgetList<Text>(find.byType(Text)).map((x) => x.data ?? '').toList();
      expect(texts().where((x) => x == kHindi), hasLength(1));
      await tester.pumpWidget(env.wrap(const CodeLookupDetailScreen(
          code: 'P0134', format: DtcFormat.sae2)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(texts(), isNot(contains(kHindi)));
      await env.close(tester);
    });
  });
}
