# Batch 1 report: pilot fixes and 100 new entries

Run: RUN_MODE = write, RUN_SCOPE = fix-pilot + batch 1. Date: 2026-10-01. Branch: `content/seed-20261001`.
Source: OBDex commit `bc58b0eb7273226a1aabae98e956b70b8362bda1` (CC0-1.0 data). Mode: **structure-only** (unchanged; the quality gate was not re-run).
Nothing outside `data/content/` and `docs/content/` was changed. `main` was not touched. Batches 2 to 4 were not started.

## 1. What exists now

| Item | Result |
|---|---|
| Entries in `generic_en_seed.jsonl` | **140** (40 pilot, rewritten to schema version 2, plus 100 new in batch 1) |
| Codes selected | 387 (365 writable; 22 held back for suspect titles) |
| Remaining writable codes for batches 2 to 4 | 225 |

| | Pilot (40) | Batch 1 (100) | Total (140) |
|---|---:|---:|---:|
| powertrain / network / chassis | 36 / 3 / 1 | 92 / 8 / 0 | 128 / 11 / 1 |
| STOP | 6 | 22 | 28 |
| SERVICE_SOON | 29 | 69 | 98 |
| MONITOR | 5 | 9 | 14 |
| can_ride_to_workshop: no / with_care / yes | 6 / 25 / 9 | 22 / 63 / 15 | 28 / 88 / 24 |
| confidence: high / medium / low | 31 / 7 / 2 | 25 / 60 / 15 | 56 / 67 / 17 |
| needs_independent_review true | 14 | 38 | 52 |
| applies_when set | 3 (cylinders_min 2) | 5 (4 cylinders_min 2, 1 liquid_cooled) | 8 |

Batch 1 covers ranks 41 to 141 of the re-ranked list (P0121 to U0008; P0134 skipped because its title is on the suspect list): throttle, MAP, intake air, engine and oil temperature (including the warm-up and overheating codes), upstream O2 sensor and heater, fuel trim, injector circuits and balance, fuel pump circuits, crankshaft and camshaft position, ignition coil, knock, vehicle speed, neutral switch, idle control, system voltage, starter relay, ECU power relay, sensor supply, ECU internal faults, immobiliser and starter request, and CAN bus wires U0001 to U0008.

**One thing to look at first: 22 of the 100 new entries are STOP.** The rubric forces STOP for every injector, ignition coil and crankshaft circuit code and allows it for fuel pump and ECU power codes, and the author chose STOP for all fuel pump circuit codes, two ECU power relay codes and three ECU internal faults. That is conservative on sudden power loss, as the brief asks, but too many STOPs can wear out a rider's attention. The independent review should test the calls listed in section 5.

## 2. Phase A: the 40 pilot entries

Every CONCERN and FAIL in the reviewer's `review_flags_20261001.csv` is fixed and logged in `data/content/fix_log_20261001.csv` (44 rows: what changed and why). Highlights:

