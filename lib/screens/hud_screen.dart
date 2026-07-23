import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../constants/app_strings.dart';
import '../services/obd_service.dart';
import '../providers/settings_provider.dart';

class HudScreen extends StatefulWidget {
  const HudScreen({super.key});
  @override
  State<HudScreen> createState() => _HudScreenState();
}

class _HudScreenState extends State<HudScreen> {
  bool _mirrored = true; // Mirror text for HUD projection

  @override
  void initState() {
    super.initState();
    // Force landscape + hide status bar for HUD
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final obd      = context.watch<ObdService>();
    final settings = context.watch<SettingsProvider>();
    final data     = obd.data;

    final speed = settings.convertSpeed(data.speed) ?? 0;
    final rpm   = data.rpm ?? 0;
    final temp  = settings.convertTemp(data.coolantTemp) ?? 0;
    final fuel  = data.fuelLevel ?? 0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _mirrored = !_mirrored),
        onLongPress: () => Navigator.pop(context),
        child: Transform(
          transform: _mirrored
              ? (Matrix4.identity()..scale(-1.0, 1.0)..translate(-MediaQuery.of(context).size.width))
              : Matrix4.identity(),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: help text
                  Row(children: [
                    const Icon(Icons.touch_app, color: Colors.white24, size: 14),
                    const SizedBox(width: 4),
                    Text(context.tr('tapToMirror'),
                        style: const TextStyle(color: Colors.white24, fontSize: 11)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text(
                          context.tr(_mirrored ? 'mirroredLabel' : 'normalLabel'),
                          style: const TextStyle(color: Colors.white38, fontSize: 10,
                              letterSpacing: 1)),
                    ),
                  ]),
                  const Spacer(),

                  // ── Main speed ────────────────────────────────────────
                  Center(
                    child: Column(children: [
                      Text(speed.toStringAsFixed(0),
                          style: TextStyle(
                            fontSize: 130,
                            fontWeight: FontWeight.w900,
                            color: _speedColor(speed, settings),
                            fontFamily: 'monospace',
                            shadows: [Shadow(color: _speedColor(speed, settings).withValues(alpha: 0.4),
                                blurRadius: 30)],
                          )),
                      Text(settings.speedUnit,
                          style: const TextStyle(fontSize: 24, color: Colors.white54,
                              letterSpacing: 4)),
                    ]),
                  ),

                  const Spacer(),

                  // ── Bottom stats row ──────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _HudStat(label: context.tr('hudRpm'), value: rpm.toStringAsFixed(0),
                          color: rpm > 5500 ? AppColors.error : Colors.white),
                      _HudStat(label: settings.tempUnit, value: temp.toStringAsFixed(0),
                          color: temp > 100 ? AppColors.error : Colors.white),
                      _HudStat(label: context.tr('hudFuel'), value: '${fuel.toStringAsFixed(0)}%',
                          color: fuel < 15 ? AppColors.error : Colors.white),
                      _HudStat(label: context.tr('hudBatt'),
                          value: data.batteryVoltage != null
                              ? '${data.batteryVoltage!.toStringAsFixed(1)}V' : '--',
                          color: Colors.white),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── RPM bar ───────────────────────────────────────────
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (rpm / 8000).clamp(0, 1),
                      minHeight: 8,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(_rpmColor(rpm)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _speedColor(double speed, SettingsProvider s) {
    final limit = s.useMetric ? 120 : 75;
    if (speed > limit * 1.2) return AppColors.error;
    if (speed > limit) return AppColors.gaugeOrange;
    return Colors.white;
  }

  Color _rpmColor(double rpm) {
    if (rpm > 6500) return AppColors.error;
    if (rpm > 5000) return AppColors.gaugeOrange;
    return Colors.greenAccent;
  }
}

class _HudStat extends StatelessWidget {
  final String label, value; final Color color;
  const _HudStat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
        color: color, fontFamily: 'monospace',
        shadows: [Shadow(color: color.withValues(alpha: 0.4), blurRadius: 16)])),
    Text(label, style: const TextStyle(fontSize: 11, color: Colors.white38, letterSpacing: 2)),
  ]);
}
