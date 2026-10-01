# Review report: pilot English seed (40 entries and 8 suspect titles)

Review run: RUN_MODE = review, RUN_SCOPE = pilot. Date: 2026-10-01.
Reviewed branch: `content/seed-20261001` (head `15235ab`). Review output branch: `content/review-20261001`.
Source: OBDex commit `bc58b0eb7273226a1aabae98e956b70b8362bda1` (re-cloned by this reviewer).
Files added by this review: `data/content/review_flags_20261001.csv` (320 rows) and this report. No entry was edited. `main` was not touched.

## In plain English (for a non-coder)

The author wrote 40 rider-facing fault-code explanations. I re-read every one as if I were a mechanic who has to hand it to a rider in India, and compared each with the source data, not with the author's own notes.

**The pilot is usable but not ready to scale as it stands.** The basic facts are mostly right: the meaning matches the code in 38 of 40 entries, and the "low voltage" and "high voltage" pairs point the right way. The ABS entries follow the rule you gave (brakes still work, ABS is off, wheel can lock; SERVICE_SOON, not STOP).

What worries me is the advice text, not the facts:

1. **One entry contradicts itself in a way that could leave a rider stranded.** U0100 ("lost contact with the engine computer") says the engine may cut out or not start, yet it is marked SERVICE_SOON while a bike with the identical "may stall" wording elsewhere is STOP.
2. **Fire and battery risk is under-warned.** P0563 (battery overcharging) and the fuel-smell lines in P0172 and P0132 do not tell the rider firmly to stop and not ride on.
3. **The advice "stop if the engine stalls" appears in four entries and means nothing**: if the engine has stalled, the rider has already stopped.
4. **Several entries assume a temperature gauge or a flashing warning lamp.** Many Indian air-cooled bikes have no gauge and many bikes do not flash the lamp for a misfire.
5. **The automatic checker (validator) passes all 40 entries, and it would also pass four kinds of bad entry that I wrote to test it** (section 4). So a clean validator run does not prove an entry is safe.
6. **All 8 suspect titles look wrong or doubtful** when compared with their neighbours in the same file (section 3). The owner's assistant should check them against public sources before those entries are written. P0139 is the clearest: it has exactly the same title as P0138.

**My recommendation: yes after fixes.** Fix the items in section 2, add the validator rules in section 5, decide the eight titles, then let the author continue with batches.

I did not re-run the 60-code quality-gate sample; that was outside this run's scope (the 40 entries and 8 titles). The sample and its single-author judging are still unchecked.

## 1. Counts per check (40 entries, 320 rows)

| Check | PASS | CONCERN | FAIL |
|---|---:|---:|---:|
| 1 Meaning matches the standard title and structure | 38 | 2 | 0 |
| 2 Causes plausible for a small bike, not car-only | 37 | 3 | 0 |
| 3 Advice free of reversals and rider danger | 23 | 17 | 0 |
| 4 Action level right under RUBRIC.md | 38 | 1 | 1 |
| 5 No part, number or voltage the source does not support | 34 | 6 | 0 |
| 6 Shared failure wording used | 40 | 0 | 0 |
| 7 Understandable to a rider | 30 | 10 | 0 |
| 8 Proposed `can_ride_to_workshop` (a proposal, so always recorded as PASS) | 40 | 0 | 0 |

26 of 40 entries have at least one CONCERN or FAIL; 14 entries are clean on all checks (P0130, P0201, P0351, P0230, P0110, P0202, P0352, P0171, P0420, P0112, P0113, P0562, P0505, U0155). Every row has a reason and a suggested fix in the CSV.

How I judged: the standard meaning of each code from my own knowledge, the OBDex entry at the recorded commit, the rubric (including your ABS special rule), and what a rider without a manual could understand. I re-ran the author's validator: 0 errors, 1 warning (P0563), matching the pilot report. Check 6 is all PASS because every directional code uses the shared phrases and the generic codes use "circuit fault" as the glossary says. One design gap there is noted in section 6.

## 2. The ten most serious problems

