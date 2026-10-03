/// Phase 1B — B5 the resolver. Pure Dart: the real seed content (validated by
/// the real importer rules), the real platform manual tables, no SQLite.
library;

import 'package:danlite_elm/constants/chassis_dtc_dictionary.dart';
import 'package:danlite_elm/knowledge/fault_resolver.dart';
import 'package:danlite_elm/knowledge/kb_models.dart';
import 'package:danlite_elm/knowledge/kb_validator.dart';
import 'package:danlite_elm/models/fault_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/kb_pack_builder.dart';

final _at = DateTime.utc(2026, 10, 2);

PackManifest _manifest({String scope = 'generic', String language = 'en', String id = 'p'}) =>
    PackManifest.parse({
      'pack_id': id,
      'scope': scope,
      'language': language,
      'version': 1,
      'entries_count': 0,
      'content_sha256': '0' * 64,
      'created_at': '2026-10-02',
      'min_app_version': '1.0.0',
      'review_state': 'draft',
    }, <String>[])!;

/// The real bundled English entries, through the real validator.
final List<KbEntry> seedEntries = [
  for (final l in seedLines()) validateEntry(l, _manifest()).entry!,
];

KbEntry entry(
  String code, {
  ScopeKind scope = ScopeKind.generic,
  String ref = '',
  String lang = 'en',
  String? title,
  String? meaning,
  List<String> causes = const <String>[],
  String? advice,
  List<String> hints = const <String>[],
  String? rideReason,
  RiderAction? action,
  CanRide? ride,
  Map<String, Object?>? appliesWhen,
  bool revoked = false,
  bool review = false,
  String? packReviewState = 'reviewed',
}) =>
    KbEntry(
      contentId: '${scope.db}${ref.isEmpty ? '' : ':$ref'}:$code:$lang',
      code: code,
      scopeKind: scope,
      scopeRef: ref,
      language: lang,
      title: title,
      meaning: meaning,
      causes: causes,
      riderAdvice: advice,
      hints: hints,
      canRideReason: rideReason,
      riderAction: action,
      canRide: ride,
      appliesWhen: appliesWhen,
      verification: 'ai_authored_adapted',
      needsIndependentReview: review,
      packId: 'p-${scope.db}-$lang',
      revoked: revoked,
      packReviewState: packReviewState,
    );

FaultRecord obd(String code) =>
    FaultRecord.fromObdCode(code, source: ReadSource.mode03, readAt: _at);
FaultRecord typed(String code, [DtcFormat f = DtcFormat.sae2]) =>
    FaultRecord.manual(code, format: f, readAt: _at);

const classic350 = VehicleContext(
    make: 'Royal Enfield', model: 'Classic 350',
    manufacturerKey: ChassisManufacturers.royalEnfield,
    platformKey: ChassisPlatforms.royalEnfieldClassic350);

VehicleContext profile(String make, String model) =>
    VehicleContext.fromProfile(make: make, model: model);

/// A legacy source standing in for the 31-entry table.
LegacyText? fakeLegacy(String code, String lang) {
  if (code == 'P0100') {
    return const LegacyText(
        title: 'Old table text', cause: 'old cause', action: 'old action', severity: 'high');
  }
  return null;
}

FaultResolver resolverWith(List<KbEntry> extra, {bool seed = true}) => FaultResolver(
    index: KnowledgeIndex([if (seed) ...seedEntries, ...extra]), legacy: fakeLegacy);

