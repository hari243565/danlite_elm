# Phase 1B plan — knowledge store, resolver, scan history, code lookup, honest Clear-Codes record

Branch `feat/fault-phase1b` from `main` @ `6490606` (Phase 1A on main). Worktree `../danlite_elm_phase1b`.
Baseline: **417 tests pass**; `flutter analyze` **7 issues** (the known ones in `dashboard_screen`, `fuel_screen`,
`hud_screen`, `realtime_screen`). Content: `origin/content/seed-20261001:data/content/generic_en_seed.jsonl`
(140 entries, schema v2, all `ai_authored_from_standard_title`, DRAFT).

## Facts from reading the code that shape the design

| Fact | Where | Consequence |
|---|---|---|
| No database package in the project; `path` only transitive. `cryptography` 2.9.0 is the Ed25519 primitive (`entitlement_service.dart` `_verifyPayload`, hard-wired to licence fields) | `pubspec.yaml`, `pubspec.lock` | Add `sqflite` 2.4.4 + `path` (direct); `sqflite_common_ffi` dev-only for host tests. Debug APK checked to build with them **before** any code was written. Pack verifier reuses `Ed25519()` + `SimplePublicKey` from `cryptography`, with its own canonical bytes and its own (unset) key. |
| `android:allowBackup` is not set, so Android Auto Backup copies the default databases folder to the rider's cloud backup | `AndroidManifest.xml`; the recorder already uses `noBackupFilesDir` (`MainActivity.kt`) | The database file lives in `noBackupFilesDir/knowledge/` via one new method on the EXISTING `com.danlite.elm/session_recorder` channel. If that path is unavailable on Android, the store opens in memory (history not kept) rather than in a backed-up folder. |
| `isManufacturerDefined` and `subsystemKey` live in `dtc_service.dart`, which imports Flutter | `dtc_service.dart` | Moved to pure `lib/constants/dtc_ranges.dart`; `dtc_service.dart` re-exports / delegates, so every caller and test is unchanged. |
| Phase 0 decided the 31-entry `DtcDatabase` "is not Torque-derived and stays" (test S7) and is outside `kUseLegacyEngineText` | `fault_text_resolution_test.dart` | Kept outside the switch, ordered AFTER the knowledge store at L4 and labelled "older app text, source not recorded". Not re-litigated. |
| Existing widget tests render `DtcScreen` with no knowledge store and expect today's text (e.g. P0198 = JSON text) | `fault_text_resolution_test.dart`, `engine_reach_result_test.dart` | The card reads the knowledge service from an OPTIONAL provider; with none, the resolver runs with an empty store and produces exactly today's legacy/structural text. New tests cover the store-present path. |
| Platform tables: Classic 350 and Bullet EFI from service manuals; Honda blink table from Honda service manuals; Bosch `5200H` from a dealer-tool readout (not a manual); Honda `4-2` listed without a meaning | `chassis_dtc_dictionary.dart` | Four honest provenance labels (manual, manual-without-meaning, dealer readout, AI guidance) instead of one. |
| Bosch-platform values are module numbers (`0x5043`); their SAE rendering (`C1043`) is arithmetic, not an SAE code | same | On a raw-hex platform an ABS code never gets a generic (L4) meaning; it resolves to raw value + "show your dealer". On ANY identified ABS platform, the platform's own code space governs: missing → structure/raw, never generic. |
| Two foreground link users can interleave (counted poll lock, not a mutex); the engine job slot (`_engineJob`) is what Clear, ABS and new reads wait for | `obd_service.dart` `_waitForLinkIdle`, `_yieldEngineExtras` | The B9 silent re-read claims the engine job slot, waits for any running read, sends ONE `03` through the Phase 1A pending helper (one attempt window), and touches no rider-visible state. |
| The 5 s auto-scan re-reads continuously | `dtc_screen.dart` | Saving every read literally would flood the 50-session cap in four minutes. Identical consecutive engine reads on one connection are coalesced into the previous session (`repeat_count`, `last_seen_at`); any change or a new connection starts a new session. (The recorder listens from outside the read path, so it cannot tell a manual read from an automatic one; an identical manual re-read is folded in too.) Every ABS scan is its own session. |
| Clear Codes always shows the success snackbar by owner rule | `dtc_screen.dart` `clearOutcomeMessageKey` + 25 tests | The clear record is internal: it is stored, but NOT shown in the History list or in Share (owner decision listed in the report). |

## Store schema (SQLite via sqflite, schema version 1)

Only SQL that works on Android 5 SQLite 3.8: no UPSERT, no `RETURNING`, no JSON1, no FTS, no window functions
(a test scans the SQL sources for these). Lists are JSON text. Times are UTC epoch milliseconds.

- `schema_version(version INTEGER)` — one row; migrations are an ordered list, each run in the open transaction.
- `kb_pack(pack_id PK, version INTEGER, scope, language, source bundled|downloaded|debug, review_state,
  content_sha256, entries_count, min_app_version, imported_at)`
