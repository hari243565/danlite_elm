#!/usr/bin/env python3
"""Self-test for validate_seed.py: each mutation of a good entry must be
rejected. Run: python3 validator_selftest.py  (needs /tmp/obdex)"""
import copy
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
rows = [json.loads(line) for line in open(os.path.join(HERE, "generic_en_seed.jsonl"), encoding="utf-8")]
by = {r["code"]: r for r in rows}

CASES = [
    ("title too long", "P0120", lambda r: r.update(title_en="x" * 80), "limit 70"),
    ("banned absolute", "P0105", lambda r: r.update(rider_advice_en="This will always work."), "banned absolute"),
    ("currency", "P0105", lambda r: r.update(rider_advice_en="It may cost 500 rupees."), "currency"),
    ("url", "P0105", lambda r: r.update(rider_advice_en="See www.example.com."), "URL"),
    ("rubric level", "P0201", lambda r: r.update(rider_action_level="MONITOR"), "not allowed"),
    ("STOP without review", "P0351", lambda r: r.update(needs_mechanic_review=False), "needs_mechanic_review"),
    ("chassis without review", "C0035", lambda r: r.update(needs_mechanic_review=False), "needs_mechanic_review"),
    ("unsourced part", "P0110", lambda r: r["likely_causes_en"].append("Failed fuel pump"), "not in the source"),
    ("voltage figure", "P0195", lambda r: r.update(meaning_en="The signal is stuck at 5 V."), "number with unit"),
    ("variant phrase", "P0195", lambda r: r.update(meaning_en="The signal is shorted to ground."), "short to ground"),
    ("german", "P0130", lambda r: r.update(meaning_en="Größe des Sensors."), "German"),
    ("bad hash", "P0135", lambda r: r["derived_from"].update(source_entry_sha256="0" * 64), "sha256"),
    ("wrong term", "P0335", lambda r: r.update(rider_advice_en="Check engine light is on. Stop."), "warning lamp"),
    ("two-sentence meaning", "P0120", lambda r: r.update(meaning_en="One thing. Two things."), "one sentence"),
    ("too many causes", "P0120", lambda r: r.update(likely_causes_en=["a b", "c d", "e f", "g h", "i j"]), "2 to 4"),
    ("limp mode wording", "P0120", lambda r: r.update(rider_advice_en="It may go into limp mode."), "reduced power mode"),
    ("system mismatch", "U0100", lambda r: r.update(system="powertrain"), "prefix"),
]


def main():
    bad = 0
    for label, code, fn, expect in CASES:
        r = copy.deepcopy(by[code])
        fn(r)
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False, encoding="utf-8") as fh:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
        out = subprocess.run([sys.executable, os.path.join(HERE, "validate_seed.py"), fh.name],
                             capture_output=True, text=True).stdout
        os.unlink(fh.name)
        ok = expect.lower() in out.lower() and "ERROR" in out
        print(("PASS " if ok else "FAIL ") + label)
        bad += 0 if ok else 1
    print(f"{len(CASES) - bad}/{len(CASES)} self-tests passed")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
