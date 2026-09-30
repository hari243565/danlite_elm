/// Danlite ELM — Chassis / ABS DTC Dictionary (English master)
///
/// ── Why this is a separate, platform-keyed table ──────────────────────────
/// Generic powertrain codes (`P0xxx`) are SAE-standardised: `P0122` means the
/// same thing on every vehicle, which is why [DtcDatabase] in
/// `dtc_descriptions.dart` can be a single flat, make-agnostic table.
///
/// Chassis codes are not like that. The `C1xxx` range in particular is
/// *manufacturer-defined*: a `C1015` on a Royal Enfield does not necessarily
/// describe the same fault as a `C1015` on any other manufacturer's vehicle.
/// Looking a chassis code up in a flat table would therefore hand the rider a
/// confidently-worded but wrong description of a braking-system fault.
///
/// ── Why the key is manufacturer + model, not manufacturer alone ──────────
/// It turns out one manufacturer is not a fine enough key either. Royal
/// Enfield's Classic 350 and its Euro-IV Bullet EFI / Continental GT platform
/// ship different ABS ECUs with *different, non-overlapping code systems*, and
/// the same number genuinely means different things across them — `C1052` is a
/// rear inlet valve fault on the Classic 350 and a low-supply-voltage fault on
/// the Bullet EFI platform. So the key is a **platform**: manufacturer plus
/// model family. A lookup that cannot identify the platform returns null
/// rather than picking one.
///
/// ── Bilingual convention ─────────────────────────────────────────────────
/// This file mirrors the split already used for engine codes:
///   • English master lives here            (as `DtcDatabase.codes` does)
///   • Hindi parallel lives in
///     `chassis_dtc_dictionary_hi.dart`     (as `DtcDictionaryHi` does)
///   • Both are resolved through the single langCode-aware entry point in
///     `DtcLocalizations` (`dtc_service.dart`), never read directly by the UI.
/// Adding a code is one entry here plus one entry in the Hindi file — no code
/// change anywhere else.
///
/// ── Data provenance (read before adding entries) ─────────────────────────
/// Classic 350  : owner's photographs of the Classic 350 service manual,
///                section 9.3.11 ("ABS DTC" table). C-code format.
/// Bullet EFI   : the publicly hosted Bullet EFI / Bullet Classic EFI /
///                Continental GT (Euro IV) service manual, page 167. Printed
///                in hex-suffix notation (`5043H`) and carrying no per-code
///                remedy column — see [ChassisDtcDatabase.bulletEfiGenericRemedy].
///
/// Where the source prints "N/A" for Query or Remedy, that field is stored
/// genuinely empty. The UI omits an empty row rather than rendering a
/// meaningless placeholder.
///
/// DO NOT invent entries for codes not present in a real service manual page.
/// This is a braking system; a plausible-sounding but fabricated description
/// or remedy is worse than no entry at all, because the app renders an unknown
/// code honestly as "no manufacturer description available" and the rider then
/// consults a dealer instead of acting on fiction.
library;

import 'obd_pids.dart';

/// One chassis/ABS fault-code entry.
///
/// Only [description] is required. [component], [query] and [remedy] default
/// to empty because they are genuinely absent from some real source rows —
/// the Bullet EFI manual has no component or query column at all, and several
/// Classic 350 rows print "N/A". Empty means "the manual does not say", and the
/// UI omits the row; it never means "we did not bother".
class ChassisDtcEntry {
  /// Manual column "Failure Component" — the manufacturer's own internal
  /// component token (e.g. `RFP/RFP_HW`, `WSS_GENERIC`). Not translated: it is
  /// an identifier a technician matches against the manual verbatim, exactly
  /// as gauge units are left untranslated elsewhere in this app.
  final String component;

  /// Manual column "Failure Description".
  final String description;

  /// Manual column "Query" — the manufacturer's elaboration of what the fault
  /// actually indicates. Genuinely actionable, so it is surfaced in the UI.
  final String query;

  /// Manual column "Remedy" — the manufacturer's prescribed fix.
  final String remedy;

  /// Danlite's own UI severity band (critical / high / medium / low), used
  /// only for card colour and sort order.
  ///
  /// NOTE: severity is NOT a column in either service manual. It is assigned
  /// by Danlite from the nature of the fault — every entry below is a fault in
  /// a motorcycle braking system, which is why they all sit at `critical`. It
  /// is a display classification, never presented to the rider as manual data.
  final String severity;

  /// False when the source lists this code but does not state what it means.
  ///
  /// The braking-system honesty rule in this file's header says an invented
  /// description is worse than none. This flag is how a code can be listed —
  /// so the rider learns it is a real, documented code rather than garbage —
  /// without any meaning being claimed for it. The UI must render such an
  /// entry with an explicit "meaning not verified" treatment.
  ///
  /// Two real situations produce it, both genuine gaps in a real source and
  /// neither a placeholder for work not done:
  ///   • Honda blink code 4-2, which the source lists in the front
  ///     wheel-speed-sensor group without giving it its own description.
  ///   • Any code read from a generic Bosch platform other than 0x5200 — see
  ///     [ChassisDtcDatabase.boschSharedCodes].
  final bool meaningVerified;

  const ChassisDtcEntry({
    required this.description,
    this.component = '',
    this.query = '',
    this.remedy = '',
    this.severity = 'critical',
    this.meaningVerified = true,
  });
}

/// Canonical manufacturer keys and the free-text normalisation that maps a
/// user-entered vehicle "Make" onto one.
///
/// The app collects `make` on the vehicle profile as free text ("Royal
/// Enfield", "royal enfield", "RoyalEnfield"…), so resolution has to be
/// tolerant. Normalisation strips case and every non-alphanumeric character,
/// then matches against a small alias table.
class ChassisManufacturers {
  ChassisManufacturers._();

  static const String royalEnfield = 'royal_enfield';
  static const String honda = 'honda';

