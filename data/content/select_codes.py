#!/usr/bin/env python3
"""Step 1: relevance selection and ranking of OBDex generic codes for small
Indian fuel-injected motorcycles and scooters.

Usage: python3 select_codes.py /path/to/obdex data/content/relevance_ranking.csv

The rules are the ones written in docs/content/SELECTION_RULES.md. Code
ranges are listed by hand (not guessed from titles) and every candidate is
checked against an exclusion pattern on the OBDex title.
"""
import csv
import glob
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
    ("throttle", "P0638", "P0638", 3), ("ride_by_wire", "P2100", "P2112", 3),
    ("ride_by_wire", "P2118", "P2119", 3), ("throttle", "P2135", "P2135", 3),
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
    ("ect", "P0115", "P0119", 3), ("ect", "P0125", "P0126", 3),
    ("ect", "P0128", "P0128", 3), ("ect", "P0217", "P0217", 3),
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
    ("injector", "P0200", "P0202", 3), ("injector", "P0261", "P0266", 3),
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
    ("ecu_power_relay", "P0685", "P0688", 3),
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
    order = list(ANCHORS)
    order += [c for c in TIER2 if c not in order]
    tag_order = {}
    for i, (tag, *_rest) in enumerate(R):
        tag_order.setdefault(tag, i)
    rest = [c for c in tags if c not in order]
    rest.sort(key=lambda c: (tier[c], min(tag_order[t] for t in tags[c]), c))
    order += rest
    anchors = set(ANCHORS)
    with open(out_csv, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["code", "rank", "tier", "reason_tags", "anchor", "honda_family", "title_obdex"])
        for i, c in enumerate(order, 1):
            t = 1 if c in anchors else (2 if c in TIER2 else tier[c])
            w.writerow([c, i, t, ";".join(tags[c]), "yes" if c in anchors else "no",
                        "yes" if HONDA_FAMILIES & set(tags[c]) else "no",
                        d[c]["title"]["en"]])
    print(f"selected {len(order)} codes of {len(d)}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
