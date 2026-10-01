#!/usr/bin/env python3
"""Turn authored text into generic_en_seed.jsonl records.

Usage:
  python3 build_seed.py <authored_module> <obdex_dir> <ranking.csv> <out.jsonl> [--append] [--date YYYY-MM-DD]

<authored_module> is a module name in this folder (for example authored_pilot)
that exposes ENTRIES. With --append, codes already in out.jsonl are kept as
they are and never overwritten; only new codes are added. Without --append the
file is rebuilt from the module (used for the Phase A rewrite of the pilot).

Schema version 2. needs_independent_review is true for every STOP, every chassis
or body code, every ABS or wheel-speed code, every low-confidence entry, every
entry that mentions a petrol smell, and every entry whose author set review=True.
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
sys.path.insert(0, HERE)
SYSTEM = {"P": "powertrain", "C": "chassis", "B": "body", "U": "network"}
MODE = "structure-only"  # decided by quality_gate.py (symptoms 26.7% > 15%)
ABS_TAGS = {"lost_comm_abs", "wheel_speed", "abs_pump", "abs_module", "abs_relay", "abs_lamp"}
FUEL_SMELL = re.compile(r"(fuel|petrol|gasoline)[ -]?(smell|odou?r)|smell (of )?(fuel|petrol)", re.I)


def load_obdex(path):
    d = {}
    loader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
    for f in sorted(glob.glob(f"{path}/data/generic/*.yaml")):
        for e in yaml.load(open(f, encoding="utf-8"), Loader=loader):
            d[e["code"]] = e
    return d


def entry_hash(e):
    blob = json.dumps(e, sort_keys=True, ensure_ascii=False, default=str)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def main(argv):
    mod = __import__(argv[0])
    obdex_dir, ranking, out = argv[1], argv[2], argv[3]
    append = "--append" in argv
    date = argv[argv.index("--date") + 1] if "--date" in argv else "2026-10-01"
    commit = subprocess.check_output(["git", "-C", obdex_dir, "rev-parse", "HEAD"], text=True).strip()
    d = load_obdex(obdex_dir)
    rows_rank = list(csv.DictReader(open(ranking, encoding="utf-8")))
    rank = {r["code"]: int(r["rank"]) for r in rows_rank}
    info = {r["code"]: r for r in rows_rank}
    existing = []
    if append and os.path.exists(out):
        existing = [json.loads(line) for line in open(out, encoding="utf-8") if line.strip()]
    have = {r["code"] for r in existing}
    new = []
    for a in mod.ENTRIES:
        c = a["code"]
        if c in have:
            continue
        assert c in rank, f"{c} not in relevance ranking"
        assert c in d, f"{c} not in OBDex"
        f_mil, f_emis, f_limp = a["flags"]
        ri = info[c]
        assert ri["write_ok"] == "yes", f"{c} has a suspect title and must not be written"
        tags = set(ri["reason_tags"].split(";"))
        text = " ".join([a["title"], a["meaning"], a["basis"], a["advice"]] + a["causes"] + a["hints"])
        review = (a.get("review", False) or a["level"] == "STOP" or c[0] in "CB" or a["confidence"] == "low"
                  or bool(tags & ABS_TAGS) or bool(FUEL_SMELL.search(text)))
        new.append({
            "schema_version": 2,
            "content_id": f"generic:{c}:en",
            "code": c,
            "system": SYSTEM[c[0]],
            "title_en": a["title"],
            "standard_title_en": ri["title_standard"],
            "meaning_en": a["meaning"],
            "likely_causes_en": a["causes"],
            "rider_action_level": a["level"],
            "rider_action_basis": a["basis"],
            "rider_advice_en": a["advice"],
            "can_ride_to_workshop": a["ride"][0],
            "can_ride_reason": a["ride"][1],
            "technician_hints_en": a["hints"],
            "flags": {"mil": f_mil, "emissions_relevant": f_emis, "limp_possible": f_limp},
            "applies_when": a.get("applies"),
            "confidence": a["confidence"],
            "derived_from": {
                "source": "OBDex", "licence": "CC0-1.0", "repo_commit": commit,
                "source_entry_sha256": entry_hash(d[c]), "mode": MODE,
                "title_basis": "override" if ri["title_status"] == "override" else "obdex",
            },
            "verification": "ai_authored_from_standard_title",
            "needs_independent_review": review,
            "updated_at": date,
        })
    new.sort(key=lambda r: rank[r["code"]])
    rows = existing + new
    with open(out, "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"wrote {len(rows)} entries ({len(new)} new) to {out}")


if __name__ == "__main__":
    main(sys.argv[1:])