  // ── Bosch-supplied ABS platforms ───────────────────────────────────────────
  // Bajaj, Yamaha, Suzuki and KTM all source their motorcycle ABS modulator
  // from Bosch, and their fault values sit in the same hexadecimal 0x5xxx
  // module-number family already confirmed on Royal Enfield's Bosch platform
  // (the `H`-suffix codes in the Bullet EFI table below). That shared
  // hardware family is the entire basis on which these makes are supported —
  // it is NOT a claim that any particular value means the same thing on each
  // of them. See [ChassisDtcDatabase.boschSharedCodes] for the single value
  // that is independently sourced, and [ChassisDictionaryKind.rawUnverifiedHex]
  // for how everything else is honestly presented.
  static const String bajaj = 'bajaj';
  static const String yamaha = 'yamaha';
  static const String suzuki = 'suzuki';
  static const String ktm = 'ktm';

  /// Normalised free-text spellings → canonical key. Extend this when adding a
  /// manufacturer; nothing else needs to change.
  static const Map<String, String> _aliases = <String, String>{
    'royalenfield': royalEnfield,
    'royalenfieldmotors': royalEnfield,
    're': royalEnfield,
    'honda': honda,
    'hondamotorcycle': honda,
    'hondamotorcycleandscooterindia': honda,
    'hmsi': honda,
    'bajaj': bajaj,
    'bajajauto': bajaj,
    'yamaha': yamaha,
    'yamahamotor': yamaha,
    'indiayamahamotor': yamaha,
    'suzuki': suzuki,
    'suzukimotorcycle': suzuki,
    'suzukimotorcycleindia': suzuki,
    'ktm': ktm,
  };

  /// Human-readable label for a canonical key, for UI display.
  static const Map<String, String> displayNames = <String, String>{
    royalEnfield: 'Royal Enfield',
    honda: 'Honda',
    bajaj: 'Bajaj',
    yamaha: 'Yamaha',
    suzuki: 'Suzuki',
    ktm: 'KTM',
  };

  /// Resolve a free-text vehicle make (e.g. `"Royal Enfield"`) to a canonical
  /// manufacturer key, or null when it is blank/unrecognised.
  ///
  /// Returning null is deliberate and load-bearing: an unrecognised make must
  /// fall through to "no chassis dictionary" rather than silently borrowing
  /// another manufacturer's chassis-code meanings.
  static String? resolveKey(String? rawMake) {
    if (rawMake == null) return null;
    final normalised = normalise(rawMake);
    if (normalised.isEmpty) return null;
    return _aliases[normalised];
  }

  /// Shared free-text normalisation: lowercase, strip everything that is not
  /// a letter or digit. `"  ROYAL-ENFIELD  "` and `"Royal Enfield"` both
  /// become `"royalenfield"`.
  static String normalise(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Every manufacturer that currently ships at least one platform dictionary.
  static List<String> get supported => ChassisPlatforms.all
      .map((p) => p.manufacturerKey)
      .toSet()
      .toList(growable: false);
}

/// What braking hardware a platform actually has.
///
/// This is not a pedantic distinction. India's braking regulation requires ABS
/// only from 125cc upwards; below that a Combi-Brake System is fitted instead.
/// CBS is purely mechanical — a linked front/rear brake with no ECU, no wheel
/// speed sensors and no fault memory whatsoever. There is nothing on such a
/// bike for a scan tool to talk to, so probing one and reporting "no module
/// answered" describes the vehicle as possibly broken when it is in fact
/// working exactly as designed.
///
/// Marketing copy is not evidence for this: "combi-brake" is often sold
/// alongside language that reads like ABS. Every [ChassisBrakeSystem.cbs]
/// entry below has to carry its own provenance note.
enum ChassisBrakeSystem {
  /// Electronic anti-lock braking with a fault-storing ECU.
  abs,

  /// Combi-Brake System: mechanical linked braking, no ECU, no fault codes.
  cbs,
}

/// How this platform's stored faults can physically be reached.
///
/// The honest centre of this whole file. Two platforms can both have real,
/// fully documented ABS fault tables and still be worlds apart in what this
/// app can do with them, because the readout mechanism differs.
enum ChassisReadMethod {
  /// Reachable over the adapter: a physically-addressed UDS `19 02` request,
  /// exactly as [ChassisModuleProfiles] describes. This is the only value that
  /// may ever be presented to the rider as a scan.
  udsLiveScan,

  /// Read by bridging the DLC with a jumper and counting flashes of the ABS
  /// warning lamp — a manual, visual, physical procedure performed on the
  /// motorcycle. There is no electrical path from a Bluetooth OBD adapter to
  /// this data at all: it never travels over CAN, so no adapter, protocol or
  /// app can retrieve it. A platform marked this way must be offered ONLY as a
  /// manual reference lookup, never wired to a scan button.
  dlcBlinkCodeManual,

  /// No fault memory exists to read (a [ChassisBrakeSystem.cbs] platform).
  notApplicable,
}

/// How much is actually known about what this platform's codes mean.
///
/// Kept separate from [ChassisReadMethod] because the two are genuinely
/// independent: a platform can be live-scannable with no decoded table, or
/// fully decoded with no way to scan it.
enum ChassisDictionaryKind {
  /// Every listed code carries a description transcribed from a real source.
  decoded,

  /// Codes can be read, but no public source decodes what they mean on this
  /// make. They must be displayed as the raw module value with an explicit
  /// "meaning not independently verified" treatment — never a guess. The one
  /// exception is [ChassisDtcDatabase.boschSharedCodes], which is sourced at
  /// the Bosch-module level rather than per brand.
  rawUnverifiedHex,

  /// No table at all for this platform.
  none,
}

/// One vehicle platform: a manufacturer plus a model family that shares a
/// single ABS ECU and therefore a single fault-code system.
class ChassisPlatform {
  /// Canonical dictionary key (e.g. `royal_enfield_classic350`).
  final String key;

  /// Which manufacturer this platform belongs to.
  final String manufacturerKey;

  /// Human-readable label for UI display.
  final String displayName;

  /// Normalised model spellings that resolve to this platform.
  ///
  /// Matching is **exact against the normalised string**, never substring.
  /// Substring matching would be actively dangerous here: "Bullet Classic EFI"
  /// contains "classic", and loosely matching that to the Classic 350 dataset
  /// would describe a braking fault using the wrong platform's table.
  final List<String> modelAliases;

