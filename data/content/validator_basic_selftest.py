#!/usr/bin/env python3
"""Self-test for validate_basic.py: it must accept the real basic-tier rows and reject every deliberately broken one.

  py validator_basic_selftest.py

Each test takes a real, passing English/Hindi pair from the built pack, breaks exactly one thing and names the rule
that must fire. A test passes only if that rule fires. The last part checks that every rule is exercised by at least
one test, so a rule cannot silently stop being tested.
"""
import copy
import sys

import basic_common as B
import validate_basic as V

CTX = V.Context()
EN_ROWS = B.read_jsonl(B.EN_PACK)
HI_ROWS = B.read_jsonl(B.HI_PACK)
if not EN_ROWS or not HI_ROWS:
    raise SystemExit("build at least one batch first (py build_basic.py --next)")
EN = {r["code"]: r for r in EN_ROWS}
HI = {r["code"]: r for r in HI_ROWS}
BASE = next(c for c in EN if "O2" in EN[c]["title_en"] or "Sensor" in EN[c]["title_en"])
FAILED, RULES_HIT, N = [], set(), 0
ALL_RULES = {"E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8", "E9", "E10", "H1", "H2", "H3", "H4", "H5", "H6", "H7"}


def pair(code=BASE):
    return copy.deepcopy(EN[code]), copy.deepcopy(HI[code])


def fired(errs):
    return {r for _c, r, _m in errs}


def expect(name, rule, mutate_en=None, mutate_hi=None, code=BASE):
    """Break the pair with the given functions; the rule must appear among the problems found."""
    global N
    N += 1
    en, hi = pair(code)
    if mutate_en:
        mutate_en(en)
    if mutate_hi:
        mutate_hi(hi)
    errs = V.check_en(en, CTX) + V.check_hi(hi, en, CTX)
    RULES_HIT.add(rule)
    if rule in fired(errs):
        print(f"PASS {name} -> {rule}")
    else:
        FAILED.append(name)
        print(f"FAIL {name}: expected {rule}, got {sorted(fired(errs))}")


def expect_set(name, rule, en_rows, hi_rows, **kw):
    global N
    N += 1
    errs = V.check_all(en_rows, hi_rows, CTX, **kw)
    RULES_HIT.add(rule)
    if rule in fired(errs):
        print(f"PASS {name} -> {rule}")
    else:
        FAILED.append(name)
        print(f"FAIL {name}: expected {rule}, got {sorted(fired(errs))}")


def set_(d, key, value):
    def f(row):
        row[key] = value
    return f


