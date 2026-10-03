#!/usr/bin/env python3
"""Validator for the basic tier (Phase 3A): standard-name-only entries, English and Hindi. Automatic checks only:
no person has read the Hindi, and the two title sources may share an origin.

  py validate_basic.py                       # generic_basic_en.jsonl + generic_basic_hi.jsonl against the plan
  py validate_basic.py --en X --hi Y         # other files
  py validate_basic.py --complete            # also require every included code of every batch to be present

A basic entry may say ONE thing: the standard's name for the code. Every text field except the title is a fixed
sentence, so the checks compare to the fixed text instead of trying to recognise bad wording.

Rules (rule id in messages; each is exercised by validator_basic_selftest.py):
  E1  file and JSON: one object per line, no duplicate content_id, no code twice per language, rows sorted
  E2  English keys exactly the pack shape; schema_version 2; content_id; code format; system from the code prefix
  E3  the title is THE agreed title: code is a planned include, both sources AGREE, the title equals the title in force
  E4  not shipped, not held, not a chassis wheel-speed code, not a manufacturer-defined range (no clash with 308 shipped)
  E5  every text is the fixed pattern: meaning "Standard name: <title>.", the fixed advice and basis, no causes, no hints
  E6  no safety claim anywhere outside the fixed advice (stop, safe, ride, danger, urgent ...)
  E7  level INFO only; can_ride unset (never a claim that the bike is safe to ride); confidence low; verification
      standard_title_only; needs_independent_review true; flags all false; applies_when null; draft in the basis
  E8  provenance: derived_from has the pinned commits, the OBDex entry hash from the plan and the failure type that
      the title's ending clearly states (or none)
  E9  importer limits: title 70 characters (Hindi 112), meaning 200 (Hindi 320), advice 220 (Hindi 352)
  E10 pack size at most 12 MB (raw bytes), manifest count and sha256 match the file
  H1  Hindi row: one per English row and nothing extra; copied fields equal the English row; hi_status machine
  H2  Hindi title is exactly what the vocabulary produces (identical English gives identical Hindi everywhere)
  H3  Hindi text quality: NFC, no replacement/invisible/control character, no Devanagari digits, no dangling marks
  H4  no English left in Hindi: a Latin word is allowed only if the English title has it and it is a single letter,
      a number-letter code (O2, 12V, 4WD) or an acronym the vocabulary keeps in Latin
  H5  numbers, brackets, slashes and quotes of the Hindi title equal those of the English title
  H6  none of the forbidden old spellings (the list in validate_hi.py)
  H7  Hindi meaning/advice/basis are the fixed texts of CANONICAL_HI.md, meaning has the title filled in (no placeholder)
"""
import csv
import hashlib
import json
import os
import re
import sys

import basic_common as B
import basic_hi as H
import hi_common as C
import validate_hi as VH

EN_KEYS = {"schema_version", "content_id", "code", "system", "title_en", "standard_title_en", "meaning_en",
           "likely_causes_en", "rider_action_level", "rider_action_basis", "rider_advice_en",
           "can_ride_to_workshop", "can_ride_reason", "technician_hints_en", "flags", "applies_when", "confidence",
           "derived_from", "verification", "needs_independent_review", "updated_at"}
HI_KEYS = {"schema_version", "content_id", "code", "system", "title_hi", "meaning_hi", "rider_action_level",
           "rider_action_basis_hi", "rider_advice_hi", "can_ride_to_workshop", "flags", "applies_when", "confidence",
           "derived_from", "verification", "needs_independent_review", "updated_at", "hi_status"}
DERIVED_KEYS = {"source", "licence", "repo_commit", "source_entry_sha256", "mode", "title_basis", "failure_type"}
DERIVED_HI = {"source": "OBDex", "licence": B.LICENCE, "mode": "structure-only"}
COPIED = ["schema_version", "code", "system", "rider_action_level", "can_ride_to_workshop", "flags", "applies_when",
          "confidence", "verification", "needs_independent_review", "updated_at"]
FLAGS_OFF = {"mil": False, "emissions_relevant": False, "limp_possible": False}
SAFETY = re.compile(r"\b(stop|stops|stopped|stopping|safe|safely|safety|unsafe|ride|rides|riding|rideable|danger\w*|"
                    r"hazard\w*|emergency|immediately|urgent\w*|critical|severe|fire|crash\w*|never|must|"
                    r"do not|don't|avoid|brake\w*)\b", re.I)
