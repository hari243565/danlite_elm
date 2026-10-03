#!/usr/bin/env python3
"""Self-test for validate_hi.py: the validator must accept the real Hindi rows and reject every deliberately broken one.

  python3 validator_hi_selftest.py

Each mutation takes a real, passing Hindi row, breaks exactly one thing, and names the rule that must catch it.
A test passes only if that rule fires. The last part checks that every rule H1-H12 is exercised by at least one test,
so a rule cannot silently stop being tested.
"""
import copy
import sys

import hi_common as C
import validate_hi as V

EN = {r["code"]: r for r in C.read_jsonl(C.EN_SEED)}
HI = {r["code"]: r for r in C.read_jsonl(C.HI_SEED)}
CTX = V.Context()
FAILED = []
RULES_HIT = set()
N = 0


def row(code):
    return copy.deepcopy(HI[code])


def rules_of(code, hi):
    return {r for r, _m in V.check_row(EN[code], hi, CTX)}


def expect(name, rule, code, mutate):
    """Break the Hindi row of `code` with `mutate(row)` and require `rule` to fire."""
    global N
    N += 1
    hi = row(code)
    mutate(hi)
    fired = rules_of(code, hi)
    RULES_HIT.add(rule)
    if rule in fired:
        print(f"PASS {name} -> {rule}")
    else:
        FAILED.append(name)
        print(f"FAIL {name}: expected {rule}, got {sorted(fired)}")


def expect_set(name, rule, hi_rows, expected_codes=None, en_rows=None):
    """Whole-set mutation (missing row, extra row, duplicate)."""
    global N
    N += 1
    en_rows = en_rows or list(EN.values())
    errs = V.check_all(en_rows, hi_rows, CTX, expected_codes)
    RULES_HIT.add(rule)
    if any(r == rule for _c, r, _m in errs):
        print(f"PASS {name} -> {rule}")
    else:
        FAILED.append(name)
        print(f"FAIL {name}: expected {rule}, got {sorted({r for _c, r, _m in errs})}")


def sub(field, old, new, count=1):
    def f(r):
        v = r[field]
        if isinstance(v, list):
            assert any(old in x for x in v), (field, old)
            for i, x in enumerate(v):
                if old in x:
                    v[i] = x.replace(old, new, count)
                    break
        else:
            assert old in v, (field, old, v)
            r[field] = v.replace(old, new, count)
    return f


def setfield(field, value):
    def f(r):
        r[field] = value
    return f


# --- baseline: the real rows are accepted --------------------------------------------------------------------------
N += 1
base = V.check_all(list(EN.values()), list(HI.values()), CTX)
if base:
    FAILED.append("baseline")
    print(f"FAIL baseline: the real Hindi set has {len(base)} errors, first: {base[0]}")
else:
    print(f"PASS baseline: all {len(HI)} real rows accepted")

# --- the ten the brief names, plus more ----------------------------------------------------------------------------
# 1 old spelling (the four forbidden ones)
expect("old spelling: अडैप्टर", "H6", "P0120", sub("technician_hints_hi", "जाँचें", "अडैप्टर जाँचें"))
expect("old spelling: एडाप्टर", "H6", "P0120", sub("technician_hints_hi", "जाँचें", "एडाप्टर जाँचें"))
expect("old spelling: फॉल्ट without nukta", "H6", "P0120", sub("technician_hints_hi", "जाँचें", "फॉल्ट जाँचें"))
expect("old spelling: दोष कोड", "H6", "P0120", sub("technician_hints_hi", "जाँचें", "दोष कोड जाँचें"))
expect("old spelling: anusvara in जांच कराएं", "H6", "P0195", sub("rider_advice_hi", "जाँच कराएँ", "जांच कराएं"))
# 2 English left in
expect("English left in a cause", "H4", "P0120", lambda r: r["likely_causes_hi"].__setitem__(0, "Worn throttle sensor"))
expect("English word inside a hint", "H4", "P0120", sub("technician_hints_hi", "वायरिंग", "wiring"))
# 3 missing placeholder / number
expect("number dropped (सिलेंडर 1)", "H5", "P0201", sub("meaning_hi", "सिलेंडर 1", "सिलेंडर"))
expect("number changed (सिलेंडर 1 to 2)", "H5", "P0201", sub("meaning_hi", "सिलेंडर 1", "सिलेंडर 2"))
expect("placeholder added", "H5", "P0120", sub("meaning_hi", "रीडिंग", "रीडिंग {x}"))
expect("Devanagari digit used", "H3", "P0201", sub("meaning_hi", "सिलेंडर 1", "सिलेंडर १"))
# 4 softened stop
expect("softened stop: STOP-TAIL replaced", "H7", "P0201",
       sub("rider_advice_hi", "आगे न चलाएँ", "सावधानी से चलाएँ"))
