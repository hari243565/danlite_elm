#!/usr/bin/env python3
"""Step 3: automated validation of generic_en_seed.jsonl.

Usage:
  python3 validate_seed.py [seed.jsonl] [--obdex /tmp/obdex] [--ranking relevance_ranking.csv]

Exit code 0 = no errors. Warnings do not fail the run.
Checks: valid JSON, required fields, types and allowed values, length limits,
duplicate content_id, rubric mapping per family, forbidden text (German
characters, currency, URLs, banned absolutes, numbers with units, part-number
patterns), preferred wording (shared failure phrases, glossary terms), the
code exists in OBDex at the recorded commit and the source hash matches,
and every part named in an entry appears in the source title, components or
causes.
"""
import csv
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))

REQUIRED = ["schema_version", "content_id", "code", "system", "title_en", "meaning_en",
            "likely_causes_en", "rider_action_level", "rider_action_basis",
            "rider_advice_en", "technician_hints_en", "flags", "confidence",
            "derived_from", "verification", "needs_mechanic_review", "updated_at"]
LEVELS = {"STOP", "SERVICE_SOON", "MONITOR", "INFO"}
SYSTEMS = {"powertrain", "chassis", "body", "network"}
SYSTEM_OF = {"P": "powertrain", "C": "chassis", "B": "body", "U": "network"}
CONF = {"high", "medium", "low"}
MODES = {"adapted", "structure-only"}
CODE_RE = re.compile(r"^[PBCU][0-3][0-9A-F]{3}$")

# ---- rubric mapping: reason tag (from relevance_ranking.csv) -> allowed levels
S, SS, M, I = "STOP", "SERVICE_SOON", "MONITOR", "INFO"
TAG_LEVELS = {
    "injector": {S}, "ignition_coil": {S}, "fuel_pump": {S, SS}, "crankshaft": {S},
    "cam_crank_sync": {S, SS}, "engine_speed_input": {S, SS}, "camshaft": {SS, S},
    "misfire": {SS, S}, "throttle": {SS, S}, "ride_by_wire": {SS, S},
    "twist_grip_sensor": {SS, S}, "idle": {SS}, "map_baro": {SS}, "iat": {M, SS},
    "ambient_temp": {M}, "ect": {SS, S}, "cooling_fan": {SS, S}, "cooling_system": {SS, S},
    "overspeed": {M, SS}, "oil_temp": {M, SS}, "oil_pressure": {S, SS},
    "o2_sensor": {SS, M}, "o2_heater": {SS, M}, "fuel_trim": {SS}, "catalyst": {M, SS},
    "knock": {SS}, "evap": {M}, "secondary_air": {M, SS}, "fuel_level": {M},
    "vehicle_speed": {SS, M}, "brake_switch": {SS, M}, "neutral_gear": {SS, M},
    "clutch_switch": {SS, M}, "system_voltage": {SS, S}, "starter_relay": {SS, S},
    "charging": {SS, S}, "ecu_power_relay": {S, SS}, "sensor_reference_supply": {SS, S},
    "control_module": {SS, S}, "immobiliser": {SS, S}, "starter_immobiliser": {SS, S},
    "can_bus": {SS, S}, "lost_comm_engine": {SS, S}, "lost_comm_abs": {SS, S},
    "lost_comm_cluster": {SS, M}, "lost_comm_immobiliser": {SS, S},
    "software": {SS, M}, "invalid_data": {SS, M},
    "abs_pump": {SS, S}, "wheel_speed": {SS, S}, "abs_module": {SS, S},
    "abs_relay": {SS, S}, "abs_lamp": {SS, S},
}

LIMITS = {"title_en": 70, "meaning_en": 200, "rider_action_basis": 60, "rider_advice_en": 220}
LIST_LIMITS = {"likely_causes_en": (2, 4, 60), "technician_hints_en": (1, 3, 90)}

GERMAN = re.compile(r"[äöüßÄÖÜ]")
CURRENCY = re.compile(r"[€$£¥₹]|\b(rs\.?|inr|eur|usd|rupees?|euros?|dollars?)\b", re.I)
URL = re.compile(r"https?://|www\.|\.com\b|\.de\b|\.in\b", re.I)
ABSOLUTES = re.compile(r"\b(always|never|guarantee[ds]?|definitely|certainly|absolutely|impossible|"
                       r"100 ?%|completely safe|perfectly safe)\b", re.I)
