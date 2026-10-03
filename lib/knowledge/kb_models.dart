/// Danlite ELM — what the knowledge store holds: one [KbEntry] per code, scope
/// and language, and the [PackManifest] of the pack it came in.
///
/// Pure Dart. The database layer (`knowledge_store.dart`) maps these to rows;
/// the resolver (`fault_resolver.dart`) reads them; nothing here knows about
/// SQLite or the UI.
library;

import 'dart:convert';

/// How specific an entry is. The resolver tries them most specific first.
enum ScopeKind {
  generic('generic'),
  moduleFamily('module_family'),
  platform('platform'),
  vehicle('vehicle');

  const ScopeKind(this.db);

  /// The value stored in `kb_entry.scope_kind` and written in a pack's scope.
  final String db;

  static ScopeKind? fromDb(String? v) {
    for (final s in values) {
      if (s.db == v) return s;
    }
    return null;
  }
}

/// What the rider should do, from the content rubric (`RUBRIC.md`).
enum RiderAction {
  stop('STOP'),
  serviceSoon('SERVICE_SOON'),
  monitor('MONITOR'),
  info('INFO');

  const RiderAction(this.db);
  final String db;

  static RiderAction? fromDb(String? v) {
    for (final a in values) {
      if (a.db == v) return a;
    }
    return null;
  }
}

/// Whether the bike can be ridden to a workshop (`can_ride_to_workshop`).
enum CanRide {
  yes('yes'),
  withCare('with_care'),
  no('no');

  const CanRide(this.db);
  final String db;

  static CanRide? fromDb(String? v) {
    for (final c in values) {
      if (c.db == v) return c;
    }
    return null;
  }
}

/// How a pack reached the phone. Decided by the import path, NEVER read from
/// the manifest: a downloaded file cannot promote itself to "bundled".
enum PackSource {
  /// Inside the signed APK; trusted because the APK is signed.
  bundled('bundled'),

  /// Fetched at run time (Phase 3). Must carry a valid signature.
  downloaded('downloaded'),

  /// Imported by a developer on a debug build. Never possible in a store build.
  debug('debug');

  const PackSource(this.db);
  final String db;

  static PackSource? fromDb(String? v) {
    for (final s in values) {
      if (s.db == v) return s;
    }
    return null;
  }
}

/// State of a Hindi row: `none` on rows in other languages, `machine` for
/// machine-produced Hindi, `reviewed` once a Hindi reader has checked it.
enum HiStatus {
  none('none'),
  machine('machine'),
  reviewed('reviewed');

  const HiStatus(this.db);
  final String db;

  static HiStatus? fromDb(String? v) {
    for (final s in values) {
      if (s.db == v) return s;
    }
    return null;
  }
}

/// `verification` of an entry that carries the standard's code name and nothing
/// more (no guidance written yet). The resolver gives it its own label.
const String kVerificationStandardTitleOnly = 'standard_title_only';

/// One stored meaning for one code, in one scope and one language.
///
/// Text fields are nullable: a Hindi row may carry only some of them, and the
/// resolver then takes the missing ones from the English row of the same
/// scope, with a note. Rider action, can-ride, applies-when and verification
/// are facts about the fault, not the language, so the resolver takes them
/// from the English row whenever one exists.
class KbEntry {
  const KbEntry({
    required this.contentId,
    required this.code,
    required this.scopeKind,
    this.scopeRef = '',
    required this.language,
    this.title,
    this.meaning,
    this.causes = const <String>[],
    this.riderAction,
    this.riderActionBasis,
    this.riderAdvice,
    this.hints = const <String>[],
    this.flags = const <String, bool>{},
    this.canRide,
    this.canRideReason,
    this.appliesWhen,
    this.confidence,
    required this.verification,
    this.needsIndependentReview = true,
    this.source,
    this.updatedAt = '',
    required this.packId,
    this.revoked = false,
    this.hiStatus = HiStatus.none,
    this.packReviewState,
  });

  final String contentId;
  final String code;
  final ScopeKind scopeKind;

  /// The platform key, module family or vehicle key; empty for generic.
  final String scopeRef;
  final String language;

  final String? title;
  final String? meaning;
  final List<String> causes;
  final RiderAction? riderAction;
  final String? riderActionBasis;
  final String? riderAdvice;
  final List<String> hints;
  final Map<String, bool> flags;
  final CanRide? canRide;
  final String? canRideReason;

  /// Conditions under which the entry applies (`{"cylinders_min": 2}`); null
  /// when it applies to every bike.
  final Map<String, Object?>? appliesWhen;
  final String? confidence;

  /// How the text was produced (`ai_authored_from_standard_title`, …).
  final String verification;
  final bool needsIndependentReview;
  final Map<String, Object?>? source;
  final String updatedAt;
  final String packId;
  final bool revoked;
  final HiStatus hiStatus;

