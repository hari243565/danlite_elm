/// Danlite ELM — checks one pack line against content schema version 2 before
/// anything is written to the store.
///
/// A Dart port of the SCHEMA rules of `data/content/validate_seed.py` on the
/// content branch (required fields, types, enums, length caps, the D4
/// level-to-can-ride mapping, `applies_when`, the D6 "no word verified" rule),
/// plus the rules only an importer can enforce: the content_id belongs to this
/// pack's scope and language, and a GENERIC pack can never carry a
/// manufacturer-defined code. The content pipeline's wording rules (R1–R10)
/// stay in the Python validator, which runs before a pack is built.
///
/// Field names carry the pack's language: `title_en` in an English pack,
/// `title_hi` in a Hindi one. A non-English pack may carry only some text
/// fields — the resolver fills the rest from English, with a note.
///
/// Pure Dart. Never throws.
library;

import '../constants/dtc_ranges.dart';
import 'kb_models.dart';

/// The schema version every line must declare.
const int kKbEntrySchemaVersion = 2;

const Set<String> _systems = {'powertrain', 'chassis', 'body', 'network'};
const Map<String, String> _systemOf = {
  'P': 'powertrain',
  'C': 'chassis',
  'B': 'body',
  'U': 'network',
};
const Set<String> _confidence = {'high', 'medium', 'low'};
const Set<String> _derivedModes = {'adapted', 'structure-only'};

/// The only `verification` values a v2 entry may carry (D6: every entry is
/// AI-authored guidance; the word "verified" appears nowhere).
const Set<String> kAllowedVerification = {
  'ai_authored_from_standard_title',
  'ai_authored_adapted',
  kVerificationStandardTitleOnly,
};

/// D4: which can-ride answers each rider action level allows.
const Map<RiderAction, Set<CanRide>> _rideAllowed = {
  RiderAction.stop: {CanRide.no},
  RiderAction.serviceSoon: {CanRide.withCare, CanRide.yes},
  RiderAction.monitor: {CanRide.yes},
  RiderAction.info: {CanRide.yes},
};

/// `applies_when` keys and the only value each may take.
///
/// The same set as `APPLIES_KEYS` in `data/content/validate_seed.py`: the
/// content pipeline may only use keys this importer accepts, and the resolver
/// shows an unknown one with a note (`kAppliesNoteKeys`).
final Map<String, bool Function(Object?)> _appliesKeys = {
  'cylinders_min': (v) => v == 2,
  for (final k in const [
    'liquid_cooled', 'ride_by_wire', 'abs_fitted', 'knock_sensor_fitted',
    'camshaft_sensor_fitted', 'oil_temp_sensor_fitted',
    'closed_throttle_switch_fitted', 'evap_fitted', 'secondary_air_fitted',
    'cooling_fan_fitted', 'oil_pressure_sensor_fitted',
    'ambient_temp_sensor_fitted', 'fuel_level_sensor_fitted',
    'gear_position_sensor_fitted', 'clutch_switch_fitted',
    'downstream_o2_sensor_fitted', 'can_bus_fitted',
  ])
    k: (Object? v) => v == true,
};

/// English length caps from the content validator.
const Map<String, int> _limits = {
  'title': 70,
  'meaning': 200,
  'rider_action_basis': 60,
  'rider_advice': 220,
  'can_ride_reason': 80,
};

/// (min items, max items, max chars per item).
const Map<String, List<int>> _listLimits = {
  'likely_causes': [2, 4, 60],
  'technician_hints': [1, 3, 90],
};

/// Devanagari and other scripts run longer than English for the same meaning;
/// caps for a non-English pack are this much looser. Still a hard cap, so a
/// runaway line cannot reach the screen.
const double kNonEnglishLengthFactor = 1.6;

final RegExp _saeCode = RegExp(r'^[PCBU][0-3][0-9A-F]{3}$');
final RegExp _hexHCode = RegExp(r'^[0-9A-F]{4}H$');
final RegExp _blinkCode = RegExp(r'^[1-9]-[1-9]$');
final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _verifiedWord =
    RegExp(r'\bverif(y|ied|ies|ication)\b', caseSensitive: false);

/// The text fields whose names carry a language suffix.
const List<String> _textFields = [
  'title',
  'meaning',
  'likely_causes',
  'rider_advice',
  'technician_hints',
];

/// Fields every line needs, whatever its language.
const List<String> _commonRequired = [
  'schema_version',
  'content_id',
  'code',
  'system',
  'rider_action_level',
  'can_ride_to_workshop',
  'flags',
  'applies_when',
  'confidence',
  'derived_from',
  'verification',
  'needs_independent_review',
  'updated_at',
];