- `kb_entry(content_id PK, code, scope_kind generic|module_family|platform|vehicle, scope_ref, language, title,
  meaning, causes_json, rider_action_level, rider_action_basis, rider_advice, hints_json, flags_json, can_ride,
  can_ride_reason, applies_when_json, confidence, verification, needs_independent_review, source_json, updated_at,
  pack_id, status active|revoked, hi_status none|machine|reviewed)` + indexes `(code, scope_kind, scope_ref,
  language)` and `(language)`. **Hindi = separate language rows** (`generic:P0120:hi`): a Hindi pack fills in with
  no code change; text columns are nullable so a partial Hindi row falls back field by field.
- `kb_revoked(content_id, pack_id)` — revocations survive re-imports of other packs.
- `scan_session(id, kind engine|abs|clear_check, started_at, last_seen_at, repeat_count, profile_id, adapter_class,
  protocol, reach_state, engine_state, voltage_band, lamp_state, clear_outcome, pre_clear_json)`
- `scan_fault(session_id, code, display_code, system, format, raw_hex, failure_type, status_byte, status_json,
  source, module, read_at, resolved_level, resolved_content_id)`

## Pack format v1

`manifest.json`: `pack_id, scope ("generic" | "module_family:<ref>" | "platform:<ref>" | "vehicle:<ref>"),
language, version (int), entries_count, content_sha256 (SHA-256 of the entries file bytes as shipped, gzip or not),
created_at, min_app_version, revoked (content_ids), signature (base64url Ed25519; null for the bundled pack)`.
`entries.jsonl` or `entries.jsonl.gz`. Field names carry the pack language (`title_en`, `title_hi`).
Signed bytes: `danlite-kb-pack-v1` + the manifest fields one per line (revoked sorted). Import = manifest check →
hash → signature (downloaded only; production key is `null` → every downloaded pack rejected) → every line validated
(Dart port of the schema-v2 S/R11 rules + "no manufacturer-defined code in a generic pack" + no content_id owned by
another pack) → ONE transaction: delete the pack's old rows, insert, record revocations, recompute status. Equal or
lower version refused. Any failure: nothing changes.

## Resolver flow (pure Dart, `lib/knowledge/fault_resolver.dart`)

`resolve(FaultRecord, VehicleContext, language, {domain})` → `ResolvedFault`. First level with ANY usable entry wins
(specificity beats language; language is chosen inside the level, field by field, with a note):

1. **L1 vehicle** store entries `scope_ref == vehicle key` (none yet; hook only).
2. **L2 platform** store entries for the platform, then the existing `ChassisDtcDatabase` platform tables (wrapped,
   not moved), ABS/unknown domain only. Bosch-shared table excluded (it is L3).
3. **L3 module family** store entries, then the Bosch shared `5200H` (Bosch platforms only).
4. **L4 generic** store entry — only for standard-defined codes (`isManufacturerDefined` false), SAE formats only,
   not for ABS codes on an identified platform; `applies_when` contradicting a KNOWN vehicle fact skips the entry,
   unknown shows it with a condition note. Then the 31-entry table, then the legacy JSON when `kUseLegacyEngineText`.
5. **L5 structure** — system, subsystem (standard codes), "defined by the manufacturer" (P1xxx…), failure type byte.
   Rendered from existing EN/HI strings; never a part name.
6. **L6 raw** — the raw value (Bosch module value on a raw-hex platform) + "show this to your dealer".

Revoked entries are skipped. Verification labels: AI guidance / service manual / manual-without-meaning / dealer
readout / older app text / structure only / raw only; "Draft: not yet independently reviewed" whenever the entry or
its pack says so.

## Screens

- Fault card: resolved title + meaning, likely causes, what to do, rider-action chip (icon + word), can-ride line,
  condition note, provenance line, "showing English" note. Phase 0/1A labels untouched. CRITICAL chip, sort and card
  colour use the rider action when known (STOP counts as critical), else the old severity.
- Look up a code (from the Fault Codes app bar and the disconnected state): offline search, ≤ 50 results, detail =
  resolver output for the active vehicle (generic only when none is identified).
- Scan history: list, detail, Delete all, Share as text (built only on tap, shared through the existing share
  channel). No VIN, no adapter traffic, no device name.

## Risks and how they are contained

- **Import killed half way** → one transaction; a test copies the database and its journal mid-import and reopens the
  copy (a real crash image): old data intact, nothing partial.
- **Bundled update while a scan saves** → one connection, sqflite serialises transactions; concurrency test.
- **A pack hijacking another pack's entries** → content_id collision rejects the whole pack.
- **Generic meaning on a manufacturer code** → resolver rule + validator rule + importer rule, each tested.
- **Old Android SQLite** → forbidden-syntax scan test.
- **Clock/timezone** → UTC epoch storage; count cap by insertion order (not time); age pruning skipped when the clock
  is behind the newest session; the session just written is never pruned.
- **Time to first screen** → import runs after `runApp`, unawaited; the fault screen shows a loading line until ready.
