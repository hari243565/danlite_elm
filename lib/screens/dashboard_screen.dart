// lib/screens/dashboard_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_strings.dart';
import '../services/obd_service.dart';
import '../services/bluetooth_classic_service.dart';
import '../providers/settings_provider.dart';
import '../models/vehicle_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ELITE TELEMETRY COLOR SYSTEM
// Design ref: hypercar HMI + professional motorsport dashboards
// ─────────────────────────────────────────────────────────────────────────────
class _EC {
  _EC._();

  // Surfaces
  static const Color bg = Color(0xFF07090E);
  static const Color surface = Color(0xFF0D1117);
  static const Color card = Color(0xFF131922);
  static const Color cardHigh = Color(0xFF192030);
  static const Color border = Color(0xFF1C2A3A);
  static const Color divider = Color(0xFF16232E);
  static const Color track = Color(0xFF182130);

  // Accents — Danlite brand derivatives
  static const Color cyan = Color(0xFF00CAFF); // electric blue
  static const Color flame = Color(0xFFFF8A00); // logo flame amber
  static const Color green = Color(0xFF00E676);
  static const Color red = Color(0xFFFF3D3D);
  static const Color amber = Color(0xFFFFB300);
  static const Color purple = Color(0xFF8B5CF6);

  // Text
  static const Color t1 = Color(0xFFEEF2F8);
  static const Color t2 = Color(0xFF607080);
  static const Color t3 = Color(0xFF2A3D52);

  // Dynamic value color based on fraction
  static Color valueColor(double fraction,
      {bool inverse = false, double warn = 0.75, double crit = 0.90}) {
    if (inverse) {
      if (fraction < 1 - crit) return red;
      if (fraction < 1 - warn) return amber;
      return green;
    }
    if (fraction >= crit) return red;
    if (fraction >= warn) return amber;
    return green;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final obd = context.watch<ObdService>();
    final bt = context.watch<BluetoothClassicService>();
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: _EC.bg,
      appBar: _DashAppBar(obd: obd, bt: bt),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 480),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
                    begin: const Offset(0, 0.04), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          ),
        ),
        child: obd.isConnected
            ? _CockpitView(
                key: const ValueKey('cockpit'),
                data: obd.data,
                settings: settings,
              )
            : _OfflineView(
                key: const ValueKey('offline'),
                pulseAnim: _pulseAnim,
                status: obd.status,
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP BAR
// ─────────────────────────────────────────────────────────────────────────────
class _DashAppBar extends StatelessWidget implements PreferredSizeWidget {
  final ObdService obd;
  final BluetoothClassicService bt;

  const _DashAppBar({required this.obd, required this.bt});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _EC.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    // Brand
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _EC.flame.withValues(alpha: 0.12),
                      ),
                      child: ClipOval(
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Image.asset('assets/images/logo.png',
                              fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Text('OBD Danlite',
                        style: TextStyle(
                            color: _EC.t1,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2)),
                    const SizedBox(width: 8),
                    _LiveDot(status: obd.status),
                    const Spacer(),
                    // Action buttons
                    _IconBtn(
                      icon: Icons.fullscreen_rounded,
                      onTap: () => Navigator.pushNamed(context, '/hud'),
                    ),
                    const SizedBox(width: 4),
                    _IconBtn(
                      icon: Icons.show_chart_rounded,
                      onTap: () => Navigator.pushNamed(context, '/graph'),
                    ),
                    const SizedBox(width: 4),
                    _IconBtn(
                      icon: Icons.dashboard_customize_rounded,
                      onTap: () => Navigator.pushNamed(context, '/realtime'),
                    ),
                  ],
                ),
              ),
            ),
            Container(height: 1, color: _EC.border),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIVE CONNECTION DOT — animated indicator
// ─────────────────────────────────────────────────────────────────────────────
class _LiveDot extends StatefulWidget {
  final ConnectionStatus status;
  const _LiveDot({required this.status});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _blink;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _blink = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool pulse = widget.status == ConnectionStatus.connecting ||
        widget.status == ConnectionStatus.error;

