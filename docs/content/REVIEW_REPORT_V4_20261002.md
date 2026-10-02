# Review report: V4 output (329 entries)

Independent review, RUN_MODE = review, RUN_SCOPE = review of the V4 output. Date: 2026-10-02.
Reviewed branch: `content/seed-20261001` (head `e7caef1`). Review output branch: `content/review-v4-20261002`.
Source: OBDex commit `bc58b0eb7273226a1aabae98e956b70b8362bda1` (re-cloned by this reviewer; the same commit the author used).
Sample seed: `20261002` (reproduce with `data/content/review_sample_v4_20261002.py`; the result is in `review_sample_v4_20261002.json`).
No entry, validator rule or earlier file was edited. `main` was not touched. Nothing outside `data/content/` and `docs/content/` changed.

I am not a mechanic and nobody on this project is. Every judgement below is reasoned engineering judgement checked against the OBDex text and the rubric, not workshop experience. I did not trust the author's log, the validator or the author's second pass; I re-ran them as checks only.

## In plain English (for a non-coder)

I re-read **189 of the 329 entries** the way a rider or a small workshop would: all 33 STOP entries, 129 new entries (100 chosen at random plus every new chassis and network entry), 60 reworked entries (30 at random plus the ones in the special groups), the 8 entries that were downgraded, the whole ride-by-wire group and the whole ABS and wheel-speed group. Each got up to 12 questions (2,110 answers).

**Short answer: the work is in better shape than after batch 1. There is no outright FAIL in the sample, but about half the entries (91 of 189) still have at least one concern, and a few concerns are about safety.**
- **Counts:** 1,989 PASS, 121 CONCERN, 0 FAIL out of 2,110 answers. 98 of 189 entries are fully clean. Seven more concerns were found outside the sample while checking neighbours (P0117, P0325, P0326, P0327, P0504, P0505, P0522).
- **The V4 fixes landed.** All 258 logged field changes on the 140 older entries are in the file, and I found no unlogged change in any rider-facing field. The 8 downgrades (P0604, P0605, P0606, P0202, P0264, P0265, P0352, P0232) are all present with their reasons.
- **The 33 STOP entries are accurate and safe to show, with one gap that matters:** the advice for P2111 (throttle stuck open) tells the rider to pull over and switch off but not how to slow down first. Nothing in the 13 newly confirmed STOP texts contradicts the owner's decision.
- **The biggest open risks are not wording:**
  1. Three ride-by-wire entries (P2100, P2102, P2103) say "the throttle may not follow the twist grip" at SERVICE_SOON, which is the same effect that makes P2104 a STOP.
  2. The idle entries (11 of them) still carry two fixed sentences that a rider can read as opposite instructions.
  3. The chassis wheel-speed codes sit on two different editions of the standard. The two sources do not agree on C0035 at all (Wal33D calls it a right front sensor *supply* code), which contradicts the owner's premise. Under the newer edition C0040 is a brake pedal switch code.
  4. The seven owner-verified titles were never stored in the entries; the entries still carry the OBDex wording.
- **The validator can still be fooled.** I wrote 6 new bad entries (plus 2 bonus ones). The validator accepted all 8 with zero errors, including a fire-risk entry that never uses the words it looks for, a STOP entry that tells the rider to open the hot radiator cap, a brake light code set to "can wait for the next service", and a reversed oil pressure meaning. Eight proposed rules catch all of them and raise zero false alarms on the 329 real entries.
- **Recommendation: yes after these rule changes** (section I). Hold the chassis wheel-speed entries, P0914 to P0919 and the alternator-field codes out of the Hindi pass until the open questions are answered.

## A. Counts per verdict

Rows: `data/content/review_flags_v4_20261002.csv` (code, check, verdict, reason, suggested_fix; 2,110 rows for the sample, plus 7 rows marked "[outside the seeded sample]").

| Group | Entries | Entries with no concern | Entries with at least one concern | FAIL rows |
|---|---:|---:|---:|---:|
| New, random 100 of 189 | 100 | 55 | 45 | 0 |
| Reworked, random 30 of 140 | 30 | 17 | 13 | 0 |
| All 33 STOP | 33 | 19 | 14 | 0 |
| New, all reviewed (random 100 + 10 chassis + 14 network + STOP and special groups) | 129 | 65 | 64 | 0 |
| Reworked, all reviewed | 60 | 33 | 27 | 0 |
| **All reviewed** | **189** | **98** | **91** | **0** |

(The "clean" and "with concern" columns count entries once, even if they have several concerns. One entry can sit in several groups.)

## B. The ten most serious problems

