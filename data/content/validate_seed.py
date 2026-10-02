#!/usr/bin/env python3
"""Step 3: automated validation of generic_en_seed.jsonl (schema version 2).

Usage:
  python3 validate_seed.py [seed.jsonl] [--obdex /tmp/obdex] [--ranking relevance_ranking.csv]
                           [--codes P0120,P0105]

Exit code 0 = no errors. Warnings do not fail the run. The OBDex checkout can
also be given with the OBDEX_DIR environment variable (default /tmp/obdex).

A clean run is NOT proof that an entry is safe (lesson of the 2026-10-01
independent review). The rules R1 to R11 below close the gaps that review
found; the mutation and regression tests in validator_selftest.py keep them
closed. Every message starts with the code, then the rule id.

Rules (rule id in messages):
  S   schema, types, lengths, forbidden text, wording, rubric level, source hash
  R1  circular advice ("stop if it stalls")
  R2  assumed hardware (gauge, tachometer, blinking lamp, scan tool for riders)
  R3  action level and text agree (no unconditional stall / no-start claims
      below STOP; STOP advice tells the rider to stop)
  R4  petrol smell needs the strong-smell stop instruction (and review)
  R5  ABS and wheel-speed codes: three plain facts, SERVICE_SOON
  R6  direction of low and high codes (temperature sensors read hotter/colder)
  R7  car-only parts blocklist
  R8  hedge fuse, relay and hose causes ("if fitted", "if hose-fed")
  R9  plain words first in the meaning
  R10 title rules (no "(listed as", no bank 2, no duplicate titles)
  R11 schema v2 fields (can_ride_to_workshop, applies_when, review, verification)
  D   owner decisions D1 to D8 for named codes
Added 2026-10-02 (independent review of batch 1, owner decisions D1 to D8):
  R12 no unconditional stop / shut-off / no-start claim below STOP ("if" must come first, not "if you like")
  R13 locked STOP table (stop_table.csv), two-way: a STOP not in the table is an error and so is a table code below STOP
  R14 direction words (hotter/colder) agree with the standard title in EVERY rider field
  R15 ABS and wheel-speed entries: no reassurance anywhere, second sentence from a closed list
  R16 fuel leak, drip or fumes needs the PETROL sentence and never "keep riding" or "wipe"
  R17 unsafe technician hints (bypass, jumper wire, battery lead off while running ...)
  R18 STOP text must not permit riding
  R19 a powertrain code with an engine-control tag has mil true
  R20 applies_when keys are required for hardware that not every bike has (knock, camshaft, oil temperature ...)
  R21 canonical sentences (D3 idle, D4 STALL, PETROL, ABS, NETWORK) word for word where they apply, no variants
  R22 Hindi-readiness (D6): sentences at most 25 words, idiom blocklist, discouraged words
  Q1 to Q8 (V5, from the independent review of V4): see check_q
  T1  title agreement (title_agreement.csv): a new entry needs AGREE; entries written before Step T only warn
"""
import csv
import glob
import hashlib
import json
import os
import pickle
import re
import subprocess
import sys
import tempfile

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))

REQUIRED = ["schema_version", "content_id", "code", "system", "title_en", "standard_title_en",
            "meaning_en", "likely_causes_en", "rider_action_level", "rider_action_basis",
            "rider_advice_en", "can_ride_to_workshop", "can_ride_reason", "technician_hints_en",
            "flags", "applies_when", "confidence", "derived_from", "verification",
            "needs_independent_review", "updated_at"]
LEVELS = {"STOP", "SERVICE_SOON", "MONITOR", "INFO"}
SYSTEMS = {"powertrain", "chassis", "body", "network"}
SYSTEM_OF = {"P": "powertrain", "C": "chassis", "B": "body", "U": "network"}
CONF = {"high", "medium", "low"}
MODES = {"adapted", "structure-only"}
VERIFICATION = {"structure-only": "ai_authored_from_standard_title", "adapted": "ai_authored_adapted"}
CODE_RE = re.compile(r"^[PBCU][0-3][0-9A-F]{3}$")
RIDE = {"yes", "with_care", "no"}
_TRUE = lambda v: v is True  # noqa: E731
APPLIES_KEYS = {"cylinders_min": lambda v: v == 2, "liquid_cooled": _TRUE, "ride_by_wire": _TRUE,
                "abs_fitted": _TRUE, "knock_sensor_fitted": _TRUE, "camshaft_sensor_fitted": _TRUE,
                "oil_temp_sensor_fitted": _TRUE, "closed_throttle_switch_fitted": _TRUE, "evap_fitted": _TRUE,
                "secondary_air_fitted": _TRUE, "cooling_fan_fitted": _TRUE, "oil_pressure_sensor_fitted": _TRUE,
                "ambient_temp_sensor_fitted": _TRUE, "fuel_level_sensor_fitted": _TRUE,
                "gear_position_sensor_fitted": _TRUE, "clutch_switch_fitted": _TRUE,
                "downstream_o2_sensor_fitted": _TRUE, "can_bus_fitted": _TRUE}
# R20: reason tag (or code) -> applies_when key that must be present
TAG_APPLIES = {"knock": "knock_sensor_fitted", "camshaft": "camshaft_sensor_fitted",
               "oil_temp": "oil_temp_sensor_fitted", "evap": "evap_fitted", "secondary_air": "secondary_air_fitted",
               "cooling_fan": "cooling_fan_fitted", "oil_pressure": "oil_pressure_sensor_fitted",
               "ambient_temp": "ambient_temp_sensor_fitted", "fuel_level": "fuel_level_sensor_fitted",
               "clutch_switch": "clutch_switch_fitted", "ride_by_wire": "ride_by_wire",
               "twist_grip_sensor": "ride_by_wire", "wheel_speed": "abs_fitted", "abs_pump": "abs_fitted",
               "abs_module": "abs_fitted", "abs_relay": "abs_fitted", "abs_lamp": "abs_fitted",
               "lost_comm_abs": "abs_fitted"}
CODE_APPLIES = {"P0510": "closed_throttle_switch_fitted", "P0220": "ride_by_wire", "P0221": "ride_by_wire",
                "P0222": "ride_by_wire", "P0223": "ride_by_wire", "P0224": "ride_by_wire"}  # throttle sensor B = redundant track
GEAR_POSITION_CODES = {f"P09{n:02X}" for n in range(0x14, 0x1A)}  # P0914 to P0919
DERIVED_KEYS = {"source", "licence", "repo_commit", "source_entry_sha256", "mode", "title_basis"}

# ---- rubric mapping: reason tag (from relevance_ranking.csv) -> allowed levels
S, SS, M, I = "STOP", "SERVICE_SOON", "MONITOR", "INFO"
TAG_LEVELS = {
    # injector and ignition_coil: R13 (stop_table.csv) decides which codes are STOP; cylinder 2 codes are SERVICE_SOON (D2)
    "injector": {S, SS}, "injector_balance": {SS, S}, "ect_warmup": {M, SS}, "ignition_coil": {S, SS}, "fuel_pump": {S, SS}, "crankshaft": {S},
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
    "can_bus": {SS, S}, "lost_comm_engine": {SS, S},
    "lost_comm_cluster": {SS, M}, "lost_comm_immobiliser": {SS, S},
    "software": {SS, M}, "invalid_data": {SS, M},
    # D3: ABS and wheel-speed function loss is SERVICE_SOON. STOP only for codes
    # about brake fluid loss or hydraulic pressure loss (none are selected).
    "lost_comm_abs": {SS}, "abs_pump": {SS}, "wheel_speed": {SS}, "abs_module": {SS},
    "abs_relay": {SS}, "abs_lamp": {SS},
}
ABS_TAGS = {"lost_comm_abs", "wheel_speed", "abs_pump", "abs_module", "abs_relay", "abs_lamp"}
# D4 default mapping. Anything outside it is an error.
RIDE_ALLOWED = {"STOP": {"no"}, "SERVICE_SOON": {"with_care", "yes"}, "MONITOR": {"yes"}, "INFO": {"yes"}}

LIMITS = {"title_en": 70, "meaning_en": 200, "rider_action_basis": 60, "rider_advice_en": 220,
          "can_ride_reason": 80}
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
VERIFIED = re.compile(r"\bverif(y|ied|ies|ication)\b", re.I)  # D6: never in text

