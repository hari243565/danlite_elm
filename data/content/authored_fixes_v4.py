"""Fixes to the 140 existing entries (pilot + batch 1) for owner decisions D1 to D8 and the independent review of
batch 1 (docs/content/REVIEW_REPORT_BATCH1_20261001.md). Applied on top of authored_pilot.py and authored_batch1.py
by authored_all.py, so the original authored text stays visible in git history.

Every change is logged row by row in fix_log_v4_20261002.csv (written by authored_all.py --log).
Keys are the authored field names (title, meaning, causes, level, basis, advice, hints, flags, confidence,
ride, applies, review). A "why" key is documentation only.
"""
from canon import *  # noqa: F401,F403

FIXES = {}


def fix(code, why, **fields):
    assert code not in FIXES, code
    FIXES[code] = dict(fields, why=why)


# ======================= D2: downgrades from STOP to SERVICE_SOON ===========================================
ECU_REASON = "ride only if the engine runs normally; go straight to a workshop"
fix("P0604", "D2: ECU keeps running in reduced power mode (the source says so); TWO-CASE advice; RAM acronym removed",
    title="ECU internal fault: working memory error",
    meaning="The bike's computer (ECU) found an error in its own working memory, so it may control the engine poorly.",
    level=SS, basis="ECU may switch to reduced power mode", advice=TWO_CASE, ride=(CARE, ECU_REASON))
fix("P0605", "D2: same as P0604; ROM acronym removed; hint to go back to the workshop that programmed the ECU",
    title="ECU internal fault: stored program error",
    meaning="The bike's computer (ECU) found an error in its own stored program, so it may control the engine poorly.",
    level=SS, basis="ECU may switch to reduced power mode", advice=TWO_CASE, ride=(CARE, ECU_REASON),
    hints=["Check the ECU supply and ground, then the stored program",
           "Ask the workshop that last programmed the ECU"])
fix("P0606", "D2: same as P0604",
    meaning="The bike's computer (ECU) found a fault in its own processor, so it may control the engine poorly.",
    level=SS, basis="ECU may switch to reduced power mode", advice=TWO_CASE, ride=(CARE, ECU_REASON))
CYL2_SS_RIDE = "reduced power and vibration; ride gently, short trip"
fix("P0202", "D2: cylinder 2 only exists on a twin, which keeps running on cylinder 1; downgraded",
    level=SS, confidence=MD, basis="one cylinder has no fuel; power is reduced",
    advice="One cylinder may get no fuel, so the engine may shake and lose power. Ride gently and keep the trip "
           "short; stop if it runs very rough or loses power badly.",
    ride=(CARE, CYL2_SS_RIDE))
fix("P0264", "D2: as P0202", level=SS, confidence=MD, basis="one cylinder has no fuel; power is reduced",
    advice="One cylinder may get no fuel, so the engine may shake and lose power. Ride gently and keep the trip "
           "short; stop if it runs very rough or loses power badly.",
    ride=(CARE, CYL2_SS_RIDE))
fix("P0265", "D2: as P0202", level=SS, confidence=MD, basis="one cylinder has no fuel; power is reduced",
    advice="One cylinder may get no fuel, so the engine may shake and lose power. Ride gently and keep the trip "
           "short; stop if it runs very rough or loses power badly.",
    ride=(CARE, CYL2_SS_RIDE))
fix("P0352", "D2: as P0202 (spark loss on cylinder 2)", level=SS, confidence=MD,
    basis="spark loss on one cylinder; power is reduced",
    advice="The spark on one cylinder may be weak or missing, so the engine may shake and lose power. Ride gently "
           "and keep the trip short; stop if it runs very rough or loses power badly.",
    ride=(CARE, CYL2_SS_RIDE))