expect("softened stop: no stop wording left in a STOP entry", "H9", "P0201",
       lambda r: r.__setitem__("rider_advice_hi", r["rider_advice_hi"].split("। ")[0] + "। जल्द जाँच कराएँ।"))
expect("softened stop: P2111 every 'रुकें' and 'न चलाएँ' replaced", "H9", "P2111",
       lambda r: r.__setitem__("rider_advice_hi", r["rider_advice_hi"].replace("रुकें", "धीमे चलें").replace("आगे न चलाएँ", "धीरे चलाएँ")))
expect("do-not-ride dropped from the petrol sentence", "H7", "P0442", sub("rider_advice_hi", "बाइक न चलाएँ", "बाइक चलाएँ"))
expect("stop wording added to a MONITOR entry", "H9", "P0195",
       lambda r: r.__setitem__("rider_advice_hi", r["rider_advice_hi"] + " तुरंत रुकें।"))
# 5 broken combining marks
expect("broken combining mark: matra after a space", "H3", "P0120", sub("title_hi", "सर्किट", "सर्किट ा"))
expect("broken combining mark: double vowel sign", "H3", "P0120", sub("meaning_hi", "रीडिंग", "रीडिंगाे"))
expect("broken combining mark: halant at word end", "H3", "P0120", sub("meaning_hi", "रीडिंग", "रीडिंग्"))
expect("broken combining mark: word starts with a matra", "H3", "P0120", sub("can_ride_reason_hi", "आइडल", "ाइडल"))
expect("not NFC (precomposed फ़ U+095E)", "H3", "P0201", sub("title_hi", "फ़्यूल", "फ़्यूल"))
expect("replacement character", "H3", "P0120", sub("title_hi", "सेंसर", "सेंस�र"))
# 6 canonical sentence changed
expect("canonical STALL sentence changed", "H7", "P0120", sub("rider_advice_hi", "वर्कशॉप", "गैराज"))
expect("canonical ABS sentence changed", "H7", "U0121", sub("rider_advice_hi", "ब्रेक काम करते रहेंगे", "ब्रेक ठीक रहेंगे"))
expect("canonical NETWORK sentence changed", "H7", "U0001", sub("rider_advice_hi", "सुरक्षा फ़ीचर", "सेफ़्टी फ़ीचर"))
expect("twin clause changed", "H7", "P0201", sub("rider_advice_hi", "एक सिलेंडर पर चलती रह सकती है", "चलती रहेगी"))
expect("canonical petrol sentence changed", "H7", "P0442", sub("rider_advice_hi", "तेज़ गंध", "हल्की गंध"))
# 7 empty field
expect("empty meaning", "H2", "P0120", setfield("meaning_hi", ""))
expect("empty cause item", "H2", "P0120", lambda r: r["likely_causes_hi"].__setitem__(1, "  "))
expect("cause list too short", "H2", "P0120", lambda r: r["likely_causes_hi"].pop())
expect("empty can-ride reason", "H2", "P0120", setfield("can_ride_reason_hi", ""))
# 8 extra row / 9 missing row
extra = copy.deepcopy(HI["P0120"])
extra["code"] = "P9999"
extra["content_id"] = "generic:P9999:hi"
expect_set("extra row (no shipped English entry)", "H1", list(HI.values()) + [extra])
expect_set("missing row", "H1", [r for c, r in HI.items() if c != "P0300"])
expect_set("duplicate row", "H1", list(HI.values()) + [copy.deepcopy(HI["P0120"])])
# 10 over-long sentence
long_sentence = " ".join(["बाइक का कंप्यूटर (ECU) थ्रॉटल की रीडिंग भरोसेमंद नहीं ले पा रहा है"] * 4) + "।"
expect("over-long sentence (31+ words)", "H8", "P0120", setfield("meaning_hi", long_sentence))
expect("advice sentence merged (count differs)", "H8", "P0195",
       lambda r: r.__setitem__("rider_advice_hi", r["rider_advice_hi"].replace("। ", "; ")))
