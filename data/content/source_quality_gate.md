# Source quality gate (Step 1B)

**Decision: MODE = structure-only.** Symptoms of the source entries failed the 15% rule (26.7% questionable or wrong, plus 25% empty). Causes passed on their own (10.0%), but the rule fires if either field is above 15%, and 20 of 60 sampled codes (33.3%) had a questionable or wrong cause or symptom.

In structure-only mode the entries use only the code, the standard title and the code's structure. OBDex causes and symptoms are not copied or adapted. `derived_from.mode` is `structure-only`. Likely causes and advice are written from motorcycle engineering knowledge of the circuit type, and every part named is checked against the OBDex title, components, causes or description by the validator.

## Method

- Source: OBDex commit `bc58b0eb7273226a1aabae98e956b70b8362bda1`.
- Sample: 60 codes drawn at random with `random.seed(20261001)` from the first selection of 389 codes (P0 36, P2 9, C0 8, U0 7; the family counts follow the selection). U0115 was in the sample and was later removed from the selection (see SELECTION_RULES.md); the final selection has 383 codes.
- One reviewer (the author of the entries), judging each field against the standard code list and sound engineering knowledge, thinking of a small fuel-injected bike. Verdicts and one-line reasons are in `source_quality_gate_sample.csv`; `quality_gate.py` computes the rates.
- Scale: OK; QUESTIONABLE (true somewhere, but boilerplate, car-only, padded or misleading for a rider); WRONG (contradicts the standard or engineering); EMPTY (symptoms only: the source has none).

## Rates (n = 60)

| Field | OK | Questionable | Wrong | Empty | Questionable + wrong |
|---|---:|---:|---:|---:|---:|
| Title | 55 | 4 | 1 | 0 | 8.3% |
| Components | 53 | 7 | 0 | 0 | 11.7% |
| Causes | 54 | 6 | 0 | 0 | 10.0% |
| Symptoms | 29 | 14 | 2 | 15 | **26.7%** |

## What the sample showed

1. **Symptoms are boilerplate per family.** Every ABS and wheel speed code repeats the same four car symptoms (stability control off, brake assist, ...). Evaporative codes repeat "fuel smell" and "loose-cap warning" for circuit faults. Overheating (P0217) lists "cabin heater weak" and "long warm-up". A gear position input (P0915) lists automatic-transmission slipping. 15 of 60 have no symptoms at all.
2. **Car parts leak into causes and components**: mass air flow sensors, air pumps and combi valves, variable valve timing solenoids, pedal sensors, a second ECM, gateway modules, central electronics fuses.
3. **Titles are mostly fine but not safe to trust blindly**: 5 of 60 were questionable or wrong. P0687 is given the sense-circuit meaning; U0075 breaks the bus A to F pattern; C003C and P033F are not clear standard titles. A wider list of suspect titles noticed while working is in `title_suspects.csv`.
4. **Causes are usually plausible** (90% fine), which is why a later run could still use them as hints for `technician_hints_en` after a mechanic reviews them. Padding is common: three causes that all say "loose connector".
5. **Flags look generic**: ABS entries set `mil: true` on some codes, and `limp_mode_possible` is set widely.

## Consequences for the content

- Do not copy OBDex causes or symptoms. Use the code, title and structure only (current mode).
- The title is the one source fact used, so titles in `title_suspects.csv` need checking against the standard before their entries are trusted.
- Keep `needs_mechanic_review` true for every chassis code.
- If the owner wants a different threshold, re-run the gate on a fresh sample (`quality_gate.py` holds the verdicts; a new sample needs new verdicts).

## Limits of this gate

One judge, the same one who writes the entries, no workshop experience, and no access to the SAE standard text. An independent RUN_MODE=review session with different eyes should repeat a 60-code sample.
