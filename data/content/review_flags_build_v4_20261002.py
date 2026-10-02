#!/usr/bin/env python3
"""Builds review_flags_v4_20261002.csv from the reviewer's findings (sample: review_sample_v4_20261002.json, seed 20261002).
Every row: code, check, verdict, reason, suggested_fix. Entries not named in CONCERNS get PASS for that check.
The findings are the reviewer's own reading of the entries against the OBDex source and the rubric; nothing is taken from the
author's logs. Run: python3 review_flags_build_v4_20261002.py"""
import csv, json, os, collections
HERE = os.path.dirname(os.path.abspath(__file__))
E = {json.loads(l)["code"]: json.loads(l) for l in open(os.path.join(HERE, "generic_en_seed.jsonl"), encoding="utf-8")}
S = json.load(open(os.path.join(HERE, "review_sample_v4_20261002.json")))
CHECKS = {1: "meaning matches standard title and structure", 2: "causes plausible for a small bike, not car-only",
          3: "advice free of reversals, circular advice and danger", 4: "level correct under RUBRIC.md and stop_table",
          5: "no part, number or hardware the source does not support", 6: "shared failure wording and glossary used",
          7: "understandable to a rider", 8: "can_ride_to_workshop sensible and consistent", 9: "canonical sentences exact, each sentence 25 words or fewer",
          10: "Hindi-translatability", 11: "applies_when correct", 12: "chassis wheel-speed wording position-neutral"}
P, C, F = "PASS", "CONCERN", "FAIL"
X = {}  # (code, check) -> (verdict, reason, fix)


def add(codes, check, verdict, reason, fix):
    for c in codes.split():
        X[(c, check)] = (verdict, reason, fix)


# ---- check 1
add("P0321", 1, C, "meaning says the signal is 'in range'; the standard title is range/performance, which also covers out-of-range readings",
    "The engine speed signal does not match what the ECU expects, so engine speed may be misread.")
add("P00D1", 1, C, "meaning says the heater circuit 'works electrically'; the standard title (range/performance) does not say that",
    "The heater of the upstream oxygen sensor does not warm the sensor as expected.")
add("P0231 P0232 P0233", 1, C, "standard title says 'Fuel Pump Secondary Circuit'; the entry renames it 'power circuit', which is the author's reading and not in the title",
    "Use 'fuel pump circuit (secondary)' in title and meaning until the owner's assistant has checked what secondary means here.")
add("P2118", 1, C, "meaning states the cause ('from a binding throttle or a worn motor') as fact; the title only says range/performance",
    "Write 'often from a binding throttle or a worn motor'.")
add("C0035", 1, C, "Wal33D reads C0035 as a wheel speed sensor SUPPLY code for another wheel; the entry says 'circuit'. The owner's premise (both sources say circuit) does not hold for C0035",
    "Keep confidence low; word it 'wheel speed sensor fault' and hold until the edition question (see held_back_triage) is answered.")
add("C003F", 1, C, "'which most bikes do not measure' is an unsupported general claim, and rotation-direction correlation is a car feature",
    "Remove the clause; consider holding the entry until a bike with direction-sensing sensors is known.")
add("P0917 P0918", 1, C, "OBDex source is an automatic gearbox selector code (TCM, harsh shifts, locked in one gear); the entry maps it to a bike gear position sensor",
    "Say only that the gear position signal is unreliable; drop the effect on starting; keep low confidence.")
add("P0351 P0352 P0328 P0325 P0326 P0327 P0505", 1, C, "the owner's assistant verified a title for this code, but standard_title_en still holds the OBDex wording (P0351 and P0352 add '(Cylinder N)'; P0325, P0327, P0328 lack 'or Single Sensor'; P0326 uses another sensor name than its siblings; P0505 says 'Idle Air Control')",
    "Move the verified title into title_overrides.csv so standard_title_en and title_basis 'override' record it; P0325 to P0328 should share one pattern.")
# ---- check 2
add("P0322", 2, C, "'Dead pickup' is informal", "Use 'Failed pickup'.")
add("P0445", 2, C, "first cause 'Shorted purge valve circuit' just repeats the title", "Use 'Shorted purge valve coil or wire'.")
add("P2097", 2, C, "cause 'Downstream oxygen sensor reading too rich' repeats the code, not a cause", "Use 'Contaminated or aged downstream oxygen sensor'.")
add("P0524", 2, C, "no sensor or wiring cause; the sibling circuit codes P0520 to P0523 show that a false low reading is possible and the owner may want that said",
    "Hint only: 'Check the sensor and wiring after the oil level and the pressure test are good'. Level stays STOP.")
add("P0625", 2, C, "'Worn alternator brushes (if fitted)': brushed field alternators are rare on small bikes", "Drop the brushes cause or mark it rare.")
add("U0140", 2, C, "a body control unit is a car idea; few bikes have one", "Keep low confidence and add an applies_when key for bikes with such a unit.")
# ---- check 3
add("P2111", 3, C, "stuck-open throttle: the advice says only 'pull over and switch off'; it does not say how to slow down first (brakes, clutch if fitted, engine stop switch)",
    "Add: 'If the bike does not slow down, use the brakes, pull in the clutch if it has one, then switch off.' (a mechanic to confirm)")
