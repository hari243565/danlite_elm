/// Danlite ELM — "Which adapter works best?"
///
/// A short, static page. It says only what the app already states elsewhere
/// (what an ELM327 adapter reads, why other modules need more, which links the
/// app uses today, that some bikes need a bike-specific cable or cannot be read
/// at all yet). No brand names, no prices, no links, no promise that any
/// adapter works: a rider reading it should know what to look for and what the
/// app cannot do, not be sold something.
library;

import 'package:flutter/material.dart';

import '../constants/app_strings.dart';

// Unified Telemetry Design System palette, matching dtc_screen._RC.
class _AC {
  static const Color bg = Color(0xFF07090E);
  static const Color surface = Color(0xFF0D1117);
  static const Color card = Color(0xFF131922);
  static const Color border = Color(0xFF1C2A3A);
  static const Color textMain = Color(0xFFEEF2F8);
  static const Color textMuted = Color(0xFF607080);
  static const Color neonCyan = Color(0xFF00CAFF);
}

class AdapterHelpScreen extends StatelessWidget {
  const AdapterHelpScreen({super.key});

  /// Heading key, body key and icon, in reading order.
  static const List<(String, String, IconData)> _points = [
    ('adapterHelpEngineTitle', 'adapterHelpEngineBody', Icons.settings_rounded),
    ('adapterHelpOtherTitle', 'adapterHelpOtherBody', Icons.disc_full_rounded),
    ('adapterHelpConnTitle', 'adapterHelpConnBody', Icons.bluetooth_rounded),
    ('adapterHelpCableTitle', 'adapterHelpCableBody', Icons.cable_rounded),
    ('adapterHelpOlderTitle', 'adapterHelpOlderBody', Icons.history_rounded),
    ('adapterHelpBlinkTitle', 'adapterHelpBlinkBody',
        Icons.lightbulb_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AC.bg,
      appBar: AppBar(
        backgroundColor: _AC.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: _AC.textMain),
        title: Text(context.tr('adapterHelpTitle'),
            style: const TextStyle(
                color: _AC.textMain, fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _AC.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          Text(context.tr('adapterHelpIntro'),
              style: const TextStyle(
                  color: _AC.textMuted, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 14),
          for (final (title, body, icon) in _points) ...[
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: _AC.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _AC.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: _AC.neonCyan),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr(title),
                            style: const TextStyle(
                                color: _AC.textMain,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 5),
                        Text(context.tr(body),
                            style: const TextStyle(
                                color: _AC.textMuted,
                                fontSize: 12.5,
                                height: 1.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