/// A value as text, or null when it is not text (a pack line is untrusted).
String? _str(Object? v) => v is String ? v : null;

class EntryValidation {
  EntryValidation(this.entry, this.errors);
  final KbEntry? entry;
  final List<String> errors;
  bool get ok => entry != null && errors.isEmpty;
}

/// Validate one decoded JSONL line for [manifest]. Returns the entry ready to
/// store, or the reasons it was refused.
EntryValidation validateEntry(Object? line, PackManifest manifest) {
  final errors = <String>[];
  if (line is! Map) {
    return EntryValidation(null, <String>['line is not a JSON object']);
  }
  final r = Map<String, Object?>.from(line);
  final lang = manifest.language;
  final english = lang == 'en';
  final codeRaw = r['code'];
  final c = codeRaw is String ? codeRaw : '?';
  void err(String m) => errors.add('$c: $m');

  // ── required and allowed fields ────────────────────────────────────────
  final required = <String>[
    ..._commonRequired,
    'title_$lang',
    if (english) ...[
      'standard_title_en',
      'meaning_en',
      'likely_causes_en',
      'rider_action_basis',
      'rider_advice_en',
      'can_ride_reason',
      'technician_hints_en',
    ],
  ];
  final missing = [for (final k in required) if (!r.containsKey(k)) k];
  if (missing.isNotEmpty) {
    err('missing fields $missing');
    return EntryValidation(null, errors);
  }
  final allowed = <String>{
    ..._commonRequired,
    'standard_title_en',
    'rider_action_basis',
    'can_ride_reason',
    for (final f in _textFields) ...['${f}_en', '${f}_$lang'],
    if (!english) ...['rider_action_basis_$lang', 'can_ride_reason_$lang', 'hi_status'],
  };
  final extra = r.keys.where((k) => !allowed.contains(k)).toList()..sort();
  if (extra.isNotEmpty) err('unexpected fields $extra');

  // ── identity ───────────────────────────────────────────────────────────
  if (r['schema_version'] != kKbEntrySchemaVersion) {
    err('schema_version must be $kKbEntrySchemaVersion');
  }
  final generic = manifest.scopeKind == ScopeKind.generic;
  final codeOk = codeRaw is String &&
      (_saeCode.hasMatch(codeRaw) ||
          (!generic && (_hexHCode.hasMatch(codeRaw) || _blinkCode.hasMatch(codeRaw))));
  if (!codeOk) err('bad code format');
  if (r['content_id'] != '${manifest.contentIdPrefix}$c:$lang') {
    err('content_id must be ${manifest.contentIdPrefix}$c:$lang');
  }
  // The line that keeps a maker's meaning out of every other maker's bike.
  if (generic && codeOk && isManufacturerDefined(c)) {
    err('manufacturer-defined code in a generic pack');
  }
  final system = r['system'];
  if (system is! String || !_systems.contains(system)) {
    err('bad system $system');
  } else if (codeOk && _saeCode.hasMatch(c) && _systemOf[c[0]] != system) {
    err('system $system does not match the code letter');
  }

  // ── enums and types ────────────────────────────────────────────────────
  final level = RiderAction.fromDb(_str(r['rider_action_level']));
  if (level == null) err('bad rider_action_level ${r['rider_action_level']}');
  final ride = CanRide.fromDb(_str(r['can_ride_to_workshop']));
  if (ride == null) {
    err('bad can_ride_to_workshop ${r['can_ride_to_workshop']}');
  } else if (level != null && !_rideAllowed[level]!.contains(ride)) {
    err('can_ride_to_workshop ${ride.db} is not allowed for ${level.db} (D4)');
  }
  final confidence = r['confidence'];
  if (confidence is! String || !_confidence.contains(confidence)) {
    err('bad confidence');
  }
  final updated = r['updated_at'];
  if (updated is! String || !_isoDate.hasMatch(updated)) {
    err('updated_at must be an ISO date');
  }
  final flags = r['flags'];
  if (flags is! Map ||
      flags.keys.toSet().difference({'mil', 'emissions_relevant', 'limp_possible'}).isNotEmpty ||
      flags.length != 3 ||
      !flags.values.every((v) => v is bool)) {
    err('flags must be exactly mil, emissions_relevant, limp_possible booleans');
  }
  final derived = r['derived_from'];
  if (derived is! Map ||
      derived['source'] is! String ||
      derived['licence'] is! String ||
      !_derivedModes.contains(derived['mode'])) {
    err('derived_from needs source, licence and an allowed mode');
  }
  final verification = r['verification'];
  if (verification is! String || !kAllowedVerification.contains(verification)) {
    err('verification "$verification" is not an allowed label');
  }
  final review = r['needs_independent_review'];
  if (review is! bool) err('needs_independent_review must be true or false');
  final aw = r['applies_when'];
  Map<String, Object?>? appliesWhen;
  if (aw != null) {
    if (aw is! Map ||
        aw.isEmpty ||
        aw.entries.any((e) => !_appliesKeys.containsKey(e.key) || !_appliesKeys[e.key]!(e.value))) {
      err('applies_when must be null or use only ${_appliesKeys.keys.toList()} with valid values');
    } else {
      appliesWhen = Map<String, Object?>.from(aw);
    }
  }
  HiStatus hiStatus = HiStatus.none;
  if (!english) {
    final hs = r['hi_status'];
    if (hs == null) {
      hiStatus = lang == 'hi' ? HiStatus.machine : HiStatus.none;
    } else {
      final parsed = hs is String ? HiStatus.fromDb(hs) : null;
      if (parsed == null || parsed == HiStatus.none) {
        err('hi_status must be machine or reviewed');
      } else {
        hiStatus = parsed;
      }
    }
  }

  // ── text and lengths ───────────────────────────────────────────────────
  final factor = english ? 1.0 : kNonEnglishLengthFactor;
  String? text(String base, String key, {bool required = false}) {
    final v = r[key];
    if (v == null && !required) return null;
    if (v is! String || v.trim().isEmpty) {
      err('$key empty or not a string');
      return null;
    }
    final cap = (_limits[base]! * factor).floor();
    if (v.length > cap) err('$key is ${v.length} chars, limit $cap');
    return v.trim();
  }

  List<String> list(String base, String key, {bool required = false}) {
    final v = r[key];
    if (v == null && !required) return const <String>[];
    final lim = _listLimits[base]!;
    if (v is! List || v.length < lim[0] || v.length > lim[1]) {
      err('$key needs ${lim[0]} to ${lim[1]} items');
      return const <String>[];
    }
    final out = <String>[];
    final cap = (lim[2] * factor).floor();
    for (final x in v) {
      if (x is! String || x.trim().isEmpty) {
        err('$key has an empty item');
      } else if (x.length > cap) {
        err('$key item is ${x.length} chars, limit $cap');
      } else {
        out.add(x.trim());
      }
    }
    if (out.map((x) => x.toLowerCase()).toSet().length != out.length) {
      err('$key has duplicate items');
    }
    return out;
  }

  final title = text('title', 'title_$lang', required: true);
  final meaning = text('meaning', 'meaning_$lang', required: english);
  final advice = text('rider_advice', 'rider_advice_$lang', required: english);
  final causes = list('likely_causes', 'likely_causes_$lang', required: english);
  final hints = list('technician_hints', 'technician_hints_$lang', required: english);
  final basis = english
      ? text('rider_action_basis', 'rider_action_basis', required: true)
      : text('rider_action_basis', 'rider_action_basis_$lang');
  final rideReason = english
      ? text('can_ride_reason', 'can_ride_reason', required: true)
      : text('can_ride_reason', 'can_ride_reason_$lang');
  // Unsuffixed English fields in a non-English pack are checked, not stored.
  if (!english) {
    text('rider_action_basis', 'rider_action_basis');
    text('can_ride_reason', 'can_ride_reason');
  }

  // D6: no text may claim verification.
  final allText = [title, meaning, advice, basis, rideReason, ...causes, ...hints]
      .whereType<String>()
      .join(' | ');
  final v = _verifiedWord.firstMatch(allText);
  if (v != null) err('the word "${v[0]}" must not appear in any text (D6)');

  if (errors.isNotEmpty) return EntryValidation(null, errors);
  return EntryValidation(
    KbEntry(
      contentId: r['content_id'] as String,
      code: c,
      scopeKind: manifest.scopeKind,
      scopeRef: manifest.scopeRef,
      language: lang,
      title: title,
      meaning: meaning,
      causes: causes,
      riderAction: level,
      riderActionBasis: basis,
      riderAdvice: advice,
      hints: hints,
      flags: Map<String, bool>.from(flags as Map),
      canRide: ride,
      canRideReason: rideReason,
      appliesWhen: appliesWhen,
      confidence: confidence as String,
      verification: verification as String,
      needsIndependentReview: review as bool,
      source: Map<String, Object?>.from(derived as Map),
      updatedAt: updated as String,
      packId: manifest.packId,
      hiStatus: hiStatus,
    ),
    errors,
  );
}