# ---- preferred wording ------------------------------------------------------
PHRASES = ["short to ground", "short to battery supply", "open circuit", "voltage below threshold",
           "voltage above threshold", "current below threshold", "current above threshold",
           "resistance above threshold", "signal out of range", "signal plausibility fault",
           "performance or incorrect operation", "stuck", "internal fault of the control unit",
           "communication lost"]
VARIANTS = {
    r"shorted to (ground|earth)|short circuit to (ground|earth)|short to earth|shorted to earth": "short to ground",
    r"shorted to (battery|supply|power)|short to (power|supply|positive|battery(?! supply))|short circuit to (battery|supply)":
        "short to battery supply",
    r"open[- ]circuited|\bopen-circuit\b|broken circuit": "open circuit",
    r"low voltage|voltage too low|voltage is low|voltage low\b": "voltage below threshold",
    r"high voltage|voltage too high|voltage is high|voltage high\b": "voltage above threshold",
    r"communication (loss|failure)|lost communication|no communication|loss of communication": "communication lost",
    r"implausible signal|plausibility error": "signal plausibility fault",
    r"internal (control )?(module|unit|ecu) (fault|failure)": "internal fault of the control unit",
}
TERMS = {
    r"\b(ECM|PCM)\b": "ECU (bike's computer)",
    r"check[- ]engine|\bCEL\b|malfunction indicator|trouble light|engine light": "warning lamp (MIL)",
    r"\bDTC\b": "fault code",
    r"\bscanner\b|\bscan-tool\b|\bOBD tool\b": "scan tool",
    r"\bearth(ed|ing)?\b": "ground",
    r"\bmotorbike\b|\bmotorcycle\b|\bmotorcycles\b": "bike",
    r"limp[- ]?(mode|home)": "reduced power mode",
    r"emissions parts": "emission system",
}

# ---- R1 to R10 patterns -----------------------------------------------------
STALLWORD = r"(stall(s|ed|ing)?|cuts? out|cutting out|dies|dying)"
R1_PATTERNS = [
    re.compile(r"\b(stop|pull over)\b[^.;]{0,50}\bif\b[^.;]{0,40}\b" + STALLWORD + r"\b", re.I),
    re.compile(r"\bif\b[^.;]{0,40}\b" + STALLWORD + r"\b[^.;]{0,40}\b(stop|pull over)\b", re.I),
]
R2_HARDWARE = re.compile(r"\b(temperature |temp |fuel |oil |rev )?gauges?\b|\btachometer\b|\brev counter\b|"
                         r"\b(blink|blinks|blinking|flash|flashes|flashing)\b|\bscan[- ]tool\b|\bscanner\b|"
                         r"\bOBD tool\b", re.I)
R2_SCAN = re.compile(r"\bscan[- ]tool\b|\bscanner\b|\bOBD tool\b", re.I)
R3_CLAIM = re.compile(r"\b" + STALLWORD + r"\b|\b(will not|won't|does not|doesn't|may not|can not|cannot|fails? to) start\b|"
                      r"\brefus(e|es|ed) to start\b|\bno[- ]start\b", re.I)
SMELL = re.compile(r"(fuel|petrol|gasoline)[ -]?(smell|odou?r)|smell (of )?(fuel|petrol)", re.I)
STRONG_SMELL = re.compile(r"smell petrol strongly near the engine or tank, or see fuel dripping, stop and do not ride",
                          re.I)
R5_BRAKES = re.compile(r"\b(normal |regular |main )?brakes? (still )?work\b", re.I)
R5_ABSOFF = re.compile(r"\bABS (is|has been|will be) (switched |turned )?off\b|\bABS (is )?(disabled|not working)\b", re.I)
R5_LOCK = re.compile(r"\b(a |the )?wheel (can|may|could) lock\b", re.I)
R5_BAD = re.compile(r"braking is not affected|ride as normal|ABS lamp can wait", re.I)
R5_HEDGE = re.compile(r"\b(should|may|might|probably|likely|could|usually)\b", re.I)
R5_WHEEL_TITLE = re.compile(r"\b(left|right) (front|rear)\b|\blisted as\b|\btone wheel\b", re.I)
R6_LOWHIGH = re.compile(r"\b(low|high)(?: input| voltage)?\s*$", re.I)
R6_TEMP_TAGS = {"ect", "iat", "oil_temp", "ambient_temp"}
R7_BLOCK = re.compile(r"\bEGR\b|exhaust gas recirc|\bMAF\b|mass air ?flow|\bPCV\b|crankcase ventilation|"
                      r"transmission (fluid|oil)|\bturbo|\bboost\b|glow plug|\bdiesel\b|\bDPF\b|particulate|"
                      r"power steering|cruise control|\bA/C\b|air condition", re.I)
R7_CHAIN = re.compile(r"timing chain|cam chain|chain stretch", re.I)
R7_CAT = re.compile(r"catalytic converter|catalyst|\bconverter\b", re.I)
R8_FUSERELAY = re.compile(r"\b(fuse|relay)s?\b", re.I)
R8_HOSE = re.compile(r"\bhoses?\b", re.I)
R9_WORKSHOP = re.compile(r"short to ground|short to battery|open circuit|plausib|voltage below threshold|"
                         r"voltage above threshold|internal fault|signal out of range|resistance above|"
                         r"current below|current above|performance or incorrect|communication lost", re.I)
R10_TITLE_BAD = re.compile(r"\(listed as|bank ?2\b", re.I)
# duplicate titles that the standard really contains (none yet)
# A bike has one rear wheel speed sensor, so the standard car-style left, right and shared rear codes get the same
# rider title; their standard titles stay in standard_title_en (batch 3, 2026-10-02).
TITLE_DUP_EXCEPTIONS = [frozenset(p) for p in (
    ("C0037", "C003A"), ("C0037", "C003D"), ("C003A", "C003D"),
    ("C0038", "C003B"), ("C0038", "C003E"), ("C003B", "C003E"))]
SECOND_CYL = re.compile(r"cylinder (#)?2\b|ignition coil [\"']?b\b|contribution/balance", re.I)

# ---- parts named in an entry must appear in the source entry ---------------
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
    (r"\b(reluctor|pulser|tone|toothed) ring\b|\bring teeth\b", ["reluctor", "tone ring", "ring", "tooth"]),
    (r"\btiming chain\b", ["timing chain"]),
    (r"\bcompression\b", ["compression"]),
    (r"\brelay\b", ["relay"]),
    (r"\bfuse\b", ["fuse"]),
    (r"\bvoltage regulator\b|\bregulator\b", ["regulator"]),
    (r"\balternator\b", ["alternator"]),
    (r"\bbattery (terminals?|condition)\b|\bweak or old battery\b|\bbattery runs\b|\bthe battery\b",
     ["battery"]),
    (r"\bcooling fan\b|\bthe fan\b", ["fan"]),
    (r"\bthermostat\b", ["thermostat"]),
    (r"\bneutral (switch|lamp|light|indicator)\b", ["neutral switch", "neutral lamp", "neutral light",
                                                    "neutral indicator", "park/neutral switch", "pnp switch"]),
    (r"\bspeed sensor\b", ["speed sensor"]),
    (r"\binstrument cluster\b|\bcluster\b", ["cluster"]),
    (r"\bABS (control )?unit\b|\bABS\b", ["abs"]),
    (r"\bwheel speed sensor\b", ["wheel speed"]),
    (r"\bimmobili[sz]er\b", ["immobili"]),
    (r"\bpurge valve\b", ["purge"]),
    (r"\bcanister\b", ["canister"]),
    (r"\bECU (injector|ignition) driver\b", ["ecu"]),
    (r"\bgateway\b", ["gateway"]),
    (r"\bknock sensor\b", ["knock"]),
    (r"\boil pressure (sensor|switch)\b", ["oil pressure"]),
    (r"\bfuel cap\b", ["fuel cap", "cap"]),
    (r"\bvent (valve|solenoid)\b", ["vent"]),
    (r"\bsecondary air\b|\bair pump\b", ["secondary air", "air pump"]),
    (r"\bstarter (relay|motor|solenoid)\b", ["starter"]),
    (r"\bsensor ground\b|\bground connections?\b|\bwiring\b|\bconnectors?\b|\bharness\b", []),
]
SENT_END = re.compile(r"(?<=[.!?])\s+(?=[A-Z])")
SEG_SPLIT = re.compile(r"[.;:!?]+\s*")