| # | Codes | Problem | Suggested fix |
|---|---|---|---|
| 1 | U0100 | Level and advice contradict each other. Basis says "engine may cut out", advice says it may "not start", level is SERVICE_SOON, and its only stop trigger is circular. P0201 with the same basis is STOP. The meaning also adds "or the scan tool", which is not part of the code. (Check 4 FAIL.) | Set STOP, or keep SERVICE_SOON only after removing the stall and no-start claims and explaining the two situations (ECU really dead versus another unit simply complaining). Remove "scan tool". |
| 2 | P0563 | Overcharging can boil or vent a battery (fire and acid). The firm warning sits behind "stop and check" and the level is SERVICE_SOON. The brief says be conservative on fire risk. | Owner decision: STOP, or SERVICE_SOON with "if the battery is hot, swollen or smells, stop, switch off and do not ride on". |
| 3 | P0172, P0132 | They tell the rider to expect "a fuel smell" but give no instruction for a strong petrol smell or dripping fuel (a leaking injector or line is a fire risk). | Add "If you smell petrol strongly near the engine or tank, or see fuel dripping, stop and do not ride." |
| 4 | U0121 | The ABS special rule asks for plain wording; the entry softens it ("should still work", "may be off"). It also does not say the speedometer can stop on bikes that take speed from the ABS unit. | "Your normal brakes still work but ABS is off and a wheel can lock in hard braking." Keep SERVICE_SOON. |
| 5 | P0120, P0122, P0123 | The three throttle-sensor entries disagree: P0120 has a (circular) stall line, P0122 and P0123 have none. A bad throttle signal can cause stalling at stops and, on ride-by-wire bikes, sudden power change. | Same wording in all three: may stall at stops, avoid traffic and long rides; stop using the bike if it stalls repeatedly. |
| 6 | P0300, P0301, P0302 | "Stop if the warning lamp blinks" depends on a lamp behaviour that many bikes do not have. The author logged this and only half fixed it. | Trigger on rough running, backfiring or strong power loss only. |
| 7 | P0115, P0117, P0118 | "Watch the temperature gauge" assumes a gauge, and many Indian air-cooled bikes and scooters have none. The gauge is not in the source. P0117's basis ("may overheat") is not what this code causes (the ECU believes the engine is hot, so the real effect is hard cold starting). P0118 has no instruction for a hot engine. | Say "if the bike has a temperature display"; add "stop and let it cool if it runs hot or the fan never stops" to P0118; fix the P0117 basis. |
| 8 | P0500 | Claims "idle control may be affected", which the source does not support (it mentions cruise control and shift adaptation, both car features). The standard title is a sensor malfunction, not a circuit code. | Remove "idle control"; title "Vehicle speed sensor A: fault". |
| 9 | P0195 | "the ECU may not notice a hot engine" invents a protection function not in the source; "watch for signs of overheating" is vague without an oil temperature display. | Drop the claim; say the oil temperature reading is lost and should be checked at the next service. |
| 10 | P0600, P0340 (and P0135, P0105) | P0600 and P0340 have the circular "stop if it stalls" line; P0600 is mostly jargon. P0340 offers a worn timing chain as a cause of a sensor circuit code, a weak car-style cause. P0135 states a heater fuse or relay flat although most small bikes have neither; P0105 assumes a vacuum hose although many bike MAP sensors are bolted on with no hose. | Replace the circular lines with "if it stalls or will not restart, have it taken to a workshop"; hedge or drop the chain cause; add "(if fitted)" to P0135 and P0105. |

Also noted in the CSV: C0035's title "(listed as left front)" will confuse a rider; "reluctor ring" (P0335) and "tone ring" (C0035) are workshop words; P0850 names a "neutral lamp" that is not a source part; P0122, P0123, P0107, P0108, P0131 and P0132 lead with workshop language (the shared failure phrases the brief requires) and need one plain clause alongside.

## 3. The 8 suspect titles

I cannot check outside sources. Method: compare each OBDex title with the codes next to it in the same file and with the family pattern. "Expected by pattern" is my inference from that pattern, not a verified standard title; the owner's assistant must confirm it.

