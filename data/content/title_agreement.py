#!/usr/bin/env python3
"""Two-source title agreement (Step T): OBDex standard title against the Wal33D generic title.

Usage:
  python3 title_agreement.py [--db /tmp/dtc-database/data/dtc_codes.db] [--ranking relevance_ranking.csv]
                             [--seed generic_en_seed.jsonl] [--out title_agreement.csv]
                             [--held held_back_titles_v2.csv]

Sources (both scratch clones live OUTSIDE the project repository):
  OBDex      https://github.com/foerbsnavi/OBDex   (CC0-1.0 data)  titles come from relevance_ranking.csv
  Wal33D     https://github.com/Wal33D/dtc-database (MIT)          table dtc_definitions, manufacturer = 'GENERIC'

The OBDex side is the title in force: title_overrides.csv (the 8 owner-checked titles) is applied first, which
relevance_ranking.csv already did (title_standard). The raw OBDex title is kept in the obdex_title column.

Verdict rule (fixed in advance, not tuned to the result):
  1. normalise both titles (case, quotes, dashes, brackets, "bank 1 sensor 2" -> b1s2, spelling, filler words
     "circuit", "malfunction", "input", "voltage", "system", "control" are dropped, "sensor/switch" -> "sensor")
  2. DISCRIMINATORS are the tokens that change the meaning of a code: wheel position, bank/sensor numbers,
     one-letter markers (A, B, C ...), cylinder numbers, and the failure words low, high, open, short, intermittent,
     range, performance, slow, delayed, stuck, rich, lean, correlation, off, no signal, erratic, supply, etc.
  3. AGREE    both titles exist, the discriminator sets are identical and similarity >= 0.80
     DISAGREE both titles exist and either the discriminators differ or similarity < 0.80
     MISSING  the code has no GENERIC row in the Wal33D database
  similarity = 0.5 * token-set Jaccard + 0.5 * difflib ratio of the normalised strings (0 to 1).

A DISAGREE is not proof that OBDex is wrong. It only means two independent sources do not say the same thing, so
the title is not trusted for writing until it has been checked.
"""
import csv
import difflib
import json
import os
import re
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
THRESHOLD = 0.80

DROP_WORDS = {"circuit", "malfunction", "input", "control", "a/b", "the", "of", "detected", "condition", "or",
              "and", "bank", "too", "fault", "module", "terminal", "emission", "emissions", "switch", "with", "from",
              "received", "data", "sensor", "internal", "ipc"}
SPELL = {"immobilizer": "immobiliser", "evaporative": "evap", "shorted": "short", "ecm": "ecu", "pcm": "ecu"}
# A marker that the standard treats as "the first or only one": "Sensor A", "Sensor 1", "Bank 1", "Fan 1".
# It is ignored when one title has it and the other has no marker of the same kind; B, C, 2 and so on never are.
DEFAULT_MARKERS = {"a", "s1", "b1", "1"}
FAILURE_WORDS = {"low", "high", "open", "short", "intermittent", "range", "performance", "slow", "delayed",
                 "stuck", "rich", "lean", "correlation", "off", "no", "signal", "erratic", "supply", "stalled",
                 "excessively", "long", "frequency", "mismatch", "incompatible", "invalid", "not",
                 "programmed", "leak", "small", "large", "very", "loose", "cap", "purge", "flow", "incorrect",
                 "insufficient", "overspeed", "over", "temperature", "resistance", "heater", "idle",
                 "forced", "limited", "shutdown", "minimum", "closed", "activity", "response", "relay", "lamp",
                 "warm", "up", "efficiency", "threshold", "below", "above", "pump", "motor", "current",
                 "ground", "battery", "bus", "lost", "communication", "cylinder", "speed"}
SUBJECT_WORDS = {"security", "immobiliser", "powertrain", "abs", "throttle", "suspension", "gateway", "body",
                 "cluster", "instrument", "tcm", "hvac", "brake", "pedal", "steering", "yaw", "acceleration",
                 "knock", "coolant", "oil", "intake", "ambient", "barometric", "manifold", "fuel",
                 "ignition", "coil", "injector", "camshaft", "crankshaft", "o2sensor", "catalyst", "evap",
                 "fan", "wheel", "tone", "vent", "valve", "starter", "generator", "field"}
POSITION = {"left", "right", "front", "rear"}
MARKER_KINDS = [("sensorbank", re.compile(r"b\ds\d")), ("bank", re.compile(r"b\d")), ("sensor", re.compile(r"s\d")),
                ("cyl", re.compile(r"cyl\d")), ("digit", re.compile(r"\d+")),
                ("letter", re.compile(r"[a-z]"))]


