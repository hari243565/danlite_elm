/// Danlite ELM — the resolver: one fixed order that picks the most specific
/// TRUTHFUL meaning for a fault code, and says honestly where it came from.
///
/// `resolve(record, vehicle, language)` walks six levels; the first level that
/// has a usable entry wins, whatever its language:
///
///   L1 vehicle variant   store entries for this exact vehicle (none yet)
///   L2 platform          store entries for the platform, then the existing
///                        manual tables in `ChassisDtcDatabase` (wrapped, not
///                        moved or edited)
///   L3 module family     store entries, then the Bosch shared 5200H
///   L4 generic           a knowledge-store entry — ONLY for standard-defined
///                        codes — then the 31-entry table (which beats a
///                        name-only entry: it has a cause and an action)
///   L5 structure         system, subsystem, "defined by the manufacturer",
///                        failure type; never a part name
///   L6 raw               the raw value and "show this to your dealer"
///
/// Rules, each tested in `test/fault_resolver_test.dart`:
///  * a manufacturer-defined code is never resolved at L4;
///  * on an identified ABS platform the platform's own code space governs: an
///    ABS code missing from its table gets structure or raw, never a generic
///    meaning — and on a Bosch raw-value platform the SAE form of a module
///    number is not an SAE code at all;
///  * specificity beats language: a level is chosen first, then its language,
///    field by field, with a note when anything is not in the asked language;
///  * `applies_when` that CONTRADICTS a known vehicle fact skips the entry;
///    unknown vehicle details show it, with the condition attached;
///  * revoked entries are skipped;
///  * provenance and verification labels say what the source really is.
///
/// Pure Dart: no Flutter, no SQLite. Text the UI owns (labels, structure
/// names) is returned as `AppStrings` keys.
library;

import '../constants/chassis_dtc_dictionary.dart';
import '../constants/chassis_dtc_dictionary_hi.dart';
import '../constants/dtc_ranges.dart';
import '../models/fault_record.dart';
import 'kb_models.dart';

/// Which module reported the code. ABS manual tables only describe ABS codes;
/// the engine's legacy text only describes engine codes.
enum FaultDomain { engine, abs, unknown }

enum ResolvedLevel {
  l1Vehicle,
  l2Platform,
  l3ModuleFamily,
  l4Generic,
  l5Structure,
  l6Raw,
}

/// Where the text came from. Drives the provenance line.
enum Provenance {
  /// Written by Danlite with AI assistance (the knowledge store).
  aiGuidance('provenanceAi'),

  /// Transcribed from the manufacturer's service manual.
  serviceManual('provenanceManual'),

  /// The manual lists the code but gives it no meaning.
  serviceManualNoMeaning('provenanceManualNoMeaning'),

  /// A dealer-tool readout of the Bosch ABS module, not a manual.
  dealerReadout('provenanceDealerReadout'),

  /// The 31-entry table that predates this design; source not recorded.
  legacyTable('provenanceLegacyTable'),

  /// No meaning: the code's structure only.
  structureOnly('provenanceStructure'),

  /// No meaning: the raw value only.
  rawOnly('provenanceRaw'),

  /// A knowledge-store entry that has the standard's code name and no guidance
  /// yet (`verification: standard_title_only`). Added last so every older
  /// label keeps its place.
  standardTitleOnly('provenanceStandardTitleOnly');

  const Provenance(this.labelKey);

  /// `AppStrings` key of the plain verification label.
  final String labelKey;

  /// The answer came from the knowledge store (guidance, or a bare standard
  /// name), so the screens render it as store content with this label.
  bool get isStoreGuidance =>
      this == Provenance.aiGuidance || this == Provenance.standardTitleOnly;
}

/// What is known about the bike. Unknown is null, never false.
class VehicleContext {
  const VehicleContext({
    this.profileId,
    this.make,
    this.model,
    this.manufacturerKey,
    this.platformKey,
    this.vehicleKey,
    this.cylinders,
    this.liquidCooled,
    this.rideByWire,
    this.absFitted,
  });

  /// No vehicle identified: generic meanings only.
  static const VehicleContext generic = VehicleContext();

