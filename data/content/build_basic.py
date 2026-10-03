#!/usr/bin/env python3
"""Basic tier (Phase 3A, aims A3 tier 2 and A4): a standard-name-only entry, English and Hindi, for every standard code
that two sources name the same way and that is not already shipped. Built by script; no cause, part or advice is invented.

  py build_basic.py --plan --obdex DIR [--db DTC_DB]   decide include/exclude for all 9,533 codes
                                                       (writes title_agreement_all.csv and basic_classification.csv)
  py build_basic.py --status                           batches done, batches left, Hindi words still missing
  py build_basic.py --todo [BATCH]                     Hindi words/phrases the next (or the given) batch still needs
  py build_basic.py --batch BATCH                      build English and Hindi entries of one batch into the packs
  py build_basic.py --next                             build the first batch that is not done
  py build_basic.py --manifests                        rewrite the two manifests from the pack files

The packs are generic_basic_en.jsonl and generic_basic_hi.jsonl, grown one batch at a time and committed after each
batch. A batch is DONE when every code it includes is in both packs, so a re-run resumes by itself.

Exclusion precedence (a code is counted under the FIRST reason that applies):
  shipped, held, chassis wheel speed, missing, disagree, other
where "other" is: title over 70 characters, damaged character in the title, a title shared by several codes, a
manufacturer-defined range. title_overrides.csv wins where it has the code (applied by title_agreement.py --all).
"""
import csv
import hashlib
import json
import os
import re
import sys

import basic_common as B

WHEEL_SPEED = re.compile(r"wheel[- ]speed|tone wheel|wheel sensor", re.I)
OTHER_REASONS = {
    "title_over_70": "title is longer than the importer's 70-character limit",
    "damaged_character": "the title contains a damaged character (U+FFFD) in the source",
    "shared_title": "the same title sits on two or more codes, so it cannot name one of them",
    "manufacturer_range": "manufacturer-defined range; a generic pack must not carry it",
}
COLS = ["code", "prefix", "batch", "status", "reason", "verdict", "title", "title_basis", "failure_type",
        "source_sha256"]


def entry_hash(e):
    blob = json.dumps(e, sort_keys=True, ensure_ascii=False, default=str)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def load_obdex_entries(obdex_dir):
    import glob
    import yaml
    loader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
    d = {}
    for f in sorted(glob.glob(os.path.join(obdex_dir, "data", "generic", "*.yaml"))):
        with open(f, encoding="utf-8") as fh:
            for e in yaml.load(fh, Loader=loader):
                d[e["code"]] = e
    return d