| # | Codes | Problem | Suggested fix |
|---|---|---|---|
| 1 | P2111 (and P2104, P2105 by the same logic) | A stuck-open throttle may not let the bike slow down. The advice says "Pull over safely, switch off and do not keep riding". It never says how to slow down first. | Add one sentence: "If the bike does not slow down, use the brakes, pull in the clutch if it has one, then switch off." A mechanic should confirm the wording. |
| 2 | P2100, P2102, P2103 (P2101, P2118 milder) | Same effect as P2104 (STOP) written at SERVICE_SOON: "the ECU may lose control of the throttle and the throttle may not follow the twist grip". The OBDex text only says limp-home with reduced power. One of the two levels is wrong. | Reword to the source ("power is reduced") or add the three codes to the STOP table. |
| 3 | P0505 to P0519 (11 idle entries) | Two fixed sentences in a row: "if it stalls at stops, ride gently" and "if it stalls more than once, do not keep riding". A rider who stalls at every stop meets both. | Owner to merge them into one two-step instruction (wording in `review_flags`, check 3). |
| 4 | C0035, C0037 to C003F, C0040, C0045, C0050 | Two editions of the chassis numbering are mixed. OBDex lists the same wheel fault under two numbers (C0037 and C0045; C003A and C0050). Wal33D says C0035 is a right front sensor **supply** code, not a left front circuit code. Under the Wal33D edition C0040 is "brake pedal switch A". | Hold C0035 at low confidence; do not write C0040, C0045, C0050 until the edition is known (section G). |
| 5 | P0201, P0261, P0262, P0351, P2300 to P2302 vs P0202, P0264, P0265, P0352, P2303 to P2305 | Cylinder 1 faults are STOP "because no fuel or spark stops a single". On a twin the other cylinder keeps running, which is why the cylinder 2 siblings are SERVICE_SOON. A twin rider gets a different instruction for the same effect. | Owner to decide: add "on a twin the other cylinder may keep running" to the cylinder 1 STOP texts, or give twins their own wording through `applies_when`. |
| 6 | P0914 to P0919 (P0917, P0918 reviewed) | The OBDex source is an automatic gearbox selector code (harsh shifts, locked in one gear). The entries invent a bike effect ("starting or other gear-based functions may be affected"). | Say only "the gear position signal is unreliable"; keep low confidence; consider holding. |
| 7 | the validator | Six safety properties are not checked (section E). | Rules Q1 to Q8. |
| 8 | P0633 (and P0512, P0513) | Reason says "if it starts, go straight to a workshop; do not switch off on the way". It tells a rider not to use the one action that always makes a bike safe, and gives no reason. | "avoid switching off the engine until you reach the workshop, unless something is wrong". |
| 9 | P0115 to P0119, P0480, P0483 to P0485, P0691, P0692, P2181 | "If the engine runs very hot, stop and let it cool": a rider without a temperature display cannot judge that. P0117 (engine looks hotter) carries the overheating warning, but the real overheating risk belongs to P0118 (engine looks colder, fan may not start). | "If your bike has a temperature warning and it comes on, or you see steam or smell hot coolant, stop and let the engine cool." Remove it from P0117. |
| 10 | 34 `applies_when` concerns (the most frequent finding) | `can_bus_fitted` exists but none of the 17 CAN bus entries uses it; alternator field and lamp terminal codes (P0620, P0621, P0625, P0626, P2500, P2501) are car-style and carry no key; EVAP vent valve and pressure sensor entries (P0448, P0451, P0454) share the coarse `evap_fitted`; neutral switch, immobiliser, sensor supply B and C and P0217 (coolant) have no key. The app would show these codes on bikes that cannot raise them. | New keys and an R20 rule that requires `can_bus_fitted` for the CAN tag. |

Next in line (concerns, not in the ten): P0321 (the entry says "in range" about a range/performance code), P0231 to P0233 ("secondary circuit" renamed "power circuit" by the author), P0054 and P0053 ("resistance outside range" is not on the shared phrase list), P2148 (hot or swollen battery warning only in `can_ride_reason`), P2504 and P0563 (29-word fixed sentence).

## C. STOP findings (all 33)

Every STOP text says "pull over", "do not keep riding", has `can_ride_to_workshop` no, `needs_independent_review` true and no permission to ride on. No STOP level is re-decided here. All 13 newly confirmed codes were checked for accuracy and safety:

| Group | Verdict |
|---|---|
| P0524 oil pressure too low | Accurate, safe. Concerns: no sensor or wiring cause although a false reading is possible; "mechanical oil pressure tester" is a tool the source does not mention. Level stays STOP. |
| P2104, P2105, P2112 | Accurate, safe. |
| **P2111 stuck open** | **Accurate but incomplete: no instruction on how to slow down (problem 1).** |
| P2146 | Accurate; its source says "stalls". Its sibling P2147 (supply low) stays SERVICE_SOON; defensible because P2147's source also lists a weak battery, but "short to ground" would have the same effect as P2146. |
| P2300, P2301, P2302 | Accurate; same twin asymmetry as problem 5. |
| P0320, P0321, P0322, P0323 | Safe. P0321 says "in range" about a range/performance code and "plausibility check" (rider cannot read it); P0322 says "Dead pickup". The four duplicate the crankshaft codes in effect; that is fine for riders. |
| The 20 earlier STOP codes | P0201, P0261, P0262, P0351: twin asymmetry. P0231, P0233: "power circuit" is the author's reading of "secondary circuit". P0217: coolant text but no `liquid_cooled`. P0336, P0629, P0685, P0686 stay STOP with review true as decided. No other concern. |

