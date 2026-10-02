#!/usr/bin/env python3
"""Review task E (2026-10-02): six NEW defective entries that the V4 validator still accepts, plus two bonus ones,
and the proposed rules Q1 to Q8 that would catch them. Run: OBDEX_DIR=/path/to/OBDex python3 review_attacks_v4_20261002.py
Nothing here edits validate_seed.py or any entry. The attacks are built in process from real entries."""
import copy, json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import validate_seed as V

OBDEX = os.environ.get("OBDEX_DIR", "/tmp/obdex")
CTX = V.build_context(OBDEX, os.path.join(HERE, "relevance_ranking.csv"))
ROWS = [json.loads(l) for l in open(os.path.join(HERE, "generic_en_seed.jsonl"), encoding="utf-8") if l.strip()]
BY = {r["code"]: r for r in ROWS}
STALL = V.STALL


def mk(code, **kw):
    r = copy.deepcopy(BY[code])
    for k, v in kw.items():
        if k == "flags":
            r["flags"].update(v)
        else:
            r[k] = v
    return r


ATTACKS = [
    ("A1", "Always-true 'if' hides a near-certain stall and no-restart claim at SERVICE_SOON (R3 and R12 loophole)",
     "P0121", mk("P0121",
                 rider_advice_en="If you ride in traffic, the engine will stall and will not restart. " + STALL,
                 can_ride_reason="idle may be uneven; avoid traffic and long trips")),
    ("A2", "Fire risk written with words R16 does not know (seeping, vapour, hot engine) and no PETROL sentence",
     "P0301", mk("P0301",
                 rider_action_basis="fuel seeping onto the hot engine",
                 rider_advice_en="Fuel may be seeping from the injector onto the hot engine and vapour can collect "
                                 "under the seat. Ride gently and get it checked soon.")),
    ("A3", "Direction reversed on a 'Too Low' standard title (R6 and R14 skip 'too low' and 'too high' titles)",
     "P0524", mk("P0524", title_en="Engine oil pressure too high",
                 meaning_en="The bike's computer (ECU) found that the engine oil pressure is above the safe limit, "
                            "which can quickly damage the engine.",
                 likely_causes_en=["Cold, thick engine oil", "Blocked oil passage", "Faulty oil pressure sensor"])),
    ("A4", "Brake light switch code downgraded to MONITOR, reassuring, review false, confidence high",
     "P0504", mk("P0504", rider_action_level="MONITOR", can_ride_to_workshop="yes", confidence="high",
                 needs_independent_review=False,
                 rider_action_basis="minor brake light fault",
                 rider_advice_en="The brake light is a minor matter. The bike rides normally; get the switch checked "
                                 "at the next service.",
                 can_ride_reason="brake light only; ride normally")),
    ("A5", "STOP advice tells the rider to open the hot radiator cap (R17 checks technician hints only)",
     "P0217", mk("P0217",
                 rider_advice_en="Pull over safely, switch off and do not keep riding; have the bike taken to a "
                                 "workshop. Open the radiator cap at once to let the steam out and add cold water.")),
    ("A6", "Brake fluid loss implied by an ABS pump entry that stays SERVICE_SOON (nothing checks braking hydraulics)",
     "C0020", mk("C0020",
                 likely_causes_en=["Low brake fluid or a leaking brake line", "Pump motor seized after long inactivity",
                                   "Corroded power supply connection"],
                 technician_hints_en=["Check the brake fluid level and top it up if it is low",
                                      "Check the ABS pump motor supply and ground connections"])),
    ("B1", "Bonus: wheel position named in meaning and hint of a wheel speed entry (owner rule: position-neutral)",
     "C0037", mk("C0037",
                 meaning_en="The ABS control unit found a fault in the left front wheel speed sensor, so ABS is "
                            "probably switched off.",
                 technician_hints_en=["Replace the left front wheel speed sensor first",
                                      "Check the sensor signal on the scan tool while the wheel turns"])),
    ("B2", "Bonus: can_ride_reason contradicts the level and the entry's own warning (lean mixture overheats the engine)",
     "P2177", mk("P2177", can_ride_reason="ride normally; long trips are fine")),
]


# ---- proposed rules ---------------------------------------------------------------------------------------------
def _sents(t):
    return V._sentences(t)


TRIGGER = re.compile(r"stall|loses? power|power loss|will not (re)?start|does not (re)?start|runs? very rough|rough|hot|swollen|"
                     r"keeps turning|hold idle|runs normally|battery|key|lamp stays on|smell|lock", re.I)
CERTAIN = re.compile(r"\bwill (stall|not (re)?start|stop|shut|die|fail|lose)\b|\bwill not restart\b", re.I)


