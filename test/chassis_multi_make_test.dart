/// Danlite ELM — coverage for the four non-Royal-Enfield chassis additions
///
/// WHAT THIS PROVES:
///   1. Honda's published blink-code table is present, complete, bilingual,
///      and reachable through a reference tool that renders a real pattern.
///   2. Honda's 2024+ OBD2B models are treated as a genuinely different
///      capability from the blink-code ones — live-scannable, and with no
///      decoded table that a scan could wrongly borrow from.
///   3. A Bosch platform shows 0x5200's independently sourced meaning and
///      shows every other value as a raw module number explicitly marked
///      unverified — never as a description.
///   4. A CBS-only model is recognised as having no fault memory at all,
///      rather than being scanned and reported as unresponsive.
///
/// WHAT THIS DOES NOT PROVE: that any real motorcycle answers. Every adapter
/// here is simulated. Whether a Bajaj, Yamaha, Suzuki, KTM or 2024+ Honda
/// actually replies depends on the module's real CAN address and on whether
/// the rider's ELM327 can address a non-engine module at all — neither of
/// which a developer machine can establish.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:danlite_elm/constants/app_strings.dart';
import 'package:danlite_elm/constants/chassis_dtc_dictionary.dart';
import 'package:danlite_elm/constants/chassis_dtc_dictionary_hi.dart';
import 'package:danlite_elm/constants/chassis_modules.dart';
import 'package:danlite_elm/constants/obd_pids.dart';
import 'package:danlite_elm/providers/settings_provider.dart';
import 'package:danlite_elm/screens/honda_blink_reference_screen.dart';
import 'package:danlite_elm/services/bluetooth_classic_service.dart';
import 'package:danlite_elm/services/dtc_service.dart';
import 'package:danlite_elm/services/obd_service.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // 1. HONDA — the published blink-code table
  // ══════════════════════════════════════════════════════════════════════════
  group('Honda blink-code table', () {
    const honda = ChassisPlatforms.hondaAbsBlink;
    final table = ChassisDtcDatabase.byPlatform[honda]!;

    test('exactly the documented codes exist, and no others', () {
      expect(table.keys.toSet(), <String>{
        '1-1', '1-2', '1-3', '1-4', '1-5',
        '2-1', '2-3',
        '3-1', '3-2', '3-3', '3-4',
        '4-1', '4-2', '4-3',
        '5-1', '5-4',
        '6-1', '6-2',
        '7-1',
        '8-1',
      });
      expect(table.length, 20);
    });

    test('the front and rear wheel-speed sets mirror each other exactly', () {
      // The source states the rear set completely; the front set is its
      // positional counterpart. If either half is ever edited without the
      // other, this fails rather than silently describing a front fault as a
      // rear one.
      expect(table['1-1']!.description, 'Front wheel speed sensor circuit');
      expect(table['1-3']!.description, 'Rear wheel speed sensor circuit');
      expect(table['1-2']!.description, 'Front wheel speed sensor');
      expect(table['1-4']!.description, 'Rear wheel speed sensor');
      expect(table['2-1']!.description, 'Front pulser ring');
      expect(table['2-3']!.description, 'Rear pulser ring');
      expect(table['4-1']!.description, 'Front wheel lock');
      expect(table['4-3']!.description, 'Rear wheel lock');
    });

    test('the remaining documented codes read exactly as sourced', () {
      expect(table['1-5']!.description,
          'Front or rear wheel speed sensor circuit short');
      for (final code in <String>['3-1', '3-2', '3-3', '3-4']) {
        expect(table[code]!.description,
            'Solenoid valve (ABS modulator) fault',
            reason: 'the source gives all four 3-x codes the same meaning');
      }
      expect(table['5-1']!.description, 'ABS pump motor lock');
      expect(table['5-4']!.description, 'ABS power supply relay');
      expect(table['6-1']!.description, contains('too low'));
      expect(table['6-2']!.description, contains('too high'));
      expect(table['7-1']!.description, 'Tire size mismatch');
      expect(table['8-1']!.description, 'ABS control unit fault');
    });

    test('4-2 is the only entry that claims no meaning, and says so', () {
      // The one genuine gap: the source lists the code without describing it.
      // Nothing may be invented to fill that, and nothing may be silently
      // presented as if it had been sourced.
      final unverified = table.entries
          .where((e) => !e.value.meaningVerified)
          .map((e) => e.key)
          .toSet();
      expect(unverified, <String>{'4-2'});
      expect(table['4-2']!.description.toLowerCase(),
          contains('without a description'));

      final resolved = DtcLocalizations.chassisEntry(honda, '4-2', 'en')!;
      expect(resolved.meaningVerified, isFalse,
          reason: 'the UI needs this to render its unverified treatment');
    });

    test('every entry carries the table-level remedy guidance', () {
      for (final entry in table.values) {
        expect(entry.remedy, ChassisDtcDatabase.hondaBlinkRemedy);
      }
      // The guidance the source actually gives, all of it, once.
      final remedy = ChassisDtcDatabase.hondaBlinkRemedy.toLowerCase();
      for (final step in <String>[
        'air gap',
        'continuity',
        'modulator',
        'fuse',
        '30 km/h',
      ]) {
        expect(remedy, contains(step), reason: 'missing documented step: $step');
      }
    });

    test('the blink table has no component or query column, as sourced', () {
      for (final entry in table.values) {
        expect(entry.component, isEmpty);
        expect(entry.query, isEmpty);
      }
    });

    test('a blink pattern can never collide with a scanned numeric code', () {
      // The property that keeps blink data out of a live read. A blink key is
      // not in hex-suffix notation, so the SAE alias index skips it entirely;
      // a scanned C1xxx therefore cannot resolve to a blink description on any
      // platform, including this one.
      for (final code in table.keys) {
        expect(ChassisDtcDatabase.deriveSaeCode(code), isNull,
            reason: '$code must not derive an SAE code');
      }
      for (final scanned in <String>['C1015', 'C1200', 'C1043', 'U2922']) {
        expect(ChassisDtcDatabase.canonicalCode(honda, scanned), isNull,
            reason: '$scanned must not resolve into the blink table');
        expect(DtcLocalizations.chassisEntry(honda, scanned, 'en'), isNull);
      }
    });

    test('English and Hindi cover the same codes, and Hindi is really Hindi',
        () {
      expect(ChassisDtcDictionaryHi.byPlatform[honda]!.keys.toSet(),
          table.keys.toSet());
      final devanagari = RegExp(r'[ऀ-ॿ]');
      for (final code in table.keys) {
        final hi = DtcLocalizations.chassisEntry(honda, code, 'hi')!;
        expect(devanagari.hasMatch(hi.description), isTrue,
            reason: '$code has no Hindi description');
        expect(devanagari.hasMatch(hi.remedy), isTrue,
            reason: '$code has no Hindi remedy');
      }
    });

    test('a language with no chassis translations falls back to English', () {
      final ta = DtcLocalizations.chassisEntry(honda, '4-3', 'ta')!;
      final en = DtcLocalizations.chassisEntry(honda, '4-3', 'en')!;
      expect(ta.description, en.description);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 2. HONDA — blink-code models are NEVER offered as a live scan
  // ══════════════════════════════════════════════════════════════════════════
  group('Honda blink-code models are reference-only, not scannable', () {
    test('an ordinary Honda model resolves to the blink platform', () {
      for (final model in <String>[
        'CB350',
        'CBR 250R',
        'Africa Twin',
        'Unicorn 160',
      ]) {
        expect(ChassisPlatforms.resolve('Honda', model),
            ChassisPlatforms.hondaAbsBlink,
            reason: 'failed on model: "$model"');
      }
    });

    test('the platform declares itself unreachable over the adapter', () {
      final p = ChassisPlatforms.byKey(ChassisPlatforms.hondaAbsBlink)!;
      expect(p.readMethod, ChassisReadMethod.dlcBlinkCodeManual);
      expect(p.isBlinkCodeOnly, isTrue);
      expect(p.isLiveScannable, isFalse,
          reason: 'nothing in the app may present this as a scan');
      expect(p.brakeSystem, ChassisBrakeSystem.abs,
          reason: 'these bikes do have ABS — it simply is not readable here');
      expect(p.capabilityProvenance, isNotEmpty);
    });

    test('exactly one platform in the whole registry is blink-code only', () {
      final blink = ChassisPlatforms.all
          .where((p) => p.isBlinkCodeOnly)
          .map((p) => p.key)
          .toSet();
      expect(blink, <String>{ChassisPlatforms.hondaAbsBlink});
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 3. HONDA — the reference tool renders a real pattern (REAL PROOF)
  // ══════════════════════════════════════════════════════════════════════════
  group('the blink reference screen', () {
    Widget harness() => ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
          child: const MaterialApp(home: HondaBlinkReferenceScreen()),
        );

    /// Tap one flash-count chip in a named row.
    ///
    /// The row has to be named: both rows offer "3", so searching for the
    /// digit alone would drive whichever row happened to come first and the
    /// test would pass or fail for the wrong reason.
    Future<void> pick(WidgetTester tester, Key row, String digit) async {
      await tester.tap(find.descendant(
        of: find.byKey(row),
        matching: find.widgetWithText(GestureDetector, digit),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('opens on a documented pattern and shows its real description',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // Its manual, reference-only nature must be unmistakable and on screen
      // before anything else.
      expect(find.text(AppStrings.get('blinkRefManualBadge', 'en')),
          findsOneWidget);
      expect(find.text(AppStrings.get('blinkRefIntro', 'en')), findsOneWidget);

      // The default pattern (1-1) resolves to Honda's own description.
      expect(find.text('Front wheel speed sensor circuit'), findsWidgets);

      // Nothing on this screen offers to read the motorcycle.
      expect(find.text(AppStrings.get('scanAbsModule', 'en')), findsNothing);
      expect(find.byIcon(Icons.radar_rounded), findsNothing);
    });

    testWidgets('selecting 4-3 shows the rear wheel lock entry and its remedy',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // Pick four long flashes, then three short — the pattern a rider counts
      // off the ABS warning lamp.
      await pick(tester, HondaBlinkReferenceScreen.longFlashRowKey, '4');
      await pick(tester, HondaBlinkReferenceScreen.shortFlashRowKey, '3');

      expect(find.text('4-3'), findsWidgets);
      expect(find.text('Rear wheel lock'), findsWidgets);
      expect(find.text(ChassisDtcDatabase.hondaBlinkRemedy), findsOneWidget);
    });

    testWidgets('an undocumented pattern says so instead of inventing a fault',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // 8-1 is documented; 8-5 is not. The pickers offer every digit the table
      // uses, so undocumented combinations are reachable and must be honest.
      await pick(tester, HondaBlinkReferenceScreen.longFlashRowKey, '8');
      await pick(tester, HondaBlinkReferenceScreen.shortFlashRowKey, '5');

      expect(find.text('8-5'), findsOneWidget);
      expect(find.text(AppStrings.get('blinkRefNoMatch', 'en')), findsOneWidget);
      // The decisive part: nothing about a fault is claimed. The remedy text
      // is rendered only by the result card, never by a table row, so its
      // absence proves no entry was resolved for this undocumented pattern.
      expect(find.text(ChassisDtcDatabase.hondaBlinkRemedy), findsNothing,
          reason: 'an undocumented pattern must not be given a remedy');
      expect(find.text('ABS control unit fault'), findsNothing,
          reason: 'the nearest documented code (8-1) must not be shown as if '
              'it were the answer');
    });

    testWidgets('the 4-2 gap is flagged rather than presented as a meaning',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await pick(tester, HondaBlinkReferenceScreen.longFlashRowKey, '4');
      await pick(tester, HondaBlinkReferenceScreen.shortFlashRowKey, '2');

      expect(find.text(AppStrings.get('absRawUnverified', 'en')),
          findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 4. HONDA 2024+ OBD2B — a genuinely different capability
  // ══════════════════════════════════════════════════════════════════════════
  group('Honda 2024+ OBD2B models', () {
    test('Hornet 2.0 spellings resolve to the OBD2B platform, not the blink '
        'one', () {
      for (final model in <String>['Hornet 2.0', 'hornet20', 'CB Hornet 2.0']) {
        expect(ChassisPlatforms.resolve('Honda', model),
            ChassisPlatforms.hondaObd2b,
            reason: 'failed on model: "$model"');
      }
    });

    test('it is live-scannable and carries no decoded table', () {
      final p = ChassisPlatforms.byKey(ChassisPlatforms.hondaObd2b)!;
      expect(p.isLiveScannable, isTrue);
      expect(p.isBlinkCodeOnly, isFalse);
      expect(p.dictionaryKind, ChassisDictionaryKind.none);
      expect(p.showsRawUnverifiedCodes, isFalse,
          reason: 'Honda is not a Bosch platform — its codes are not shown as '
              'Bosch module numbers');
      expect(ChassisDtcDatabase.hasDictionary(ChassisPlatforms.hondaObd2b),
          isFalse);
    });

    test('a scanned code on it is never described from the blink table', () {
      // The decisive isolation check. Honda's blink table sits under the same
      // make; if a numeric DTC could reach it, a rider would be shown a
      // blink-code meaning for a completely unrelated value.
      for (final code in <String>['C1015', 'C1043', 'C1200', 'C1011']) {
        expect(
            DtcLocalizations.chassisEntry(
                ChassisPlatforms.hondaObd2b, code, 'en'),
            isNull,
            reason: '$code must resolve to no description at all');
      }
    });

    // A plain async test, not testWidgets: this drives the real ObdService
    // against a simulated adapter, and its timeouts and retries run on real
    // timers that testWidgets' fake clock would never advance.
    test('a simulated OBD2B Honda scan reads the code and describes nothing',
        () async {
      final elm = AnsweringElm(respondingHeader: '7B0', dtcBytes: '50 43 00');
      final obd = ObdService(elm);
      expect(
          await obd.connectBluetooth(const BtDevice(
              name: 'OBDII', address: '00:11:22:33:44:55', bonded: true)),
          isTrue);

      final codes = await obd.readChassisDtcs(
          vehicleMake: 'Honda', vehicleModel: 'Hornet 2.0');

      expect(obd.chassisScanOutcome, ChassisScanOutcome.faultsFound);
      expect(codes.single.code, 'C1043');
      expect(codes.single.description, isEmpty,
          reason: 'no verified meaning exists, so none is claimed');
      expect(codes.single.remedy, isEmpty);
      expect(codes.single.severity, 'unknown');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 120)));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 5. BOSCH RAW-HEX MODE
  // ══════════════════════════════════════════════════════════════════════════
  group('Bosch platforms — raw values, one verified meaning', () {
    const boschPlatforms = <String>[
      ChassisPlatforms.bajajBoschAbs,
      ChassisPlatforms.yamahaBoschAbs,
      ChassisPlatforms.suzukiBoschAbs,
      ChassisPlatforms.ktmBoschAbs,
    ];

    test('the four makes resolve, on any model', () {
      expect(ChassisPlatforms.resolve('Bajaj', 'Pulsar NS200'),
          ChassisPlatforms.bajajBoschAbs);
      expect(ChassisPlatforms.resolve('Yamaha', 'MT-15'),
          ChassisPlatforms.yamahaBoschAbs);
      expect(ChassisPlatforms.resolve('Suzuki', 'Gixxer SF 250'),
          ChassisPlatforms.suzukiBoschAbs);
      expect(ChassisPlatforms.resolve('KTM', 'Duke 390'),
          ChassisPlatforms.ktmBoschAbs);
      // A blank model still resolves to nothing, for every make.
      expect(ChassisPlatforms.resolve('Bajaj', ''), isNull);
      expect(ChassisPlatforms.resolve('KTM', '   '), isNull);
    });

    test('each is live-scannable and flagged as showing raw values', () {
      for (final key in boschPlatforms) {
        final p = ChassisPlatforms.byKey(key)!;
        expect(p.isLiveScannable, isTrue, reason: key);
        expect(p.showsRawUnverifiedCodes, isTrue, reason: key);
        expect(p.dictionaryKind, ChassisDictionaryKind.rawUnverifiedHex,
            reason: key);
        expect(p.brakeSystem, ChassisBrakeSystem.abs, reason: key);
      }
    });

    test('exactly one code is decoded, and it is 0x5200', () {
      expect(ChassisDtcDatabase.boschSharedCodes.keys.toSet(),
          <String>{'5200H'});
      for (final key in boschPlatforms) {
        expect(ChassisDtcDatabase.byPlatform[key],
            same(ChassisDtcDatabase.boschSharedCodes),
            reason: '$key must share the one Bosch-module-level table');
      }
    });

    test('0x5200 is reachable from the code a scan actually produces', () {
      // 0x5200 decodes to C1200 through the same standard bit-packing every
      // other code in this app uses. Without that, the entry would be dead
      // data no scan could ever match.
      expect(ChassisDtcDatabase.deriveSaeCode('5200H'), 'C1200');
      expect(ChassisDtcDatabase.rawModuleLabel('C1200'), '0x5200');
      expect(ChassisDtcDatabase.rawModuleValue('C1200'), 0x5200);
    });

    test('0x5200 shows its real, sourced meaning on every Bosch make', () {
      for (final key in boschPlatforms) {
        final en = DtcLocalizations.chassisEntry(key, 'C1200', 'en')!;
        expect(en.description,
            'ABS ECU EEPROM / variant read error (checksum or access byte '
            'corrupted)',
            reason: key);
        expect(en.meaningVerified, isTrue, reason: key);
        // Sourced as a fault, not as a fix. No remedy may be invented.
        expect(en.remedy, isEmpty, reason: key);

        final hi = DtcLocalizations.chassisEntry(key, 'C1200', 'hi')!;
        expect(RegExp(r'[ऀ-ॿ]').hasMatch(hi.description), isTrue, reason: key);
        expect(hi.meaningVerified, isTrue, reason: key);
      }
    });

    // ── THE NO-FABRICATION TEST ───────────────────────────────────────────
    test('an unrecognised Bosch code resolves to nothing but a raw value', () {
      // The single most important assertion in this file. Every value a Bosch
      // module can report, other than 0x5200, must come back with no
      // dictionary entry at all — so the only thing the UI can render is the
      // raw module number under its "meaning not verified" treatment. There is
      // no path by which a guess reaches a braking-fault card.
      final everyOtherValue = <String>[];
      for (var v = 0x5000; v <= 0x53FF; v++) {
        if (v == 0x5200) continue;
        final sae = ObdParser.decodeDtcPair((v >> 8) & 0xFF, v & 0xFF);
        if (sae != null) everyOtherValue.add(sae);
      }
      expect(everyOtherValue.length, greaterThan(1000),
          reason: 'sanity: the sweep must actually cover the 0x5xxx family');

      for (final key in boschPlatforms) {
        for (final code in everyOtherValue) {
          expect(DtcLocalizations.chassisEntry(key, code, 'en'), isNull,
              reason: '$key/$code resolved to a description it has no source '
                  'for');
          expect(DtcLocalizations.chassisEntry(key, code, 'hi'), isNull,
              reason: '$key/$code resolved in Hindi');
          expect(ChassisDtcDatabase.canonicalCode(key, code), isNull,
              reason: '$key/$code matched a dictionary key');
        }
      }
    });

    test('Royal Enfield codes never leak onto a Bosch make, and vice versa',
        () {
      // Royal Enfield's Bullet EFI platform is itself Bosch-based and uses the
      // same notation, which is exactly why this has to be checked rather than
      // assumed. Its 19 decoded values must not become descriptions on Bajaj.
      for (final code in ChassisDtcDatabase
          .byPlatform[ChassisPlatforms.royalEnfieldBulletEfi]!.keys) {
        final sae = ChassisDtcDatabase.deriveSaeCode(code)!;
        expect(
            DtcLocalizations.chassisEntry(
                ChassisPlatforms.bajajBoschAbs, sae, 'en'),
            isNull,
            reason: '$code ($sae) leaked from Royal Enfield onto Bajaj');
      }
      // And 0x5200 is not silently added to Royal Enfield's tables either.
      expect(
          DtcLocalizations.chassisEntry(
              ChassisPlatforms.royalEnfieldBulletEfi, 'C1200', 'en'),
          isNull);
      expect(
          DtcLocalizations.chassisEntry(
              ChassisPlatforms.royalEnfieldClassic350, 'C1200', 'en'),
          isNull);
    });

    test('rawModuleLabel is the exact inverse of the existing decoder', () {
      // It must never drift from ObdParser.decodeDtcPair, or the number shown
      // to a rider would not be the number their module reported.
      for (var v = 0x4000; v <= 0x7FFF; v += 7) {
        final sae = ObdParser.decodeDtcPair((v >> 8) & 0xFF, v & 0xFF);
        if (sae == null) continue;
        expect(ChassisDtcDatabase.rawModuleValue(sae), v, reason: sae);
        expect(ChassisDtcDatabase.rawModuleLabel(sae),
            '0x${v.toRadixString(16).toUpperCase().padLeft(4, '0')}',
            reason: sae);
      }
      expect(ChassisDtcDatabase.rawModuleLabel('5200H'), isNull,
          reason: 'a manual-notation key is not an SAE code');
      expect(ChassisDtcDatabase.rawModuleLabel('4-2'), isNull);
    });

    test('a simulated Bajaj scan yields 0x5200 with its real meaning',
        () async {
      final elm = AnsweringElm(respondingHeader: '7B0', dtcBytes: '52 00 00');
      final obd = ObdService(elm);
      expect(
          await obd.connectBluetooth(const BtDevice(
              name: 'OBDII', address: '00:11:22:33:44:55', bonded: true)),
          isTrue);

      final codes = await obd.readChassisDtcs(
          vehicleMake: 'Bajaj', vehicleModel: 'Pulsar NS200');

      expect(obd.chassisScanOutcome, ChassisScanOutcome.faultsFound);
      final card = codes.single;
      expect(card.code, 'C1200');
      expect(ChassisDtcDatabase.rawModuleLabel(card.code), '0x5200');
      expect(card.description, contains('EEPROM'),
          reason: 'the one sourced Bosch meaning is shown');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('a simulated Bajaj scan yields any other value undescribed',
        () async {
      final elm = AnsweringElm(respondingHeader: '7B0', dtcBytes: '50 43 00');
      final obd = ObdService(elm);
      expect(
          await obd.connectBluetooth(const BtDevice(
              name: 'OBDII', address: '00:11:22:33:44:55', bonded: true)),
          isTrue);

      final codes = await obd.readChassisDtcs(
          vehicleMake: 'Bajaj', vehicleModel: 'Pulsar NS200');

      final card = codes.single;
      expect(card.code, 'C1043');
      // The value is real and is shown; the meaning is absent and stays absent.
      expect(ChassisDtcDatabase.rawModuleLabel(card.code), '0x5043');
      expect(card.description, isEmpty);
      expect(card.query, isEmpty);
      expect(card.remedy, isEmpty);
      expect(card.severity, 'unknown');

      await obd.disconnect();
      await elm.close();
    }, timeout: const Timeout(Duration(seconds: 120)));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 6. CBS / ABS GATING
  // ══════════════════════════════════════════════════════════════════════════
  group('CBS gating', () {
    test('CBS models resolve to the CBS platform, not the blink one', () {
      for (final model in <String>[
        'Activa',
        'Activa 6G',
        'Activa 125',
        'Dio',
        'Shine 100',
      ]) {
        expect(ChassisPlatforms.resolve('Honda', model),
            ChassisPlatforms.hondaCbs,
            reason: 'failed on model: "$model"');
      }
    });

    test('the CBS platform declares that there is nothing to read', () {
      final p = ChassisPlatforms.byKey(ChassisPlatforms.hondaCbs)!;
      expect(p.isCbsOnly, isTrue);
      expect(p.brakeSystem, ChassisBrakeSystem.cbs);
      expect(p.readMethod, ChassisReadMethod.notApplicable);
      expect(p.isLiveScannable, isFalse);
      expect(p.dictionaryKind, ChassisDictionaryKind.none);
      expect(ChassisDtcDatabase.hasDictionary(ChassisPlatforms.hondaCbs),
          isFalse,
          reason: 'a bike with no fault memory can have no fault table');
      // The classification is inferred, so it must carry its own provenance.
      expect(p.capabilityProvenance, contains('regulat'));
    });

    test('no ABS platform is ever flagged CBS', () {
      final cbs = ChassisPlatforms.all
          .where((p) => p.isCbsOnly)
          .map((p) => p.key)
          .toSet();
      expect(cbs, <String>{ChassisPlatforms.hondaCbs});
      // Royal Enfield in particular must be untouched by this flag.
      for (final p in ChassisPlatforms.forManufacturer(
          ChassisManufacturers.royalEnfield)) {
        expect(p.isCbsOnly, isFalse, reason: p.key);
        expect(p.isLiveScannable, isTrue, reason: p.key);
        expect(p.dictionaryKind, ChassisDictionaryKind.decoded, reason: p.key);
      }
    });

    test('the gate has real copy in both shipped languages', () {
      // The gate replaces the scan UI, so its message is the entire screen. A
      // missing key would leave a rider looking at a raw identifier.
      for (final key in <String>[
        'absCbsTitle',
        'absCbsDesc',
        'absCbsProvenance',
        'absCbsScanAnyway',
      ]) {
        for (final lang in <String>['en', 'hi']) {
          final text = AppStrings.get(key, lang);
          expect(text, isNot(key), reason: '$key missing for "$lang"');
          expect(text.length, greaterThan(4), reason: '$key/$lang too short');
        }
      }
      expect(AppStrings.get('absCbsDesc', 'en'), contains('CBS'));
      expect(AppStrings.get('absCbsDesc', 'en'),
          contains('no chassis fault codes'));
      expect(RegExp(r'[ऀ-ॿ]').hasMatch(AppStrings.get('absCbsDesc', 'hi')),
          isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 7. THE MAKES WITH NO REAL DATA STAY UNSUPPORTED
  // ══════════════════════════════════════════════════════════════════════════
  group('TVS and Hero are not quietly absorbed', () {
    test('neither make resolves, and neither has a platform', () {
      for (final make in <String>[
        'TVS',
        'tvs motor',
        'Hero',
        'Hero MotoCorp',
        'heromotocorp',
      ]) {
        expect(ChassisManufacturers.resolveKey(make), isNull, reason: make);
        expect(ChassisPlatforms.resolve(make, 'Apache RTR 160'), isNull,
            reason: make);
      }
      for (final p in ChassisPlatforms.all) {
        expect(p.manufacturerKey, isNot('tvs'), reason: p.key);
        expect(p.manufacturerKey, isNot('hero'), reason: p.key);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 8. REGISTRY-WIDE INVARIANTS
  // ══════════════════════════════════════════════════════════════════════════
  group('registry-wide invariants', () {
    test('platform keys are unique and every alias belongs to one platform',
        () {
      final keys = ChassisPlatforms.all.map((p) => p.key).toList();
      expect(keys.toSet().length, keys.length, reason: 'duplicate platform key');

      final seen = <String, String>{};
      for (final p in ChassisPlatforms.all) {
        for (final alias in p.modelAliases) {
          expect(alias, ChassisManufacturers.normalise(alias),
              reason: '"$alias" is not stored normalised, so it can never '
                  'match a rider\'s free-text model');
          final owner = '${p.manufacturerKey}/$alias';
          expect(seen.containsKey(owner), isFalse,
              reason: 'alias "$alias" is claimed twice under '
                  '${p.manufacturerKey}');
          seen[owner] = p.key;
        }
      }
    });

    test('a decoded platform really has a table, and an undecoded one has no '
        'unsourced entries', () {
      for (final p in ChassisPlatforms.all) {
        final table = ChassisDtcDatabase.byPlatform[p.key];
        switch (p.dictionaryKind) {
          case ChassisDictionaryKind.decoded:
            expect(table, isNotNull, reason: '${p.key} claims to be decoded');
            expect(table, isNotEmpty, reason: p.key);
            break;
          case ChassisDictionaryKind.rawUnverifiedHex:
            // Only the Bosch-module-level value may be present.
            expect(table!.keys.toSet(), <String>{'5200H'}, reason: p.key);
            break;
          case ChassisDictionaryKind.none:
            expect(table, isNull,
                reason: '${p.key} claims no dictionary but ships one');
            break;
        }
      }
    });

    test('a CBS platform can never also be live-scannable', () {
      for (final p in ChassisPlatforms.all) {
        if (p.isCbsOnly) {
          expect(p.isLiveScannable, isFalse, reason: p.key);
          expect(p.readMethod, ChassisReadMethod.notApplicable, reason: p.key);
        }
      }
    });

    test('every non-default capability carries a provenance note', () {
      for (final p in ChassisPlatforms.all) {
        final isDefault = p.brakeSystem == ChassisBrakeSystem.abs &&
            p.readMethod == ChassisReadMethod.udsLiveScan &&
            p.dictionaryKind == ChassisDictionaryKind.decoded;
        if (!isDefault) {
          expect(p.capabilityProvenance, isNotEmpty,
              reason: '${p.key} claims a non-default capability with no stated '
                  'reason');
        }
      }
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// A SIMULATED ELM327 WITH A MODULE THAT ACTUALLY ANSWERS
// ═══════════════════════════════════════════════════════════════════════════
/// Mirrors `ProgrammableElm` in `chassis_addressing_coverage_test.dart`, with
/// the one difference these tests need: the DTC bytes the module reports are
/// configurable, so the same simulated bike can hand back 0x5200 (the one
/// decoded Bosch value) or any undecoded value.
///
/// It is a simulation. It proves the software's decode and display path, and
/// nothing whatsoever about real hardware.
class AnsweringElm extends BluetoothClassicService {
  AnsweringElm({required this.respondingHeader, required this.dtcBytes});

  /// The `ATSH` value at which the simulated module answers `19 02 FF`.
  final String respondingHeader;

  /// The three DTC bytes of the UDS record, space-separated (e.g. `'52 00 00'`
  /// for 0x5200 with failure type 0x00).
  final String dtcBytes;

  final _ctrl = StreamController<String>.broadcast();
  bool _connected = false;
  String? _header;

  @override
  Stream<String> get dataStream => _ctrl.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect(BtDevice device) async {
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<bool> write(String cmd) async {
    if (!_connected) return false;
    final c = cmd.trim().toUpperCase();

    if (c.isEmpty) {
      _reply('\r>');
      return true;
    }
    if (c.startsWith('ATSH')) {
      _header = c.substring(4);
    } else if (c == 'ATZ' || c == ObdPids.autoProtocol || c == 'ATAR') {
      _header = null;
    }

    if (c == 'ATZ') {
      _reply('\r\rELM327 v1.5\r\r>');
    } else if (c == 'ATDPN') {
      _reply('\r6\r\r>');
    } else if (c.startsWith('AT')) {
      _reply('\rOK\r\r>');
    } else if (c == '0100') {
      _reply('\r41 00 BE 3E B8 11\r\r>');
    } else if (_header == null) {
      // The functional broadcast, where only the engine ECU answers. If one of
      // these ever surfaced as a chassis fault, an engine problem would have
      // been relabelled a braking problem.
      _reply(c == '03' ? '\r7E8 06 43 01 01 72\r\r>' : '\r>');
    } else if (_header == respondingHeader && c == '1902FF') {
      final resp = (int.parse(_header!, radix: 16) + 8)
          .toRadixString(16)
          .toUpperCase();
      _reply('\r$resp 07 59 02 FF $dtcBytes 2F\r\r>');
    } else {
      _reply('\rNO DATA\r\r>');
    }
    return true;
  }

  void _reply(String payload) {
    scheduleMicrotask(() {
      if (!_ctrl.isClosed) _ctrl.add(payload);
    });
  }

  Future<void> close() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }
}
