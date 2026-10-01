#!/usr/bin/env python3
"""Review run 2026-10-01, section D: try to defeat validate_seed.py.

Builds six new defective entries (plus two bonus ones), each breaking a different
safety property, and runs the CURRENT validator on them in process. Then runs the
PROPOSED extra rules (R12 to R19, defined below in this file only; validate_seed.py
is not modified) on the same entries and on all real entries to show they catch
the defects without false alarms.

Usage: OBDEX_DIR=/tmp/obdex python3 review_validator_defeat_20261001.py
"""
import copy
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import validate_seed as V  # noqa: E402

OBDEX = os.environ.get("OBDEX_DIR", "/tmp/obdex")
CTX = V.build_context(OBDEX, os.path.join(HERE, "relevance_ranking.csv"))
ROWS = [json.loads(line) for line in open(os.path.join(HERE, "generic_en_seed.jsonl"), encoding="utf-8")
        if line.strip()]
BY = {r["code"]: r for r in ROWS}

# ----------------------------------------------------------------------------
# PROPOSED RULES (not in validate_seed.py). Each returns a list of messages.
# ----------------------------------------------------------------------------
# Codes the reviewer recommends keeping at STOP after batch 1 (section STOP calibration of the
# report). Two-way lock: a code in this set may not be below STOP, and no other code may be STOP.
# The owner edits this one table to change a STOP decision.
STOP_LOCK = {
    "P0201", "P0200", "P0261", "P0262", "P0351", "P0350", "P0335", "P0336", "P0337", "P0338", "P0339",
    "P0230", "P0231", "P0232", "P0233", "P0627", "P0628", "P0629", "P0685", "P0686", "P0217",
}

R12_CLAIM = re.compile(
    r"\b(shuts?|shut(ting)?) (off|down)\b|\bstops? (running|suddenly|dead)\b|\bconks? out\b|"
    r"\bgoes? (dead|off)\b|\bloses? (all|total) power\b|\b(will not|won't|may not|might not|can ?not|cannot|"
    r"does not|doesn't|fails? to) (re)?start\b|\b(will not|won't|may not|cannot|can't) (turn over|crank)\b|"
    r"\bdies?\b|\bdying\b|\bseiz(es|e|ing)\b|\b(stall(s|ed|ing)?|cuts? out|cutting out)\b", re.I)
R12_IF_BEFORE = re.compile(r"\bif\b(?! you (like|wish|want|prefer|must))[^;.]{0,60}$", re.I)

R14_WRONG = {  # direction words that contradict a LOW or HIGH temperature sensor code, in any rider field
    "LOW": re.compile(r"(looks?|reads?|thinks?|seems?|believes?|shows?)[^.;]{0,40}\b(colder|cooler|cold)\b", re.I),
    "HIGH": re.compile(r"(looks?|reads?|thinks?|seems?|believes?|shows?)[^.;]{0,40}\b(hotter|warmer|hot)\b", re.I),
}
R15_REASSURE = re.compile(r"\bno need\b|\bnot a problem\b|\bnothing to worry\b|\bsafe to\b|\bnormal speed\b|"
                          r"\bno risk\b|\bfine in the (rain|wet)\b|\bride (as usual|normally)\b|\bnot (a )?(danger|risk)\b|"
                          r"\bno (danger|hazard)\b|\bwithout (any )?(worry|concern)\b|\bnormal (riding|braking)\b", re.I)
R15_ALLOWED_SECOND = {
    "ride gently, brake early and get it checked soon.",
    "ride gently, brake early, avoid wet roads and get it checked soon.",
}
R16_FUEL = re.compile(r"(fuel|petrol|gasoline)[^.;]{0,40}\b(leak\w*|drip\w*|spill\w*|wet|fumes?|flood\w*|puddle|"
                      r"soak\w*)\b|\b(leak\w*|drip\w*|spill\w*|fumes?|flood\w*)\b[^.;]{0,40}(fuel|petrol|gasoline)", re.I)
R16_KEEP = re.compile(r"\b(keep riding|carry on|ride on|wipe|ignore|no need to stop|continue riding)\b", re.I)
R17_UNSAFE_HINT = re.compile(
    r"\bbypass\w*\b|\bjumper\b|\bjump(er)?(ing)? (the )?(relay|switch|wire)|short(ing)? (the )?(terminals?|pins?)|"
    r"disconnect(ing)? the battery (while|with) the engine (is )?running|battery (lead|cable)s? off while|"
    r"(open|remove) the (radiator|coolant|fuel) cap (while|when) (it is |the engine is )?(hot|running)|"
    r"spark[- ](test|check)\w* (near|over|beside) (the )?(fuel|tank|injector)|run(ning)? the engine (dry|without oil)",
    re.I)
R18_PERMIT = re.compile(r"\byou can (still )?ride\b|\bride (on|home)\b|\bsafe to ride\b|\bride gently\b|\bshort ride\b|"
                        r"\bif you must\b|\bkeep riding to\b|\bto the workshop at\b|\bnormal speed\b|\bfine to ride\b", re.I)
