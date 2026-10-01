#!/usr/bin/env python3
"""Step 1: relevance selection and ranking of OBDex generic codes for small
Indian fuel-injected motorcycles and scooters.

Usage: python3 select_codes.py /path/to/obdex data/content/relevance_ranking.csv

Version 3 (2026-10-01): extends ecu_power_relay to P0690, applies
title_overrides.csv, orders tier 3 by how likely a small bike is to raise the
code (ride-by-wire last), runs a duplicate-title scan and writes
title_suspects.csv. Codes whose title cannot be reconciled are kept in the
ranking with write_ok = no and are never written.

The rules are the ones written in docs/content/SELECTION_RULES.md. Code
ranges are listed by hand (not guessed from titles) and every candidate is
checked against an exclusion pattern on the OBDex title.
"""
import csv
import glob
import os
import re
import sys

import yaml

LOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

# ---- anchors (rank 1..9), in this order -----------------------------------
ANCHORS = ["P0120", "P0105", "P0195", "P0130", "P0135",
           "P0201", "P0351", "P0230", "P0335"]

# ---- tier 2: common core circuits, spread over families (rank 10..40) -----
TIER2 = ["P0110", "P0115", "P0202", "P0352", "P0300", "P0301", "P0302",
         "P0171", "P0172", "P0420", "P0122", "P0123", "P0107", "P0108",
         "P0112", "P0113", "P0117", "P0118", "P0131", "P0132", "P0500",
         "P0562", "P0563", "P0850", "P0600", "P0340", "P0505", "U0100",
         "U0121", "U0155", "C0035"]

