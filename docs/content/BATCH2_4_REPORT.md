# Batch 2 to 4 report: review fixes, title agreement, 189 new entries

Run: RUN_MODE = write, RUN_SCOPE = apply review + title agreement + batches 2 to 4. Date: 2026-10-02. Branch: `content/seed-20261001` (also pushed to the session branch `claude/affectionate-goldberg-imd6di`).
Source: OBDex commit `bc58b0eb7273226a1aabae98e956b70b8362bda1` (CC0-1.0 data), mode **structure-only** (unchanged; the quality gate was not re-run). Second title source: Wal33D dtc-database commit `04c43d72e7db7197658b6f72fe582c5076d9eee8` (MIT).
Nothing outside `data/content/` and `docs/content/` was changed. `main` was not touched. **There is no batch 4: after the title gate only 189 writable codes were left, so the run wrote batch 2 (100) and batch 3 (89) and stopped.**

## 1. What exists now

| Item | Result |
|---|---|
| Entries in `generic_en_seed.jsonl` | **329** (140 existing, reworked, plus 189 new) |
| Codes selected | 387 (329 written, 58 not writable because the two title sources do not agree or one has no entry) |
| Validator (`validate_seed.py`) | **0 errors, 21 warnings** on all 329 entries |
| Validator self-test (`validator_selftest.py`) | **90 of 90 pass** (run after the 140 fixes, after batch 2 and after batch 3) |

| | Existing 140 | New 189 | Total 329 |
|---|---:|---:|---:|
| powertrain / network / chassis | 128 / 11 / 1 | 165 / 14 / 10 | 293 / 25 / 11 |
| STOP | 20 | 13 | **33** |
| SERVICE_SOON | 106 | 121 | 227 |
| MONITOR | 14 | 55 | 69 |
| can_ride_to_workshop: no / with_care / yes | 20 / 96 / 24 | 13 / 112 / 64 | 33 / 208 / 88 |
| confidence: high / medium / low | 52 / 68 / 20 | 6 / 113 / 70 | 58 / 181 / 90 |
| needs_independent_review true | 61 | 111 | **172** |
| `applies_when` set | 27 (8 before) | 118 | 145 |

By code family (all 329): P0 241, P2 52, U0 25, C0 11. The 189 new entries are P0 115, P2 50, U0 14, C0 10.
New entries by main reason tag: evaporative emission 20, oxygen sensors 17 and their heaters 8, ride-by-wire throttle 16 and twist grip sensors 5, ECU internal faults and control unit codes 13, charging 9, wheel speed 8, ABS pump and unit 2, CAN bus and bus off 7, cooling fan 6, secondary air 6, intake and barometric pressure 6, fuel mixture variants 6, ignition coils 6, gear position 6, sensor supply B and C 6, oil pressure 5, throttle sensor B 5, fuel level 5, ambient temperature 5, engine speed signal 4, injector supply 3, unit communication and software codes 7, and 1 each for start-up misfire, crank and camshaft correlation (2), intake air temperature, overspeed, brake switch, clutch switch, cooling system.

## 2. What changed in the 140 existing entries and why

110 of the 140 entries changed (258 field changes, every one in `fix_log_v4_20261002.csv` with its reason). The other 30 are untouched and keep `updated_at` 2026-10-01.

