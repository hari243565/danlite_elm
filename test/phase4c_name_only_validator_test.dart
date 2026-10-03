/// Phase 4C K1 — the importer accepts name-only entries (`standard_title_only`)
/// and ONLY those may leave out causes, hints and can-ride. Every other entry
/// keeps the rules it always had.
library;

import 'dart:math';

import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/knowledge/kb_validator.dart';
import 'package:danlite_elm/knowledge/knowledge_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/kb_pack_builder.dart';

const String kAdviceEn =
    'This code has a standard name only. We have no further guidance for it yet. '
    'If the warning lamp is on or the bike runs badly, have it checked soon.';

/// A name-only English line exactly as the content branch builds it.
Map<String, Object?> nameOnlyEn([String code = 'P0001']) => <String, Object?>{
      'schema_version': 2,
      'content_id': 'generic:$code:en',
      'code': code,
      'system': 'powertrain',
      'title_en': 'Fuel Volume Regulator A Control Circuit/Open',
      'standard_title_en': 'Fuel Volume Regulator A Control Circuit/Open',
      'meaning_en': 'Standard name: Fuel Volume Regulator A Control Circuit/Open.',
      'likely_causes_en': <String>[],
      'rider_action_level': 'INFO',
      'rider_action_basis': 'Draft: standard name only',
      'rider_advice_en': kAdviceEn,
      'can_ride_to_workshop': null,
      'can_ride_reason': null,
      'technician_hints_en': <String>[],
      'flags': <String, Object?>{'mil': false, 'emissions_relevant': false, 'limp_possible': false},
      'applies_when': null,
      'confidence': 'low',
      'derived_from': <String, Object?>{
        'source': 'OBDex', 'licence': 'CC0-1.0', 'mode': 'structure-only',
      },
      'verification': 'standard_title_only',
      'needs_independent_review': true,
      'updated_at': '2026-10-03',
    };

Map<String, Object?> nameOnlyHi([String code = 'P0001']) => <String, Object?>{
      'schema_version': 2,
      'content_id': 'generic:$code:hi',
      'code': code,
      'system': 'powertrain',
      'title_hi': 'फ़्यूल वॉल्यूम रेगुलेटर A कंट्रोल सर्किट/ओपन',
      'meaning_hi': 'मानक नाम: फ़्यूल वॉल्यूम रेगुलेटर A कंट्रोल सर्किट/ओपन।',
      'rider_action_level': 'INFO',
      'rider_action_basis_hi': 'ड्राफ़्ट: सिर्फ़ मानक नाम',
      'rider_advice_hi': 'इस कोड का सिर्फ़ मानक नाम उपलब्ध है। अभी इसके बारे में हमारे पास और जानकारी नहीं है।',
      'can_ride_to_workshop': null,
      'flags': <String, Object?>{'mil': false, 'emissions_relevant': false, 'limp_possible': false},
      'applies_when': null,
      'confidence': 'low',
      'derived_from': <String, Object?>{
        'source': 'OBDex', 'licence': 'CC0-1.0', 'mode': 'structure-only',
      },
      'verification': 'standard_title_only',
      'needs_independent_review': true,
      'updated_at': '2026-10-03',
      'hi_status': 'machine',
    };

PackManifest manifestFor(String lang, {String packId = 'generic_basic_en'}) {
  final errors = <String>[];
  final m = PackManifest.parse(<String, Object?>{
    'pack_id': packId,
    'scope': 'generic',
    'language': lang,
    'version': 1,
    'entries_count': 1,
    'content_sha256': 'a' * 64,
    'created_at': '2026-10-03',
    'min_app_version': '1.0.0',
  }, errors);
  expect(errors, isEmpty);
  return m!;
}

final PackManifest enM = manifestFor('en');
final PackManifest hiM = manifestFor('hi', packId: 'generic_basic_hi');

Future<ImportOutcome> importLines(
    List<Map<String, Object?>> lines, String lang, String packId) async {
  final (store, _) = await openTempStore();
  final p = await buildPack(lines: lines, packId: packId, language: lang);
  final r = await store.importPack(
      manifestBytes: p.manifestBytes, entriesBytes: p.entriesBytes,
      source: PackSource.bundled, appVersion: '1.0.0');
  await store.close();
  return r;
}