R19_FLAGS_FLOOR = {  # tags whose codes the engine unit normally lights the warning lamp for
    "injector", "ignition_coil", "crankshaft", "fuel_pump", "misfire", "throttle", "map_baro", "ect", "o2_sensor",
    "o2_heater", "fuel_trim", "camshaft", "knock", "idle", "system_voltage", "control_module", "ecu_power_relay",
    "sensor_reference_supply", "catalyst", "cam_crank_sync", "starter_relay",
}


def segs(text):
    return [s.strip() for s in re.split(r"(?<=[.])\s+", text) if s.strip()]


def proposed(r):
    out = []
    c = r["code"]
    lvl = r["rider_action_level"]
    tags = CTX["tags"].get(c, [])
    rk = CTX["rank"].get(c)
    fields = ["meaning_en", "rider_action_basis", "rider_advice_en", "can_ride_reason"]
    # R12 broader level/text agreement; 'if' must come BEFORE the claim, and not 'if you like'
    if lvl in ("SERVICE_SOON", "MONITOR", "INFO"):
        for f in fields:
            for sg in segs(r[f]):
                for part in re.split(r"[;]", sg):
                    m = R12_CLAIM.search(part)
                    if m and not R12_IF_BEFORE.search(part[:m.start()]):
                        out.append(f"R12 {lvl} entry makes an unconditional claim '{m.group(0)}' in {f}")
    # R13 STOP lock (two-way)
    if lvl == "STOP" and c not in STOP_LOCK:
        out.append("R13 STOP level is not in the owner's STOP table")
    if lvl != "STOP" and c in STOP_LOCK:
        out.append("R13 code is in the owner's STOP table but the level is below STOP")
    # R14 direction words in every rider field for temperature sensors
    if rk is not None and set(tags) & V.R6_TEMP_TAGS:
        d = V.direction(rk["title_standard"])
        if d:
            for f in fields:
                m = R14_WRONG[d].search(r[f])
                if m:
                    out.append(f"R14 {d} temperature code but {f} says '{m.group(0)}' (wrong direction)")
    # R15 ABS: no reassurance anywhere; second sentence from a closed list
    if set(tags) & V.ABS_TAGS or c[0] == "C":
        for f in ("rider_advice_en", "rider_action_basis", "can_ride_reason", "meaning_en"):
            m = R15_REASSURE.search(r[f])
            if m:
                out.append(f"R15 ABS entry reassures the rider in {f}: '{m.group(0)}'")
        ss = segs(r["rider_advice_en"])
        if len(ss) == 2 and ss[1].lower() not in R15_ALLOWED_SECOND:
            out.append(f"R15 ABS second sentence is not on the approved list: '{ss[1]}'")
    # R16 fuel leak / fumes in rider text needs the PETROL sentence and no 'keep riding'
    for f in ("meaning_en", "rider_action_basis", "rider_advice_en", "can_ride_reason"):
        m = R16_FUEL.search(r[f])
        if m and not V.STRONG_SMELL.search(r["rider_advice_en"]):
            out.append(f"R16 fuel leak or fumes in {f} ('{m.group(0)}') without the PETROL stop sentence")
        if m and R16_KEEP.search(r[f]):
            out.append(f"R16 fuel leak in {f} with a keep-riding instruction ('{R16_KEEP.search(r[f]).group(0)}')")
    # R17 unsafe technician hints; rider text may only say 'bypass' as 'do not bypass'
    for h in r["technician_hints_en"]:
        m = R17_UNSAFE_HINT.search(h)
        if m:
            out.append(f"R17 unsafe technician hint: '{m.group(0)}'")
    for f in ("rider_advice_en", "can_ride_reason"):
        for sg in segs(r[f]):
            if re.search(r"\bbypass", sg, re.I) and not re.search(r"(do not|don't|never) (try to )?bypass", sg, re.I) \
                    and not re.search(r"\bdo not bypass", sg, re.I):
                out.append(f"R17 rider text mentions bypass without 'do not bypass': '{sg}'")
    # R18 STOP text must not permit riding
    if lvl == "STOP":
        for f in ("rider_advice_en", "can_ride_reason", "rider_action_basis"):
            m = R18_PERMIT.search(r[f])
            if m:
                out.append(f"R18 STOP entry permits riding in {f}: '{m.group(0)}'")
        ss = segs(r["rider_advice_en"])
        if not any("pull over" in s.lower() and "do not keep riding" in s.lower() for s in ss):
            out.append("R18 STOP advice lacks 'pull over ... do not keep riding'")
    # R19 flags: a code with a lamp-relevant tag must have mil true; STOP entries must have limp_possible or mil true
    if set(tags) & R19_FLAGS_FLOOR and c[0] == "P" and not r["flags"]["mil"]:
        out.append("R19 powertrain code with an engine-control tag has mil false")
    return out


# ----------------------------------------------------------------------------
# the defective entries
# ----------------------------------------------------------------------------
def mk(code, **fields):
    r = copy.deepcopy(BY[code])
    r.update(fields)
    return r