    Color dotColor;
    switch (widget.status) {
      case ConnectionStatus.connected:
        dotColor = _EC.green;
        break;
      case ConnectionStatus.connecting:
        dotColor = _EC.amber;
        break;
      case ConnectionStatus.error:
        dotColor = _EC.red;
        break;
      default:
        dotColor = _EC.t3;
    }

    return AnimatedBuilder(
      animation: _blink,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: pulse
              ? dotColor.withValues(alpha: 0.35 + 0.65 * _blink.value)
              : dotColor,
          boxShadow: widget.status == ConnectionStatus.connected
              ? [
                  BoxShadow(
                      color: dotColor.withValues(alpha: 0.7), blurRadius: 5)
                ]
              : null,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OFFLINE VIEW — breathtaking empty state with radar pulse rings
// ─────────────────────────────────────────────────────────────────────────────
class _OfflineView extends StatelessWidget {
  final Animation<double> pulseAnim;
  final ConnectionStatus status;

  const _OfflineView({
    super.key,
    required this.pulseAnim,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final isConnecting = status == ConnectionStatus.connecting;
    final isError = status == ConnectionStatus.error;
    final ringColor = isError ? _EC.red : _EC.cyan;

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: _EC.bg,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Radar / sonar rings ─────────────────────────────────────────
          ...List.generate(
              4,
              (i) => AnimatedBuilder(
                    animation: pulseAnim,
                    builder: (_, __) {
                      final offset = i * 0.25;
                      final v = ((pulseAnim.value + offset) % 1.0);
                      final alpha = (1 - v) * (isError ? 0.10 : 0.08);
                      final size = 80 + v * 280;
                      return Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ringColor.withValues(alpha: alpha),
                            width: 1,
                          ),
                        ),
                      );
                    },
                  )),

          // ── Subtle grid pattern overlay ─────────────────────────────────
          Opacity(
            opacity: 0.03,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 12, childAspectRatio: 1),
              itemCount: 144,
              itemBuilder: (_, __) => Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: _EC.cyan, width: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

          // ── Main content column ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Central icon ring
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: ringColor.withValues(alpha: 0.6), width: 1.5),
                    gradient: RadialGradient(
                      colors: [
                        ringColor.withValues(alpha: 0.10),
                        Colors.transparent,
                      ],
                      radius: 0.8,
                    ),
                  ),
                  child: Icon(
                    isConnecting
                        ? Icons.bluetooth_searching_rounded
                        : isError
                            ? Icons.error_outline_rounded
                            : Icons.bluetooth_disabled_rounded,
                    size: 44,
                    color: ringColor.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 30),

                // Status tag
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: ringColor.withValues(alpha: 0.10),
                    border: Border.all(color: ringColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    context.tr(isConnecting
                        ? 'statusScanning'
                        : isError
                            ? 'statusError'
                            : 'statusOffline'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: ringColor,
                      letterSpacing: 2.5,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Heading
                Text(
                  context.tr(isConnecting ? 'connecting' : 'noAdapterTitle'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _EC.t1,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),

                // Subtitle
                Text(
                  context.tr('noAdapterDesc'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _EC.t2,
                    fontSize: 13,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 32),

                // CTA or spinner
                if (isConnecting)
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      color: _EC.cyan.withValues(alpha: 0.8),
                      strokeWidth: 2,
                    ),
                  )
                else
                  // Elite CTA button
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/connect'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 15),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF005C88), Color(0xFF00CAFF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _EC.cyan.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.link_rounded,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 10),
                        Text(
                          context.tr('connectAdapter'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ]),
                    ),
                  ),

                const SizedBox(height: 48),

                // Quick tips panel
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _EC.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _EC.border),
                  ),
                  child: Column(children: [
                    _TipRow(
                      icon: Icons.wifi_rounded,
                      color: _EC.cyan,
                      text: context.tr('tipWifi'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(color: _EC.divider, height: 1),
                    ),
                    _TipRow(
                      icon: Icons.bluetooth_rounded,
                      color: _EC.purple,
                      text: context.tr('tipBluetooth'),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _TipRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: _EC.t2, fontSize: 11, height: 1.5))),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// COCKPIT VIEW — live instrument cluster
// ─────────────────────────────────────────────────────────────────────────────
class _CockpitView extends StatelessWidget {
  final VehicleData data;
  final SettingsProvider settings;

  const _CockpitView({
    super.key,
    required this.data,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
      child: Column(children: [
        // TIER 1 — Primary arc gauges: Speed + RPM
        _PrimaryGaugeTier(data: data, settings: settings),
        const SizedBox(height: 10),

        // TIER 2 — Secondary cards: Coolant, Throttle, Load
        _SecondaryMetricTier(data: data, settings: settings),
        const SizedBox(height: 10),

        // TIER 3 — Linear bars: Fuel + Battery
        _LinearBarTier(data: data, settings: settings),
        const SizedBox(height: 10),

        // TIER 4 — Quick stats strip
        _QuickStatsStrip(data: data, settings: settings),
        const SizedBox(height: 14),

        // TIER 5 — Action grid
        _ActionGrid(),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIER 1: PRIMARY GAUGE ROW
// ─────────────────────────────────────────────────────────────────────────────
class _PrimaryGaugeTier extends StatelessWidget {
  final VehicleData data;
  final SettingsProvider settings;

  const _PrimaryGaugeTier({required this.data, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
          child: _ArcGaugeWidget(
        value: settings.convertSpeed(data.speed),
        min: 0,
        max: settings.useMetric ? 260 : 160,
        label: context.tr('speed').toUpperCase(),
        unit: settings.speedUnit,
        accentColor: _EC.cyan,
        warningAt: settings.useMetric ? 160 : 100,
        criticalAt: settings.useMetric ? 220 : 135,
        size: 170,
      )),
      const SizedBox(width: 9),
      Expanded(
          child: _ArcGaugeWidget(
        value: data.rpm,
        min: 0,
        max: 8000,
        label: context.tr('rpm').toUpperCase(),
        unit: 'RPM',
        accentColor: _EC.flame,
        warningAt: 5500,
        criticalAt: 7000,
        size: 170,
      )),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ANIMATED ARC GAUGE WIDGET
// ─────────────────────────────────────────────────────────────────────────────
class _ArcGaugeWidget extends StatefulWidget {
  final double? value;
  final double min, max;
  final String label, unit;
  final Color accentColor;
  final double? warningAt, criticalAt;
  final double size;

  const _ArcGaugeWidget({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.unit,
    required this.accentColor,
    this.warningAt,
    this.criticalAt,
    this.size = 160,
  });

  @override
  State<_ArcGaugeWidget> createState() => _ArcGaugeWidgetState();
}

class _ArcGaugeWidgetState extends State<_ArcGaugeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _prev = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _anim = Tween<double>(begin: 0, end: 0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void didUpdateWidget(_ArcGaugeWidget old) {
    super.didUpdateWidget(old);
    if (widget.value != null && widget.value != old.value) {
      final clamped = widget.value!.clamp(widget.min, widget.max);
      _anim = Tween<double>(begin: _prev, end: clamped)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
      _ctrl.forward(from: 0);
      _prev = clamped;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color _accentForValue(double? v) {
    if (v == null) return _EC.t3;
    if (widget.criticalAt != null && v >= widget.criticalAt!) return _EC.red;
    if (widget.warningAt != null && v >= widget.warningAt!) return _EC.amber;
    return widget.accentColor;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final animated = widget.value != null ? _anim.value : null;
        final color = _accentForValue(widget.value);
        final fraction = animated != null
            ? (animated - widget.min) / (widget.max - widget.min)
            : 0.0;

        return Container(
          width: widget.size,
          height: widget.size + 18,
          decoration: BoxDecoration(
            color: _EC.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _EC.border),
            boxShadow: animated != null
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.06),
                        blurRadius: 24,
                        spreadRadius: 2)
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
            child: Column(children: [
              Expanded(
                child: CustomPaint(
                  painter: _GaugePainter(
                    fraction: fraction.clamp(0, 1),
                    color: color,
                    hasValue: animated != null,
                    warningFraction: widget.warningAt != null
                        ? (widget.warningAt! - widget.min) /
                            (widget.max - widget.min)
                        : null,
                    criticalFraction: widget.criticalAt != null
                        ? (widget.criticalAt! - widget.min) /
                            (widget.max - widget.min)
                        : null,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Value number — large + glow when active
                        Text(
                          animated != null
                              ? animated
                                  .toStringAsFixed(widget.unit == 'RPM' ? 0 : 1)
                              : '—',
                          style: TextStyle(
                            fontSize: widget.size * 0.185,
                            fontWeight: FontWeight.w900,
                            color: animated != null ? color : _EC.t3,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            shadows: animated != null
                                ? [
                                    Shadow(
                                        color: color.withValues(alpha: 0.55),
                                        blurRadius: 14)
                                  ]
                                : null,
                          ),
                        ),
                        Text(widget.unit,
                            style: TextStyle(
                              fontSize: widget.size * 0.079,
                              color: _EC.t2,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.8,
                            )),
                        SizedBox(height: widget.size * 0.04),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(widget.label,
                  style: const TextStyle(
                      fontSize: 9.5,
                      color: _EC.t2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.2)),
            ]),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GAUGE CUSTOM PAINTER — 240° arc with zone bands + glowing tip
// ─────────────────────────────────────────────────────────────────────────────
class _GaugePainter extends CustomPainter {
  final double fraction;
  final Color color;
  final bool hasValue;
  final double? warningFraction, criticalFraction;

  const _GaugePainter({
    required this.fraction,
    required this.color,
    this.hasValue = true,
    this.warningFraction,
    this.criticalFraction,
  });

  static const double _startDeg = 150;
  static const double _sweepDeg = 240;
  static const double _startRad = _startDeg * math.pi / 180;
  static const double _sweepRad = _sweepDeg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.54;
    final r = math.min(size.width, size.height * 0.96) * 0.43;
    final sw = r * 0.13;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // ── Background track ───────────────────────────────────────────────────
    canvas.drawArc(
        rect,
        _startRad,
        _sweepRad,
        false,
        Paint()
          ..color = _EC.track
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.round);

    // ── Zone backgrounds (subtle, widen track) ─────────────────────────────
    if (warningFraction != null) {
      _drawZoneArc(canvas, rect, _startRad, _sweepRad * warningFraction!,
          _EC.green.withValues(alpha: 0.05), sw * 2.6);
      if (criticalFraction != null) {
        _drawZoneArc(
            canvas,
            rect,
            _startRad + _sweepRad * warningFraction!,
            _sweepRad * (criticalFraction! - warningFraction!),
            _EC.amber.withValues(alpha: 0.05),
            sw * 2.6);
        _drawZoneArc(
            canvas,
            rect,
            _startRad + _sweepRad * criticalFraction!,
            _sweepRad * (1 - criticalFraction!),
            _EC.red.withValues(alpha: 0.05),
            sw * 2.6);
      }
    }

    // ── Value arc ──────────────────────────────────────────────────────────
    final valueSweep = _sweepRad * fraction;
    if (valueSweep > 0.01) {
      canvas.drawArc(
          rect,
          _startRad,
          valueSweep,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = sw
            ..strokeCap = StrokeCap.round);

      // Glowing tip
      final tipA = _startRad + valueSweep;
      final tx = cx + r * math.cos(tipA);
      final ty = cy + r * math.sin(tipA);

      // Outer glow
      canvas.drawCircle(
          Offset(tx, ty),
          sw * 1.4,
          Paint()
            ..color = color.withValues(alpha: 0.22)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));

      // Inner dot
      canvas.drawCircle(Offset(tx, ty), sw * 0.65,
          Paint()..color = Colors.white.withValues(alpha: 0.9));
      canvas.drawCircle(
          Offset(tx, ty),
          sw * 0.65,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = sw * 0.18);
    }

    // ── Tick marks ─────────────────────────────────────────────────────────
    _drawTicks(canvas, cx, cy, r, sw);

    // ── Analog needle + pivot hub ────────────────────────────────────────────
    if (hasValue) {
      _drawNeedle(canvas, cx, cy, r, sw);
    }
  }

  /// Sweeping analog needle: a sleek tapering polygon that pivots from the
  /// gauge centre to point at the current value, topped with a metallic hub.
  void _drawNeedle(Canvas c, double cx, double cy, double r, double sw) {
    final center = Offset(cx, cy);
    final angle = _startRad + _sweepRad * fraction.clamp(0.0, 1.0);

    final tipLen = r * 0.88; // reaches just inside the arc
    final tailLen = r * 0.15; // short counter-balance behind the pivot
    final baseHalf = sw * 0.40; // half-width at the widest point (the pivot)

    c.save();
    c.translate(cx, cy);
    c.rotate(angle);

    // Tapering blade: widest at the pivot, sharpening to the tip.
    final needle = Path()
      ..moveTo(-tailLen, 0)
      ..lineTo(0, -baseHalf)
      ..lineTo(tipLen, 0)
      ..lineTo(0, baseHalf)
      ..close();

    // Soft glow so the needle reads clearly over arc + zone bands.
    c.drawPath(
        needle,
        Paint()
          ..color = color.withValues(alpha: 0.32)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

    // Solid needle body.
    c.drawPath(needle, Paint()..color = color);

    c.restore();

    // Central pivot hub — brushed-metal look sitting above the blade base.
    c.drawCircle(
        center,
        sw * 0.95,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.4),
            colors: const [Color(0xFF6E7A8C), _EC.cardHigh, Color(0xFF05070A)],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: sw * 0.95)));
    c.drawCircle(
        center,
        sw * 0.95,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.black.withValues(alpha: 0.55));
    // Bright centre cap.
    c.drawCircle(
        center, sw * 0.30, Paint()..color = color.withValues(alpha: 0.9));
  }

  void _drawZoneArc(
      Canvas c, Rect rect, double start, double sweep, Color color, double sw) {
    c.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.butt);
  }

  void _drawTicks(Canvas c, double cx, double cy, double r, double sw) {
    final tickPaint = Paint()
      ..color = _EC.t3
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    const int ticks = 10;
    for (int i = 0; i <= ticks; i++) {
      final angle = _startRad + _sweepRad * i / ticks;
      final inner = r - sw * 1.2;
      final outer = r - sw * 1.9;
      c.drawLine(
        Offset(cx + inner * math.cos(angle), cy + inner * math.sin(angle)),
        Offset(cx + outer * math.cos(angle), cy + outer * math.sin(angle)),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.hasValue != hasValue;
}

// ─────────────────────────────────────────────────────────────────────────────
// TIER 2: SECONDARY METRIC CARDS
// ─────────────────────────────────────────────────────────────────────────────
class _SecondaryMetricTier extends StatelessWidget {
  final VehicleData data;
  final SettingsProvider settings;

  const _SecondaryMetricTier({required this.data, required this.settings});

  @override
  Widget build(BuildContext context) {
    final coolantFrac = data.coolantTemp != null
        ? ((settings.convertTemp(data.coolantTemp) + 40) / 170).clamp(0.0, 1.0)
        : 0.0;

    return Row(children: [
      Expanded(
          child: _MetricCard(
        label: context.tr('coolantTemp'),
        rawValue: data.coolantTemp != null
            ? settings.convertTemp(data.coolantTemp)
            : null,
        unit: settings.tempUnit,
        fraction: coolantFrac,
        accentColor: _EC.amber,
        critAt: 0.82,
        warnAt: 0.70,
      )),
      const SizedBox(width: 8),
      Expanded(
          child: _MetricCard(
        label: context.tr('throttle'),
        rawValue: data.throttle,
        unit: '%',
        fraction: (data.throttle ?? 0) / 100,
        accentColor: _EC.cyan,
      )),
      const SizedBox(width: 8),
      Expanded(
          child: _MetricCard(
        label: context.tr('engineLoad'),
        rawValue: data.engineLoad,
        unit: '%',
        fraction: (data.engineLoad ?? 0) / 100,
        accentColor: _EC.cyan,
        critAt: 0.92,
        warnAt: 0.78,
      )),
    ]);
  }
}

class _MetricCard extends StatelessWidget {
  final String label, unit;
  final double? rawValue;
  final double fraction;
  final Color accentColor;
  final double? warnAt, critAt;

  const _MetricCard({
    required this.label,
    required this.rawValue,
    required this.unit,
    required this.fraction,
    required this.accentColor,
    this.warnAt,
    this.critAt,
  });

  Color _barColor() {
    if (critAt != null && fraction >= critAt!) return _EC.red;
    if (warnAt != null && fraction >= warnAt!) return _EC.amber;
    return accentColor;
  }

  @override
  Widget build(BuildContext context) {
    final color = _barColor();
    final hasValue = rawValue != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
      decoration: BoxDecoration(
        color: _EC.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasValue && critAt != null && fraction >= critAt!
              ? _EC.red.withValues(alpha: 0.4)
              : _EC.border,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 8.5,
                color: _EC.t2,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.8)),
        const SizedBox(height: 7),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            hasValue ? rawValue!.toStringAsFixed(0) : '—',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: hasValue ? color : _EC.t3,
              fontFeatures: const [FontFeature.tabularFigures()],
              shadows: hasValue
                  ? [
                      Shadow(
                          color: color.withValues(alpha: 0.45), blurRadius: 10)
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 3),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(unit,
                style: const TextStyle(
                    fontSize: 10, color: _EC.t2, fontWeight: FontWeight.w500)),
          ),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction.clamp(0, 1),
            minHeight: 4,
            backgroundColor: _EC.track,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIER 3: LINEAR BAR METRICS — Fuel + Battery
// ─────────────────────────────────────────────────────────────────────────────
class _LinearBarTier extends StatelessWidget {
  final VehicleData data;
  final SettingsProvider settings;

  const _LinearBarTier({required this.data, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _LinearBar(
        icon: Icons.battery_charging_full_rounded,
        label: context.tr('batteryVoltage'),
        value: data.batteryVoltage,
        unit: 'V',
        min: 10.0,
        max: 15.0,
        color: _EC.cyan,
        inverse: false,
      ),
    ]);
  }
}

class _LinearBar extends StatelessWidget {
  final IconData icon;
  final String label, unit;
  final double? value;
  final double min, max;
  final Color color;
  final bool inverse;

  const _LinearBar({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.color,
    required this.inverse,
  });

  @override
  Widget build(BuildContext context) {
    final fraction =
        value != null ? ((value! - min) / (max - min)).clamp(0.0, 1.0) : 0.0;

    final isCrit = inverse ? fraction < 0.12 : fraction > 0.92;
    final isWarn = inverse ? fraction < 0.28 : fraction > 0.78;
    final barColor = isCrit
        ? _EC.red
        : isWarn
            ? _EC.amber
            : color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: _EC.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCrit ? _EC.red.withValues(alpha: 0.5) : _EC.border,
        ),
      ),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: barColor.withValues(alpha: 0.12),
          ),
          child: Icon(icon, color: barColor, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      color: _EC.t2,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                value != null
                    ? '${value!.toStringAsFixed(unit == 'V' ? 2 : 0)} $unit'
                    : '— $unit',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: value != null ? barColor : _EC.t3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ]),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 5,
                backgroundColor: _EC.track,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
          ],
        )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIER 4: QUICK STATS STRIP — Intake, MAF, MAP, Timing
// ─────────────────────────────────────────────────────────────────────────────
class _QuickStatsStrip extends StatelessWidget {
  final VehicleData data;
  final SettingsProvider settings;

  const _QuickStatsStrip({required this.data, required this.settings});

  @override
  Widget build(BuildContext context) {
    String _fmtTemp(double? v) => v != null
        ? '${settings.convertTemp(v).toStringAsFixed(0)}${settings.tempUnit}'
        : '—';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
      decoration: BoxDecoration(
        color: _EC.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _EC.border),
      ),
      child: Row(children: [
        _Stat(
            label: context.tr('intakeTemp'), value: _fmtTemp(data.intakeTemp)),
        _VDiv(),
        _Stat(
            label: context.tr('mafLabel'),
            value:
                data.maf != null ? '${data.maf!.toStringAsFixed(1)} g/s' : '—'),
        _VDiv(),
        _Stat(
            label: context.tr('mapLabel'),
            value: data.manifoldPressure != null
                ? '${data.manifoldPressure!.toStringAsFixed(0)} kPa'
                : '—'),
        _VDiv(),
        _Stat(
            label: context.tr('timingLabel'),
            value: data.timingAdvance != null
                ? '${data.timingAdvance!.toStringAsFixed(1)}°'
                : '—'),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _EC.t1,
                fontFeatures: [FontFeature.tabularFigures()],
              )),
          const SizedBox(height: 3),
          Text(label.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 8,
                  color: _EC.t2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
        ]),
      );
}

class _VDiv extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: _EC.divider);
}

// ─────────────────────────────────────────────────────────────────────────────
// TIER 5: ACTION GRID
// ─────────────────────────────────────────────────────────────────────────────
class _ActionGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      _AItem(Icons.warning_amber_rounded, context.tr('faultCodes'), _EC.red,
          '/dtc', iconAsset: 'assets/icons/fault_code_gold.png'),
      _AItem(Icons.speed_rounded,
          context.tr('accelTestShort').replaceAll('\n', ' '), _EC.flame,
          '/performance'),
      _AItem(Icons.local_gas_station_rounded,
          context.tr('fuelEconomy').replaceAll('\n', ' '), _EC.cyan, '/fuel'),
      _AItem(Icons.show_chart_rounded,
          context.tr('liveGraphs').replaceAll('\n', ' '), _EC.green, '/graph'),
      _AItem(Icons.history_rounded,
          context.tr('tripHistory').replaceAll('\n', ' '), _EC.purple, '/trips'),
      _AItem(Icons.fullscreen_rounded,
          context.tr('hudMode').replaceAll('\n', ' '), const Color(0xFF06B6D4),
          '/hud'),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.12,
      children: items.map((a) => _ACard(item: a)).toList(),
    );
  }
}

class _AItem {
  final IconData icon;
  final String label;
  final Color color;
  final String route;
  final String? iconAsset;
  const _AItem(this.icon, this.label, this.color, this.route, {this.iconAsset});
}

class _ACard extends StatelessWidget {
  final _AItem item;
  const _ACard({required this.item});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => Navigator.pushNamed(context, item.route),
        child: Container(
          decoration: BoxDecoration(
            color: _EC.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: item.color.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                  color: item.color.withValues(alpha: 0.07),
                  blurRadius: 14,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: item.color.withValues(alpha: 0.11),
              ),
              child: item.iconAsset != null
                  ? Padding(
                      padding: const EdgeInsets.all(9),
                      child: Image.asset(item.iconAsset!, fit: BoxFit.contain),
                    )
                  : Icon(item.icon, color: item.color, size: 22),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(item.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _EC.t1,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  )),
            ),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED: APPBAR ICON BUTTON
// ─────────────────────────────────────────────────────────────────────────────
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _EC.card,
            border: Border.all(color: _EC.border),
          ),
          child: Icon(icon, color: _EC.t2, size: 17),
        ),
      );
}