  /// The `review_state` of the pack this row came in (`draft`, …), joined in
  /// when entries are loaded. Null when unknown.
  final String? packReviewState;

  /// The row is still a draft: its own flag, or its pack's review state.
  bool get isDraft =>
      needsIndependentReview || (packReviewState ?? 'draft') == 'draft';

  /// True when no text field is filled in at all.
  bool get hasNoText =>
      (title ?? '').isEmpty &&
      (meaning ?? '').isEmpty &&
      causes.isEmpty &&
      (riderAdvice ?? '').isEmpty;

  Map<String, Object?> toRow() => <String, Object?>{
        'content_id': contentId,
        'code': code,
        'scope_kind': scopeKind.db,
        'scope_ref': scopeRef,
        'language': language,
        'title': title,
        'meaning': meaning,
        'causes_json': jsonEncode(causes),
        'rider_action_level': riderAction?.db,
        'rider_action_basis': riderActionBasis,
        'rider_advice': riderAdvice,
        'hints_json': jsonEncode(hints),
        'flags_json': jsonEncode(flags),
        'can_ride': canRide?.db,
        'can_ride_reason': canRideReason,
        'applies_when_json': appliesWhen == null ? null : jsonEncode(appliesWhen),
        'confidence': confidence,
        'verification': verification,
        'needs_independent_review': needsIndependentReview ? 1 : 0,
        'source_json': source == null ? null : jsonEncode(source),
        'updated_at': updatedAt,
        'pack_id': packId,
        'status': revoked ? 'revoked' : 'active',
        'hi_status': hiStatus.db,
      };

  /// From a `kb_entry` row (optionally joined with `kb_pack.review_state` as
  /// `pack_review_state`). Malformed JSON columns read as empty, never throw.
  factory KbEntry.fromRow(Map<String, Object?> r) => KbEntry(
        contentId: r['content_id'] as String,
        code: r['code'] as String,
        scopeKind: ScopeKind.fromDb(r['scope_kind'] as String?) ?? ScopeKind.generic,
        scopeRef: (r['scope_ref'] as String?) ?? '',
        language: r['language'] as String,
        title: r['title'] as String?,
        meaning: r['meaning'] as String?,
        causes: _stringList(r['causes_json']),
        riderAction: RiderAction.fromDb(r['rider_action_level'] as String?),
        riderActionBasis: r['rider_action_basis'] as String?,
        riderAdvice: r['rider_advice'] as String?,
        hints: _stringList(r['hints_json']),
        flags: _boolMap(r['flags_json']),
        canRide: CanRide.fromDb(r['can_ride'] as String?),
        canRideReason: r['can_ride_reason'] as String?,
        appliesWhen: _objectMap(r['applies_when_json']),
        confidence: r['confidence'] as String?,
        verification: (r['verification'] as String?) ?? '',
        needsIndependentReview: (r['needs_independent_review'] as int? ?? 1) != 0,
        source: _objectMap(r['source_json']),
        updatedAt: (r['updated_at'] as String?) ?? '',
        packId: r['pack_id'] as String,
        revoked: r['status'] == 'revoked',
        hiStatus: HiStatus.fromDb(r['hi_status'] as String?) ?? HiStatus.none,
        packReviewState: r['pack_review_state'] as String?,
      );

  static Object? _decode(Object? v) {
    if (v is! String || v.isEmpty) return null;
    try {
      return jsonDecode(v);
    } on FormatException {
      return null;
    }
  }

  static List<String> _stringList(Object? v) {
    final d = _decode(v);
    return d is List ? <String>[for (final x in d) if (x is String) x] : const <String>[];
  }

  static Map<String, bool> _boolMap(Object? v) {
    final d = _decode(v);
    if (d is! Map) return const <String, bool>{};
    return <String, bool>{
      for (final e in d.entries)
        if (e.key is String && e.value is bool) e.key as String: e.value as bool,
    };
  }

  static Map<String, Object?>? _objectMap(Object? v) {
    final d = _decode(v);
    return d is Map ? Map<String, Object?>.from(d) : null;
  }
}

/// A pack's `manifest.json`, parsed and shape-checked. See
/// `docs/faults/PHASE1B_PLAN.md` "Pack format v1".
class PackManifest {
  const PackManifest({
    required this.packId,
    required this.scope,
    required this.scopeKind,
    required this.scopeRef,
    required this.language,
    required this.version,
    required this.entriesCount,
    required this.contentSha256,
    required this.createdAt,
    required this.minAppVersion,
    this.revoked = const <String>[],
    this.signature,
    this.keyId,
    this.reviewState = 'draft',
  });

  final String packId;

