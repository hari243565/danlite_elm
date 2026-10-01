/// Danlite ELM — the on-phone database schema and its migrations.
///
/// One SQLite file holds the knowledge store and the scan history. Only SQL
/// that the oldest supported Android (API 21, SQLite 3.8) understands is used:
/// no UPSERT, no RETURNING, no JSON1, no full-text search, no window functions.
/// Lists are stored as JSON text and decoded in Dart. `test/kb_store_test.dart`
/// scans this folder for the forbidden syntax.
///
/// Migrations are an ordered list; migration N takes the database from schema
/// N-1 to N. Each runs inside sqflite's open transaction, and the
/// `schema_version` table records the result alongside SQLite's own
/// `user_version`.
library;

import 'package:sqflite/sqflite.dart';

/// The schema this build writes.
const int kKnowledgeSchemaVersion = 1;

/// Statements per migration; index 0 is migration 1.
const List<List<String>> kMigrations = <List<String>>[
  // ── 1: knowledge store + scan history ──────────────────────────────────
  <String>[
    'CREATE TABLE schema_version (version INTEGER NOT NULL)',
    'INSERT INTO schema_version (version) VALUES (0)',
    'CREATE TABLE kb_pack ('
        'pack_id TEXT PRIMARY KEY NOT NULL, '
        'version INTEGER NOT NULL, '
        'scope TEXT NOT NULL, '
        'language TEXT NOT NULL, '
        'source TEXT NOT NULL, '
        'review_state TEXT NOT NULL, '
        'content_sha256 TEXT NOT NULL, '
        'entries_count INTEGER NOT NULL, '
        'min_app_version TEXT NOT NULL, '
        'imported_at INTEGER NOT NULL)',
    'CREATE TABLE kb_entry ('
        'content_id TEXT PRIMARY KEY NOT NULL, '
        'code TEXT NOT NULL, '
        'scope_kind TEXT NOT NULL, '
        "scope_ref TEXT NOT NULL DEFAULT '', "
        'language TEXT NOT NULL, '
        'title TEXT, '
        'meaning TEXT, '
        'causes_json TEXT, '
        'rider_action_level TEXT, '
        'rider_action_basis TEXT, '
        'rider_advice TEXT, '
        'hints_json TEXT, '
        'flags_json TEXT, '
        'can_ride TEXT, '
        'can_ride_reason TEXT, '
        'applies_when_json TEXT, '
        'confidence TEXT, '
        'verification TEXT NOT NULL, '
        'needs_independent_review INTEGER NOT NULL, '
        'source_json TEXT, '
        'updated_at TEXT, '
        'pack_id TEXT NOT NULL, '
        "status TEXT NOT NULL DEFAULT 'active', "
        "hi_status TEXT NOT NULL DEFAULT 'none')",
    'CREATE INDEX kb_entry_lookup ON kb_entry (code, scope_kind, scope_ref, language)',
    'CREATE INDEX kb_entry_language ON kb_entry (language)',
    'CREATE INDEX kb_entry_pack ON kb_entry (pack_id)',
    'CREATE TABLE kb_revoked ('
        'content_id TEXT NOT NULL, '
        'pack_id TEXT NOT NULL)',
    'CREATE INDEX kb_revoked_id ON kb_revoked (content_id)',
    'CREATE TABLE scan_session ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'kind TEXT NOT NULL, '
        'started_at INTEGER NOT NULL, '
        'last_seen_at INTEGER NOT NULL, '
        'repeat_count INTEGER NOT NULL DEFAULT 1, '
        'connection_id TEXT, '
        'signature TEXT, '
        'profile_id TEXT, '
        'vehicle_label TEXT, '
        'adapter_class TEXT, '
        'protocol TEXT, '
        'reach_state TEXT NOT NULL, '
        'engine_state TEXT, '
        'voltage_band TEXT, '
        'lamp_state TEXT, '
        'clear_outcome TEXT, '
        'pre_clear_json TEXT)',
    'CREATE INDEX scan_session_kind ON scan_session (kind, id)',
    'CREATE TABLE scan_fault ('
        'session_id INTEGER NOT NULL, '
        'position INTEGER NOT NULL, '
        'code TEXT NOT NULL, '
        'display_code TEXT NOT NULL, '
        'system TEXT, '
        'format TEXT NOT NULL, '
        'raw_hex TEXT, '
        'failure_type INTEGER, '
        'status_byte INTEGER, '
        'status_json TEXT, '
        'source TEXT NOT NULL, '
        'module TEXT, '
        'read_at INTEGER NOT NULL, '
        'resolved_level TEXT, '
        'resolved_content_id TEXT)',
    'CREATE INDEX scan_fault_session ON scan_fault (session_id)',
  ],
];

/// Run migrations `from + 1` … `to`, then record [to].
Future<void> runMigrations(DatabaseExecutor db, int from, int to) async {
  for (var v = from + 1; v <= to; v++) {
    for (final sql in kMigrations[v - 1]) {
      await db.execute(sql);
    }
  }
  await db.update('schema_version', <String, Object?>{'version': to});
}
