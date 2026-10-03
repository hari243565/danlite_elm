/// Danlite ELM — typed-code lookup: no bike, no adapter, no network.
///
/// [parseLookupQuery] turns what a rider types into codes, code prefixes or
/// words — forgiving about case, spaces, dashes, a letter O typed for a zero
/// (`PO120`), a Bosch module value written `5043H` or `0x5043`, and a Honda
/// blink pattern written `4-3`, `4 3` or `4.3`. [searchCodes] looks in the
/// knowledge store (indexed code match plus LIKE on title and meaning) and in
/// the existing manual tables, and returns at most [kLookupMaxResults].
///
/// A result only says WHERE a meaning is listed. What the rider is told about
/// a code is always the resolver's answer for their vehicle (the detail page),
/// so a meaning listed for another make is never applied to theirs.
library;

import '../constants/chassis_dtc_dictionary.dart';
import '../constants/chassis_dtc_dictionary_hi.dart';
import '../models/fault_record.dart';
import 'fault_resolver.dart';
import 'kb_models.dart';
import 'knowledge_store.dart';

const int kLookupMaxResults = 50;

class LookupQuery {
  const LookupQuery({
    this.raw = '',
    this.codes = const <String>[],
    this.prefixes = const <String>[],
    this.words = const <String>[],
    this.format = DtcFormat.sae2,
  });

  final String raw;

  /// Exact codes to match (`P0120`, `5043H` and its SAE form `C1043`, `4-3`).
  final List<String> codes;

  /// Partial codes (`P01`).
  final List<String> prefixes;

  /// Lower-case words, all of which must appear.
  final List<String> words;

  /// How the code was written, for the record the detail page resolves.
  final DtcFormat format;

  bool get isEmpty => codes.isEmpty && prefixes.isEmpty && words.isEmpty;
}

final RegExp _blink = RegExp(r'^([1-9])\s*[-–—.\s]\s*([1-9])$');
final RegExp _hex = RegExp(r'^(?:0X)?([0-9A-F]{4})H?$');
final RegExp _sae = RegExp(r'^[PCBU][0-3][0-9A-F]{3}$');
final RegExp _partial = RegExp(r'^[PCBU][0-3]?[0-9A-F]{0,3}$');

LookupQuery parseLookupQuery(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return const LookupQuery();
  final b = _blink.firstMatch(raw);
  if (b != null) {
    return LookupQuery(raw: raw, codes: ['${b[1]}-${b[2]}'], format: DtcFormat.blink);
  }
  final compact = raw.toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');
  // A letter O where a digit must be ("PO120", "P0I20" is not fixed: only O).
  final fixed = compact.length >= 2 && 'PCBU'.contains(compact[0])
      ? compact[0] + compact.substring(1).replaceAll('O', '0')
      : compact;
  if (_sae.hasMatch(fixed)) return LookupQuery(raw: raw, codes: [fixed]);
  final explicitHex = compact.startsWith('0X') || compact.endsWith('H');
  final h = _hex.firstMatch(compact);
  if (h != null && explicitHex) {
    final key = '${h[1]}H';
    final sae = ChassisDtcDatabase.deriveSaeCode(key);
    return LookupQuery(
        raw: raw, codes: [key, if (sae != null) sae], format: DtcFormat.hexH);
  }
  if (fixed.length >= 2 && fixed.length <= 4 && _partial.hasMatch(fixed)) {
    return LookupQuery(raw: raw, prefixes: [fixed]);
  }
  final words = raw
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.length >= 2)
      .take(5)
      .toList();
  return LookupQuery(raw: raw, words: words);
}

/// Where a meaning is listed.
enum LookupScope { generic, platform, moduleFamily, vehicle }

class LookupResult {
  const LookupResult({
    required this.code,
    required this.title,
    required this.scope,
    required this.format,
    this.scopeRef = '',
    this.scopeName,
  });

  final String code;
  final String title;
  final LookupScope scope;
  final DtcFormat format;

  /// Platform key or family; empty for generic.
  final String scopeRef;

  /// Human name of the scope ("Classic 350"), when it has one.
  final String? scopeName;

  String get key => '${scope.name}|$scopeRef|$code';
}

