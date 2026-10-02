#!/usr/bin/env python3
"""Self-tests for validate_seed.py. Run: python3 validator_selftest.py

Five parts, all must pass (part 2b added 2026-10-02 for the rules R12 to R22 and T1):
  0. baseline: every unmodified entry in generic_en_seed.jsonl validates cleanly
  1. regression: the reviewer's defective entries (review_regression_cases.json)
     are rejected for the right rule. These are permanent.
  2. mutation test: 10 good entries, each broken in a different way a reviewer
     found; the validator must reject all ten with the expected rule.
  2b. v4 mutation test: one good entry per new rule (R12 to R22, T1), each broken the way the batch 1
     reviewer or the owner decisions D1 to D8 describe; the validator must reject each with the named rule
  3. rule coverage and legacy cases: every rule R1 to R11 and the owner
     decisions D1 to D6 are exercised at least once.

A rejection counts only if the expected rule id appears in an error for that
code (so a case cannot pass by accident through another rule).
"""
import copy
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import validate_seed as V  # noqa: E402

OBDEX = os.environ.get("OBDEX_DIR", "/tmp/obdex")
CTX = V.build_context(OBDEX, os.path.join(HERE, "relevance_ranking.csv"))
ROWS = [json.loads(line) for line in open(os.path.join(HERE, "generic_en_seed.jsonl"), encoding="utf-8")
        if line.strip()]
_HELD = os.path.join(HERE, "held_entries_v5.jsonl")  # V5 G3: held-out entries stay usable as test material
BY = {r["code"]: r for r in ROWS}
if os.path.exists(_HELD):
    for _line in open(_HELD, encoding="utf-8"):
        if _line.strip():
            _r = json.loads(_line)
            _r.pop("held_reason", None)
            BY[_r["code"]] = _r


def errors_for(entry):
    errs, _ = V.check_all([entry], CTX)
    return errs


def mutate(code, fn):
    r = copy.deepcopy(BY[code])
    fn(r)
    return r


def expect(label, entry, rule, needle=""):
    errs = [e for e in errors_for(entry) if f": {rule}: " in e and needle.lower() in e.lower()]
    ok = bool(errs)
    print(("PASS " if ok else "FAIL ") + label + ("" if ok else f"   (no {rule} error; got {errors_for(entry)})"))
    return ok


