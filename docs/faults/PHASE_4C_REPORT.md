# Phase 4C report: name-only entries in the app, borrowed text retired, honest Hindi label

Branch `feat/fault-4c` (from `main` @ `0d75789`, Phase 4A). `main` was not touched and nothing was merged.
Commits: K1 `85264f8`, K2 `9545c3f`, K3 `d6f0248`, K4 `0a16da5`, K5 `7bc8134`, then this report.
`ios/Runner/GeneratedPluginRegistrant.m` is still modified and was never staged.

## What was done

| Item | In plain words | Proving tests |
|---|---|---|
| K1 | The importer now accepts a "name only" line (verification exactly `standard_title_only`). Only those lines may leave out causes, hints, can-ride and flags. They must be INFO, confidence low, and have a title, a meaning and the advice sentence. A name-only line that carries causes, hints, a can-ride answer, a set flag, another level or another confidence is refused, and so is the whole pack. Every other line keeps the old rules exactly. | `phase4c_name_only_validator_test.dart` (45): good lines, normal lines still refused, 30 ways to over-claim, all-or-nothing packs, 2,000 random mutations that never crash |
| K2 | The 7,672 English and 7,672 Hindi name-only entries are in the app (4 packs now). A fresh install imports all four; a phone already at the 4A state gets only the two new packs and its 616 guidance rows and its history stay byte for byte the same. No code or content id is in both the 308 and the name-only content. Real guidance always beats a bare name. | `phase4c_bundled_basic_test.dart` (25) with the real files |
| K3 | The borrowed engine text is deleted. 244 standard codes lose their old title (listed below). Any code with no content now shows its structure, its raw code and "show it to your dealer". | `phase4c_legacy_retirement_test.dart` (16), plus a `git grep` proof |
| K4 | A card that shows Hindi from a machine-translated row has one extra line under the draft line. Not on English, not when it falls back to English, not on structure-only answers, not on the app's own screens. | `phase4c_hindi_label_test.dart` (21) |
| K5 | The 14 conditions the app cannot decide now read "May not apply to your bike. Applies only to bikes with ..." (Hindi too). Cylinders, liquid-cooled, ride-by-wire and ABS are unchanged. | `phase4c_condition_notes_test.dart` (26) |
| K6 | Below. | whole suite |

## K2 measurements (this PC; 3 runs, desktop SQLite; a phone will be slower)

| Measure | Result | Budget |
|---|---|---|
| First start, all 4 packs (open, import 15,960 rows, build the index) | 1.36 to 1.45 s | 15 s |
| Longest stretch the screen was frozen during it | 64 to 75 ms | 250 ms |
| Rebuilding the in-memory index from the database | about 250 ms | |
| Database size | 16.6 MB (was 0.9 MB at 616 rows) | |
| Pack files in the app (raw) | English guidance 464 KB, Hindi guidance 708 KB, name-only English 9.08 MB, name-only Hindi 9.96 MB | each under the 20 MB cap |
| What they add to the APK (stored, compressed) | name-only English 686 KB, Hindi 327 KB | |

No tuning was needed, so none was done. Each pack stays under the 20 MB as-shipped and 50 MB decoded limits.

## K3 coverage change, in numbers

Before the text was deleted, the codes the borrowed text explained for an unidentified bike:

| | Codes |
|---|---:|
| In the borrowed JSON | 1,709 per language: 1,273 standard codes and 436 manufacturer-defined `P1xxx` |
| In the 31-entry table (kept) | 31 (27 also in the JSON; 4 only here) |
| Standard codes the old text explained | 1,277 |
| of which now covered by the 308 shipped entries | 250 |
| of which now covered by the name-only packs | 780 |
| of which in neither, but kept by the 31-entry table (`C0035`, `P0400`, `P0700`) | 3 |
| **of which in neither and now structure + raw code + dealer line** | **244** |

