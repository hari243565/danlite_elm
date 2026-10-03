#!/usr/bin/env python3
"""Shared helpers for the Hindi pass (build_hi.py, validate_hi.py, validator_hi_selftest.py).

Reads the three tables the owner can edit by hand:
  CANONICAL_HI.md   fixed Hindi sentences and clauses (ID | English | Hindi)
  GLOSSARY_HI.md    glossary terms (English | Hindi | Must contain | Note)
and the shipped English seed. Pure standard library.
"""
import json
import os
import re
import sys
import unicodedata

for _stream in (sys.stdout, sys.stderr):  # Windows consoles default to cp1252; the messages carry Hindi
    try:
        _stream.reconfigure(encoding="utf-8")
    except Exception:
        pass

HERE = os.path.dirname(os.path.abspath(__file__))
EN_SEED = os.path.join(HERE, "generic_en_seed.jsonl")
HI_SEED = os.path.join(HERE, "generic_hi_seed.jsonl")
CANON_MD = os.path.join(HERE, "CANONICAL_HI.md")
GLOSS_MD = os.path.join(HERE, "GLOSSARY_HI.md")
TM_DIR = os.path.join(HERE, "hi_tm")
TM_JSON = os.path.join(HERE, "hi_tm.json")

BATCH_SIZE = 40


def nfc(s):
    return unicodedata.normalize("NFC", s)


def read_jsonl(path):
    out = []
    with open(path, encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except ValueError as e:
                    raise SystemExit(f"{path} line {i}: not JSON ({e})")
    return out


def md_tables(path):
    """Yield (section_title, [cells...]) for every data row of every pipe table in a markdown file."""
    section = ""
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("#"):
                section = line.lstrip("#").strip()
                continue
            if not line.startswith("|"):
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if all(set(c) <= set("-: ") for c in cells):
                continue  # separator row
            rows.append((section, cells))
    return rows


def load_canonical():
    """-> (sentences {id: (en, hi)}, clauses {id: (en, hi)}, actions {id: (en, hi)})"""
    sentences, clauses, actions = {}, {}, {}
    for section, cells in md_tables(CANON_MD):
        if len(cells) != 3 or cells[0] in ("ID",):
            continue
        cid, en, hi = cells
        if section.startswith("Whole"):
            target = sentences
        elif section.startswith("Clauses"):
            target = clauses
        elif section.startswith("Rider-action"):
            target = actions
        else:
            continue  # hedges are read by validate_hi.py
        target[cid] = (en, nfc(hi))
    return sentences, clauses, actions


def load_glossary():
    """-> list of dicts {triggers:[...], hindi, must:[...]} (all Hindi NFC)."""
    out = []
    for section, cells in md_tables(GLOSS_MD):
        if len(cells) != 4 or cells[0] == "English":
            continue
        en, hi, must, _note = cells
        triggers = [t.strip() for t in en.split(" / ") if t.strip()]
        musts = [nfc(m.strip()) for m in (must or hi).split(" / ") if m.strip()]
        out.append({"triggers": triggers, "hindi": nfc(hi), "must": musts, "section": section})
    return out


_EN_SENT = re.compile(r"(?<=[.!?])\s+")
_HI_SENT = re.compile(r"(?<=[।.!?])\s+")


def en_sentences(text):
    return [s.strip() for s in _EN_SENT.split(text.strip()) if s.strip()]


def hi_sentences(text):
    return [s.strip() for s in _HI_SENT.split(text.strip()) if s.strip()]


def trigger_regex(term):
    # whole word, optional plural "s"; spaces inside a term match any run of space or hyphen
    body = re.escape(term).replace(r"\ ", r"[\s-]+").replace(r"\-", r"[\s-]")
    flags = 0 if term.isupper() else re.I  # acronyms (ABS, ECU, CAN) match in capitals only
    return re.compile(r"(?<![A-Za-z])" + body + r"(?:s|es)?(?![A-Za-z])", flags)


def english_units(row):
    """Every rider-readable English string of an entry, as (kind, text) in a fixed order.
    kinds: T title, M meaning, C cause, A advice sentence, R can-ride reason, H hint."""
    units = [("T", row["title_en"]), ("M", row["meaning_en"])]
    units += [("C", c) for c in row["likely_causes_en"]]
    units += [("A", s) for s in en_sentences(row["rider_advice_en"])]
    units.append(("R", row["can_ride_reason"]))
    units += [("H", h) for h in (row.get("technician_hints_en") or [])]
    return units


def assign_ids(en_rows):
    """Deterministic ids for every distinct (kind, english) in file order: T0001, M0001, C0001..."""
    ids, counters = {}, {}
    for r in en_rows:
        for kind, text in english_units(r):
            if (kind, text) not in ids:
                counters[kind] = counters.get(kind, 0) + 1
                ids[(kind, text)] = f"{kind}{counters[kind]:04d}"
    return ids


def batches(en_rows):
    return [en_rows[i:i + BATCH_SIZE] for i in range(0, len(en_rows), BATCH_SIZE)]