def normalise(title):
    t = title.lower().replace("\u2014", " ").replace("\u2013", " ")
    t = t.replace('"', "").replace("'", "").replace("(", " ").replace(")", " ").replace(",", " ")
    t = t.replace("anti-lock brake system", "abs").replace("anti lock brake system", "abs")
    t = re.sub(r"\babs\s+abs\b", "abs", t)
    t = t.replace("secondary air injection", "air").replace("serial data gateway", "gateway")
    t = t.replace("cooling fan", "fan").replace("check sum", "checksum")
    t = t.replace("throttle/pedal", "throttle").replace("throttle pedal", "throttle")
    t = t.replace("ecm or pcm", "ecm/pcm").replace("ecm/pcm", "ecu").replace("sensor/switch", "sensor")
    t = t.replace("switch/sensor", "sensor").replace("sensor or switch", "sensor").replace("control module", "ecu")
    t = t.replace("field/f ", "field ").replace("lamp/l ", "lamp ").replace("lamp l ", "lamp ")
    t = t.replace("intermittent/erratic", "intermittent").replace("intermittent erratic", "intermittent")
    t = t.replace("o2 sensor", "o2sensor").replace("ho2s", "o2sensor")
    t = t.replace("-", " ")
    t = re.sub(r"\bbank\s*(\d)\s*(?:,|\s)*(?:sensor|s)\s*(\d)\b", r"b\1 s\2", t)
    t = re.sub(r"\bbank\s*(\d)\b", r"b\1", t)
    t = re.sub(r"\bsensor\s*(\d)\b", r"s\1", t)
    t = re.sub(r"\bcylinder\s*#?(\d)\b", r"cyl\1", t)
    t = re.sub(r"\blow\s+(input|voltage)\b", "low", t)
    t = re.sub(r"\bhigh\s+(input|voltage)\b", "high", t)
    t = re.sub(r"\b(circuit|sensor)/open\b", r"\1 open", t)
    t = re.sub(r"[^a-z0-9 ]+", " ", t)
    toks = []
    for w in t.split():
        w = SPELL.get(w, w)
        if not w or w in DROP_WORDS:
            continue
        toks.append(w)
    if "manifold" in toks and "barometric" in toks:  # "MAP/Barometric Pressure" is one name for the same sensor
        toks = [w for w in toks if w != "barometric"]
    return toks


def marker_kind(w):
    for kind, rx in MARKER_KINDS:
        if rx.fullmatch(w):
            return kind
    return None


def discriminators(toks):
    return {w for w in toks if w in POSITION or w in FAILURE_WORDS or w in SUBJECT_WORDS or marker_kind(w)}


def key_difference(ta, tb):
    """Discriminators that differ, ignoring a default marker that only one title carries."""
    da, db = discriminators(ta), discriminators(tb)
    kinds_a = {marker_kind(w) for w in da if marker_kind(w)}
    kinds_b = {marker_kind(w) for w in db if marker_kind(w)}
    only_a, only_b = da - db, db - da
    only_a = {w for w in only_a if not (w in DEFAULT_MARKERS and marker_kind(w) not in kinds_b)}
    only_b = {w for w in only_b if not (w in DEFAULT_MARKERS and marker_kind(w) not in kinds_a)}
    return sorted(only_a), sorted(only_b)


def strip_default(toks):
    return [w for w in toks if w not in DEFAULT_MARKERS]


def similarity(a, b):
    ta, tb = strip_default(normalise(a)), strip_default(normalise(b))
    sa, sb = set(ta), set(tb)
    jac = len(sa & sb) / len(sa | sb) if sa | sb else 0.0
    ratio = difflib.SequenceMatcher(None, " ".join(sorted(ta)), " ".join(sorted(tb))).ratio()
    return 0.5 * jac + 0.5 * ratio


def compare(obdex_title, wal_title):
    """Return (similarity, verdict, note)."""
    if wal_title is None:
        return 0.0, "MISSING", "no GENERIC row for this code in the Wal33D database"
    sim = similarity(obdex_title, wal_title)
    only_o, only_w = key_difference(normalise(obdex_title), normalise(wal_title))
    if only_o or only_w:
        return sim, "DISAGREE", f"MEANING: key words differ: OBDex only {only_o}; Wal33D only {only_w}"
    if sim < THRESHOLD:
        return sim, "DISAGREE", f"WORDING: same key words but similarity {sim:.2f} is below {THRESHOLD}"
    return sim, "AGREE", ""