expect("meaning has no full stop", "H8", "P0120", lambda r: r.__setitem__("meaning_hi", r["meaning_hi"].rstrip("।")))
# rider-action meaning
expect("MONITOR entry with do-not-ride wording", "H9", "P0195",
       lambda r: r.__setitem__("rider_advice_hi", r["rider_advice_hi"] + " बाइक न चलाएँ।"))
expect("do-not-ride wording in a reason where the English only says no night rides", "H9", "P0562",
       sub("can_ride_reason_hi", "रात में सवारी न करें", "रात में न चलाएँ"))
expect("level changed", "H1", "P0201", setfield("rider_action_level", "MONITOR"))
# 10 glossary
expect("glossary term not used: सेंसर", "H10", "P0120", sub("title_hi", "सेंसर", "संवेदक"))
expect("glossary term not used: इंजेक्टर", "H10", "P0201", sub("title_hi", "इंजेक्टर", "नोज़ल"))
expect("failure phrase not used (ग्राउंड से शॉर्ट)", "H10", "P0122", sub("meaning_hi", "ग्राउंड से शॉर्ट", "ज़मीन से जुड़ना"))
expect("hedge dropped (अगर लगा हो)", "H10", "P0135", sub("likely_causes_hi", "(अगर लगा हो)", ""))
expect("hedge dropped (अगर होज़ से जुड़ा हो)", "H10", "P0105", sub("likely_causes_hi", "(अगर होज़ से जुड़ा हो)", ""))
# 11 length ratio
expect("length ratio too small", "H11", "P0120", setfield("meaning_hi", "ECU रीडिंग नहीं ले पा रहा।"))
expect("length ratio too large", "H11", "P0120", lambda r: r.__setitem__("likely_causes_hi", ["सेंसर " * 40, r["likely_causes_hi"][1], r["likely_causes_hi"][2]]))
# 12 importer rules
expect("hi_status the importer rejects (ai_translated_draft)", "H12", "P0120", setfield("hi_status", "ai_translated_draft"))
expect("wrong content_id", "H12", "P0120", setfield("content_id", "generic:P0120:en"))
expect("importer length cap (title over 112 characters)", "H12", "P0120", setfield("title_hi", "थ्रॉटल पोज़ीशन सेंसर " * 8))
expect("unexpected field", "H12", "P0120", setfield("title_en", "x"))
expect("needs_independent_review false", "H12", "P0120", setfield("needs_independent_review", False))
expect("can-ride not allowed for the level", "H12", "P0201", setfield("can_ride_to_workshop", "yes"))
# 4b Latin allowed list
expect("Latin token the English field does not have (ABS added)", "H4", "P0120", sub("title_hi", "A:", "A ABS:"))

# --- every rule is exercised ------------------------------------------------------------------------------------------
N += 1
want = {f"H{i}" for i in range(1, 13)}
if want - RULES_HIT:
    FAILED.append("coverage")
    print(f"FAIL coverage: no test for {sorted(want - RULES_HIT)}")
else:
    print("PASS coverage: every rule H1-H12 is exercised by at least one test")

print(f"\n{N - len(FAILED)}/{N} validator_hi tests passed")
sys.exit(1 if FAILED else 0)