STOP calibration: 33 of 329 is 10 percent. After the rules above are settled it could go to 33 plus 3 (P2100, P2102, P2103) or stay at 33 with P2100 to P2103 reworded. I would not add more.

## D. Validator-defeating entries (task E)

Run in process (`data/content/review_attacks_v4_20261002.py`; needs `OBDEX_DIR`). Baseline reproduced: 329 entries, 0 errors, 21 warnings, self-test 90 of 90. Each attack is a real entry with a few fields changed. **The current validator gives 0 errors for all eight.** None repeats the earlier eight.

| ID | Code | Safety property broken | What was changed | Why the validator misses it | Proposed rule |
|---|---|---|---|---|---|
| A1 | P0121 | Level understates a near-certain stall | Advice: "If you ride in traffic, the engine will stall and will not restart." plus the STALL sentence | R3 accepts any "if" in the sentence; R12 accepts any "if" before the claim. "If you ride in traffic" is always true | **Q1**: below STOP, the "if" before a stall or no-start claim must contain a real symptom (stall, power loss, rough running, hot battery and so on) |
| A2 | P0301 | Fire risk without the fuel warning | Basis "fuel seeping onto the hot engine"; advice "fuel may be seeping ... vapour can collect under the seat" | R16 knows leak, drip, spill, wet, fumes, puddle; not seep, ooze, weep, vapour, hot engine | **Q2**: fuel or vapour that seeps, collects or reaches a hot part needs the PETROL sentence |
| A3 | P0524 | Wrong direction in the diagnosis | Title and meaning say oil pressure too HIGH; causes changed to match | R6 and R14 skip every standard title that ends "Too Low" or "Too High" | **Q3**: for titles ending too low, too high, low or high, `title_en` and `meaning_en` must not say the opposite |
| A4 | P0504 | A braking code treated as minor and unreviewed | Level MONITOR, can ride yes, confidence high, review false, advice "The brake light is a minor matter" | The tag `brake_switch` allows MONITOR; only STOP, chassis, ABS tags, low confidence and petrol force review | **Q4**: any entry that talks about braking needs review true, no MONITOR, no high confidence |
| A5 | P0217 | Rider told to do something that scalds | STOP advice adds "Open the radiator cap at once to let the steam out and add cold water." | R17 checks technician hints only; for rider text it checks only the word bypass | **Q5**: opening a cap or pouring water may appear only as "do not open the cap while it is hot" |
| A6 | C0020 | Brake hydraulics implied at SERVICE_SOON | Cause "Low brake fluid or a leaking brake line"; hint "top it up if it is low" | No rule looks for brake fluid, line, pad, caliper or hydraulic; D3 says fluid loss would be STOP | **Q6**: braking hydraulics words are an error unless the source has them |
| B1 | C0037 | Owner rule broken (position-neutral) | Meaning and hint name "the left front wheel speed sensor" | R5 checks the rider title only | **Q7**: no left or right wheel in any text field of a wheel speed entry |
| B2 | P2177 | can_ride_reason contradicts level and the entry's own warning | Reason "ride normally; long trips are fine" on a lean mixture that can overheat the engine | R15 reassurance list applies to ABS only | **Q8**: a with_care entry may not permit normal or long riding |

Test of the proposed rules (same script): each catches its attack, and **none flags any of the 329 real entries** (0 false positives). Two honest limits: the false-positive test only shows the rules do not hurt today's text, and each rule is itself a pattern that a determined writer can evade. The durable answers are independent review of every STOP and braking entry (already required) and a rule that fails closed: a safety word the validator does not understand should go to a human, not pass.

Further validator gaps seen while reading (not attacked): R22 stops sentences over 25 words only in `meaning_en` and `rider_advice_en`, not in `can_ride_reason`; the idiom list has "jumps" but not "jumped", and lacks "misbehave", "pulling the bus down", "fine-tune", "run on", "sender" and "snap"; R20 does not require `can_bus_fitted`; the 7 owner-verified titles are not checked against `standard_title_en`.

## E. Cross-entry consistency (task F, all 329 entries)

**1. The same failure type in different words**
- Short circuit: "short circuit" (P0414, P0445, P0448) versus the listed "short to ground" and "short to battery supply". The standard titles do not say which, so either add "short circuit" to the shared list or name the target only when the source does.
- Resistance: "resistance outside range" (P0053, P0054) is not on the list ("resistance above threshold", "signal out of range").
- Communication: "communication fault" (U0001, U0010); "communication lost" (U0100, U0121, U0140, U0146, U0155, U0167); "communication lost (bus off)" (U0073, U0074); "bus off" only (U0075, U0076, U0077).
- "signal out of range" is used once (P2502), "intermittent circuit fault" 16 times and "circuit fault" 35 times for similar situations; 36 titles have no colon form. These are style gaps, not errors.