UNITS = re.compile(r"\b\d+([.,]\d+)?\s?(v|volts?|mv|ohms?|ω|kω|kpa|psi|bar|amps?|ma|hz|rpm|km/?h|mm|°c|deg)\b|[Ωω]", re.I)
PINNO = re.compile(r"\bpins? ?(no\.?|number)? ?\d+\b|\bterminal \d+\b", re.I)
PARTNO = re.compile(r"\b[A-Z0-9]{3,}-[A-Z0-9]{2,}(-[A-Z0-9]+)*\b|\b\d{5,}\b")
LONGNUM = re.compile(r"\d{3,}")

# ---- preferred wording ------------------------------------------------------
PHRASES = ["short to ground", "short to battery supply", "open circuit", "voltage below threshold",
           "voltage above threshold", "current below threshold", "current above threshold",
           "resistance above threshold", "signal out of range", "signal plausibility fault",
           "performance or incorrect operation", "stuck", "internal fault of the control unit",
           "communication lost"]
# discouraged variant -> preferred phrase
VARIANTS = {
    r"shorted to (ground|earth)|short circuit to (ground|earth)|short to earth|shorted to earth": "short to ground",
    r"shorted to (battery|supply|power)|short to (power|supply|positive|battery(?! supply))|short circuit to (battery|supply)":
        "short to battery supply",
    r"open[- ]circuited|\bopen-circuit\b|broken circuit": "open circuit",
    r"low voltage|voltage too low|voltage is low|voltage low\\b": "voltage below threshold",
    r"high voltage|voltage too high|voltage is high|voltage high\\b": "voltage above threshold",
    r"communication (loss|failure)|lost communication|no communication|loss of communication": "communication lost",
    r"implausible signal|plausibility error": "signal plausibility fault",
    r"internal (control )?(module|unit|ecu) (fault|failure)": "internal fault of the control unit",
}
TERMS = {  # banned wording -> preferred (see docs/content/GLOSSARY_EN.md)
    r"\b(ECM|PCM)\b": "ECU (bike's computer)",
    r"check[- ]engine|\bCEL\b|malfunction indicator|trouble light|engine light": "warning lamp (MIL)",
    r"\bDTC\b": "fault code",
    r"\bscanner\b|\bscan-tool\b|\bOBD tool\b": "scan tool",
    r"\bearth(ed|ing)?\b": "ground",
    r"\bmotorbike\b|\bmotorcycle\b|\bmotorcycles\b": "bike",
    r"limp[- ]?(mode|home)": "reduced power mode",
    r"emissions parts": "emission system",
}