# ============================================================================
# source data
# ============================================================================
def load_obdex(path):
    """Parse the OBDex YAML (about 35 s); cached in the temp folder per commit."""
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


def _load_lines(name):
    path = os.path.join(HERE, name)
    return set(open(path, encoding="utf-8").read().split()) if os.path.exists(path) else set()


def _load_verdicts():
    path = os.path.join(HERE, "title_agreement.csv")
    if not os.path.exists(path):
        return {}
    return {r["code"]: r["verdict"] for r in csv.DictReader(open(path, encoding="utf-8"))}


def build_context(obdex, ranking):
    rk = {r["code"]: r for r in csv.DictReader(open(ranking, encoding="utf-8"))}
    return {
        "obdex": load_obdex(obdex),
        "commit": subprocess.check_output(["git", "-C", obdex, "rev-parse", "HEAD"], text=True).strip(),
        "rank": rk,
        "tags": {c: r["reason_tags"].split(";") for c, r in rk.items()},
        "overrides": {r["code"]: r for r in csv.DictReader(
            open(os.path.join(HERE, "title_overrides.csv"), encoding="utf-8"))},
        "stop_table": {r["code"]: r for r in csv.DictReader(
            open(os.path.join(HERE, "stop_table.csv"), encoding="utf-8"))},
        "title_verdict": _load_verdicts(),
        "grandfathered": _load_lines("entries_before_step_t.txt"),
    }


# ============================================================================
# helpers
# ============================================================================
def rider_fields(r):
    """Text a rider can read (R2 'scan tool' rule applies here)."""
    return [r["title_en"], r["meaning_en"], r["rider_action_basis"], r["rider_advice_en"],
            r["can_ride_reason"]] + list(r["likely_causes_en"])


def all_text(r):
    return " | ".join(rider_fields(r) + list(r["technician_hints_en"]))


def segments(text):
    return [s.strip() for s in SEG_SPLIT.split(text) if s.strip()]


def direction(std_title):
    """'LOW', 'HIGH' or None from the standard title of a circuit low/high code."""
    t = re.sub(r"\(.*?\)", "", std_title).strip()
    if re.search(r"\b(too|over|under)\s+(low|high)\s*$", t, re.I):
        return None
    m = R6_LOWHIGH.search(t)
    if not m:
        return None
    return m.group(1).upper()


# ============================================================================
# decisions D1 to D6 for named codes (kept as permanent regression checks)
# ============================================================================
def has(r, field, rx):
    v = r[field] if isinstance(r[field], str) else " ".join(r[field])
    return re.search(rx, v, re.I) is not None


DECISIONS = {
    "P0563": [
        ("D1 level SERVICE_SOON", lambda r: r["rider_action_level"] == "SERVICE_SOON"),
        ("D1 can_ride with_care", lambda r: r["can_ride_to_workshop"] == "with_care"),
        ("D1 stop triggers (hot, swollen, rotten eggs, very bright lights, blowing bulbs) and 'do not ride on'",
         lambda r: all(has(r, "rider_advice_en", x) for x in
                       [r"hot, swollen", r"rotten eggs", r"very bright", r"bulbs keep blowing",
                        r"stop, switch off and do not ride on"])),
        ("D1 short daytime ride to a workshop only", lambda r: has(r, "rider_advice_en", r"short way, in daylight")),
        ("D1 reasoning in rider_action_basis", lambda r: has(r, "rider_action_basis", r"overcharge|battery")),
        ("D1 needs_independent_review", lambda r: r["needs_independent_review"] is True),
    ],
    "U0100": [
        ("D2 level SERVICE_SOON", lambda r: r["rider_action_level"] == "SERVICE_SOON"),
        ("D2 can_ride with_care", lambda r: r["can_ride_to_workshop"] == "with_care"),
        ("D2 two honest cases",
         lambda r: has(r, "rider_advice_en", r"if the engine runs normally") and
         has(r, "rider_advice_en", r"if it stalls, loses power or will not start, do not keep riding")),
        ("D2 no scan tool anywhere", lambda r: not has({"x": all_text(r)}, "x", r"scan tool|scanner")),
    ],
    "U0121": [("D3 level SERVICE_SOON", lambda r: r["rider_action_level"] == "SERVICE_SOON")],
    "C0035": [
        ("D3 level SERVICE_SOON", lambda r: r["rider_action_level"] == "SERVICE_SOON"),
        ("D3 rider-friendly title", lambda r: r["title_en"] == "Wheel speed sensor fault (front or rear wheel)"),
    ],
    "P0500": [("title", lambda r: r["title_en"] == "Vehicle speed sensor A: fault")],
    "P0420": [("exhaust or converter modification named first",
               lambda r: re.search(r"modified|removed", r["likely_causes_en"][0], re.I) is not None)],
    "P0335": [("toothed ring explained",
               lambda r: has(r, "likely_causes_en", r"toothed ring") and has(r, "technician_hints_en", r"toothed ring"))],
    "P0340": [("timing chain dropped",
               lambda r: not has({"x": all_text(r)}, "x", r"timing chain|chain"))],
    "P0195": [("no protection claim",
               lambda r: not has({"x": all_text(r)}, "x", r"may not notice|signs of overheating"))],
    "P0850": [("no neutral lamp", lambda r: not has({"x": all_text(r)}, "x", r"neutral lamp|neutral light"))],
    "U0075": [("plain single-bus entry, low confidence", lambda r: r["confidence"] == "low"),
              ("no car body networks", lambda r: not has({"x": all_text(r)}, "x", r"\bbody\b|comfort|door|window|seat"))],
    "U0076": [("plain single-bus entry, low confidence", lambda r: r["confidence"] == "low"),
              ("no car body networks", lambda r: not has({"x": all_text(r)}, "x", r"\bbody\b|comfort|door|window|seat"))],
    "U0077": [("plain single-bus entry, low confidence", lambda r: r["confidence"] == "low"),
              ("no car body networks", lambda r: not has({"x": all_text(r)}, "x", r"\bbody\b|comfort|door|window|seat"))],
}
# ---- owner decisions D2 to D8 (2026-10-02), kept as permanent checks
for _c in ("P0604", "P0605", "P0606"):
    DECISIONS.setdefault(_c, []).extend([
        ("D2 SERVICE_SOON with_care (the source says the ECU keeps running)",
         lambda r: r["rider_action_level"] == "SERVICE_SOON" and r["can_ride_to_workshop"] == "with_care"),
        ("D2 TWO-CASE advice", lambda r: TWO_CASE in r["rider_advice_en"]),
        ("D2 needs_independent_review", lambda r: r["needs_independent_review"] is True)])
for _c in ("P0202", "P0264", "P0265", "P0352"):
    DECISIONS.setdefault(_c, []).extend([
        ("D2 SERVICE_SOON with_care (cylinder 2 only; the engine keeps running)",
         lambda r: r["rider_action_level"] == "SERVICE_SOON" and r["can_ride_to_workshop"] == "with_care"),
        ("D2 stop trigger for very rough running or heavy power loss",
         lambda r: has(r, "rider_advice_en", r"stop if it runs very rough or loses power badly")),
        ("D2 applies_when cylinders_min 2", lambda r: (r["applies_when"] or {}).get("cylinders_min") == 2)])
DECISIONS.setdefault("P0232", []).extend([
    ("D2 SERVICE_SOON with_care (the source says the pump stays powered)",
     lambda r: r["rider_action_level"] == "SERVICE_SOON" and r["can_ride_to_workshop"] == "with_care"),
    ("D2 reason in rider_action_basis (pump stays powered)", lambda r: has(r, "rider_action_basis", r"stay powered")),
    ("D2 no open circuit claim", lambda r: not has({"x": all_text(r)}, "x", r"open circuit")),
    ("D2 confidence low and review true", lambda r: r["confidence"] == "low" and r["needs_independent_review"] is True)])
