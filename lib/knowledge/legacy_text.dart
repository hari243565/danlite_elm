/// Danlite ELM — the 31-entry table that predates the knowledge store, offered
/// to the resolver at L4 AFTER the store (Phase 0 kept it: it is not
/// Torque-derived; its source is simply not recorded).
///
/// English only. The borrowed Torque-Pro text (the translations asset and the
/// corrupted Hindi dictionary) was deleted in Phase 4C: the shipped guidance
/// and the name-only packs replace it, and a code none of them describes now
/// gets its structure, its raw value and "show it to your dealer".
///
/// A manufacturer-defined code never reaches this (the resolver stops it before
/// L4), and it is refused here as well.
library;

import '../constants/dtc_descriptions.dart';
import '../constants/dtc_ranges.dart';
import 'fault_resolver.dart';

LegacyText? legacyEngineText(String code, String language) {
  final upper = code.toUpperCase();
  if (isManufacturerDefined(upper)) return null;
  final table = DtcDatabase.codes[upper];
  final title = table?['desc'] ?? '';
  if (title.isEmpty) return null;
  return LegacyText(
    title: title,
    cause: table?['cause'] ?? '',
    action: table?['action'] ?? '',
    severity: table?['severity'] ?? 'unknown',
  );
}
