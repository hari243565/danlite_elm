# Pilot report: English seed for standard (generic) fault codes

Run: RUN_MODE = write, RUN_SCOPE = pilot. Date: 2026-10-01. Branch: `content/seed-20261001`.
Source: OBDex commit `bc58b0eb7273226a1aabae98e956b70b8362bda1` (CC0-1.0 data).
Nothing outside `data/content/` and `docs/content/` was changed.

## 1. What exists now

| Item | Result |
|---|---|
| Access preflight | Passed. Clone worked; push to the branch worked. |
| Codes selected | **383** of 9,533 (target was about 1,200; not padded, see SELECTION_RULES.md) |
| Entries written | **40** in `data/content/generic_en_seed.jsonl` (the 40 highest-ranked codes) |
| Mode | **structure-only** (decided by the quality gate) |

Entries by system: powertrain 36, network 3, chassis 1.
Entries by rider action level: STOP 6, SERVICE_SOON 29, MONITOR 5, INFO 0.
Confidence: high 31, medium 7, low 2. `needs_mechanic_review` is true on 12 entries (6 STOP, 1 chassis, 3 network, 2 others: the low-confidence serial link P0600 and the overcharging code P0563, which was kept on review for fire and battery risk).
All 9 evidence anchors from the Royal Enfield manual are ranks 1 to 9 and are in the pilot. The Honda blink-table sensor families (MAP, engine temperature, throttle position, intake air temperature, injector) are all in the pilot.

## 2. Quality gate (Step 1B)

60 codes drawn at random across P0, P2, C0 and U0. Judged against the standard code list and engineering knowledge for a small fuel-injected bike.

| Field | Questionable or wrong | Empty |
|---|---:|---:|
| Title | 8.3% | 0 |
| Components | 11.7% | 0 |
| Causes | 10.0% | 0 |
| Symptoms | **26.7%** | 25.0% |

Decision rule: causes or symptoms above 15% means structure-only. Symptoms are at 26.7%, so **MODE = structure-only**. In plain terms: the source's symptom lists are mostly generic car text, so none of its causes or symptoms were copied. Details and examples are in `data/content/source_quality_gate.md`; the verdict per code is in `data/content/source_quality_gate_sample.csv`.

## 3. Validator and second pass

- `validate_seed.py` result on the 40 entries: **0 errors, 1 warning**. The warning (P0563) is that "battery" appears only in the OBDex description of the code, not in its title, components or causes. It is kept on purpose because overcharging damage to the battery is the safety point of that entry.
- `validator_selftest.py`: 17 of 17 mutation tests pass (each deliberately broken entry is rejected: too long, banned word, currency, URL, wrong rubric level, missing review flag, unsourced part, voltage figure, wrong wording, German text, bad source hash, wrong glossary term, two-sentence meaning, five causes, "limp mode", wrong system).
- Skeptical second pass (acting as a sceptical mechanic): all 40 entries re-read against their source entries (the brief asks for at least 30 per 300). 19 rows are in `data/content/seed_review_log.csv`: 14 fixed, 2 open and needing a mechanic (ABS braking claim in U0121, wheel position in C0035), 1 open app rule (P0202 on single-cylinder bikes), 2 accepted.
- Notable catches: the coolant sensor advice had one code's symptoms the wrong way round; several entries named the catalytic converter or cooling fan, which the source entry does not list; "stop if the lamp blinks" is not reliable on bikes.
- This pass was by the same author as the entries. An independent RUN_MODE=review session is still needed.

## 4. Time and effort

- Wall time: about 30 minutes from the first commit to this report.
- Budget used: about 260,000 tokens in total (15.00 million at start, 14.74 million at the end of the run).
- Roughly half of that was one-off work: cloning and reading the source, selection rules, the quality gate, the validator, the build script and the documents. Writing, validating and re-reading the 40 entries was about 70,000 to 90,000 tokens.
- **Estimate per 100 entries: about 150,000 to 200,000 tokens** (writing about 50,000; validation loops, corrections and the sceptical pass about 100,000; reading source entries for part checks the rest). Structure-only mode keeps source reading small. Entries that are near-duplicates of an earlier one (the voltage above and below threshold pairs, the wheel speed variants) are cheaper; chassis and network codes cost more because each needs mechanic-review wording.
- **The remaining 343 codes would cost roughly 0.5 to 0.7 million tokens** (batches 1 to 4 at 100 codes each, the last one with 43). Hindi comes after this and is a separate cost.

## 5. Additions beyond the brief