**2. Sibling codes with contradictory levels or can_ride values**
- P2100, P2102, P2103 (SERVICE_SOON) versus P2104 (STOP): the same effect, see problem 2.
- Cylinder 1 STOP codes versus cylinder 2 SERVICE_SOON codes on a twin (problem 5): P0201/P0202, P0261/P0264, P0262/P0265, P0351/P0352, P2300 to P2302/P2303 to P2305.
- P0522 and P0523 (oil pressure sensor, SERVICE_SOON, review false) versus P0524 (STOP): the source for P0522 says it can mean really low oil pressure, and the only stop trigger is a lamp the bike may not have.
- P2146 (STOP) versus P2147 (SERVICE_SOON): see section C.
- Known and decided, listed for completeness: P0231 and P0233 (STOP) versus P0232 (SERVICE_SOON); P0685 and P0686 (STOP) versus P0687 (SERVICE_SOON).
- P0117 versus P0118: the same "stop and let it cool" sentence in both; only P0118 carries the overheating risk (problem 9).
- P0131 (review false) versus P0132 (review true), P2503 versus P2504: review differs only because one text mentions petrol or a hot battery. Acceptable.

**3. Low and high pairs.** 44 pairs. The direction is right in all 44 (meaning, title and advice); my own check of all 90 entries with a "voltage below/above threshold" title found no meaning that says the opposite. Level, can_ride, confidence or review differ in 4 pairs (P0131/P0132, P0231/P0232, P0686/P0687, P2503/P2504); three are explained above.

**4. Engine and intake temperature direction.** All 4 temperature pairs (8 entries: P0112/P0113, P0117/P0118, P0197/P0198, P0072/P0073) say the right thing: low voltage means the engine, oil or air LOOKS hotter, high voltage means colder.

**5. can_ride versus level.** The mechanical mapping holds in all 329 entries (STOP no; SERVICE_SOON with_care or yes; MONITOR yes). Reasons that sit badly with the value: P068A ("usually rideable" with with_care), P0504 (advice says "get it fixed before riding" if the brake light fails but the value is with_care), P0633, P0512, P0513 ("do not switch off on the way").

**6. Same concern in a family.** Alternator field and lamp terminal codes: P0620, P0621, P0625, P0626, P2500, P2501. Gear position codes P0914 to P0919. "Let it cool": 12 entries (list in problem 9). Idle: 11 entries.

## F. Hindi-translatability findings