  /// From the free-text make and model of a vehicle profile, through the same
  /// exact-alias resolution the ABS screen uses — an unrecognised make or
  /// model identifies nothing, so nothing is borrowed from another make.
  factory VehicleContext.fromProfile(
      {String? profileId, String? make, String? model}) {
    return VehicleContext(
      profileId: profileId,
      make: make,
      model: model,
      manufacturerKey: ChassisManufacturers.resolveKey(make),
      platformKey: ChassisPlatforms.resolve(make, model),
    );
  }

  final String? profileId;
  final String? make;
  final String? model;
  final String? manufacturerKey;
  final String? platformKey;

  /// Hook for L1 (a specific variant). Nothing sets it yet.
  final String? vehicleKey;

  final int? cylinders;
  final bool? liquidCooled;
  final bool? rideByWire;
  final bool? absFitted;

  ChassisPlatform? get platform => ChassisPlatforms.byKey(platformKey);

  /// `bosch_abs` when the platform's table is the Bosch module-level one.
  String? get moduleFamily {
    final k = platformKey;
    if (k == null) return null;
    return identical(ChassisDtcDatabase.byPlatform[k], ChassisDtcDatabase.boschSharedCodes)
        ? kBoschAbsFamily
        : null;
  }

  bool get identifiesVehicle => platformKey != null || vehicleKey != null;
}

const String kBoschAbsFamily = 'bosch_abs';

/// A row of the 31-entry table, supplied by the app. English only.
class LegacyText {
  const LegacyText({
    required this.title,
    this.cause = '',
    this.action = '',
    this.severity = 'unknown',
  });
  final String title;
  final String cause;
  final String action;
  final String severity;
}

typedef LegacyTextLookup = LegacyText? Function(String code, String language);

/// The structure of a code, for L5. Labels are rendered by the UI.
class StructuralFacts {
  const StructuralFacts({
    this.system,
    this.subsystemKey,
    this.manufacturerDefined = false,
    this.failureType,
  });
  final FaultSystem? system;
  final String? subsystemKey;
  final bool manufacturerDefined;
  final int? failureType;
}

/// A platform manual's own columns, rendered as they always were.
class PlatformDetail {
  const PlatformDetail({this.component = '', this.query = '', this.remedy = ''});
  final String component;
  final String query;
  final String remedy;
}

class ResolvedFault {
  const ResolvedFault({
    required this.level,
    required this.provenance,
    required this.code,
    required this.displayCode,
    required this.languageRequested,
    required this.languageUsed,
    this.title,
    this.meaning,
    this.causes = const <String>[],
    this.riderAdvice,
    this.hints = const <String>[],
    this.riderAction,
    this.canRide,
    this.canRideReason,
    this.draft = false,
    this.contentId,
    this.englishFields = const <String>{},
    this.conditions,
    this.platformDetail,
    this.rawModuleLabel,
    this.structure,
    this.legacySeverity,
    this.scopeLabel,
    this.hindiMachine = false,
  });

  final ResolvedLevel level;
  final Provenance provenance;

  /// The code as resolved, and as shown (`0x5043` on a Bosch raw platform).
  final String code;
  final String displayCode;

  final String? title;
  final String? meaning;
  final List<String> causes;
  final String? riderAdvice;
  final List<String> hints;
  final RiderAction? riderAction;
  final CanRide? canRide;
  final String? canRideReason;

  /// Not yet independently reviewed (entry flag or pack review state).
  final bool draft;
  final String? contentId;

  final String languageRequested;

  /// The language most of the text is in.
  final String languageUsed;

  /// Text fields shown in English although another language was asked for.
  final Set<String> englishFields;

  /// `applies_when` of the chosen entry, when the vehicle's matching detail is
  /// unknown — the UI says which bikes it applies to.
  final Map<String, Object?>? conditions;

  final PlatformDetail? platformDetail;
  final String? rawModuleLabel;
  final StructuralFacts? structure;

  /// The old severity band, for a legacy-table answer only.
  final String? legacySeverity;