add("P0506 P0509", 3, C, "two fixed sentences overlap: 'if it stalls at stops, ride gently' and 'if it stalls more than once, do not keep riding'; a rider who stalls at every stop meets both. Same in all idle entries",
    "Owner to merge: 'If it stalls once at a stop, ride gently and have it checked soon. If it stalls again or will not restart, do not keep riding; have it taken to a workshop.'")
add("P0633", 3, C, "'do not switch off on the way' tells the rider not to use the one action that always stops danger, and the reason is not given",
    "Write 'avoid switching off the engine until you reach the workshop, unless something is wrong'.")
add("P0117", 3, C, "advice says 'if it runs very hot, stop and let it cool', but this fault makes the engine LOOK hotter; the overheating risk belongs to P0118 (looks colder, fan may not start)",
    "Remove the overheating sentence from P0117 and keep it in P0118.")
add("P0232", 7, C, "does not say why a pump that stays powered matters (flat battery, fuel pressure)", "Add 'the battery may go flat' if the owner agrees.")
# ---- check 4
add("P2100 P2102 P2103", 4, C, "text says the ECU may lose control of the throttle and the throttle may not follow the twist grip; that is the STOP reason of P2104. The OBDex text only says limp-home with reduced power",
    "Either reword to what the source says ('power is reduced') or add these codes to the STOP table. The same wording at SERVICE_SOON and at STOP is a contradiction.")
add("P0201 P0261 P0262 P0351 P2300 P2301 P2302", 4, C, "STOP rests on 'no fuel or no spark stops a single'; on a twin the other cylinder keeps running, which is exactly why the cylinder 2 siblings (P0202, P0264, P0265, P0352, P2303 to P2305) were set to SERVICE_SOON",
    "Owner to decide: keep STOP and add 'on a twin the other cylinder may keep running', or give twins their own wording through applies_when.")
add("P0522", 4, C, "source says the code can mean genuinely low oil pressure, yet the only stop trigger is a warning lamp the bike may not have; review is false", 
    "Set needs_independent_review true and say 'if the engine is noisy, hot or the oil level is low, do not keep riding'.")
# ---- check 5
add("P0520 P0521 P0524", 5, C, "'mechanical oil pressure tester' is a tool the source does not mention", "Write 'check the oil pressure with the workshop's pressure test'.")
add("P2122 P2123 P2127 P2128 P2138", 5, C, "'twist grip sensor D/E' is the author's mapping of 'throttle/pedal position sensor D/E'; the source does not say twist grip",
    "Write 'throttle (twist grip) position sensor D' and keep confidence low.")
# ---- check 6
add("P0054", 6, C, "'resistance outside range' is not on the shared phrase list (the list has 'resistance above threshold' and 'signal out of range')",
    "Add 'resistance out of range' to the shared list and use it here and in P0053.")
add("P0460", 6, C, "'fuel level sender' is not a glossary term", "Use 'fuel level sensor'.")
add("P0445", 6, C, "'short circuit' is not on the list; the standard says only 'circuit shorted'", "Add 'short circuit (to ground or battery supply not stated)' to the list or use the existing two phrases only when the source names which.")
add("U0075 U0076 U0077", 6, C, "titles end 'bus off' while U0073 and U0074 say 'communication lost (bus off)'", "Use 'communication lost (bus off)' in all five.")
# ---- check 7
add("P0321", 7, C, "'plausibility check' is jargon in a rider sentence", "See check 1.")
add("U0003 U0004 U0005 U0006 U0007 U0008 U0073 U0074", 7, C, "meaning uses 'CAN bus' without saying what it is (only U0001 and U0009 explain it)", "First use: 'CAN bus (the bike's data network)'.")
add("C003F", 7, C, "'disagree on the direction of rotation' means little to a rider", "See check 1.")
add("P2109", 7, C, "'closed throttle stop' is not explained", "Write 'the closed position of the throttle'.")
add("P0483 P0485", 7, C, "'if the engine runs very hot' is something a rider without a temperature display cannot judge (same sentence in P0480, P0691, P0692 and the ECT codes P0115 to P0119)",
    "Write 'If your bike has a temperature warning and it comes on, or you see steam or smell hot coolant, stop and let the engine cool.'")
add("P0504", 8, C, "advice says 'if the brake light does not come on, get it fixed before riding' but the value is with_care and the reason says 'ride gently'; a bike with no brake light should not be ridden (outside the seeded sample)",
    "Reason: 'ride only if the brake light works'.")