class LookupResults {
  const LookupResults(this.items, {this.capped = false});
  final List<LookupResult> items;

  /// More matched than [kLookupMaxResults].
  final bool capped;

  static const LookupResults empty = LookupResults(<LookupResult>[]);
}

/// Search the store (when there is one) and the manual tables.
Future<LookupResults> searchCodes(LookupQuery q,
    {KnowledgeStore? store, required String language}) async {
  if (q.isEmpty) return LookupResults.empty;
  final exact = <LookupResult>[];
  final prefix = <LookupResult>[];
  final word = <LookupResult>[];
  final seen = <String>{};
  void add(List<LookupResult> into, LookupResult r) {
    if (seen.add(r.key)) into.add(r);
  }

  // ── knowledge store ────────────────────────────────────────────────────
  if (store != null) {
    // A code has one row per language: ask for enough rows that the
    // one-result-per-code merge below still sees a full page of codes.
    final languages = await store.languageCount();
    final rows = await store.search(
        codes: q.codes,
        prefixes: q.prefixes,
        words: q.words,
        limit: (kLookupMaxResults + 1) * (languages < 1 ? 1 : languages));
    // One result per code and scope, in the asked language when present.
    final best = <String, KbEntry>{};
    for (final e in rows) {
      final k = '${e.scopeKind.db}|${e.scopeRef}|${e.code}';
      final have = best[k];
      if (have == null || (e.language == language && have.language != language)) {
        best[k] = e;
      }
    }
    for (final e in best.values) {
      final r = LookupResult(
        code: e.code,
        title: e.title ?? e.meaning ?? e.code,
        scope: switch (e.scopeKind) {
          ScopeKind.generic => LookupScope.generic,
          ScopeKind.platform => LookupScope.platform,
          ScopeKind.moduleFamily => LookupScope.moduleFamily,
          ScopeKind.vehicle => LookupScope.vehicle,
        },
        scopeRef: e.scopeRef,
        scopeName: ChassisPlatforms.byKey(e.scopeRef)?.displayName,
        format: q.format,
      );
      add(q.codes.contains(e.code) ? exact : (q.words.isEmpty ? prefix : word), r);
    }
  }

  // ── manual tables (Bosch shared once, as a module family) ─────────────
  var boschDone = false;
  for (final platform in ChassisDtcDatabase.byPlatform.entries) {
    final bosch = identical(platform.value, ChassisDtcDatabase.boschSharedCodes);
    if (bosch && boschDone) continue;
    if (bosch) boschDone = true;
    for (final row in platform.value.entries) {
      final key = row.key;
      final sae = ChassisDtcDatabase.deriveSaeCode(key);
      final hi = ChassisDtcDictionaryHi.lookup(platform.key, key);
      final title = language == 'hi' && hi != null && hi.description.isNotEmpty
          ? hi.description
          : row.value.description;
      final r = LookupResult(
        code: key,
        title: title,
        scope: bosch ? LookupScope.moduleFamily : LookupScope.platform,
        scopeRef: bosch ? kBoschAbsFamily : platform.key,
        scopeName: bosch ? null : ChassisPlatforms.byKey(platform.key)?.displayName,
        format: key.contains('-')
            ? DtcFormat.blink
            : (sae != null ? DtcFormat.hexH : DtcFormat.sae2),
      );
      if (q.codes.contains(key) || (sae != null && q.codes.contains(sae))) {
        add(exact, r);
      } else if (q.prefixes.any((p) => key.startsWith(p) || (sae?.startsWith(p) ?? false))) {
        add(prefix, r);
      } else if (q.words.isNotEmpty) {
        final text = '${row.value.description} ${hi?.description ?? ''}'.toLowerCase();
        if (q.words.every(text.contains)) add(word, r);
      }
    }
  }

  final all = [...exact, ...prefix, ...word];
  return LookupResults(all.take(kLookupMaxResults).toList(),
      capped: all.length > kLookupMaxResults);
}

/// The record the detail page resolves for a typed [code].
FaultRecord lookupRecord(String code, DtcFormat format) =>
    FaultRecord.manual(code, format: format, readAt: DateTime.now());
