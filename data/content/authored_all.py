"""All authored entries in rank order: pilot + batch 1 (with the v4 fixes applied) + batches 2 to 4.

Usage:  python3 authored_all.py --log      writes fix_log_v4_20261002.csv (what the fixes changed)
build_seed.py imports ENTRIES from this module.
"""
import copy
import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import authored_batch1  # noqa: E402
import authored_fixes_v4  # noqa: E402
import authored_pilot  # noqa: E402
from held_v5 import HELD  # noqa: E402,F401  (build_seed.py moves these out of the shipped seed)

BATCH_MODULES = ["authored_batch2", "authored_batch3", "authored_batch4"]


def _load_batches():
    out = []
    for name in BATCH_MODULES:
        if os.path.exists(os.path.join(HERE, name + ".py")):
            out += __import__(name).ENTRIES
    return out


def apply_fixes(entries, log):
    fixes = authored_fixes_v4.FIXES
    seen = set()
    out = []
    for e in entries:
        e = copy.deepcopy(e)
        f = fixes.get(e["code"])
        if f:
            seen.add(e["code"])
            for k, v in f.items():
                if k == "why":
                    continue
                old = e.get(k)
                if old != v:
                    log.append((e["code"], k, old, v, f["why"]))
                e[k] = v
        out.append(e)
    missing = set(fixes) - seen
    assert not missing, f"fixes for codes that are not in pilot or batch 1: {sorted(missing)}"
    return out


LOG = []
ENTRIES = apply_fixes(authored_pilot.ENTRIES + authored_batch1.ENTRIES, LOG) + _load_batches()

if __name__ == "__main__":
    if "--log" in sys.argv:
        path = os.path.join(HERE, "fix_log_v4_20261002.csv")
        with open(path, "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["code", "field", "old", "new", "why"])
            for code, k, old, new, why in LOG:
                w.writerow([code, k, old if not isinstance(old, (list, tuple, dict)) else repr(old),
                            new if not isinstance(new, (list, tuple, dict)) else repr(new), why])
        print(f"{len(LOG)} field changes on {len({x[0] for x in LOG})} codes -> {path}")
    print(f"{len(ENTRIES)} entries")
