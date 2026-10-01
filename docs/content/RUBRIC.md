# Rider action rubric (Step 2)

| Level | Use when | Rider advice must |
|---|---|---|
| STOP | Typically causes stalling, no start, sudden power loss, fuel leakage or fire risk, or loss of the ability to brake or steer normally | tell the rider to pull over safely and check before riding further |
| SERVICE_SOON | Can damage the engine or catalyst if ignored, or hurts drivability (misfire, O2 sensor, throttle, fuel trim) | say to get it checked soon and how to ride meanwhile |
| MONITOR | Minor, emissions-only or likely to clear | say it can wait for the next service |
| INFO | Reserved, test not completed, purely diagnostic | not use "pull over" |

`needs_mechanic_review` is true for every STOP, every chassis or braking code and every low-confidence entry. The validator enforces it.

## Interpretation of "touches braking or steering"

The brief lists "touches braking or steering" under STOP. This run reads it as: the fault can stop the rider from braking or steering normally (for example a stuck valve or lost brake pressure). A wheel speed sensor or ABS communication fault normally switches ABS off while the base brakes still work, so those codes are SERVICE_SOON with explicit "ABS may be off, brake early" advice and a mechanic review flag. If the owner wants every ABS code to be STOP, change the `abs_*`, `wheel_speed` and `lost_comm_abs` rows below to `{STOP}`; the validator will then enforce it.

## Mapping enforced by the validator (reason tag to allowed levels)

The tags come from `relevance_ranking.csv`. A code with several tags may use any level allowed by any of its tags.

| Tag | Allowed |
|---|---|
| injector, ignition_coil, crankshaft | STOP |
| fuel_pump, cam_crank_sync, engine_speed_input, oil_pressure, ecu_power_relay | STOP, SERVICE_SOON |
| camshaft, misfire, throttle, ride_by_wire, twist_grip_sensor, ect, cooling_fan, cooling_system, system_voltage, starter_relay, charging, sensor_reference_supply, control_module, immobiliser, starter_immobiliser, can_bus, lost_comm_engine, lost_comm_abs, lost_comm_immobiliser, abs_pump, wheel_speed, abs_module, abs_relay, abs_lamp | SERVICE_SOON, STOP |
| idle, map_baro, fuel_trim, knock | SERVICE_SOON |
| o2_sensor, o2_heater, vehicle_speed, brake_switch, neutral_gear, clutch_switch | SERVICE_SOON, MONITOR |
| iat, oil_temp, catalyst, overspeed, secondary_air, software, invalid_data, lost_comm_cluster | MONITOR, SERVICE_SOON |
| evap, fuel_level, ambient_temp | MONITOR |

## Flags

- `mil`: the warning lamp (MIL) normally lights for this code. Chassis and network codes are set false unless the engine unit raises them.
- `emissions_relevant`: the fault can affect exhaust emissions or fuel control.
- `limp_possible`: the ECU may substitute a default value or limit power.

## Confidence

- high: standard generic meaning, not bike-specific.
- medium: meaning is standard but the effect depends on the bike (speed source, neutral interlock, camshaft sensor, network units).
- low: thin or car-oriented source, or the generic code is ambiguous on a bike (serial link, chassis wheel codes).

## Wording rules

No absolute words (always, never, guaranteed, definitely, certainly, absolutely). No part numbers, pin numbers, voltages, resistances or cost figures. No brand names. Parts named in an entry must appear in the source entry's title, components or causes (a part found only in the source description gives a validator warning).