SAFETY_HI = re.compile(r"रुक|न चलाएँ|न चलाएं|खतरा|ख़तरा|सुरक्षित|असुरक्षित|तुरंत|फ़ौरन|आपातकाल|ज़रूर|कभी न|बचें")
WHEEL_SPEED = re.compile(r"wheel[- ]speed|tone wheel|wheel sensor|\b(left|right)\s+(front|rear)\b", re.I)
LATIN_RUN = re.compile(r"[A-Za-z][A-Za-z0-9]*|[0-9]+[A-Za-z][A-Za-z0-9]*")
ISO = re.compile(r"^\d{4}-\d{2}-\d{2}$")
HI_MEANING_CAP, HI_ADVICE_CAP = int(200 * 1.6), int(220 * 1.6)


class Context:
    def __init__(self):
        self.plan = {r["code"]: r for r in csv.DictReader(open(B.CLASSIFICATION, encoding="utf-8", newline=""))}
        self.agreement = {r["code"]: r for r in csv.DictReader(open(B.AGREEMENT_ALL, encoding="utf-8", newline=""))}
        self.shipped = {r["code"] for r in B.read_jsonl(B.SHIPPED_EN)}
        self.held = {r["code"] for r in B.read_jsonl(B.HELD_JSONL)}
        self.translator = H.Translator()
        # multi-letter Latin outputs the vocabulary keeps on purpose (acronyms)
        self.acronyms = {v for v in self.translator.vocab.values() if re.fullmatch(r"[A-Za-z0-9]+", v)}
        for hi in self.translator.vocab.values():
            self.acronyms.update(re.findall(r"[A-Za-z0-9]{2,}", hi))
        canon = {}
        for _section, cells in C.md_tables(C.CANON_MD):
            if len(cells) == 3 and cells[0].startswith("BASIC-"):
                canon[cells[0]] = (cells[1], C.nfc(cells[2]))
        self.canon = canon


def en_tokens(title):
    return set(re.findall(r"[A-Za-z0-9]+", title))


def check_canonical(ctx):
    """The fixed texts in basic_common.py must be the ones in CANONICAL_HI.md."""
    errs = []
    want = {"BASIC-ADVICE": (B.ADVICE_EN, B.ADVICE_HI), "BASIC-MEANING": (B.MEANING_EN, B.MEANING_HI),
            "BASIC-BASIS": (B.BASIS_EN, B.BASIS_HI)}
    for cid, (en, hi) in want.items():
        if cid not in ctx.canon:
            errs.append(("-", "H7", f"{cid} is missing from CANONICAL_HI.md"))
        elif ctx.canon[cid] != (en, C.nfc(hi)):
            errs.append(("-", "H7", f"{cid} in CANONICAL_HI.md differs from basic_common.py"))
    # the fixed advice is the only text allowed to contain words the safety scan looks for
    if SAFETY.search(B.ADVICE_EN.replace("warning lamp", "")) or SAFETY.search(B.MEANING_EN) \
            or SAFETY.search(B.BASIS_EN):
        errs.append(("-", "E6", "a fixed English text contains a safety word"))
    return errs