1. **Selection tiers and tags.** `relevance_ranking.csv` has a `tier` (1 anchors, 2 spread list, 3 core, 4 extended) and `reason_tags` that the validator reuses to enforce the rubric per family. A `honda_family` column marks the 51 codes in the sensor families that Honda blink tables list.
2. **Explicit drops and removals.** Network codes for modules a bike does not have (second ECM, injector or fuel-pump control module, starter/generator, brake system module) were removed after the sample showed one. A `DROP` list in `select_codes.py` keeps the reason for each removed code reviewable.
3. **Quality gate also grades title and components**, not only causes and symptoms, because 8% of sampled titles were already doubtful. `title_suspects.csv` lists 8 codes whose OBDex title looks wrong (P0139, P0626, P0686 to P0688, U0075 to U0077). Because the brief calls the title a fact "you may rely on", this list needs the owner's attention before those entries are written.
4. **Extra validator checks:** the source hash must match the OBDex entry at the recorded commit; every part named is checked against the source title, components and causes (with a warning tier for the description); rubric level enforced per reason tag; STOP advice must say pull over or stop and MONITOR advice must not; entries must be one sentence in the meaning and one or two in the advice; long sentences are warned about for the Hindi pass; numbers with units, pin numbers, part numbers and long digit strings are rejected; wording variants of the shared phrases and glossary terms ("check engine light", "ECM", "limp mode", "earth") are rejected; system must match the code prefix; duplicate meanings are warned.
5. **`validator_selftest.py`** proves the validator rejects what it should. Rerun it whenever the validator changes.
6. **`build_seed.py`** turns authored text into the JSONL, adds the source hash and commit, orders entries by rank, and with `--append` never overwrites an earlier entry. **`select_codes.py`** and **`quality_gate.py`** make selection and the gate reproducible.
7. **Glossary** also lists the discouraged forms, which the validator uses, so the Hindi pass has one source of truth.
8. **Fields a diagnostics app would likely need (not added; would change schema_version 1; proposed for a version 2):**
   - `failure_type` enum aligned with the shared phrase list, so the app's failure-type table does not parse text.
   - `applies_when` (needs two cylinders, needs a camshaft sensor, needs ABS fitted, liquid-cooled only) so the app hides codes the bike cannot raise.
   - `can_ride_to_workshop` (yes / carefully / no) next to the action level.
   - `related_codes` and a `root_cause_group` (for example all sensor supply faults, ECU power, CAN) so several codes can be shown as one problem.
   - `standard_title_en` kept separate from the rider title, for search and for traceability to the source.
   - `reviewed_by`, `reviewed_at`, `review_status` per entry, so reviewed text is distinguishable from seed text.
   - `clear_conditions` (when the lamp normally goes out) and `drive_cycle_needed`.

## 6. Risks noticed

- **Selection yields 383 codes, not 1,200.** A small bike simply does not raise more generic codes. If the owner wants more entries, they would have to come from other sources (maker-specific tables, Honda blink codes), not from padding the generic layer.
- **Generic codes cover only part of what bikes report.** Many Indian bikes use maker-specific codes or blink codes. The generic seed will not explain every code a rider sees.
- **Chassis (C) codes are car-style** (left front, right rear). On a bike they need a maker table to say which wheel is meant. All are on mechanic review.
- **Braking wording.** The "normal braking should still work" statement in the ABS entries depends on the bike (combined braking systems differ). It is hedged and flagged but needs a mechanic.
- **P0420 and aftermarket exhausts.** Modified exhausts commonly set it. The entry does not mention this because the source does not.
- **Single judge.** The quality gate and the second pass are by the author of the entries. An independent review run should re-sample.
- **Licence.** The source data is CC0-1.0 and the OBDex README says descriptions are independently authored, but this was not verified here. The seed uses short standard titles as a base and writes all other text itself. The owner may want a lawyer to confirm that rewording the standard's short titles is acceptable.
- **The 15% rule is crude.** Boilerplate symptoms drove the decision; causes alone would have passed. It is the safer choice for riders but costs more writing.

## 7. What the owner must decide

1. **Continue?** Review 5 to 10 pilot entries (suggested: P0201, P0300, P0420, P0562, P0563, U0121, C0035) for tone, safety wording and usefulness. If acceptable, run `RUN_SCOPE = batches 1-4` (about 0.5 to 0.7 million tokens).
2. **Rubric reading.** Confirm that ABS and wheel speed faults are SERVICE_SOON with an ABS-off warning, not STOP (see RUBRIC.md, "Interpretation").
3. **Rule changes.** Keep structure-only? Add wide-band O2, variable valve timing or fuel pressure codes? Accept the 383 target?
4. **Suspect titles.** Decide how to treat the 8 titles in `title_suspects.csv` (check against the standard first, or write entries from the pattern).
5. **Start a review run** (RUN_MODE = review, new session) on the 40 pilot entries before more are written, so the first batch inherits corrections.
6. **Schema.** Decide whether to adopt the version 2 fields in section 5.8 before the Hindi pass.

## 8. Files in this run

- `docs/content/`: ACCESS_CHECK.md, SELECTION_RULES.md, RUBRIC.md, GLOSSARY_EN.md, PILOT_REPORT.md.
- `data/content/`: relevance_ranking.csv, generic_en_seed.jsonl, source_quality_gate.md, source_quality_gate_sample.csv, title_suspects.csv, seed_review_log.csv, select_codes.py, quality_gate.py, authored_pilot.py, build_seed.py, validate_seed.py, validator_selftest.py.
