#!/usr/bin/env python3
"""Self-tests for validate_seed.py. Run: python3 validator_selftest.py

Four parts, all must pass:
  0. baseline: every unmodified entry in generic_en_seed.jsonl validates cleanly
  1. regression: the reviewer's defective entries (review_regression_cases.json)
     are rejected for the right rule. These are permanent.
  2. mutation test: 10 good entries, each broken in a different way a reviewer
     found; the validator must reject all ten with the expected rule.
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
BY = {r["code"]: r for r in ROWS}


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