fix("P0232", "D2: the OBDex description says the pump stays powered when it should be off (no stall); downgraded, "
    "reason in rider_action_basis; open circuit removed",
    title="Fuel pump power circuit: voltage above threshold",
    meaning="The fuel pump power circuit reads too high for the bike's computer (ECU), often from a short to battery "
            "supply that keeps the pump powered.",
    causes=["Fuel pump relay stuck closed (if fitted)", "Wire short to battery supply",
            "Corroded connector with poor contact"],
    level=SS, confidence=L, basis="pump may stay powered when it should be off",
    advice="The fuel pump may stay powered when it should be off; get it checked soon. " + STALL,
    ride=(CARE, "ride only if the engine runs normally; go to a workshop soon"),
    hints=["Check whether the pump runs with the ignition off",
           "Check the pump relay (if fitted) and the supply wiring for a short to battery supply"])

# ======================= STOP wording ===========================================================================
INJ_RIDE = "that cylinder may get no fuel and the engine may stop; arrange transport"
for _c in ("P0200", "P0201", "P0261", "P0262"):
    fix(_c, "review: reason stated for singles and twins; 'cut out' removed",
        basis="engine may stop suddenly",
        advice="The engine may misfire, lose power or stop. " + STOP_TAIL, ride=(NO, INJ_RIDE))
for _c in ("P0350", "P0351"):
    fix(_c, "review: 'run on one cylinder' removed (meaningless on a single)",
        basis="spark loss may stop the engine",
        advice="The engine may misfire, lose power or stop. " + STOP_TAIL,
        ride=(NO, "spark loss can stop the engine; arrange transport"))
fix("P0335", "review: 'stall, cut out or refuse to start' replaced; meaning shortened to 25 words",
    meaning="The bike's computer (ECU) found a fault in the crankshaft position sensor circuit, so it may not know "
            "engine position.",
    advice="The engine may stop or not start. " + STOP_TAIL)
fix("P0336", "review: 'refuse to start' removed",
    advice="The engine may stop, run roughly or not start. " + STOP_TAIL)
fix("P0337", "review: 'refuse to start' removed", advice="The engine may stop or not start. " + STOP_TAIL)
fix("P0338", "review: 'refuse to start' removed", advice="The engine may stop or not start. " + STOP_TAIL)
fix("P0339", "review: 'cut out' and 'drops out' removed",
    meaning="The crankshaft sensor signal is lost at times, so the bike's computer (ECU) may lose engine speed and "
            "position for a moment.",
    basis="engine may stop suddenly", advice="The engine may stop suddenly without warning. " + STOP_TAIL,
    ride=(NO, "engine may stop at any time; arrange transport"))
fix("P0230", "review: STOP-TAIL instead of the restart variant",
    advice="The engine may be hard to start or may stop without warning. " + STOP_TAIL)
fix("P0231", "review: rider title 'fuel pump power circuit'; confidence low; STOP-TAIL",
    title="Fuel pump power circuit: voltage below threshold", confidence=L,
    meaning="The fuel pump circuit reads too low for the bike's computer (ECU), so the pump may not run properly.",
    advice="The engine may be hard to start or may stop without warning. " + STOP_TAIL)
fix("P0233", "review: rider title; confidence low; 'cut out' and 'drops out' removed; STOP-TAIL",
    title="Fuel pump power circuit: intermittent circuit fault", confidence=L,
    meaning="The fuel pump circuit loses contact at times, so the pump may stop for a moment and the engine may "
            "stop suddenly.",
    basis="pump may stop; sudden power loss",
    advice="The engine may stop suddenly without warning. " + STOP_TAIL,
    ride=(NO, "pump may stop at any time; arrange transport"))
fix("P0627", "review: STOP-TAIL instead of the restart variant",
    advice="The engine may be hard to start or may stop without warning. " + STOP_TAIL)
fix("P0628", "review: STOP-TAIL instead of the restart variant",
    advice="The engine may be hard to start or may stop without warning. " + STOP_TAIL)
fix("P0629", "review: 'cut out' removed; STOP kept (D2), review true",
    basis="pump control lost; engine may stop",
    advice="The pump may run at the wrong times or stop, and the engine may stop suddenly. " + STOP_TAIL)