  /// Whether this model actually has an ABS ECU, or a mechanical CBS with
  /// nothing to scan. Defaults to [ChassisBrakeSystem.abs] so every platform
  /// that shipped before this flag existed keeps its exact previous behaviour.
  final ChassisBrakeSystem brakeSystem;

  /// How this platform's faults can be reached. Defaults to
  /// [ChassisReadMethod.udsLiveScan] — the behaviour of every platform that
  /// shipped before this flag existed.
  final ChassisReadMethod readMethod;

  /// How much is known about what this platform's codes mean. Defaults to
  /// [ChassisDictionaryKind.decoded], again preserving prior behaviour.
  final ChassisDictionaryKind dictionaryKind;

  /// Why this platform carries the capability flags it does, in one line, for
  /// a reader checking the claim rather than taking it on trust. Empty for the
  /// platforms that predate the flags and simply use every default.
  final String capabilityProvenance;

  const ChassisPlatform({
    required this.key,
    required this.manufacturerKey,
    required this.displayName,
    required this.modelAliases,
    this.brakeSystem = ChassisBrakeSystem.abs,
    this.readMethod = ChassisReadMethod.udsLiveScan,
    this.dictionaryKind = ChassisDictionaryKind.decoded,
    this.capabilityProvenance = '',
  });

  /// True when this platform may be offered to the rider as a live scan.
  bool get isLiveScannable => readMethod == ChassisReadMethod.udsLiveScan;

  /// True when the only route to this platform's codes is the manual
  /// blink-code procedure on the motorcycle itself.
  bool get isBlinkCodeOnly =>
      readMethod == ChassisReadMethod.dlcBlinkCodeManual;

  /// True when this model has no fault memory to read at all.
  bool get isCbsOnly => brakeSystem == ChassisBrakeSystem.cbs;

  /// True when a code read from this platform must be shown as a raw module
  /// value with its meaning explicitly marked unverified.
  bool get showsRawUnverifiedCodes =>
      dictionaryKind == ChassisDictionaryKind.rawUnverifiedHex;
}

/// Platform registry and the make+model resolution that selects a dataset.
class ChassisPlatforms {
  ChassisPlatforms._();

  static const String royalEnfieldClassic350 = 'royal_enfield_classic350';
  static const String royalEnfieldBulletEfi = 'royal_enfield_bullet_efi';

  /// Honda ABS models read by DLC jumper + counting warning-lamp flashes.
  /// Fully decoded, and completely unreachable over Bluetooth. See
  /// [ChassisReadMethod.dlcBlinkCodeManual].
  static const String hondaAbsBlink = 'honda_abs_blink';

  /// Honda's 2024-onward OBD2B-compliant models, which expose diagnostics over
  /// CAN/UDS the way Royal Enfield's platform does. Scannable, but with no
  /// decoded table — see the entry's own provenance note.
  static const String hondaObd2b = 'honda_obd2b';

  /// Honda models fitted with CBS instead of ABS: nothing to scan at all.
  static const String hondaCbs = 'honda_cbs';

  static const String bajajBoschAbs = 'bajaj_bosch_abs';
  static const String yamahaBoschAbs = 'yamaha_bosch_abs';
  static const String suzukiBoschAbs = 'suzuki_bosch_abs';
  static const String ktmBoschAbs = 'ktm_bosch_abs';

