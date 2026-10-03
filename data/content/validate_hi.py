#!/usr/bin/env python3
"""Validator for the Hindi seed (aim A4, Phase 2). Automatic checks only: no human has read the Hindi.

  python3 validate_hi.py                      # whole set: generic_hi_seed.jsonl against generic_en_seed.jsonl
  python3 validate_hi.py --upto N             # only batches 1..N are expected (a batch commit)
  python3 validate_hi.py --hi X.jsonl --en Y.jsonl

Checks (a row fails if any fails):
  H1  every shipped English entry has exactly one Hindi row, nothing extra, no duplicates; copied fields equal English
  H2  no empty field; the lists have as many items as the English
  H3  Unicode NFC, no replacement or invisible characters, no dangling combining marks, no Devanagari digits
  H4  Latin letters only in allowed tokens (ABS, ECU, CAN, MAP, MIL, O2, VIN, Danlite, codes, units, sensor letters A-E)
      and never a token the English field does not have
  H5  placeholders and numbers identical to the English
  H6  none of the forbidden spellings (अडैप्टर, एडाप्टर, फॉल्ट without nukta, दोष कोड, and discouraged variants)
  H7  fixed sentences word for word wherever the English uses them (CANONICAL_HI.md), none added where it does not
  H8  every Hindi sentence 30 words or fewer; same sentence count as the English
  H9  rider-action meaning: stop wording and do-not-ride wording present exactly where the English has them; a STOP
      entry has one of them; a MONITOR entry has neither; rider action level, can-ride answer unchanged
  H10 glossary terms (GLOSSARY_HI.md) used wherever the English uses the term; hedges kept
  H11 length ratio between 0.5 and 3 times the English (characters, per field)
  H12 the app importer's own schema rules (kb_validator.dart): keys, enums, caps 1.6x, list sizes, hi_status
"""
import json
import os
import re
import sys
import unicodedata

import hi_common as C

ALLOWED_LATIN = {"ABS", "ECU", "CAN", "MAP", "MIL", "O2", "VIN", "Danlite",
                 "A", "B", "C", "D", "E", "V", "km", "kPa", "RPM", "rpm", "km/h"}
CODE_RE = re.compile(r"\b[PCBU][0-3][0-9A-F]{3}\b")
LATIN_RUN = re.compile(r"[A-Za-z][A-Za-z0-9]*(?:/[A-Za-z]+)?")
DEV_DIGITS = re.compile(r"[०-९]")
INVISIBLE = re.compile(r"[​‌‍⁠﻿ ­�]")

FORBIDDEN = [
    # the four the brief names
    "अडैप्टर", "एडाप्टर", "फॉल्ट", "दोष कोड",
    # discouraged variants of fixed words (anusvara where the app writes chandrabindu, odd loanword spellings)
    "जांच", "कराएं", "चलाएं", "पहुंच", "यहां", "वहां", "कहां", "दिखाएं", "बताएं",
    "एबीएस", "ईसीयू", "सेन्सर", "सैंसर", "इन्जन", "इंजीन", "बेटरी", "थ्रोटल", "इन्जेक्टर", "इंजैक्टर",
    "कनैक्टर", "वर्कशाप", "सर्कट", "सरकिट",
]

STOP_HI = re.compile(r"रुकें|रुक जाएँ|रुकना")
DNR_HI = re.compile(r"न चलाएँ")
STOP_EN = re.compile(r"(?:^|[.;,]\s+|\band\s+|\bthen\s+)(?:stop|pull over)\b(?!\s+(?:suddenly|without|on its own|working))",
                     re.I)
DNR_EN = re.compile(r"\bdo not (?:keep riding|ride)\b|\bnot ride on\b", re.I)

VIRAMA, NUKTA = "्", "़"


def is_consonant(ch):
    o = ord(ch)
    return 0x0915 <= o <= 0x0939 or 0x0958 <= o <= 0x095f


def is_indep_vowel(ch):
    o = ord(ch)
    return 0x0904 <= o <= 0x0914 or o in (0x0960, 0x0961)


def is_matra(ch):
    o = ord(ch)
    return 0x093e <= o <= 0x094c or o in (0x093a, 0x093b, 0x094e, 0x094f, 0x0955, 0x0956, 0x0957, 0x0962, 0x0963)


