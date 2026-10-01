# Review report: batch 1 (140 entries: 40 pilot + 100 new)

Independent review, RUN_MODE = review, RUN_SCOPE = batch 1. Date: 2026-10-01.
Reviewed branch: `content/seed-20261001` (head `d923c4a`). Review output branch: `content/review-batch1-20261001`.
Source: OBDex commit `bc58b0eb7273226a1aabae98e956b70b8362bda1` (re-cloned by this reviewer; same commit the author used).
Sample seed: `20261001` (reproduce with `data/content/review_sample_batch1_20261001.py`).
No entry was edited. `main` was not touched. Nothing outside `data/content/` and `docs/content/` changed.

I am not a mechanic and nobody on this project is. Every judgement below is reasoned engineering judgement checked against the OBDex text, not workshop experience. Where it matters I say how sure I am.

## In plain English (for a non-coder)

I re-read 68 of the 140 entries as if I had to hand each one to a rider: all 28 STOP entries, 30 random other batch 1 entries and 10 random pilot entries. I judged each on 10 questions (680 answers) and compared the text with the source, not with the author's own notes.

**The facts are in good shape; the wording and some calls are not yet ready to copy 225 more times.**
- *Facts:* the meaning matches the standard title in 65 of 68 entries and nothing was wrong in direction (low versus high, hotter versus colder). The 9 sampled pilot entries that the first review had flagged are all fixed.
- *Advice and level:* 3 entries have advice that contradicts itself (FAIL), 13 level questions remain, and between a quarter and a third of entries have wording that a rider or a Hindi translator will struggle with.
- *Counts:* 583 PASS, 94 CONCERN, 3 FAIL out of 680 answers. 19 of 68 entries are clean, 46 have only concerns, 3 have a FAIL.

**STOP calibration (your worry about 22 in 100): you were partly right.** I would downgrade **7 of the 28 STOP entries** to SERVICE_SOON: P0604, P0605, P0606 (the ECU internal faults; the source itself says the ECU runs on in limp-home) and P0202, P0264, P0265, P0352 (cylinder 2 faults, which exist only on twins, where the engine keeps running on the other cylinder). That takes batch 1 from 22 STOP to 17, and the whole 140 from 28 to 21. I would keep the other 21, but 5 of them are borderline and need a mechanic (P0232, P0629, P0336, P0685, P0686). I found no entry that should be upgraded to STOP. The high share is mostly a result of the selection (the engine-critical circuits came first), not of an over-nervous author.

**The validator can still be fooled.** I wrote 6 new bad entries (plus 2 bonus ones). The current validator accepted all 8 with zero errors. They include an entry that says the engine "will shut off suddenly and will not restart" at the low SERVICE_SOON level, an ABS entry that adds "no need to ride differently in the rain", and a fuel-leak entry that says "wipe it off and keep riding". Seven proposed new rules catch all of them (an eighth, on warning-lamp flags, guards later batches), and on the 140 real entries they flag only 3 real problems (P0633, P0512, P0513: "may not restart" claimed at SERVICE_SOON) plus the 7 intended STOP downgrades.

**Recommendation: batches 2 to 4 may proceed after the rule changes in section G, not before.** The most important: one single "if it stalls" sentence for every entry, the STOP table as a locked list, the new validator rules, an ABS sentence for the CAN bus entries, and a mechanic's look at five pump and ECU STOP calls. The ABS and chassis family is almost unreviewed (one ABS entry in my sample), so it needs its own review after it is written.

## A. Counts per verdict (68 entries reviewed, 680 rows)

Rows: `data/content/review_flags_batch1_20261001.csv` (code, check, verdict, reason, suggested_fix).