  static const List<ChassisPlatform> all = <ChassisPlatform>[
    ChassisPlatform(
      key: royalEnfieldClassic350,
      manufacturerKey: ChassisManufacturers.royalEnfield,
      displayName: 'Classic 350',
      modelAliases: <String>[
        'classic350',
        'classic350cc',
        'reclassic350',
        'royalenfieldclassic350',
      ],
    ),
    ChassisPlatform(
      key: royalEnfieldBulletEfi,
      manufacturerKey: ChassisManufacturers.royalEnfield,
      displayName: 'Bullet EFI / Continental GT',
      modelAliases: <String>[
        'bulletefi',
        'bullet500efi',
        'bulletefi500',
        'bulletclassicefi',
        'continentalgt',
        'continentalgt535',
      ],
    ),

    // ══════════════════════════════════════════════════════════════════════
    // Honda — three genuinely different situations under one make
    // ══════════════════════════════════════════════════════════════════════
    // Honda is the reason [ChassisReadMethod] exists. Honda publishes a real,
    // portable ABS fault table that is consistent across its ABS models — and
    // on the majority of that lineup the table is read by bridging the DLC and
    // counting flashes of the ABS warning lamp. That data never travels over
    // CAN. No adapter and no app can fetch it. Only the 2024-onward OBD2B
    // models expose ABS diagnostics electronically.
    //
    // Listing "Honda" as supported without separating those two would be the
    // single most misleading thing this file could do, so they are separate
    // platforms with separate capabilities rather than one averaged entry.

    // The CBS models are listed first purely for readability; resolution is by
    // exact alias match, so list order does not affect which one is picked.
    ChassisPlatform(
      key: hondaCbs,
      manufacturerKey: ChassisManufacturers.honda,
      displayName: 'Honda CBS models (no ABS)',
      brakeSystem: ChassisBrakeSystem.cbs,
      readMethod: ChassisReadMethod.notApplicable,
      dictionaryKind: ChassisDictionaryKind.none,
      capabilityProvenance:
          'Sub-125cc Honda models, where India\'s braking regulation requires '
          'CBS rather than ABS and no ABS variant is offered. Derived from the '
          'regulatory threshold plus published engine displacement, not from a '
          'dealer-tool readout — which is why the CBS notice offers a "scan '
          'anyway" action rather than blocking the scan outright. Remove an '
          'alias here if a variant of that model with real ABS ever appears.',
      modelAliases: <String>[
        // Activa — every variant is sub-125cc and none is offered with ABS.
        'activa',
        'activa5g',
        'activa6g',
        'activa125',
        // Dio (109cc).
        'dio',
        // Shine 100 (99cc).
        'shine100',
      ],
    ),
    ChassisPlatform(
      key: hondaObd2b,
      manufacturerKey: ChassisManufacturers.honda,
      displayName: 'Honda 2024+ (OBD2B)',
      readMethod: ChassisReadMethod.udsLiveScan,
      // Deliberately NOT decoded. The blink-code table below is a *blink*
      // table: its keys are flash patterns, not the numeric DTCs a UDS reply
      // carries, and no source maps one onto the other. Pointing this platform
      // at that table would silently relabel a scanned number with a blink
      // code's meaning — a guess about a braking fault, which this file
      // forbids. So the scan runs, and reports what it read honestly
      // undescribed.
      dictionaryKind: ChassisDictionaryKind.none,
      capabilityProvenance:
          'OBD2B compliance from 2024 makes ABS diagnostics reachable over '
          'CAN/UDS on these models. No public source decodes the numeric DTCs '
          'they return, and the blink-code table is not a mapping for them.',
      modelAliases: <String>[
        'hornet20',
        'hornet2',
        'cbhornet20',
        'hondahornet20',
      ],
    ),
    ChassisPlatform(
      key: hondaAbsBlink,
      manufacturerKey: ChassisManufacturers.honda,
      displayName: 'Honda ABS (blink-code models)',
      readMethod: ChassisReadMethod.dlcBlinkCodeManual,
      dictionaryKind: ChassisDictionaryKind.decoded,
      capabilityProvenance:
          'Honda service manuals publish this table and it is consistent '
          'across Honda ABS models, which is why it is a make-level default. '
          'Retrieval is by DLC jumper and warning-lamp flash count — a manual '
          'procedure on the motorcycle, with no CAN path a scan tool could '
          'use.',
      // No aliases: this is the manufacturer fallback (see
      // [_fallbackPlatformByManufacturer]), reached by any Honda model that is
      // not one of the explicitly-listed CBS or OBD2B models above.
      modelAliases: <String>[],
    ),

    // ══════════════════════════════════════════════════════════════════════
    // Bosch-supplied platforms — Bajaj / Yamaha / Suzuki / KTM
    // ══════════════════════════════════════════════════════════════════════
    // One entry per make, with no model dimension, because there is no
    // per-model data to distinguish: what is known is hardware-level (a Bosch
    // modulator using the 0x5xxx module-number family) and applies to the
    // make's whole ABS lineup equally.
    //
    // These are [ChassisDictionaryKind.rawUnverifiedHex], and that is the
    // whole point of them. The probe can reach the module and read real
    // values; what it cannot do is say what those values mean, because no
    // public source decodes them per brand. The one value that IS sourced —
    // 0x5200 — is sourced at the Bosch-module level, so it applies to all four
    // equally and lives in [ChassisDtcDatabase.boschSharedCodes].
    ChassisPlatform(
      key: bajajBoschAbs,
      manufacturerKey: ChassisManufacturers.bajaj,
      displayName: 'Bajaj (Bosch ABS)',
      dictionaryKind: ChassisDictionaryKind.rawUnverifiedHex,
      capabilityProvenance: _boschProvenance,
      modelAliases: <String>[],
    ),
    ChassisPlatform(
      key: yamahaBoschAbs,
      manufacturerKey: ChassisManufacturers.yamaha,
      displayName: 'Yamaha (Bosch ABS)',
      dictionaryKind: ChassisDictionaryKind.rawUnverifiedHex,
      capabilityProvenance: _boschProvenance,
      modelAliases: <String>[],
    ),
    ChassisPlatform(
      key: suzukiBoschAbs,
      manufacturerKey: ChassisManufacturers.suzuki,
      displayName: 'Suzuki (Bosch ABS)',
      dictionaryKind: ChassisDictionaryKind.rawUnverifiedHex,
      capabilityProvenance: _boschProvenance,
      modelAliases: <String>[],
    ),
    ChassisPlatform(
      key: ktmBoschAbs,
      manufacturerKey: ChassisManufacturers.ktm,
      displayName: 'KTM (Bosch ABS)',
      dictionaryKind: ChassisDictionaryKind.rawUnverifiedHex,
      capabilityProvenance: _boschProvenance,
      modelAliases: <String>[],
    ),
  ];

  static const String _boschProvenance =
      'ABS modulator supplied by Bosch, using the same hexadecimal 0x5xxx '
      'module-number family confirmed on Royal Enfield\'s Bosch platform. '
      'Shared hardware family only — no public source decodes these values '
      'per brand, so every code except the Bosch-level 0x5200 is shown raw '
      'and explicitly unverified.';

  /// The platform a make falls back to when the model is that make's but
  /// matches no specific alias.
  ///
  /// ── Why this exists, and why Royal Enfield is deliberately not in it ─────
  /// Royal Enfield genuinely needs the model: its Classic 350 and Bullet EFI
  /// platforms disagree about what the same number means, so falling back to
  /// either would describe a braking fault from the wrong table. It has no
  /// entry here, and its resolution is byte-for-byte what it was before this
  /// map existed — an unrecognised Royal Enfield model still resolves to null.
  ///
  /// The makes below are the opposite case, for two different reasons:
  ///   • Honda's blink table is published as consistent across its ABS models,
  ///     so a make-level default is what the source itself supports. The
  ///     models that must NOT reach it — CBS models with no ABS, and the 2024+
  ///     OBD2B models — carry explicit aliases, and an exact alias match is
  ///     always tried first.
  ///   • The Bosch makes have no per-model dimension at all: what is known
  ///     about them is a hardware fact about the modulator, identical across
  ///     the make's lineup.
  ///
  /// A blank model still resolves to null for every make, unchanged. That is
  /// what keeps the "set your model" nudge working, and for Honda it genuinely
  /// matters — without a model there is no way to tell an ABS bike from a CBS
  /// one.
  static const Map<String, String> _fallbackPlatformByManufacturer =
      <String, String>{
    ChassisManufacturers.honda: hondaAbsBlink,
    ChassisManufacturers.bajaj: bajajBoschAbs,
    ChassisManufacturers.yamaha: yamahaBoschAbs,
    ChassisManufacturers.suzuki: suzukiBoschAbs,
    ChassisManufacturers.ktm: ktmBoschAbs,
  };

  /// True when [manufacturerKey] resolves any non-blank model to a platform.
  ///
  /// Used by the UI to word the "set your model" nudge correctly: listing the
  /// models we recognise only helps for a make that actually discriminates by
  /// model.
  static bool hasModelIndependentFallback(String? manufacturerKey) =>
      manufacturerKey != null &&
      _fallbackPlatformByManufacturer.containsKey(manufacturerKey);