# ---- candidate ranges: (tag, first, last, tier) ---------------------------
# tier 3 = core, tier 4 = extended / less likely on a small bike
R = [
    # throttle, idle, ride-by-wire
    ("throttle", "P0120", "P0124", 3), ("throttle", "P0220", "P0224", 4),
    ("ride_by_wire", "P0638", "P0638", 3), ("ride_by_wire", "P2100", "P2112", 3),
    ("ride_by_wire", "P2118", "P2119", 3), ("ride_by_wire", "P2135", "P2135", 3),
    ("twist_grip_sensor", "P2122", "P2123", 4), ("twist_grip_sensor", "P2127", "P2128", 4),
    ("twist_grip_sensor", "P2138", "P2138", 4),
    ("idle", "P0505", "P0511", 3), ("idle", "P0518", "P0519", 3),
    ("starter_immobiliser", "P0512", "P0513", 3),
    # intake pressure / temperature
    ("map_baro", "P0105", "P0109", 3), ("map_baro", "P0068", "P0069", 4),
    ("map_baro", "P2226", "P2230", 4),
    ("iat", "P0110", "P0114", 3), ("iat", "P0127", "P0127", 4),
    ("ambient_temp", "P0070", "P0074", 4),
    # engine / oil temperature, cooling fan, oil pressure
    ("ect", "P0115", "P0119", 3), ("ect_warmup", "P0125", "P0126", 3),
    ("ect_warmup", "P0128", "P0128", 3), ("ect", "P0217", "P0217", 3),
    ("overspeed", "P0219", "P0219", 4), ("cooling_fan", "P0480", "P0480", 3),
    ("cooling_fan", "P0483", "P0485", 4), ("cooling_fan", "P0691", "P0692", 3),
    ("cooling_system", "P2181", "P2181", 4),
    ("oil_temp", "P0195", "P0199", 3), ("oil_pressure", "P0520", "P0524", 3),
    # O2 sensors, heaters, fuel trim, catalyst (bank 1 only)
    ("o2_sensor", "P0130", "P0134", 3), ("o2_heater", "P0135", "P0135", 3),
    ("o2_sensor", "P0136", "P0140", 4), ("o2_heater", "P0141", "P0141", 4),
    ("o2_sensor", "P013A", "P013B", 4), ("o2_sensor", "P013E", "P013F", 4),
    ("o2_heater", "P0030", "P0032", 3), ("o2_heater", "P0036", "P0038", 4),
    ("o2_heater", "P0053", "P0054", 4), ("o2_heater", "P00D1", "P00D2", 4),
    ("o2_sensor", "P00D5", "P00D5", 4), ("o2_sensor", "P014C", "P014D", 4),
    ("o2_sensor", "P015A", "P015B", 4),
    ("fuel_trim", "P0170", "P0172", 3), ("fuel_trim", "P2096", "P2097", 4),
    ("fuel_trim", "P2177", "P2178", 4), ("fuel_trim", "P2187", "P2188", 4),
    ("o2_sensor", "P2195", "P2196", 3), ("o2_sensor", "P2270", "P2271", 4),
    ("o2_sensor", "P2A00", "P2A01", 4),
    ("catalyst", "P0420", "P0421", 3),
    # injectors (cylinders 1 and 2), fuel pump, fuel level
    ("injector", "P0200", "P0202", 3), ("injector", "P0261", "P0262", 3),
    ("injector_balance", "P0263", "P0263", 3), ("injector", "P0264", "P0265", 3),
    ("injector_balance", "P0266", "P0266", 3),
    ("injector", "P2146", "P2148", 4),
    ("fuel_pump", "P0230", "P0233", 3), ("fuel_pump", "P0627", "P0629", 3),
    ("fuel_level", "P0460", "P0464", 4),
    # misfire
    ("misfire", "P0300", "P0302", 3), ("misfire", "P0316", "P0316", 4),
    # crank / cam / ignition / knock
    ("crankshaft", "P0335", "P0339", 3), ("camshaft", "P0340", "P0344", 3),
    ("cam_crank_sync", "P0016", "P0016", 4), ("cam_crank_sync", "P033F", "P033F", 4),
    ("engine_speed_input", "P0320", "P0323", 4),
    ("ignition_coil", "P0350", "P0352", 3), ("ignition_coil", "P2300", "P2305", 4),
    ("knock", "P0324", "P0329", 3),
    # evaporative, secondary air
    ("evap", "P0440", "P0449", 3), ("evap", "P0450", "P0457", 4),
    ("evap", "P0496", "P0499", 4),
    ("secondary_air", "P0410", "P0414", 3), ("secondary_air", "P0418", "P0418", 4),
    ("secondary_air", "P0491", "P0491", 4),
    # vehicle speed, gear / neutral, clutch, brake switch
    ("vehicle_speed", "P0500", "P0503", 3), ("brake_switch", "P0504", "P0504", 4),
    ("neutral_gear", "P0850", "P0852", 3), ("neutral_gear", "P0914", "P0919", 4),
    ("clutch_switch", "P0704", "P0704", 4),
    # electrical system, control module
    ("system_voltage", "P0560", "P0563", 3), ("starter_relay", "P0615", "P0617", 3),
    ("charging", "P0620", "P0621", 4), ("charging", "P0625", "P0626", 4),
    ("charging", "P2500", "P2504", 4),
    ("ecu_power_relay", "P0685", "P0690", 3),
    ("sensor_reference_supply", "P0641", "P0643", 3),
    ("sensor_reference_supply", "P0651", "P0653", 4),
    ("sensor_reference_supply", "P0697", "P0699", 4),
    ("control_module", "P0600", "P0607", 3), ("control_module", "P0608", "P0610", 4),
    ("control_module", "P060A", "P060E", 4), ("control_module", "P062F", "P0630", 4),
    ("immobiliser", "P0633", "P0633", 3), ("control_module", "P0634", "P0634", 4),
    ("control_module", "P2610", "P2610", 4),
    # network
    ("can_bus", "U0001", "U0010", 3), ("can_bus", "U0073", "U0077", 4),
    ("lost_comm_engine", "U0100", "U0100", 3),
    ("lost_comm_abs", "U0121", "U0121", 3),
    ("lost_comm_cluster", "U0155", "U0155", 3), ("lost_comm_cluster", "U0140", "U0140", 4),
    ("lost_comm_cluster", "U0146", "U0146", 4),
    ("lost_comm_immobiliser", "U0167", "U0168", 4),
    ("software", "U0300", "U0301", 4), ("software", "U0327", "U0327", 4),
    ("invalid_data", "U0401", "U0401", 4), ("invalid_data", "U0415", "U0415", 4),
    ("invalid_data", "U0421", "U0421", 4), ("invalid_data", "U0408", "U0408", 4),
    # chassis: ABS / wheel speed (conservative; every one needs mechanic review)
    ("abs_pump", "C0020", "C0025", 4), ("abs_pump", "C0110", "C0112", 4),
    ("wheel_speed", "C0030", "C0036", 4), ("wheel_speed", "C0037", "C0038", 4),
    ("wheel_speed", "C003A", "C003F", 4), ("wheel_speed", "C0040", "C0046", 4),
    ("wheel_speed", "C0050", "C0056", 4), ("wheel_speed", "C0060", "C0066", 4),
    ("wheel_speed", "C0080", "C0081", 4), ("wheel_speed", "C0234", "C0235", 4),
    ("wheel_speed", "C0238", "C0238", 4), ("wheel_speed", "C0245", "C0245", 4),
    ("abs_module", "C004F", "C004F", 4), ("abs_module", "C0099", "C0099", 4),
    ("abs_module", "C0246", "C0246", 4), ("abs_module", "C0220", "C0220", 4),
    ("abs_relay", "C0121", "C0121", 4), ("abs_relay", "C0225", "C0225", 4),
    ("abs_lamp", "C0241", "C0242", 4),
]
# tier-3 chassis codes: the plain "circuit malfunction" wheel speed codes
TIER3_EXTRA = {"C0040", "C0045", "C0050", "C0099"}

