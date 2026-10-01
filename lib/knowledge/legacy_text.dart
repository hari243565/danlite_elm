/// Danlite ELM — the engine text that predates the knowledge store, offered
/// to the resolver at L4 AFTER the store, in exactly the order Phase 0 set:
///
///  * Hindi from the legacy JSON (only while `kUseLegacyEngineText` is on);
///  * the 31-entry `DtcDatabase` English (outside the switch — Phase 0 kept
///    it: it is not Torque-derived);
///  * English from the legacy JSON (only while the switch is on).
///
/// The corrupted `DtcDictionaryHi` is never consulted. A manufacturer-defined
/// code never reaches this (the resolver stops it before L4).
///
/// Separate from the pure resolver because the JSON lives behind Flutter
/// asset loading (`DtcLocalizations`).
library;

import '../constants/dtc_descriptions.dart';
import '../services/dtc_service.dart';
import 'fault_resolver.dart';

LegacyText? legacyEngineText(String code, String language,
    {required bool useImported}) {
  final table = DtcDatabase.codes[code];
  final tableTitle = table?['desc'] ?? '';
  final title = DtcLocalizations.description(code, language,
      englishFallback: tableTitle, useLegacyText: useImported);
  if (title.isEmpty) return null;
  final fromTable = title == tableTitle && tableTitle.isNotEmpty;
  return LegacyText(
    title: title,
    // Only the JSON carries Hindi; anything else is English.
    language: fromTable ? 'en' : (language == 'hi' && title != _jsonEnglish(code, useImported)
        ? 'hi'
        : 'en'),
    imported: !fromTable,
    cause: table?['cause'] ?? '',
    action: table?['action'] ?? '',
    severity: table?['severity'] ?? 'unknown',
  );
}

String? _jsonEnglish(String code, bool useImported) {
  final en = DtcLocalizations.description(code, 'en',
      englishFallback: '', useLegacyText: useImported);
  return en.isEmpty ? null : en;
}
