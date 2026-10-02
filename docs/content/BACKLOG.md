# Content backlog

Ideas that are not decided and not part of any current step.

- Possible schema v3 field `action_level_twin`: a second action level for two-cylinder bikes, so that a cylinder 1
  ignition or injector fault can be STOP on a single and SERVICE_SOON on a twin without relying on one clause of
  text (raised by the independent review of V4, problem 5; V5 group G6 only added a wording clause).
- New `applies_when` keys the independent review of V4 asked for and the V5 fix log rejected for now (the schema does not
  have them): `evap_vent_valve_fitted`, `evap_pressure_sensor_fitted` (P0448, P0451, P0454), `immobiliser_fitted`
  (P0633, U0167), `neutral_switch_fitted` (P0852), a key for sensor supplies B and C (P0651 to P0653, P0697 to P0699),
  `alternator_ecu_controlled` (P0620, P0621, P0625, P0626, P2500, P2501, held out in `held_entries_v5.jsonl`), and a key
  for a body control unit (U0140).
- A schema field that marks `standard_title_en` as "not for riders" (it names a wheel position on chassis entries).