# Codes inside the ranges above that are still out of scope (second throttle
# actuator, cold-start strategy codes, brake assist, second barometric sensor,
# brake pedal feedback). Kept explicit so the reason is reviewable.
DROP = {"P210A", "P210B", "P210C", "P210D", "P210E", "P210F", "P050B", "P050C",
        "P050E", "P050F", "P222A", "P222B", "P222C", "P222D", "P222E", "P222F",
        "C0024"}

# Titles that put a code out of scope (bank 2, cylinders 3+, boost, diesel ...)
EXCLUDE_TITLE = re.compile(
    r"bank ?2|cylinder (#)?([3-9]|1[0-9])\b|turbo|supercharg|diesel|glow|hybrid|"
    r"\bHV\b|transmission|torque|sensor 3|a/c|air condition|cruise|power steering|"
    r"\bEGR\b|exhaust gas recirc|particulate|NOx|reductant|bank ?1/bank ?2|"
    r"group [b-h]\b|transfer case|4wd|all wheel|airbag|SRS|seat ?belt",
    re.I,
)

# Reason tags that count as "Honda PGM-FI blink-table sensor families"
HONDA_FAMILIES = {"map_baro", "ect", "throttle", "iat", "injector"}


# Order of reason tags inside a tier: more likely on a small bike first,
# ride-by-wire and car-style chassis variants last.
TAG_PRIORITY = [
    "throttle", "map_baro", "iat", "ect", "ect_warmup", "oil_temp", "o2_sensor", "o2_heater", "fuel_trim",
    "injector", "injector_balance", "fuel_pump", "misfire", "crankshaft", "camshaft", "ignition_coil", "knock",
    "vehicle_speed", "neutral_gear", "idle", "system_voltage", "starter_relay",
    "ecu_power_relay", "sensor_reference_supply", "control_module", "immobiliser",
    "starter_immobiliser", "can_bus", "lost_comm_engine", "lost_comm_abs", "lost_comm_cluster",
    "lost_comm_immobiliser", "cooling_fan", "cooling_system", "oil_pressure", "evap",
    "secondary_air", "catalyst", "software", "invalid_data", "charging", "cam_crank_sync",
    "engine_speed_input", "overspeed", "fuel_level", "ambient_temp", "brake_switch",
    "clutch_switch", "twist_grip_sensor", "ride_by_wire", "abs_pump", "wheel_speed",
    "abs_module", "abs_relay", "abs_lamp",
]

# Titles checked by hand against the neighbouring codes (2026-10-01). These are
# NOT overridden: the standard title is uncertain, so no entry is written.
MANUAL_SUSPECTS = {
    "P0134": "Title mixes 'No Activity' with 'Slow Response'; P0133 is already slow response and the standard meaning of P0134 is no activity detected. Check before writing.",
    "P0140": "Same 'No Activity / Slow Response' mix as P0134 (sensor 2).",
    "P2230": "Same wording as P2228 (Barometric Pressure Circuit Low); the standard pattern expects intermittent or erratic here.",
    "U0168": "Same wording as U0167 (immobilizer) with only the spelling changed; the standard U0168 is the vehicle security control module.",
    "C0037": "Wheel speed titles C0037 to C003F do not follow the C0031 to C0066 pattern (no failure type, 'Supply', 'Tone Wheel' for C003C); the wheel and the failure type cannot be reconciled.",
    "C0038": "See C0037.", "C003A": "See C0037.", "C003B": "See C0037.", "C003C": "See C0037.",
    "C003D": "See C0037.", "C003E": "See C0037.", "C003F": "See C0037.",
    "P033F": "Not a clear standard title; cannot be reconciled with P0335 to P0339.",
    "C0030": "Wheel speed circuit titles C0030 to C0036 mix 'Range/Performance', 'Low', 'High', 'Signal Erratic' and 'No Signal' in a pattern that does not match C0040 to C0066; the wheel and failure type cannot be reconciled with the neighbouring codes.",
    "C0031": "See C0030.", "C0032": "See C0030.", "C0033": "See C0030.", "C0034": "See C0030.",
    "C0036": "See C0030.",
}
# Checked and confirmed facts (owner-supplied 2026-10-01): not suspects.
CONFIRMED = {
    "P0685": "ECM/PCM Power Relay Control Circuit/Open (confirmed standard title)",
    "U0073": "Control Module Communication Bus A Off (confirmed)",
    "U0074": "Control Module Communication Bus B Off (confirmed)",
}

HERE = os.path.dirname(os.path.abspath(__file__))


def load_overrides():
    path = os.path.join(HERE, "title_overrides.csv")
    return {r["code"]: r for r in csv.DictReader(open(path, encoding="utf-8"))}


