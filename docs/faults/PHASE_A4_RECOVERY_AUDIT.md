# Phase A-4 recovery audit

Date: 2026-10-02. Worktree `danlite_elm_a4`, branch `feat/fault-a4`, commit `08f2d92` (already pushed to `origin`).
Auditor: the recovery session. Every "proven" below was demonstrated by a command run in THIS session, not taken from
a commit message, a plan or the earlier session's notes.

## What the interrupted session left behind

It had in fact **finished**. Everything was committed as `08f2d92` and pushed before the terminal closed; the working
tree was clean, so no "WIP" commit was needed. Nothing was half-written. A safety copy of the folder was still taken
(`..\danlite_elm_a4_safety_20261002-2214`, 103 files in `lib\`, 64 in `test\`).

## Debris check

| Check | Result |
|---|---|
| Git lock file in the worktree's git folder | none |
| Running `git` process | none |
| `dart` / `flutter` processes | 4 `dart` processes: VS Code's language server, the tooling daemon, the Flutter daemon, DevTools. All started minutes before this audit, so they are the owner's reopened editor, not stale. **Left running.** |
| `.env` for tests | present, git-ignored |
| Generated `ios/Runner/GeneratedPluginRegistrant.*` | every `flutter` command rewrites these with line-ending noise. Restored with `git restore` on those two files after each run; not committed |

## Baseline, run in this session

| Command | Result |
|---|---|
| `flutter pub get` | OK; `pubspec.yaml` and `pubspec.lock` unchanged |
| `flutter test` (whole suite) | **774 passed, 0 failed** (567 earlier + 207 new), exit 0 |
| A-4 test files alone | 223 passed |
| `flutter analyze` | **7 issues, the same known 7** (`dashboard_screen`, `fuel_screen`, `hud_screen` x3, `realtime_screen`); none new |
| `dart format --output=none` on the 23 changed Dart files | no syntax errors. It reports style differences only, which is normal here: the repo is not `dart format`-clean (untouched-style files differ too) |
| `flutter build apk --debug` | built OK. The APK's compiled code contains `readEngineContext`, `decodeReadinessBytes`, `snapShortTrim`, `historyClearAfterUnknown`, `contextReadBudget` |
| Unfinished-work search (`TODO`, `FIXME`, `UnimplementedError`, `skip:`, empty files) | none. Three false hits (`faultWhatToDo`, a comment containing "xxx") |

## Scope audit (`git diff --name-only main...HEAD`, 35 files)

All 35 are inside the allowed scope: 2 docs, 10 `lib` files (strings, knowledge/history, the fault screens, the
engine-context service and widget), 23 tests/fixtures.

| Must be unchanged versus `main` | Result |
|---|---|
| `pubspec.yaml`, `pubspec.lock`, `android\`, `ios\` | untouched |
| auth, payments, backend, portal, admin, supabase | untouched |
| `clearDtcs()` body | **no changed line inside it**, checked by line range against `main`. One supporting change sits next to it: `_lastClearOutcome` became a property whose setter also bumps a counter, so a snapshot read before a clear is never shown after it. `clearDtcs` itself is not edited. |
| Clear Codes wording/timing | unchanged except S3. The only difference is the one line below |
| ABS probe, order, addresses, sweep, recovery | no change to any ABS code. 14 ABS **Hindi display strings** changed, spelling only (S1) |
| K-line gate flag | not touched; the new job checks it and says "not read" on a K-line bike (test: "the K-line bus is not read and says why") |
| Other languages | only `noFreezeData` removed from 9 languages (the dead text, see C1) |

**Earlier tests that were touched (reported, as required):** `test/phase1b_screens_test.dart` was *narrowed* in one place.
That test pins the Clear Codes functions byte-for-byte to `main`; it now allows exactly one difference, the S3 line
(`context.tr(...)` becomes `AppStrings.get(..., context.read<SettingsProvider>()...)`), and still demands every other
byte equal. `test/replay_fixtures_test.dart`, `codes_present.txt` and the replay README only gained lines. No earlier
test was deleted, skipped or loosened elsewhere.

## Item table

| Item | State | Proof run in this session |
|---|---|---|
| **C1** freeze frame (Mode 02) | **DONE-AND-PROVEN** | `lib/services/engine_context.dart` (`decodeFreezeFrameTrigger`, `FreezeFrameResult` family), `lib/services/obd_service.dart` (`readEngineContext`), UI in `lib/widgets/engine_context_view.dart` + `dtc_screen.dart`. Tests: `engine_context_decoders_test` "0000 means there is NO snapshot — not a code called P0000", `engine_context_service_test` "silence is NoAnswer — never 'no snapshot', never 'unsupported'", `engine_context_screens_test` "a silent bike: honest words, never the old 'No Freeze Data'" (en and hi) and "the old 'No Freeze Data Available' text is gone from every language". The text no longer exists anywhere in `lib\`. PID 02 is requested first (`020200`). All 223 pass |
| **C2** counters 21, 31, 4D, 4E, 30 | **DONE-AND-PROVEN** | formulas read in `engine_context.dart` (256A+B, and A for 30); `engine_context_decoders_test` "C2 counters" vectors 0, 1, 255, 256, 65534, 65535 for each of the four two-byte counters and 0, 1, 254, 255 for warm-ups; service test "the maximum is 'at least'"; screen test "[hi] the maximum reads 'कम से कम 65,535'". Lamp lines are hidden at 0 or when the lamp is known off (a "lamp on for 0 km" would be untrue) |
| **C3** readiness decode | **DONE-AND-PROVEN, with one owner flag** | pure `decodeReadinessBytes` with vectors (`41 01 83 07 E5 00`, all-complete, none-supported, bit-by-bit B/C/D, compression ignition = not applicable). **Flag:** the brief says "extend the existing Readiness screen", but no such screen exists in `main` (the keys `readiness`/`emissionReadiness` were unused). It is a new section of the Freeze Frame sheet instead |
| **C4** tests | **DONE-AND-PROVEN** | simulator `test/support/context_sim.dart` + `context_harness.dart` (a separate simulator beside the existing one, not an edit of it); 8 new replay fixtures (full snapshot, Mode 02 unsupported, no snapshot, partial support, 29-bit CAN, response pending, silent, refused) all pass in `replay_fixtures_test`; `engine_context_fuzz_test` "10,000+ mutated, random-hex and random-text replies: typed results, no throw" (it found a real bug, fixed); `a4_scenarios_test` scenarios 3, 13, 14 (11 tests); `docs/faults/PHASE_A4_SCENARIOS.md` exists |
| **S1** Hindi consistency | **DONE-AND-PROVEN, with two flags** | counted in the Hindi block (lines 988-1782): `अडैप्टर` 0, `एडाप्टर` 0, `फॉल्ट` 0; `faultCodes` = `फ़ॉल्ट कोड`; both provenance strings read `के सर्विस मैनुअल`; all 24 changed Hindi strings checked against `main`: 21 are pure spelling swaps, 3 are the exact ones the brief names. `hindi_consistency_test` (7 tests). See flags F1, F2 |
| **S2** Clear record in History detail only | **DONE-AND-PROVEN** | wording verbatim (EN and HI) in `app_strings.dart`; shown by `clearRecordSentence` in `scan_history_screen.dart` only (grep: no use in the Clear Codes screen); `a4_clear_record_history_test` (7 tests) |
| **S3** debug-mode assertion | **DONE-AND-PROVEN** | one line in `dtc_screen.dart` (`context.read` instead of the listening `context.tr`). Mutation check: with the old line put back, `clear_codes_debug_message_test` FAILS on Flutter's `debugBuilding` assertion; with the fix it passes (3 tests). File restored afterwards. The Phase 1B guard confirms nothing else in the Clear flow changed |
| **S4** string parity | **DONE-AND-PROVEN** | parsed both blocks independently: 574 keys in `en`, 574 in `hi`, zero missing either way; 49 new keys, each in both; `a4_strings_test` pins the owner's own wording verbatim and checks `{n}`/`{time}`/`{code}` placeholders match |
| **S5** no regressions | **DONE-AND-PROVEN** | full suite 774/774, analyze same 7, debug APK built |
| `PHASE_A4_PLAN.md` matches | **MOSTLY**, four small differences below | exists; design and risks match the build |

### As built, versus the plan (docs only, nothing to fix)

1. The plan says the order is lamp bytes → counters → snapshot. As built: snapshot first, then the lamp bytes and counters.
2. The plan says `readEngineContext({parts, isCancelled})`. As built: `({force, isCancelled})`; there is no `parts`.
3. The plan lists a separate `decodeFuelSystemStatus`. As built: fuel-system status is decoded inside `decodeFreezeFrameValue`.
4. The plan says a silent bike ends a group on its first silent request. As built: two silences in a row end the read
   (test: "a silent bike costs two windows, not the whole list").

## Flags and findings for the owner (nothing here was changed)

- **F1.** Three Hindi strings still say `दोष कोड` while the tab now says `फ़ॉल्ट कोड`: `faultCodesDtc`, `noFaultCodes`,
  `clearAllQ`. `clearAllQ` is the Clear Codes confirmation dialog, whose wording this phase must not change, so all three
  were left. Decision: change them in a later wording pass?
- **F2.** 16 occurrences of `एडाप्टर` remain in **other** languages' blocks (not Hindi). The brief limited S1 to Hindi.
- **F3.** No Readiness screen existed (see C3).
- **F4.** Owner's folder: `git status` shows only `ios/Runner/GeneratedPluginRegistrant.m` modified, as it was before the
  phase began. `main` is still `d607f8b`. The plan recorded a SHA-256 of that diff; this session computed a hash by a
  different method, so the two cannot be compared. The file list and `main`'s commit are the evidence.
- **F5.** All proof is by simulator, fixtures and tests. Nothing was run on a real bike, as agreed.

## What remains

Nothing in C1-C4 or S1-S5. Not merged, by instruction. Open for the owner: F1, F3, whether to merge, and the real-bike
check at the end of the project (J1979 byte layouts are marked in code comments as to be re-checked against the standard).
