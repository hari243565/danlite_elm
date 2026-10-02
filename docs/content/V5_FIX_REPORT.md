# V5 fix report: applying the independent review of the V4 entries

Date: 2026-10-02. Branch: `content/seed-20261001`. Author session. Plan v1.1, aim A3, tier T1, step B-1, gate G-T1.
Nothing new was written: no new entries, no Hindi, no batches. `main` was not touched. Only `data/content/` and
`docs/content/` changed. The OBDex data was read from a clone at the pinned commit `bc58b0eb7273226a1aabae98e956b70b8362bda1`;
no code from that clone was run.

## In plain English

The reviewer found real problems in 189 of the 329 entries. I fixed what the owner decided (groups G1 to G8), proved the
fixes with the checking program, and stopped. The checking program (the validator) now reports **0 errors**, and all
**109 of 109** self-tests pass (90 before this pass, 8 new regression cases for the reviewer's attacks, 11 new tests for
the owner's decisions G2 to G8). The shipped seed now has **308 entries**; **21** are held out in a separate file.
104 of the 308 shipped entries changed; the other 204 are byte for byte unchanged, including their `updated_at`.

None of this makes any entry "verified" or "checked by a mechanic". Nobody on the project is a mechanic. Every entry that
the rules say needs independent review still has `needs_independent_review` true.

## What changed per group

| Group | What | Count |
|---|---|---|
| G1 validator | Rules Q1 to Q8 from the reviewer added to `validate_seed.py`. The reviewer's 8 defective entries are in `review_regression_cases.json` and each is rejected by its Q rule. All 329 entries (shipped + held) give 0 errors, so there were no new hits to explain or tune. | 8 rules, 8 regression cases |
| G2 titles | The six owner-verified public titles are in `title_overrides.csv` (14 overrides now). `select_codes.py` regenerated `relevance_ranking.csv` and `title_suspects.csv` (only those six rows changed); the build uses them. Proof: for all six, `standard_title_en` equals the override and `title_basis` is `override`. | 6 entries |
| G3 hold-outs | Moved out of the shipped seed into `held_entries_v5.jsonl` with the reviewer's reason in a `held_reason` field: chassis wheel-speed C0035, C0037, C0038, C003A to C003F (9); gear position P0914 to P0919 (6); alternator field and lamp terminal P0620, P0621, P0625, P0626, P2500, P2501 (6). Not deleted: their text is still in the `authored_*.py` files. | 21 held, 308 shipped |
| G4 STOP table | P2100, P2102, P2103 are now STOP (P2101 stays SERVICE_SOON, with_care). Checking the other ride-by-wire entries against the rule moved four more to STOP: P2106 (forced limited power), P2110 (forced limited engine speed), P2107 and P2108 (throttle control unit faults). Sensor plausibility faults (P2135, P0220 to P0224, P2122 to P2138 and so on) stay SERVICE_SOON. `stop_table.csv` has a reason for each of the seven. P2111 now says "Close the throttle, pull in the clutch, use both brakes to slow down, then stop safely and switch off." All keep `needs_independent_review` true. STOP entries: 33 to 40. | 7 level changes, 8 entries |
| G5 idle | The 10 idle entries use exactly the owner's pair of sentences. P0507 (the 11th) keeps its own mandatory "throttle does not snap fully shut" sentence and gets the second half of the pair, because its advice may have only two sentences. The stacked STALL sentence is gone from all 11. | 11 entries |
| G6 twin | The clause "on a two-cylinder bike it may keep running on one cylinder, but have it checked soon" is joined to the first sentence of the seven cylinder 1 ignition and injector STOP entries (P0201, P0261, P0262, P0351, P2300, P2301, P2302). Levels unchanged. A line about a possible `action_level_twin` field is in `docs/content/BACKLOG.md` (new file). | 7 entries |
| G7 long sentences | The 29-word battery sentence in P0563 and P2504 is two sentences (19 and 13 words). The validator no longer exempts it: every sentence is measured. The bus-fault (NETWORK) sentence was already two sentences of 20 and 21 words, so it needed no change. | 2 entries |
| G8 concerns | 128 CONCERN rows (121 in the sample plus 7 found outside it). See below. | 72 shipped + 8 held entries edited |

(G8 entries overlap with other groups: for example P0201 is in G6 and G8.)

## Fix log totals (G8)

`fix_log_v5_20261002.csv` has one row for every CONCERN row (128): **107 APPLIED, 21 REJECTED**. Every text change, field by
field, is in `fix_changes_v5_20261002.csv`.

Most important applied: the "runs very hot" sentence replaced in 11 entries and removed from P0117; P0633, P0512, P0513
no longer say "do not switch off on the way"; `can_bus_fitted` added to all 17 CAN entries (and required by rule R20);
oil pressure "mechanical tester" wording; P0522 now needs review and names noisy, hot or low oil as reasons to stop;
P2148 now carries the hot or swollen battery sentence; idioms replaced (misbehave, fine-tune, pulling the bus down,
jumped, run on, sender).

Most important rejections (21):
- **P0217** (STOP overheating): adding `liquid_cooled` would hide a STOP code on air- and oil-cooled bikes, which can also overheat. The text is already conditional on a radiator.
- **New `applies_when` keys** (16 rows): evap vent valve and pressure sensor (P0448, P0451, P0454), immobiliser (P0633, U0167), neutral switch (P0852), sensor supplies B and C (P0651 to P0653, P0697 to P0699), alternator ECU field (P0625, P0626, P2500, P2501), body control unit (U0140). The schema does not have these keys, so I did not invent them; they are in the backlog. The alternator entries are held out meanwhile.
- **P0232** "the battery may go flat": not in the source and the owner has not agreed.
- **P0326**: no verified title was given for it; it is not one of the six.
- **C0035** "mark `standard_title_en` not for riders": a schema change; the entry is held out.

## Validator and mutation results

- Validator on the shipped seed: 308 entries, **0 errors, 15 warnings**. Warnings: six "title not agreed by two sources" for
  the six owner-verified-title entries (P0351, P0352, P0325, P0327, P0328, P0505; they were written before Step T and are
  kept); P0563 and P068B mention the battery only in the source description; P0491, U0401, U0415, P033F, P0322, P0219,
  C004F use none of the shared failure phrases. All were already warnings before.
- Validator on all 329 (308 + 21 held): 0 errors, 21 warnings.
- `held_entries_v5.jsonl` run alone shows one error per entry, "unexpected fields ['held_reason']": that is the extra field, nothing else.
- Self-tests: **109/109**, 0 failures. All earlier tests pass unchanged. Parts: baseline, regression (now includes the reviewer's 8 attacks), 10 mutations, v4 mutations, 11 new v5 mutations, rule coverage.
- Validator additions: Q1 to Q8; idle pair rules; the idioms misbehave, fine-tune, jumped, "pulling the bus down", "run on", "sender"; phrases "short circuit" and "resistance out of range" on the shared list; `can_bus_fitted` required for CAN entries; decision checks for P2100 to P2103, P2101, P2111 and the seven twin entries; an error if a held-out code is in the shipped seed.

## Entries now held out and why

- **Chassis wheel speed (9):** the two editions of the chassis code numbering are mixed in the source, one source reads C0035 as a right front sensor supply code, "position-neutral" is not settled for front or rear, and the stored standard title still names a wheel. C003F also made an unsupported claim about direction sensing (removed in the held copy).
- **P0914 to P0919 (6):** the source is an automatic gearbox selector code; the entry invented a bike effect. The held copies now say only that the gear position signal is unreliable.
- **Alternator field and lamp terminal (6):** a car-style feature with no `applies_when` key to hide it from bikes that cannot raise it. P0625's rare "worn brushes" cause is removed in the held copy.

## What I could not do or decided differently

- **P0507** cannot carry the full idle pair (advice limit of two sentences plus its mandatory throttle sentence). It carries the second half only.
- **Twin clause** is joined with a semicolon to the first sentence (two-sentence limit) and the validator's idiom list ignores that exact clause, because the owner's wording contains "running on one cylinder". A STOP entry that says "have it checked soon" in the same text as "do not keep riding" may read mixed; I used the owner's words and kept the clause before the STOP sentence.
- **P2111** confidence is now medium: rule Q4 forbids high confidence on text that mentions brakes.
- **P0563 and P2504** now have three sentences in the advice; the validator allows a third only for the battery pair.
- **R1** ("stop if it stalls") now ignores the owner's exact idle sentence, because "at a stop" there is a place, not advice.
- A mechanic should still confirm P2111's wording and the four extra STOP entries.

## Additions beyond the brief

1. **P2106, P2107, P2108, P2110 to STOP.** G4 said to check the other ride-by-wire entries against the rule; I applied it. They are marked `proposed_v5` in `stop_table.csv` for the owner to confirm (P2100, P2102, P2103 are `owner_confirmed_v5`). To undo, delete the rows and the four `fix(...)` blocks in `authored_fixes_v5.py`.
2. **Same-word fixes** for the idioms the new validator lists caught in entries the reviewer did not name: P0124, P0600, P0601, P0607, P0634 (misbehave), P0130, P2195 (fine-tune), P0464 (sender), P0523 (pressure test), P0512 and P0513 (reason wording), and six ride reasons that said "stop if the engine gets very hot". Each is logged.
3. **Build tooling:** `authored_fixes_v5.py` (all V5 text changes, applied by `authored_all.py`), `held_v5.py`, `build_fix_log_v5.py`, a held-file step in `build_seed.py`, `fix_changes_v5_20261002.csv`, a copy of the reviewer's flags CSV (`review_flags_v4_20261002.csv`), `.gitignore` for `__pycache__`.
4. **Backlog** items for the schema keys listed above.