def is_nasal_sign(ch):
    return 0x0900 <= ord(ch) <= 0x0903


def dangling_marks(text):
    """Return a list of problems with combining marks in a Devanagari string."""
    out = []
    for i, ch in enumerate(text):
        prev = text[i - 1] if i else ""
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if ch == VIRAMA:
            if not (prev and (is_consonant(prev) or prev == NUKTA)):
                out.append(f"halant without a consonant at {i}")
            elif not (nxt and (is_consonant(nxt) or nxt in "‍")):
                out.append(f"halant not followed by a consonant at {i}")
        elif ch == NUKTA:
            if not (prev and is_consonant(prev)):
                out.append(f"nukta without a consonant at {i}")
        elif is_matra(ch):
            if not (prev and (is_consonant(prev) or prev == NUKTA)):
                out.append(f"vowel sign without a consonant at {i}")
        elif is_nasal_sign(ch):
            if not (prev and (is_consonant(prev) or prev == NUKTA or is_matra(prev) or is_indep_vowel(prev))):
                out.append(f"chandrabindu/anusvara/visarga without a base at {i}")
    return out


def latin_tokens(text):
    t = CODE_RE.sub(" ", text)
    return [m.group(0) for m in LATIN_RUN.finditer(t)]


def hi_words(sentence):
    return [w for w in sentence.split() if re.search(r"[\wऀ-ॿ]", w)]


def number_tokens(text):
    return sorted(re.findall(r"\d+(?:\.\d+)?", text))


def placeholder_tokens(text):
    return sorted(re.findall(r"\{[^}]*\}|<[^>]*>|%[sd]", text))


# ----------------------------------------------------------------------------------------------------------------

TEXT_CAPS = {"title": 70, "meaning": 200, "rider_advice": 220, "can_ride_reason": 80}
LIST_CAPS = {"likely_causes": (2, 4, 60), "technician_hints": (1, 3, 90)}
ENGLISH_FACTOR = 1.6
COMMON_REQUIRED = ["schema_version", "content_id", "code", "system", "rider_action_level", "can_ride_to_workshop",
                   "flags", "applies_when", "confidence", "derived_from", "verification", "needs_independent_review",
                   "updated_at"]
HI_ALLOWED = set(COMMON_REQUIRED) | {"title_hi", "meaning_hi", "likely_causes_hi", "rider_advice_hi",
                                     "technician_hints_hi", "can_ride_reason_hi", "rider_action_basis_hi",
                                     "standard_title_en", "rider_action_basis", "can_ride_reason", "hi_status"}
COPIED = ["schema_version", "code", "system", "rider_action_level", "can_ride_to_workshop", "flags", "applies_when",
          "confidence", "derived_from", "verification"]
ALLOWED_VERIFICATION = {"ai_authored_from_standard_title", "ai_authored_adapted"}
RIDE_ALLOWED = {"STOP": {"no"}, "SERVICE_SOON": {"with_care", "yes"}, "MONITOR": {"yes"}, "INFO": {"yes"}}


class Context:
    def __init__(self):
        self.sentences, self.clauses, _actions = C.load_canonical()
        self.glossary = C.load_glossary()
        self.hedges = {k: v for k, v in self.clauses_and_hedges().items()}
        self.gloss_re = [(g, [C.trigger_regex(t) for t in g["triggers"]]) for g in self.glossary
                         if g["section"].lower() != "hedges"]

    def clauses_and_hedges(self):
        out = {}
        for section, cells in C.md_tables(C.CANON_MD):
            if section.startswith("Hedges") and len(cells) == 3 and cells[0] != "ID":
                out[cells[0]] = (cells[1], C.nfc(cells[2]))
        return out


def units_of_english(en):
    """(label, kind, english text) in the same order as units_of_hindi."""
    out = [("title", "T", en["title_en"]), ("meaning", "M", en["meaning_en"])]
    out += [(f"cause {i + 1}", "C", c) for i, c in enumerate(en["likely_causes_en"])]
    out.append(("advice", "A", en["rider_advice_en"]))
    out.append(("can-ride reason", "R", en["can_ride_reason"]))
    out += [(f"hint {i + 1}", "H", h) for i, h in enumerate(en.get("technician_hints_en") or [])]
    return out


