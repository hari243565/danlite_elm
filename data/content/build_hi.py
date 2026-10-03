#!/usr/bin/env python3
"""Build generic_hi_seed.jsonl from the English seed and the Hindi translation memory.

Translation memory: data/content/hi_tm/batchN.txt, one line per distinct English string:
    ID | Hindi text            (lines starting with # and blank lines are ignored)
The ID (T0001, M0001, C0001, A0001, R0001, H0001) is assigned from the English text, see hi_common.assign_ids.
The same English string always gets the same Hindi, so wording stays consistent. An advice sentence that is one of
the fixed sentences in CANONICAL_HI.md is filled in by this program word for word (it never appears in --todo).
The token <TWIN> inside a Hindi sentence is replaced by the fixed twin clause.

  python3 build_hi.py --todo N      list the strings batch N still needs (with the entry for context)
  python3 build_hi.py --upto N      build rows for batches 1..N (all of them without N); fails on a missing string
  python3 build_hi.py --status      how many strings are translated

hi_tm.json (written by every build) records the English text next to each Hindi string; if the English seed changes
under an id the build stops and says which one, so a changed English sentence cannot keep a stale translation.
"""
import hashlib
import json
import os
import sys

import hi_common as C

UPDATED_AT = "2026-10-03"
HI_STATUS = "machine"  # the importer (kb_validator.dart) accepts only "machine" or "reviewed"; see HI_REPORT.md


def load_tm():
    tm = {}
    if not os.path.isdir(C.TM_DIR):
        return tm
    for name in sorted(os.listdir(C.TM_DIR)):
        if not name.endswith(".txt"):
            continue
        with open(os.path.join(C.TM_DIR, name), encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                line = line.rstrip("\n")
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                if " | " not in line:
                    raise SystemExit(f"{name} line {n}: expected 'ID | Hindi'")
                tid, hi = line.split(" | ", 1)
                tid, hi = tid.strip(), C.nfc(hi.strip())
                if tid in tm and tm[tid] != hi:
                    raise SystemExit(f"{name} line {n}: {tid} translated twice with different text")
                tm[tid] = hi
    return tm


def main():
    args = sys.argv[1:]
    en_rows = C.read_jsonl(C.EN_SEED)
    ids = C.assign_ids(en_rows)
    by_id = {v: k for k, v in ids.items()}
    canon, clauses, _actions = C.load_canonical()
    canon_by_en = {en: hi for en, hi in canon.values()}
    twin_hi = clauses["TWIN"][1]
    tm = load_tm()
    unknown = sorted(set(tm) - set(by_id))
    if unknown:
        raise SystemExit(f"hi_tm has ids that match no English string: {unknown[:10]}")

    # drift check against the English recorded with the last build
    if os.path.exists(C.TM_JSON):
        old = json.load(open(C.TM_JSON, encoding="utf-8"))
        for tid, rec in old.items():
            if tid in by_id and by_id[tid][1] != rec["en"] and tid in tm:
                raise SystemExit(f"{tid}: the English text changed since it was translated; re-translate it.\n"
                                 f"  was: {rec['en']}\n  now: {by_id[tid][1]}")

    def hindi_for(kind, text):
        if kind == "A" and text in canon_by_en:
            return canon_by_en[text]
        tid = ids[(kind, text)]
        hi = tm.get(tid)
        return None if hi is None else hi.replace("<TWIN>", twin_hi)

    bs = C.batches(en_rows)

    if "--status" in args:
        need = [k for k in ids if not (k[0] == "A" and k[1] in canon_by_en)]
        done = [k for k in need if ids[k] in tm]
        print(f"distinct strings {len(ids)}; fixed sentences filled automatically {len(ids) - len(need)}; "
              f"translated {len(done)} of {len(need)}; batches {len(bs)}")
        return

    if "--todo" in args:
        n = int(args[args.index("--todo") + 1])
        seen = set()
        for r in bs[n - 1]:
            lines = []
            for kind, text in C.english_units(r):
                tid = ids[(kind, text)]
                if tid in seen or hindi_for(kind, text) is not None:
                    continue
                seen.add(tid)
                lines.append(f"{tid}\t{text}")
            if lines:
                print(f"## {r['code']} [{r['rider_action_level']}, ride: {r['can_ride_to_workshop']}] {r['title_en']}")
                print("\n".join(lines))
        return

    upto = int(args[args.index("--upto") + 1]) if "--upto" in args else len(bs)
    chosen = [r for b in bs[:upto] for r in b]
    out, missing = [], []
    for r in chosen:
        title = hindi_for("T", r["title_en"])
        meaning = hindi_for("M", r["meaning_en"])
        causes = [hindi_for("C", c) for c in r["likely_causes_en"]]
        advice = [hindi_for("A", s) for s in C.en_sentences(r["rider_advice_en"])]
        reason = hindi_for("R", r["can_ride_reason"])
        hints = [hindi_for("H", h) for h in (r.get("technician_hints_en") or [])]
        if None in [title, meaning, reason] + causes + advice + hints:
            missing.append(r["code"])
            continue
        out.append({
            "schema_version": r["schema_version"],
            "content_id": r["content_id"][:-2] + "hi",
            "code": r["code"],
            "system": r["system"],
            "title_hi": title,
            "meaning_hi": meaning,
            "likely_causes_hi": causes,
            "rider_action_level": r["rider_action_level"],
            "rider_advice_hi": " ".join(advice),
            "can_ride_to_workshop": r["can_ride_to_workshop"],
            "can_ride_reason_hi": reason,
            "technician_hints_hi": hints,
            "flags": r["flags"],
            "applies_when": r["applies_when"],
            "confidence": r["confidence"],
            "derived_from": r["derived_from"],
            "verification": r["verification"],
            "needs_independent_review": True,  # nobody has read the Hindi; the English flag does not carry over
            "updated_at": UPDATED_AT,
            "hi_status": HI_STATUS,
        })
    if missing:
        raise SystemExit(f"{len(missing)} entries still have untranslated strings: {missing[:12]}")

    with open(C.HI_SEED, "w", encoding="utf-8", newline="\n") as f:
        for row in out:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    rec = {tid: {"en": by_id[tid][1], "hi": hi} for tid, hi in sorted(tm.items())}
    with open(C.TM_JSON, "w", encoding="utf-8", newline="\n") as f:
        json.dump(rec, f, ensure_ascii=False, indent=0, sort_keys=True)
        f.write("\n")
    print(f"wrote {len(out)} Hindi rows (batches 1..{upto}) to {os.path.basename(C.HI_SEED)}")
    if len(out) == len(en_rows):
        # manifest in the same shape as assets/knowledge/generic_en/manifest.json, for the app's importer
        digest = hashlib.sha256(open(C.HI_SEED, "rb").read()).hexdigest()
        manifest = {
            "pack_id": "generic_hi", "scope": "generic", "language": "hi", "version": 1,
            "entries_count": len(out), "content_sha256": digest, "created_at": UPDATED_AT,
            "min_app_version": "1.0.0", "review_state": "draft", "revoked": [], "signature": None,
            "source": "bundled",
            "content_origin": "content/seed-20261001, data/content/generic_hi_seed.jsonl, built by build_hi.py from "
                              "generic_en_seed.jsonl. AI-translated DRAFT Hindi, hi_status machine, not read by any "
                              "person. content_sha256 is of the file with LF line endings, byte for byte as shipped.",
        }
        with open(os.path.join(C.HERE, "generic_hi_manifest.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"wrote generic_hi_manifest.json (sha256 {digest[:12]}...)")


if __name__ == "__main__":
    main()