def q1(r):
    """Q1: below STOP, a claim of stall, stop or no-start that follows a comma-separated 'if' clause needs a real symptom
    in that clause ('if you ride in traffic, the engine will stall' is not a condition). Canonical sentences are exempt."""
    out = []
    if r["rider_action_level"] == "STOP":
        return out
    canon = {V.STALL, V.TWO_CASE, V.IDLE_FIRST, V.BATTERY, V.BATTERY_HOT, V.STOP_TAIL, V.PETROL, V.ABS_SENT}
    for f in ("meaning_en", "rider_action_basis", "rider_advice_en", "can_ride_reason"):
        for sg in _sents(r[f]):
            if sg in canon:
                continue
            for part in sg.split(";"):
                m = V.R12_CLAIM.search(part) or CERTAIN.search(part)
                if not m:
                    continue
                ifm = re.search(r"\bif\b(.*)$", part[:m.start()], re.I)
                if ifm and "," in ifm.group(1) and not TRIGGER.search(ifm.group(1)):
                    out.append(f"Q1 the 'if' before '{m.group(0)}' names no real symptom in {f}: '{ifm.group(0).strip()}'")
    return out


FIRE = re.compile(r"(fuel|petrol|vapou?rs?)[^.;]{0,60}\b(seep\w*|ooze\w*|weep\w*|dribbl\w*|escap\w*|build\w* up|collect\w*|"
                  r"ignit\w*|catch\w* fire|on fire|hot (engine|exhaust|part)s?)\b|"
                  r"\b(seep\w*|ooze\w*|weep\w*|dribbl\w*|collect\w*)\b[^.;]{0,40}(fuel|petrol|vapou?r)", re.I)


def q2(r):
    """Q2: fuel or vapour that seeps, collects or reaches a hot part needs the PETROL sentence (extends R16)."""
    out = []
    for f in ("meaning_en", "rider_action_basis", "rider_advice_en", "can_ride_reason"):
        m = FIRE.search(r[f])
        if m and V.PETROL not in r["rider_advice_en"]:
            out.append(f"Q2 fire-risk wording '{m.group(0)}' in {f} without the PETROL sentence")
    return out


def q3(r):
    """Q3: 'too low/too high' and 'low/high' standard titles: title_en and meaning_en must not say the opposite."""
    out = []
    rk = CTX["rank"].get(r["code"])
    if not rk:
        return out
    std = re.sub(r"\(.*?\)", "", rk["title_standard"]).strip()
    m = re.search(r"\b(too )?(low|high)\s*(input|voltage)?\s*$", std, re.I)
    if not m:
        return out
    low = m.group(2).lower() == "low"
    lowrx, highrx = r"\b(below|low|lower|too low)\b", r"\b(above|higher|high|too high)\b"
    right, wrong = (lowrx, highrx) if low else (highrx, lowrx)
    for f in ("title_en", "meaning_en"):
        if re.search(wrong, r[f], re.I) and not re.search(right, r[f], re.I):
            out.append(f"Q3 standard title says {'LOW' if low else 'HIGH'} but {f} says the opposite")
    return out


BRAKE = re.compile(r"\bbrak(e|es|ing)\b", re.I)


def q4(r):
    """Q4: any entry that talks about braking needs review true, high confidence is not allowed, and MONITOR is not allowed."""
    out = []
    txt = " ".join([r["title_en"], r["meaning_en"], r["rider_advice_en"], r["rider_action_basis"], r["can_ride_reason"]])
    if BRAKE.search(txt) or "brake" in r["standard_title_en"].lower():
        if r["needs_independent_review"] is not True:
            out.append("Q4 braking text but needs_independent_review is not true")
        if r["rider_action_level"] not in ("SERVICE_SOON", "STOP"):
            out.append(f"Q4 braking text at level {r['rider_action_level']} (SERVICE_SOON or STOP only)")
        if r["confidence"] == "high":
            out.append("Q4 braking text with confidence high (no braking entry may be high until a mechanic has seen it)")
    return out


UNSAFE_RIDER = re.compile(r"\b(open|remove|take off|loosen|unscrew)\b[^.;]{0,30}\b(radiator|coolant|filler|fuel|oil|tank)?\s?cap\b|"
                          r"\b(pour|splash|spray)\b[^.;]{0,20}\bwater\b|\bblow (out|into)\b|\btouch the (exhaust|engine|silencer)\b|"
                          r"\bcheck the (fuel|petrol) (level )?with (a )?(match|lighter|flame)\b", re.I)


def q5(r):
    """Q5: rider text and hints may only mention opening a cap as 'do not open the cap while it is hot'."""
    out = []
    texts = [("rider_advice_en", r["rider_advice_en"]), ("can_ride_reason", r["can_ride_reason"])] + \
        [("hint", h) for h in r["technician_hints_en"]]
    for f, t in texts:
        for sg in _sents(t):
            m = UNSAFE_RIDER.search(sg)
            if m and not re.search(r"\b(do not|don't|never)\b[^.;]{0,15}$", sg[:m.start()] + " ", re.I) \
                    and not re.search(r"\b(do not|don't)\s+(open|remove)", sg, re.I):
                out.append(f"Q5 unsafe instruction in {f}: '{m.group(0)}'")
    return out