  /// Which table answered, for the lookup screen ("Classic 350").
  final String? scopeLabel;

  /// The text shown is Hindi from a row marked `machine`: translated by a
  /// program and not yet read by a person. The card says so.
  final bool hindiMachine;

  /// The answer is a bare standard name and nothing more
  /// (`verification: standard_title_only`). The screens give it a neutral
  /// "Name only" chip instead of the rider-action chip, and show its title
  /// once. Its rider action stays INFO in the data, so ordering and the
  /// CRITICAL count are unchanged.
  bool get isNameOnly => provenance == Provenance.standardTitleOnly;

  /// Something is not in the asked language.
  bool get languageFallback =>
      languageUsed != languageRequested || englishFields.isNotEmpty;

  /// A meaning is claimed (L1–L4, or a manual entry).
  bool get hasMeaning =>
      level.index <= ResolvedLevel.l4Generic.index &&
      provenance != Provenance.serviceManualNoMeaning;
}

/// Every active store entry, grouped by code. Built once after an import;
/// immutable.
class KnowledgeIndex {
  KnowledgeIndex(Iterable<KbEntry> entries) {
    for (final e in entries) {
      if (e.revoked) continue;
      (_byCode[e.code] ??= <KbEntry>[]).add(e);
    }
  }

  static final KnowledgeIndex empty = KnowledgeIndex(const <KbEntry>[]);

  final Map<String, List<KbEntry>> _byCode = <String, List<KbEntry>>{};

  List<KbEntry> entriesFor(String code) => _byCode[code] ?? const <KbEntry>[];

  int get codeCount => _byCode.length;
  bool get isEmpty => _byCode.isEmpty;
}

final RegExp _saeCode = RegExp(r'^[PCBU][0-3][0-9A-F]{3}$');

bool _nameOnly(KbEntry e) => e.verification == kVerificationStandardTitleOnly;

class FaultResolver {
  FaultResolver({required this.index, this.legacy});

  final KnowledgeIndex index;
  final LegacyTextLookup? legacy;