def norm_title(t):
    """Title normalised for duplicate detection. Keeps +/- symbols and letters."""
    t = t.lower()
    t = re.sub(r"[\"'`/,()\u2014]+|(?<=\w)-(?=\w)", " ", t)
    t = t.replace("immobilizer", "immobiliser").replace("ecm pcm", "ecm").replace("ecm or pcm", "ecm")
    t = re.sub(r"\b(sensor|circuit|the|system)\b", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def scan_titles(d, titles, selected):
    """Return {code: (problem, evidence)} for selected codes whose title duplicates
    one of the 5 codes before or after it in the source (same family), after
    normalisation. 'titles' maps code -> the title in force (override applied)."""
    out = {}
    codes = sorted(d)
    idx = {c: i for i, c in enumerate(codes)}
    for c in selected:
        i = idx[c]
        mine = norm_title(titles[c])
        for j in range(max(0, i - 5), min(len(codes), i + 6)):
            o = codes[j]
            if o == c or o[:2] != c[:2]:
                continue
            if norm_title(titles.get(o, d[o]["title"]["en"])) == mine:
                out[c] = ("duplicate title", f"same title as {o}: {titles.get(o, d[o]['title']['en'])}")
                break
    return out


def load(obdex_dir):
    d = {}
    for f in sorted(glob.glob(f"{obdex_dir}/data/generic/*.yaml")):
        for e in yaml.load(open(f, encoding="utf-8"), Loader=LOADER):
            d[e["code"]] = e
    return d


def in_range(code, a, b):
    return len(code) == 5 and code[0] == a[0] and a <= code <= b


def main(obdex_dir, out_csv):
    d = load(obdex_dir)
    ov = load_overrides()
    tags, tier = {}, {}
    for tag, a, b, t in R:
        for c in sorted(d):
            if in_range(c, a, b) and c not in DROP and not EXCLUDE_TITLE.search(d[c]["title"]["en"]):
                tags.setdefault(c, [])
                if tag not in tags[c]:
                    tags[c].append(tag)
                tier[c] = min(tier.get(c, 9), t)
    for c in TIER3_EXTRA:
        if c in tier:
            tier[c] = 3
    for c in ANCHORS + TIER2:
        assert c in tags, f"anchor/tier2 code not selected: {c}"
    for c in ov:
        assert c in d, f"override for a code that is not in OBDex: {c}"
    order = list(ANCHORS)
    order += [c for c in TIER2 if c not in order]
    prio = {t: i for i, t in enumerate(TAG_PRIORITY)}
    missing = {t for c in tags for t in tags[c]} - set(prio)
    assert not missing, f"tags without priority: {missing}"
    rest = [c for c in tags if c not in order]
    rest.sort(key=lambda c: (tier[c], min(prio[t] for t in tags[c]), c))
    order += rest
    # titles in force: override first, then OBDex
    titles = {c: ov[c]["verified_title"] if c in ov else d[c]["title"]["en"] for c in d}
    dup = scan_titles(d, titles, list(order))
    suspects = []  # (code, obdex_title, title_in_force, problem, action)
    for c in order:
        if c in ov:
            suspects.append((c, d[c]["title"]["en"], titles[c], "OBDex title wrong (owner-supplied check)",
                             "override applied"))
        if c in MANUAL_SUSPECTS:
            suspects.append((c, d[c]["title"]["en"], titles[c], MANUAL_SUSPECTS[c], "do not write"))
        elif c in dup:
            suspects.append((c, d[c]["title"]["en"], titles[c], dup[c][0] + ": " + dup[c][1], "do not write"))
    blocked = {s[0] for s in suspects if s[4] == "do not write"}
    anchors = set(ANCHORS)
    with open(out_csv, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["code", "rank", "tier", "reason_tags", "anchor", "honda_family", "title_obdex",
                    "title_standard", "title_status", "write_ok"])
        for i, c in enumerate(order, 1):
            t = 1 if c in anchors else (2 if c in TIER2 else tier[c])
            status = "override" if c in ov else ("suspect" if c in blocked else
                                                 ("confirmed" if c in CONFIRMED else "obdex"))
            w.writerow([c, i, t, ";".join(tags[c]), "yes" if c in anchors else "no",
                        "yes" if HONDA_FAMILIES & set(tags[c]) else "no",
                        d[c]["title"]["en"], titles[c], status, "no" if c in blocked else "yes"])
    with open(os.path.join(os.path.dirname(os.path.abspath(out_csv)), "title_suspects.csv"), "w",
              newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["code", "obdex_title", "title_in_force", "problem", "action"])
        w.writerows(suspects)
    print(f"selected {len(order)} codes of {len(d)}; {len(blocked)} not writable (suspect title); "
          f"{len(ov)} overrides applied")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