fix("P0217", "review: OVERHEAT sentence and radiator hedge; low oil and lean mixture added as a technician hint; "
    "'wreck' replaced",
    basis="overheating can destroy the engine", ride=(NO, "overheating can destroy the engine; arrange transport"),
    advice=OVERHEAT + " If your bike has a radiator, do not open the cap while it is hot.",
    hints=["Check the engine oil level and the coolant level (liquid-cooled bikes)",
           "Look for a lean mixture and for blocked airflow around the engine"])
fix("P0685", "review: keep STOP; plain wording", basis="ECU may lose power; engine may stop",
    advice="The engine may stop or not start without warning. " + STOP_TAIL)
fix("P0686", "review: keep STOP; plain wording", basis="ECU may lose power; engine may stop",
    advice="The engine may stop or not start without warning. " + STOP_TAIL)

# ======================= D3: idle family =========================================================================
IDLE_RIDE = "idle may be unsteady; avoid heavy traffic and long trips"
fix("P0505", "D3: contradictory idle sentence replaced; plain words", basis="idle speed may be too high or too low",
    advice=IDLE, ride=(CARE, IDLE_RIDE))
fix("P0506", "D3 (FAIL): contradictory idle sentence replaced", advice=IDLE, ride=(CARE, IDLE_RIDE))
fix("P0507", "D3 and review: throttle-not-closing hazard gets its own stop sentence; review true",
    basis="idle too high; bike may not slow down", review=True,
    advice="If the throttle does not snap fully shut when you let go, do not ride; have it checked first. " + STALL,
    ride=(CARE, "ride gently and avoid heavy traffic; no long trips"))
fix("P0508", "D3: contradictory idle sentence replaced", advice=IDLE, ride=(CARE, IDLE_RIDE))
fix("P0509", "D3: contradictory idle sentence replaced", advice=IDLE, ride=(CARE, IDLE_RIDE))
fix("P050A", "D3: contradictory idle sentence replaced", advice=IDLE, ride=(CARE, "cold idle may be unsteady; avoid heavy traffic"))
fix("P050D", "D3: contradictory idle sentence replaced", advice=IDLE, ride=(CARE, "cold idle may be rough; avoid heavy traffic"))
fix("P0510", "D3 (FAIL): contradictory idle sentence replaced; applies_when closed throttle switch", advice=IDLE,
    applies=CLOSED_THROTTLE, ride=(CARE, IDLE_RIDE))
fix("P0511", "D3: contradictory idle sentence replaced", advice=IDLE, ride=(CARE, IDLE_RIDE))
fix("P0518", "D3: contradictory idle sentence replaced; 'drops out' removed",
    meaning="The idle air control circuit loses contact at times, so the bike's computer (ECU) sometimes loses "
            "control of the idle speed.",
    advice=IDLE, ride=(CARE, "idle may be unsteady at times; avoid heavy traffic"))
fix("P0519", "D3 (FAIL): contradictory idle sentence replaced; 'hunt' removed",
    meaning="The idle speed does not follow the bike's computer (ECU), so it may go up and down or stay too high or "
            "too low.",
    basis="idle may be unsteady, too high or too low", advice=IDLE, ride=(CARE, IDLE_RIDE))

# ======================= D4: STALL, NETWORK, ABS ================================================================
MAP_ADVICE = "The engine may run rough, lose power or be hard to start; get it checked soon. " + STALL
for _c in ("P0105", "P0106", "P0107"):
    fix(_c, "review/D4: MAP is the load input, so it carries the canonical STALL sentence", advice=MAP_ADVICE)
fix("P0108", "review/D4: STALL added; 'run rich' removed",
    advice="The engine may use too much fuel, lose power or be hard to start; get it checked soon. " + STALL)
fix("P0109", "review/D4: STALL added; 'drops out or jumps' removed",
    meaning="The intake pressure reading is lost or changes suddenly at times, so the bike's computer (ECU) "
            "sometimes misjudges engine load.",
    advice="The engine may run rough or lose power at times; get it checked soon. " + STALL)