# ---- parts named in an entry must appear in the source entry ---------------
# (regex on the entry text) -> tokens, any of which must occur in the source
# title + affected_components + common_causes labels (lower-case, '_' = ' ')
PARTS = [
    (r"\bthrottle body\b", ["throttle body"]),
    (r"\bthrottle position sensor\b|\btps\b", ["throttle position", "tps", "throttle"]),
    (r"\bMAP sensor\b|manifold pressure sensor|intake pressure sensor", ["map", "manifold"]),
    (r"\bvacuum hoses?\b", ["vacuum hose", "vacuum"]),
    (r"\bvacuum leak\b|intake air leak|air leak", ["vacuum", "intake", "unmetered", "leak"]),
    (r"\bintake (parts|boots?)\b", ["intake"]),
    (r"\bspark plugs?\b", ["spark plug"]),
    (r"\bignition coils?\b", ["ignition coil", "coil"]),
    (r"\bfuel injectors?\b|\binjectors?\b", ["injector"]),
    (r"\bfuel pump\b", ["fuel pump"]),
    (r"\bfuel pressure regulator\b", ["fuel pressure regulator", "pressure regulator"]),
    (r"\bfuel pressure\b", ["fuel pressure", "fuel_pressure"]),
    (r"\bfuel filter\b", ["fuel filter"]),
    (r"\bfuel tank\b", ["fuel tank", "tank"]),
    (r"\bair filter\b", ["air filter"]),
    (r"\bidle air (control )?(valve|passage)\b|\bIAC\b", ["idle air", "iac"]),
    (r"\boxygen sensor\b|\bO2 sensor\b", ["oxygen sensor", "o2 sensor", "oxygen_sensor", "ho2s"]),
    (r"\bcatalytic converter\b|\bcatalyst\b", ["catalyst", "catalytic"]),
    (r"\bexhaust\b", ["exhaust"]),
    (r"\bcrankshaft position sensor\b|crank sensor", ["crankshaft"]),
    (r"\bcamshaft position sensor\b", ["camshaft"]),
    (r"\breluctor ring\b|\bpulser ring\b|\btone ring\b|\bring teeth\b", ["reluctor", "tone ring", "ring"]),
    (r"\btiming chain\b", ["timing chain"]),
    (r"\bcompression\b", ["compression"]),
    (r"\brelay\b", ["relay"]),
    (r"\bfuse\b", ["fuse"]),
    (r"\bvoltage regulator\b|\bregulator\b", ["regulator"]),
    (r"\balternator\b", ["alternator"]),
    (r"\bbattery (terminals?|condition)\b|\bweak or old battery\b|\bbattery runs\b|\bthe battery\b",
     ["battery"]),
    (r"\bcooling fan\b", ["fan"]),
    (r"\bthermostat\b", ["thermostat"]),
    (r"\bneutral switch\b|\bneutral lamp\b", ["neutral", "pnp"]),
    (r"\bspeed sensor\b", ["speed sensor"]),
    (r"\binstrument cluster\b|\bcluster\b", ["cluster"]),
    (r"\bABS (control )?unit\b|\bABS\b", ["abs"]),
    (r"\bwheel speed sensor\b", ["wheel speed"]),
    (r"\bimmobili[sz]er\b", ["immobili"]),
    (r"\bpurge valve\b", ["purge"]),
    (r"\bcanister\b", ["canister"]),
    (r"\bECU (injector|ignition) driver\b", ["ecu"]),
    (r"\bgateway\b", ["gateway"]),
    (r"\bsensor ground\b|\bground connections?\b|\bwiring\b|\bconnectors?\b|\bharness\b", []),
]
SENT_END = re.compile(r"(?<=[.!?])\s+(?=[A-Z])")


def load_obdex(path):
    """Parse the OBDex YAML (about 35 s); cached in the temp folder per commit."""
    import pickle
    import tempfile
    head = subprocess.check_output(["git", "-C", path, "rev-parse", "HEAD"], text=True).strip()
    cache = os.path.join(tempfile.gettempdir(), f"obdex_index_{head[:12]}.pkl")
    if os.path.exists(cache):
        with open(cache, "rb") as fh:
            return pickle.load(fh)
    d = {}
    loader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
    for f in sorted(glob.glob(f"{path}/data/generic/*.yaml")):
        for e in yaml.load(open(f, encoding="utf-8"), Loader=loader):
            d[e["code"]] = e
    with open(cache, "wb") as fh:
        pickle.dump(d, fh)
    return d


def entry_hash(e):
    blob = json.dumps(e, sort_keys=True, ensure_ascii=False, default=str)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def source_description(e):
    return (e.get("description", {}).get("en", "") or "").lower().replace("_", " ")


def source_text(e):
    parts = [e["title"]["en"]] + list(e.get("affected_components", []))
    parts += [c["label"]["en"] for c in e.get("common_causes", [])]
    return " ".join(parts).lower().replace("_", " ")


def all_text(r):
    return " | ".join([r["title_en"], r["meaning_en"], r["rider_action_basis"], r["rider_advice_en"]]
                      + r["likely_causes_en"] + r["technician_hints_en"])


