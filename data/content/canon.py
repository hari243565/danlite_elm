"""Canonical sentences (owner decisions D3 and D4, 2026-10-02) and shared constants for the authored modules.

One form for each standard sentence, word for word, everywhere it applies. validate_seed.py keeps its own copy of
these strings on purpose: a typo here is then caught by the validator instead of being repeated everywhere.
"""

S, SS, M, I = "STOP", "SERVICE_SOON", "MONITOR", "INFO"
H, MD, L = "high", "medium", "low"
NO, CARE, YES = "no", "with_care", "yes"

STALL = "If it stalls more than once or will not restart, do not keep riding; have it taken to a workshop."
PETROL = "If you smell petrol strongly near the engine or tank, or see fuel dripping, stop and do not ride."
ABS_FACT = "Your normal brakes still work, but ABS is off, so a wheel can lock in hard braking."
NETWORK = ("Some electronic units on the bike cannot talk to each other, so warning lights or safety features may "
           "not work. If ABS is affected, your normal brakes still work, but ABS is off, so a wheel can lock in "
           "hard braking.")
IDLE_FIRST = "If it stalls at stops or will not hold idle, ride gently, avoid heavy traffic and have it checked soon."
IDLE = IDLE_FIRST + " " + STALL
BATTERY = ("If the battery is hot, swollen or smells of rotten eggs, or the lights are very bright or bulbs keep "
           "blowing, stop, switch off and do not ride on.")
BATTERY_HOT = "If the battery is hot or swollen, stop, switch off and do not ride on."
TWO_CASE = ("If the engine runs normally, have it checked soon; if it stalls, loses power or will not start, "
            "do not keep riding.")
STOP_TAIL = "Pull over safely, switch off and do not keep riding; have the bike taken to a workshop."
OVERHEAT = "Pull over safely, switch off and let the engine cool; do not keep riding."
ABS_TAIL = "Ride gently, brake early and get it checked soon."
ABS_TAIL_WET = "Ride gently, brake early, avoid wet roads and get it checked soon."

TWO_CYL = {"cylinders_min": 2}
LIQUID = {"liquid_cooled": True}
ABS_FITTED = {"abs_fitted": True}
KNOCK = {"knock_sensor_fitted": True}
CAM = {"camshaft_sensor_fitted": True}
OILT = {"oil_temp_sensor_fitted": True}
CLOSED_THROTTLE = {"closed_throttle_switch_fitted": True}
RBW = {"ride_by_wire": True}
EVAP = {"evap_fitted": True}
SECAIR = {"secondary_air_fitted": True}
FAN = {"cooling_fan_fitted": True}
OILP = {"oil_pressure_sensor_fitted": True}
AMBIENT = {"ambient_temp_sensor_fitted": True}
FUELLEVEL = {"fuel_level_sensor_fitted": True}
GEARPOS = {"gear_position_sensor_fitted": True}
CLUTCH = {"clutch_switch_fitted": True}
DOWNSTREAM = {"downstream_o2_sensor_fitted": True}


def both(*dicts):
    """Merge applies_when dictionaries."""
    out = {}
    for d in dicts:
        out.update(d)
    return out