- **STOP dropped from 28 to 20.** Seven downgrades to SERVICE_SOON / with_care as decided (P0604, P0605, P0606, P0202, P0264, P0265, P0352) and P0232, which the OBDex description says leaves the pump powered (reason in its `rider_action_basis`; "open circuit" removed; confidence low). P0336, P0629, P0685, P0686 stay at STOP.
- **One advice sentence per situation (D3, D4).** The idle sentence replaced the self-contradicting "avoid traffic and do not keep riding" in 10 idle entries (P0506, P0510, P0519 and seven more; P0507 got its own throttle-not-closing sentence). One STALL sentence is now used in every entry that talks about stalls; MAP (P0105 to P0109), camshaft (P0340 to P0344), P0561, P0600 and the throttle entries were brought to it. The 8 CAN bus entries U0001 to U0008 carry the NETWORK sentence and review true. U0100 uses the TWO-CASE sentence as one sentence.
- **P068A, P068B (D5).** P068B again says the battery may go flat (the OBDex description supports it). P068A now talks about lost learned settings. TWO-CASE is gone from both, and from the empty first sentences of P0601, P0602, P0607, P0688 to P0690.
- **No-start claims at SERVICE_SOON (D7).** P0633, P0512, P0513: "if it starts, go straight to a workshop; do not switch off on the way".
- **Hindi-readiness (D6).** Idioms replaced (cut out, drops out or jumps, hunt, reduce load, fair share, run on one cylinder, refuse to start, run rich, run hot, points to, stumble) in 22 entries logged as D6 fixes plus the entries rewritten under D2 to D4; sentences over 25 words shortened; "RAM" and "ROM" removed from rider titles of P0604 and P0605; fuel pump entries P0231 to P0233 now say "fuel pump power circuit".
- **`applies_when` (review, R20).** Knock (P0324 to P0329), camshaft (P0340 to P0344), oil temperature (P0195 to P0199), closed throttle switch (P0510) and ABS (U0121, C0035) entries now name the hardware they need.

## 3. Title agreement (Step T, a dry run of the 9,100-code method)