  ResolvedFault resolve(FaultRecord record, VehicleContext vehicle, String language,
      {FaultDomain domain = FaultDomain.unknown}) {
    final code = record.code.trim().toUpperCase();
    final entries = index.entriesFor(code);
    final platform = vehicle.platform;
    final absAllowed = domain != FaultDomain.engine;

    // ── L1 vehicle ───────────────────────────────────────────────────────
    final vk = vehicle.vehicleKey;
    if (vk != null) {
      final r = _fromStore(entries, ScopeKind.vehicle, vk, record, code, vehicle,
          language, ResolvedLevel.l1Vehicle);
      if (r != null) return r;
    }

    // ── L2 platform ──────────────────────────────────────────────────────
    final pk = vehicle.platformKey;
    if (pk != null) {
      final r = _fromStore(entries, ScopeKind.platform, pk, record, code, vehicle,
          language, ResolvedLevel.l2Platform);
      if (r != null) return r;
      if (absAllowed && vehicle.moduleFamily == null) {
        final t = _fromManualTable(pk, code, record, language, ResolvedLevel.l2Platform,
            platform?.displayName);
        if (t != null) return t;
      }
    }

    // ── L3 module family ─────────────────────────────────────────────────
    final family = vehicle.moduleFamily;
    if (family != null && absAllowed) {
      final r = _fromStore(entries, ScopeKind.moduleFamily, family, record, code,
          vehicle, language, ResolvedLevel.l3ModuleFamily);
      if (r != null) return r;
      final t = _fromManualTable(pk!, code, record, language,
          ResolvedLevel.l3ModuleFamily, 'Bosch ABS');
      if (t != null) return t;
    }

    // ── L4 generic ───────────────────────────────────────────────────────
    final isSae = _saeCode.hasMatch(code) &&
        record.format != DtcFormat.blink &&
        record.format != DtcFormat.hexH;
    final platformOwnsCode = platform != null &&
        platform.brakeSystem == ChassisBrakeSystem.abs &&
        (domain == FaultDomain.abs || (domain == FaultDomain.unknown && code.startsWith('C')));
    final rawPlatform =
        (platform?.showsRawUnverifiedCodes ?? false) && domain != FaultDomain.engine;
    if (isSae && !isManufacturerDefined(code) && !platformOwnsCode && !rawPlatform) {
      final r = _fromStore(entries, ScopeKind.generic, '', record, code, vehicle,
          language, ResolvedLevel.l4Generic);
      if (r != null && r.provenance != Provenance.standardTitleOnly) return r;
      if (domain != FaultDomain.abs) {
        final l = legacy?.call(code, language);
        if (l != null && l.title.isNotEmpty) {
          // The table is English only; a Hindi rider is told so (languageUsed).
          return ResolvedFault(
            level: ResolvedLevel.l4Generic,
            provenance: Provenance.legacyTable,
            code: code,
            displayCode: record.displayCode,
            languageRequested: language,
            languageUsed: 'en',
            title: l.title,
            causes: l.cause.isEmpty ? const <String>[] : <String>[l.cause],
            riderAdvice: l.action.isEmpty ? null : l.action,
            legacySeverity: l.severity,
          );
        }
      }
      if (r != null) return r;
    }

    // ── L6 raw, for what has no SAE structure to describe ────────────────
    if (rawPlatform && _saeCode.hasMatch(code)) {
      return ResolvedFault(
        level: ResolvedLevel.l6Raw,
        provenance: Provenance.rawOnly,
        code: code,
        displayCode: ChassisDtcDatabase.rawModuleLabel(code) ?? record.displayCode,
        rawModuleLabel: ChassisDtcDatabase.rawModuleLabel(code),
        languageRequested: language,
        languageUsed: language,
      );
    }
    if (!isSae) {
      return ResolvedFault(
        level: ResolvedLevel.l6Raw,
        provenance: Provenance.rawOnly,
        code: code,
        displayCode: record.displayCode,
        languageRequested: language,
        languageUsed: language,
      );
    }

    // ── L5 structure ─────────────────────────────────────────────────────
    return ResolvedFault(
      level: ResolvedLevel.l5Structure,
      provenance: Provenance.structureOnly,
      code: code,
      displayCode: record.displayCode,
      languageRequested: language,
      languageUsed: language,
      structure: StructuralFacts(
        system: FaultSystem.fromCode(code),
        subsystemKey: subsystemKeyFor(code),
        manufacturerDefined: isManufacturerDefined(code),
        failureType: record.failureType,
      ),
    );
  }