# ---- check 8
add("P068A", 8, C, "value is with_care but the reason says 'usually rideable' (the same fault type P068B says the battery may go flat)", "Use can_ride yes with reason 'usually rideable', or change the reason.")
# ---- check 9
add("P2504", 9, C, "29-word sentence (the BATTERY sentence); the brief says each sentence inside a canonical sentence must be 25 words or fewer; D6 exempted it knowingly (P0563 is the same)",
    "Split: 'If the battery is hot, swollen or smells of rotten eggs, stop, switch off and do not ride on. Do the same if the lights are very bright or bulbs keep blowing.'")
add("P2148", 9, C, "the hot or swollen battery stop condition is only in can_ride_reason; the advice has no BATTERY-HOT sentence although it says the battery may be overcharged",
    "Add the BATTERY-HOT sentence to the advice, as in P0561 and P2502.")
# ---- check 10
add("P033F", 10, C, "'jumped timing chain': the validator blocks 'jumps' but not 'jumped'", "Use 'worn or slipped timing chain (rare)' and add 'jumped' to the idiom list.")
add("P0617", 10, C, "'starter may run on' is an idiom", "Use 'starter may keep turning after the engine starts'.")
add("U0004 U0007 U0009 U0073 U0074 U0075 U0076 U0077", 10, C, "cause 'A faulty unit pulling the bus down' is an idiom", "Use 'A faulty unit that disturbs the bus'.")
add("P0224 P0602", 10, C, "'misbehave' (basis or reason) is an idiom", "Use 'work wrongly'.")
add("P2196 P2A00", 10, C, "'fine-tune' in the meaning", "Use 'adjust'.")
add("P0460", 10, C, "'sender' is not a glossary term", "See check 6.")
# ---- check 11
add("P0217", 11, C, "meaning and causes are coolant-specific but applies_when is empty", "Add {liquid_cooled: true} or reword for air-cooled and oil-cooled bikes.")
add("P0625 P0626 P2500 P2501", 11, C, "ECU-controlled alternator field or lamp terminal is a car-style feature that small bikes rarely have; applies_when is empty", "New key such as alternator_ecu_controlled.")
add("U0001 U0002 U0003 U0004 U0005 U0006 U0007 U0008 U0009 U0010 U0073 U0074 U0075 U0076 U0077 U0140 U0146", 11,
    C, "only a bike with a CAN bus can raise these; the key can_bus_fitted exists in the validator but no entry uses it", "Add {can_bus_fitted: true} and make the validator require it for the can_bus tag.")
add("P0448 P0451 P0454", 11, C, "evap_fitted is too coarse: vent valves and pressure sensors are much rarer on bikes than a purge valve and canister", "Separate keys (evap_vent_valve_fitted, evap_pressure_sensor_fitted).")
add("P0852", 11, C, "not every bike feeds a neutral switch to the ECU", "Add a neutral_switch_fitted key.")
add("P0633 U0167", 11, C, "not every bike has an immobiliser", "Add an immobiliser_fitted key.")
add("P0651 P0652 P0653 P0697 P0698 P0699", 11, C, "supplies B and C may not exist on a small bike", "Add a key or keep low confidence.")
# ---- check 12
add("C0035", 12, C, "title and meaning are neutral, but standard_title_en stores 'Left Front' and the hint names front and rear; if standard_title_en is ever shown the position leaks",
    "Mark standard_title_en of chassis entries as not for riders, or store a neutral form.")
add("C0037 C0038 C003A C003B C003C C003D C003E", 12, C, "rider text says 'rear'; the owner rule is 'a wheel speed sensor' with no position, and standard_title_en stores Left Rear or Right Rear",
    "Use 'a wheel speed sensor' unless the owner accepts front or rear as neutral; OBDex lists the same fault twice (C0037 and C0045), so the position mapping is edition-dependent.")


def main():
    rows = []
    rev = S["reviewed"]
    chassis_like = {c for c in rev if E[c]["system"] == "chassis" or c in ("U0121", "U0415") or "ABS" in E[c]["rider_advice_en"] or "wheel speed" in E[c]["title_en"].lower()}
    for c in rev:
        for k in range(1, 13):
            if k == 12 and c not in chassis_like:
                continue
            v, r, f = X.get((c, k), (P, "no problem found" if k != 12 else "wording is position-neutral", ""))
            rows.append((c, f"{k} {CHECKS[k]}", v, r, f))
    with open(os.path.join(HERE, "review_flags_v4_20261002.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["code", "check", "verdict", "reason", "suggested_fix"])
        w.writerows(rows)
    missing = [k for k in X if k[0] not in rev]
    extra = []
    for (c, k) in sorted(missing):
        v, r, f = X[(c, k)]
        extra.append((c, f"{k} {CHECKS[k]} [outside the seeded sample]", v, r, f))
    with open(os.path.join(HERE, "review_flags_v4_20261002.csv"), "a", newline="", encoding="utf-8") as fh:
        csv.writer(fh).writerows(extra)
    print(len(rows), "rows;", len(rev), "entries;", "findings outside the sample (recorded in the report only):", sorted({k[0] for k in missing}))
    cnt = collections.Counter(r[2] for r in rows)
    print(cnt)


if __name__ == "__main__":
    main()