Sentence length is fine: no sentence in any rider field is over 25 words except the BATTERY sentence in P0563 and P2504 (29 words; the owner's D6 exemption). The brief says each sentence inside a canonical sentence must be 25 words or fewer, so I report it: split it as "If the battery is hot, swollen or smells of rotten eggs, stop, switch off and do not ride on. Do the same if the lights are very bright or bulbs keep blowing." (19 and 13 words).

Words the idiom list does not know: "pulling the bus down" (8 entries), "misbehave" (7), "fine-tune" (4), "jumped" (P033F), "run on" (P0617), "sender" (P0460, P0464), "snap" (P0507). Probably fine but a translator should confirm: "hesitate" (17 entries), "chafed" (22), "drift" (8), "wiggle" (hints). The 9 fixed sentences themselves are plain and translatable.

## G. Title triage (task G)

File: `data/content/held_back_triage_v2_20261002.csv` (65 rows, with both titles, the type, my proposed position-neutral or semantic title where the type allows it, confidence, and the evidence).

My rules: **WORDING** = same component and failure kind, different words. **POSITION** = same fault, different wheel, bank or sensor number (no row was a pure position difference: left or right differences always came with a different fault or numbering). **NUMBERING** = the OBDex title for this code appears under a different code number in Wal33D (edition shift), shown by a title match. **DIFFERENT_FAULT** = the titles name different faults and no offset explains it. I added a fifth value, **NO_SECOND_SOURCE**, for the 17 rows where Wal33D has no row at all, because nothing can be compared.

| Type | Rows |
|---|---:|
| WORDING | 11 (P0134, P0140, P0325, P0327, P0328, P0351, P0352, P0418, P0446, P0449, P0505) |
| POSITION | 0 |
| NUMBERING | 4 (C0035, C0040, C0045, C0050) |
| DIFFERENT_FAULT | 33 |
| NO_SECOND_SOURCE | 17 (C0056, C0060, C0066, C0080, C0110, C0111, C0112, C0121, C0220, C0225, C0234, C0235, C0238, C0241, C0242, C0245, C0246) |

**What the C-block shows (my hypothesis, tested against the data but not against the web):** Wal33D uses three codes per wheel in C0030 to C003F (tone wheel, sensor, supply: C0030 left front tone wheel, C0031 left front sensor, C0032 its supply, C0033 to C0035 the same for right front, C0036 to C0038 left rear, C0039 to C003B right rear, C003C to C003E rear). The OBDex entries C0037 to C003F follow that layout, which is why they agree with Wal33D. But OBDex C0030 to C0036 and C0040 to C0066 follow an older layout (several fault kinds per wheel). So OBDex contains **both editions**, and it lists the same fault twice (left rear sensor at C0037 and at C0045; right rear at C003A and at C0050). The seed therefore mixes editions: C0035 (old) next to C0037 to C003F (new). One public lookup on the chassis block should settle all 47 chassis rows.

**DIFFERENT_FAULT rows (for the owner's assistant to verify on the public web; no entry is to be written for them):**

| Code | OBDex title | Wal33D title | Confidence | Why it is not a wording or numbering difference |
|---|---|---|---|---|
| C0021 | ABS Pump Motor Circuit Range/Performance | Brake Booster Performance | medium | OBDex: ABS pump motor circuit range/performance. Wal33D: brake booster performance. Wal33D C0020 (pump motor control) agrees with OBDex, so the two sources split after C0020. |
| C0022 | ABS Pump Motor Circuit Low | Brake Booster Solenoid | medium | OBDex: ABS pump motor circuit low. Wal33D: brake booster solenoid. |
| C0023 | ABS Pump Motor Circuit High | Stop Lamp Control | medium | OBDex: ABS pump motor circuit high. Wal33D: stop lamp control. |
| C0025 | ABS Pump Motor Stalled | Brake Pedal Feedback Pressure Sensor Circuit | medium | OBDex: ABS pump motor stalled. Wal33D: brake pedal feedback pressure sensor circuit. |
| C0030 | Left Front Wheel Speed Sensor Circuit Range/Performance | Left Front Tone Wheel | medium | Old seven-code left front series in OBDex (range, low, high, erratic, no signal, malfunction, intermittent). Wal33D has three codes per wheel (tone wheel, sensor, supply): here the left front tone wheel. Two editions of the standard, unverified. |
| C0031 | Left Front Wheel Speed Sensor Circuit Low | Left Front Wheel Speed Sensor | medium | Same wheel, but OBDex says circuit low and Wal33D says plain wheel speed sensor. Two editions, unverified. |
| C0032 | Left Front Wheel Speed Sensor Circuit High | Left Front Wheel Speed Sensor Supply | medium | Same wheel, OBDex circuit high versus Wal33D sensor supply. Two editions, unverified. |
| C0033 | Left Front Wheel Speed Sensor Signal Erratic | Right Front Tone Wheel | medium | OBDex: left front signal erratic. Wal33D: right front tone wheel. Wal33D follows the three-per-wheel layout (C0033 right front tone wheel, C0034 right front sensor, C0035 right front supply). |
| C0034 | Left Front Wheel Speed Sensor No Signal | Right Front Wheel Speed Sensor | medium | OBDex: left front no signal. Wal33D: right front wheel speed sensor. Three-per-wheel layout in Wal33D. |
| C0036 | Left Front Wheel Speed Sensor Circuit Intermittent | Left Rear Tone Wheel | medium | OBDex: left front circuit intermittent. Wal33D: left rear tone wheel. Three-per-wheel layout in Wal33D (C0037 left rear sensor, C0038 left rear supply agree with OBDex). |
| C0041 | Right Front Wheel Speed Sensor Circuit Range/Performance | Brake Pedal Switch B | medium | OBDex: right front circuit range/performance. Wal33D: brake pedal switch B (Wal33D C0040 to C0046 is a brake pedal and pressure block). |
| C0042 | Right Front Wheel Speed Sensor Circuit Low | Brake Pedal Position Sensor Circuit A | medium | OBDex: right front circuit low. Wal33D: brake pedal position sensor circuit A. |
| C0043 | Right Front Wheel Speed Sensor Circuit High | Brake Pedal Position Sensor Circuit B | medium | OBDex: right front circuit high. Wal33D: brake pedal position sensor circuit B. |
| C0044 | Right Front Wheel Speed Sensor Signal Erratic | Brake Pressure Sensor A | medium | OBDex: right front signal erratic. Wal33D: brake pressure sensor A. |
| C0046 | Right Front Wheel Speed Sensor Circuit Intermittent | Brake Pressure Sensor A/B | medium | OBDex: right front circuit intermittent. Wal33D: brake pressure sensor A/B. |
| C0052 | Left Rear Wheel Speed Sensor Circuit Low | Steering Wheel Position Sensor Signal A | medium | OBDex: left rear circuit low. Wal33D: steering wheel position sensor signal A (a steering block). A bike has no such sensor. |
| C0053 | Left Rear Wheel Speed Sensor Circuit High | Steering Wheel Position Sensor Signal B | medium | OBDex: left rear circuit high. Wal33D: steering wheel position sensor signal B. |
| C0054 | Left Rear Wheel Speed Sensor Signal Erratic | Steering Wheel Position Sensor Signal C | medium | OBDex: left rear signal erratic. Wal33D: steering wheel position sensor signal C. |
| C0055 | Left Rear Wheel Speed Sensor No Signal | Steering Wheel Position Sensor Signal D | medium | OBDex: left rear no signal. Wal33D: steering wheel position sensor signal D. |
| C0061 | Right Rear Wheel Speed Sensor Circuit Range/Performance | Lateral Acceleration Sensor | medium | OBDex: right rear circuit range/performance. Wal33D: lateral acceleration sensor (a vehicle dynamics block). |
| C0062 | Right Rear Wheel Speed Sensor Circuit Low | Longitudinal Acceleration Sensor | medium | OBDex: right rear circuit low. Wal33D: longitudinal acceleration sensor. |
| C0063 | Right Rear Wheel Speed Sensor Circuit High | Yaw Rate Sensor | medium | OBDex: right rear circuit high. Wal33D: yaw rate sensor. |
| C0064 | Right Rear Wheel Speed Sensor Signal Erratic | Roll Rate Sensor | medium | OBDex: right rear signal erratic. Wal33D: roll rate sensor. |
| C0065 | Right Rear Wheel Speed Sensor No Signal | Vertical Acceleration Sensor | medium | OBDex: right rear no signal. Wal33D: vertical acceleration sensor. |
| C0081 | Wheel Speed Mismatch (Rear Axle) | ABS Malfunction Indicator | low | OBDex: wheel speed mismatch (rear axle). Wal33D: ABS malfunction indicator. A bike has no axle pair. |
| C0099 | ABS Control Module Internal Fault | 4WD/AWD Rear Differential Unit Actuator A Position Sensor A | low | OBDex: ABS control module internal fault. Wal33D: a 4WD rear differential position sensor. Car-only in Wal33D. |
| P0421 | Warm Up Catalyst Efficiency Below Threshold (Bank 1) | Catalyst 1 Efficiency Below Threshold Bank 1 | low | OBDex: warm-up catalyst. Wal33D: "Catalyst 1" (P0422 is "Catalyst 2"). May be the same catalyst under a new naming scheme, but that is a guess. Not a small-bike code; low priority. |
| P2119 | Throttle Closed Position Performance | Throttle Actuator A Control Throttle Body Range/Performance | low | OBDex: throttle closed position performance. Wal33D: throttle body range/performance. Different fault names; P2109 already covers the minimum stop. |
| P2230 | Barometric Pressure Circuit Low | Barometric Pressure Sensor A Circuit Intermittent/Erratic | medium | OBDex repeats "Barometric Pressure Circuit Low" (the title of P2228). Wal33D says intermittent/erratic, which fits the P2227 to P2230 sequence (range, low, high, intermittent). Likely an OBDex duplicate. |
| U0168 | Lost Communication with Vehicle Immobilizer Control Module | Lost Communication With Vehicle Security Control Module | medium | OBDex repeats the immobiliser title of U0167 (spelled with z). Wal33D says vehicle security control module. Likely an OBDex duplicate. |
| U0327 | Software Incompatibility with Powertrain Control Module | Software Incompatibility With Vehicle Security Control Module | medium | OBDex says powertrain control module (that is U0301). Wal33D says vehicle security control module, which follows U0326 (immobiliser). Likely an OBDex error. |
| U0408 | Invalid Data Received from Vehicle Immobilizer Control Module | Invalid Data Received From Throttle Actuator A Control Module | low | OBDex: immobiliser control module. Wal33D: throttle actuator A control module. No block pattern explains it. |
| U0421 | Invalid Data Received from Throttle/Pedal Position Sensor | Invalid Data Received From Suspension Control Module A | low | OBDex: throttle/pedal position sensor. Wal33D: suspension control module A. No block pattern explains it. |

**NUMBERING rows** (one lookup each; the proposed title is valid only under the older edition, and under the newer edition C0040 and C0045 are brake codes):

| Code | OBDex title | Wal33D title | Where OBDex title sits in Wal33D | Confidence |
|---|---|---|---|---|
| C0035 | Left Front Wheel Speed Sensor Circuit Malfunction | Right Front Wheel Speed Sensor Supply | OBDex title (left front circuit malfunction) is the same fault as Wal33D C0031 (left front wheel speed sensor). Wal33D C0035 is "right front wheel speed sensor supply". So the sources do NOT both say circuit: Wal33D says supply, and the wheel differs. A position-neutral title is only safe if the owner confirms the edition. | low |
| C0040 | Right Front Wheel Speed Sensor Circuit Malfunction | Brake Pedal Switch A | OBDex title (right front circuit malfunction) equals Wal33D C0034 (right front wheel speed sensor). Wal33D C0040 is "brake pedal switch A". Do not write until the edition is confirmed: under the newer edition this is a brake pedal code. | low |
| C0045 | Left Rear Wheel Speed Sensor Circuit Malfunction | Brake Pressure Sensor B | OBDex title (left rear circuit malfunction) equals Wal33D C0037, and OBDex itself also lists the same fault at C0037, so OBDex holds one fault under two numbers (two editions mixed). Wal33D C0045 is "brake pressure sensor B". | low |
| C0050 | Right Rear Wheel Speed Sensor Circuit Malfunction | (none) | OBDex title (right rear circuit malfunction) equals Wal33D C003A, and OBDex also lists it at C003A. Wal33D has no generic row for C0050. | low |

**WORDING rows** are safe to use with the proposed titles in the CSV once the owner's assistant has seen them; six of them (P0351, P0352, P0325, P0327, P0328, P0505) are owner-verified titles; the seventh, P0326, agrees between the sources but is stored with another wording than its siblings (see section J).

## H. Statistics (task H)

Each cell reads: CONCERN rows / FAIL rows of rows asked (CONCERN rate). Check 12 is asked only of the wheel speed and ABS entries.

| Check | New, random 100 | Reworked, random 30 | Targeted: all 33 STOP | New, all reviewed (129) | Reworked, all reviewed (60) |
|---|---|---|---|---|---|
| 1 Meaning matches title | 4 / 0 of 100 (4%) | 3 / 0 of 30 (10%) | 4 / 0 of 33 (12%) | 6 / 0 of 129 (5%) | 7 / 0 of 60 (12%) |
| 2 Causes plausible | 4 / 0 of 100 (4%) | 0 / 0 of 30 (0%) | 2 / 0 of 33 (6%) | 6 / 0 of 129 (5%) | 0 / 0 of 60 (0%) |
| 3 Advice safe, no reversal | 0 / 0 of 100 (0%) | 3 / 0 of 30 (10%) | 1 / 0 of 33 (3%) | 1 / 0 of 129 (1%) | 3 / 0 of 60 (5%) |
| 4 Level correct | 1 / 0 of 100 (1%) | 1 / 0 of 30 (3%) | 7 / 0 of 33 (21%) | 6 / 0 of 129 (5%) | 4 / 0 of 60 (7%) |
| 5 No unsupported part | 5 / 0 of 100 (5%) | 0 / 0 of 30 (0%) | 1 / 0 of 33 (3%) | 8 / 0 of 129 (6%) | 0 / 0 of 60 (0%) |
| 6 Failure wording and glossary | 5 / 0 of 100 (5%) | 0 / 0 of 30 (0%) | 0 / 0 of 33 (0%) | 6 / 0 of 129 (5%) | 0 / 0 of 60 (0%) |
| 7 Rider can understand | 4 / 0 of 100 (4%) | 0 / 0 of 30 (0%) | 1 / 0 of 33 (3%) | 7 / 0 of 129 (5%) | 7 / 0 of 60 (12%) |
| 8 can_ride sensible | 0 / 0 of 100 (0%) | 1 / 0 of 30 (3%) | 0 / 0 of 33 (0%) | 0 / 0 of 129 (0%) | 1 / 0 of 60 (2%) |
| 9 Canonical sentences, 25 words | 2 / 0 of 100 (2%) | 0 / 0 of 30 (0%) | 0 / 0 of 33 (0%) | 2 / 0 of 129 (2%) | 0 / 0 of 60 (0%) |
| 10 Hindi-translatable | 8 / 0 of 100 (8%) | 3 / 0 of 30 (10%) | 0 / 0 of 33 (0%) | 10 / 0 of 129 (8%) | 5 / 0 of 60 (8%) |
| 11 applies_when correct | 18 / 0 of 100 (18%) | 4 / 0 of 30 (13%) | 1 / 0 of 33 (3%) | 23 / 0 of 129 (18%) | 11 / 0 of 60 (18%) |
| 12 Wheel speed position-neutral | 5 / 0 of 13 (38%) | 0 / 0 of 2 (0%) | - | 7 / 0 of 21 (33%) | 1 / 0 of 10 (10%) |
| Entries with at least one concern or fail | 45 of 100 (45%) | 13 of 30 (43%) | 14 of 33 (42%) | 64 of 129 (50%) | 27 of 60 (45%) |

Reading the table:
- **New versus reworked.** New entries have more concerns on causes (4 %), unsupported parts (5 %) and failure wording (5 %); the random 30 reworked entries have none on those three but 3 of 30 on advice (the idle sentences of P0506 and P0509, and P0633) and 3 of 30 on Hindi. The reworked group is cleaner on facts, not on rider advice.
- **Check 11 (`applies_when`) is the single largest source of concerns** (34 rows, 18 percent of the new and 18 percent of the reworked entries). It is a rule problem, not an author problem, and one rule change removes most of it.
- **No FAIL anywhere.** The 12 checks on the 33 STOP entries gave 7 concerns on level (the twin asymmetry), none on advice except P2111.
- **What the sample can and cannot show.** With n = 100, a defect present in 3 percent of entries is missed with probability 0.97^100 = 5 percent; present in 1 percent, missed 37 percent. With n = 30, a 3 percent defect is missed 40 percent of the time, and only defects above about 10 percent (missed 4 percent) are reliably seen. Zero FAIL in 129 new entries means the true FAIL rate is below about 2.3 percent with 95 percent confidence (rule of three). The STOP group is the whole population, so its numbers are exact. One reviewer who is not a mechanic cannot see workshop facts (for example whether a P0200 on a twin really keeps running), so every "PASS" means "no problem I could find from the source and the rubric", not "verified".
- **The author's checks.** Full-population checks that I ran on all 329 entries: field limits (0 violations), sentence length (2 exempt), level and can_ride mapping (0 violations), canonical sentences (STALL, PETROL, ABS, NETWORK all word for word where the text needs them), fix log completeness (0 unlogged changes). Source support of causes: 52 causes in 43 entries use words that are not in the source (mostly "Broken wiring or loose connector" and "Fault inside the ECU"); harmless, but not source-derived.

## I. Recommendation: may the author proceed?

**Yes after these rule changes**, for both the Hindi pass and the basic-tier pilot, with two groups held back.

Before the Hindi pass (these change English that Hindi copies):
1. Fix P2111 (how to slow down) and decide P2100 to P2103 (reword or STOP).
2. Owner merges the idle sentences, and splits the 29-word BATTERY sentence. These are fixed sentences that will be translated once and reused 12 times.
3. Replace the "runs very hot" sentence (12 entries) and fix P0633, P0512, P0513, P0117.
4. Store the 7 owner-verified titles in `title_overrides.csv`.
5. Add the idioms of section F to R22 (and apply the fixes in `review_flags`, checks 10).

**Hold out of the Hindi pass and the pilot** until answered: all chassis wheel-speed entries (C0035, C0037 to C003F), P0914 to P0919, the alternator field and lamp terminal codes (P0620, P0621, P0625, P0626, P2500, P2501), and the cylinder 1 STOP wording until the owner has decided the twin question.

Before the basic-tier pilot (9,100 codes), add to the validator: Q1 to Q8, a rule that requires `can_bus_fitted` for the CAN tag and the new `applies_when` keys, and a rule that checks `standard_title_en` against the verified title list. Run a random review of 100 pilot entries with the same 12 checks; expect about 45 percent of entries to carry at least one concern until the `applies_when` keys exist, and about one third afterwards (38 percent of the 189 reviewed entries have a concern that is not about `applies_when`). The title method (two agreeing sources) held for the engine and network families but failed for the chassis block, so use it only with an edition check.

## J. Entries that contradict owner decisions

- **C0035 premise.** The owner wrote that the sources agree it is a wheel speed sensor circuit code and differ only on which wheel. In the data Wal33D reads it as a right front wheel speed sensor **supply** code. The entry's "circuit" may be the wrong kind of fault as well as the wrong wheel.
- **Position-neutral wheel speed entries.** The rider title and meaning of C0035 are neutral. C0037, C0038, C003A, C003B, C003C, C003D and C003E say "rear" (a front or rear claim, not left or right), and `standard_title_en` of every chassis entry stores "Left Front", "Left Rear" or "Right Rear". If the owner reads "position-neutral" as "no front or rear either", seven entries need new wording.
- **The seven owner-verified titles** (P0351, P0352, P0325, P0326, P0327, P0328, P0505) stay as entries, but the stored `standard_title_en` is still the OBDex wording for all seven (`title_basis` obdex). For example P0351 keeps "(Cylinder 1)", P0325, P0327, P0328 lack "or Single Sensor", P0326 uses another sensor name than its siblings, P0505 says "Idle Air Control".
- **Canonical sentences of 25 words or fewer.** P0563 and P2504 carry the BATTERY sentence of 29 words as one sentence (decided in D6, still against the brief's per-sentence rule).
- **The 13 STOP codes** are all STOP in the data and the table: no contradiction.
- Not contradicted: NETWORK sentence (word for word in all 18 bus, gateway and software entries), the ABS sentence (word for word in all 13 ABS and wheel-speed entries), the TWO-CASE sentence, the downgrade decisions.

## Additions beyond the brief

1. **Full-population mechanical checks** (not only the sample): limits, level and can_ride mapping, sentence length, canonical sentence variants, fix-log completeness against the earlier commit `d923c4a` (0 unlogged changes), a source-support check for causes. Reason: a sample cannot show absence of a defect; these checks can.
2. **A reusable attack script with proposed rules Q1 to Q8 and a false-positive test** on all 329 entries. Reason: the owner can adopt the rules as written, with proof that they do not break today's text.
3. **A fifth triage class, NO_SECOND_SOURCE, and an evidence column** in the triage CSV, plus the finding that OBDex holds both chassis editions. Reason: the four classes in the brief could not describe a missing second source honestly, and the edition finding explains 47 rows with one question.
4. **Three findings outside the seeded sample, shown separately** (P0117, P0504, P0522 and the four owner-title entries P0325, P0326, P0327, P0505), so the statistics stay unbiased while the findings are not lost.
5. **Reproducible sampling script** (`review_sample_v4_20261002.py`, seed 20261002) and **the flag builder** (`review_flags_build_v4_20261002.py`), so the flags can be re-derived and corrected.
6. **Risks noticed:** (a) the new rules are patterns and can be evaded; (b) `standard_title_en` may leak positions to the app; (c) `can_bus_fitted` is defined but unused, so the app cannot yet hide bus faults on bikes without CAN; (d) the stored `mil`, `emissions_relevant` and `limp_possible` flags are still unchecked judgement (I found no contradiction among siblings, but nobody has verified them); (e) the same reviewer type (an AI that is not a mechanic) wrote and reviewed; a workshop check of the STOP list and of P2111, P2100 to P2104, P0232 is still needed.

## Files in this review

- `docs/content/REVIEW_REPORT_V4_20261002.md` (this report)
- `data/content/review_flags_v4_20261002.csv` (code, check, verdict, reason, suggested_fix)
- `data/content/held_back_triage_v2_20261002.csv` (65 rows)
- `data/content/review_sample_v4_20261002.py` and `.json` (seed 20261002)
- `data/content/review_attacks_v4_20261002.py` and `.json` (six attacks, two bonus attacks, proposed rules Q1 to Q8, false-positive test)
- `data/content/review_flags_build_v4_20261002.py` and `review_triage_build_v4_20261002.py` (how the two CSVs were built)
