/// Danlite ELM — "Blink-code references": the small list that leads to the
/// manual look-up tables (Honda ABS, Royal Enfield older EFI).
///
/// Neither table reads anything from the bike. The list only orders them: a
/// rider whose active profile is a Royal Enfield sees that reference first;
/// everyone else sees Honda first, as it was before the second one existed. The
/// Yamaha FZ-16 FI meter-code reference is last for everyone except a Yamaha
/// profile, which sees it first.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_strings.dart';
import '../constants/chassis_dtc_dictionary.dart' show ChassisManufacturers;
import '../providers/vehicle_provider.dart';
import 'honda_blink_reference_screen.dart';
import 'royal_enfield_blink_reference_screen.dart';
import 'yamaha_fz16_meter_screen.dart';

enum BlinkReference { royalEnfield, honda, yamahaFz16 }

/// The references in display order for the active profile's [make].
List<BlinkReference> blinkReferenceOrder(String? make) =>
    ChassisManufacturers.resolveKey(make) == ChassisManufacturers.royalEnfield
        ? const [BlinkReference.royalEnfield, BlinkReference.honda]
        : const [BlinkReference.honda, BlinkReference.royalEnfield];

/// Every reference tile in display order: the two blink references in their
/// own order, with the Yamaha meter codes first on a Yamaha profile and last
/// otherwise.
List<BlinkReference> blinkReferenceTiles(String? make) {
  final blink = blinkReferenceOrder(make);
  return ChassisManufacturers.resolveKey(make) == ChassisManufacturers.yamaha
      ? [BlinkReference.yamahaFz16, ...blink]
      : [...blink, BlinkReference.yamahaFz16];
}

// Unified Telemetry Design System palette, matching dtc_screen._RC.
class _LC {
  static const Color bg = Color(0xFF07090E);
  static const Color surface = Color(0xFF0D1117);
  static const Color card = Color(0xFF131922);
  static const Color border = Color(0xFF1C2A3A);
  static const Color textMain = Color(0xFFEEF2F8);
  static const Color textMuted = Color(0xFF607080);
  static const Color neonCyan = Color(0xFF00CAFF);
}

class BlinkReferencesScreen extends StatelessWidget {
  const BlinkReferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final make = context.watch<VehicleProvider>().active?.make;
    return Scaffold(
      backgroundColor: _LC.bg,
      appBar: AppBar(
        backgroundColor: _LC.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: _LC.textMain),
        title: Text(context.tr('blinkRefsTitle'),
            style: const TextStyle(
                color: _LC.textMain, fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _LC.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          Text(context.tr('blinkRefsIntro'),
              style: const TextStyle(
                  color: _LC.textMuted, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 14),
          for (final ref in blinkReferenceTiles(make)) ...[
            _tile(context, ref),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, BlinkReference ref) {
    final (title, sub, builder) = switch (ref) {
      BlinkReference.royalEnfield => (
          context.tr('blinkRefsRoyal'),
          context.tr('blinkRefsRoyalSub'),
          (BuildContext _) => const RoyalEnfieldBlinkReferenceScreen(),
        ),
      BlinkReference.honda => (
          context.tr('blinkRefTitle'),
          context.tr('blinkRefsHondaSub'),
          (BuildContext _) => const HondaBlinkReferenceScreen(),
        ),
      BlinkReference.yamahaFz16 => (
          context.tr('blinkRefsYamaha'),
          context.tr('blinkRefsYamahaSub'),
          (BuildContext _) => const YamahaFz16MeterScreen(),
        ),
    };
    return GestureDetector(
      key: ValueKey('blink-ref-${ref.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: builder)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _LC.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _LC.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.menu_book_rounded, size: 22, color: _LC.neonCyan),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: _LC.textMain,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(sub,
                      style: const TextStyle(
                          color: _LC.textMuted, fontSize: 12, height: 1.4)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _LC.textMuted),
          ],
        ),
      ),
    );
  }
}