def main():
    args = sys.argv[1:]
    seed = next((a for a in args if a.endswith(".jsonl")), os.path.join(HERE, "generic_en_seed.jsonl"))
    obdex = args[args.index("--obdex") + 1] if "--obdex" in args else "/tmp/obdex"
    ranking = args[args.index("--ranking") + 1] if "--ranking" in args else os.path.join(HERE, "relevance_ranking.csv")
    errors, warns = [], []

    def err(code, msg):
        errors.append(f"{code}: {msg}")

    def warn(code, msg):
        warns.append(f"{code}: {msg}")

    tags = {r["code"]: r["reason_tags"].split(";") for r in csv.DictReader(open(ranking, encoding="utf-8"))}
    d = load_obdex(obdex)
    commit = subprocess.check_output(["git", "-C", obdex, "rev-parse", "HEAD"], text=True).strip()

    rows, seen, meanings = [], set(), {}
    for n, line in enumerate(open(seed, encoding="utf-8"), 1):
        if not line.strip():
            continue
        try:
            r = json.loads(line)
        except json.JSONDecodeError as ex:
            err(f"line {n}", f"invalid JSON: {ex}")
            continue
        rows.append(r)
        c = r.get("code", f"line {n}")
        missing = [k for k in REQUIRED if k not in r]
        if missing:
            err(c, f"missing fields {missing}")
            continue
        extra = set(r) - set(REQUIRED)
        if extra:
            err(c, f"unexpected fields {sorted(extra)}")
        # types and allowed values
        if r["schema_version"] != 1:
            err(c, "schema_version must be 1")
        if not CODE_RE.match(c):
            err(c, "bad code format")
        if r["content_id"] != f"generic:{c}:en":
            err(c, "content_id does not match code")
        if r["content_id"] in seen:
            err(c, "duplicate content_id")
        seen.add(r["content_id"])
        if r["system"] not in SYSTEMS:
            err(c, f"bad system {r['system']}")
        elif CODE_RE.match(c) and SYSTEM_OF[c[0]] != r["system"]:
            err(c, f"system {r['system']} does not match code prefix")
        if r["rider_action_level"] not in LEVELS:
            err(c, f"bad rider_action_level {r['rider_action_level']}")
        if r["confidence"] not in CONF:
            err(c, "bad confidence")
        if r["verification"] != "standards_derived_adapted":
            err(c, "bad verification value")
        if not isinstance(r["needs_mechanic_review"], bool):
            err(c, "needs_mechanic_review must be boolean")
        if not re.match(r"^\d{4}-\d{2}-\d{2}$", str(r["updated_at"])):
            err(c, "updated_at must be an ISO date")
        fl = r["flags"]
        if not isinstance(fl, dict) or set(fl) != {"mil", "emissions_relevant", "limp_possible"} \
                or not all(isinstance(v, bool) for v in fl.values()):
            err(c, "flags must be exactly mil, emissions_relevant, limp_possible booleans")
        df = r["derived_from"]
        if not isinstance(df, dict) or set(df) != {"source", "licence", "repo_commit", "source_entry_sha256", "mode"}:
            err(c, "derived_from keys wrong")
            continue
        if df["source"] != "OBDex" or df["licence"] != "CC0-1.0":
            err(c, "derived_from source or licence wrong")
        if df["mode"] not in MODES:
            err(c, "derived_from.mode not allowed")
        # length limits
        for k, lim in LIMITS.items():
            if not isinstance(r[k], str) or not r[k].strip():
                err(c, f"{k} empty or not a string")
            elif len(r[k]) > lim:
                err(c, f"{k} is {len(r[k])} chars, limit {lim}")
        for k, (lo, hi, lim) in LIST_LIMITS.items():
            v = r[k]
            if not isinstance(v, list) or not (lo <= len(v) <= hi):
                err(c, f"{k} needs {lo} to {hi} items")
                continue
            if len(set(x.lower() for x in v)) != len(v):
                err(c, f"{k} has duplicate items")
            for x in v:
                if not isinstance(x, str) or not x.strip():
                    err(c, f"{k} has an empty item")
                elif len(x) > lim:
                    err(c, f"{k} item is {len(x)} chars, limit {lim}: {x[:40]}...")
        # sentence counts
        ms = SENT_END.split(r["meaning_en"].strip())
        if len(ms) != 1 or not r["meaning_en"].strip().endswith("."):
            err(c, "meaning_en must be exactly one sentence ending with a full stop")
        ads = SENT_END.split(r["rider_advice_en"].strip())
        if len(ads) > 2:
            err(c, "rider_advice_en must be 1 or 2 sentences")
        for s in ms + ads:
            if len(s.split()) > 32:
                warn(c, f"long sentence ({len(s.split())} words), simplify for Hindi translation")
        # forbidden text
        t = all_text(r)
        for name, rx in [("German character", GERMAN), ("currency", CURRENCY), ("URL", URL),
                         ("banned absolute", ABSOLUTES), ("number with unit", UNITS),
                         ("pin number", PINNO), ("part number", PARTNO)]:
            m = rx.search(t)
            if m:
                err(c, f"{name}: '{m.group(0)}'")
        if LONGNUM.search(t):
            warn(c, "contains a number of 3+ digits; check it is not a part or pin number")
        # preferred wording
        for rx, pref in VARIANTS.items():
            m = re.search(rx, t, re.I)
            if m:
                err(c, f"use '{pref}' instead of '{m.group(0)}'")
        for rx, pref in TERMS.items():
            m = re.search(rx, t)
            if m:
                err(c, f"use '{pref}' instead of '{m.group(0)}'")
        # rider action rubric
        lvl = r["rider_action_level"]
        allowed = set()
        for tg in tags.get(c, []):
            allowed |= TAG_LEVELS.get(tg, set())
        if c not in tags:
            err(c, "code is not in relevance_ranking.csv")
        elif not allowed:
            err(c, f"no rubric mapping for tags {tags[c]}")
        elif lvl not in allowed:
            err(c, f"level {lvl} not allowed for {tags[c]} (allowed {sorted(allowed)})")
        adv = r["rider_advice_en"].lower()
        if lvl == "STOP" and not re.search(r"pull over|stop", adv):
            err(c, "STOP advice must tell the rider to pull over or stop")
        if lvl in ("MONITOR", "INFO") and re.search(r"pull over", adv):
            err(c, f"{lvl} advice should not tell the rider to pull over")
        # review rule
        must_review = lvl == "STOP" or c[0] in "CB" or r["confidence"] == "low"
        if must_review and not r["needs_mechanic_review"]:
            err(c, "needs_mechanic_review must be true (STOP, chassis/braking or low confidence)")
        # source checks
        src = d.get(c)
        if src is None:
            err(c, "code not found in OBDex")
            continue
        if df["repo_commit"] != commit:
            err(c, f"repo_commit {df['repo_commit'][:8]} differs from OBDex checkout {commit[:8]}")
        if df["source_entry_sha256"] != entry_hash(src):
            err(c, "source_entry_sha256 does not match the OBDex entry")
        stext = source_text(src)
        sdesc = source_description(src)
        for rx, toks in PARTS:
            if toks and re.search(rx, t, re.I) and not any(tok in stext for tok in toks):
                m = re.search(rx, t, re.I)
                if any(tok in sdesc for tok in toks):
                    warn(c, f"names '{m.group(0)}' found only in the source description, not in title/components/causes")
                else:
                    err(c, f"names '{m.group(0)}' which is not in the source title, components, causes or description")
        # content sanity
        if r["meaning_en"] in meanings:
            warn(c, f"meaning_en identical to {meanings[r['meaning_en']]}")
        meanings[r["meaning_en"]] = c
        if df["mode"] == "structure-only" and not any(p in r["title_en"].lower() + r["meaning_en"].lower()
                                                      for p in PHRASES + ["circuit fault", "misfire", "too lean",
                                                                          "too rich", "efficiency", "fault"]):
            warn(c, "title/meaning uses none of the shared failure phrases; check it is a generic code")
        # lamp / safety wording consistency
        if lvl == "STOP" and not r["needs_mechanic_review"]:
            err(c, "STOP entries need mechanic review")
    # duplicates by code
    codes = [r.get("code") for r in rows]
    for c in {x for x in codes if codes.count(x) > 1}:
        err(c, "code appears more than once")
    # report
    print(f"{len(rows)} entries checked in {seed}")
    for w in warns:
        print("WARN ", w)
    for e in errors:
        print("ERROR", e)
    lv = {}
    for r in rows:
        lv[r.get("rider_action_level")] = lv.get(r.get("rider_action_level"), 0) + 1
    print(f"levels: {lv}; errors: {len(errors)}; warnings: {len(warns)}")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