HYDRAULIC = re.compile(r"\bbrake (fluid|line|hose|pad|disc|disk|pipe)s?\b|\bhydraulic\b|\bmaster cylinder\b|\bcaliper\b|"
                       r"\bair in the (brake|lines?)\b", re.I)


def q6(r):
    """Q6: braking hydraulics are out of scope for a generic electronic code: any such word is an error unless the source has it."""
    out = []
    src = V.source_text(CTX["obdex"][r["code"]]) if r["code"] in CTX["obdex"] else ""
    for f in ("title_en", "meaning_en", "rider_advice_en", "rider_action_basis", "can_ride_reason"):
        m = HYDRAULIC.search(r[f])
        if m and m.group(0).lower() not in src:
            out.append(f"Q6 braking hydraulics '{m.group(0)}' in {f}, not in the source")
    for x in list(r["likely_causes_en"]) + list(r["technician_hints_en"]):
        m = HYDRAULIC.search(x)
        if m and m.group(0).lower() not in src:
            out.append(f"Q6 braking hydraulics '{m.group(0)}' in '{x[:40]}', not in the source")
    return out


POSITION = re.compile(r"\b(left|right)\b|\b(left|right) (front|rear)\b|\bfront left\b|\bfront right\b", re.I)


def q7(r):
    """Q7: wheel speed entries name no left or right wheel in any text field (owner rule: position-neutral)."""
    out = []
    tags = CTX["tags"].get(r["code"], [])
    if "wheel_speed" in tags or r["code"][0] == "C":
        for f in ("title_en", "meaning_en", "rider_advice_en", "can_ride_reason"):
            m = POSITION.search(r[f])
            if m:
                out.append(f"Q7 wheel position '{m.group(0)}' in {f}")
        for x in list(r["likely_causes_en"]) + list(r["technician_hints_en"]):
            m = POSITION.search(x)
            if m:
                out.append(f"Q7 wheel position '{m.group(0)}' in '{x[:40]}'")
    return out


PERMIT_RISK = re.compile(r"\b(ride normally|long trips (are|is) fine|no need to (slow|stop|worry)|ride as (usual|normal)|"
                         r"carry on as normal|as far as you like)\b", re.I)


def q8(r):
    """Q8: below STOP, can_ride_reason and advice may not permit normal or long riding when the level is SERVICE_SOON with_care."""
    out = []
    if r["rider_action_level"] == "SERVICE_SOON" and r["can_ride_to_workshop"] == "with_care":
        for f in ("can_ride_reason", "rider_advice_en"):
            m = PERMIT_RISK.search(r[f])
            if m:
                out.append(f"Q8 with_care entry permits normal riding in {f}: '{m.group(0)}'")
    return out


QS = [("Q1", q1), ("Q2", q2), ("Q3", q3), ("Q4", q4), ("Q5", q5), ("Q6", q6), ("Q7", q7), ("Q8", q8)]
EXPECT = {"A1": "Q1", "A2": "Q2", "A3": "Q3", "A4": "Q4", "A5": "Q5", "A6": "Q6", "B1": "Q7", "B2": "Q8"}


def main():
    errs0, _ = V.check_all(ROWS, CTX)
    print(f"baseline: {len(ROWS)} real entries, validator errors {len(errs0)}")
    result = {"attacks": [], "false_positives": {}}
    accepted = 0
    for aid, label, code, entry in ATTACKS:
        errs, _ = V.check_all([entry], CTX)
        got = []
        for qn, fn in QS:
            got += fn(entry)
        want = EXPECT[aid]
        caught = any(g.startswith(want) for g in got)
        ok = not errs
        accepted += ok
        print(f"{aid} {code}: validator errors={len(errs)} ({'ACCEPTED' if ok else 'rejected: ' + errs[0]}); "
              f"proposed {want} {'CATCHES' if caught else 'MISSES'}")
        result["attacks"].append({"id": aid, "code": code, "label": label, "validator_errors": errs,
                                  "accepted_by_validator": ok, "proposed_rule": want, "proposed_rule_catches": caught,
                                  "proposed_messages": got, "entry": entry})
    print(f"accepted by the current validator: {accepted} of {len(ATTACKS)}")
    print("false positives of the proposed rules on the 329 real entries:")
    for qn, fn in QS:
        hits = {r["code"]: fn(r) for r in ROWS if fn(r)}
        result["false_positives"][qn] = hits
        print(f"  {qn}: {len(hits)} real entries flagged {sorted(hits)[:30]}")
    json.dump(result, open(os.path.join(HERE, "review_attacks_v4_20261002.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