for _c in ("P0336", "P0629", "P0685", "P0686"):
    DECISIONS.setdefault(_c, []).append(
        ("D2 stays STOP with needs_independent_review true",
         lambda r: r["rider_action_level"] == "STOP" and r["needs_independent_review"] is True))
for _c in ("P0506", "P0510", "P0519"):
    DECISIONS.setdefault(_c, []).append(
        ("D3 no self-contradicting sentence",
         lambda r: not has(r, "rider_advice_en", r"avoid traffic and do not keep riding")))
DECISIONS.setdefault("P0507", []).append(
    ("review: throttle-not-closing stop sentence",
     lambda r: has(r, "rider_advice_en", r"if the throttle does not snap fully shut when you let go, do not ride")))
DECISIONS.setdefault("P068B", []).append(
    ("D5 battery-drain statement restored", lambda r: has(r, "rider_advice_en", r"battery may go flat")))
for _c in ("P0633", "P0512", "P0513"):
    DECISIONS.setdefault(_c, []).append(
        ("D7 no-start claim is conditional", lambda r: has(r, "can_ride_reason", r"^if it starts")))
for _c in ("U0001", "U0002", "U0003", "U0004", "U0005", "U0006", "U0007", "U0008"):
    DECISIONS.setdefault(_c, []).append(
        ("D4 NETWORK sentence and review true",
         lambda r: NETWORK in r["rider_advice_en"] and r["needs_independent_review"] is True))
# plain stall warning must be present on the three throttle sensor entries (review fix)
for _c in ("P0120", "P0122", "P0123"):
    DECISIONS.setdefault(_c, []).append(
        ("stall warning with a real action (not circular)",
         lambda r: has(r, "rider_advice_en", r"if it stalls more than once or will not restart, do not keep riding")))
for _c in ("P0115", "P0117", "P0118"):
    DECISIONS.setdefault(_c, []).append(
        ("no gauge", lambda r: not has({"x": all_text(r)}, "x", r"gauge")))



# ============================================================================
# v4 rules (2026-10-02): reviewer's R12 to R19, plus R20 to R22 and T1
# ============================================================================
R12_CLAIM = re.compile(
    r"\b(shuts?|shut(ting)?) (off|down)\b|\bstops? (running|suddenly|dead)\b|\bconks? out\b|"
    r"\bgoes? (dead|off)\b|\bloses? (all|total) power\b|\b(will not|won't|may not|might not|can ?not|cannot|"
    r"does not|doesn't|fails? to) (re)?start\b|\b(will not|won't|may not|cannot|can't) (turn over|crank)\b|"
    r"\bdies?\b|\bdying\b|\bseiz(es|e|ing)\b|\b(stall(s|ed|ing)?|cuts? out|cutting out)\b", re.I)