| Check | PASS | CONCERN | FAIL |
|---|---:|---:|---:|
| 1 Meaning matches the standard title and structure | 65 | 3 | 0 |
| 2 Causes plausible for a small bike, not car-only | 60 | 8 | 0 |
| 3 Advice free of reversals, circular advice, rider danger | 60 | 5 | 3 |
| 4 Level correct under the rubric (ABS rule) | 55 | 13 | 0 |
| 5 No part or hardware the source does not support | 66 | 2 | 0 |
| 6 Shared failure wording and glossary used | 67 | 1 | 0 |
| 7 Understandable to a rider | 49 | 19 | 0 |
| 8 `can_ride_to_workshop` value and reason | 60 | 8 | 0 |
| 9 Standard sentences used where required | 55 | 13 | 0 |
| 10 Hindi-translatability | 46 | 22 | 0 |
| **Total** | **583** | **94** | **3** |

| Group | Entries | Clean | Concern only | FAIL |
|---|---:|---:|---:|---:|
| All 28 STOP entries | 28 | 3 | 25 | 0 |
| 30 random batch 1 non-STOP | 30 | 9 | 18 | 3 |
| 10 random pilot non-STOP | 10 | 7 | 3 | 0 |

The pilot sample confirms the earlier fixes. First review: 26 of 40 pilot entries had a concern. Now 3 of 10 sampled pilot entries have one, and none of those three repeats an earlier finding (P0302 has a new wording issue created by the fix, P0340 uses a sentence variant, P0850 has a long meaning). Of the 10 sampled, 9 had been flagged and fixed (P0135, P0302, P0122, P0123, P0131, P0132, P0340, P0850, U0121) and all fixes are present; P0112 had been clean.

The three FAILs are one problem seen three times: **P0506, P0510, P0519** say "if it stalls at stops, avoid traffic and do not keep riding". "Avoid traffic" means keep riding, "do not keep riding" means stop; a rider cannot do both. The same sentence is in 10 idle entries (P0505, P0506, P0508, P0509, P050A, P050D, P0510, P0511, P0518, P0519).

## B. The ten most serious problems

| # | Codes | Problem | Fix |
|---|---|---|---|
| 1 | P0507 (and the idle family P0505 to P0519) | P0507 lists "throttle not closing fully" as a cause (not in the source), a real hazard because the bike keeps pulling when you slow down, yet the only stop trigger is "if the idle stays high ... avoid traffic", which is true whenever the code is shown. The 10 idle entries also carry the self-contradicting sentence (three FAILs, section A). | Use the STALL sentence for the idle family; add to P0507 "If the throttle does not snap fully shut when you let go, do not ride; have it checked first." |
| 2 | U0001 to U0008 (found in section E, not in my sample) | All 8 CAN bus entries say "Meters, lamps or safety systems may stop working; ride carefully". A bus fault can switch ABS off, but the rider is not told brakes still work and a wheel can lock. They are marked `needs_independent_review` false and confidence medium, while U0121 (ABS) is true. | Add a conditional ABS sentence ("If your ABS lamp stays on, ..."), set review true. |
| 3 | P0232, P0629 (also P0231, P0233) | STOP rests on "the pump may stop", but the OBDex text for P0232 says a stuck relay or short that keeps the pump powered (no stall), and an open circuit would not read high. P0233's source speaks of a transfer or lift pump, which small bikes do not have. P0231 and P0233 are marked confidence medium; they should be low. | Mechanic to confirm. Until then keep STOP (a wrong STOP costs a workshop visit, a wrong downgrade leaves a pump failure unwarned), remove "open circuit" from P0232, set confidence low. |
| 4 | P0604, P0605, P0606, P0202, P0264, P0265, P0352 | STOP over-calls (section C). | Downgrade to SERVICE_SOON. |
| 5 | 6 stall sentences (section E1) | The rider is told "do not keep riding" after one stall in some entries and after "more than once" in others. | One sentence, word for word. |
| 6 | P0561 | Stop trigger "stop and switch off" is weaker than the P0563 wording ("stop, switch off and do not ride on"), depends on "lights flicker badly" (hard to act on at night), and there is no stall warning although P0560 and P0562 warn the engine will stop on a flat battery. | BATTERY stop wording plus STALL. |
| 7 | P068B (also P0687, P068A, P0688 to P0690) | The TWO-CASE sentence (stall, power loss, no start) does not fit a relay that releases late. The real effect, a battery that drains because the ECU stays powered, was removed as "unsupported", but the OBDex description says exactly that ("keeps the ECU powered too long after key-off, drains the battery"). The validator only warns when a claim is found in the description alone, so the author deleted a supported claim. | Restore the battery sentence; stop using TWO-CASE where stalls are not plausible. |
| 8 | P0633, P0512, P0513 | `can_ride_reason` says "it may not restart", a no-start claim in a SERVICE_SOON entry. Rule R3 misses it because its pattern needs the word "start" on its own. | Proposed rule R12 (section D); reword to "do not switch off on the way". |
| 9 | P0300, P0301, P0302, P0263, P0266; P0350, P0351, P0352 | "Reduce load" (engine load? luggage? electrical?) and "fair share of the work" are unclear and will translate badly in five common misfire and balance entries, two of them anchors. "Run on one cylinder" (coil entries) means nothing to the owner of a single-cylinder bike, the main target. | "Ride gently and avoid hard acceleration"; "misfire, lose power or stop". |
| 10 | P0324 to P0329 (knock), P0340 to P0344 (camshaft), P0510, P0195 to P0199 (oil temperature) | Hardware that many Indian bikes do not have, with no `applies_when`, so the app would show a code the bike cannot raise. Also unchecked: the `mil`, `emissions_relevant` and `limp_possible` flags differ without a stated rule inside the ECU power relay family (P0685 true/true/true, P0687 true/false/false, P0688 true/true/true). | New `applies_when` keys (`knock_sensor_fitted`, `camshaft_sensor_fitted`, `oil_temp_sensor_fitted`); a flag rule per tag. |