  /// Resolve a free-text make + model to a platform key.
  ///
  /// Returns null when the make is unrecognised, when the model is blank, or
  /// when the model does not exactly match a known alias for that make. All
  /// three cases are reported honestly by the UI rather than guessed: picking
  /// the wrong platform would describe a braking fault from the wrong table.
  static String? resolve(String? rawMake, String? rawModel) {
    final manufacturerKey = ChassisManufacturers.resolveKey(rawMake);
    if (manufacturerKey == null || rawModel == null) return null;
    final normalised = ChassisManufacturers.normalise(rawModel);
    if (normalised.isEmpty) return null;
    for (final platform in all) {
      if (platform.manufacturerKey != manufacturerKey) continue;
      if (platform.modelAliases.contains(normalised)) return platform.key;
    }
    // Exact aliases always win. Only once none has matched does a make-level
    // default apply, and only for the makes that genuinely have one — see
    // [_fallbackPlatformByManufacturer].
    return _fallbackPlatformByManufacturer[manufacturerKey];
  }

  /// The platform record for [platformKey], or null.
  static ChassisPlatform? byKey(String? platformKey) {
    if (platformKey == null) return null;
    for (final platform in all) {
      if (platform.key == platformKey) return platform;
    }
    return null;
  }

  /// Platforms known for a manufacturer — used by the UI to tell the rider
  /// which models it can currently identify.
  static List<ChassisPlatform> forManufacturer(String? manufacturerKey) =>
      manufacturerKey == null
          ? const <ChassisPlatform>[]
          : all
              .where((p) => p.manufacturerKey == manufacturerKey)
              .toList(growable: false);
}

/// Platform-keyed chassis/ABS code table (English master).
class ChassisDtcDatabase {
  ChassisDtcDatabase._();

  /// The Bullet EFI manual lists faults without a remedy column. Rather than
  /// invent a specific technical fix per code — which nothing in the source
  /// supports — every entry in that dataset carries this one safe instruction.
  static const String bulletEfiGenericRemedy =
      'Have this inspected by an authorised Royal Enfield service center';

  /// The Honda blink table's remedy guidance.
  ///
  /// The source gives its remedy guidance for the table as a whole — air-gap
  /// inspection, continuity checks against the ABS modulator connector, fuse
  /// checks, modulator replacement where indicated, then erase and re-verify
  /// on a test ride above 30 km/h — rather than one specific fix per code.
  /// Splitting that pool across twenty codes would mean deciding, per code,
  /// which step applies; nothing in the source supports those decisions, and
  /// guessing them on a braking system is exactly what this file forbids. So
  /// it is stored once, verbatim in substance, and shown on every entry — the
  /// same choice already made for [bulletEfiGenericRemedy].
  static const String hondaBlinkRemedy =
      'Documented remedy guidance for this table: inspect the wheel speed '
      'sensor air gap, check circuit continuity against the ABS modulator '
      'connector, check the related fuses, and replace the modulator where '
      'indicated. Then erase the code and re-verify on a test ride above '
      '30 km/h.';