void main() {
  final r = resolverWith(const <KbEntry>[]);

  test('the seed validates: 308 entries, none manufacturer-defined', () {
    expect(seedEntries, hasLength(308));
  });

  group('L1 vehicle', () {
    final variant = entry('P0120', scope: ScopeKind.vehicle, ref: 'classic350_2024_bs6',
        title: 'Variant text', meaning: 'Variant meaning.');
    final plat = entry('P0120', scope: ScopeKind.platform,
        ref: ChassisPlatforms.royalEnfieldClassic350, title: 'Platform text', meaning: 'm.');
    test('a matching vehicle entry wins over platform and generic', () {
      final v = VehicleContext(
          platformKey: ChassisPlatforms.royalEnfieldClassic350,
          vehicleKey: 'classic350_2024_bs6');
      final res = resolverWith([variant, plat]).resolve(obd('P0120'), v, 'en');
      expect(res.level, ResolvedLevel.l1Vehicle);
      expect(res.title, 'Variant text');
    });
    test('another vehicle\'s entry is ignored', () {
      final v = VehicleContext(
          platformKey: ChassisPlatforms.royalEnfieldClassic350, vehicleKey: 'other');
      expect(resolverWith([variant, plat]).resolve(obd('P0120'), v, 'en').level,
          ResolvedLevel.l2Platform);
    });
    test('no vehicle key: L1 is never reached', () {
      expect(resolverWith([variant]).resolve(obd('P0120'), classic350, 'en').level,
          ResolvedLevel.l4Generic);
    });
  });

  group('L2 platform', () {
    test('Classic 350 ABS code from the service manual table', () {
      final res = r.resolve(obd('C1015'), classic350, 'en', domain: FaultDomain.abs);
      expect(res.level, ResolvedLevel.l2Platform);
      expect(res.provenance, Provenance.serviceManual);
      expect(res.title, 'ABS Pump/Motor Failure');
      expect(res.platformDetail!.remedy, 'Change ABS unit');
      expect(res.platformDetail!.component, 'RFP/RFP_HW');
      expect(res.hasMeaning, isTrue);
      expect(res.riderAction, isNull, reason: 'the manual gives no rider action');
    });
    test('Bullet EFI: a scanned SAE code reaches its hex-H manual row', () {
      final res = r.resolve(obd('C1043'), profile('Royal Enfield', 'Bullet EFI'), 'en',
          domain: FaultDomain.abs);
      expect(res.level, ResolvedLevel.l2Platform);
      expect(res.title, ChassisDtcDatabase.lookup(ChassisPlatforms.royalEnfieldBulletEfi, '5043H')!.description);
    });
    test('Bullet EFI: a typed hex-H value', () {
      final res = r.resolve(typed('5043H', DtcFormat.hexH),
          profile('Royal Enfield', 'Continental GT'), 'en');
      expect(res.level, ResolvedLevel.l2Platform);
    });
    test('the same number means different things on two Royal Enfield platforms', () {
      final c = r.resolve(obd('C1052'), classic350, 'en', domain: FaultDomain.abs);
      final b = r.resolve(obd('C1052'), profile('Royal Enfield', 'Bullet EFI'), 'en',
          domain: FaultDomain.abs);
      expect(c.title, isNot(b.title));
      expect(c.title, ChassisDtcDatabase.lookup(ChassisPlatforms.royalEnfieldClassic350, 'C1052')!.description);
    });
    test('Honda blink pattern on a Honda blink-code bike', () {
      final res = r.resolve(typed('4-3', DtcFormat.blink), profile('Honda', 'CB350'), 'en');
      expect(res.level, ResolvedLevel.l2Platform);
      expect(res.title, 'Rear wheel lock');
    });
    test('Honda 4-2: in the manual without a meaning, and labelled so', () {
      final res = r.resolve(typed('4-2', DtcFormat.blink), profile('Honda', 'CB350'), 'en');
      expect(res.provenance, Provenance.serviceManualNoMeaning);
      expect(res.hasMeaning, isFalse);
    });
    test('a store platform entry beats the manual table', () {
      final res = resolverWith([
        entry('C1015', scope: ScopeKind.platform,
            ref: ChassisPlatforms.royalEnfieldClassic350, title: 'Store', meaning: 'm.')
      ]).resolve(obd('C1015'), classic350, 'en', domain: FaultDomain.abs);
      expect(res.title, 'Store');
      expect(res.provenance, Provenance.aiGuidance);
    });
    test('ABS manual tables are not used for an engine-reported code', () {
      final res = r.resolve(obd('C1015'), classic350, 'en', domain: FaultDomain.engine);
      expect(res.level, ResolvedLevel.l5Structure);
    });
    test('Hindi from the parallel Hindi table', () {
      final res = r.resolve(obd('C1015'), classic350, 'hi', domain: FaultDomain.abs);
      expect(res.languageUsed, 'hi');
      expect(res.title, isNot('ABS Pump/Motor Failure'));
      expect(res.languageFallback, isFalse);
    });
    test('a language with no table text: English, with the note', () {
      final res = r.resolve(obd('C1015'), classic350, 'bn', domain: FaultDomain.abs);
      expect(res.languageUsed, 'en');
      expect(res.languageFallback, isTrue);
    });
  });

  group('L3 module family (Bosch)', () {
    test('Bosch 0x5200 on every Bosch make, from a dealer readout', () {
      for (final make in ['Bajaj', 'Yamaha', 'Suzuki', 'KTM']) {
        final res = r.resolve(obd('C1200'), profile(make, 'Any model'), 'en',
            domain: FaultDomain.abs);
        expect(res.level, ResolvedLevel.l3ModuleFamily, reason: make);
        expect(res.provenance, Provenance.dealerReadout);
      }
    });
    test('typed as the module value 5200H', () {
      final res = r.resolve(typed('5200H', DtcFormat.hexH), profile('Bajaj', 'Dominar'), 'en');
      expect(res.level, ResolvedLevel.l3ModuleFamily);
    });
    test('a store module-family entry beats the Bosch table', () {
      final res = resolverWith([
        entry('C1200', scope: ScopeKind.moduleFamily, ref: kBoschAbsFamily,
            title: 'Family store', meaning: 'm.')
      ]).resolve(obd('C1200'), profile('KTM', 'Duke'), 'en', domain: FaultDomain.abs);
      expect(res.title, 'Family store');
      expect(res.level, ResolvedLevel.l3ModuleFamily);
    });
    test('any other Bosch value is the raw module number, never a guess', () {
      final res = r.resolve(obd('C1043'), profile('Bajaj', 'Pulsar'), 'en',
          domain: FaultDomain.abs);
      expect(res.level, ResolvedLevel.l6Raw);
      expect(res.rawModuleLabel, '0x5043');
      expect(res.displayCode, '0x5043');
      expect(res.title, isNull);
    });
    test('the Bosch table is not applied to a non-Bosch platform', () {
      final res = r.resolve(obd('C1200'), classic350, 'en', domain: FaultDomain.abs);
      expect(res.level, isNot(ResolvedLevel.l3ModuleFamily));
    });
  });

  group('L4 generic', () {
    test('a standard code from the store: all rider fields, AI label, draft', () {
      final res = r.resolve(obd('P0120'), VehicleContext.generic, 'en');
      expect(res.level, ResolvedLevel.l4Generic);
      expect(res.provenance, Provenance.aiGuidance);
      expect(res.provenance.labelKey, 'provenanceAi');
      expect(res.title, 'Throttle position sensor A: circuit fault');
      expect(res.causes, hasLength(3));
      expect(res.riderAdvice, contains('workshop'));
      expect(res.riderAction, RiderAction.serviceSoon);
      expect(res.canRide, CanRide.withCare);
      expect(res.canRideReason, isNotEmpty);
      expect(res.draft, isTrue, reason: 'the seed is draft content');
      expect(res.contentId, 'generic:P0120:en');
    });
    test('a STOP code', () {
      final stop = seedEntries.firstWhere((e) => e.riderAction == RiderAction.stop);
      final res = r.resolve(obd(stop.code), VehicleContext.generic, 'en');
      expect(res.riderAction, RiderAction.stop);
      expect(res.canRide, CanRide.no);
    });
    for (final code in ['P1120', 'P1000', 'P3000', 'P3399', 'C1035', 'B1001', 'B2001', 'U1100', 'U2100']) {
      test('manufacturer-defined $code never gets a generic meaning, even if one is stored', () {
        final res = resolverWith([entry(code, title: 'Borrowed', meaning: 'Borrowed.')])
            .resolve(obd(code), VehicleContext.generic, 'en');
        expect(res.level, ResolvedLevel.l5Structure);
        expect(res.title, isNull);
        expect(res.structure!.manufacturerDefined, isTrue);
      });
    }
    test('the store beats the older table for the same code', () {
      final res = resolverWith([entry('P0100', title: 'Store P0100', meaning: 'm.')])
          .resolve(obd('P0100'), VehicleContext.generic, 'en');
      expect(res.provenance, Provenance.aiGuidance);
    });
    test('no store entry: the 31-entry table, labelled as older text', () {
      final res = r.resolve(obd('P0100'), VehicleContext.generic, 'en');
      expect(res.provenance, Provenance.legacyTable);
      expect(res.title, 'Old table text');
      expect(res.causes, ['old cause']);
      expect(res.legacySeverity, 'high');
      expect(res.riderAction, isNull);
    });
    test('a standard code in neither the store nor the table is structure only', () {
      expect(r.resolve(obd('P0017'), VehicleContext.generic, 'en').level,
          ResolvedLevel.l5Structure);
    });
    test('legacy engine text is never used for an ABS code', () {
      expect(r.resolve(obd('P0100'), VehicleContext.generic, 'en', domain: FaultDomain.abs).level,
          ResolvedLevel.l5Structure);
    });
    test('an identified ABS platform owns its ABS codes: no generic C0020', () {
      final res = r.resolve(obd('C0020'), classic350, 'en', domain: FaultDomain.abs);
      expect(res.level, ResolvedLevel.l5Structure);
    });
    test('typed with an ABS platform selected: C codes are the platform\'s, P codes generic', () {
      expect(r.resolve(typed('C0020'), classic350, 'en').level, ResolvedLevel.l5Structure);
      expect(r.resolve(typed('P0120'), classic350, 'en').level, ResolvedLevel.l4Generic);
    });
    test('no platform identified: a standard ABS code may use the generic entry', () {
      final res = r.resolve(obd('C0020'), VehicleContext.generic, 'en', domain: FaultDomain.abs);
      expect(res.level, ResolvedLevel.l4Generic);
      expect(res.title, 'ABS pump motor: circuit fault');
    });
    test('a Bosch raw platform: even a standard-looking value is a module number', () {
      final res = r.resolve(obd('C0020'), profile('Yamaha', 'R15'), 'en', domain: FaultDomain.abs);
      expect(res.level, ResolvedLevel.l6Raw);
      expect(res.rawModuleLabel, '0x4020');
    });
  });

  group('never another make\'s meaning (scenario 20)', () {
    test('a blink pattern with no Honda profile is raw only', () {
      expect(r.resolve(typed('4-3', DtcFormat.blink), VehicleContext.generic, 'en').level,
          ResolvedLevel.l6Raw);
      expect(r.resolve(typed('4-3', DtcFormat.blink), classic350, 'en').level,
          ResolvedLevel.l6Raw);
    });
    test('the default "Unknown / Vehicle" profile identifies nothing', () {
      final v = profile('Unknown', 'Vehicle');
      expect(v.platformKey, isNull);
      expect(r.resolve(obd('C1015'), v, 'en', domain: FaultDomain.abs).level,
          ResolvedLevel.l5Structure);
    });
    test('a known make with an unknown model borrows no platform table', () {
      final v = profile('Royal Enfield', 'Himalayan');
      expect(v.platformKey, isNull);
      expect(r.resolve(obd('C1015'), v, 'en', domain: FaultDomain.abs).title, isNull);
    });
  });

  group('language', () {
    final hiFull = entry('P0105', lang: 'hi', title: 'MAP सेंसर: सर्किट में खराबी',
        meaning: 'हिंदी अर्थ।', causes: ['कारण एक', 'कारण दो'], advice: 'हिंदी सलाह।',
        hints: ['मैकेनिक के लिए संकेत'], rideReason: 'धीरे चलाएँ');
    final hiTitleOnly = entry('P0120', lang: 'hi', title: 'थ्रॉटल सेंसर: खराबी');
    test('Hindi asked, only English: English with the note', () {
      final res = r.resolve(obd('P0120'), VehicleContext.generic, 'hi');
      expect(res.languageUsed, 'en');
      expect(res.languageFallback, isTrue);
    });
    test('English asked: no note', () {
      expect(r.resolve(obd('P0120'), VehicleContext.generic, 'en').languageFallback, isFalse);
    });
    test('a full Hindi row: Hindi, no note', () {
      final res = resolverWith([hiFull]).resolve(obd('P0105'), VehicleContext.generic, 'hi');
      expect(res.languageUsed, 'hi');
      expect(res.title, 'MAP सेंसर: सर्किट में खराबी');
      expect(res.causes, ['कारण एक', 'कारण दो']);
      expect(res.languageFallback, isFalse);
    });
    test('a partial Hindi row: missing fields from English, named', () {
      final res = resolverWith([hiTitleOnly]).resolve(obd('P0120'), VehicleContext.generic, 'hi');
      expect(res.title, 'थ्रॉटल सेंसर: खराबी');
      expect(res.meaning, contains('throttle'));
      expect(res.englishFields, <String>{'meaning', 'causes', 'riderAdvice', 'hints', 'canRideReason'});
      expect(res.languageFallback, isTrue);
    });
    test('specificity beats language: English platform entry over Hindi generic', () {
      final res = resolverWith([
        hiFull,
        entry('P0105', scope: ScopeKind.platform,
            ref: ChassisPlatforms.royalEnfieldClassic350, title: 'Platform EN', meaning: 'm.'),
      ]).resolve(obd('P0105'), classic350, 'hi');
      expect(res.level, ResolvedLevel.l2Platform);
      expect(res.title, 'Platform EN');
      expect(res.languageUsed, 'en');
      expect(res.languageFallback, isTrue);
    });
    test('rider action comes from the English row, not a disagreeing Hindi row', () {
      final hiStop = entry('P0120', lang: 'hi', title: 'हिंदी', action: RiderAction.stop);
      final res = resolverWith([hiStop]).resolve(obd('P0120'), VehicleContext.generic, 'hi');
      expect(res.riderAction, RiderAction.serviceSoon);
    });
    test('a Hindi-only entry is used on its own', () {
      final res = resolverWith([entry('P0999', lang: 'hi', title: 'केवल हिंदी', meaning: 'अर्थ।')],
          seed: false).resolve(obd('P0999'), VehicleContext.generic, 'hi');
      expect(res.title, 'केवल हिंदी');
      expect(res.languageFallback, isFalse);
    });
  });

  group('applies_when', () {
    final twin = seedEntries.firstWhere((e) => e.appliesWhen?['cylinders_min'] == 2);
    test('unknown cylinders: shown, with the condition attached', () {
      final res = r.resolve(obd(twin.code), VehicleContext.generic, 'en');
      expect(res.level, ResolvedLevel.l4Generic);
      expect(res.conditions, {'cylinders_min': 2});
    });
    test('a known single-cylinder bike: skipped', () {
      final res = r.resolve(obd(twin.code), const VehicleContext(cylinders: 1), 'en');
      expect(res.level, isNot(ResolvedLevel.l4Generic));
      expect(res.contentId, isNull);
    });
    test('a known twin: shown, no condition note', () {
      final res = r.resolve(obd(twin.code), const VehicleContext(cylinders: 2), 'en');
      expect(res.level, ResolvedLevel.l4Generic);
      expect(res.conditions, isNull);
    });
    test('liquid_cooled: an air-cooled bike skips P0128', () {
      expect(r.resolve(obd('P0128'), const VehicleContext(liquidCooled: false), 'en').level,
          isNot(ResolvedLevel.l4Generic));
      expect(r.resolve(obd('P0128'), const VehicleContext(liquidCooled: true), 'en').level,
          ResolvedLevel.l4Generic);
    });
  });

  group('revoked and competing entries', () {
    test('a revoked entry is skipped', () {
      final revokedOnly = resolverWith(
          [entry('P0999', title: 'Revoked', meaning: 'm.', revoked: true)], seed: false);
      expect(revokedOnly.resolve(obd('P0999'), VehicleContext.generic, 'en').level,
          ResolvedLevel.l5Structure);
    });
    test('a revoked platform entry falls back to the manual table', () {
      final res = resolverWith([
        entry('C1015', scope: ScopeKind.platform,
            ref: ChassisPlatforms.royalEnfieldClassic350, title: 'Revoked', meaning: 'm.',
            revoked: true)
      ]).resolve(obd('C1015'), classic350, 'en', domain: FaultDomain.abs);
      expect(res.provenance, Provenance.serviceManual);
    });
    test('two entries for one code at different levels: the most specific wins', () {
      final res = resolverWith([
        entry('P0120', scope: ScopeKind.moduleFamily, ref: kBoschAbsFamily,
            title: 'Family', meaning: 'm.'),
        entry('P0120', scope: ScopeKind.platform, ref: ChassisPlatforms.bajajBoschAbs,
            title: 'Platform', meaning: 'm.'),
      ]).resolve(obd('P0120'), profile('Bajaj', 'Dominar'), 'en');
      expect(res.title, 'Platform');
      expect(res.level, ResolvedLevel.l2Platform);
    });
    test('draft follows the entry and its pack', () {
      final reviewed = resolverWith([entry('P0999', title: 't', meaning: 'm.')], seed: false)
          .resolve(obd('P0999'), VehicleContext.generic, 'en');
      expect(reviewed.draft, isFalse);
      final draftPack = resolverWith(
              [entry('P0999', title: 't', meaning: 'm.', packReviewState: 'draft')], seed: false)
          .resolve(obd('P0999'), VehicleContext.generic, 'en');
      expect(draftPack.draft, isTrue);
    });
  });

  group('L5 structure and L6 raw', () {
    test('a standard code nobody describes: system and subsystem, no text', () {
      final res = resolverWith(const <KbEntry>[])
          .resolve(obd('P0017'), VehicleContext.generic, 'en');
      expect(res.level, ResolvedLevel.l5Structure);
      expect(res.provenance, Provenance.structureOnly);
      expect(res.structure!.system, FaultSystem.powertrain);
      expect(res.structure!.subsystemKey, 'dtcSubFuelAir');
      expect(res.title, isNull);
      expect(res.meaning, isNull);
      expect(res.causes, isEmpty, reason: 'structure never names a part');
    });
    test('a UDS record keeps its failure type for the structure', () {
      final rec = FaultRecord(
          system: FaultSystem.chassis, code: 'C1099', rawBytes: const [0x50, 0x99, 0x11],
          format: DtcFormat.uds3, failureType: 0x11, status: FaultStatus.unknown,
          source: ReadSource.uds19, readAt: _at);
      final res = r.resolve(rec, VehicleContext.generic, 'en', domain: FaultDomain.abs);
      expect(res.structure!.failureType, 0x11);
      expect(res.displayCode, 'C1099-11');
    });
    test('something that is not a code at all is raw only', () {
      final res = r.resolve(typed('XYZ1'), VehicleContext.generic, 'en');
      expect(res.level, ResolvedLevel.l6Raw);
      expect(res.provenance, Provenance.rawOnly);
    });
    test('lower case and spaces in a record are normalised', () {
      final rec = FaultRecord(
          system: FaultSystem.powertrain, code: ' p0120 ', rawBytes: const [],
          format: DtcFormat.sae2, status: FaultStatus.unknown,
          source: ReadSource.manual, readAt: _at);
      expect(r.resolve(rec, VehicleContext.generic, 'en').title,
          'Throttle position sensor A: circuit fault');
    });
    test('an empty store still answers every code honestly', () {
      final empty = FaultResolver(index: KnowledgeIndex.empty);
      expect(empty.resolve(obd('P0120'), VehicleContext.generic, 'en').level,
          ResolvedLevel.l5Structure);
      expect(empty.resolve(obd('P1120'), VehicleContext.generic, 'en').structure!.manufacturerDefined,
          isTrue);
    });
    test('every provenance has its own label key', () {
      final keys = Provenance.values.map((p) => p.labelKey).toSet();
      expect(keys, hasLength(Provenance.values.length));
    });
  });
}