## C. STOP calibration (all 28 STOP entries)

How I judged. STOP is justified when, **if the fault the code names is real and present**, the engine on a typical single-cylinder bike would stop or lose all power suddenly, fuel could leak, or braking or steering is hit. "May" cases that only reduce power or only matter at the next start are SERVICE_SOON. I also weighed the cost of being wrong: a wrong STOP costs a workshop visit and some trust; a wrong downgrade leaves a rider unwarned. So where I doubt a call but cannot show it is wrong, I keep STOP and say so.

`can_ride_to_workshop` agrees in all 28 (STOP gives `no`, as D4 requires). The seven downgrades would change it to `with_care`.

| Code | Level now | My call | Confidence | Reason |
|---|---|---|---|---|
| P0201 | STOP | **keep** | high | Single cylinder: an open or shorted injector circuit leaves the engine without fuel. The source says the cylinder runs without fuel. |
| P0200 | STOP | **keep** | medium | Same, no cylinder given (applies to singles). |
| P0261, P0262 | STOP | **keep** | high | Cylinder 1 injector circuit low or high, same effect. |
| P0202 | STOP | **downgrade** to SERVICE_SOON | medium | Cylinder 2 exists only on twins; the engine keeps running on cylinder 1 with less power and vibration. P0302 (misfire cylinder 2, same effect from a dead coil) is SERVICE_SOON; STOP here contradicts it. |
| P0264, P0265 | STOP | **downgrade** | medium | As P0202. |
| P0351 | STOP | **keep** | high | Single: no spark, engine stops and will not restart. |
| P0350 | STOP | **keep** | medium | No cylinder given (applies to singles). |
| P0352 | STOP | **downgrade** | medium | As P0202. |
| P0335 | STOP | **keep** | high | The source says the engine will not start or will stall. |
| P0337, P0338, P0339 | STOP | **keep** | high | Crankshaft signal low, high, intermittent: sudden stop is the textbook effect. |
| P0336 | STOP | **keep, borderline** | low-medium | A performance fault usually lets the engine run, but crank signal loss ends a ride without warning. SERVICE_SOON with the STALL sentence would also be defensible. |
| P0230 | STOP | **keep** | medium | Pump control circuit fault: a pump that is off stops the engine. |
| P0231 | STOP | **keep** | medium | Pump circuit voltage below expected: pump weak or off. Confidence of the entry should be low (the word "secondary" is unexplained by the source). |
| P0232 | STOP | **keep for now, verify** | low | The entry says the pump may stop; the source says the pump stays powered. See problem 3. |
| P0233 | STOP | **keep** | medium | An intermittent drop-out of the only pump stops the engine. The source speaks of a transfer pump; confidence should be low. |
| P0627, P0628 | STOP | **keep** | medium | Pump control circuit open or low: the pump does not run (the source: "with no pump operation the engine cannot run"). |
| P0629 | STOP | **keep for now, verify** | low | Control circuit high more often leaves the pump running than off. Same asymmetric-cost reasoning as P0232. |
| P0217 | STOP | **keep** | medium | An active overheating condition can seize the engine within minutes and the advice (pull over, let it cool) is the right one. **Rubric gap:** the rubric does not name overheating and says engine damage is SERVICE_SOON. Add "an active condition that destroys the engine within minutes (overheating, no oil pressure)" to STOP. |
| P0685, P0686 | STOP | **keep, borderline** | low | The source says the effect is on shutdown or at the next start, not a mid-ride stall. An intermittent open on a rare relay could still cut the ECU's power suddenly. Hedged "(if fitted)", so few bikes will show it. |
| P0604, P0605, P0606 | STOP | **downgrade** | medium | A processor, RAM or ROM fault has to be running to be stored. The OBDex text for P0605 and P0606 says the ECU defaults to limp-home with reduced function, not to stopping. P0601, P0602, P0603 and P0607 (same family) are SERVICE_SOON. "ECU may fail" is speculation. |