| Code | OBDex title | Neighbours in the same file | Verdict | Reason |
|---|---|---|---|---|
| P0139 | O2 Sensor Circuit High Voltage (Bank 1 Sensor 2) | P0136 circuit malfunction, P0137 low voltage, P0138 high voltage (all B1S2), then P013A and P013B slow response (B1S2) | **SUSPECT** (high) | Word-for-word the same title as P0138 (only the comma differs), and its description also says high voltage. The sensor 1 block is malfunction, low, high, then P0133 slow response, so the pattern expects P0139 = slow response. It is one of two duplicate-title pairs inside the 383 selected codes (the other is P0685/P0686). |
| P0626 | Generator Field/F Terminal Circuit Performance | P0625 "Generator Field Terminal Circuit Low"; P0627 begins a new family (fuel pump control) | **SUSPECT** (medium) | Low is followed by "Performance" rather than High. By the low then high pattern used all over the file, P0626 would be "Circuit High". |
| P0686 | ECM/PCM Power Relay Control Circuit Open | P0685 "ECM or PCM Power Relay Control Circuit Open" | **SUSPECT** (high) | Duplicates P0685. The family P0627 to P062A runs open, low, high, range, so the pattern expects P0685 open, P0686 low, P0687 high. |
| P0687 | ECM/PCM Power Relay Sense Circuit Open | P0688 sense high, P0689 sense low, P0690 sense high | **SUSPECT** (medium) | If P0686 is control low, then P0687 should be control high, and "sense circuit open" is out of place. A sense family then would run open, low, high. |
| P0688 | ECM/PCM Power Relay Sense Circuit High | P0689 sense low, P0690 sense high | **SUSPECT** (high) | Same title as P0690 ("Sense Circuit High"), and the OBDex description of P0690 says "Same as P0689 with the sense line shorted to supply". The pattern expects P0688 = sense open, P0689 = low, P0690 = high. |
| U0075 | Control Module Communication Bus "B" Performance | U0073 bus A off, U0074 bus B off, then U007A bus H off, U007B I, U007C J, U007D K, U007E L | **SUSPECT** (high) | The bus letters run A, B, then jump to H. Codes U0075 to U0079 sit where bus C to G would be. U0075 would be bus C, but the file gives bus B again. It also duplicates U0070 (bus B performance). |
| U0076 | Control Module Communication Bus "C" Off | same | **SUSPECT** (medium) | By the lettering pattern bus C belongs at U0075, so bus C at U0076 is off by one place. |
| U0077 | Vehicle Communication Bus B Off | same; U0078 "Vehicle Communication Bus B (+) Open" | **SUSPECT** (high) | Bus B Off already exists as U0074. The "Vehicle Communication Bus" wording differs from the "Control Module Communication Bus" series around it. By pattern U0077 would be bus E. |

Result: 8 of 8 SUSPECT. Consequence for the author: these are the only titles that structure-only mode relies on as "facts", so write no entry for any of them until the titles are checked. Related selection bug: `select_codes.py` includes P0685 to P0688 but stops before P0689 and P0690, which belong to the same family (section 6).

## 4. Three defects the validator does not catch

I confirmed each example by running `validate_seed.py` on it against the recorded commit: **0 errors, 0 warnings** for all of them. Each example is a copy of a real pilot entry with only the shown fields changed (other fields, including the source hash, are unchanged).

**Defect 1: wrong direction (low and high swapped).** The validator checks the shared phrases are spelled right but never compares them with the direction in the OBDex title ("High Input"). Example, P0123 carrying P0122's meaning:

```json
{"code":"P0123","title_en":"Throttle position sensor A: voltage below threshold","meaning_en":"The throttle position sensor signal is lower than the bike's computer (ECU) expects, often from a short to ground.","likely_causes_en":["Signal wire short to ground","Faulty throttle position sensor"]}
```

**Defect 2: advice that endangers a rider but uses no banned word.** The validator only checks that STOP advice says "pull over" and that MONITOR advice does not. It has no rule for the ABS special rule (brakes work, ABS off, wheel can lock, brake early). Example, C0035 (SERVICE_SOON, review flag true):

```json
{"code":"C0035","rider_action_level":"SERVICE_SOON","rider_action_basis":"braking unaffected","rider_advice_en":"Braking is not affected, so ride as normal. The ABS lamp can wait until the next service."}
```

**Defect 3: a car-only or unsupported part in the causes.** The parts check only looks at a fixed list of about 45 patterns; anything outside the list is never checked, and a part that is in the source passes even if it does not exist on a small bike. Example, P0172 with an EGR valve (EGR is excluded by the selection rules and absent from the source entry for P0172):

```json
{"code":"P0172","likely_causes_en":["Stuck-open EGR valve","Leaking or stuck-open fuel injector","Blocked air filter"]}
```

(The same gap lets a mass air flow sensor through on P0171, because the OBDex source for that code lists one.)

**Bonus, a fourth: level contradicts the entry's own text.** This is a real defect in the pilot (U0100). Example, U0155 with stall wording at SERVICE_SOON, which the validator accepts because it only maps tags to allowed levels:

```json
{"code":"U0155","rider_action_level":"SERVICE_SOON","rider_action_basis":"engine may stall or not start","rider_advice_en":"The engine may cut out or refuse to start while riding. Get it checked soon."}
```

## 5. Should the author continue to full batches?

**Yes after fixes.**

Why not "yes": the safety items in section 2 (U0100, P0563, the fuel-smell wording, ABS wording) sit in advice text that the whole batch will imitate; 26 of 40 entries have at least one concern. Fixing it now is cheap, fixing it across 383 entries is not.