def units_of_hindi(hi):
    out = [("title", "T", hi.get("title_hi")), ("meaning", "M", hi.get("meaning_hi"))]
    out += [(f"cause {i + 1}", "C", c) for i, c in enumerate(hi.get("likely_causes_hi") or [])]
    out.append(("advice", "A", hi.get("rider_advice_hi")))
    out.append(("can-ride reason", "R", hi.get("can_ride_reason_hi")))
    out += [(f"hint {i + 1}", "H", h) for i, h in enumerate(hi.get("technician_hints_hi") or [])]
    return out


def check_row(en, hi, ctx):
    """All checks for one English/Hindi pair. Returns a list of (rule, message)."""
    errs = []

    def err(rule, msg):
        errs.append((rule, msg))

    code = en["code"]
    # ---- H12 importer schema rules -----------------------------------------------------------------------------
    keys = set(hi.keys())
    missing = [k for k in COMMON_REQUIRED + ["title_hi"] if k not in keys]
    if missing:
        err("H12", f"missing fields {missing}")
        return errs
    extra = sorted(keys - HI_ALLOWED)
    if extra:
        err("H12", f"unexpected fields {extra}")
    if hi["schema_version"] != 2:
        err("H12", "schema_version must be 2")
    if hi["content_id"] != f"generic:{code}:hi":
        err("H12", f"content_id must be generic:{code}:hi")
    if hi.get("hi_status") not in ("machine", "reviewed"):
        err("H12", f"hi_status {hi.get('hi_status')!r}: the importer accepts only machine or reviewed")
    if hi["verification"] not in ALLOWED_VERIFICATION:
        err("H12", f"verification {hi['verification']!r} is not an allowed label")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(hi["updated_at"])):
        err("H12", "updated_at must be an ISO date")
    if not isinstance(hi["needs_independent_review"], bool):
        err("H12", "needs_independent_review must be true or false")
    elif hi["needs_independent_review"] is not True:
        err("H12", "needs_independent_review must stay true: nobody has read the Hindi")
    if hi["rider_action_level"] not in RIDE_ALLOWED or hi["can_ride_to_workshop"] not in RIDE_ALLOWED[hi["rider_action_level"]]:
        err("H12", "can_ride_to_workshop is not allowed for the level (D4)")
    def cap(base, n=1):
        return int(TEXT_CAPS[base] * ENGLISH_FACTOR)
    for fld, base in (("title_hi", "title"), ("meaning_hi", "meaning"), ("rider_advice_hi", "rider_advice"),
                      ("can_ride_reason_hi", "can_ride_reason")):
        v = hi.get(fld)
        if isinstance(v, str) and len(v) > cap(base):
            err("H12", f"{fld} is {len(v)} characters, the importer limit is {cap(base)}")
    for fld, base in (("likely_causes_hi", "likely_causes"), ("technician_hints_hi", "technician_hints")):
        v = hi.get(fld)
        lo, hi_n, per = LIST_CAPS[base]
        if not isinstance(v, list) or not (lo <= len(v) <= hi_n):
            err("H12", f"{fld} needs {lo} to {hi_n} items")
            continue
        for x in v:
            if isinstance(x, str) and len(x) > int(per * ENGLISH_FACTOR):
                err("H12", f"{fld} item is {len(x)} characters, the importer limit is {int(per * ENGLISH_FACTOR)}")
        if len({x.lower() for x in v if isinstance(x, str)}) != len(v):
            err("H12", f"{fld} has duplicate items")

    # ---- H1 copied fields ----------------------------------------------------------------------------------------
    for k in COPIED:
        if hi.get(k) != en.get(k):
            err("H1", f"{k} differs from the English row")

    # ---- unit-level checks ---------------------------------------------------------------------------------------
    en_units = units_of_english(en)
    hi_units = units_of_hindi(hi)
    for lst_en, lst_hi, name in ((en["likely_causes_en"], hi.get("likely_causes_hi"), "likely causes"),
                                 (en.get("technician_hints_en") or [], hi.get("technician_hints_hi"), "mechanic hints")):
        if not isinstance(lst_hi, list) or len(lst_hi) != len(lst_en):
            err("H2", f"{name}: {len(lst_hi) if isinstance(lst_hi, list) else 'no'} Hindi items for {len(lst_en)} English")
            return errs  # alignment lost, the per-unit checks below would be noise
    for (label, kind, e), (_l2, _k2, h) in zip(en_units, hi_units):
        if not isinstance(h, str) or not h.strip():
            err("H2", f"{label} is empty")
            continue
        # H3 Unicode
        if C.nfc(h) != h:
            err("H3", f"{label} is not NFC-normalised")
        if INVISIBLE.search(h):
            err("H3", f"{label} has a replacement, invisible or non-breaking character")
        if re.search(r"[\x00-\x08\x0b-\x1f\x7f]", h):
            err("H3", f"{label} has a control character")
        if h != h.strip() or "  " in h:
            err("H3", f"{label} has leading, trailing or double spaces")
        if DEV_DIGITS.search(h):
            err("H3", f"{label} uses Devanagari digits; the style sheet says Latin digits")
        for p in dangling_marks(h):
            err("H3", f"{label}: dangling combining mark ({p})")
        # H4 Latin
        toks = latin_tokens(h)
        en_toks = set(latin_tokens(e))
        for t in toks:
            if t not in ALLOWED_LATIN:
                err("H4", f"{label}: Latin text left in: {t!r}")
            elif t not in en_toks:
                err("H4", f"{label}: {t!r} is not in the English field")
        stripped = CODE_RE.sub("", h)
        if re.search(r"[A-Za-z]{2,}", stripped) and not toks:
            err("H4", f"{label}: Latin text left in")
        # H5 numbers and placeholders
        if number_tokens(e) != number_tokens(h):
            err("H5", f"{label}: numbers differ (English {number_tokens(e)}, Hindi {number_tokens(h)})")
        if placeholder_tokens(e) != placeholder_tokens(h):
            err("H5", f"{label}: placeholders differ ({placeholder_tokens(e)} vs {placeholder_tokens(h)})")
        # H6 forbidden spellings
        for bad in FORBIDDEN:
            if bad in h:
                err("H6", f"{label}: forbidden spelling {bad!r}")
        # H8 sentence length and count
        hs = C.hi_sentences(h)
        for s in hs:
            if len(hi_words(s)) > 30:
                err("H8", f"{label}: sentence of {len(hi_words(s))} words (limit 30): {s[:40]}...")
        es = C.en_sentences(e)
        if kind in ("M", "A") and len(hs) != len(es):
            err("H8", f"{label}: {len(hs)} Hindi sentences for {len(es)} English")
        if kind in ("M", "A") and not re.search(r"[।.!?]$", h):
            err("H8", f"{label}: does not end with a full stop (।)")
        if kind in ("T", "C", "R", "H") and re.search(r"[।]$", h):
            err("H8", f"{label}: this field has no full stop in the English")
        # H11 length ratio
        ratio = len(h) / max(1, len(e))
        if not 0.5 <= ratio <= 3:
            err("H11", f"{label}: length ratio {ratio:.2f} (limit 0.5 to 3)")
        # H10 glossary and hedges
        for g, regs in ctx.gloss_re:
            if any(r.search(e) for r in regs) and not any(m in h for m in g["must"]):
                err("H10", f"{label}: English uses {g['triggers'][0]!r} but the Hindi has none of {g['must']}")
        for hid, (hen, hhi) in ctx.hedges.items():
            if re.search(r"(?<![A-Za-z])" + re.escape(hen) + r"(?![A-Za-z])", e, re.I) and hhi not in h:
                err("H10", f"{label}: hedge {hen!r} must appear as {hhi!r}")

    # ---- H7 canonical sentences ----------------------------------------------------------------------------------
    adv_en = C.en_sentences(en["rider_advice_en"])
    adv_hi_text = hi.get("rider_advice_hi") or ""
    adv_hi = C.hi_sentences(adv_hi_text)
    expect_count = {}
    for s in adv_en:
        for cid, (cen, chi) in ctx.sentences.items():
            if s == cen:
                expect_count[chi] = expect_count.get(chi, 0) + 1
    for chi, n in expect_count.items():
        have = sum(1 for s in adv_hi if s == chi)
        if have != n:
            err("H7", f"fixed sentence expected {n}x, found {have}x word for word: {chi[:45]}...")
    for cid, (cen, chi) in ctx.sentences.items():
        if chi not in expect_count and any(s == chi for s in adv_hi):
            err("H7", f"fixed sentence {cid} appears in the Hindi but the English does not use it")
    for cid, (cen, chi) in ctx.clauses.items():
        if cen in en["rider_advice_en"] and chi not in adv_hi_text:
            err("H7", f"clause {cid} must appear word for word")
        if cen not in en["rider_advice_en"] and chi in adv_hi_text:
            err("H7", f"clause {cid} appears in the Hindi but the English does not use it")

    # ---- H9 rider-action meaning ---------------------------------------------------------------------------------
    level = en["rider_action_level"]
    for label, text_en, text_hi in (("advice", en["rider_advice_en"], adv_hi_text),
                                    ("can-ride reason", en["can_ride_reason"], hi.get("can_ride_reason_hi") or "")):
        en_stop, en_dnr = bool(STOP_EN.search(text_en)), bool(DNR_EN.search(text_en))
        hi_stop, hi_dnr = bool(STOP_HI.search(text_hi)), bool(DNR_HI.search(text_hi))
        if en_stop and not hi_stop:
            err("H9", f"{label}: the English tells the rider to stop but the Hindi has no stop wording (रुकें)")
        if hi_stop and not en_stop:
            err("H9", f"{label}: Hindi stop wording (रुकें) where the English does not tell the rider to stop")
        if en_dnr and not hi_dnr:
            err("H9", f"{label}: the English says do not ride but the Hindi has no do-not-ride wording (न चलाएँ)")
        if hi_dnr and not en_dnr:
            err("H9", f"{label}: Hindi do-not-ride wording where the English does not say it")
        if level == "MONITOR" and (hi_stop or hi_dnr):
            err("H9", f"{label}: a MONITOR entry must not contain stop or do-not-ride wording")
    if level == "STOP" and not (STOP_HI.search(adv_hi_text) or DNR_HI.search(adv_hi_text)):
        err("H9", "a STOP entry must contain the Hindi stop wording (रुकें) or do-not-ride wording (न चलाएँ)")
    return errs