Totals: downgrade 7, keep 21 (16 clear, 5 borderline: P0336, P0232, P0629, P0685, P0686). **Batch 1: 22 STOP becomes 17 (12 if the borderline five later go). Pilot: 6 becomes 4. Whole 140: 28 becomes 21.**

Upgrades considered and rejected: P0507 (stuck throttle as a cause; better as a stop trigger inside SERVICE_SOON), P0561 (voltage instability; better fixed by the stop trigger and the STALL sentence), P0615 to P0617 (starter relay; advice already says switch off at once).

The share of STOP in batch 1 is high because the ranking put the engine-critical circuits first (injector, coil, crankshaft, pump). The remaining 225 codes are mostly MONITOR or SERVICE_SOON (evaporative, secondary air, chassis, network), so I expect the final share to be well below 15 percent. That is an estimate, not a measurement.

One more point for the app owner: the STOP text says "Pull over safely, switch off". A rider who reads the code at home with the engine off cannot pull over. If the app knows whether the fault is active or stored, two advice versions (riding, parked) would be clearer and would make STOP less tiring.

## D. Trying to defeat the validator

Script: `data/content/review_validator_defeat_20261001.py` (runs the real `validate_seed.py` in process on each defective entry, then my proposed rules, which live only in that file; the validator itself is unchanged). Each defect is a copy of a real entry with only the shown fields changed. Run: `OBDEX_DIR=/tmp/obdex python3 data/content/review_validator_defeat_20261001.py`.

Baseline: 140 real entries, 0 errors, 1 warning (P0563), as in the author's report.

