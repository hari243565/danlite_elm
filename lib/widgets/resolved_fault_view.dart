/// Danlite ELM — how a resolved fault is shown: the rider-action chip, the
/// guidance (meaning, likely causes, what to do, can-ride line, conditions),
/// the language note and the provenance line. Shared by the fault card and
/// the code lookup so both say exactly the same thing.
///
/// Thin: every decision was made by the resolver; this only lays it out.
/// Rows are built only when they have content — never an empty line.
library;

import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../knowledge/fault_resolver.dart';
import '../knowledge/kb_models.dart';

class FaultPalette {
  static const Color textMain = Color(0xFFEEF2F8);
  static const Color textMuted = Color(0xFF607080);
  static const Color red = Color(0xFFFF3D3D);
  static const Color amber = Color(0xFFFF8A00);
  static const Color yellow = Color(0xFFFFD23D);
  static const Color cyan = Color(0xFF00CAFF);
}

/// Card colour for a rider action. Never the only signal: the chip carries an
/// icon and a word.
Color riderActionColor(RiderAction a) => switch (a) {
      RiderAction.stop => FaultPalette.red,
      RiderAction.serviceSoon => FaultPalette.amber,
      RiderAction.monitor => FaultPalette.yellow,
      RiderAction.info => FaultPalette.cyan,
    };

IconData riderActionIcon(RiderAction a) => switch (a) {
      RiderAction.stop => Icons.front_hand_rounded,
      RiderAction.serviceSoon => Icons.build_rounded,
      RiderAction.monitor => Icons.visibility_rounded,
      RiderAction.info => Icons.info_outline_rounded,
    };

String riderActionKey(RiderAction a) => switch (a) {
      RiderAction.stop => 'riderActionStop',
      RiderAction.serviceSoon => 'riderActionServiceSoon',
      RiderAction.monitor => 'riderActionMonitor',
      RiderAction.info => 'riderActionInfo',
    };

/// `applies_when` key -> the note shown when the bike's matching detail is
/// unknown. Every key a shipped pack uses must be here, or its condition
/// would be dropped silently (a test checks the bundled packs).
const Map<String, String> kAppliesNoteKeys = {
  'cylinders_min': 'appliesCylindersMin2',
  'liquid_cooled': 'appliesLiquidCooled',
  'ride_by_wire': 'appliesRideByWire',
  'abs_fitted': 'appliesAbsFitted',
  'knock_sensor_fitted': 'appliesKnockSensor',
  'camshaft_sensor_fitted': 'appliesCamshaftSensor',
  'oil_temp_sensor_fitted': 'appliesOilTempSensor',
  'closed_throttle_switch_fitted': 'appliesClosedThrottleSwitch',
  'evap_fitted': 'appliesEvap',
  'secondary_air_fitted': 'appliesSecondaryAir',
  'cooling_fan_fitted': 'appliesCoolingFan',
  'oil_pressure_sensor_fitted': 'appliesOilPressureSensor',
  'ambient_temp_sensor_fitted': 'appliesAmbientTempSensor',
  'fuel_level_sensor_fitted': 'appliesFuelLevelSensor',
  'gear_position_sensor_fitted': 'appliesGearPositionSensor',
  'clutch_switch_fitted': 'appliesClutchSwitch',
  'downstream_o2_sensor_fitted': 'appliesDownstreamO2',
  'can_bus_fitted': 'appliesCanBus',
};

/// "Stop" / "Service soon" / "Monitor" / "Info" — icon and word.
class RiderActionChip extends StatelessWidget {
  const RiderActionChip(this.action, {super.key});
  final RiderAction action;