Why not "no": the core facts are sound (meaning and direction right in 38 of 40; causes plausible in 37; car-only causes were dropped well; ABS handled to the owner's rule). The problems are fixable by rules, not a rewrite.

Before batches start:
1. Fix the ten items in section 2.
2. Owner decides P0563 (STOP or not) and confirms the ABS wording.
3. Check the 8 suspect titles; write nothing for them until then.
4. Add the validator rules in the next list.
5. Add a rule to the author's brief: advice may not contain a stop trigger that depends on the engine already being stopped, a gauge, or a flashing lamp.

## Additions beyond the brief

1. **Proposed new field `can_ride_to_workshop` (yes | with_care | no).** Proposed values for all 40 entries are in the `reason` column of check 8 in the CSV. Rubric mapping I used: STOP gives `no`; SERVICE_SOON gives `with_care` unless the bike is plainly rideable (O2 sensor, O2 heater, an air-fuel code where the bike runs normally), which gives `yes`; MONITOR gives `yes`; ABS and chassis codes give `with_care`. Summary: no (P0201, P0202, P0351, P0352, P0230, P0335, U0100), yes (P0195, P0130, P0135, P0110, P0420, P0112, P0113, P0131, P0132), with_care (24). Why: the action level says how serious, not whether the rider can get home; the owner can validate the field by an enforced mapping from the level plus an override list.
2. **New validator checks (each would have caught something above):**
   - Direction check: for codes whose OBDex title contains Low/High/Open/Circuit Low/High, the entry's title and meaning phrase must agree.
   - ABS and wheel-speed rule: for `lost_comm_abs`, `wheel_speed`, `abs_*` tags the advice must contain "brake" and "lock" and must not contain "braking is not affected" or "ride as normal".
   - Level versus text: a SERVICE_SOON or MONITOR entry may not use "may stall", "cut out", "not start" or "sudden" in basis or advice unless its tag allows STOP and the entry says why.
   - Circular advice: reject "stop if the engine stalls/cuts out" style phrases.
   - Hardware assumptions: warn on "temperature gauge", "warning lamp blinks", "vacuum hose", "fuse or relay" unless hedged ("if fitted").
   - Car-only deny list: EGR, turbo, boost, MAF, mass air flow, PCV, transmission, A/C, power steering, hub bearing, AWD, cruise, shift (error even when the source names them).
   - Fire and fuel: any entry that mentions "fuel smell", "petrol smell" or "overcharge" needs a firm stop sentence and `needs_mechanic_review`.
   - Part regex loosening: "neutral lamp" currently passes because the token is just "neutral"; require the exact part word.
   - Title duplicate scan across the whole source file, to find suspect titles automatically (this found P0139/P0138 immediately; U0003 to U0009 look duplicate only if the +/- symbols are stripped, so the check must keep symbols).
3. **Flag consistency.** `limp_possible` and `mil` in the entries differ from the source in places (for example P0105, P0115, P0117, P0118 have `limp_possible` true where the source has none) and nothing checks them. The author's own gate says the source flags are generic. Decide the rule: either derive flags from tag plus failure type, or have a mechanic confirm them.
4. **Selection bug.** `select_codes.py` line 93 uses the range P0685 to P0688 for `ecu_power_relay`; P0689 and P0690 (sense low and high) are in the same family but not selected. Extend the range to P0690 after the titles are sorted out.
5. **Cause hedging for hardware that may not exist.** Add an optional per-entry field `applies_when` (needs hose-fed MAP, needs heater fuse, needs two cylinders, needs a gauge) so the app can hide or hedge. P0202, P0302 and P0352 cannot occur on a single-cylinder bike and today nothing says so. This matches the author's own version-2 proposal and I support it.
6. **Plain-clause rule for required phrases.** Check 6 (use the shared failure phrases) and check 7 (understandable) pull against each other: "short to ground" is required but is workshop language. Suggest the entry carry a `meaning_plain_en` clause or the app show the shared phrase only in a technician section.
7. **Failure-type table gap.** The 14 shared phrases have no entry for the generic "circuit fault" or for "efficiency below threshold" (P0420) or misfire and trim codes. 17 of the 40 pilot titles rely on "circuit fault". Add "circuit fault (type not specified)" and the other categories to the app's table or the Hindi pass will invent its own.
8. **Missing real-world causes for India.** P0420 does not mention a modified, damaged or removed exhaust or catalytic converter, the commonest trigger on Indian bikes; P0171 and P0172 do not mention aftermarket air filters or exhausts. The source does not list them, so the author left them out correctly under the rules, but a mechanic should add them to `technician_hints_en`.
9. **Reviewer independence.** Two checks in this report (the quality gate sample and the author's second-pass log) are still single-judge. A fresh 60-code re-sample in a later review run would complete the independent check.
10. **Process note.** The validator takes about 35 seconds to parse the source on a cold start; fine for batches, but it should cache the index (it already does in the temp folder) and print the recorded commit it validated against.

## Files

- `data/content/review_flags_20261001.csv`: 320 rows (code, check, verdict, reason, suggested_fix).
- `docs/content/REVIEW_REPORT_20261001.md`: this report.