def check_en(e, ctx):
    errs = []
    code = e.get("code", "?")

    def err(rule, msg):
        errs.append((code, rule, msg))

    keys = set(e.keys())
    if keys != EN_KEYS:
        err("E2", f"keys differ: missing {sorted(EN_KEYS - keys)} extra {sorted(keys - EN_KEYS)}")
        return errs
    if not isinstance(code, str) or not B.CODE_RE.match(code):
        err("E2", "bad code format")
        return errs
    if e["schema_version"] != 2:
        err("E2", "schema_version must be 2")
    if e["content_id"] != f"generic:{code}:en":
        err("E2", f"content_id must be generic:{code}:en")
    if e["system"] != B.SYSTEM_OF[code[0]]:
        err("E2", "system does not match the code prefix")
    title = e["title_en"]
    if not isinstance(title, str):
        err("E2", "title_en is not text")
        return errs

    # E3 the agreed title
    plan, agr = ctx.plan.get(code), ctx.agreement.get(code)
    if plan is None or agr is None:
        err("E3", "code is not in the plan")
    else:
        if plan["status"] != "include":
            err("E3", f"code is not a planned include (plan says: {plan['reason'] or plan['status']})")
        if agr["verdict"] != "AGREE":
            err("E3", f"the two sources do not agree on this code ({agr['verdict']})")
        if " ".join(agr["title_in_force"].split()) != title:
            err("E3", "title is not the agreed title in force")
    if e["standard_title_en"] != title:
        err("E3", "standard_title_en differs from title_en")

    # E4 which codes may be here at all
    if code in ctx.shipped:
        err("E4", "clashes with a shipped entry")
    if code in ctx.held:
        err("E4", "is a held-out code")
    if code[0] == "C" and WHEEL_SPEED.search(title):
        err("E4", "chassis wheel-speed code")
    if B.is_manufacturer_defined(code):
        err("E4", "manufacturer-defined range")

    # E5 fixed patterns
    if e["meaning_en"] != B.MEANING_EN.format(title=title):
        err("E5", "meaning is not exactly 'Standard name: <title>.'")
    if e["rider_advice_en"] != B.ADVICE_EN:
        err("E5", "advice is not the fixed sentence")
    if e["rider_action_basis"] != B.BASIS_EN:
        err("E5", "rider_action_basis is not the fixed text")
    if e["likely_causes_en"] != [] or e["technician_hints_en"] != []:
        err("E5", "causes and hints must be empty: nothing is invented")
    if e["can_ride_reason"] is not None:
        err("E5", "can_ride_reason must be unset")
    if re.search(r"[{}<>]|%[sd]", " ".join(str(e[k]) for k in ("title_en", "meaning_en", "rider_advice_en",
                                                                 "rider_action_basis"))):
        err("E5", "a placeholder is left in the text")

    # E6 safety scan: every text field, with the title removed and the fixed advice allowed
    scan = " | ".join(str(e[k]).replace(title, "") for k in ("meaning_en", "rider_action_basis")) + " | " + \
        str(e["can_ride_reason"] or "")
    if SAFETY.search(scan):
        err("E6", f"safety wording outside the fixed advice: {SAFETY.search(scan).group(0)!r}")
    if e["rider_advice_en"] != B.ADVICE_EN and SAFETY.search(e["rider_advice_en"]):
        err("E6", f"safety wording in the advice: {SAFETY.search(e['rider_advice_en']).group(0)!r}")

    # E7 labels
    if e["rider_action_level"] != B.LEVEL:
        err("E7", f"level must be {B.LEVEL}, not {e['rider_action_level']!r}")
    if e["can_ride_to_workshop"] is not None:
        err("E7", "can_ride_to_workshop must be unset: a basic entry never says the bike can be ridden")
    if e["confidence"] != B.CONFIDENCE:
        err("E7", "confidence must be low")
    if e["verification"] != B.VERIFICATION:
        err("E7", f"verification must be {B.VERIFICATION}")
    if e["needs_independent_review"] is not True:
        err("E7", "needs_independent_review must be true")
    if e["flags"] != FLAGS_OFF:
        err("E7", "flags must be the three booleans, all false (placeholders; the app does not show them)")
    if e["applies_when"] is not None:
        err("E7", "applies_when must be null")
    if not (isinstance(e["updated_at"], str) and ISO.match(e["updated_at"])):
        err("E7", "updated_at must be an ISO date")
    if "draft" not in str(e["rider_action_basis"]).lower():
        err("E7", "the label text must say draft")

    # E8 provenance
    d = e["derived_from"]
    if not isinstance(d, dict) or set(d.keys()) != DERIVED_KEYS:
        err("E8", "derived_from keys are wrong")
    else:
        if d["source"] != "OBDex" or d["licence"] != B.LICENCE or d["repo_commit"] != B.OBDEX_COMMIT:
            err("E8", "derived_from source, licence or OBDex commit is wrong")
        if d["mode"] != "structure-only":
            err("E8", "derived_from mode must be structure-only")
        if plan is not None:
            if d["source_entry_sha256"] != plan["source_sha256"]:
                err("E8", "source_entry_sha256 does not match the plan")
            if d["title_basis"] != ("override" if plan["title_basis"] == "override" else "obdex"):
                err("E8", "title_basis does not match the plan")
        want = B.failure_type(title)[0]
        if d["failure_type"] != want:
            err("E8", f"failure_type {d['failure_type']!r} is not what the title ending states ({want!r})")

    # E9 importer limits
    if len(title) > B.TITLE_CAP_EN:
        err("E9", f"title is {len(title)} characters, the importer limit is {B.TITLE_CAP_EN}")
    if len(e["meaning_en"]) > 200 or len(e["rider_advice_en"]) > 220:
        err("E9", "meaning or advice is over the importer limit")
    return errs