  @override
  Widget build(BuildContext context) {
    final c = riderActionColor(action);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(riderActionIcon(action), size: 13, color: c),
          const SizedBox(width: 4),
          Text(context.tr(riderActionKey(action)),
              style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// The chip for a name-only answer: grey, icon plus word, and none of the
/// rider-action colours. A bare standard name is not advice, and "Info" next
/// to a title that mentions fuel pressure, brakes or misfire can read as
/// "nothing to worry about".
class NameOnlyChip extends StatelessWidget {
  const NameOnlyChip({super.key});

  @override
  Widget build(BuildContext context) {
    const c = FaultPalette.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.label_outline_rounded, size: 13, color: c),
          const SizedBox(width: 4),
          Text(context.tr('riderActionNameOnly'),
              style: const TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// The one chip every screen draws for a resolved answer: the neutral "Name
/// only" chip for a bare name, the rider-action chip otherwise, nothing when
/// the answer has no rider action.
class FaultActionChip extends StatelessWidget {
  const FaultActionChip(this.r, {super.key});
  final ResolvedFault r;

  @override
  Widget build(BuildContext context) {
    if (r.isNameOnly) return const NameOnlyChip();
    final a = r.riderAction;
    return a == null ? const SizedBox.shrink() : RiderActionChip(a);
  }
}

/// The guidance below the title.
class ResolvedGuidance extends StatelessWidget {
  const ResolvedGuidance(this.r, {super.key, this.showHints = false});
  final ResolvedFault r;
  final bool showHints;

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 3),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: FaultPalette.textMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7)),
      );

  Widget _bullets(List<String> items, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final x in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $x',
                  style: TextStyle(color: color, fontSize: 12.5, height: 1.35)),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    // A name-only card shows its title once: the "Standard name: <title>."
    // line only repeats it. (The line stays in the data.)
    final title = r.title ?? '';
    final repeatsTitle = r.isNameOnly &&
        title.isNotEmpty &&
        (r.meaning ?? '').contains(title);
    final meaning = repeatsTitle ? '' : (r.meaning ?? '');
    final advice = r.riderAdvice ?? '';
    final reason = r.canRideReason ?? '';
    final conditions = [
      for (final k in (r.conditions ?? const <String, Object?>{}).keys)
        if (kAppliesNoteKeys.containsKey(k)) context.tr(kAppliesNoteKeys[k]!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (meaning.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(meaning,
                style: const TextStyle(
                    color: FaultPalette.textMain, fontSize: 13, height: 1.4)),
          ),
        for (final c in conditions)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(c,
                style: const TextStyle(
                    color: FaultPalette.amber,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35)),
          ),
        if (r.causes.isNotEmpty) ...[
          _label(context.tr('faultLikelyCauses')),
          _bullets(r.causes, FaultPalette.textMuted),
        ],
        if (advice.isNotEmpty) ...[
          _label(context.tr('faultWhatToDo')),
          Text(advice,
              style: const TextStyle(
                  color: FaultPalette.cyan, fontSize: 12.5, height: 1.4)),
        ],
        if (r.canRide != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                    r.canRide == CanRide.no
                        ? Icons.do_not_disturb_on_rounded
                        : Icons.two_wheeler_rounded,
                    size: 15,
                    color: r.canRide == CanRide.no ? FaultPalette.red : FaultPalette.textMain),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [
                      context.tr(switch (r.canRide!) {
                        CanRide.yes => 'canRideYes',
                        CanRide.withCare => 'canRideWithCare',
                        CanRide.no => 'canRideNo',
                      }),
                      if (reason.isNotEmpty) reason,
                    ].join(' — '),
                    style: const TextStyle(
                        color: FaultPalette.textMain,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        if (showHints && r.hints.isNotEmpty) ...[
          _label(context.tr('faultForMechanic')),
          _bullets(r.hints, FaultPalette.textMuted),
        ],
        ProvenanceLine(r),
      ],
    );
  }
}

/// The language note (when anything is not in the asked language) and the
/// plain verification label, plus "Draft…" when not yet reviewed.
class ProvenanceLine extends StatelessWidget {
  const ProvenanceLine(this.r, {super.key});
  final ResolvedFault r;

  @override
  Widget build(BuildContext context) {
    final note = !r.languageFallback
        ? null
        : context.tr(r.languageUsed != r.languageRequested
            ? 'faultShowingEnglish'
            : 'faultPartlyEnglish');
    final label = [
      context.tr(r.provenance.labelKey),
      if (r.draft) context.tr('provenanceDraft'),
    ].join('. ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.translate_rounded, size: 13, color: FaultPalette.textMuted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(note,
                      style: const TextStyle(
                          color: FaultPalette.textMuted, fontSize: 11, height: 1.35)),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.source_outlined, size: 13, color: FaultPalette.textMuted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: FaultPalette.textMuted,
                        fontSize: 10.5,
                        fontStyle: FontStyle.italic,
                        height: 1.4)),
              ),
            ],
          ),
        ),
        // Hindi from a machine-translated row: one short line under the draft
        // line. Never on English or on anything the app wrote itself.
        if (r.hindiMachine)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.translate_rounded, size: 13, color: FaultPalette.textMuted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(context.tr('faultHindiMachine'),
                      style: const TextStyle(
                          color: FaultPalette.textMuted,
                          fontSize: 10.5,
                          fontStyle: FontStyle.italic,
                          height: 1.4)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
