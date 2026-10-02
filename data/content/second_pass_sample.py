#!/usr/bin/env python3
"""Step 4: reproducible random sample for the skeptical second pass.

Usage: python3 second_pass_sample.py <batch 2|3> [--obdex /tmp/obdex] [--show]
Batch 2 = the first 100 writable codes written in the 2026-10-02 run, batch 3 = the next 89 (see BATCH2_4_REPORT.md).
Seed = 20261002 + batch number. Writes second_pass_batch<N>_sample.csv (code only); --show prints each sampled entry
next to its OBDex source entry so it can be re-read.
"""
import csv
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import validate_seed as V  # noqa: E402

batch = int(sys.argv[1])
obdex = sys.argv[sys.argv.index("--obdex") + 1] if "--obdex" in sys.argv else os.environ.get("OBDEX_DIR", "/tmp/obdex")
rk = list(csv.DictReader(open(os.path.join(HERE, "relevance_ranking.csv"), encoding="utf-8")))
old = set(open(os.path.join(HERE, "entries_before_step_t.txt")).read().split())
pool = [r["code"] for r in rk if r["code"] not in old and r["write_ok"] == "yes"]
codes = pool[:100] if batch == 2 else pool[100:]
rows = {json.loads(l)["code"]: json.loads(l) for l in open(os.path.join(HERE, "generic_en_seed.jsonl"), encoding="utf-8")}
random.seed(20261002 + batch)
sample = sorted(random.sample([c for c in codes if c in rows], 30))
with open(os.path.join(HERE, f"second_pass_batch{batch}_sample.csv"), "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["code"])
    for c in sample:
        w.writerow([c])
print(len(sample), "codes:", " ".join(sample))
if "--show" in sys.argv:
    d = V.load_obdex(obdex)
    for c in sample:
        r = rows[c]
        e = d[c]
        print(f"\n=== {c} [{r['rider_action_level']}/{r['can_ride_to_workshop']}/{r['confidence']}] {r['title_en']}")
        print("  MEANING:", r["meaning_en"])
        print("  CAUSES:", " | ".join(r["likely_causes_en"]))
        print("  BASIS:", r["rider_action_basis"], "| ADVICE:", r["rider_advice_en"])
        print("  RIDE:", r["can_ride_reason"], "| HINTS:", " | ".join(r["technician_hints_en"]))
        print("  SRC:", r["standard_title_en"], "|", (e.get("description", {}).get("en", "") or "").strip().replace("\n", " ")[:260])
        print("  SRC causes:", [x["label"]["en"] for x in e.get("common_causes", [])], e.get("affected_components"))