`title_agreement.py` (reproducible; rule in its header) compared the title in force (OBDex, with the 8 owner-checked overrides applied first) with the Wal33D generic title for all 387 selected codes. Output: `title_agreement.csv`, `held_back_titles_v2.csv` (65 rows with both titles and the neighbouring codes, for the owner's assistant), `held_back_before_step_t.txt`, `entries_before_step_t.txt`.

| | AGREE | DISAGREE | MISSING |
|---|---:|---:|---:|
| All 387 selected codes | 322 | 47 | 18 |
| The 22 previously held back | **12** | 10 | 0 |
| The other 365 | 310 | **37** | **18** |

- **Resolved:** 12 of the 22 held-back codes now have two agreeing titles and were written: P0141, P2110, P033F, U0167 and the rear wheel speed codes C0037, C0038, C003A to C003F. Still held: P0134, P0140 (OBDex says "no activity / slow response", Wal33D "no activity detected", the same as the batch 1 reviewer's guess), P2230, U0168, C0030 to C0034, C0036.
- **How many of the 365 disagree:** 37 DISAGREE and 18 MISSING, 55 of 365 (15 percent). The number is dominated by the chassis codes: of 43 selected C0 codes outside the held-back group only 2 agree (C0020, C004F); 23 disagree and 18 are missing in Wal33D. Without the chassis codes, **14 of 322 powertrain and network codes disagree (4.3 percent)**: powertrain 11 of 295 (3.7 percent; 6 are meaning-level differences such as P0351, P0352, P0421, P0449, P0418, P2119 and 5 are wording-only such as P0505, P0446 and the knock sensor naming P0325, P0327, P0328), network 3 of 27 (11 percent: U0327, U0408, U0421).
- **What this means for the 9,100-code basic tier (my reading, not a measurement):** for the common engine and network codes expect about 4 to 5 percent of titles to be flagged, roughly half of them wording differences that a person clears in seconds; for the chassis block expect most codes to be flagged. My hypothesis, **unverified**, is that OBDex follows the older SAE chassis numbering (C0035 left front, C0040 right front, C0045 left rear, C0050 right rear wheel speed circuit) and Wal33D the newer numbering (C0035 right front wheel speed sensor supply, C0040 brake pedal switch A, C0045 brake pressure sensor B, C0050 and C0056 to C0066 missing or other sensors), so the sources disagree because they are two editions of the standard, not because one has random errors. The owner's assistant can confirm that in one lookup.
- **Limits of the method:** AGREE does not prove a title is right. Both sources may come from the same origin (P0233 "Fuel Pump Secondary Circuit Intermittent" matches word for word, and the strange C003x titles agree exactly). Normalisation was tuned once after the first run (the first run gave 115 DISAGREE; the extra rules for default markers such as "sensor A", synonyms such as "secondary air injection" = "AIR system", and a few filler words brought it to 47); every rule is in the script and the 30 AGREE pairs I spot-checked were true agreements.
- **Seven entries written before Step T do not agree** (P0351, P0352, P0505, C0035, P0325, P0327, P0328). They stay in the seed, with a validator warning and `entry_written = yes` in the held list. **Owner decision:** keep them (my recommendation for the six whose difference is wording or numbering: both sources name the same circuit) or withdraw them until the owner's assistant has checked the titles. C0035 is the one real conflict (OBDex: left front circuit malfunction; Wal33D: right front sensor supply); its rider entry is generic ("a wheel speed sensor circuit") and is review true.
- **The ranking now carries the verdict.** `write_ok` in `relevance_ranking.csv` is yes only for AGREE codes and for the 140 grandfathered entries; `select_codes.py` applies it (run order in its header). Rank order is unchanged.

## 4. The 189 new entries

Batch 2 = the first 100 codes after batch 1 (U0009 to P0652), batch 3 = the last 89 (P0653 to C004F). Every entry is written from the code, the standard title in force and the structure of the code; parts named in an entry appear in the source entry (the validator checks it).

| Level | Count | Notes |
|---|---:|---|
| STOP | 13 | proposals in `stop_table.csv`, owner to confirm: P0524 (oil pressure too low, a rubric gap I closed: an active condition that can destroy the engine within minutes), P2104, P2105, P2111, P2112 (ride-by-wire throttle: forced idle, forced shutdown, stuck open, stuck closed), P2146 (injector supply open), P2300 to P2302 (ignition coil A, as P0351), P0320 to P0323 (engine speed signal, as the crankshaft codes) |
| SERVICE_SOON | 121 | 9 of them `can_ride_to_workshop` yes (upstream oxygen sensor response and heater codes) |
| MONITOR | 55 | evaporative, secondary air, downstream oxygen sensor, fuel level, ambient temperature, overspeed |

111 of the 189 are `needs_independent_review` true (all STOP, all chassis and network, all ride-by-wire, all low confidence, every petrol-smell or vapour-leak entry, the brake switch code). 70 are low confidence, mostly thin sources: ECU internal faults, sensor supply B and C, gear position (automatic-transmission source), twist grip sensors, charging terminals, wheel speed and ABS.

Things a reviewer should know about the new entries:
- **Vapour leak codes (P0442, P0455 to P0457) carry the PETROL sentence** because rule R16 treats any fuel leak or vapour leak as a fuel-smell case; they are MONITOR but review true.
- **The NETWORK sentence is long** (two sentences, 215 characters), so it fills the whole advice field. The "ride only if the engine runs normally" condition moved to `can_ride_reason`. If the owner prefers the stall condition in the advice, the 220-character limit or the sentence has to change.
- **Wheel speed codes:** a bike has one rear sensor, so C0037, C003A, C003D (and the supply codes C0038, C003B, C003E) get the same rider title; the validator allows exactly these two triples as duplicates. Standard titles stay in `standard_title_en`. Warnings "meaning identical" for these 4 entries are expected.
- **U0075, U0076, U0077:** the OBDex entry text describes other buses (U0075: bus B degraded). The entries follow the owner-checked titles ("bus C/D/E off") and say only that a bus stopped; confidence low; `derived_from.title_basis` is `override`.
- **`mil`, `emissions_relevant`, `limp_possible`** are still my judgement from the structure of the code. Nobody has checked them.

## 5. Validator, mutation test and regression

- **New rules** (all in `validate_seed.py`, described in RUBRIC.md): R12 to R19 as written by the reviewer (R13 reads the locked `stop_table.csv`), R20 `applies_when` per hardware tag, R21 canonical sentences word for word, R22 Hindi-readiness (25-word limit, idiom blocklist, discouraged words), T1 title agreement. On the 140 existing entries they flagged exactly what the reviewer predicted (R12: P0633, P0512, P0513; R13: the seven downgrades plus P0232) plus the new R20 to R22 findings, all fixed in the text, none by loosening a rule. Two narrow exemptions exist and are documented in the code: the owner's D1 BATTERY sentence may exceed 25 words, and the fixed NETWORK, PETROL and ABS sentences are not part-checked against the source (they name ABS and fuel on purpose).
- **Regression file:** the reviewer's 8 defective entries (6 defects plus 2 bonus) are in `review_regression_cases.json` next to the earlier 4; all 12 are rejected for the named rule.
- **Self-test, 90 of 90:** 1 baseline, 12 regression, 10 original mutation, 26 new mutation cases (one per new rule, some twice, plus D2, D5, D7 and T1), 41 rule coverage and legacy cases. It was run after the 140 fixes, after batch 2 and after batch 3; it never failed.
- **Warnings (21):** 7 T1 (the seven grandfathered entries), 7 "no shared failure phrase" (soft hint), 3 "battery found only in the source description" (P0563, P068B and one more; kept on purpose), 4 identical meanings (the rear wheel speed codes above).
- A clean run is still not proof of safety. The checks are patterns. The review that follows should concentrate on level calls and meaning, not wording.

## 6. Second pass (sceptical mechanic) and what it found

Random 30 of each batch (`second_pass_sample.py`, seed 20261002 plus the batch number; lists in `second_pass_batch2_sample.csv` and `second_pass_batch3_sample.csv`), re-read against the OBDex source entry. All rows are in `seed_review_log.csv` (12 new rows).

- **Batch 2:** 3 real defects in the sample (P0524 "within minutes" was an unsupported time claim; P0918 duplicated cause; P2226 informal wording) and 2 accepted notes (P0127 generic cause not in the source; the gear position family comes from an automatic-transmission source). Outside the sample I found and fixed 2 more (P2148 had no warning about a hot or swollen battery; "off idle" in P2177 and P2178 is jargon).
- **Batch 3:** 1 real defect in the sample (P0450 hint not in the source) and notes for the choices a reviewer should look at (U0075 to U0077 text versus source, the rear wheel speed titles, P0320 to P0323 at STOP with low confidence, the brake switch advice).
- **The second pass is weaker than an independent review.** Last time the same-author pass found problems in 27 percent of a sample and the independent reviewer then found 94 concerns in 68 entries. This time the pass found fewer (about 10 to 17 percent defect rate in the samples), partly because the new batches use more shared wording. I expect the independent review to find more, mostly wording, and I would not treat the low rate as evidence of quality.

## 7. Effort used

- Tokens: about **0.6 million** (15.0 million at the start, about 14.4 million at the end). Roughly 0.15 million was reading (the brief, the reviewer's report and files, the existing validator and entries); 0.06 million for Step T; 0.15 million for the validator, the self-tests and the 140 fixes; 0.12 million for batch 2 and 0.12 million for batch 3 (writing, fixing validator findings, second pass); the rest for documents.
- Estimate per 100 new entries: about 0.1 to 0.12 million tokens, plus about 0.3 million of one-off cost (reading, validator, fixes). Wall time: about 1 to 1.5 hours.

## 8. What I could not do

- No mechanic or workshop check of anything. The reviewer is not a mechanic either, so every safety-relevant entry stays review true.
- No title was checked on the public web (no access in this session); the 65 non-AGREE titles wait for the owner's assistant.
- The 60-code quality gate was not re-run with a fresh sample (still outstanding from the first review); mode stays structure-only.
- No Hindi.
- 58 selected codes are not written (10 still held from before, 48 new): 40 chassis wheel speed and ABS codes, 5 powertrain (P0446, P0449, P0421, P2119, P0418), 3 network (U0327, U0408, U0421).

## 9. Decisions for the owner

1. **Confirm or remove the 13 proposed STOP codes** in `stop_table.csv` (section 4). Until then they are STOP and review true.
2. **The seven written entries whose titles do not agree** (section 3): keep or withdraw.
3. **Start the independent review** as planned: 100 random of the 189 new entries plus every STOP (33). I would add: the 7 downgraded entries, the 6 ride-by-wire STOP codes, the ABS and wheel speed group as a group (11 entries, almost unreviewed so far), and the NETWORK entries.
4. **NETWORK sentence length** and the **BATTERY sentence over 25 words** (section 4 and RUBRIC.md): accept or change.
5. **Title check by the owner's assistant:** the 65 rows of `held_back_titles_v2.csv`, starting with the C0 block (one lookup may explain all 40 chassis codes if the two editions hypothesis is right) and the 10 still-held earlier codes.
6. **Whether the method is good enough for the 9,100-code basic tier:** it caught real problems (shifted titles) at a cost of about 5 percent flagged codes in the common families. Its weak point is that the two sources may not be independent.

## 10. Recommendations for the Hindi pass

- Translate the **9 fixed sentences** once (GLOSSARY_EN.md, "Fixed sentences": STALL, PETROL, ABS, NETWORK, IDLE, BATTERY-HOT, OVERHEAT, TWO-CASE, STOP-TAIL) and the long BATTERY sentence of P0563 and P2504. They cover most of the advice text.
- Translate the glossary terms first (about 120). New hard ones: downstream and upstream oxygen sensor, delayed response, twist grip, pickup, tone ring, vapour system, purge valve, bus off, sensor supply, learned settings.
- Sentences are at most 25 words (one fixed sentence 29), the longest 269 of 961 sentences have 21 to 25 words. Start with the shorter entries (MONITOR) to test the glossary, then the SERVICE_SOON groups, and do the STOP entries last, with a native-speaker check.
- Carry `applies_when` and the review flag through unchanged; Hindi entries inherit the level and the can-ride value.

## Additions beyond the brief

1. **`stop_table.csv` as data, not code.** The owner edits one file to change a STOP; each row has a reason and a status (owner_confirmed, proposed). Reason: it makes the owner's decision enforceable and visible, and it shows which STOPs are proposals.
2. **New `applies_when` keys and rule R20** (14 hardware keys). Reason: the batch 1 reviewer found codes the bike cannot raise; the app can now hide them. The app must learn the keys.
3. **Title gate T1 with a grandfather list**, and the verdict stored in `relevance_ranking.csv`. Reason: Step T results are used by the tools, not only read by a person.
4. **Canonical sentences enforced by R21** (five sentences, word for word). Reason: the reviewer found six variants of one stall sentence.
5. **Hindi-readiness as validator rules (R22)**, not as a reading task. Reason: the reviewer found a quarter to a third of entries hard to translate; rules find them in seconds and stop them coming back.
6. **`fix_log_v4_20261002.csv`**: every field change on the 140 entries with its reason. Reason: the independent reviewer can check each fix.
7. **`second_pass_sample.py`** with a fixed seed and `--show`, which prints the entry next to its source. Reason: the second pass is reproducible.
8. **`build_seed.py` keeps `updated_at` for entries that did not change.** Reason: the date shows which entries a reviewer needs to look at again (299 changed or new, 30 untouched).
9. **Risks noticed:** (a) the two title sources may share one origin; (b) the chassis disagreement may be two editions of the standard, not errors; (c) 40 percent of the new entries are low confidence because the OBDex text is thin or car-oriented (ABS, automatic-transmission, distributor, comfort bus); (d) the `mil`, `emissions_relevant` and `limp_possible` flags are unchecked judgement; (e) 13 new STOP proposals would take STOP to 10 percent of all entries, which is within the reviewer's expectation (below 15 percent) but is the owner's call; (f) the reviewer's idea to give STOP entries two versions of advice (riding, parked) is not done and needs an app decision.
10. **Validator exemptions are narrow and written in the code and RUBRIC.md** (D1 BATTERY sentence, fixed sentences in the part check, the rear wheel speed duplicate titles, the ABS and wheel speed subject words). Reason: no rule was loosened to make an entry pass.