def main():
    results = []
    # ---- 0 baseline
    print("== 0. baseline: unmodified entries are clean")
    errs, _ = V.check_all(ROWS, CTX)
    ok = not errs
    print(("PASS " if ok else "FAIL ") + f"{len(ROWS)} unmodified entries give {len(errs)} errors")
    for e in errs[:10]:
        print("   ", e)
    results.append(ok)

    # ---- 1 regression
    print("== 1. regression: reviewer's defective entries must be rejected")
    cases = json.load(open(os.path.join(HERE, "review_regression_cases.json"), encoding="utf-8"))["cases"]
    for c in cases:
        r = copy.deepcopy(BY[c["code"]])
        r.update(copy.deepcopy(c["fields"]))
        results.append(expect(c["name"], r, c["expect_rule"]))

    # ---- 2 mutation test (10 good entries, 10 different reviewer findings)
    print("== 2. mutation test: ten good entries, ten different defects")
    M = [
        ("R1 circular advice 'stop if it stalls' (P0120)", "P0120",
         lambda r: r.update(rider_advice_en="Idle may be uneven. Get it checked soon; stop and check sooner if the engine stalls or surges."), "R1"),
        ("R2 assumed temperature gauge (P0115)", "P0115",
         lambda r: r.update(rider_advice_en="The bike may be hard to start when cold. Get it checked soon and watch the temperature gauge."), "R2"),
        ("R3 unconditional no-start claim at SERVICE_SOON (P0850)", "P0850",
         lambda r: r.update(rider_advice_en="The bike may not start. Get it checked soon.", can_ride_reason="if it starts, go to a workshop"), "R3"),
        ("R4 petrol smell without the stop instruction (P0172)", "P0172",
         lambda r: r.update(rider_advice_en="Expect black smoke, a petrol smell or poor mileage. Get it checked soon."), "R4"),
        ("R5 hedged ABS advice (U0121)", "U0121",
         lambda r: r.update(rider_advice_en="Normal braking should still work, but ABS may be off. Ride gently and get it checked soon."), "R5"),
        ("R6 low/high swapped on a temperature sensor (P0117)", "P0117",
         lambda r: r.update(meaning_en="The engine temperature signal is lower than the bike's computer (ECU) expects, so the engine looks colder than it is; often a short to ground."), "R6"),
        ("R7 car-only MAF sensor cause (P0171)", "P0171",
         lambda r: r.update(likely_causes_en=["Dirty mass air flow sensor", "Intake air leak (vacuum leak)"]), "R7"),
        ("R8 relay cause without 'if fitted' (P0135)", "P0135",
         lambda r: r.update(likely_causes_en=["Open heater element in the oxygen sensor", "Blown heater fuse or faulty relay"]), "R8"),
        ("R9 workshop phrase leads the meaning (P0122)", "P0122",
         lambda r: r.update(meaning_en="Short to ground or a missing sensor supply makes the throttle position reading too low for the bike's computer (ECU)."), "R9"),
        ("R10 'listed as left front' in a title (C0035)", "C0035",
         lambda r: r.update(title_en="Wheel speed sensor (listed as left front): circuit fault"), "R10"),
    ]
    assert len(M) == 10
    for label, code, fn, rule in M:
        results.append(expect(label, mutate(code, fn), rule))

    # ---- 2b v4 mutation test
    print("== 2b. v4 mutation test: the rules added on 2026-10-02")
    STALL_ = "If it stalls more than once or will not restart, do not keep riding; have it taken to a workshop."
    M2 = [
        ("R12 'may shut off' at SERVICE_SOON (P0130)", "P0130",
         lambda r: r.update(rider_advice_en="The engine may shut off at speed. Get it checked soon."), "R12"),
        ("R12 'will not restart' in the ride reason, unconditional (P0633)", "P0633",
         lambda r: r.update(can_ride_reason="go to a workshop; it will not restart"), "R12"),
        ("R13 STOP not in the table (P0120)", "P0120",
         lambda r: r.update(rider_action_level="STOP", can_ride_to_workshop="no",
                            rider_advice_en="The engine may stop. Pull over safely, switch off and do not keep riding; "
                                            "have the bike taken to a workshop."), "R13"),
        ("R13 table code below STOP (P0335)", "P0335",
         lambda r: r.update(rider_action_level="SERVICE_SOON", can_ride_to_workshop="with_care",
                            rider_advice_en="The engine may stop or not start. Get it checked soon."), "R13"),
        ("R14 'looks colder' on a LOW voltage engine temperature code (P0117)", "P0117",
         lambda r: r.update(rider_action_basis="the engine looks colder than it is"), "R14"),
        ("R15 ABS second sentence off the closed list (C0035)", "C0035",
         lambda r: r.update(rider_advice_en="Your normal brakes still work, but ABS is off, so a wheel can lock in "
                                            "hard braking. Ride as usual."), "R15"),
        ("R16 fuel leak without the PETROL sentence (P0301)", "P0301",
         lambda r: r.update(rider_action_basis="fuel may leak from the injector"), "R16"),
        ("R17 jumper wire in a technician hint (P0105)", "P0105",
         lambda r: r.update(technician_hints_en=["Use a jumper wire to feed the sensor directly"]), "R17"),
        ("R18 STOP reason permits riding (P0201)", "P0201",
         lambda r: r.update(can_ride_reason="you can still ride gently to the workshop"), "R18"),
        ("R19 engine-control code with mil false (P0120)", "P0120",
         lambda r: r["flags"].update(mil=False), "R19"),
        ("R20 knock code without applies_when (P0324)", "P0324",
         lambda r: r.update(applies_when=None), "R20"),
        ("R20 oil temperature code without applies_when (P0195)", "P0195",
         lambda r: r.update(applies_when=None), "R20"),
        ("R21 camshaft stall variant instead of STALL (P0340)", "P0340",
         lambda r: r.update(rider_advice_en="The engine may run rough. If it stalls or will not restart, do not keep "
                                            "riding and have it taken to a workshop."), "R21"),
        ("R21 idle entry without the D3 sentence (P0505)", "P0505",
         lambda r: r.update(rider_advice_en="Idle may be uneven. " + STALL_), "R21"),
        ("R21 CAN entry with the old advice (U0001)", "U0001",
         lambda r: r.update(rider_advice_en="Meters, lamps or safety systems may stop working; ride carefully."), "R21"),
        ("R21 bus fault with review false (U0003)", "U0003",
         lambda r: r.update(needs_independent_review=False), "R21"),
        ("R21 ABS entry without the canonical ABS sentence (U0121)", "U0121",
         lambda r: r.update(rider_advice_en="Your brakes work, but ABS is off, so a wheel can lock. Ride gently, "
                                            "brake early and get it checked soon."), "R21"),
        ("R22 sentence of more than 25 words (P0300)", "P0300",
         lambda r: r.update(meaning_en="The bike's computer (ECU) detected misfires on more than one cylinder or at "
                                       "random times, so combustion is incomplete and the engine may run rough and lose "
                                       "power."), "R22"),
        ("R22 idiom 'cut out' (P0233)", "P0233",
         lambda r: r.update(rider_action_basis="engine may cut out"), "R22"),
        ("R22 idiom 'refuse to start' (P0337)", "P0337",
         lambda r: r.update(rider_advice_en="The engine may refuse to start. Pull over safely, switch off and do not "
                                            "keep riding; have the bike taken to a workshop."), "R22"),
        ("R22 discouraged word 'module' (U0155)", "U0155",
         lambda r: r.update(meaning_en="The bike's computer (ECU) stopped receiving messages from the cluster module."),
         "R22"),
        ("D2 P0232 back to STOP", "P0232",
         lambda r: r.update(rider_action_level="STOP", can_ride_to_workshop="no"), "R13"),
        ("D2 P0604 loses the TWO-CASE advice", "P0604",
         lambda r: r.update(rider_advice_en="The engine may stall. Get it checked soon."), "D"),
        ("D5 P068B loses the battery statement", "P068B",
         lambda r: r.update(rider_advice_en="Have it checked soon; it may behave oddly."), "D"),
        ("D7 P0512 unconditional no-restart reason", "P0512",
         lambda r: r.update(can_ride_reason="go to a workshop; it may not restart"), "R12"),
    ]
    for label, code, fn, rule in M2:
        results.append(expect(label, mutate(code, fn), rule))
    # ---- 2c v5 mutation test: the groups G2 to G8 of 2026-10-02 (owner decisions after the review of V4)
    print("== 2c. v5 mutation test: owner decisions G2 to G8")
    IDLE_STACK = "If it stalls more than once or will not restart, do not keep riding; have it taken to a workshop."
    OLD_BATTERY = ("If the battery is hot, swollen or smells of rotten eggs, or the lights are very bright or bulbs keep "
                   "blowing, stop, switch off and do not ride on.")
    M3 = [
        ("G2 standard title back to the OBDex wording (P0351)", "P0351",
         lambda r: r.update(standard_title_en='Ignition Coil "A" Primary/Secondary Circuit Malfunction (Cylinder 1)'), "S"),
        ("G4 P2100 back to SERVICE_SOON", "P2100",
         lambda r: r.update(rider_action_level="SERVICE_SOON", can_ride_to_workshop="with_care",
                            rider_advice_en="The throttle may not follow the twist grip. Get it checked soon."), "R13"),
        ("G4 P2111 loses the slow-down advice", "P2111",
         lambda r: r.update(rider_advice_en="Pull over safely, switch off and do not keep riding; have the bike taken to a workshop."), "D"),
        ("G5 idle entry with the stacked STALL sentence (P0506)", "P0506",
         lambda r: r.update(rider_advice_en="If it stalls once at a stop, ride gently, avoid heavy traffic and have it checked soon. " + IDLE_STACK), "R21"),
        ("G5 idle entry with the old first sentence (P0509)", "P0509",
         lambda r: r.update(rider_advice_en="If it stalls at stops or will not hold idle, ride gently, avoid heavy traffic and have it checked soon. If it stalls more than once or will not restart, do not keep riding."), "R21"),
        ("G6 cylinder 1 STOP entry loses the twin clause (P0201)", "P0201",
         lambda r: r.update(rider_advice_en="The engine may misfire, lose power or stop. Pull over safely, switch off and do not keep riding; have the bike taken to a workshop."), "D"),
        ("G7 the old 29-word battery sentence is no longer allowed (P0563)", "P0563",
         lambda r: r.update(rider_advice_en=OLD_BATTERY + " Otherwise ride only a short way, in daylight, to a workshop."), "R22"),
        ("G8 CAN entry without can_bus_fitted (U0001)", "U0001",
         lambda r: r.update(applies_when=None), "R20"),
        ("G8 idiom 'misbehave' (P0602)", "P0602",
         lambda r: r.update(rider_action_basis="ECU may misbehave"), "R22"),
        ("G8 idiom 'pulling the bus down' (U0004)", "U0004",
         lambda r: r.update(likely_causes_en=["CAN plus wire short to ground", "A faulty unit pulling the bus down"]), "R22"),
        ("G8 discouraged word 'sender' (P0460)", "P0460",
         lambda r: r.update(likely_causes_en=["Failed fuel level sender", "Damaged wiring or loose connector"]), "R22"),
    ]
    for label, code, fn, rule in M3:
        results.append(expect(label, mutate(code, fn), rule))
    # T1: a new entry (not written before Step T) whose title the two sources do not agree on
    t1 = copy.deepcopy(BY["P0420"])
    t1["code"], t1["content_id"] = "P0449", "generic:P0449:en"
    results.append(expect("T1 new entry for a code whose title is DISAGREE (P0449)", t1, "T1"))

    # ---- 3 rule coverage, owner decisions and legacy cases
    print("== 3. rule coverage, owner decisions D1 to D6 and legacy cases")
    X = [
        ("R1 reverse order 'if it cuts out, pull over' (P0340)", "P0340",
         lambda r: r.update(rider_advice_en="Get it checked soon. If the engine cuts out, pull over."), "R1"),
        ("R2 blinking lamp (P0300)", "P0300",
         lambda r: r.update(rider_advice_en="Expect rough running. Get it checked soon; stop if the warning lamp blinks."), "R2"),
        ("R2 tachometer (P0505)", "P0505",
         lambda r: r.update(rider_advice_en="Idle may hunt. Watch the tachometer and get it checked soon."), "R2"),
        ("R2 scan tool in rider text (U0100)", "U0100",
         lambda r: r.update(meaning_en="Another unit or the scan tool could not get messages from the engine computer (ECU)."), "R2"),
        ("R3 STOP advice that never says stop (P0201)", "P0201",
         lambda r: r.update(rider_advice_en="The engine may misfire. Have it checked."), "R3"),
        ("R3 MONITOR with unconditional stall claim (P0420)", "P0420",
         lambda r: r.update(rider_advice_en="The engine will stall at low speed. Get it checked at the next service."), "R3"),
        ("R4 fuel smell in a cause (P0132)", "P0132",
         lambda r: r.update(rider_advice_en="Expect poor mileage and a fuel smell; get it checked soon."), "R4"),
        ("R5 level STOP for an ABS code (U0121)", "U0121",
         lambda r: r.update(rider_action_level="STOP", can_ride_to_workshop="no",
                            rider_advice_en="Pull over and do not keep riding. Your normal brakes still work, but ABS is off, so a wheel can lock in hard braking."), "R5"),
        ("R5 missing 'wheel can lock' (C0035)", "C0035",
         lambda r: r.update(rider_advice_en="Your normal brakes still work, but ABS is off. Ride gently and get it checked soon."), "R5"),
        ("R6 high title on a low code (P0107)", "P0107",
         lambda r: r.update(title_en="Intake manifold pressure (MAP) sensor: voltage above threshold"), "R6"),
        ("R6 intake air low must say hotter (P0112)", "P0112",
         lambda r: r.update(meaning_en="The intake air temperature signal is lower than the bike's computer (ECU) expects, so the air looks colder than it is."), "R6"),
        ("R7 timing chain cause not marked rare (P0335)", "P0335",
         lambda r: r.update(likely_causes_en=["Faulty crankshaft position sensor", "Stretched timing chain"]), "R7"),
        ("R7 catalytic converter as cause of another code (P0130)", "P0130",
         lambda r: r.update(likely_causes_en=["Aged oxygen sensor", "Blocked catalytic converter"]), "R7"),
        ("R8 hose without 'if hose-fed' (P0105)", "P0105",
         lambda r: r.update(likely_causes_en=["Faulty intake pressure (MAP) sensor", "Cracked vacuum hose"]), "R8"),
        ("R10 'bank 2' in a title (P0300)", "P0300",
         lambda r: r.update(title_en="Misfire detected (bank 2)"), "R10"),
        ("R10 duplicate title across codes", "P0301",
         lambda r: r.update(title_en=BY["P0302"]["title_en"]), "R10dup"),
        ("R11 missing applies_when on a cylinder 2 code (P0202)", "P0202",
         lambda r: r.update(applies_when=None), "R11"),
        ("R11 bad can_ride value (P0201)", "P0201",
         lambda r: r.update(can_ride_to_workshop="with_care"), "R11"),
        ("R11 verification label (P0120)", "P0120",
         lambda r: r.update(verification="manufacturer_verified"), "R11"),
        ("R11 schema version 1 (P0120)", "P0120",
         lambda r: r.update(schema_version=1), "R11"),
        ("D6 the word 'verified' (P0120)", "P0120",
         lambda r: r.update(rider_advice_en="This advice is verified. " + r["rider_advice_en"]), "D6"),
        ("D1 P0563 loses the stop triggers", "P0563",
         lambda r: r.update(rider_advice_en="Overcharging can damage the battery. Get it checked soon."), "D"),
        ("D2 U0100 gets back a no-start claim", "U0100",
         lambda r: r.update(rider_advice_en="The engine may not start. Get it checked soon."), "D"),
        # legacy cases from the pilot self-test
        ("S title too long", "P0120", lambda r: r.update(title_en="x" * 80), "S", "limit 70"),
        ("S banned absolute", "P0105", lambda r: r.update(rider_advice_en="This will always work."), "S", "banned absolute"),
        ("S currency", "P0105", lambda r: r.update(rider_advice_en="It may cost 500 rupees."), "S", "currency"),
        ("S url", "P0105", lambda r: r.update(rider_advice_en="See www.example.com."), "S", "URL"),
        ("S rubric level", "P0201", lambda r: r.update(rider_action_level="MONITOR", can_ride_to_workshop="yes"), "S", "not allowed"),
        ("S STOP without review", "P0351", lambda r: r.update(needs_independent_review=False), "S", "needs_independent_review"),
        ("S chassis without review", "C0035", lambda r: r.update(needs_independent_review=False), "S", "needs_independent_review"),
        ("S unsourced part", "P0110", lambda r: r["likely_causes_en"].append("Failed fuel pump"), "S", "not in the source"),
        ("S voltage figure", "P0195", lambda r: r.update(meaning_en="The signal is stuck at 5 V."), "S", "number with unit"),
        ("S variant phrase", "P0195", lambda r: r.update(meaning_en="The signal is shorted to ground."), "S", "short to ground"),
        ("S german", "P0130", lambda r: r.update(meaning_en="Größe des Sensors."), "S", "German"),
        ("S bad hash", "P0135", lambda r: r["derived_from"].update(source_entry_sha256="0" * 64), "S", "sha256"),
        ("S wrong term", "P0335", lambda r: r.update(rider_advice_en="Check engine light is on. Pull over and do not keep riding."), "S", "warning lamp"),
        ("S two-sentence meaning", "P0120", lambda r: r.update(meaning_en="One thing. Two things."), "S", "one sentence"),
        ("S too many causes", "P0120", lambda r: r.update(likely_causes_en=["a b", "c d", "e f", "g h", "i j"]), "S", "2 to 4"),
        ("S limp mode wording", "P0120", lambda r: r.update(rider_advice_en="It may go into limp mode."), "S", "reduced power mode"),
        ("S system mismatch", "U0100", lambda r: r.update(system="powertrain"), "S", "prefix"),
        ("S standard title altered", "P0120", lambda r: r.update(standard_title_en="Something else"), "S", "standard_title_en"),
    ]
    for case in X:
        label, code, fn, rule = case[:4]
        needle = case[4] if len(case) > 4 else ""
        r = mutate(code, fn)
        if rule == "R10dup":  # needs two entries
            errs, _ = V.check_all([r, copy.deepcopy(BY["P0302"])], CTX)
            ok = any(": R10: title duplicates" in e for e in errs)
            print(("PASS " if ok else "FAIL ") + label)
            results.append(ok)
        else:
            results.append(expect(label, r, rule, needle))

    bad = results.count(False)
    print(f"\n{len(results) - bad}/{len(results)} validator tests passed")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