def check_hi(h, en, ctx):
    errs = []
    code = h.get("code", "?")

    def err(rule, msg):
        errs.append((code, rule, msg))

    keys = set(h.keys())
    if keys != HI_KEYS:
        err("H1", f"keys differ: missing {sorted(HI_KEYS - keys)} extra {sorted(keys - HI_KEYS)}")
        return errs
    if h["content_id"] != f"generic:{code}:hi":
        err("H1", f"content_id must be generic:{code}:hi")
    if h["hi_status"] != "machine":
        err("H1", "hi_status must be machine")
    for k in COPIED:
        if h[k] != en.get(k):
            err("H1", f"{k} differs from the English row")
    if h["derived_from"] != DERIVED_HI:
        err("H1", "derived_from must be the lean Hindi record (source, licence, mode)")
    t, m, a, b = h["title_hi"], h["meaning_hi"], h["rider_advice_hi"], h["rider_action_basis_hi"]
    if not all(isinstance(x, str) for x in (t, m, a, b)):
        err("H1", "a Hindi text is not a string")
        return errs

    # H2 the vocabulary decides the Hindi title
    try:
        want = ctx.translator.translate(en["title_en"])
        if t != want:
            err("H2", f"Hindi title is not what the vocabulary produces: {t!r} vs {want!r}")
    except H.Missing as ex:
        err("H2", f"the vocabulary has no Hindi for: {sorted(set(ex.words))}")

    # H3 text quality, H6 forbidden spellings
    for label, x in (("title", t), ("meaning", m), ("advice", a), ("basis", b)):
        if not x.strip():
            err("H3", f"{label} is empty")
            continue
        if C.nfc(x) != x:
            err("H3", f"{label} is not NFC-normalised")
        if VH.INVISIBLE.search(x) or re.search(r"[\x00-\x08\x0b-\x1f\x7f]", x):
            err("H3", f"{label} has a replacement, invisible or control character")
        if x != x.strip() or "  " in x:
            err("H3", f"{label} has leading, trailing or double spaces")
        if VH.DEV_DIGITS.search(x):
            err("H3", f"{label} uses Devanagari digits")
        for p in VH.dangling_marks(x):
            err("H3", f"{label}: dangling combining mark ({p})")
        for bad in VH.FORBIDDEN:
            if bad in x:
                err("H6", f"{label}: forbidden spelling {bad!r}")

    # H4 English left in Hindi (title only; the fixed texts are checked word for word below)
    allowed_here = en_tokens(en["title_en"])
    for run in LATIN_RUN.findall(t):
        if run not in allowed_here:
            err("H4", f"Latin text not in the English title: {run!r}")
        elif not (len(run) == 1 or re.fullmatch(r"\d+[A-Za-z]+|[A-Za-z]+\d+[A-Za-z0-9]*", run)
                  or run in ctx.acronyms):
            err("H4", f"English word left in the Hindi title: {run!r}")
    if not re.search(r"[ऀ-ॿ]", t) and re.search(r"[a-z]", t):
        err("H4", "the Hindi title has no Devanagari at all")

    # H5 numbers and punctuation
    et = en["title_en"]
    if sorted(re.findall(r"\d+", et)) != sorted(re.findall(r"\d+", t)):
        err("H5", "numbers differ between the English and Hindi title")
    for ch in '()/"':
        if et.count(ch) != t.count(ch):
            err("H5", f"{ch!r} appears {et.count(ch)}x in English and {t.count(ch)}x in Hindi")

    # H7 fixed texts, title filled in, no placeholder
    if m != B.MEANING_HI.format(title=t):
        err("H7", "Hindi meaning is not exactly 'मानक नाम: <title>।'")
    if a != B.ADVICE_HI:
        err("H7", "Hindi advice is not the fixed sentence of CANONICAL_HI.md")
    if b != B.BASIS_HI:
        err("H7", "Hindi basis is not the fixed text")
    if re.search(r"[{}<>]|%[sd]", t + m + a + b):
        err("H7", "a placeholder is left in the Hindi text")
    if SAFETY_HI.search(t.replace(t, "") + m.replace(t, "") + b) or \
            (a != B.ADVICE_HI and SAFETY_HI.search(a)):
        err("E6", "safety wording in the Hindi text outside the fixed advice")
    # E9 importer limits for Hindi
    if len(t) > B.TITLE_CAP_HI:
        err("E9", f"Hindi title is {len(t)} characters, the importer limit is {B.TITLE_CAP_HI}")
    if len(m) > HI_MEANING_CAP or len(a) > HI_ADVICE_CAP:
        err("E9", "Hindi meaning or advice is over the importer limit")
    return errs


