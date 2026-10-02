#!/usr/bin/env python3
"""Writes fix_log_v5_20261002.csv: one row for every CONCERN row of review_flags_v4_20261002.csv (the independent
review of V4) with the author's decision (owner decision G8): APPLIED or REJECTED, and a one-line reason.
The text changes themselves are in authored_fixes_v5.py and are listed field by field in fix_changes_v5_20261002.csv."""
import csv
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
A, R = "APPLIED", "REJECTED"
WHEEL_HELD = {"C0035", "C0037", "C0038", "C003A", "C003B", "C003C", "C003D", "C003E", "C003F"}
CAN = {"U0001", "U0002", "U0003", "U0004", "U0005", "U0006", "U0007", "U0008", "U0009", "U0010", "U0073", "U0074", "U0075",
       "U0076", "U0077", "U0140", "U0146"}
TWIN = {"P0201", "P0261", "P0262", "P0351", "P2300", "P2301", "P2302"}
G2 = {"P0325", "P0327", "P0328", "P0351", "P0352", "P0505"}
ALT = {"P0620", "P0621", "P0625", "P0626", "P2500", "P2501"}
HOT = {"P0115", "P0116", "P0117", "P0118", "P0119", "P0480", "P0483", "P0484", "P0485", "P0691", "P0692", "P2181"}