R12_IF_BEFORE = re.compile(r"\bif\b(?! you (like|wish|want|prefer|must))[^;.]{0,60}$", re.I)
R14_WRONG = {
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
R19_FLAGS_FLOOR = {"injector", "ignition_coil", "crankshaft", "fuel_pump", "misfire", "throttle", "map_baro", "ect",
                   "o2_sensor", "o2_heater", "fuel_trim", "camshaft", "knock", "idle", "system_voltage",
                   "control_module", "ecu_power_relay", "sensor_reference_supply", "catalyst", "cam_crank_sync",
                   "starter_relay"}

# ---- canonical sentences (D3, D4). One form, word for word, everywhere it applies.
STALL = "If it stalls more than once or will not restart, do not keep riding; have it taken to a workshop."
BATTERY = ("If the battery is hot, swollen or smells of rotten eggs, or the lights are very bright or bulbs keep "
           "blowing, stop, switch off and do not ride on.")
PETROL = "If you smell petrol strongly near the engine or tank, or see fuel dripping, stop and do not ride."
ABS_SENT = "Your normal brakes still work, but ABS is off, so a wheel can lock in hard braking."
NETWORK = ("Some electronic units on the bike cannot talk to each other, so warning lights or safety features may "
           "not work. If ABS is affected, your normal brakes still work, but ABS is off, so a wheel can lock in "
           "hard braking.")
IDLE_FIRST = "If it stalls at stops or will not hold idle, ride gently, avoid heavy traffic and have it checked soon."
IDLE_PAIR = ("If it stalls once at a stop, ride gently, avoid heavy traffic and have it checked soon. If it stalls "
             "more than once or will not restart, do not keep riding.")
BATTERY_HOT = "If the battery is hot or swollen, stop, switch off and do not ride on."
TWO_CASE = ("If the engine runs normally, have it checked soon; if it stalls, loses power or will not start, "
            "do not keep riding.")
STOP_TAIL = "Pull over safely, switch off and do not keep riding; have the bike taken to a workshop."
# a sentence that talks about stalling and "do not keep riding" must be one of the canonical forms
STALL_FAMILY = re.compile(r"\bstalls?\b[^.]*\bdo not keep riding\b", re.I)
STALL_TAGS = {"throttle", "map_baro", "camshaft", "idle", "sensor_reference_supply", "ride_by_wire", "twist_grip_sensor"}
NETWORK_TAGS = {"can_bus"}
NETWORK_CODES = {"U0146", "U0140"}
IDLE_TAGS = {"idle"}

# ---- R22 Hindi-readiness
MAX_WORDS = 25
IDIOMS = re.compile(
    r"\bcut(s|ting)? out\b|\bdrops? out\b|\bjumps? about\b|\bjumps?\b|\bhunt(s|ing)?\b|\brun(s|ning)? on one cylinder\b|"
    r"\breduce (the )?load\b|\bfair share\b|\brefus(e|es|ed|ing) to\b|\bkeeps? pulling\b|\brun(s)? hot\b|"
    r"\boff in one direction\b|\bwreck(s|ed)?\b|\bstumbles?\b|\bconks?\b|\bgoes? haywire\b|\bfire up\b|\bbogs?\b|"
    r"\brun(s|ning)? (rich|lean|richer|leaner)\b|\bkicks? in\b|\bfalls? back\b|\bcomes? and goes\b|\bgive up\b|"
    r"\bpoint(s)? to\b|\bsit(s)? (too )?(high|low)\b|\bwrong way round\b|\bgets? worse\b", re.I)
DISCOURAGED_WORDS = re.compile(r"\bmodules?\b|\bharness(es)?\b|\bloom\b", re.I)

# ---- R20/R21/R22 helpers
def _sentences(text):
    return [x.strip() for x in SENT_END.split(text.strip()) if x.strip()]


def check_v4(r, ctx, err, warn, tags, rk):
    c = r["code"]
    lvl = r["rider_action_level"]
    tagset = set(tags)
    fields = ["meaning_en", "rider_action_basis", "rider_advice_en", "can_ride_reason"]
    # ---- T1 title agreement
    verdict = ctx.get("title_verdict", {}).get(c)
    if ctx.get("title_verdict"):
        if verdict != "AGREE":
            if c in ctx.get("grandfathered", set()):
                warn(c, "T1", f"title not agreed by two sources ({verdict}); entry written before Step T, "
                              f"kept until the owner's assistant has checked the title")
            else:
                err(c, "T1", f"title not agreed by two sources ({verdict}); a new entry must not be written")
    # ---- R12 no unconditional claim below STOP ("if" must come first)
    if lvl in ("SERVICE_SOON", "MONITOR", "INFO"):
        for f in fields:
            for sg in _sentences(r[f]):
                for part in sg.split(";"):
                    m = R12_CLAIM.search(part)
                    if m and not R12_IF_BEFORE.search(part[:m.start()]):
                        err(c, "R12", f"{lvl} entry makes an unconditional claim '{m.group(0)}' in {f}")
    # ---- R13 locked STOP table
    st = ctx.get("stop_table", {})
    if lvl == "STOP" and c not in st:
        err(c, "R13", "STOP level is not in the owner's STOP table (stop_table.csv)")
    if lvl != "STOP" and c in st:
        err(c, "R13", "code is in the owner's STOP table (stop_table.csv) but the level is below STOP")
    # ---- R14 direction words in every rider field
    if rk is not None and tagset & R6_TEMP_TAGS:
        d = direction(rk["title_standard"])
        if d:
            for f in fields:
                m = R14_WRONG[d].search(r[f])
                if m:
                    err(c, "R14", f"{d} temperature code but {f} says '{m.group(0)}' (wrong direction)")
    # ---- R15 ABS: no reassurance, second sentence from a closed list
    if tagset & ABS_TAGS or c[0] == "C":
        for f in ("rider_advice_en", "rider_action_basis", "can_ride_reason", "meaning_en"):
            m = R15_REASSURE.search(r[f])
            if m:
                err(c, "R15", f"ABS entry reassures the rider in {f}: '{m.group(0)}'")
        ss = _sentences(r["rider_advice_en"])
        if len(ss) == 2 and ss[1].lower() not in R15_ALLOWED_SECOND:
            err(c, "R15", f"ABS second sentence is not on the approved list: '{ss[1]}'")
    # ---- R16 fuel leak and fumes
    for f in fields:
        m = R16_FUEL.search(r[f])
        if m and PETROL not in r["rider_advice_en"]:
            err(c, "R16", f"fuel leak or fumes in {f} ('{m.group(0)}') without the PETROL stop sentence")
        if m and R16_KEEP.search(r[f]):
            err(c, "R16", f"fuel leak in {f} with a keep-riding instruction ('{R16_KEEP.search(r[f]).group(0)}')")
    # ---- R17 unsafe technician hints; rider text may only say bypass as 'do not bypass'
    for h in r["technician_hints_en"]:
        m = R17_UNSAFE_HINT.search(h)
        if m:
            err(c, "R17", f"unsafe technician hint: '{m.group(0)}'")
    for f in ("rider_advice_en", "can_ride_reason"):
        for sg in _sentences(r[f]):
            if re.search(r"\bbypass", sg, re.I) and not re.search(r"\b(do not|don't|never) (try to )?bypass", sg, re.I):
                err(c, "R17", f"rider text mentions bypass without 'do not bypass': '{sg}'")
    # ---- R18 STOP text must not permit riding
    if lvl == "STOP":
        for f in ("rider_advice_en", "can_ride_reason", "rider_action_basis"):
            m = R18_PERMIT.search(r[f])
            if m:
                err(c, "R18", f"STOP entry permits riding in {f}: '{m.group(0)}'")
        if not any("pull over" in x.lower() and "do not keep riding" in x.lower()
                   for x in _sentences(r["rider_advice_en"])):
            err(c, "R18", "STOP advice lacks one sentence with 'pull over' and 'do not keep riding'")
    # ---- R19 flags
    if tagset & R19_FLAGS_FLOOR and c[0] == "P" and not r["flags"]["mil"]:
        err(c, "R19", "powertrain code with an engine-control tag has mil false")
    # ---- R20 applies_when for hardware that not every bike has
    need = {TAG_APPLIES[t] for t in tagset if t in TAG_APPLIES}
    if c in CODE_APPLIES:
        need.add(CODE_APPLIES[c])
    if c in GEAR_POSITION_CODES:
        need.add("gear_position_sensor_fitted")
    std = (rk["title_standard"] if rk else "").lower()
    if re.search(r"sensor 2\b|sensor2\b", std) and tagset & {"o2_sensor", "o2_heater"}:
        need.add("downstream_o2_sensor_fitted")
    aw = r["applies_when"] or {}
    for k in sorted(need):
        if aw.get(k) is not True:
            err(c, "R20", f"applies_when must include {{'{k}': true}} (hardware that not every bike has)")
    # ---- R21 canonical sentences
    advice = r["rider_advice_en"]
    for sg in _sentences(advice):
        if STALL_FAMILY.search(sg) and STALL not in sg and TWO_CASE not in sg:
            err(c, "R21", f"stall advice is not the canonical STALL sentence: '{sg}'")
    if tagset & STALL_TAGS and lvl != "STOP" and STALL not in advice and TWO_CASE not in advice:
        err(c, "R21", "entry needs the canonical STALL (or TWO-CASE) sentence (D4) in rider_advice_en")
    if tagset & IDLE_TAGS and c not in IDLE_FIRST_EXEMPT and IDLE_FIRST not in advice:
        err(c, "R21", "idle entries need the D3 sentence: " + IDLE_FIRST)
    if (tagset & NETWORK_TAGS or c in NETWORK_CODES) and NETWORK not in advice:
        err(c, "R21", "bus fault entries need the canonical NETWORK sentence (D4) word for word")
    if (tagset & NETWORK_TAGS or c in NETWORK_CODES) and r["needs_independent_review"] is not True:
        err(c, "R21", "bus fault entries need needs_independent_review true (D4)")
    if (tagset & ABS_TAGS or c[0] == "C") and ABS_SENT not in advice and NETWORK not in advice:
        err(c, "R21", "ABS entries need the canonical ABS sentence (D4) word for word")
    # ---- R22 Hindi-readiness (D6)
    for f in ("meaning_en", "rider_advice_en"):
        for sg in _sentences(r[f]):
            n = len(sg.split())
            if n > MAX_WORDS and sg != BATTERY:  # the owner's D1 BATTERY sentence (29 words) is fixed text
                err(c, "R22", f"sentence of {n} words in {f} (limit {MAX_WORDS}): '{sg[:50]}...'")
    for f in fields + ["title_en"]:
        m = IDIOMS.search(r[f])
        if m:
            err(c, "R22", f"idiom or phrasal verb '{m.group(0)}' in {f}; use a plain glossary word")
    for x in list(r["likely_causes_en"]) + list(r["technician_hints_en"]):
        m = IDIOMS.search(x)
        if m:
            err(c, "R22", f"idiom or phrasal verb '{m.group(0)}' in '{x}'")
    for f in fields + ["title_en"]:
        m = DISCOURAGED_WORDS.search(r[f])
        if m:
            err(c, "R22", f"discouraged word '{m.group(0)}' in {f}; see GLOSSARY_EN.md")


# ============================================================================
# Q1 to Q8 (2026-10-02 independent review of V4, adopted by the owner in V5 group G1)
# ============================================================================
Q_TRIGGER = re.compile(r"stall|loses? power|power loss|will not (re)?start|does not (re)?start|runs? very rough|rough|hot|"
                       r"swollen|keeps turning|hold idle|runs normally|battery|key|lamp stays on|smell|lock", re.I)
Q_CERTAIN = re.compile(r"\bwill (stall|not (re)?start|stop|shut|die|fail|lose)\b|\bwill not restart\b", re.I)
Q_FIRE = re.compile(r"(fuel|petrol|vapou?rs?)[^.;]{0,60}\b(seep\w*|ooze\w*|weep\w*|dribbl\w*|escap\w*|build\w* up|collect\w*|"
                    r"ignit\w*|catch\w* fire|on fire|hot (engine|exhaust|part)s?)\b|"
                    r"\b(seep\w*|ooze\w*|weep\w*|dribbl\w*|collect\w*)\b[^.;]{0,40}(fuel|petrol|vapou?r)", re.I)
Q_BRAKE = re.compile(r"\bbrak(e|es|ing)\b", re.I)
Q_UNSAFE = re.compile(r"\b(open|remove|take off|loosen|unscrew)\b[^.;]{0,30}\b(radiator|coolant|filler|fuel|oil|tank)?\s?cap\b|"
                      r"\b(pour|splash|spray)\b[^.;]{0,20}\bwater\b|\bblow (out|into)\b|\btouch the (exhaust|engine|silencer)\b|"
                      r"\bcheck the (fuel|petrol) (level )?with (a )?(match|lighter|flame)\b", re.I)
Q_HYDRAULIC = re.compile(r"\bbrake (fluid|line|hose|pad|disc|disk|pipe)s?\b|\bhydraulic\b|\bmaster cylinder\b|\bcaliper\b|"
                         r"\bair in the (brake|lines?)\b", re.I)
Q_POSITION = re.compile(r"\b(left|right)\b|\b(left|right) (front|rear)\b|\bfront left\b|\bfront right\b", re.I)
Q_PERMIT = re.compile(r"\b(ride normally|long trips (are|is) fine|no need to (slow|stop|worry)|ride as (usual|normal)|"
                      r"carry on as normal|as far as you like)\b", re.I)


def check_q(r, ctx, err, tags, rk):
    c = r["code"]
    lvl = r["rider_action_level"]
    fields4 = ("meaning_en", "rider_action_basis", "rider_advice_en", "can_ride_reason")
    # Q1: below STOP, the "if" before a stall or no-start claim must contain a real symptom
    if lvl != "STOP":
        canon = {STALL, TWO_CASE, IDLE_FIRST, BATTERY, BATTERY_HOT, STOP_TAIL, PETROL, ABS_SENT, IDLE_PAIR}
        for f in fields4:
            for sg in _sentences(r[f]):
                if sg in canon:
                    continue
                for part in sg.split(";"):
                    m = R12_CLAIM.search(part) or Q_CERTAIN.search(part)
                    if not m:
                        continue
                    ifm = re.search(r"\bif\b(.*)$", part[:m.start()], re.I)
                    if ifm and "," in ifm.group(1) and not Q_TRIGGER.search(ifm.group(1)):
                        err(c, "Q1", f"the 'if' before '{m.group(0)}' names no real symptom in {f}: '{ifm.group(0).strip()}'")
    # Q2: fuel or vapour that seeps, collects or reaches a hot part needs the PETROL sentence
    for f in fields4:
        m = Q_FIRE.search(r[f])
        if m and PETROL not in r["rider_advice_en"]:
            err(c, "Q2", f"fire-risk wording '{m.group(0)}' in {f} without the PETROL sentence")
    # Q3: 'too low/too high/low/high' standard titles: title_en and meaning_en must not say the opposite
    if rk:
        std = re.sub(r"\(.*?\)", "", rk["title_standard"]).strip()
        m = re.search(r"\b(too )?(low|high)\s*(input|voltage)?\s*$", std, re.I)
        if m:
            low = m.group(2).lower() == "low"
            lowrx, highrx = r"\b(below|low|lower|too low)\b", r"\b(above|higher|high|too high)\b"
            right, wrong = (lowrx, highrx) if low else (highrx, lowrx)
            for f in ("title_en", "meaning_en"):
                if re.search(wrong, r[f], re.I) and not re.search(right, r[f], re.I):
                    err(c, "Q3", f"standard title says {'LOW' if low else 'HIGH'} but {f} says the opposite")
    # Q4: braking text needs review true, no MONITOR, no high confidence
    txt = " ".join([r["title_en"], r["meaning_en"], r["rider_advice_en"], r["rider_action_basis"], r["can_ride_reason"]])
    if Q_BRAKE.search(txt) or "brake" in r["standard_title_en"].lower():
        if r["needs_independent_review"] is not True:
            err(c, "Q4", "braking text but needs_independent_review is not true")
        if lvl not in ("SERVICE_SOON", "STOP"):
            err(c, "Q4", f"braking text at level {lvl} (SERVICE_SOON or STOP only)")
        if r["confidence"] == "high":
            err(c, "Q4", "braking text with confidence high (no braking entry may be high until a mechanic has seen it)")
    # Q5: opening a cap or pouring water only as 'do not open the cap while it is hot'
    for f, t in [("rider_advice_en", r["rider_advice_en"]), ("can_ride_reason", r["can_ride_reason"])] + \
            [("hint", h) for h in r["technician_hints_en"]]:
        for sg in _sentences(t):
            m = Q_UNSAFE.search(sg)
            if m and not re.search(r"\b(do not|don't|never)\b[^.;]{0,15}$", sg[:m.start()] + " ", re.I) \
                    and not re.search(r"\b(do not|don't)\s+(open|remove)", sg, re.I):
                err(c, "Q5", f"unsafe instruction in {f}: '{m.group(0)}'")
    # Q6: braking hydraulics are an error unless the source has the word
    src = source_text(ctx["obdex"][c]) if c in ctx["obdex"] else ""
    for f in ("title_en", "meaning_en", "rider_advice_en", "rider_action_basis", "can_ride_reason"):
        m = Q_HYDRAULIC.search(r[f])
        if m and m.group(0).lower() not in src:
            err(c, "Q6", f"braking hydraulics '{m.group(0)}' in {f}, not in the source")
    for x in list(r["likely_causes_en"]) + list(r["technician_hints_en"]):
        m = Q_HYDRAULIC.search(x)
        if m and m.group(0).lower() not in src:
            err(c, "Q6", f"braking hydraulics '{m.group(0)}' in '{x[:40]}', not in the source")
    # Q7: no left or right wheel in any text field of a wheel speed entry
    if "wheel_speed" in tags or c[0] == "C":
        for f in ("title_en", "meaning_en", "rider_advice_en", "can_ride_reason"):
            m = Q_POSITION.search(r[f])
            if m:
                err(c, "Q7", f"wheel position '{m.group(0)}' in {f}")
        for x in list(r["likely_causes_en"]) + list(r["technician_hints_en"]):
            m = Q_POSITION.search(x)
            if m:
                err(c, "Q7", f"wheel position '{m.group(0)}' in '{x[:40]}'")
    # Q8: a with_care entry may not permit normal or long riding
    if lvl == "SERVICE_SOON" and r["can_ride_to_workshop"] == "with_care":
        for f in ("can_ride_reason", "rider_advice_en"):
            m = Q_PERMIT.search(r[f])
            if m:
                err(c, "Q8", f"with_care entry permits normal riding in {f}: '{m.group(0)}'")



# P0507 (idle too high) carries its own first sentence (throttle not closing fully) instead of the D3 sentence;
# it still needs STALL, and the decision check in DECISIONS makes the throttle sentence mandatory.
IDLE_FIRST_EXEMPT = {"P0507"}

# ============================================================================
# per-entry checks
# ============================================================================
def check_entry(r, ctx, err, warn):
    c = r.get("code", "?")
    d = ctx["obdex"]
    missing = [k for k in REQUIRED if k not in r]
    if missing:
        err(c, "S", f"missing fields {missing}")
        return
    extra = set(r) - set(REQUIRED)
    if extra:
        err(c, "S", f"unexpected fields {sorted(extra)}")
    # ---- S: types and allowed values
    if r["schema_version"] != 2:
        err(c, "R11", "schema_version must be 2")
    if not CODE_RE.match(c):
        err(c, "S", "bad code format")
    if r["content_id"] != f"generic:{c}:en":
        err(c, "S", "content_id does not match code")
    if r["system"] not in SYSTEMS:
        err(c, "S", f"bad system {r['system']}")
    elif CODE_RE.match(c) and SYSTEM_OF[c[0]] != r["system"]:
        err(c, "S", f"system {r['system']} does not match code prefix")
    if r["rider_action_level"] not in LEVELS:
        err(c, "S", f"bad rider_action_level {r['rider_action_level']}")
    if r["confidence"] not in CONF:
        err(c, "S", "bad confidence")
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", str(r["updated_at"])):
        err(c, "S", "updated_at must be an ISO date")
    fl = r["flags"]
    if not isinstance(fl, dict) or set(fl) != {"mil", "emissions_relevant", "limp_possible"} \
            or not all(isinstance(v, bool) for v in fl.values()):
        err(c, "S", "flags must be exactly mil, emissions_relevant, limp_possible booleans")
    df = r["derived_from"]
    if not isinstance(df, dict) or set(df) != DERIVED_KEYS:
        err(c, "S", "derived_from keys wrong")
        return
    if df["source"] != "OBDex" or df["licence"] != "CC0-1.0":
        err(c, "S", "derived_from source or licence wrong")
    if df["mode"] not in MODES:
        err(c, "S", "derived_from.mode not allowed")
    # ---- R11: v2 fields
    if r["verification"] not in set(VERIFICATION.values()):
        err(c, "R11", f"verification '{r['verification']}' is not an allowed AI-authored label")
    elif df["mode"] in VERIFICATION and r["verification"] != VERIFICATION[df["mode"]]:
        err(c, "R11", f"verification must be {VERIFICATION[df['mode']]} in {df['mode']} mode")
    if not isinstance(r["needs_independent_review"], bool):
        err(c, "R11", "needs_independent_review must be boolean")
    if r["can_ride_to_workshop"] not in RIDE:
        err(c, "R11", f"can_ride_to_workshop must be one of {sorted(RIDE)}")
    elif r["rider_action_level"] in RIDE_ALLOWED and r["can_ride_to_workshop"] not in RIDE_ALLOWED[r["rider_action_level"]]:
        err(c, "R11", f"can_ride_to_workshop {r['can_ride_to_workshop']} deviates from the D4 mapping for "
                      f"{r['rider_action_level']} (allowed {sorted(RIDE_ALLOWED[r['rider_action_level']])})")
    aw = r["applies_when"]
    if aw is not None:
        if not isinstance(aw, dict) or not aw or any(k not in APPLIES_KEYS or not APPLIES_KEYS[k](v)
                                                     for k, v in aw.items()):
            err(c, "R11", f"applies_when must be null or use only {sorted(APPLIES_KEYS)} with valid values")
    rk = ctx["rank"].get(c)
    if rk is None:
        err(c, "S", "code is not in relevance_ranking.csv")
        tags = []
    else:
        tags = ctx["tags"][c]
        if rk["write_ok"] != "yes":
            err(c, "S", "code has a suspect title (write_ok = no); no entry may be written")
        if r["standard_title_en"] != rk["title_standard"]:
            err(c, "S", "standard_title_en differs from the title in force in relevance_ranking.csv")
        want = "override" if c in ctx["overrides"] else "obdex"
        if df["title_basis"] != want:
            err(c, "S", f"derived_from.title_basis must be {want}")
        std = rk["title_standard"]
        if SECOND_CYL.search(std) and not (aw and aw.get("cylinders_min") == 2):
            err(c, "R11", "code needs a second cylinder: applies_when must be {cylinders_min: 2}")
    # ---- S: lengths
    for k, lim in LIMITS.items():
        if not isinstance(r[k], str) or not r[k].strip():
            err(c, "S", f"{k} empty or not a string")
        elif len(r[k]) > lim:
            err(c, "S", f"{k} is {len(r[k])} chars, limit {lim}")
    for k, (lo, hi, lim) in LIST_LIMITS.items():
        v = r[k]
        if not isinstance(v, list) or not (lo <= len(v) <= hi):
            err(c, "S", f"{k} needs {lo} to {hi} items")
            continue
        if len(set(x.lower() for x in v)) != len(v):
            err(c, "S", f"{k} has duplicate items")
        for x in v:
            if not isinstance(x, str) or not x.strip():
                err(c, "S", f"{k} has an empty item")
            elif len(x) > lim:
                err(c, "S", f"{k} item is {len(x)} chars, limit {lim}: {x[:40]}...")
    if not all(isinstance(r[k], str) for k in ("meaning_en", "rider_advice_en")) \
            or not all(isinstance(x, str) for k in LIST_LIMITS for x in r[k]):
        return
    ms = SENT_END.split(r["meaning_en"].strip())
    if len(ms) != 1 or not r["meaning_en"].strip().endswith("."):
        err(c, "S", "meaning_en must be exactly one sentence ending with a full stop")
    ads = SENT_END.split(r["rider_advice_en"].strip())
    if len(ads) > 2:
        err(c, "S", "rider_advice_en must be 1 or 2 sentences")
    for s in ms + ads:
        if len(s.split()) > 32:
            warn(c, "S", f"long sentence ({len(s.split())} words), simplify for Hindi translation")
    # ---- S: forbidden text and wording
    t = all_text(r)
    for name, rx in [("German character", GERMAN), ("currency", CURRENCY), ("URL", URL),
                     ("banned absolute", ABSOLUTES), ("number with unit", UNITS),
                     ("pin number", PINNO), ("part number", PARTNO)]:
        m = rx.search(t)
        if m:
            err(c, "S", f"{name}: '{m.group(0)}'")
    m = VERIFIED.search(t)
    if m:
        err(c, "D6", f"the word '{m.group(0)}' must not appear in any text (entries are AI-authored guidance)")
    if LONGNUM.search(t):
        warn(c, "S", "contains a number of 3+ digits; check it is not a part or pin number")
    for rx, pref in VARIANTS.items():
        m = re.search(rx, t, re.I)
        if m:
            err(c, "S", f"use '{pref}' instead of '{m.group(0)}'")
    for rx, pref in TERMS.items():
        m = re.search(rx, t)
        if m:
            err(c, "S", f"use '{pref}' instead of '{m.group(0)}'")
    # ---- S: rubric level
    lvl = r["rider_action_level"]
    allowed = set()
    for tg in tags:
        allowed |= TAG_LEVELS.get(tg, set())
    if rk is not None:
        if not allowed:
            err(c, "S", f"no rubric mapping for tags {tags}")
        elif lvl not in allowed:
            err(c, "S", f"level {lvl} not allowed for {tags} (allowed {sorted(allowed)})")
    adv = r["rider_advice_en"].lower()
    must_review = lvl == "STOP" or c[0] in "CB" or r["confidence"] == "low" or bool(set(tags) & ABS_TAGS) \
        or bool(SMELL.search(t))
    if must_review and r["needs_independent_review"] is not True:
        err(c, "S", "needs_independent_review must be true (STOP, chassis or braking, low confidence, petrol smell)")
    # ---- R1 circular advice
    for field in ("rider_advice_en", "rider_action_basis", "meaning_en", "can_ride_reason"):
        for rx in R1_PATTERNS:
            m = rx.search(r[field])
            if m:
                err(c, "R1", f"circular advice in {field}: '{m.group(0)}' (if it has stalled the rider has already stopped)")
    # ---- R2 assumed hardware
    for field in ("title_en", "meaning_en", "rider_action_basis", "rider_advice_en", "can_ride_reason"):
        for seg in segments(r[field]):
            m = R2_HARDWARE.search(seg)
            if m and not re.search(r"\bif your bike\b", seg, re.I):
                err(c, "R2", f"assumed hardware '{m.group(0)}' in {field}; write 'if your bike ...' or remove")
    for x in r["likely_causes_en"]:
        m = R2_HARDWARE.search(x)
        if m and not re.search(r"\bif your bike\b", x, re.I):
            err(c, "R2", f"assumed hardware '{m.group(0)}' in a cause")
    for x in r["technician_hints_en"]:
        m = R2_HARDWARE.search(x)
        if m and not R2_SCAN.fullmatch(m.group(0)) and not re.search(r"\bif your bike\b", x, re.I):
            err(c, "R2", f"assumed hardware '{m.group(0)}' in a hint")
    # ---- R3 level and text agree
    if lvl in ("SERVICE_SOON", "MONITOR", "INFO"):
        for field in ("meaning_en", "rider_action_basis", "rider_advice_en", "can_ride_reason"):
            for seg in segments(r[field]):
                m = R3_CLAIM.search(seg)
                if m and not re.search(r"\bif\b", seg, re.I):
                    err(c, "R3", f"{lvl} entry makes an unconditional claim '{m.group(0)}' in {field}; "
                                 f"use 'if ...' wording or raise the level")
    if lvl == "STOP":
        if not re.search(r"pull over|\bstop\b", adv) or not re.search(r"do not (keep )?(ride|riding)\b|stop riding", adv):
            err(c, "R3", "STOP advice must tell the rider to stop (pull over) and not to keep riding")
    if lvl in ("MONITOR", "INFO") and re.search(r"pull over", adv):
        err(c, "R3", f"{lvl} advice should not tell the rider to pull over")
    # ---- R4 petrol smell
    if SMELL.search(t) and not STRONG_SMELL.search(r["rider_advice_en"]):
        err(c, "R4", "mentions a petrol smell but the advice lacks 'If you smell petrol strongly near the engine "
                     "or tank, or see fuel dripping, stop and do not ride.'")
    # ---- R5 ABS and wheel speed
    if set(tags) & ABS_TAGS or c[0] == "C":
        a = r["rider_advice_en"]
        if not (R5_BRAKES.search(a) and R5_ABSOFF.search(a) and R5_LOCK.search(a)):
            err(c, "R5", "ABS rule: advice must say the normal brakes still work, ABS is off, and a wheel can lock "
                         "in hard braking")
        if R5_BAD.search(t):
            err(c, "R5", f"ABS rule: forbidden reassurance '{R5_BAD.search(t).group(0)}'")
        for seg in segments(a):
            if (R5_BRAKES.search(seg) or R5_ABSOFF.search(seg) or R5_LOCK.search(seg)) and R5_HEDGE.search(seg):
                err(c, "R5", f"ABS rule: the plain sentence must not be hedged ('{R5_HEDGE.search(seg).group(0)}')")
        if lvl != "SERVICE_SOON":
            err(c, "R5", "ABS and wheel-speed codes must be SERVICE_SOON (STOP only for fluid or pressure loss)")
        if R5_WHEEL_TITLE.search(r["title_en"]):
            err(c, "R5", "rider title must not name a car wheel position or 'listed as'")
    # ---- R6 direction of low and high codes
    if rk is not None:
        dr = direction(rk["title_standard"])
        if dr:
            low = dr == "LOW"
            right, wrong = (r"\b(below|low|lower)\b", r"\b(above|higher|high)\b") if low else \
                           (r"\b(above|high|higher)\b", r"\b(below|lower|low)\b")
            mean = r["meaning_en"]
            if not re.search(right, mean, re.I) or re.search(wrong, mean, re.I):
                err(c, "R6", f"standard title says {dr}: the meaning must say {'below/low' if low else 'above/high'} "
                             f"and not the opposite")
            want = "voltage below threshold" if low else "voltage above threshold"
            bad = "voltage above threshold" if low else "voltage below threshold"
            if want not in r["title_en"].lower() or bad in r["title_en"].lower():
                err(c, "R6", f"standard title says {dr}: title_en must use '{want}'")
            if set(tags) & R6_TEMP_TAGS:
                need = "hotter" if low else "colder"
                other = "colder" if low else "hotter"
                if need not in mean.lower() or other in mean.lower():
                    err(c, "R6", f"temperature sensor {dr} voltage means it LOOKS {need.upper()}: meaning must say '{need}'")
    # ---- R7 car-only parts
    for x in [r["title_en"], r["meaning_en"], r["rider_advice_en"], r["rider_action_basis"]] \
            + list(r["likely_causes_en"]) + list(r["technician_hints_en"]):
        m = R7_BLOCK.search(x)
        if m:
            err(c, "R7", f"car-only part '{m.group(0)}'")
        if R7_CHAIN.search(x) and not re.search(r"\brare\b", x, re.I):
            err(c, "R7", f"timing chain cause '{R7_CHAIN.search(x).group(0)}' must be marked rare")
    if "catalyst" not in tags:
        for x in r["likely_causes_en"]:
            if R7_CAT.search(x):
                err(c, "R7", f"catalytic converter named as a cause of an unrelated code: '{x}'")
    # ---- R8 hedging
    std_l = (rk["title_standard"] if rk else "").lower()
    for x in list(r["likely_causes_en"]) + list(r["technician_hints_en"]):
        xl = x.lower()
        if R8_FUSERELAY.search(x) and "if fitted" not in xl and not (
                "relay" in std_l and "relay" in R8_FUSERELAY.search(x).group(0).lower()):
            err(c, "R8", f"'{x}' names a fuse or relay: add 'if fitted'")
        if R8_HOSE.search(x) and "if hose-fed" not in xl:
            err(c, "R8", f"'{x}' names a hose: add 'if hose-fed'")
    # ---- R9 plain first
    first12 = " ".join(r["meaning_en"].split()[:12])
    m = R9_WORKSHOP.search(first12)
    if m:
        err(c, "R9", f"meaning starts with workshop wording '{m.group(0)}' in its first 12 words")
    # ---- R10 title
    m = R10_TITLE_BAD.search(r["title_en"])
    if m:
        err(c, "R10", f"title contains '{m.group(0)}'")
    # ---- v4 rules R12 to R22 and T1
    check_v4(r, ctx, err, warn, tags, rk)
    check_q(r, ctx, err, tags, rk)
    # ---- D decisions
    for name, fn in DECISIONS.get(c, []):
        try:
            ok = fn(r)
        except Exception:  # a malformed entry should fail, not crash
            ok = False
        if not ok:
            err(c, "D", f"owner decision not met: {name}")
    # ---- source checks
    src = d.get(c)
    if src is None:
        err(c, "S", "code not found in OBDex")
        return
    if df["repo_commit"] != ctx["commit"]:
        err(c, "S", f"repo_commit {df['repo_commit'][:8]} differs from OBDex checkout {ctx['commit'][:8]}")
    if df["source_entry_sha256"] != entry_hash(src):
        err(c, "S", "source_entry_sha256 does not match the OBDex entry")
    stext = source_text(src)
    sdesc = source_description(src)
    t_parts = t.replace(NETWORK, "").replace(PETROL, "")  # fixed owner sentences name ABS and fuel on purpose
    abs_entry = bool(set(tags) & ABS_TAGS) or c[0] == "C"  # ABS and wheel speed are the subject of these codes
    for rx, toks in PARTS:
        if abs_entry and toks and toks[0] in ("abs", "wheel speed"):
            continue
        if toks and re.search(rx, t_parts, re.I) and not any(tok in stext for tok in toks):
            m = re.search(rx, t_parts, re.I)
            if any(tok in sdesc for tok in toks):
                warn(c, "S", f"names '{m.group(0)}' found only in the source description, not in title/components/causes")
            else:
                err(c, "S", f"names '{m.group(0)}' which is not in the source title, components, causes or description")
    if df["mode"] == "structure-only" and not any(p in r["title_en"].lower() + r["meaning_en"].lower()
                                                  for p in PHRASES + ["circuit fault", "misfire", "too lean",
                                                                      "too rich", "efficiency", "fault", "too low",
                                                                      "too high", "slow response", "overheating",
                                                                      "error", "unstable", "incorrect", "switched off too",
                                                                      "weaker", "rough", "key", "lower than", "higher than",
                                                                      "warming up", "stays below", "not programmed", "short", "leak", "break", "open", "shorted",
                                                                      "not working", "correlation", "does not match", "not match", "touching",
                                                                      "too slow", "stopped", "delay", "slow", "resistance", "limited", "forced", "reacts", "outside"]):
        warn(c, "S", "title/meaning uses none of the shared failure phrases; check it is a generic code")


def check_all(rows, ctx):
    errors, warns = [], []

    def err(c, rule, msg):
        errors.append(f"{c}: {rule}: {msg}")

    def warn(c, rule, msg):
        warns.append(f"{c}: {rule}: {msg}")

    seen, meanings, titles = set(), {}, {}
    for r in rows:
        c = r.get("code", "?")
        check_entry(r, ctx, err, warn)
        cid = r.get("content_id")
        if cid in seen:
            err(c, "S", "duplicate content_id")
        seen.add(cid)
        m = r.get("meaning_en")
        if m in meanings:
            warn(c, "S", f"meaning_en identical to {meanings[m]}")
        meanings[m] = c
        tl = (r.get("title_en") or "").strip().lower()
        if tl in titles:
            pair = frozenset({c, titles[tl]})
            if pair not in TITLE_DUP_EXCEPTIONS:
                err(c, "R10", f"title duplicates the title of {titles[tl]}: '{r['title_en']}'")
        titles[tl] = c
    codes = [r.get("code") for r in rows]
    for c in {x for x in codes if codes.count(x) > 1}:
        err(c, "S", "code appears more than once")
    return errors, warns


def main():
    args = sys.argv[1:]
    seed = next((a for a in args if a.endswith(".jsonl")), os.path.join(HERE, "generic_en_seed.jsonl"))
    obdex = args[args.index("--obdex") + 1] if "--obdex" in args else os.environ.get("OBDEX_DIR", "/tmp/obdex")
    ranking = args[args.index("--ranking") + 1] if "--ranking" in args else os.path.join(HERE, "relevance_ranking.csv")
    only = set(args[args.index("--codes") + 1].split(",")) if "--codes" in args else None
    ctx = build_context(obdex, ranking)
    rows, bad = [], []
    for n, line in enumerate(open(seed, encoding="utf-8"), 1):
        if not line.strip():
            continue
        try:
            r = json.loads(line)
        except json.JSONDecodeError as ex:
            bad.append(f"line {n}: S: invalid JSON: {ex}")
            continue
        if only is None or r.get("code") in only:
            rows.append(r)
    errors, warns = check_all(rows, ctx)
    errors = bad + errors
    print(f"{len(rows)} entries checked in {seed} against OBDex commit {ctx['commit']}")
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