void main() {
  group('K1 a good name-only entry is accepted', () {
    test('English, with empty cause and hint lists and a null can-ride', () {
      final v = validateEntry(nameOnlyEn(), enM);
      expect(v.errors, isEmpty);
      final e = v.entry!;
      expect(e.verification, kVerificationStandardTitleOnly);
      expect(e.causes, isEmpty);
      expect(e.hints, isEmpty);
      expect(e.canRide, isNull);
      expect(e.canRideReason, isNull);
      expect(e.riderAction, RiderAction.info);
      expect(e.flags, {'mil': false, 'emissions_relevant': false, 'limp_possible': false});
    });

    test('Hindi, with machine status', () {
      final v = validateEntry(nameOnlyHi(), hiM);
      expect(v.errors, isEmpty);
      expect(v.entry!.hiStatus, HiStatus.machine);
      expect(v.entry!.canRide, isNull);
    });

    test('the cause, hint and can-ride keys may be left out altogether', () {
      final l = nameOnlyEn()
        ..remove('likely_causes_en')
        ..remove('technician_hints_en')
        ..remove('can_ride_reason');
      expect(validateEntry(l, enM).errors, isEmpty);
      final l2 = nameOnlyEn()..['likely_causes_en'] = null..['technician_hints_en'] = null;
      expect(validateEntry(l2, enM).errors, isEmpty);
    });

    test('the flags may be left out and then default to false', () {
      final l = nameOnlyEn()..remove('flags');
      final v = validateEntry(l, enM);
      expect(v.errors, isEmpty);
      expect(v.entry!.flags.values.every((x) => x == false), isTrue);
      expect(v.entry!.flags.keys.toSet(), {'mil', 'emissions_relevant', 'limp_possible'});
    });

    test('a whole name-only pack imports (English and Hindi)', () async {
      final en = await importLines([nameOnlyEn('P0001'), nameOnlyEn('P0003')], 'en', 'generic_basic_en');
      expect(en.imported, isTrue, reason: '$en');
      final hi = await importLines([nameOnlyHi('P0001')], 'hi', 'generic_basic_hi');
      expect(hi.imported, isTrue, reason: '$hi');
    });
  });

  group('K1 a normal entry keeps every rule it had', () {
    Map<String, Object?> normal() => Map<String, Object?>.from(seedLine('P0120'));

    test('the real seed line is still accepted', () {
      expect(validateEntry(normal(), enM).errors, isEmpty);
    });

    test('missing causes are refused (key absent, empty, one item, null)', () {
      for (final mutate in <void Function(Map<String, Object?>)>[
        (l) => l.remove('likely_causes_en'),
        (l) => l['likely_causes_en'] = <String>[],
        (l) => l['likely_causes_en'] = ['only one'],
        (l) => l['likely_causes_en'] = null,
      ]) {
        final l = normal();
        mutate(l);
        expect(validateEntry(l, enM).ok, isFalse, reason: '$l');
      }
    });

    test('missing hints or can-ride are refused', () {
      for (final mutate in <void Function(Map<String, Object?>)>[
        (l) => l.remove('technician_hints_en'),
        (l) => l['technician_hints_en'] = <String>[],
        (l) => l['can_ride_to_workshop'] = null,
        (l) => l.remove('can_ride_to_workshop'),
        (l) => l['can_ride_reason'] = null,
        (l) => l.remove('flags'),
      ]) {
        final l = normal();
        mutate(l);
        expect(validateEntry(l, enM).ok, isFalse);
      }
    });

    test('every other verification label keeps the full rules', () {
      for (final v in ['ai_authored_from_standard_title', 'ai_authored_adapted']) {
        final l = nameOnlyEn()..['verification'] = v;
        expect(validateEntry(l, enM).ok, isFalse, reason: v);
      }
    });

    test('a Hindi row that is not name-only still needs a can-ride value', () {
      final l = nameOnlyHi()..['verification'] = 'ai_authored_from_standard_title';
      expect(validateEntry(l, hiM).ok, isFalse);
    });
  });

  group('K1 a name-only entry that claims more is refused', () {
    void refused(String why, void Function(Map<String, Object?>) mutate,
        {bool hindi = false}) {
      test(why, () {
        final l = hindi ? nameOnlyHi() : nameOnlyEn();
        mutate(l);
        final v = validateEntry(l, hindi ? hiM : enM);
        expect(v.ok, isFalse);
        expect(v.entry, isNull);
        expect(v.errors, isNotEmpty);
      });
    }

    refused('with causes', (l) => l['likely_causes_en'] = ['a loose plug', 'a bad sensor']);
    refused('with hints', (l) => l['technician_hints_en'] = ['check the plug']);
    refused('with causes (Hindi)', (l) => l['likely_causes_hi'] = ['ढीला प्लग', 'ख़राब सेंसर'], hindi: true);
    refused('with hints (Hindi)', (l) => l['technician_hints_hi'] = ['प्लग जाँचें'], hindi: true);
    refused('with a can-ride answer', (l) => l['can_ride_to_workshop'] = 'yes');
    refused('with a can-ride reason', (l) => l['can_ride_reason'] = 'ride gently');
    refused('with level STOP', (l) => l['rider_action_level'] = 'STOP');
    refused('with level SERVICE_SOON', (l) => l['rider_action_level'] = 'SERVICE_SOON');
    refused('with level MONITOR', (l) => l['rider_action_level'] = 'MONITOR');
    refused('with level STOP (Hindi)', (l) => l['rider_action_level'] = 'STOP', hindi: true);
    refused('with confidence medium', (l) => l['confidence'] = 'medium');
    refused('with confidence high', (l) => l['confidence'] = 'high');
    refused('with no title', (l) => l.remove('title_en'));
    refused('with a blank title', (l) => l['title_en'] = '  ');
    refused('with no meaning', (l) => l.remove('meaning_en'));
    refused('with no advice', (l) => l.remove('rider_advice_en'));
    refused('with no meaning (Hindi)', (l) => l.remove('meaning_hi'), hindi: true);
    refused('with no advice (Hindi)', (l) => l.remove('rider_advice_hi'), hindi: true);
    refused('with the mil flag set', (l) => (l['flags'] as Map)['mil'] = true);
    refused('with the limp flag set', (l) => (l['flags'] as Map)['limp_possible'] = true);
    refused('with the emissions flag set', (l) => (l['flags'] as Map)['emissions_relevant'] = true);
    refused('with a flag that is not a boolean', (l) => (l['flags'] as Map)['mil'] = 'no');
    refused('with an unknown flag', (l) => (l['flags'] as Map)['extra'] = false);
    refused('with a wrong verification word', (l) => l['verification'] = 'standard_title');
    refused('with a verification in the wrong case', (l) => l['verification'] = 'Standard_Title_Only');
    refused('with the word verified in its text', (l) => l['meaning_en'] = 'Standard name: verified circuit.');
    refused('with an unknown field', (l) => l['hint_en'] = 'x');
    refused('with a title over the limit', (l) => l['title_en'] = 'x' * 71);
    refused('with a manufacturer-defined code', (l) {
      l['code'] = 'P1234';
      l['content_id'] = 'generic:P1234:en';
    });

    test('a null level or a numeric level is refused, not thrown on', () {
      for (final bad in [null, 3, <Object?>[], true]) {
        final l = nameOnlyEn()..['rider_action_level'] = bad;
        expect(validateEntry(l, enM).ok, isFalse, reason: '$bad');
      }
    });
  });

  group('K1 a pack is all or nothing', () {
    test('one bad name-only line refuses the whole pack', () async {
      final bad = nameOnlyEn('P0003')..['likely_causes_en'] = ['x', 'y'];
      final r = await importLines([nameOnlyEn('P0001'), bad, nameOnlyEn('P0004')], 'en', 'generic_basic_en');
      expect(r.refusal, ImportRefusal.entriesInvalid);
    });

    test('a mixed pack of normal and name-only lines imports; a bad normal line sinks it',
        () async {
      final ok = await importLines(
          [seedLine('P0120'), nameOnlyEn('P0001')], 'en', 'generic_en');
      expect(ok.imported, isTrue, reason: '$ok');
      final broken = Map<String, Object?>.from(seedLine('P0121'))..['likely_causes_en'] = <String>[];
      final r = await importLines([nameOnlyEn('P0001'), broken], 'en', 'generic_en');
      expect(r.refusal, ImportRefusal.entriesInvalid);
      final r2 = await importLines(
          [seedLine('P0120'), nameOnlyEn('P0001')..['rider_action_level'] = 'STOP'],
          'en', 'generic_en');
      expect(r2.refusal, ImportRefusal.entriesInvalid);
    });

    test('a refused pack leaves the database exactly as it was', () async {
      final (store, _) = await openTempStore();
      final good = await buildPack(lines: [nameOnlyEn('P0001')], packId: 'generic_basic_en');
      expect((await store.importPack(
              manifestBytes: good.manifestBytes, entriesBytes: good.entriesBytes,
              source: PackSource.bundled, appVersion: '1.0.0'))
          .imported, isTrue);
      final bad = await buildPack(
          lines: [nameOnlyEn('P0001'), nameOnlyEn('P0003')..['confidence'] = 'high'],
          packId: 'generic_basic_en', version: 2);
      final r = await store.importPack(
          manifestBytes: bad.manifestBytes, entriesBytes: bad.entriesBytes,
          source: PackSource.bundled, appVersion: '1.0.0');
      expect(r.imported, isFalse);
      final rows = await store.db.query('kb_entry');
      expect(rows, hasLength(1));
      expect((await store.pack('generic_basic_en'))!.version, 1);
      await store.close();
    });
  });

  group('K1 fuzz: whatever a name-only line holds, the validator never throws', () {
    test('2,000 random mutations of a name-only line', () {
      final rnd = Random(4242);
      final junk = <Object?>[
        null, 0, -1, 7, 1.5, true, false, '', ' ', 'x', 'STOP', 'INFO', 'yes', 'low',
        <Object?>[], <Object?>['a'], <Object?>[1, null], <String, Object?>{},
        <String, Object?>{'mil': 1}, 'standard_title_only', '\u0000', 'é' * 300,
      ];
      final fields = nameOnlyEn().keys.toList();
      final hiFields = nameOnlyHi().keys.toList();
      for (var i = 0; i < 2000; i++) {
        final hindi = rnd.nextBool();
        final l = hindi ? nameOnlyHi() : nameOnlyEn();
        final names = hindi ? hiFields : fields;
        for (var k = 0; k < 1 + rnd.nextInt(4); k++) {
          final f = names[rnd.nextInt(names.length)];
          switch (rnd.nextInt(3)) {
            case 0:
              l.remove(f);
            case 1:
              l[f] = junk[rnd.nextInt(junk.length)];
            default:
              l['extra_${rnd.nextInt(5)}'] = junk[rnd.nextInt(junk.length)];
          }
        }
        // Always keep the line a name-only line so the lenient branch is hit.
        if (rnd.nextInt(4) != 0) l['verification'] = 'standard_title_only';
        final EntryValidation v;
        try {
          v = validateEntry(l, hindi ? hiM : enM);
        } catch (e, st) {
          fail('threw ${e.runtimeType} on $l\n$st');
        }
        if (v.ok) {
          // Anything that gets through is a clean name-only (or normal) entry.
          final e = v.entry!;
          if (e.verification == kVerificationStandardTitleOnly) {
            expect(e.riderAction, RiderAction.info);
            expect(e.causes, isEmpty);
            expect(e.hints, isEmpty);
            expect(e.canRide, isNull);
            expect(e.confidence, 'low');
          }
        }
      }
    });

    test('non-object lines and a line with every value wrong', () {
      for (final bad in [null, 3, 'text', <Object?>[], <Object?>[1]]) {
        expect(validateEntry(bad, enM).ok, isFalse);
      }
      final allWrong = {for (final k in nameOnlyEn().keys) k: 5};
      expect(validateEntry(allWrong, enM).ok, isFalse);
    });
  });
}