  static const Map<String, Map<String, ChassisDtcEntry>> byPlatform =
      <String, Map<String, ChassisDtcEntry>>{
    // ══════════════════════════════════════════════════════════════════════
    // Royal Enfield Classic 350
    // Source: Classic 350 service manual, section 9.3.11 ("ABS DTC").
    // Transcribed verbatim. Add further rows one entry at a time.
    // ══════════════════════════════════════════════════════════════════════
    ChassisPlatforms.royalEnfieldClassic350: <String, ChassisDtcEntry>{
      'C1015': ChassisDtcEntry(
        component: 'RFP/RFP_HW',
        description: 'ABS Pump/Motor Failure',
        query: 'Failure in the ABS Pump Motor',
        remedy: 'Change ABS unit',
      ),
      'C1019': ChassisDtcEntry(
        component: 'VR',
        description: 'ABS ECU Relay Fault',
        query: 'Failure in the ABS valve relay',
        remedy: 'Change ABS unit',
      ),
      'C1021': ChassisDtcEntry(
        component: 'ECU',
        description: 'ABS ECU Internal fault',
        query: 'ABS Microcontroller Failure',
        remedy: 'Change ABS unit',
      ),
      'C1024': ChassisDtcEntry(
        component: 'WSS_GENERIC',
        description: '(GENERIC) ABS Wheel Speed Difference too high',
        query: 'Signal quality from the front/Rear WSS is not good',
        remedy: 'Check the front toner wheel/ Airgap',
      ),
      'C1031': ChassisDtcEntry(
        component: 'WSS_ohmic',
        description: 'ABS Wheel Speed Circuit Open or Shorted (Rear)',
        query: 'Failure in the Rear WSS (electric)',
        remedy: 'Change Rear WSS or Check wiring from WSS to ABS',
      ),
      'C1032': ChassisDtcEntry(
        component: 'WSS_plausibility',
        description: 'ABS Wheel Speed Intermittent (Rear)',
        query: 'Signal quality from the Rear WSS is not good',
        remedy: 'Check the Rear toner wheel/Airgap consistency/WSS bracket',
      ),
      'C1033': ChassisDtcEntry(
        component: 'WSS_ohmic',
        description: 'ABS Wheel Speed Circuit Open or Shorted (Front)',
        query: 'Failure in the Front WSS (electric)',
        remedy: 'Change Front WSS or Check wiring from WSS to ABS',
      ),
      'C1034': ChassisDtcEntry(
        component: 'WSS_plausibility',
        description: 'ABS Wheel Speed Intermittent (Front)',
        query: 'Signal quality from the front WSS is not good',
        remedy: 'Check the front toner wheel/Airgap consistency/WSS bracket',
      ),
      'C1048': ChassisDtcEntry(
        component: 'Valves EV',
        description:
            '(AV) ABS Release Solenoid Circuit Open or high Resistance (Rear)',
        query: 'Failure in the rear Outlet Valve',
        remedy: 'Change ABS unit',
      ),
      'C1049': ChassisDtcEntry(
        component: 'Valves EV',
        description:
            '(AV) ABS Release Solenoid Circuit Open or high Resistance (Front)',
        query: 'Failure in the front Outlet Valve',
        remedy: 'Change ABS unit',
      ),
      'C1052': ChassisDtcEntry(
        component: 'Valves EV',
        description:
            '(EV) ABS Apply Solenoid Circuit Open or high Resistance (Rear)',
        query: 'Failure in the rear Inlet Valve',
        remedy: 'Change ABS unit',
      ),
      'C1054': ChassisDtcEntry(
        component: 'Valves EV',
        description:
            '(EV) ABS Apply Solenoid Circuit Open or high Resistance (Front)',
        query: 'Failure in the front Inlet Valve',
        remedy: 'Change ABS unit',
      ),
      'C1058': ChassisDtcEntry(
        component: 'UZ',
        description: 'ABS Voltage Low',
        query: 'Battery Voltage Too Low',
        remedy: 'Check the Battery',
      ),
      'C1059': ChassisDtcEntry(
        component: 'UZ',
        description: 'ABS Voltage High',
        query: 'Battery Voltage Too high',
        remedy: 'Check the voltage regulator/Battery',
      ),
      // Query and Remedy print as "N/A" in the manual — stored genuinely
      // empty so the UI omits those rows.
      'C1334': ChassisDtcEntry(
        component: 'ABS ECU',
        description: 'Variant not configured in EEPROM',
      ),
      'C1335': ChassisDtcEntry(
        component: 'ABS ECU',
        description: 'Variant Information Error',
      ),
      'U2921': ChassisDtcEntry(
        component: 'CAN_GENERIC',
        description: 'CAN Generic monitoring',
        query: 'CAN controller failure. Diagnosis is not possible with tester '
            'in this case.',
        remedy: 'Change ABS unit',
      ),
      'U2922': ChassisDtcEntry(
        component: 'CAN_BUSOFF',
        description: 'High Speed CAN Communications Bus Fault',
        query: 'CAN BusOff failure',
        remedy: 'Check for CAN lines connection',
      ),
      'U2926': ChassisDtcEntry(
        component: 'CAN_COMMUNIC',
        description: 'Cluster DLC / Timeout Failure',
      ),
    },

    // ══════════════════════════════════════════════════════════════════════
    // Royal Enfield Bullet EFI / Bullet Classic EFI / Continental GT (Euro IV)
    // Source: Bullet EFI service manual, page 167.
    //
    // A genuinely different platform with a different numbering convention:
    // the manual prints fault values in hex-suffix notation (`5043H`), has no
    // Failure Component or Query column, and gives no per-code remedy — hence
    // the single shared [bulletEfiGenericRemedy] on every entry.
    //
    // Keys are the manual's own notation, verbatim. See [deriveSaeCode] for
    // how a scanned SAE-format code is matched back onto these.
    // ══════════════════════════════════════════════════════════════════════
    ChassisPlatforms.royalEnfieldBulletEfi: <String, ChassisDtcEntry>{
      '5013H': ChassisDtcEntry(
        description: 'Rear Inlet Valve malfunction (EV)',
        remedy: bulletEfiGenericRemedy,
      ),
      '5014H': ChassisDtcEntry(
        description: 'Rear Outlet Valve malfunction (AV)',
        remedy: bulletEfiGenericRemedy,
      ),
      '5017H': ChassisDtcEntry(
        description: 'Front Inlet Valve malfunction (EV)',
        remedy: bulletEfiGenericRemedy,
      ),
      '5018H': ChassisDtcEntry(
        description: 'Front Outlet Valve malfunction (AV)',
        remedy: bulletEfiGenericRemedy,
      ),
      '5019H': ChassisDtcEntry(
        description: 'Valve Relay malfunction (Failsafe relay)',
        remedy: bulletEfiGenericRemedy,
      ),
      '5025H': ChassisDtcEntry(
        description: 'Deviation between Wheel speeds (WSS_GENERIC)',
        remedy: bulletEfiGenericRemedy,
      ),
      '5035H': ChassisDtcEntry(
        description: 'Pump Motor Malfunction',
        remedy: bulletEfiGenericRemedy,
      ),
      '5042H': ChassisDtcEntry(
        description: 'Front wheel speed sensor malfunction - Plausibility',
        remedy: bulletEfiGenericRemedy,
      ),
      '5043H': ChassisDtcEntry(
        description:
            'Front wheel speed sensor Disconnection/ground Short/Uz Short',
        remedy: bulletEfiGenericRemedy,
      ),
      '5044H': ChassisDtcEntry(
        description: 'Rear wheel speed sensor malfunction - Plausibility',
        remedy: bulletEfiGenericRemedy,
      ),
      '5045H': ChassisDtcEntry(
        description:
            'Rear wheel speed sensor Disconnection/ground Short/Uz Short',
        remedy: bulletEfiGenericRemedy,
      ),
      '5052H': ChassisDtcEntry(
        description: 'Power Supply Malfunction (Low Voltage)',
        remedy: bulletEfiGenericRemedy,
      ),
      '5053H': ChassisDtcEntry(
        description: 'Power Supply Malfunction (High Voltage)',
        remedy: bulletEfiGenericRemedy,
      ),
      '5055H': ChassisDtcEntry(
        description: 'ECU malfunction',
        remedy: bulletEfiGenericRemedy,
      ),
      '5122H': ChassisDtcEntry(
        description: 'Varcode EEPROM ReadError',
        remedy: bulletEfiGenericRemedy,
      ),
      '5223H': ChassisDtcEntry(
        description: 'VarCode EEPROM Out Of Range',
        remedy: bulletEfiGenericRemedy,
      ),
      '5331H': ChassisDtcEntry(
        description: 'Front Wheel Pressure sensor ohmic fault',
        remedy: bulletEfiGenericRemedy,
      ),
      '5332H': ChassisDtcEntry(
        description:
            'Front wheel pressure sensor offset/Test Pulse/POT fault',
        remedy: bulletEfiGenericRemedy,
      ),
      '5333H': ChassisDtcEntry(
        description: 'External Supply for Pressure sensor failure',
        remedy: bulletEfiGenericRemedy,
      ),
    },

    // ══════════════════════════════════════════════════════════════════════
    // Honda — ABS blink-code table
    // Source: Honda service manuals' ABS DTC table, published and consistent
    // across Honda ABS models.
    //
    // ── Read this before touching anything here ─────────────────────────────
    // The keys are NOT fault codes in the SAE sense and are not what any scan
    // returns. They are blink patterns: the number of long flashes of the ABS
    // warning lamp, a dash, then the number of short flashes, counted by eye
    // with the DLC bridged. Nothing in this table ever travels over CAN, which
    // is why [ChassisPlatforms.hondaAbsBlink] is marked
    // [ChassisReadMethod.dlcBlinkCodeManual] and is never wired to a scan.
    //
    // The notation also means [deriveSaeCode] cannot and must not match these:
    // its regex requires four hex digits and an H suffix, so a blink key falls
    // straight through it. A scanned numeric code can therefore never collide
    // with a blink pattern, which is the property that keeps this table from
    // leaking into a live read.
    //
    // Front/rear pairing: the source states the rear set explicitly and
    // completely (1-3 circuit, 1-4 sensor, 2-3 pulser ring, 4-3 wheel lock),
    // and the front set is its direct positional counterpart. 4-2 is the one
    // code the source lists without giving it a description of its own — see
    // its entry.
    // ══════════════════════════════════════════════════════════════════════
    ChassisPlatforms.hondaAbsBlink: <String, ChassisDtcEntry>{
      '1-1': ChassisDtcEntry(
        description: 'Front wheel speed sensor circuit',
        remedy: hondaBlinkRemedy,
      ),
      '1-2': ChassisDtcEntry(
        description: 'Front wheel speed sensor',
        remedy: hondaBlinkRemedy,
      ),
      '1-3': ChassisDtcEntry(
        description: 'Rear wheel speed sensor circuit',
        remedy: hondaBlinkRemedy,
      ),
      '1-4': ChassisDtcEntry(
        description: 'Rear wheel speed sensor',
        remedy: hondaBlinkRemedy,
      ),
      '1-5': ChassisDtcEntry(
        description: 'Front or rear wheel speed sensor circuit short',
        remedy: hondaBlinkRemedy,
      ),
      '2-1': ChassisDtcEntry(
        description: 'Front pulser ring',
        remedy: hondaBlinkRemedy,
      ),
      '2-3': ChassisDtcEntry(
        description: 'Rear pulser ring',
        remedy: hondaBlinkRemedy,
      ),
      // The source gives all four 3-x codes the same meaning rather than
      // distinguishing them. Reproduced as printed; inventing four different
      // modulator faults to fill the gap is not an option.
      '3-1': ChassisDtcEntry(
        description: 'Solenoid valve (ABS modulator) fault',
        remedy: hondaBlinkRemedy,
      ),
      '3-2': ChassisDtcEntry(
        description: 'Solenoid valve (ABS modulator) fault',
        remedy: hondaBlinkRemedy,
      ),
      '3-3': ChassisDtcEntry(
        description: 'Solenoid valve (ABS modulator) fault',
        remedy: hondaBlinkRemedy,
      ),
      '3-4': ChassisDtcEntry(
        description: 'Solenoid valve (ABS modulator) fault',
        remedy: hondaBlinkRemedy,
      ),
      '4-1': ChassisDtcEntry(
        description: 'Front wheel lock',
        remedy: hondaBlinkRemedy,
      ),
      // The one genuine gap in this table. The source lists 4-2 among the
      // front wheel-speed-sensor / wheel-lock codes but gives it no
      // description of its own, so none is claimed here. Listing it still
      // helps: a rider who counts four long and two short flashes learns that
      // this is a real, documented Honda code rather than a miscount, and that
      // its meaning must come from a dealer.
      '4-2': ChassisDtcEntry(
        description:
            'Listed in the source among the front wheel-speed-sensor codes, '
            'without a description of its own',
        remedy: hondaBlinkRemedy,
        meaningVerified: false,
      ),
      '4-3': ChassisDtcEntry(
        description: 'Rear wheel lock',
        remedy: hondaBlinkRemedy,
      ),
      '5-1': ChassisDtcEntry(
        description: 'ABS pump motor lock',
        remedy: hondaBlinkRemedy,
      ),
      '5-4': ChassisDtcEntry(
        description: 'ABS power supply relay',
        remedy: hondaBlinkRemedy,
      ),
      '6-1': ChassisDtcEntry(
        description: 'Supply voltage too low (under-voltage)',
        remedy: hondaBlinkRemedy,
      ),
      '6-2': ChassisDtcEntry(
        description: 'Supply voltage too high (over-voltage)',
        remedy: hondaBlinkRemedy,
      ),
      '7-1': ChassisDtcEntry(
        description: 'Tire size mismatch',
        remedy: hondaBlinkRemedy,
      ),
      '8-1': ChassisDtcEntry(
        description: 'ABS control unit fault',
        remedy: hondaBlinkRemedy,
      ),
    },

    // ══════════════════════════════════════════════════════════════════════
    // Bosch-supplied platforms — the ONE independently sourced shared code
    // ══════════════════════════════════════════════════════════════════════
    // Every Bosch platform points at the same [boschSharedCodes] map. That is
    // not a shortcut: 0x5200 is sourced from a real dealer-tool readout as a
    // Bosch *module-level* fault, i.e. a property of the modulator itself
    // rather than of the motorcycle wrapped around it, so it means the same
    // thing on a Bajaj, a Yamaha, a Suzuki and a KTM alike.
    //
    // Nothing else goes in here. Any other value read from these platforms is
    // shown as a raw module number with its meaning explicitly marked
    // unverified — see [ChassisDictionaryKind.rawUnverifiedHex] and
    // [rawModuleLabel].
    ChassisPlatforms.bajajBoschAbs: boschSharedCodes,
    ChassisPlatforms.yamahaBoschAbs: boschSharedCodes,
    ChassisPlatforms.suzukiBoschAbs: boschSharedCodes,
    ChassisPlatforms.ktmBoschAbs: boschSharedCodes,
  };