CAM_ADVICE = "The engine may be hard to start, run rough or lose power; get it checked soon. " + STALL
for _c in ("P0340", "P0341", "P0342", "P0343"):
    fix(_c, "D4: canonical STALL sentence (the camshaft variant is retired); applies_when camshaft sensor",
        advice=CAM_ADVICE, applies=CAM)
fix("P0344", "D4: canonical STALL sentence; applies_when camshaft sensor; 'drops out' removed",
    meaning="The camshaft sensor signal is lost at times, so the bike's computer (ECU) may sometimes time fuel and "
            "spark wrongly.",
    advice="The engine may hesitate, run rough or be hard to start at times; get it checked soon. " + STALL,
    applies=CAM)
fix("P0561", "review: BATTERY-HOT stop trigger and STALL; plain meaning",
    meaning="The electrical system voltage keeps going up and down, so lights may flicker and the bike's computer "
            "(ECU) cannot rely on it.",
    basis="unstable voltage can harm electrics",
    advice=BATTERY_HOT + " " + STALL, ride=(CARE, "short trip to a workshop; stop if the battery gets hot or swollen"))
fix("P0600", "D4: canonical STALL sentence instead of the 'stalls or loses power more than once' variant",
    advice="Warning lamps or other functions may not work correctly; get it checked soon. " + STALL)
fix("U0100", "D4: TWO-CASE as one canonical sentence", advice=TWO_CASE)
for _c in ("U0001", "U0002", "U0003", "U0004", "U0005", "U0006", "U0007", "U0008"):
    fix(_c, "D4: canonical NETWORK sentence (ABS may be affected); review true",
        advice=NETWORK, review=True, ride=(CARE, ECU_REASON))
fix("U0121", "review: applies_when abs_fitted (R20)", applies=ABS_FITTED)
fix("C0035", "review: applies_when abs_fitted (R20)", applies=ABS_FITTED)

# ======================= D5, D7: ECU power relay, immobiliser, starter ==========================================
fix("P068B", "D5: battery-drain statement restored (the OBDex description says the relay keeps the ECU powered and "
    "drains the battery); TWO-CASE removed",
    basis="ECU stays powered after switch-off; battery may drain",
    advice="The battery may go flat if the ECU stays powered after switch-off. Have it checked soon.",
    ride=(CARE, "battery may go flat overnight; go to a workshop soon"),
    hints=["Check whether the ECU power relay (if fitted) releases after key-off",
           "Measure the battery drain with the ignition off"])
fix("P068A", "review: TWO-CASE does not fit a relay that releases early; plain effect (learned settings)",
    basis="ECU may lose its learned settings",
    advice="The ECU may lose its learned settings, so idle may be slightly different for a while. Have it checked soon.",
    ride=(CARE, "usually rideable; go to a workshop soon"))
for _c in ("P0688", "P0689", "P0690"):
    fix(_c, "review: empty first sentence removed; TWO-CASE only", advice=TWO_CASE)
for _c in ("P0601", "P0607"):
    fix(_c, "review: empty first sentence removed; TWO-CASE only", advice=TWO_CASE)
fix("P0602", "review: empty first sentence removed; TWO-CASE only", advice=TWO_CASE)
fix("P0603", "review: plain title and advice (before what?)",
    title="ECU internal fault: learned settings lost",
    advice="The bike may idle or run slightly differently until the ECU relearns. If the battery is weak, charge or "
           "replace it; if the code returns, have it checked soon.")
fix("P0633", "D7: no-start claim made conditional",
    ride=(CARE, "if it starts, go straight to a workshop; do not switch off on the way"))
fix("P0512", "D7: no-start claim made conditional",
    ride=(CARE, "if it starts, go straight to a workshop; do not switch off on the way"))
fix("P0513", "D7: no-start claim made conditional",
    ride=(CARE, "if it starts, go straight to a workshop; do not switch off on the way"))
fix("P0615", "review: 'it keeps running' made clear",
    advice="If the starter does not turn the engine, do not keep trying; get it checked soon. If the starter keeps "
           "turning after the engine starts, switch off at once.",
    ride=(CARE, "if it starts, go straight to a workshop; the starter may fail next time"))