- **Circular "stop if it stalls" advice** (P0120, P0340, P0600, U0100): replaced by "if it stalls more than once or will not restart, do not keep riding; have it taken to a workshop". P0122 and P0123 now carry the same stall warning as P0120.
- **Gauge and blinking-lamp advice** (P0115, P0117, P0118, P0300 to P0302): removed. P0117's basis is now "hard cold start, stumbles until warm"; P0118 says to stop and let the engine cool if it runs very hot.
- **Fuel smell** (P0172, P0132): the strong-petrol-smell stop sentence is added and the entries are on review.
- **Unsupported parts removed:** idle control (P0500), neutral lamp (P0850), scan tool (U0100), temperature gauge (P0115). Hardware hedges added: "(if hose-fed)" P0105, "(if fitted)" P0135 and P0230. P0340 timing chain dropped. P0335 "toothed ring on the crankshaft (reluctor ring)". P0420 names a modified, damaged or removed exhaust or converter first.
- **Plain first:** P0122, P0123, P0107, P0108, P0131, P0132 start with a plain sentence before any workshop phrase. P0500 title is "Vehicle speed sensor A: fault".
- **Owner decisions:** D1 (P0563, firm stop triggers), D2 (U0100, two honest cases, no scan tool, `with_care`), D3 (U0121 and C0035 carry the plain ABS sentence; C0035 title "Wheel speed sensor fault (front or rear wheel)"), D4 (`can_ride_to_workshop` on every entry; the reviewer's proposals adopted except U0100, where D2 wins), D5 (`applies_when` on P0202, P0302, P0352), D6 (`verification` is `ai_authored_from_standard_title`; the word "verified" is rejected everywhere).
- All 40 migrated to schema version 2 and rebuilt from `authored_pilot.py`.

## 3. Titles

- `title_overrides.csv` holds exactly the eight owner-checked titles (P0139, P0626, P0686, P0687, P0688, U0075, U0076, U0077) and they are applied. The selection script now covers P0685 to P0690 (and so P068A and P068B), and the ranking was re-run (387 codes).
- A duplicate-title scan over the selected codes, plus hand checks against neighbouring codes, produced 22 held-back codes (listed with reasons in `title_suspects.csv` and in SELECTION_RULES.md): P0134, P0140, P0141, P2110, P2230, U0167, U0168, P033F and the wheel-speed titles C0030 to C0034, C0036, C0037, C0038 and C003A to C003F. **No entry was written for any of them.**
- **A mismatch the owner should know about:** for P0687 and P0688 the OBDex entry text (components, causes, description) describes the failure the OBDex title said, not the checked title. For example the P0688 source text is about a sense circuit shorted high, while the checked title is "Sense Circuit/Open". Entries follow the checked title and record `derived_from.title_basis = "override"`. The sha256 still points to the OBDex entry, so the mismatch is visible to anyone who looks.
- U0075 to U0077 are not in this batch (tier 4). When written they will be plain single-bus entries with low confidence; the validator already enforces that for them.

## 4. Validator and mutation test results

- `validate_seed.py` on all 140 entries: **0 errors, 1 warning** (P0563: "battery" appears only in the source description; kept on purpose, it is the point of D1).
- The first run on the new batch gave 52 errors, mostly from the old part-name check (parts named that the source entry does not list: spark plug, injector, relay, battery, exhaust, toothed ring) and from advice longer than two sentences. All were fixed in the text, not by loosening the rule.
- `validator_selftest.py`: **56 of 56 tests pass**: baseline (all 140 unmodified entries clean); the **4 reviewer-written defective entries kept as permanent regression cases** (`review_regression_cases.json`: wrong direction, ABS reassurance, EGR cause, level contradicting text); the **mutation test** (10 good entries each broken a different way the reviewer found, rules R1 to R10, all 10 rejected for the named rule); and 41 further cases covering R1 to R11, owner decisions D1 to D6 and 18 legacy and schema checks. A test passes only if the expected rule id appears in an error for that code.
- The brief mentions "the reviewer's four defective entries and three blind-spot examples". The review report has three blind-spot defects plus one "bonus" defect, which is four examples; all four are in the regression file and the three blind spots (direction, ABS advice, car-only part) are also covered by mutation cases. If a separate set of three was meant, it was not in the review branch.
- **A clean validator run is still not proof of safety.** The checks are patterns; they cannot tell whether STOP is the right level for a code, whether a cause is realistic on a given bike, or whether the Hindi will be understood. That is why the second pass and an independent review follow.

## 5. Second pass (sceptical mechanic) and what it found

A random sample of 30 of the 100 entries (`random.seed(20261002)`, listed in `second_pass_batch1_sample.csv`) was re-read against its OBDex source entry. Results are in `seed_review_log.csv` (12 new rows).

- **8 of the 30 had a problem (27%)**; 5 were fixed, 3 stay open or accepted. Fixed: an invented detail in P0501 ("from the engine"); a part name inconsistent with the rest (P0511); wrong-direction advice (P0616 told the rider about a starter that keeps running, which belongs to P0617, the HIGH code); a confusing phrase (P0133); a high-idle code that told the rider about stalling (P0507).
- Open or accepted: **P0688** (source text describes a different failure from the checked title, section 3); **P0605 and P0606** (STOP for an ECU internal fault may be too strong, the ECU can run for a long time after storing the code); P0324 (the source text is unusable, nothing was taken from it).
- Five more problems were found outside the sample when re-reading the batch and fixed: the P0170 title was workshop language, the P0263 and P0266 titles said "weaker" where the source says less or more than average, the CAN entries did not hint that safety systems can be affected, and P0687 and P068B mentioned a flat battery that the source does not support.
- Most problems were wording slips a pattern check cannot see. This pass was done by the same author as the entries. **An independent review is still needed** and should concentrate on the calls below.

**Where the independent reviewer should look (my least certain calls):**
1. STOP versus SERVICE_SOON for the ECU internal faults P0604, P0605, P0606 (STOP) against P0601, P0602, P0603, P0607 (SERVICE_SOON).
2. STOP for the intermittent codes P0233 and P0339.
3. The two-case advice used where the ECU or the data link may be at fault (P0687 to P0690, P068A, P068B, U0001 to U0008). It is honest but vague; does it help a rider?
4. P0561 (unstable system voltage) and P0641 to P0643 (sensor supply), SERVICE_SOON with a stop trigger. The brief says be conservative on sudden power loss.
5. Knock codes P0324 to P0329 (low or medium confidence): many Indian bikes have no knock sensor at all.
6. The idle codes' `can_ride` of `with_care` and the starter relay wording.
7. `mil`, `emissions_relevant` and `limp_possible`: written by judgement in structure-only mode; nobody has checked them.

Suggested sample for the independent review: all 22 STOP entries, the 15 low-confidence entries, the 4 entries with a stop trigger in a SERVICE_SOON level (P0561, P0641 to P0643), plus 15 random others.

## 6. Effort used

- Tokens: about **0.4 million** for this whole run (15.0 million at the start, about 14.6 million at the end). Roughly 0.1 million was reading (the brief, the review report, the pilot code and files); about 0.14 million for Phase A and B (rewriting the 40 entries, the new validator, the 56 tests, the fix log); about 0.15 million for batch 1 (writing 100 entries, fixing validator findings, the second pass); the rest for documents and the report.
- Wall time: about 1 hour.
- **Estimate per 100 entries: about 150,000 to 200,000 tokens**, the same as the pilot estimate. Batch 1 writing was cheap because most families come in low/high/intermittent groups, but the part-name rule forced many rewrites. Chassis (C0), network and wheel-speed batches should cost more because each needs the ABS sentence and review wording, so budget about 200,000 per 100 for batches 2 to 4 (225 writable codes: roughly 0.4 to 0.5 million).

## 7. Additions beyond the brief

1. **`standard_title_en`** (the standard title in force, override applied) and **`derived_from.title_basis`** (obdex or override). The app can search by the standard title, a technician sees what the code is called in the tool, and the validator can check the direction (low or high) from it instead of from the rider's wording.
2. **`applies_when` can say more than `cylinders_min`**: it also allows `liquid_cooled`, `ride_by_wire` and `abs_fitted` (only `cylinders_min` and `liquid_cooled` are used so far). P0128 (thermostat) would otherwise show on air-cooled bikes. The validator also forces `cylinders_min: 2` for any code whose standard title names cylinder 2, ignition coil B or a contribution/balance fault.
3. **Selection:** ranking by how likely a small bike is to raise the code (ride-by-wire last), two new tags (`injector_balance`, `ect_warmup`) so the rubric does not over- or under-warn, a `write_ok` column, and a duplicate-title scan inside the selection script with a hand-checked suspect list. The ranking file also carries `title_standard` and `title_status`.
4. **Validator:** rules R1 to R11; the R3 and R1 rules also read `can_ride_reason`; checks for owner decisions D1 to D6 on named codes so they cannot be undone by accident; a `verified` word ban; a review-flag rule that also covers ABS and petrol-smell entries; a tighter neutral-switch part check; more part patterns (fan, knock sensor, oil pressure sensor, secondary air, starter parts); the validator prints the OBDex commit it validated against; `OBDEX_DIR` environment variable; and an in-process API so tests run in seconds.
5. **Tests as a product:** `validator_selftest.py` is now a regression suite (baseline, reviewer cases, mutation test, rule coverage). Run it after every validator change.
6. **Glossary:** fixed sentences (the stall sentence, the two-case sentence, the petrol and ABS sentences) are listed once so the Hindi pass translates each exactly once.
7. **Source mismatch notes** (P0687, P0688) and the observation that the OBDex text for P0324 is unusable support keeping structure-only mode.

**Fields and table changes proposed, not done (they need the owner):**
- Add to the app's failure-type table: "circuit fault (type not specified)", "intermittent circuit fault", "slow response", "signal stuck lean / rich", "efficiency below threshold". Many titles use these (17 of the 40 pilot titles by the reviewer's count, and most of the intermittent, slow-response and stuck codes in batch 1); without table entries the Hindi pass will invent its own.
- A `failure_type` enum, `related_codes` and a `root_cause_group` (for example all sensor supply faults, ECU power, CAN) so the app can show several codes as one problem; `clear_conditions` and `reviewed_by`, `reviewed_at`, `review_status` per entry.
- A mechanic or maker table for the flags and for the ABS and wheel-speed entries (which wheel).