  /// The first usable store answer at one scope, or null.
  ResolvedFault? _fromStore(List<KbEntry> all, ScopeKind kind, String ref,
      FaultRecord record, String code, VehicleContext vehicle, String language,
      ResolvedLevel level) {
    var group = [
      for (final e in all)
        if (!e.revoked && e.scopeKind == kind && e.scopeRef == ref) e
    ];
    if (group.isEmpty) return null;
    // Real guidance always beats a bare name for the same code, in either
    // language: a name-only row is used only when nothing richer exists here.
    if (group.any((e) => !_nameOnly(e))) {
      group = [for (final e in group) if (!_nameOnly(e)) e];
    }
    KbEntry? inLang(String l) {
      for (final e in group) {
        if (e.language == l) return e;
      }
      return null;
    }

    final en = inLang('en');
    final asked = inLang(language);
    final primary = asked ?? en ?? group.first;
    // Facts about the fault come from English when it exists.
    final facts = en ?? primary;

    final aw = facts.appliesWhen;
    Map<String, Object?>? conditions;
    if (aw != null && aw.isNotEmpty) {
      final verdict = _applies(aw, vehicle);
      if (verdict == false) return null; // contradicted: skip this level
      if (verdict == null) conditions = aw;
    }

    final english = <String>{};
    String? pick(String field, String? Function(KbEntry) get) {
      final v = get(primary);
      if (v != null && v.isNotEmpty) return v;
      final f = en == null || identical(en, primary) ? null : get(en);
      if (f != null && f.isNotEmpty) {
        english.add(field);
        return f;
      }
      return null;
    }

    List<String> pickList(String field, List<String> Function(KbEntry) get) {
      final v = get(primary);
      if (v.isNotEmpty) return v;
      if (en == null || identical(en, primary)) return const <String>[];
      final f = get(en);
      if (f.isNotEmpty) english.add(field);
      return f;
    }

    final title = pick('title', (e) => e.title);
    final meaning = pick('meaning', (e) => e.meaning);
    final causes = pickList('causes', (e) => e.causes);
    final advice = pick('riderAdvice', (e) => e.riderAdvice);
    final hints = pickList('hints', (e) => e.hints);
    final rideReason = pick('canRideReason', (e) => e.canRideReason);
    if ((title ?? '').isEmpty && (meaning ?? '').isEmpty) return null;

    return ResolvedFault(
      level: level,
      // The less-claiming label wins if either row says "title only".
      provenance: facts.verification == kVerificationStandardTitleOnly ||
              primary.verification == kVerificationStandardTitleOnly
          ? Provenance.standardTitleOnly
          : Provenance.aiGuidance,
      code: code,
      displayCode: record.displayCode,
      languageRequested: language,
      languageUsed: primary.language,
      title: title,
      meaning: meaning,
      causes: causes,
      riderAdvice: advice,
      hints: hints,
      riderAction: facts.riderAction,
      canRide: facts.canRide,
      canRideReason: rideReason,
      draft: facts.isDraft || primary.isDraft,
      contentId: primary.contentId,
      englishFields: primary.language == language ? english : const <String>{},
      conditions: conditions,
      scopeLabel: kind == ScopeKind.generic ? null : ref,
      hindiMachine: primary.language == 'hi' && primary.hiStatus == HiStatus.machine,
    );
  }

  /// A row from the existing manual tables, in [language] where the Hindi
  /// parallel has it.
  ResolvedFault? _fromManualTable(String platformKey, String code, FaultRecord record,
      String language, ResolvedLevel level, String? scopeLabel) {
    final master = ChassisDtcDatabase.lookup(platformKey, code);
    if (master == null) return null;
    final hi = language == 'hi' ? ChassisDtcDictionaryHi.lookup(platformKey, code) : null;
    final english = <String>{};
    String choose(String field, String? local, String master) {
      if (language == 'en' || master.isEmpty) return master;
      if (local != null && local.isNotEmpty) return local;
      english.add(field);
      return master;
    }

    final title = choose('title', hi?.description, master.description);
    final query = choose('query', hi?.query, master.query);
    final remedy = choose('remedy', hi?.remedy, master.remedy);
    final allEnglish = language != 'en' && hi == null;
    final family = level == ResolvedLevel.l3ModuleFamily;
    return ResolvedFault(
      level: level,
      provenance: family
          ? Provenance.dealerReadout
          : (master.meaningVerified
              ? Provenance.serviceManual
              : Provenance.serviceManualNoMeaning),
      code: code,
      displayCode: record.displayCode,
      languageRequested: language,
      languageUsed: allEnglish ? 'en' : language,
      title: title,
      platformDetail: PlatformDetail(
          component: master.component, query: query, remedy: remedy),
      englishFields: allEnglish ? const <String>{} : english,
      scopeLabel: scopeLabel,
    );
  }

  /// true = applies, false = known not to apply, null = unknown.
  static bool? _applies(Map<String, Object?> aw, VehicleContext v) {
    var unknown = false;
    for (final e in aw.entries) {
      bool? ok;
      switch (e.key) {
        case 'cylinders_min':
          final n = v.cylinders;
          ok = n == null ? null : n >= ((e.value as num?) ?? 0);
        case 'liquid_cooled':
          ok = v.liquidCooled == null ? null : v.liquidCooled == e.value;
        case 'ride_by_wire':
          ok = v.rideByWire == null ? null : v.rideByWire == e.value;
        case 'abs_fitted':
          ok = v.absFitted == null ? null : v.absFitted == e.value;
        default:
          ok = null; // a condition this build does not know: show, with it.
      }
      if (ok == false) return false;
      if (ok == null) unknown = true;
    }
    return unknown ? null : true;
  }
}