def check_all(en_rows, hi_rows, ctx, complete=False, en_bytes=None, hi_bytes=None, manifests=None):
    """Whole-pack checks. -> [(code, rule, message)]"""
    errs = check_canonical(ctx)
    for lang, rows in (("en", en_rows), ("hi", hi_rows)):
        seen_ids, seen_codes = set(), set()
        for r in rows:
            cid, code = r.get("content_id"), r.get("code")
            if cid in seen_ids:
                errs.append((code, "E1", f"duplicate content_id {cid}"))
            seen_ids.add(cid)
            if code in seen_codes:
                errs.append((code, "E1", f"code appears twice in the {lang} pack"))
            seen_codes.add(code)
        order = [B.code_sort_key(r["code"]) for r in rows if isinstance(r.get("code"), str) and B.CODE_RE.match(r["code"])]
        if order != sorted(order):
            errs.append(("-", "E1", f"{lang} pack is not sorted by code"))
    for r in en_rows:
        errs += check_en(r, ctx)
    en_by = {r.get("code"): r for r in en_rows}
    hi_by = {r.get("code"): r for r in hi_rows}
    for c in hi_by:
        if c not in en_by:
            errs.append((c, "H1", "Hindi row without an English row"))
    for c in en_by:
        if c not in hi_by:
            errs.append((c, "H1", "English row without a Hindi row"))
    for c, h in hi_by.items():
        if c in en_by:
            errs += check_hi(h, en_by[c], ctx)
    # identical English title -> identical Hindi title, across the whole pack
    memo = {}
    for c, h in hi_by.items():
        if c in en_by:
            t_en = en_by[c].get("title_en")
            if t_en in memo and memo[t_en] != h.get("title_hi"):
                errs.append((c, "H2", f"the same English title has two Hindi titles: {t_en!r}"))
            memo.setdefault(t_en, h.get("title_hi"))
    if complete:
        have = set(en_by)
        for c, p in ctx.plan.items():
            if p["status"] == "include" and c not in have:
                errs.append((c, "E1", "planned include is missing from the pack"))
    # E10 sizes and manifests
    for lang, data in (("en", en_bytes), ("hi", hi_bytes)):
        if data is not None and len(data) > B.PACK_LIMIT_BYTES:
            errs.append(("-", "E10", f"{lang} pack is {len(data)} bytes, over the {B.PACK_LIMIT_BYTES} limit"))
    if manifests:
        for lang, data, m in (("en", en_bytes, manifests.get("en")), ("hi", hi_bytes, manifests.get("hi"))):
            if m is None or data is None:
                continue
            if m.get("entries_count") != data.count(b"\n"):
                errs.append(("-", "E10", f"{lang} manifest entries_count is wrong"))
            if m.get("content_sha256") != hashlib.sha256(data).hexdigest():
                errs.append(("-", "E10", f"{lang} manifest content_sha256 is wrong"))
            if m.get("review_state") != "draft" or m.get("signature") is not None or m.get("scope") != "generic" \
                    or m.get("language") != lang:
                errs.append(("-", "E10", f"{lang} manifest scope, language, review_state or signature is wrong"))
    return errs


def main():
    a = sys.argv[1:]
    en_path = a[a.index("--en") + 1] if "--en" in a else B.EN_PACK
    hi_path = a[a.index("--hi") + 1] if "--hi" in a else B.HI_PACK
    ctx = Context()
    en_rows, hi_rows = B.read_jsonl(en_path), B.read_jsonl(hi_path)
    en_bytes = open(en_path, "rb").read() if os.path.exists(en_path) else b""
    hi_bytes = open(hi_path, "rb").read() if os.path.exists(hi_path) else b""
    manifests = {}
    for lang, mp in (("en", B.EN_MANIFEST), ("hi", B.HI_MANIFEST)):
        if os.path.exists(mp):
            manifests[lang] = json.load(open(mp, encoding="utf-8"))
    errs = check_all(en_rows, hi_rows, ctx, complete="--complete" in a, en_bytes=en_bytes, hi_bytes=hi_bytes,
                     manifests=manifests)
    for c, rule, msg in errs[:60]:
        print(f"{c}  {rule}  {msg}")
    if len(errs) > 60:
        print(f"... and {len(errs) - 60} more")
    print(f"{len(en_rows)} English rows, {len(hi_rows)} Hindi rows, English {len(en_bytes)} bytes, Hindi "
          f"{len(hi_bytes)} bytes: {'FAIL, ' + str(len(errs)) + ' problems' if errs else 'all checks pass'}")
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()