| # | Safety property broken | Entry changed | Text that gets through | Current validator | Proposed rule |
|---|---|---|---|---|---|
| D1 | A stall claim below STOP | P0130 (SERVICE_SOON, can ride yes) | "The engine will shut off suddenly at speed and will not restart. Get it checked soon." Ride reason: "keep riding to the workshop" | **accepted, 0 errors**. R3's word list has "stall", "cut out", "dies" but not "shut off", "stops running", "restart". | R12 (wider claim list) |
| D2 | STOP calibration inverted | P0627 (fuel pump control circuit open) set to SERVICE_SOON with the TWO-CASE sentence | "If the engine runs normally, have it checked soon; if it stalls or will not start, do not keep riding." | **accepted.** The tag map allows STOP or SERVICE_SOON for fuel pump codes, and the text is conditional. | R13 (locked STOP table) |
| D3 | Direction reversed outside the meaning | P0118 (engine temperature HIGH voltage: engine looks colder) | Advice: "The engine looks hotter than it is ... There is no risk of overheating", ride reason "safe in traffic and heat". The meaning and title stay correct. | **accepted.** R6 reads only title and meaning. This one tells the rider the opposite of the truth: the fan may stay off. | R14 (direction words in every rider field) |
| D4 | ABS reassurance in the second sentence | U0121 (ABS communication lost) | Standard sentence, then "There is no need to ride differently in the rain." Ride reason "fine in the rain and at full speed". | **accepted.** R5 bans three phrases only. | R15 (no reassurance; second sentence from a closed list) |
| D5 | Fuel leak and fire risk without the word "smell" | P0172 | "Fuel may be leaking onto the hot engine and fumes can build up. Wipe it off and keep riding." | **accepted.** R4 triggers only on "petrol smell" wording. | R16 (leak, drip, fumes need the PETROL sentence, no "keep riding") |
| D6 | Unsafe technician hint that contradicts the rider advice | P0850 | Hints: "Bypass the neutral switch with a jumper wire ..."; "Take a battery lead off while the engine is running ..." (rider advice says do not bypass any safety switch). | **accepted.** Hints are only checked for parts and gauges. | R17 (unsafe procedure list; "bypass" only as "do not bypass") |
| B7 | Bonus: "if" used as a loophole | P0109 | "Ride on if you like, because the engine will stall without warning in traffic." | **accepted.** R3 accepts any segment that contains the word "if". | R12 (the "if" must come before the claim and not be "if you like") |
| B8 | Bonus: STOP entry that permits riding | P0335 | "... do not keep riding. If you must, you can still ride gently home at normal speed." Ride reason "safe to ride home gently". | **accepted.** STOP advice only needs "pull over" and "do not keep riding" somewhere. | R18 (STOP text must not permit riding) |

Result: **8 of 8 accepted by the current validator; 8 of 8 flagged by the proposed rules.** I first wrote D3 and D6 so clumsily that the part-name check rejected them ("cooling fan", "the battery"); I rewrote them so the safety property is the only thing wrong, which is what the table shows.

Proposed new rules (all in the script; each is a pattern, so each has blind spots too):