Correction to the brief's expectation: the 436 manufacturer `P1xxx` codes were **never shown** (the Phase 0 rule stops them), so deleting them changes nothing for a rider. The real loss is 244 standard codes that the content owner held out of the name-only tier. Reasons: 191 the two title sources disagree, 25 they agree but not on the same words, 16 title over the 70-character limit, 12 held out by hand. The list, codes and reasons only (no borrowed titles copied), is `docs/faults/PHASE_4C_K3_CODES_LOST.csv`.

Gained: the content now covers 7,980 standard codes, 6,950 more than the old text did.

What a rider sees for a code in none of the content (for example `P0134`): the code itself, "Powertrain" and its subsystem, the line "No meaning is known for this code. Show it to your dealer or workshop." (this existing sentence now also covers standard codes; before it said only "No verified description yet."), and the label "Structure only, no verified meaning". No title, cause, advice, can-ride line or chip.

### What was deleted (proved with `git grep`)

`kUseLegacyEngineText` and `legacyEngineTextAllowed`; `lib/constants/build_flags.dart` (nothing else used `STORE_BUILD`, so the file went entirely); `test/store_build_guard_test.dart`; `assets/dtc_translations.json` and its `pubspec.yaml` line; `lib/constants/dtc_dictionary_hi.dart`; the JSON loading, `description()` and `parseRawDictionary` in `dtc_service.dart` and the call in `main.dart`; the imported-text branch of the resolver; `Provenance.legacyImported`, its two strings and its screen branches. The 31-entry `DtcDatabase` and the Hindi text of the ABS tables are kept.

`git grep` for every deleted name over the whole repository finds nothing in code or tests. Two leftovers, both history and not code: the older documents `PHASE1B_PLAN.md` and `PHASE_4A_REPORT.md` describe the old design, and `.claude/settings.local.json` holds one old recorded shell command that mentions `DtcLocalizations.init`. I left them.

How the store-build guard was simplified safely: it existed only to keep the borrowed text out of store builds. With the text gone there is nothing left to switch off, so `--dart-define=STORE_BUILD=true` is now a harmless no-op. The protection is now a test that fails if the asset, the dictionary, the flag file or any name that referred to them comes back.

## K6 results

- Whole suite: **1,195 pass, 0 fail** (1,073 before). New: 133. Removed: 12, each with its reason (below).
- `flutter analyze`: the same 7 known issues, nothing new.
- `flutter build apk --debug`: succeeds. The APK holds all four packs (SHA-256 of each matches its manifest) and no `dtc_translations`.
- `main` is `0d75789`, the same as at the start, locally and on `origin`.
- Packs: `.gitattributes` still stops line-ending rewriting (`-text`); git stores the four new files with LF; the production download key is still unset.

### Tests removed (12)

`store_build_guard_test.dart` (2: tested the deleted switch). In `fault_text_resolution_test.dart` (10: they read the deleted JSON or dictionary or the switch): the 436-P1 asset test, "standard P0 resolves exactly as before", switch on, store build never on, every dictionary code has clean JSON Hindi, the corruption detectors, no corrupted token returned, Hindi with the switch on, Hindi falls back to English (re-tested on the resolver in `phase4c_legacy_retirement_test`), and the stale "999 entries" comment test. Two more in that file were rewritten, not removed: the manufacturer-code card test (no longer quotes the asset) and the unknown-code card test (now also checks the dealer line); the subsystem-name checks that sat inside "switch off" became their own test. In `chassis_dtc_test.dart` one assertion that called the deleted `description()`. In `fault_resolver_test.dart` "imported legacy text only while the switch is on" became "a standard code in neither the store nor the table is structure only".

### Older tests that had to change (counts and one rule)

- Tests that hard-coded the 616-row total now use the real total (15,960): `bundled_content_test`, `scan_history_test`, `phase1b_screens_test`. The upgrade test now expects four imports.
- `phase4a_title_only_label_test`: the "less-claiming label wins if either row says title only" rule is replaced by the 4C rule (real guidance beats a bare name; the label is title-only only when every row is). The card tests moved from `P0120` to `P0121` because `P0120` is in the 31-entry table, which now rightly beats a bare name, and use a valid name-only line.
- `phase1b_screens_test` "a standard code nobody describes" moved from `P0017` (now has a name) to `P0134`.