def check_all(en_rows, hi_rows, ctx, expected_codes=None):
    """-> list of (code, rule, message). expected_codes limits H1 to a subset (a batch commit)."""
    out = []
    en_by = {r["code"]: r for r in en_rows}
    expected = [r["code"] for r in en_rows] if expected_codes is None else list(expected_codes)
    seen = {}
    for r in hi_rows:
        c = r.get("code", "?")
        if c in seen:
            out.append((c, "H1", "duplicate Hindi row"))
        seen[c] = r
    for c in expected:
        if c not in seen:
            out.append((c, "H1", "no Hindi row for this English entry"))
    for c in seen:
        if c not in en_by:
            out.append((c, "H1", "Hindi row has no shipped English entry (extra row)"))
        elif c not in expected:
            out.append((c, "H1", "Hindi row for an entry outside the expected set"))
    for c, row in seen.items():
        if c in en_by and c in expected:
            for rule, msg in check_row(en_by[c], row, ctx):
                out.append((c, rule, msg))
    return out


def main():
    args = sys.argv[1:]

    def opt(name, default):
        return args[args.index(name) + 1] if name in args else default

    en_rows = C.read_jsonl(opt("--en", C.EN_SEED))
    hi_rows = C.read_jsonl(opt("--hi", C.HI_SEED))
    expected = None
    if "--upto" in args:
        n = int(opt("--upto", "0"))
        expected = [r["code"] for b in C.batches(en_rows)[:n] for r in b]
    ctx = Context()
    errs = check_all(en_rows, hi_rows, ctx, expected)
    for c, rule, msg in errs:
        print(f"ERROR {c} {rule}: {msg}")
    by_rule = {}
    for _c, rule, _m in errs:
        by_rule[rule] = by_rule.get(rule, 0) + 1
    levels = {}
    for r in hi_rows:
        levels[r.get("rider_action_level")] = levels.get(r.get("rider_action_level"), 0) + 1
    print(f"hindi rows: {len(hi_rows)}; English entries: {len(en_rows)}; levels: {levels}; "
          f"errors: {len(errs)} {dict(sorted(by_rule.items()))}")
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()
