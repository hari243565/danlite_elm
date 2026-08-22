import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../constants/app_colors.dart';
import '../services/app_version_service.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('About OBD Danlite'),
        backgroundColor: AppColors.navyMid,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Hero banner ───────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40),
              decoration: const BoxDecoration(gradient: AppColors.navyGradient),
              child: Column(children: [
                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12),
                    border: Border.all(color: AppColors.flameOrange, width: 2.5),
                  ),
                  child: const Icon(Icons.local_fire_department,
                      size: 50, color: AppColors.flameGold),
                ),
                const SizedBox(height: 14),
                const Text('OBD Danlite',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
                        color: Colors.white, letterSpacing: 1)),
                const SizedBox(height: 4),
                const Text('OBD2 Vehicle Diagnostics',
                    style: TextStyle(color: Colors.white60, fontSize: 14)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.flameOrange.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20)),
                  // Real versionName from the APK, not a hand-copied literal.
                  // `initialData` means this only ever shows the bare label on
                  // the very first read of the process; afterwards the cached
                  // value paints on the first frame.
                  child: FutureBuilder<PackageInfo?>(
                    future: AppVersionService.load(),
                    initialData: AppVersionService.cached,
                    builder: (context, snap) {
                      final v = AppVersionService.versionOf(snap.data);
                      return Text(v == null ? 'Version' : 'Version $v',
                          style: const TextStyle(color: AppColors.flameGold,
                              fontWeight: FontWeight.w700, fontSize: 13));
                    },
                  ),
                ),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Features ───────────────────────────────────────────────
                _SectionTitle('What OBD Danlite Can Do'),
                const SizedBox(height: 12),
                ...[
                  (Icons.dashboard_rounded,      'Real-Time Dashboard',    'Customizable gauges for speed, RPM, temp, and more'),
                  (Icons.warning_amber_rounded,   'DTC Fault Code Reader',  'Read, diagnose, and clear Check Engine codes'),
                  (Icons.speed_rounded,           'Performance Testing',    '0–60 mph, 0–100 km/h, quarter mile & dyno estimate'),
                  (Icons.local_gas_station,       'Fuel Economy Tracking',  'Live MPG, trip computer, CO₂ emissions, cost'),
                  (Icons.show_chart,              'Live Graphs',            'Real-time charts for any sensor parameter'),
                  (Icons.fullscreen,              'HUD Mode',               'Heads-up display for night driving'),
                  (Icons.route,                   'Trip Logging',           'Record and export trips as CSV'),
                  (Icons.directions_car,          'Multiple Vehicles',      'Manage profiles for all your vehicles'),
                  (Icons.language,                '23 Indian Languages',    'Full UI in Hindi, Tamil, Telugu, and 20 more'),
                  (Icons.wifi,                    'Wi-Fi + Bluetooth',      'Works with all ELM327 OBD2 adapters'),
                ].map((f) => _FeatureTile(icon: f.$1, title: f.$2, desc: f.$3)),

                const SizedBox(height: 24),

                // ── Supported Adapters ─────────────────────────────────────
                _SectionTitle('Supported OBD2 Adapters'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight)),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Wi-Fi Adapters (Android + iOS)',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                              color: AppColors.textPrimary)),
                      SizedBox(height: 6),
                      Text('• Generic ELM327 Wi-Fi  (192.168.0.10:35000)\n'
                           '• OBDLink MX+ Wi-Fi\n'
                           '• Vgate iCar Wi-Fi\n'
                           '• PLX Kiwi 3 Wi-Fi',
                           style: TextStyle(fontSize: 13, color: AppColors.textSecondary,
                               height: 1.7)),
                      SizedBox(height: 12),
                      Text('Bluetooth Adapters (Android only)',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                              color: AppColors.textPrimary)),
                      SizedBox(height: 6),
                      Text('• Any ELM327 v1.5+ Bluetooth Classic adapter\n'
                           '• Pair in phone Bluetooth settings first',
                           style: TextStyle(fontSize: 13, color: AppColors.textSecondary,
                               height: 1.7)),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Legal ─────────────────────────────────────────────────
                _SectionTitle('Legal'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondary, borderRadius: BorderRadius.circular(12)),
                  child: const Text(
                    'OBD Danlite is an original application. '
                    'All OBD2 protocols used are open standard (SAE J1979, ISO 15765). '
                    'This app is for informational purposes only. '
                    'Always consult a qualified mechanic for vehicle repairs. '
                    'Do not operate the device while driving.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary,
                        height: 1.6)),
                ),
                const SizedBox(height: 40),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
          color: AppColors.textPrimary, letterSpacing: 0.2));
}

class _FeatureTile extends StatelessWidget {
  final IconData icon; final String title, desc;
  const _FeatureTile({required this.icon, required this.title, required this.desc});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppColors.bgSecondary, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: AppColors.navyMid, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
            color: AppColors.textPrimary)),
        Text(desc, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary,
            height: 1.4)),
      ])),
    ]),
  );
}