  /// The only Bosch-platform code whose meaning is independently sourced.
  ///
  /// Written in the same hex-suffix notation the Bullet EFI manual uses, so
  /// the existing [deriveSaeCode] machinery matches a scanned SAE-format code
  /// (0x5200 decodes to `C1200`) back onto it with no new mechanism.
  ///
  /// There is deliberately no remedy: the source states what the fault is, not
  /// how to fix it. The UI's own "show this value to your dealer" guidance is
  /// app copy and is rendered as such, never dressed up as manufacturer data.
  static const Map<String, ChassisDtcEntry> boschSharedCodes =
      <String, ChassisDtcEntry>{
    '5200H': ChassisDtcEntry(
      description:
          'ABS ECU EEPROM / variant read error (checksum or access byte '
          'corrupted)',
    ),
  };

  // ── Hex-notation ↔ SAE code matching ──────────────────────────────────────
  /// Convert a manual-notation fault value such as `5043H` into the
  /// five-character SAE form a scan actually produces (`C1043`), or null if
  /// [rawCode] is not in that notation.
  ///
  /// WHY THIS EXISTS — and the one inference it rests on:
  /// The UDS decoder only ever emits five-character SAE codes, because that is
  /// what the two DTC bytes on the wire decode to. The Bullet EFI manual
  /// prints the *same two bytes* in the German/Bosch convention of a hex value
  /// with an `H` suffix. Without this conversion those 19 entries could never
  /// match a scanned code and would be dead data.
  ///
  /// The conversion invents nothing: it reads `5043H` as the byte pair
  /// `0x50 0x43` and hands it to the codebase's existing, unmodified
  /// [ObdParser.decodeDtcPair] — the same standard bit-packing already used for
  /// every engine and Classic 350 code. Descriptions and remedies stay verbatim.
  ///
  /// The inference is that the `H` suffix means hexadecimal. It is corroborated
  /// within the data: the Bullet EFI manual's `5019H` "Valve Relay malfunction
  /// (Failsafe relay)" converts to `C1019`, which is independently what the
  /// Classic 350 manual calls "ABS ECU Relay Fault / Failure in the ABS valve
  /// relay" — two separately-sourced manuals agreeing on the same fault at the
  /// same value. It is nonetheless an inference and is flagged as such; if the
  /// client's testing contradicts it, deleting [_saeAliasByPlatform] removes
  /// the behaviour and leaves the verbatim entries untouched.
  static String? deriveSaeCode(String rawCode) {
    final match =
        RegExp(r'^([0-9A-F]{4})H$').firstMatch(rawCode.toUpperCase());
    if (match == null) return null;
    final value = int.parse(match.group(1)!, radix: 16);
    return ObdParser.decodeDtcPair((value >> 8) & 0xFF, value & 0xFF);
  }

