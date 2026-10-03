#!/usr/bin/env python3
"""Shared rules of the basic tier (Phase 3A): standard code names only, English and Hindi.

One place for the fixed texts, the code-range rules, the failure-type rules and the file names, so the builder
(build_basic.py), the validator (validate_basic.py) and the self-test (validator_basic_selftest.py) cannot drift
apart. Pure standard library.

What a basic entry is: the standard's name for a code and nothing more. It carries NO cause, NO part, NO advice
beyond one fixed sentence, and it makes no claim about whether the bike can be ridden.
"""
import json
import os
import re
import sys

for _stream in (sys.stdout, sys.stderr):  # Windows consoles default to cp1252; the messages carry Hindi
    try:
        _stream.reconfigure(encoding="utf-8")
    except Exception:
        pass

HERE = os.path.dirname(os.path.abspath(__file__))
CLASSIFICATION = os.path.join(HERE, "basic_classification.csv")
AGREEMENT_ALL = os.path.join(HERE, "title_agreement_all.csv")
VOCAB = os.path.join(HERE, "basic_hi_vocab.tsv")
TITLE_OVERRIDES_HI = os.path.join(HERE, "basic_hi_titles.tsv")
EN_PACK = os.path.join(HERE, "generic_basic_en.jsonl")
HI_PACK = os.path.join(HERE, "generic_basic_hi.jsonl")
EN_MANIFEST = os.path.join(HERE, "generic_basic_en_manifest.json")
HI_MANIFEST = os.path.join(HERE, "generic_basic_hi_manifest.json")
SHIPPED_EN = os.path.join(HERE, "generic_en_seed.jsonl")
HELD_JSONL = os.path.join(HERE, "held_entries_v5.jsonl")

UPDATED_AT = "2026-10-03"
OBDEX_COMMIT = "bc58b0eb7273226a1aabae98e956b70b8362bda1"
WAL33D_COMMIT = "04c43d72e7db7197658b6f72fe582c5076d9eee8"
PACK_LIMIT_BYTES = 12 * 1024 * 1024
BATCH_TARGET = 500

SYSTEM_OF = {"P": "powertrain", "C": "chassis", "B": "body", "U": "network"}
PREFIX_ORDER = "PCBU"
CODE_RE = re.compile(r"^[PCBU][0-3][0-9A-F]{3}$")

# ---- the fixed texts (the Hindi advice is also stored in CANONICAL_HI.md, section "Basic tier") --------------
ADVICE_EN = ("This code has a standard name only. We have no further guidance for it yet. If the warning lamp is on "
             "or the bike runs badly, have it checked soon.")
ADVICE_HI = ("इस कोड का सिर्फ़ मानक नाम उपलब्ध है। अभी इसके बारे में हमारे पास और जानकारी नहीं है। "
             "अगर चेतावनी लैंप जल रहा हो या बाइक ठीक से न चल रही हो, तो जल्द जाँच कराएँ।")
MEANING_EN = "Standard name: {title}."
MEANING_HI = "मानक नाम: {title}।"
BASIS_EN = "Draft: standard name only"
BASIS_HI = "ड्राफ़्ट: सिर्फ़ मानक नाम"
VERIFICATION = "standard_title_only"
LEVEL = "INFO"
CONFIDENCE = "low"
LICENCE = "CC0-1.0"

# Importer limits (kb_validator.dart): English title 70, Hindi 1.6 times that.
TITLE_CAP_EN = 70
TITLE_CAP_HI = int(70 * 1.6)

# ---- manufacturer-defined ranges: a port of isManufacturerDefined in lib/constants/dtc_ranges.dart ------------


def is_manufacturer_defined(code):
    c = code.strip().upper()
    if not CODE_RE.match(c):
        return False
    second = c[1]
    if c[0] == "P":
        if second == "1":
            return True
        return second == "3" and c[2] in "0123"
    return second in "12"


# ---- failure type from the END of the title, only when the title clearly states it ------------------------------
# Each rule: (regex on the cleaned title, id, English phrase from the shared failure-phrase table in GLOSSARY_HI.md).
# The title is cleaned first: quotes removed, a trailing "(Bank 1 ...)" group removed, whitespace collapsed.
FAILURE_RULES = [
    (re.compile(r"\bshort(ed)? to ground$", re.I), "short_to_ground", "short to ground"),
    (re.compile(r"\bshort(ed)? to (battery|b\+|power|supply)( supply)?$", re.I), "short_to_battery_supply",
     "short to battery supply"),
    (re.compile(r"(circuit\s*/\s*open|circuit\s+open|open\s+circuit)$", re.I), "open_circuit", "open circuit"),
    (re.compile(r"(circuit\s+low(\s+input)?|low\s+input)$", re.I), "voltage_below_threshold",
     "voltage below threshold"),
    (re.compile(r"(circuit\s+high(\s+input)?|high\s+input)$", re.I), "voltage_above_threshold",
     "voltage above threshold"),
    (re.compile(r"(range\s*/\s*performance|range\s+or\s+performance|circuit\s+performance|\bperformance)$", re.I),
     "performance_or_incorrect_operation", "performance or incorrect operation"),
    (re.compile(r"intermittent(\s*/\s*erratic)?$", re.I), "intermittent", "intermittent"),
    (re.compile(r"circuit\s+malfunction$", re.I), "circuit_fault", "circuit fault"),
    (re.compile(r"^lost\s+communication\b", re.I), "communication_lost", "communication lost"),
]


def clean_title_for_rules(title):
    t = title.replace('"', "").replace("“", "").replace("”", "")
    t = re.sub(r"\s*\([^()]*\)\s*$", "", t)  # trailing "(Bank 1 Sensor 2)" and the like
    return " ".join(t.split())


def failure_type(title):
    """-> (id, phrase) or (None, None). Only the ending (or, for lost communication, the start) of the title counts."""
    t = clean_title_for_rules(title)
    for rx, fid, phrase in FAILURE_RULES:
        if rx.search(t):
            return fid, phrase
    return None, None


# ---- small helpers -------------------------------------------------------------------------------------------


def read_jsonl(path):
    out = []
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except ValueError as e:
                    raise SystemExit(f"{path} line {i}: not JSON ({e})")
    return out


def code_sort_key(code):
    return (PREFIX_ORDER.index(code[0]), code[1:])