def plan_batches(codes):
    """Equal-sized chunks of about BATCH_TARGET codes per prefix, in order P, C, B, U. -> {code: batch id}"""
    out = {}
    for pfx in B.PREFIX_ORDER:
        cs = sorted((c for c in codes if c[0] == pfx), key=B.code_sort_key)
        if not cs:
            continue
        n = max(1, round(len(cs) / B.BATCH_TARGET))
        size = -(-len(cs) // n)
        for i, c in enumerate(cs):
            out[c] = f"{pfx}{i // size + 1:02d}"
    return out


def do_plan(args):
    import title_agreement as T
    obdex = args[args.index("--obdex") + 1] if "--obdex" in args else os.environ.get("OBDEX_DIR", "/tmp/obdex")
    db = args[args.index("--db") + 1] if "--db" in args else os.environ.get("DTC_DB", "/tmp/dtc-database/data/dtc_codes.db")
    T.run_all(db, obdex, B.AGREEMENT_ALL)
    entries = load_obdex_entries(obdex)
    ag = {r["code"]: r for r in csv.DictReader(open(B.AGREEMENT_ALL, encoding="utf-8", newline=""))}
    shipped = {r["code"] for r in B.read_jsonl(B.SHIPPED_EN)}
    held = {r["code"] for r in B.read_jsonl(B.HELD_JSONL)}
    batch_of = plan_batches(ag)

    # titles shared by several codes (only counted among codes both sources agree on and that are otherwise fine)
    title_count = {}
    for c, r in ag.items():
        if r["verdict"] == "AGREE":
            title_count.setdefault(r["title_in_force"], []).append(c)

    rows = []
    for c in sorted(ag, key=B.code_sort_key):
        r = ag[c]
        title = " ".join(r["title_in_force"].split())
        reason = None
        status = "exclude"
        if c in shipped:
            reason = "shipped"
        elif c in held:
            reason = "held"
        elif c[0] == "C" and (WHEEL_SPEED.search(r["obdex_title"]) or WHEEL_SPEED.search(r["wal33d_title"])
                              or WHEEL_SPEED.search(title)):
            reason = "chassis_wheel_speed"
        elif r["verdict"] == "MISSING":
            reason = "missing"
        elif r["verdict"] == "DISAGREE":
            reason = "disagree"
        elif "�" in title:
            reason = "other:damaged_character"
        elif B.is_manufacturer_defined(c):
            reason = "other:manufacturer_range"
        elif len(title) > B.TITLE_CAP_EN:
            reason = "other:title_over_70"
        elif len(title_count.get(r["title_in_force"], [])) > 1:
            reason = "other:shared_title"
        else:
            status = "include"
        fid = ""
        if status == "include":
            fid = B.failure_type(title)[0] or ""
        rows.append({"code": c, "prefix": c[0], "batch": batch_of[c], "status": status, "reason": reason or "",
                     "verdict": r["verdict"], "title": title, "title_basis": r["title_status"], "failure_type": fid,
                     "source_sha256": entry_hash(entries[c]) if status == "include" else ""})
    with open(B.CLASSIFICATION, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=COLS, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    print_counts(rows)


def print_counts(rows):
    inc = [r for r in rows if r["status"] == "include"]
    print(f"{len(rows)} codes: {len(inc)} included, {len(rows) - len(inc)} excluded")
    reasons = {}
    for r in rows:
        if r["status"] == "exclude":
            reasons.setdefault(r["reason"], {})
            reasons[r["reason"]][r["prefix"]] = reasons[r["reason"]].get(r["prefix"], 0) + 1
    for k in sorted(reasons):
        print(f"  {k:28s} {sum(reasons[k].values()):5d}  {reasons[k]}")
    print("  included by prefix:", {p: sum(1 for r in inc if r["prefix"] == p) for p in B.PREFIX_ORDER})


def load_rows():
    if not os.path.exists(B.CLASSIFICATION):
        raise SystemExit("basic_classification.csv is missing: run  py build_basic.py --plan --obdex DIR")
    return list(csv.DictReader(open(B.CLASSIFICATION, encoding="utf-8", newline="")))


def batch_ids(rows):
    seen = []
    for r in rows:
        if r["batch"] not in seen:
            seen.append(r["batch"])
    return seen


def done_batches(rows):
    en = {e["code"] for e in B.read_jsonl(B.EN_PACK)}
    hi = {e["code"] for e in B.read_jsonl(B.HI_PACK)}
    out = {}
    for b in batch_ids(rows):
        want = [r["code"] for r in rows if r["batch"] == b and r["status"] == "include"]
        out[b] = all(c in en and c in hi for c in want)
    return out


# ---- entries --------------------------------------------------------------------------------------------------


def derived(r):
    fid = r["failure_type"] or None
    return {"source": "OBDex", "licence": B.LICENCE, "repo_commit": B.OBDEX_COMMIT,
            "source_entry_sha256": r["source_sha256"], "mode": "structure-only",
            "title_basis": "override" if r["title_basis"] == "override" else "obdex", "failure_type": fid}


def derived_hi():
    # lean on purpose: the Hindi pack is the larger one, and the English row of the same code carries the full record
    return {"source": "OBDex", "licence": B.LICENCE, "mode": "structure-only"}


def english_entry(r):
    t = r["title"]
    return {
        "schema_version": 2, "content_id": f"generic:{r['code']}:en", "code": r["code"],
        "system": B.SYSTEM_OF[r["code"][0]], "title_en": t, "standard_title_en": t,
        "meaning_en": B.MEANING_EN.format(title=t), "likely_causes_en": [],
        "rider_action_level": B.LEVEL, "rider_action_basis": B.BASIS_EN, "rider_advice_en": B.ADVICE_EN,
        "can_ride_to_workshop": None, "can_ride_reason": None, "technician_hints_en": [],
        "flags": {"mil": False, "emissions_relevant": False, "limp_possible": False},
        "applies_when": None, "confidence": B.CONFIDENCE, "derived_from": derived(r),
        "verification": B.VERIFICATION, "needs_independent_review": True, "updated_at": B.UPDATED_AT,
    }


def hindi_entry(r, title_hi):
    return {
        "schema_version": 2, "content_id": f"generic:{r['code']}:hi", "code": r["code"],
        "system": B.SYSTEM_OF[r["code"][0]], "title_hi": title_hi,
        "meaning_hi": B.MEANING_HI.format(title=title_hi), "rider_action_level": B.LEVEL,
        "rider_action_basis_hi": B.BASIS_HI, "rider_advice_hi": B.ADVICE_HI, "can_ride_to_workshop": None,
        "flags": {"mil": False, "emissions_relevant": False, "limp_possible": False},
        "applies_when": None, "confidence": B.CONFIDENCE, "derived_from": derived_hi(),
        "verification": B.VERIFICATION, "needs_independent_review": True, "updated_at": B.UPDATED_AT,
        "hi_status": "machine",
    }


def write_pack(path, entries):
    entries = sorted(entries, key=lambda e: B.code_sort_key(e["code"]))
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        for e in entries:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")


def write_manifests():
    for path, mpath, lang in ((B.EN_PACK, B.EN_MANIFEST, "en"), (B.HI_PACK, B.HI_MANIFEST, "hi")):
        data = open(path, "rb").read() if os.path.exists(path) else b""
        count = data.count(b"\n")
        m = {"pack_id": f"generic_basic_{lang}", "scope": "generic", "language": lang, "version": 1,
             "entries_count": count, "content_sha256": hashlib.sha256(data).hexdigest(), "created_at": B.UPDATED_AT,
             "min_app_version": "1.0.0", "review_state": "draft", "revoked": [], "signature": None,
             "source": "bundled",
             "content_origin": "content/seed-20261001, data/content/" + os.path.basename(path) + ", built by "
                               "build_basic.py. Standard code names only (verification standard_title_only): no "
                               "cause, part or advice. Titles agreed by OBDex (bc58b0e) and Wal33D (04c43d7). content_sha256 is of the "
                               "file with LF line endings, byte for byte as shipped."}
        if lang == "hi":
            m["content_origin"] += " AI-translated DRAFT Hindi, hi_status machine, not read by any person."
        with open(mpath, "w", encoding="utf-8", newline="\n") as f:
            json.dump(m, f, ensure_ascii=False, indent=2)
            f.write("\n")
    print("manifests written")


def do_batch(bid, rows):
    import basic_hi as H
    todo = [r for r in rows if r["batch"] == bid and r["status"] == "include"]
    if not todo:
        print(f"batch {bid}: nothing to include")
        return True
    tr = H.Translator()
    missing, hi_titles = [], {}
    for r in todo:
        try:
            hi_titles[r["code"]] = tr.translate(r["title"])
        except H.Missing as e:
            missing.extend(e.words)
    if missing:
        uniq = sorted(set(missing))
        print(f"batch {bid}: {len(uniq)} Hindi words/phrases are missing; run  py build_basic.py --todo {bid}")
        return False
    en_old = [e for e in B.read_jsonl(B.EN_PACK) if e["code"] not in {r["code"] for r in todo}]
    hi_old = [e for e in B.read_jsonl(B.HI_PACK) if e["code"] not in {r["code"] for r in todo}]
    write_pack(B.EN_PACK, en_old + [english_entry(r) for r in todo])
    write_pack(B.HI_PACK, hi_old + [hindi_entry(r, hi_titles[r["code"]]) for r in todo])
    write_manifests()
    print(f"batch {bid}: {len(todo)} English and {len(todo)} Hindi entries written")
    return True


def do_todo(bid, rows):
    import basic_hi as H
    tr = H.Translator()
    words = {}
    for r in rows:
        if r["status"] != "include" or (bid and r["batch"] != bid):
            continue
        try:
            tr.translate(r["title"])
        except H.Missing as e:
            for w in e.words:
                words.setdefault(w, r["title"])
    for w in sorted(words):
        print(f"{w}\t# {words[w]}")
    print(f"# {len(words)} missing", file=sys.stderr)


def main():
    a = sys.argv[1:]
    if "--plan" in a:
        do_plan(a)
        return
    if "--manifests" in a:
        write_manifests()
        return
    rows = load_rows()
    if "--status" in a:
        import basic_hi as H
        done = done_batches(rows)
        print(f"batches done {sum(done.values())} of {len(done)}: " +
              " ".join(f"{b}{'*' if d else ''}" for b, d in done.items()))
        print_counts(rows)
        tr = H.Translator()
        miss = set()
        for r in rows:
            if r["status"] == "include":
                try:
                    tr.translate(r["title"])
                except H.Missing as e:
                    miss.update(e.words)
        print(f"Hindi words/phrases missing for the whole list: {len(miss)}; vocabulary size {len(tr.vocab)}")
        return
    if "--todo" in a:
        i = a.index("--todo")
        do_todo(a[i + 1] if i + 1 < len(a) and not a[i + 1].startswith("--") else None, rows)
        return
    if "--batch" in a:
        sys.exit(0 if do_batch(a[a.index("--batch") + 1], rows) else 1)
    if "--next" in a:
        done = done_batches(rows)
        left = [b for b, d in done.items() if not d]
        if not left:
            print("all batches are done")
            return
        sys.exit(0 if do_batch(left[0], rows) else 1)
    print(__doc__)


if __name__ == "__main__":
    main()