def decide(code, n, reason):
    low = reason.lower()
    if code in WHEEL_HELD and n == 12 or code in WHEEL_HELD and n == 1 and code == "C0035":
        if "standard_title_en" in low and code == "C0035" and n == 12:
            return R, "standard_title_en is locked to the source title by the validator; the entry is held out (G3) and a schema field 'not for riders' is a backlog item"
        return A, "entry held out of the shipped seed (G3) until the owner's assistant settles the chassis edition and the position rule; text left as it is"
    if code == "C003F":
        return A, "unsupported 'most bikes do not measure' clause removed and plain wording used; entry also held out (G3)"
    if code in GEAR_HELD:
        return A, "gear position text reduced to 'the signal is unreliable' (starting effect dropped) in all six P0914 to P0919 entries; entries held out (G3)"
    if n == 4 and code in TWIN:
        return A, "twin clause added to the cylinder 1 text, level unchanged (G6); schema field action_level_twin put on the backlog"
    if n == 4 and code in ("P2100", "P2102", "P2103"):
        return A, "now STOP and in stop_table.csv (G4, owner decision)"
    if n == 4 and code == "P0522":
        return A, "needs_independent_review true and the advice now names noisy, hot or low oil as reasons to stop"
    if n == 1 and code in G2 or code in G2 and "verified a title" in low:
        if code == "P0326":
            return R, "no verified title was given for P0326 (the two sources agree on it); the owner's G2 list names six codes, so it is unchanged"
        return A, "verified public title stored in title_overrides.csv and in standard_title_en with title_basis override (G2)"
    if code == "P0326":
        return R, "no verified title was given for P0326 (the two sources agree on it); the owner's G2 list names six codes, so it is unchanged"
    if n == 3 and code.startswith("P05") and "idle" in low or "two fixed sentences overlap" in low:
        return A, "idle entries now use the owner's pair of sentences (G5); the reviewer's suggested wording was replaced by the owner's"
    if n == 3 and code == "P2111" or code == "P2111":
        return A, "owner's slow-down advice added (G4); confidence set to medium because rule Q4 forbids high confidence on braking text"
    if code == "P0217":
        return R, "adding liquid_cooled would hide a STOP overheating code on air- and oil-cooled bikes, which can also overheat; the text is already conditional on a radiator"
    if code in ("P0232",) and n == 7:
        return R, "'the battery may go flat' is not in the source and the owner has not agreed; no safety gain, so the sentence stays as it is"
    if code in ("P0231", "P0232", "P0233"):
        return A, "title and meaning say 'fuel pump circuit (secondary)' as in the standard title"
    if code in ("P0448", "P0451", "P0454"):
        return R, "needs new applies_when keys (evap_vent_valve_fitted, evap_pressure_sensor_fitted) that the schema does not have; put on the backlog"
    if code in ALT and n == 11:
        return R, "needs a new key (alternator_ecu_controlled) that the schema does not have; the six entries are held out (G3) until it exists"
    if code in ("P0633", "P0852", "U0167") and n == 11:
        return R, "needs a new key (immobiliser_fitted or neutral_switch_fitted) that the schema does not have; put on the backlog"
    if code in ("P0651", "P0652", "P0653", "P0697", "P0698", "P0699"):
        return R, "needs a new key for sensor supplies B and C that the schema does not have; confidence left as it is, no evidence to lower it"
    if code == "U0140" and n == 2:
        return R, "needs a new key for a body control unit; confidence is already low and can_bus_fitted is now set"
    if code in CAN and n == 11:
        return A, "applies_when {can_bus_fitted: true} added to all 17 CAN entries and rule R20 now requires it for the can_bus tag"
    if code in CAN and n == 7:
        return A, "'CAN bus (the bike's data network)' at first use (sentence kept to 25 words or fewer)"
    if code in CAN and n == 10:
        return A, "'A faulty unit that disturbs the bus' in all eight entries that had the idiom; idiom added to the validator list"
    if code in ("U0075", "U0076", "U0077") and n == 6:
        return A, "titles read 'communication lost (bus off)' like U0073 and U0074"
    if code in HOT and n in (3, 7):
        return A, "replaced by the sentence about a temperature warning, steam or hot coolant in all 11 entries; removed from P0117"
    if code == "P0117":
        return A, "overheating sentence removed from P0117 (the engine only looks hotter); P0118 keeps it"
    if code in ("P0520", "P0521", "P0524") and n == 5:
        return A, "'the workshop's oil pressure test' in all five oil pressure entries (P0520 to P0524)"
    if code == "P0524" and n == 2:
        return A, "third hint added about the sensor and wiring after the oil level and pressure test; level stays STOP"
    if code in ("P0224", "P0602") and n == 10:
        return A, "'work wrongly' wording; same fix for the other entries with 'misbehave' (P0124, P0600, P0601, P0607, P0634); idiom added to the validator"
    if code == "P0617":
        return A, "'starter may keep turning after the engine starts'; 'run on' added to the idiom list"
    if code == "P033F":
        return A, "'Worn or slipped timing chain (rare)'; 'jumped' added to the idiom list"
    if code in ("P0196", "P2196", "P2A00"):
        return A, "'adjust' instead of 'fine-tune' (also P0130 and P2195); idiom added to the validator"
    if code == "P0460":
        return A, "'sensor' instead of 'sender' (also P0464); 'sender' added to the validator list"
    if code == "P0322":
        return A, "'Failed pickup'"
    if code == "P0321":
        return A, "meaning says the signal does not match what the ECU expects; no 'in range' and no 'plausibility check'"
    if code == "P0445" and n == 2:
        return A, "'Shorted purge valve coil or wire'"
    if code == "P0445" and n == 6:
        return A, "'short circuit' added to the shared phrase list in validate_seed.py"
    if code in ("P0054",):
        return A, "'resistance out of range' added to the shared phrase list and used in the titles of P0053 and P0054"
    if code == "P00D1":
        return A, "meaning now says the heater does not warm the sensor as expected, as in the standard title"
    if code == "P2097":
        return A, "'Contaminated or aged downstream oxygen sensor'"
    if code == "P2109":
        return A, "'the closed position of the throttle'"
    if code == "P2118":
        return A, "'often from a binding throttle or a worn motor'"
    if code in ("P2122", "P2123", "P2127", "P2128", "P2138"):
        return A, "'throttle (twist grip) position sensor D/E' in title, meaning, cause and hint; confidence was already low"
    if code == "P2148":
        return A, "BATTERY-HOT sentence added to the advice (it replaces the STALL sentence, as the advice may have only two sentences)"
    if code == "P2504":
        return A, "battery sentence split into two sentences of 19 and 13 words (G7)"
    if code == "P068A":
        return A, "reason now 'ride with care; go to a workshop soon', which fits with_care"
    if code == "P0504":
        return A, "reason now 'ride only if the brake light works; ride gently'"
    if code in ("P0633", "P0512", "P0513"):
        return A, "reason now 'avoid switching off unless unsafe' (P0512 and P0513 changed the same way)"
    if code == "P0625":
        return A, "brushes cause removed (entry is held out under G3)"
    raise SystemExit(f"no decision for {code} check {n}: {reason[:80]}")


GEAR_HELD = {"P0914", "P0915", "P0916", "P0917", "P0918", "P0919"}

rows = [r for r in csv.DictReader(open(os.path.join(HERE, "review_flags_v4_20261002.csv"), encoding="utf-8"))
        if r["verdict"] == "CONCERN"]
with open(os.path.join(HERE, "fix_log_v5_20261002.csv"), "w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    w.writerow(["code", "check", "action", "reason"])
    tally = {A: 0, R: 0}
    for r in rows:
        n = int(re.match(r"\d+", r["check"]).group(0))
        act, why = decide(r["code"], n, r["reason"])
        tally[act] += 1
        w.writerow([r["code"], r["check"], act, why])
print(len(rows), "concern rows:", tally)