## 8. Risks noticed

- **STOP inflation** (section 1) and, in the other direction, SERVICE_SOON for the ECU data-link and sensor-supply codes. Both depend on judgement that no checker can confirm.
- **Hardware hedges ("if fitted", "if hose-fed")** appear in 13 of the 100 entries. They are honest but make the text longer for translation and more hesitant for the rider. The app should use `applies_when` to hide parts a bike does not have, instead of hedging in text, once there is bike-family data.
- **Knock, EVAP, secondary air and starter request codes** depend on hardware many Indian bikes lack; confidence is medium or low and they should be shown only when the bike supports them.
- **Single author.** The quality gate (60 codes), both second passes and the flags are by the same author. The fresh 60-code re-sample suggested by the reviewer has not been done.
- **Part-name rule vs. usefulness.** Because the source is distrusted, parts that the source does not list were removed from causes even when they are real (spark plug in a balance fault, a relay in a fuel pump fault). That is the safe side but it makes some entries less useful to a technician; a mechanic can add them later.
- **Licence** remains as in the pilot report (CC0 data, short standard titles used as the base, all other text original); a lawyer's confirmation is still open.

## 9. What the owner must decide

1. **Start the independent review of this batch** (a separate session, RUN_MODE = review), on the suggested sample in section 5. Do not start batches 2 to 4 before it comes back, so that its findings are applied once.
2. **STOP calibration:** confirm or change the calls in section 5 (items 1 to 4). If the owner prefers fewer STOPs, the rubric mapping in `validate_seed.py` and RUBRIC.md is the one place to change.
3. **Add the missing phrases** to the app's failure-type table (section 7).
4. **Held-back titles:** have the 22 titles in `title_suspects.csv` checked against public sources, as was done for the eight overrides, so those entries can be written (the wheel-speed group matters most for ABS).
5. **Whether to re-run the quality gate** with a fresh 60-code sample by an independent reviewer.

## 10. Files in this run

- `docs/content/`: BATCH1_REPORT.md (this file), RUBRIC.md, SELECTION_RULES.md and GLOSSARY_EN.md (all revised), PILOT_REPORT.md (unchanged, historical).
- `data/content/`: generic_en_seed.jsonl (140 entries), relevance_ranking.csv, title_overrides.csv, title_suspects.csv, fix_log_20261001.csv, seed_review_log.csv, second_pass_batch1_sample.csv, review_regression_cases.json, select_codes.py, build_seed.py, validate_seed.py, validator_selftest.py, authored_pilot.py (rewritten), authored_batch1.py.