  /// As written: `generic`, `platform:<ref>`, `module_family:<ref>`,
  /// `vehicle:<ref>`.
  final String scope;
  final ScopeKind scopeKind;
  final String scopeRef;
  final String language;
  final int version;
  final int entriesCount;

  /// Lower-case hex SHA-256 of the entries file exactly as shipped.
  final String contentSha256;
  final String createdAt;
  final String minAppVersion;
  final List<String> revoked;

  /// base64url Ed25519 signature over [canonicalPackBytes]; null for the
  /// bundled pack.
  final String? signature;
  final String? keyId;

  /// `draft` until the content is independently reviewed.
  final String reviewState;

  /// The prefix every content_id in this pack must start with.
  String get contentIdPrefix => '$scope:';

  /// Parse and check a manifest. Returns null and fills [errors] when anything
  /// is missing, mistyped or out of range; never throws.
  static PackManifest? parse(Object? json, List<String> errors) {
    if (json is! Map) {
      errors.add('manifest is not a JSON object');
      return null;
    }
    String? str(String k, {bool optional = false}) {
      final v = json[k];
      if (v == null && optional) return null;
      if (v is! String || v.isEmpty) {
        errors.add('manifest.$k must be a non-empty string');
        return null;
      }
      if (v.contains('\n') || v.contains('\r')) {
        errors.add('manifest.$k must be one line');
        return null;
      }
      return v;
    }

    int? integer(String k, {int min = 0}) {
      final v = json[k];
      if (v is! int || v < min) {
        errors.add('manifest.$k must be an integer >= $min');
        return null;
      }
      return v;
    }

    final packId = str('pack_id');
    final scope = str('scope');
    final language = str('language');
    final version = integer('version', min: 1);
    final count = integer('entries_count');
    final sha = str('content_sha256');
    final created = str('created_at');
    final minApp = str('min_app_version');
    final signature = json['signature'];
    final keyId = str('key_id', optional: true);
    final review = json['review_state'];
    final revokedRaw = json['revoked'] ?? const <Object?>[];

    if (packId != null && !RegExp(r'^[a-z0-9_.-]{1,64}$').hasMatch(packId)) {
      errors.add('manifest.pack_id has characters outside a-z 0-9 _ . -');
    }
    if (language != null && !RegExp(r'^[a-z]{2,3}$').hasMatch(language)) {
      errors.add('manifest.language must be a 2 or 3 letter code');
    }
    if (sha != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      errors.add('manifest.content_sha256 must be 64 lower-case hex digits');
    }
    if (minApp != null && parseAppVersion(minApp) == null) {
      errors.add('manifest.min_app_version must look like 1.2.3');
    }
    if (signature != null && (signature is! String || signature.isEmpty)) {
      errors.add('manifest.signature must be a string or null');
    }
    if (review != null && review is! String) {
      errors.add('manifest.review_state must be a string');
    }
    final revoked = <String>[];
    if (revokedRaw is! List) {
      errors.add('manifest.revoked must be a list');
    } else {
      for (final r in revokedRaw) {
        if (r is! String || r.isEmpty || r.contains('\n') || r.contains(',')) {
          errors.add('manifest.revoked holds a bad content_id');
        } else {
          revoked.add(r);
        }
      }
    }

    ScopeKind? kind;
    var ref = '';
    if (scope != null) {
      final parts = scope.split(':');
      kind = ScopeKind.fromDb(parts.first);
      if (kind == null) {
        errors.add('manifest.scope "$scope" is not generic, module_family, platform or vehicle');
      } else if (kind == ScopeKind.generic) {
        if (parts.length != 1) errors.add('manifest.scope generic takes no reference');
      } else if (parts.length != 2 || !RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(parts[1])) {
        errors.add('manifest.scope ${kind.db} needs one reference (a-z 0-9 _)');
      } else {
        ref = parts[1];
      }
    }

    if (errors.isNotEmpty) return null;
    return PackManifest(
      packId: packId!,
      scope: scope!,
      scopeKind: kind!,
      scopeRef: ref,
      language: language!,
      version: version!,
      entriesCount: count!,
      contentSha256: sha!,
      createdAt: created!,
      minAppVersion: minApp!,
      revoked: List<String>.unmodifiable(revoked),
      signature: signature as String?,
      keyId: keyId,
      reviewState: (review as String?) ?? 'draft',
    );
  }
}

/// `1.2.3` (an optional `+build` is ignored) as three integers; null if not
/// that shape.
List<int>? parseAppVersion(String v) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)(\+\d+)?$').firstMatch(v.trim());
  if (m == null) return null;
  return <int>[int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)];
}

/// True when app version [app] is at least [min]. Unparseable means no.
bool appVersionAtLeast(String app, String min) {
  final a = parseAppVersion(app);
  final b = parseAppVersion(min);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return true;
}