  /// Per-platform index of derived SAE code → the manual's literal key.
  /// Built once, lazily, from [byPlatform] itself, so it can never drift out
  /// of sync with the data it indexes.
  static final Map<String, Map<String, String>> _saeAliasByPlatform =
      <String, Map<String, String>>{
    for (final platform in byPlatform.entries)
      platform.key: <String, String>{
        for (final code in platform.value.keys)
          if (deriveSaeCode(code) != null) deriveSaeCode(code)!: code,
      },
  };

  /// Resolve [code] to the literal dictionary key for [platformKey], following
  /// the hex-notation alias when needed. Returns null when the platform has no
  /// entry for it under either form.
  static String? canonicalCode(String? platformKey, String code) {
    if (platformKey == null) return null;
    final table = byPlatform[platformKey];
    if (table == null) return null;
    final upper = code.toUpperCase();
    if (table.containsKey(upper)) return upper;
    return _saeAliasByPlatform[platformKey]?[upper];
  }

  /// English entry for [code] under [platformKey], or null when either the
  /// platform or the specific code has no real dictionary data.
  static ChassisDtcEntry? lookup(String? platformKey, String code) {
    final canonical = canonicalCode(platformKey, code);
    if (canonical == null) return null;
    return byPlatform[platformKey]![canonical];
  }

  // ── SAE code → raw module value (the inverse of [deriveSaeCode]) ──────────
  /// The two DTC bytes behind an SAE-format code, as a single 16-bit value, or
  /// null when [code] is not a five-character SAE code.
  ///
  /// WHY THIS EXISTS: on a Bosch platform whose codes are undecoded, the SAE
  /// rendering is the least useful thing to put in front of a rider. `C1043`
  /// looks like a code from a table that does not exist. The module's own
  /// number — 0x5043 — is the value printed in Bosch documentation and the one
  /// a dealer tool would show, so it is what gets displayed and what is worth
  /// reading out over the phone to a service centre.
  ///
  /// This invents nothing. It is the exact arithmetic inverse of the standard
  /// bit-packing [ObdParser.decodeDtcPair] already performs, run backwards:
  /// the letter is the top two bits, the second character the next two, and
  /// the remaining three characters are the low nibbles.
  static int? rawModuleValue(String code) {
    final match = RegExp(r'^([PCBU])([0-3])([0-9A-F])([0-9A-F])([0-9A-F])$')
        .firstMatch(code.toUpperCase());
    if (match == null) return null;
    final letter = const <String, int>{'P': 0, 'C': 1, 'B': 2, 'U': 3}[
        match.group(1)!]!;
    final second = int.parse(match.group(2)!);
    final third = int.parse(match.group(3)!, radix: 16);
    final fourth = int.parse(match.group(4)!, radix: 16);
    final fifth = int.parse(match.group(5)!, radix: 16);
    final b1 = (letter << 6) | (second << 4) | third;
    final b2 = (fourth << 4) | fifth;
    return (b1 << 8) | b2;
  }

  /// [rawModuleValue] formatted the way Bosch documentation prints it
  /// (`0x5200`), or null when [code] is not an SAE-format code.
  static String? rawModuleLabel(String code) {
    final value = rawModuleValue(code);
    if (value == null) return null;
    return '0x${value.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  }

  /// True when this platform ships a chassis dictionary at all — lets the UI
  /// distinguish "we have no data for this model" from "this specific code is
  /// not in the table we do have".
  static bool hasDictionary(String? platformKey) =>
      platformKey != null && byPlatform.containsKey(platformKey);
}