def main():
    # ---- the good rows must pass ---------------------------------------------------------------------------
    en, hi = pair()
    errs = V.check_en(en, CTX) + V.check_hi(hi, en, CTX)
    if errs:
        print("FAIL a real pair is rejected:", errs)
        FAILED.append("real pair")
    else:
        print("PASS a real pair is accepted")
    whole = V.check_all(EN_ROWS, HI_ROWS, CTX)
    if whole:
        print("FAIL the whole built pack is rejected:", whole[:3])
        FAILED.append("whole pack")
    else:
        print(f"PASS the whole built pack ({len(EN_ROWS)} + {len(HI_ROWS)} rows) is accepted")

    t = EN[BASE]["title_en"]
    # ---- E2 shape ------------------------------------------------------------------------------------------
    expect("extra field in the English row", "E2", lambda e: e.update({"likely_causes_hi": []}))
    expect("missing field in the English row", "E2", lambda e: e.pop("confidence"))
    expect("content_id of another code", "E2", set_(0, "content_id", "generic:P0120:en"))
    expect("system does not match the prefix", "E2", set_(0, "system", "chassis"))
    # ---- E3 the agreed title -------------------------------------------------------------------------------
    expect("title that is not the agreed one", "E3", lambda e: e.update({"title_en": t + " B", "standard_title_en": t + " B",
                                                                          "meaning_en": f"Standard name: {t} B."}))
    disagree = next(c for c, r in CTX.agreement.items() if r["verdict"] == "DISAGREE" and c[0] == "P"
                    and not B.is_manufacturer_defined(c))
    expect("a code the two sources disagree on", "E3",
           lambda e: e.update({"code": disagree, "content_id": f"generic:{disagree}:en"}))
    missing = next(c for c, r in CTX.agreement.items() if r["verdict"] == "MISSING" and c[0] == "C")
    expect("a code missing from the second source", "E3",
           lambda e: e.update({"code": missing, "content_id": f"generic:{missing}:en", "system": "chassis"}))
    # ---- E4 which codes may be here ------------------------------------------------------------------------
    shipped = sorted(CTX.shipped)[0]
    expect("clash with a shipped entry", "E4", lambda e: e.update({"code": shipped, "content_id": f"generic:{shipped}:en"}))
    held = sorted(CTX.held)[0]
    expect("a held-out code", "E4", lambda e: e.update({"code": held, "content_id": f"generic:{held}:en"}))
    expect("a chassis wheel-speed code", "E4",
           lambda e: e.update({"code": "C0045", "content_id": "generic:C0045:en", "system": "chassis",
                               "title_en": "Left Rear Wheel Speed Sensor Circuit Malfunction",
                               "standard_title_en": "Left Rear Wheel Speed Sensor Circuit Malfunction",
                               "meaning_en": "Standard name: Left Rear Wheel Speed Sensor Circuit Malfunction."}))
    expect("a manufacturer-defined range", "E4",
           lambda e: e.update({"code": "P1234", "content_id": "generic:P1234:en"}))
    # ---- E5 fixed patterns ---------------------------------------------------------------------------------
    expect("text beyond the pattern in the meaning", "E5", set_(0, "meaning_en", f"Standard name: {t}. It is a sensor fault."))
    expect("altered advice", "E5", set_(0, "rider_advice_en", B.ADVICE_EN.replace("soon", "today")))
    expect("an invented cause", "E5", set_(0, "likely_causes_en", ["Faulty sensor", "Loose connector"]))
    expect("an invented hint", "E5", set_(0, "technician_hints_en", ["Check the connector"]))
    expect("a placeholder left in the meaning", "E5", set_(0, "meaning_en", "Standard name: {title}."))
    # ---- E6 safety claims ----------------------------------------------------------------------------------
    expect("a stop claim in the meaning", "E6", set_(0, "meaning_en", f"Standard name: {t}. Stop riding now."))
    expect("a safe-to-ride claim in the basis", "E6", set_(0, "rider_action_basis", "Draft: safe to ride"))
    expect("a danger word in a Hindi sentence", "E6", set_(0, "rider_action_basis_hi", "ड्राफ़्ट: खतरा"), None) \
        if False else expect("a danger word in the Hindi meaning", "E6", None,
                             lambda h: h.update({"meaning_hi": h["meaning_hi"].replace("।", " तुरंत रुकें।")}))
    # ---- E7 labels -----------------------------------------------------------------------------------------
    expect("level other than INFO", "E7", set_(0, "rider_action_level", "SERVICE_SOON"))
    expect("a can-ride claim", "E7", set_(0, "can_ride_to_workshop", "yes"))
    expect("confidence above low", "E7", set_(0, "confidence", "high"))
    expect("wrong verification label", "E7", set_(0, "verification", "ai_authored_from_standard_title"))
    expect("review flag switched off", "E7", set_(0, "needs_independent_review", False))
    expect("basis that does not say draft", "E7", set_(0, "rider_action_basis", "Standard name only"))
    # ---- E8 provenance -------------------------------------------------------------------------------------
    expect("wrong OBDex commit", "E8", lambda e: e["derived_from"].update({"repo_commit": "0" * 40}))
    expect("wrong failure type", "E8", lambda e: e["derived_from"].update({"failure_type": "short_to_ground"}))
    expect("wrong source hash", "E8", lambda e: e["derived_from"].update({"source_entry_sha256": "0" * 64}))
    # ---- E9 limits -----------------------------------------------------------------------------------------
    long_t = "Fuel " * 15 + "Sensor"
    expect("title over 70 characters", "E9", lambda e: e.update({"title_en": long_t, "standard_title_en": long_t,
                                                                  "meaning_en": f"Standard name: {long_t}."}))
    # ---- H1 .. H7 the Hindi row ----------------------------------------------------------------------------
    expect("Hindi status not machine", "H1", None, set_(0, "hi_status", "reviewed"))
    expect("Hindi level differs from the English", "H1", None, set_(0, "rider_action_level", "STOP"))
    expect("Hindi title that the vocabulary does not produce", "H2", None,
           lambda h: h.update({"title_hi": h["title_hi"] + " सेंसर", "meaning_hi": f"मानक नाम: {h['title_hi']} सेंसर।"}))
    expect("a Devanagari digit", "H3", None, lambda h: h.update({"title_hi": h["title_hi"] + " १"}))
    expect("a replacement character", "H3", None, lambda h: h.update({"meaning_hi": h["meaning_hi"].replace("।", "�।")}))
    expect("English left in the Hindi title", "H4", None,
           lambda h: h.update({"title_hi": h["title_hi"] + " Valve", "meaning_hi": f"मानक नाम: {h['title_hi']} Valve।"}))
    expect("a number that changed", "H5", None, lambda h: h.update({"title_hi": h["title_hi"] + " 7"}))
    expect("an old spelling (थ्रोटल)", "H6", None,
           lambda h: h.update({"title_hi": h["title_hi"] + " थ्रोटल", "meaning_hi": f"मानक नाम: {h['title_hi']} थ्रोटल।"}))
    expect("Hindi advice altered", "H7", None, set_(0, "rider_advice_hi", B.ADVICE_HI.replace("जल्द", "कल")))
    expect("a placeholder left in the Hindi meaning", "H7", None, set_(0, "meaning_hi", "मानक नाम: {title}।"))
    expect("Hindi meaning without the title", "H7", None, set_(0, "meaning_hi", "मानक नाम: कुछ और।"))
    # ---- whole-pack rules -----------------------------------------------------------------------------------
    dup = EN_ROWS[:3] + [copy.deepcopy(EN_ROWS[1])] + EN_ROWS[3:5]
    expect_set("duplicate content_id", "E1", dup, HI_ROWS)
    expect_set("rows out of order", "E1", [EN_ROWS[1], EN_ROWS[0]] + EN_ROWS[2:], HI_ROWS)
    expect_set("an English row without a Hindi row", "H1", EN_ROWS, HI_ROWS[1:])
    expect_set("a planned code missing from a complete pack", "E1", EN_ROWS, HI_ROWS, complete=True) \
        if len(EN_ROWS) < sum(1 for r in CTX.plan.values() if r["status"] == "include") else None
    expect_set("pack over 12 MB", "E10", EN_ROWS, HI_ROWS, en_bytes=b"x\n" * (B.PACK_LIMIT_BYTES // 2 + 1))
    expect_set("manifest with a wrong hash", "E10", EN_ROWS, HI_ROWS, en_bytes=b"{}\n" * len(EN_ROWS),
               hi_bytes=b"{}\n" * len(HI_ROWS),
               manifests={"en": {"entries_count": len(EN_ROWS), "content_sha256": "0" * 64, "review_state": "draft",
                                 "signature": None, "scope": "generic", "language": "en"}})
    # a fixed text edited in one place only
    orig = CTX.canon.get("BASIC-ADVICE")
    CTX.canon["BASIC-ADVICE"] = (orig[0], orig[1] + " x")
    expect_set("CANONICAL_HI.md differs from the code", "H7", EN_ROWS, HI_ROWS)
    CTX.canon["BASIC-ADVICE"] = orig

    missing_rules = ALL_RULES - RULES_HIT
    print(f"\n{N} broken-entry tests; rules exercised: {sorted(RULES_HIT)}")
    if missing_rules:
        print("rules never exercised:", sorted(missing_rules))
        FAILED.append("coverage")
    if FAILED:
        print(f"{len(FAILED)} FAILED: {FAILED}")
        sys.exit(1)
    print("all self-tests pass")


if __name__ == "__main__":
    main()