fix("P0616", "review: reason matches the advice",
    ride=(CARE, "if it starts, go straight to a workshop; the starter may fail next time"))
fix("P0617", "review: reason matches the advice (switch off at once)",
    ride=(CARE, "ride only if the starter stops after the engine starts"))

# ======================= Hindi-readiness (D6) and plain words =====================================================
fix("P0120", "D6: 'jump-free' removed from a technician hint",
    hints=["Check the sensor connector for water, corrosion and bent pins",
           "Wiggle the harness while watching the throttle reading on the scan tool",
           "Look for a smooth reading from closed to fully open"])
fix("P0124", "D6: 'drops out or jumps' removed",
    hints=["Wiggle the harness and connector while watching the throttle reading on the scan tool",
           "Look for sudden changes in the reading while moving the throttle slowly"],
    meaning="The throttle position reading is lost or changes suddenly at times, so the bike's computer (ECU) "
            "sometimes misreads the throttle.",
    basis="throttle reading lost at times")
fix("P0114", "D6: 'drops out or jumps' removed",
    meaning="The intake air temperature reading is lost or changes suddenly at times, so the bike's computer (ECU) "
            "sometimes corrects the fuelling wrongly.")
fix("P0119", "D6: 'drops out or jumps' removed",
    meaning="The engine temperature reading is lost or changes suddenly at times, so the bike's computer (ECU) "
            "sometimes misjudges how hot the engine is.")
fix("P0199", "D6: 'drops out or jumps' removed; applies_when oil temperature sensor",
    meaning="The oil temperature reading is lost or changes suddenly at times, so the bike's computer (ECU) "
            "sometimes gets a wrong reading.",
    basis="temperature reading lost at times",
    advice="The bike should ride normally, but the oil temperature reading may be lost. Ask a mechanic to check the "
           "sensor at the next service.", applies=OILT)
for _c in ("P0195", "P0196", "P0197", "P0198"):
    fix(_c, "R20: applies_when oil temperature sensor", applies=OILT)
fix("P0503", "D6: 'jumps about' removed; meaning shortened",
    meaning="The vehicle speed signal is lost, changes suddenly or reads too high, often from a loose connector or a "
            "short to battery supply.",
    advice="The speedometer may read wrongly, and other speed-based functions may be affected. Get it checked soon and "
           "do not rely on the speedometer.")
fix("P0117", "D6: 'stumbles' removed",
    basis="hard cold start; runs unevenly until warm",
    advice="The bike may be hard to start when cold and run unevenly until warm. Get it checked soon; if it runs very "
           "hot, stop and let it cool.")
fix("P0118", "D6: 'run rich' removed",
    basis="extra fuel use; cooling may not switch on",
    advice="The bike may use more fuel and smoke, and cooling may not switch on when needed. Get it checked soon; if "
           "the engine runs very hot, stop and let it cool.")
fix("P0130", "D6: 'run richer' and 'falls back' removed",
    advice="The bike may use more fuel and fail an emission check. It usually rides normally, but get it checked soon "
           "to protect the emission system.",
    ride=(YES, "fuel control changes to a fixed setting; usually rideable"))
fix("P0170", "review: plain meaning, no idioms",
    meaning="The bike's computer (ECU) is making large fuel corrections, but the engine still gets too much or too "
            "little fuel.",
    basis="wrong fuel mixture", ride=(CARE, "mixture is wrong; short, gentle ride only"))
fix("P0171", "D6: 'run hot' removed; meaning shortened",
    meaning="The bike's computer (ECU) is adding extra fuel to keep the mixture right, so the engine is getting too "
            "much air or too little fuel.",
    advice="The engine may hesitate, run rough or lose power, and a lean mixture can overheat the engine. Get it "
           "checked soon and avoid hard or long rides until it is fixed.",
    ride=(CARE, "lean mixture can overheat the engine; short, gentle ride only"))
fix("P0112", "D6: meaning shortened to 25 words",
    meaning="The intake air temperature signal is too low for the bike's computer (ECU), so the air looks hotter than "
            "it is.")