def load_wal(db_path):
    con = sqlite3.connect(db_path)
    rows = con.execute("select code, description from dtc_definitions "
                       "where manufacturer = 'GENERIC' and locale = 'en'").fetchall()
    con.close()
    return {c: d for c, d in rows}


def main():
    a = sys.argv[1:]

    def opt(name, default):
        return a[a.index(name) + 1] if name in a else default

    db = opt("--db", os.environ.get("DTC_DB", "/tmp/dtc-database/data/dtc_codes.db"))
    ranking = opt("--ranking", os.path.join(HERE, "relevance_ranking.csv"))
    seed = opt("--seed", os.path.join(HERE, "generic_en_seed.jsonl"))
    out = opt("--out", os.path.join(HERE, "title_agreement.csv"))
    held = opt("--held", os.path.join(HERE, "held_back_titles_v2.csv"))
    wal = load_wal(db)
    rk = list(csv.DictReader(open(ranking, encoding="utf-8")))
    by_code = {r["code"]: r for r in rk}
    written = set()
    if os.path.exists(seed):
        written = {json.loads(line)["code"] for line in open(seed, encoding="utf-8") if line.strip()}
    frozen = os.path.join(HERE, "held_back_before_step_t.txt")
    prev_held = set(open(frozen).read().split()) if os.path.exists(frozen) else \
        {r["code"] for r in rk if r["write_ok"] != "yes"}
    rows = []
    for r in rk:
        c = r["code"]
        std = r["title_standard"]
        sim, verdict, note = compare(std, wal.get(c))
        if r["title_status"] == "override":
            note = ("owner-checked override applied. " + note).strip()
        rows.append({
            "code": c, "obdex_title": r["title_obdex"], "wal33d_title": wal.get(c, ""),
            "similarity": f"{sim:.2f}", "verdict": verdict, "note": note,
            "title_in_force": std, "title_status": r["title_status"],
            "previously_held_back": "yes" if c in prev_held else "no",
            "entry_written": "yes" if c in written else "no",
        })
    cols = ["code", "obdex_title", "wal33d_title", "similarity", "verdict", "note", "title_in_force",
            "title_status", "previously_held_back", "entry_written"]
    with open(out, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)

    def neighbours(code):
        fam = code[:3]
        n = int(code[1:], 16)
        res = []
        for d in (-2, -1, 1, 2):
            c2 = code[0] + format(n + d, "04X")
            res.append(f"{c2}={wal.get(c2, '?')}")
        return " | ".join(res)

    hcols = ["code", "obdex_title", "wal33d_title", "similarity", "verdict", "note", "previously_held_back",
             "entry_written", "neighbouring_codes_wal33d", "neighbouring_codes_obdex"]
    obdex_titles = {r["code"]: r["title_obdex"] for r in rk}
    with open(held, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=hcols)
        w.writeheader()
        for r in rows:
            if r["verdict"] == "AGREE":
                continue
            c = r["code"]
            n = int(c[1:], 16)
            ob_n = " | ".join(f"{c[0] + format(n + d, '04X')}={obdex_titles.get(c[0] + format(n + d, '04X'), '(not selected)')}"
                              for d in (-2, -1, 1, 2))
            w.writerow({"code": c, "obdex_title": r["obdex_title"], "wal33d_title": r["wal33d_title"],
                        "similarity": r["similarity"], "verdict": r["verdict"], "note": r["note"],
                        "previously_held_back": r["previously_held_back"], "entry_written": r["entry_written"],
                        "neighbouring_codes_wal33d": neighbours(c), "neighbouring_codes_obdex": ob_n})
    tot = {}
    for r in rows:
        tot[r["verdict"]] = tot.get(r["verdict"], 0) + 1
    print(f"{len(rows)} codes; verdicts {tot}")
    prev = [r for r in rows if r["previously_held_back"] == "yes"]
    rest = [r for r in rows if r["previously_held_back"] != "yes"]
    pc = {v: sum(1 for r in prev if r["verdict"] == v) for v in ("AGREE", "DISAGREE", "MISSING")}
    rc = {v: sum(1 for r in rest if r["verdict"] == v) for v in ("AGREE", "DISAGREE", "MISSING")}
    print(f"previously held back ({len(prev)}): {pc}")
    print(f"other ({len(rest)}): {rc}")


if __name__ == "__main__":
    main()
