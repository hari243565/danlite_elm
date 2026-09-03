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

  const ChassisDtcEntry({
    required this.description,
    this.component = '',
    this.query = '',
    this.remedy = '',
    this.severity = 'critical',
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

  /// Normalised free-text spellings → canonical key. Extend this when adding a
  /// manufacturer; nothing else needs to change.
  static const Map<String, String> _aliases = <String, String>{
    'royalenfield': royalEnfield,
    'royalenfieldmotors': royalEnfield,
    're': royalEnfield,
  };

  /// Human-readable label for a canonical key, for UI display.
  static const Map<String, String> displayNames = <String, String>{
    royalEnfield: 'Royal Enfield',
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

  const ChassisPlatform({
    required this.key,
    required this.manufacturerKey,
    required this.displayName,
    required this.modelAliases,
  });
}

/// Platform registry and the make+model resolution that selects a dataset.
class ChassisPlatforms {
  ChassisPlatforms._();

  static const String royalEnfieldClassic350 = 'royal_enfield_classic350';
  static const String royalEnfieldBulletEfi = 'royal_enfield_bullet_efi';

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
  ];

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
    return null;
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

  /// True when this platform ships a chassis dictionary at all — lets the UI
  /// distinguish "we have no data for this model" from "this specific code is
  /// not in the table we do have".
  static bool hasDictionary(String? platformKey) =>
      platformKey != null && byPlatform.containsKey(platformKey);
}