## Every new or changed string

New:
- `faultHindiMachine`, English: "Hindi is machine-translated and has not been checked by a person."
- `faultHindiMachine`, Hindi: "यह हिंदी मशीन से अनुवादित है और अभी किसी व्यक्ति ने इसे जाँचा नहीं है।"

Changed (14 keys x 2 languages): each of `appliesKnockSensor`, `appliesCamshaftSensor`, `appliesOilTempSensor`, `appliesClosedThrottleSwitch`, `appliesEvap`, `appliesSecondaryAir`, `appliesCoolingFan`, `appliesOilPressureSensor`, `appliesAmbientTempSensor`, `appliesFuelLevelSensor`, `appliesGearPositionSensor`, `appliesClutchSwitch`, `appliesDownstreamO2`, `appliesCanBus` now starts with "May not apply to your bike. " / "आपकी बाइक पर लागू न भी हो सकता है। " and then the old sentence ("Applies only to bikes with <X>." / "यह सिर्फ़ <X> वाली बाइक पर लागू होता है।"). Example: "May not apply to your bike. Applies only to bikes with an EVAP (fuel vapour) system."

Removed: `provenanceLegacyImported` (English and Hindi).

Reused, not new: `faultRawShowDealer` now also appears for a standard code with no content.

## Found, not fixed, or worth knowing

1. **A bare name is labelled "Info".** 459 name-only titles mention things like fuel pressure, brakes or misfire, and the card shows the calm "Info" chip with "have it checked soon". That is the content owner's design and the 4A label says "name only", but a rider could read "Info" as "harmless". See decision 2.
2. **The card repeats itself:** the title and then "Standard name: <same title>." on the next line.
3. **The 31-entry table beats a name-only entry** (5 codes, English only). A Hindi rider sees that table's English title and the "showing English" note instead of the Hindi name. Intended for now (the table has a cause and an action).
4. **Pack version.** The brief asked for versions "higher than any earlier one". Versions are compared per pack id, so the two new packs are v1, as the content branch built them; raising them would also stop a later content v2 of the same packs from ever installing. If you want a different number, it is a one-line change in each manifest (the entries hash does not cover the manifest).
5. **Phone timing is unmeasured.** 1.4 s on this PC; a low-end phone may be several times slower. Well inside 15 s even at 5x, but worth one look on the real handset or emulator before a release.
6. **Memory:** the resolver keeps all 15,960 rows (both languages) in memory. Fine today (about 250 ms to build); loading only the asked language is possible later (open item 6 of the 4A report).
7. **Conditions the profile "can decide":** in practice the vehicle profile carries none of cylinders, ABS, liquid-cooled or ride-by-wire yet, so those notes still show every time, with today's plain wording.
8. Still open from earlier phases: Hindi lookup with English words matches English rows only; the debug-only clear-codes snackbar bug; scan history re-resolves with today's content.

## What the owner must decide

1. **The 244 lost codes.** Accept "ask your dealer" for them, or ask the content session to add the 25 "words differ" and 16 "title too long" ones (they are likely safe) and decide on the 191 where the sources disagree. List: `docs/faults/PHASE_4C_K3_CODES_LOST.csv`.
2. **The Info chip on a bare name.** Keep it, or show a neutral "Name only" chip with no rider-action colour for these entries.
3. **Title and "Standard name: ..." repeated.** Hide the second line on name-only cards?
4. **Table vs Hindi name** (item 3 above): keep the English table for those 5 codes, or let the Hindi name win?
5. **Pack versions** (item 4): keep v1 or set a higher number.
6. Whether to merge `feat/fault-4c` (K1 to K5) now, and whether the next content round should be reviewed Hindi (which would switch the new line off by marking rows `reviewed`).