| Rule | What it checks |
|---|---|
| R12 | Below STOP: no unconditional claim that the engine stops, shuts off, stops running, dies or will not (re)start, in meaning, basis, advice and ride reason. The word "if" must appear before the claim in the same clause and must not be "if you like". |
| R13 | A two-way lock. A table of STOP codes (the owner's decision). A code in it may not be below STOP; a STOP entry not in it is an error. This also stops STOP inflation by accident. |
| R14 | For temperature sensors, the "looks hotter" or "looks colder" wording must agree with the standard title in every rider field, not only the meaning. |
| R15 | ABS and wheel-speed entries: no reassurance wording anywhere ("no need", "safe to", "normal speed", "fine in the rain"); the second advice sentence must come from a closed list. |
| R16 | A fuel leak, drip, spill or fumes in rider text needs the PETROL sentence and must not say "keep riding", "wipe" or "ignore". |
| R17 | Technician hints may not contain unsafe procedures (bypass, jumper wire, battery lead off while running, open the cap hot). Rider text may only say "bypass" as "do not bypass". |
| R18 | STOP text must not permit riding ("you can still ride", "ride home", "safe to ride", "if you must") and must contain "pull over" and "do not keep riding". |
| R19 | A powertrain code with an engine-control tag must have `mil` true. (No real entry breaks it today; it guards later batches.) |

False alarms on the 140 real entries: R12 flags **P0633, P0512, P0513** ("may not restart" in the ride reason, a real finding, problem 8). R13 flags the 7 intended downgrades. R14 to R19: no hits. A first draft of R12 also flagged the 7 CAN entries for "may stop working" and a first draft of R15 and R18 flagged C0035 and P0217 for harmless wording; I narrowed the patterns and the final script shows no such hits.

## E. Cross-entry consistency (all 140)

Within each hardware tag all siblings have the same level and `can_ride_to_workshop`, so no sibling pair contradicts another on level (checked by script: P0112/P0113, P0117/P0118, P0197/P0198, P0122/P0123, P0107/P0108, P0131/P0132, P0261/P0262, P0264/P0265, P0341/P0342; the ECT and IAT low/high pairs agree). The contradictions are between families and in wording:

1. **Six different stall sentences for the same event.** STALL ("if it stalls more than once or will not restart, do not keep riding; have it taken to a workshop"): 8 entries (P0120 to P0124, P0641 to P0643). Camshaft variant ("if it stalls or will not restart, do not keep riding and have it taken ..."): P0340 to P0344. Idle variant ("if it stalls at stops, avoid traffic and do not keep riding"): 10 idle entries. TWO-CASE: 17 entries (P0601, P0602, P0607, P0687 to P0690, P068A, P068B, U0001 to U0008). P0600 ("stalls or loses power more than once"). U0100 (TWO-CASE without its first sentence). One stall means stop in some, "more than once" in others.
2. **STOP sentence variants.** 22 of 28 STOP entries use STOP-TAIL exactly. P0230, P0231, P0232, P0627, P0628 end "avoid repeated restart attempts" and drop the workshop; P0217 says "let the engine cool".
3. **Injector wording.** P0201, P0261, P0262 say "may misfire, lose power or stop"; P0202, P0264, P0265 say "One cylinder may get no fuel ... sudden power loss". Ride reasons differ: P0201 "a single-cylinder bike gets no fuel", P0200 "a cylinder may get no fuel", P0202/P0264/P0265 "sudden power loss possible".
4. **Cylinder 2 level.** P0202 and P0352 are STOP but P0302 (the same dead cylinder detected as a misfire) and P0266 are SERVICE_SOON (section C).
5. **Fuel pump names.** P0230 "Fuel pump control: primary circuit fault" and P0627 to P0629 "Fuel pump control circuit: ..." describe the same circuit in different words; P0231 to P0233 "secondary circuit" is unexplained.
6. **Open circuit wording.** Titles use "open circuit" for P0200, P0627, P0685, P0688, but P0350's standard title also ends "Circuit/Open" and its title says only "circuit fault". Meanings use four different words for an open circuit: "break", "broken", "line is broken", "disconnected".
7. **Intermittent wording.** "drops out or jumps at times" (P0124, P0109, P0114, P0119, P0199, P0329), "drops out at times" (P0233, P0339, P0344, P0518), "jumps about" (P0503).
8. **MAP versus TPS.** The five throttle entries carry the stall warning; the five MAP entries (P0105 to P0109) do not, although MAP is the load input on speed-density bikes.
9. **Petrol sentence.** P0132 and P0172 carry it. P0301 and P0302 name a "leaking injector" as a cause without it. Rule R4 only triggers on the word "smell".
10. **Voltage stop triggers.** P0563 "stop, switch off and do not ride on" (D1); P0561 "stop and switch off"; P0560 and P0562 say the engine will stop if the battery goes flat but have no stop trigger.
11. **Starter relay.** P0615 to P0617 share one ride reason ("avoid switching off on the way") although P0617's advice says "switch off at once". P0615 says "If it keeps running after the engine starts" (what is "it"?).
12. **ECU names.** U0100's title and basis say "engine computer (ECU)"; everywhere else "bike's computer (ECU)" or "ECU".
13. **Review flag.** The 8 CAN entries (U0001 to U0008) are review false, confidence medium, although a bus fault can switch ABS off and U0121 is review true.
14. **Flags (`mil`, `emissions_relevant`, `limp_possible`).** Siblings differ without a stated rule: P0687 and P068A/P068B are true/false/false while P0685, P0686, P0688, P0689 are true/true/true; P0600 true/false/false and P0601 true/true/true; P0602 limp true and P0603 limp false; P0512, P0513 and P0633 are all false. Nobody has checked any of them.
15. **`can_ride` values.** The tag mapping is consistent: O2 sensor and heater `yes` (10), ECT, MAP, throttle, idle, CAN, knock, cam `with_care`. The only odd one is P0633/P0512/P0513 (`with_care` with a "may not restart" reason).
16. **Selection gap noticed on the way.** C0039 "Right Rear Tone Wheel" is not selected although C003C "Rear Tone Wheel" is (held back).

## F. Held-back titles

`data/content/held_back_titles_20261001.csv` has all 22 codes: the OBDex title, the two codes before and the two after in the same file (with titles), why it was held back, my view of the OBDex title, my best guess at the standard title (labelled UNVERIFIED, with confidence and basis). I cannot check outside sources; every guess comes from the neighbouring titles and from memory of the standard's layout, so the owner's assistant must verify.

What stands out:
- **Probably false alarms (3):** P0141 (the OBDex title looks right; the duplicate comes from P0142, which should be sensor 3), P2110 (the duplicate is P2113), U0167 (the duplicate is U0168).
- **Left front wheel speed block C0030 to C0036 (6 codes) looks internally consistent.** OBDex gives every wheel the same seven slots (circuit malfunction, range/performance, low, high, signal erratic, no signal, intermittent). The earlier "pattern does not match" reason is weak. Probably releasable once the titles are confirmed. A bike has one front and one rear sensor, so the rider text says "front wheel".
- **Probably wrong, with a pattern-based guess (4):** P0134 and P0140 (no activity detected), P2230 (barometric pressure circuit intermittent/erratic, and P2231 looks wrong too), U0168 (vehicle security control module).
- **No reliable guess (9):** C0037, C0038 and C003A to C003F (8 codes) look like a newer series with no failure type in the title; **P033F** is a crankshaft/camshaft correlation title that belongs near P0016 to P0019.
- OBDex shifts blocks by one in several places (P0142/P0143, P2113 to P2115, P2230/P2231, U0167/U0168). A "title repeats in an adjacent code" scan found them; a "same title in a different family template" scan would find more.

## G. Residual error estimate and recommendation

What the sample says. Rates of CONCERN or FAIL per check, for the 40 random non-STOP entries (these are the only ones that estimate the 112 unreviewed non-STOP entries; the 28 STOP entries are a full count). 95% intervals are Wilson intervals.

| Check | 40 random non-STOP | 95% interval | 28 STOP (full count) |
|---|---:|---|---:|
| 1 Meaning | 0% (0) | 0 to 9% | 11% (3) |
| 2 Causes | 18% (7) | 9 to 32% | 4% (1) |
| 3 Advice | 18% (7; 3 FAIL) | 9 to 32% | 4% (1) |
| 4 Level | 5% (2) | 1 to 17% | 39% (11) |
| 5 Parts | 5% (2) | 1 to 17% | 0% |
| 6 Wording | 0% | 0 to 9% | 4% (1) |
| 7 Rider understanding | 28% (11) | 16 to 43% | 29% (8) |
| 8 `can_ride` | 0% | 0 to 9% | 29% (8) |
| 9 Standard sentences | 18% (7) | 9 to 32% | 21% (6) |
| 10 Hindi | 28% (11) | 16 to 43% | 39% (11) |
| Any substantive concern (checks 1 to 5 and 8) | 38% (15) | 24 to 53% | 54% (15) |
| Any FAIL | 8% (3) | 3 to 20% | 0 |

What a sample of this size can tell us: the shape of the problem. Meaning and direction are reliable (0 of 40 random and 0 FAIL of 68), so the checker plus the source hash do their job on facts. Wording problems (checks 7 and 10, about 28%) are common and cheap to fix by rule.

What it cannot tell us: (1) rare defects. A defect present in 3% of entries has a 30% chance of not appearing in a sample of 40. (2) Anything about families I barely sampled: only one ABS entry (U0121), one oil-temperature group, no wheel speed, no starter relay or CAN entry in the random sample (CAN was read in section E). Batches 2 to 4 are mostly *new families* (chassis, evaporative, secondary air, network), so batch 1's rates predict them poorly. (3) Whether the facts are right for a real bike: nobody with workshop experience has read any of this. (4) My own bias: one reviewer, one pass, and the CONCERN threshold is mine. Presentation concerns (checks 6, 7, 9, 10) are matters of taste more than error.

Recommendation: **batches 2 to 4 may proceed after these rule changes.** Not "may proceed": the same stall-wording and STOP-calibration problems would be copied into 225 entries. Not "should not proceed": the facts are sound and the problems are repairable by rule.

Before batch 2:
1. One STALL sentence word for word everywhere stalls are mentioned (idle, camshaft, MAP, CAN, voltage); retire the other variants; add OVERHEAT and RESTART as fixed sentences in the glossary.
2. Apply the 7 STOP downgrades through the locked STOP table (R13) and add the overheating line to the rubric. Have a mechanic check P0232, P0629, P0336, P0685, P0686.
3. Add validator rules R12 to R18 (R19 optional) and put the 8 defective entries into `review_regression_cases.json`.
4. Fix the real hits: P0633, P0512, P0513, P068B and the other TWO-CASE entries where stalls are irrelevant, P0507, P0561, the CAN entries (ABS sentence, review true).
5. Replace "reduce load", "run on one cylinder", "cut out", "hunt", "drops out or jumps", "refuse to start" with glossary words before the Hindi pass.
6. Add `applies_when` keys for knock, camshaft, oil temperature sensor, closed throttle switch.
7. Verify the 22 held-back titles (section F) before the chassis batch; review the ABS and wheel-speed entries as a group once written.
8. Re-run the 60-code quality gate with a fresh sample by an independent reviewer (still outstanding from the first review).

## Additions beyond the brief

1. **Keep/downgrade with a stated cost rule** (a wrong STOP costs a visit, a wrong downgrade leaves a rider unwarned) so the owner can see which calls are close.
2. **Locked STOP table (R13)**: a STOP change becomes an explicit edit, in both directions. It makes the owner's STOP decision enforceable instead of implied by tag mapping.
3. **A reproducible defeat script** that the owner can re-run after every validator change, with eight cases, and a sampling script with the fixed seed.
4. **Read the OBDex description, not only components and causes.** Three entries make claims the description contradicts or supports in the opposite direction (P0232 pump stays powered, P0605/P0606 limp-home, P068B battery drain). The validator's "description only" warning led the author to delete a supported claim (P068B). Suggest a reviewer checklist line: "does the entry's main effect agree with the source description".
5. **New `applies_when` keys** (section G6) and **flag rules per tag** (R19 is a start) so the app can hide codes a bike cannot raise.
6. **Glossary additions:** OVERHEAT, RESTART and a conditional ABS sentence for CAN entries as fixed sentences; replace idioms listed in problem 9.
7. **Title scan improvement:** the held-back list contains probable false alarms (P0141, P2110, U0167, the left front block) and OBDex block shifts. A scan that compares each title with the same slot in neighbouring families would reduce both. C0039 is missing from the selection.
8. **App-level question:** do riders read STOP entries while riding or parked? Two advice versions (active fault, stored fault) would fit the text to the situation.
9. **Review status fields** (`reviewed_by`, `reviewed_at`, `review_status`) per entry, so that this review's CONCERN and FAIL rows can be closed one by one.
10. **Process:** the validator takes about 34 seconds to parse OBDex on a cold start; with the temp cache it runs in under a second.

## Files added by this review

- `data/content/review_flags_batch1_20261001.csv`: 680 rows.
- `data/content/held_back_titles_20261001.csv`: 22 rows.
- `data/content/review_validator_defeat_20261001.py`: defective entries and proposed rules.
- `data/content/review_sample_batch1_20261001.py`: reproduces the sample (seed 20261001).
- `docs/content/REVIEW_REPORT_BATCH1_20261001.md`: this report.