fix("P0128", "D6: 'points to' removed",
    meaning="The engine is not warming up to its normal temperature, which may mean the thermostat is stuck open.")
fix("P0562", "D6: 'points to' removed",
    meaning="The bike's computer (ECU) sees the electrical system voltage lower than expected, so the battery may be "
            "weak or charging may be poor.")
fix("P0563", "D6: 'points to' removed (D1 sentences unchanged)",
    meaning="The bike's computer (ECU) sees the electrical system voltage higher than expected, so the charging "
            "system may be overcharging.")
for _c in ("P0300", "P0301", "P0302"):
    fix(_c, "review/D6: 'reduce load' replaced",
        advice="Expect rough running, jerking or loss of power. Ride gently, avoid hard acceleration and get it "
               "checked soon; stop if it runs very rough, backfires or loses power badly.",
        ride=(CARE, "ride gently, avoid hard acceleration; keep the trip short"))
fix("P0263", "review/D6: 'fair share', 'reduce load' and 'out of balance' replaced",
    title="Cylinder 1 is not working as well as the other cylinder",
    meaning="The bike's computer (ECU) found that cylinder 1 is not working as well as the other cylinder, so the "
            "engine may run rough.",
    advice="Expect rough running, jerking or loss of power. Ride gently, avoid hard acceleration and get it checked "
           "soon; stop if it runs very rough, backfires or loses power badly.",
    ride=(CARE, "ride gently, avoid hard acceleration; keep the trip short"))
fix("P0266", "review/D6: as P0263",
    title="Cylinder 2 is not working as well as the other cylinder",
    meaning="The bike's computer (ECU) found that cylinder 2 is not working as well as the other cylinder, so the "
            "engine may run rough.",
    advice="Expect rough running, jerking or loss of power. Ride gently, avoid hard acceleration and get it checked "
           "soon; stop if it runs very rough, backfires or loses power badly.",
    ride=(CARE, "ride gently, avoid hard acceleration; keep the trip short"))
KNOCK_ADVICE = ("Avoid hard acceleration and poor-quality petrol; get it checked soon. If you hear heavy knocking or "
                "pinging, stop and let the engine cool.")
for _c in ("P0324", "P0325", "P0327", "P0328"):
    fix(_c, "review: 'low-grade fuel' replaced; applies_when knock sensor", advice=KNOCK_ADVICE, applies=KNOCK)
fix("P0326", "review/D6: meaning shortened and made plain; applies_when knock sensor",
    meaning="The knock sensor signal does not match what the bike's computer (ECU) expects, so it cannot tell normal "
            "engine noise from harmful knocking.",
    advice=KNOCK_ADVICE, applies=KNOCK)
fix("P0329", "review/D6: 'drops out or jumps' removed; applies_when knock sensor",
    meaning="The knock sensor signal is lost or changes suddenly at times, so the bike's computer (ECU) may "
            "sometimes misjudge engine knock.",
    basis="knock protection unreliable", advice=KNOCK_ADVICE, applies=KNOCK)
fix("P0850", "review/D6: meaning split into plain words (one sentence)",
    meaning="The bike's computer (ECU) may not know whether the bike is in neutral, because the neutral switch signal "
            "is faulty.")
fix("P0125", "review: the circumstance is not in the source; moved to a technician hint; meaning shortened to 25 words",
    meaning="The engine is warming up too slowly, or its temperature reading is too low, so the bike's computer (ECU) "
            "cannot begin fine fuel control.",
    causes=["Faulty engine temperature sensor", "Thermostat stuck open (liquid-cooled bikes)"],
    hints=["Compare the scan tool reading with the real engine temperature, cold and warm",
           "Very short rides or very cold weather can also cause this code"])
fix("P0126", "review: the circumstance is not in the source; moved to a technician hint",
    causes=["Faulty engine temperature sensor", "Thermostat stuck open (liquid-cooled bikes)"],
    hints=["Compare the scan tool reading with the real engine temperature, cold and warm",
           "Very short rides or very cold weather can also cause this code"])
