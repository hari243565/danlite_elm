# Phase 4A report: final content bundled, scale test, honest-display fixes

Branch `feat/fault-4a` (from `main` @ `a5394dc`, Phase 4B). `main` was not touched. Nothing merged.
Commits: H1 `ea83ced`, H2 `9536b6f`, H3 `f075910`, H4 `c01b10f`, then this report.

## What shipped

| Item | Result | Proving tests |
|---|---|---|
| H1 content | English pack v2 (308 entries, was v1 with 140) and a new Hindi pack v1 (308 rows) are bundled byte for byte from `content/seed-20261001`. Database after a fresh install: **616 rows = 308 English + 308 Hindi**, all active, source `bundled`, review state `draft`, all Hindi rows `hi_status = machine`. | `test/bundled_content_test.dart` (23 tests) |
| H2 scale | 10,000 + 10,000 synthetic rows (test only): import 1.9 s, lookup about 33 ms, word search 35 to 80 ms. | `test/knowledge_scale_test.dart` (8 tests) |
| H3 honest display | ABS bar neutral unless the module answered; "None in scan results"; "Read at {time}" on Engine and ABS cards. | `test/phase4a_honest_display_test.dart` (26 tests) |
| H4 label | "Standard code name only; no further guidance yet" for `standard_title_only`. | `test/phase4a_title_only_label_test.dart` (10 tests) |

Suite: 1006 earlier tests plus 67 new = **1073 pass**. `flutter analyze`: the same 7 known issues. `flutter build apk --debug`: succeeds, and the APK contains both packs (hashes checked).

## Defects found and fixed on the way (all inside H1 to H4)

1. **The new English pack would have been refused whole.** The Dart importer accepted 4 of the 18 `applies_when` conditions the content uses (e.g. `evap_fitted`, `can_bus_fitted`). Fixed: it now accepts the same 18 as the content validator.
2. **A condition the screen had no sentence for was dropped silently**, so the rider saw guidance with its "applies only to…" condition missing. 14 new notes added in English and Hindi, and a test fails if a shipped pack ever uses a condition without one.
3. **The validator threw instead of refusing** on a non-text `hi_status`, `rider_action_level` or `can_ride_to_workshop` (its own comment says it never throws).
4. **Lookup lost half its results** once a code had two languages (the 50-row cap counted rows, not codes).
5. **Start-up import froze the main thread for 815 ms** at 10,000 + 10,000 rows. Now 93 ms (work is sliced).
6. **gunzip stored every byte as a Dart int** (8 bytes of memory per byte). Now a byte buffer; Hindi import 1229 ms to 738 ms.

## H2 measurements (this PC, desktop SQLite; a phone will be slower)

| Measure | Result | Budget |
|---|---|---|
| Import English 10,000 | 741 ms | |
| Import Hindi 10,000 (gzipped) | 738 ms | |
| Import total | about 1.9 s | 15 s |
| Typed-code lookup (mean / worst of 150) | 33 ms / 41 ms | 200 ms |
| Word search, 1 to 2 words, thousands match | 35 to 71 ms | 200 ms |
| Word search with no match | about 80 ms | 200 ms |
| Prefix search | 31 to 38 ms | 200 ms |
| Database size | 36 MB | |
| Load every row into the resolver index | about 380 ms | |
| Longest main-thread stall during start-up import | 93 ms (was 815 ms) | 250 ms |
| 50,000 compact rows (48 MB decoded) | imported, 2.4 s | no crash |
| 50,000 real-size rows (68 MB decoded) | refused cleanly in 0.13 s, database unchanged | no crash |

Pack limits are unchanged and still protect the phone: 20 MB as shipped, 50 MB decoded. 10,000 real-size Hindi rows are 20.8 MB raw, so a pack that size must be gzipped.

## What would be deleted later (not now: the basic tier that replaces its coverage is not bundled yet)

- `kUseLegacyEngineText` and `legacyEngineTextAllowed` in `lib/constants/build_flags.dart`, and `test/store_build_guard_test.dart`.
- The borrowed text: `assets/dtc_translations.json` (and its `pubspec.yaml` line), `DtcLocalizations` loading in `lib/services/dtc_service.dart`, the corrupted `lib/constants/dtc_dictionary_hi.dart`.
- `lib/knowledge/legacy_text.dart` JSON branches, `useImportedLegacyText` in `lib/knowledge/fault_resolver.dart`, `Provenance.legacyImported` with its string `provenanceLegacyImported` and the branches in `dtc_screen.dart` and `code_lookup_screen.dart`, and the test at `fault_text_resolution_test.dart:208`.
- Kept by Phase 0 decision: the 31-entry `DtcDatabase`.

## Found but not fixed (outside H1 to H4)

1. **C0035 is gone from the English pack on purpose** (the content owner holds it out). A rider on an unidentified bike who reads C0035 now sees the code's structure only, not wheel-speed text. Four old tests used C0035 as the example generic ABS code; they now use C0020.
2. **104 of the 308 entries carry a condition the app can never decide** (it does not know whether a bike has EVAP, a CAN bus, a knock sensor…). They show "Applies only to bikes with…" every time. Honest, but noisy. The bike profile would need those facts to settle it.
3. **The Hindi is machine-translated and unread by a person.** The card says "written with AI assistance" and "Draft", but nothing says the Hindi itself is machine-translated. `hi_status` is stored but not shown.
4. **Scan history re-resolves with today's content**, so after a content upgrade an old scan can show different guidance than it did when it was read. The stored code, time and level are untouched.
5. **Lookup in Hindi** with English words matches English rows only, so the result title is English.
6. **The resolver index loads every language into memory** (about 380 ms and tens of MB at 20,000 rows; trivial at 616). It could load only the asked language.
7. The ABS bar shows plain "No reply" and not the adapter-limited hint (that stays in the panel below).
8. From earlier phases, still open: the debug-only clear snackbar bug; `GeneratedPluginRegistrant.m` is modified and unstaged.

## Owner decisions

1. Should Hindi cards say the Hindi is machine-translated until a person has read it?
2. C0035: accept structure-only for unidentified bikes, or restore a neutral wheel-speed entry?
3. Add the missing bike facts (EVAP, CAN bus, knock sensor…) to the profile, or reword those conditions as plain notes?
4. The next content (`standard_title_only`) has only a name. The importer still requires meaning, causes and advice in every English line. Tell me whether title-only lines should be allowed to omit them (validator change in the next phase).