DEFECTS = [
    ("D1", "synonym gap: unconditional stop-running claim below STOP",
     "P0130 (O2 sensor circuit fault, SERVICE_SOON, can ride yes)",
     mk("P0130",
        rider_action_basis="engine shuts off at speed",
        rider_advice_en="The engine will shut off suddenly at speed and will not restart. Get it checked soon.",
        can_ride_reason="engine shuts off without warning; keep riding to the workshop")),
    ("D2", "STOP calibration inverted: fuel pump circuit open set to SERVICE_SOON",
     "P0627 (fuel pump control circuit: open circuit)",
     mk("P0627",
        rider_action_level="SERVICE_SOON", rider_action_basis="pump may not run",
        rider_advice_en="The engine may be hard to start. If the engine runs normally, have it checked soon; "
                        "if it stalls or will not start, do not keep riding.",
        can_ride_to_workshop="with_care", can_ride_reason="ride only if the engine runs normally",
        needs_independent_review=True)),
    ("D3", "direction reversed in rider advice and basis (engine temperature HIGH voltage = looks colder)",
     "P0118 (engine temperature sensor: voltage above threshold)",
     mk("P0118",
        rider_action_basis="cooling may switch on too often",
        rider_advice_en="The engine looks hotter than it is, so cooling may switch on more often than needed. "
                        "There is no risk of overheating; get it checked at the next service.",
        can_ride_reason="cooling runs too often only; safe in traffic and heat")),
    ("D4", "ABS entry: standard sentence present, then a reassuring second sentence",
     "U0121 (ABS control unit: communication lost)",
     mk("U0121",
        rider_advice_en="Your normal brakes still work, but ABS is off, so a wheel can lock in hard braking. "
                        "There is no need to ride differently in the rain.",
        can_ride_reason="brakes work, ABS off; fine in the rain and at full speed")),
    ("D5", "fuel leak and fire risk without the word 'smell': keep riding",
     "P0172 (fuel mixture too rich)",
     mk("P0172",
        rider_action_basis="fuel may leak onto the hot engine",
        rider_advice_en="Fuel may be leaking onto the hot engine and fumes can build up. "
                        "Wipe it off and keep riding; get it checked soon.",
        can_ride_reason="fuel may drip onto the engine; usually rideable")),
    ("D6", "unsafe technician hint that contradicts the rider advice",
     "P0850 (neutral switch input: circuit fault); rider advice says do not bypass any safety switch",
     mk("P0850",
        technician_hints_en=["Bypass the neutral switch with a jumper wire to see whether the bike starts",
                             "Check the switch connector for oil, water and corrosion",
                             "Take a battery lead off while the engine is running to see if the fault clears"])),
    ("B7", "bonus: the word 'if' used as a loophole ('if you like')",
     "P0109 (intake pressure (MAP) sensor: intermittent circuit fault)",
     mk("P0109",
        rider_advice_en="Ride on if you like, because the engine will stall without warning in traffic. "
                        "Get it checked when convenient.")),
    ("B8", "bonus: STOP entry whose text permits riding on",
     "P0335 (crankshaft position sensor A: circuit fault)",
     mk("P0335",
        rider_advice_en="Pull over safely, switch off and do not keep riding. If you must, you can still ride "
                        "gently home at normal speed.",
        can_ride_reason="safe to ride home gently; workshop can wait")),
]


def main():
    print(f"validate_seed.py version in use: rules R1 to R11 + D; OBDex {CTX['commit'][:12]}")
    base_errs, base_warns = V.check_all(ROWS, CTX)
    print(f"baseline: {len(ROWS)} real entries -> {len(base_errs)} errors, {len(base_warns)} warnings")
    accepted = caught = 0
    results = []
    for did, prop, target, entry in DEFECTS:
        errs, warns = V.check_all([entry], CTX)
        pm = proposed(entry)
        acc = not errs
        accepted += acc
        caught += bool(pm)
        results.append((did, acc, pm))
        print(f"\n{did} {prop}\n  target: {target}\n  current validator: "
              f"{'ACCEPTED (0 errors)' if acc else 'rejected: ' + '; '.join(errs)}"
              f"{' | warnings: ' + '; '.join(warns) if warns else ''}\n  proposed rules: "
              f"{'; '.join(pm) if pm else 'NOT CAUGHT'}")
    print(f"\nSUMMARY: {accepted} of {len(DEFECTS)} defective entries accepted by the current validator; "
          f"{caught} of {len(DEFECTS)} flagged by the proposed rules")
    # false positives of the proposed rules on the 140 real entries
    fp = {}
    for r in ROWS:
        for m in proposed(r):
            fp.setdefault(m.split()[0], []).append(f"{r['code']}: {m}")
    print("\nPROPOSED RULES on the 140 real entries (every hit needs a human look):")
    if not fp:
        print("  no hits")
    for k in sorted(fp):
        print(f"  {k}: {len(fp[k])} hits")
        for x in fp[k][:40]:
            print("     ", x)
    return 0


if __name__ == "__main__":
    sys.exit(main())
