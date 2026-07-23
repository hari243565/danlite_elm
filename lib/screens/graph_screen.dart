import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_strings.dart';
import '../services/obd_service.dart';

// Unified Telemetry Design System Palette (matches home_screen._NC / realtime_screen._RC)
class _RC {
  static const Color bg = Color(0xFF07090E);
  static const Color surface = Color(0xFF0D1117);
  static const Color card = Color(0xFF131922);
  static const Color border = Color(0xFF1C2A3A);
  static const Color textMain = Color(0xFFEEF2F8);
  static const Color textMuted = Color(0xFF607080);
  static const Color darkTrack = Color(0xFF182130);
  static const Color neonCyan = Color(0xFF00CAFF);
  static const Color neonAmber = Color(0xFFFF8A00);
}

class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  static const int _maxPoints = 50;
  static const Duration _minSampleGap = Duration(milliseconds: 400);

  final List<double> _rpmHistory = [];
  final List<double> _speedHistory = [];
  DateTime? _lastSampleAt;
  ObdService? _obd;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Consume the ObdService change-notifier "stream": subscribe once per
    // instance, re-subscribing only if the provided instance actually changes.
    final obd = context.read<ObdService>();
    if (!identical(_obd, obd)) {
      _obd?.removeListener(_onObdData);
      _obd = obd;
      _obd!.addListener(_onObdData);
    }
  }

  @override
  void dispose() {
    _obd?.removeListener(_onObdData);
    super.dispose();
  }

  void _onObdData() {
    final obd = _obd;
    if (obd == null) return;

    if (!obd.isConnected) {
      if (_rpmHistory.isNotEmpty || _speedHistory.isNotEmpty) {
        if (mounted) {
          setState(() {
            _rpmHistory.clear();
            _speedHistory.clear();
          });
        } else {
          _rpmHistory.clear();
          _speedHistory.clear();
        }
      }
      _lastSampleAt = null;
      return;
    }

    // Time-gate sampling so the buffer fills at a steady, performant cadence
    // instead of on every single PID update fired by the poll loop.
    final now = DateTime.now();
    if (_lastSampleAt != null && now.difference(_lastSampleAt!) < _minSampleGap) return;
    _lastSampleAt = now;

    // Never let a transient null PID read produce a gap/crash in the chart —
    // hold the last known value instead.
    final rpm = obd.data.rpm ?? (_rpmHistory.isNotEmpty ? _rpmHistory.last : 0.0);
    final speed = obd.data.speed ?? (_speedHistory.isNotEmpty ? _speedHistory.last : 0.0);

    if (!mounted) return;
    setState(() {
      _rpmHistory.add(rpm);
      if (_rpmHistory.length > _maxPoints) _rpmHistory.removeAt(0);
      _speedHistory.add(speed);
      if (_speedHistory.length > _maxPoints) _speedHistory.removeAt(0);
    });
  }

  double _dynamicAxisMax(List<double> points, {required double floor, required double headroom}) {
    if (points.isEmpty) return floor;
    final maxV = points.reduce((a, b) => a > b ? a : b);
    final scaled = maxV * headroom;
    return scaled < floor ? floor : scaled;
  }

  @override
  Widget build(BuildContext context) {
    final obd = context.watch<ObdService>();

    return Scaffold(
      backgroundColor: _RC.bg,
      appBar: AppBar(
        backgroundColor: _RC.surface,
        elevation: 0,
        title: Text(context.tr('liveGraphsTitle'),
            style: const TextStyle(color: _RC.textMain, fontWeight: FontWeight.w800)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _RC.border),
        ),
      ),
      body: obd.isConnected ? _buildConnected(obd) : _buildDisconnected(),
    );
  }

  Widget _buildDisconnected() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _RC.card,
                shape: BoxShape.circle,
                border: Border.all(color: _RC.border),
              ),
              child: const Icon(Icons.show_chart_rounded, size: 48, color: _RC.textMuted),
            ),
            const SizedBox(height: 20),
            Text(context.tr('graphNotConnectedTitle'),
                style: const TextStyle(
                    color: _RC.textMain,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                context.tr('graphNotConnectedDesc'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _RC.textMuted, fontSize: 13),
              ),
            ),
          ],
        ),
      );

  Widget _buildConnected(ObdService obd) {
    final rpmMax = _dynamicAxisMax(_rpmHistory, floor: 1000, headroom: 1.2);
    final speedMax = _dynamicAxisMax(_speedHistory, floor: 40, headroom: 1.2);

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _ChannelCard(
          title: context.tr('sensorEngineRpm').toUpperCase(),
          unit: 'RPM',
          color: _RC.neonAmber,
          points: List.unmodifiable(_rpmHistory),
          axisMax: rpmMax,
          decimals: 0,
        ),
        _ChannelCard(
          title: context.tr('sensorVehicleSpeed').toUpperCase(),
          unit: 'km/h',
          color: _RC.neonCyan,
          points: List.unmodifiable(_speedHistory),
          axisMax: speedMax,
          decimals: 0,
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: _RC.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _RC.border)),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 14, color: _RC.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.trArgs('graphBufferStatus', {
                    'current': '${_rpmHistory.length}',
                    'max': '$_maxPoints',
                  }),
                  style: const TextStyle(color: _RC.textMuted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChannelCard extends StatelessWidget {
  final String title;
  final String unit;
  final Color color;
  final List<double> points;
  final double axisMax;
  final int decimals;

  const _ChannelCard({
    required this.title,
    required this.unit,
    required this.color,
    required this.points,
    required this.axisMax,
    this.decimals = 0,
  });

  @override
  Widget build(BuildContext context) {
    final last = points.isEmpty ? 0.0 : points.last;
    final maxV = points.isEmpty ? 0.0 : points.reduce((a, b) => a > b ? a : b);
    final minV = points.isEmpty ? 0.0 : points.reduce((a, b) => a < b ? a : b);
    final avgV = points.isEmpty ? 0.0 : points.reduce((a, b) => a + b) / points.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _RC.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _RC.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      color: _RC.textMain,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4)),
              const Spacer(),
              Text(
                points.isEmpty ? '—' : '${last.toStringAsFixed(decimals)} $unit',
                style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 120,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparkPainter(
                points: points,
                axisMax: axisMax,
                color: color,
                awaitingDataLabel: context.tr('awaitingData'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _miniStat(context.tr('minLabel'), minV),
              _miniStat(context.tr('avgLabel'), avgV),
              _miniStat(context.tr('maxLabel'), maxV),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, double value) => Row(
        children: [
          Text('$label ',
              style: const TextStyle(
                  color: _RC.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
          Text(value.toStringAsFixed(decimals),
              style: const TextStyle(
                  color: _RC.textMain,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace')),
        ],
      );
}

class _SparkPainter extends CustomPainter {
  final List<double> points;
  final double axisMax;
  final Color color;
  final String awaitingDataLabel;

  _SparkPainter({
    required this.points,
    required this.axisMax,
    required this.color,
    required this.awaitingDataLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      final tp = TextPainter(
        text: TextSpan(
            text: awaitingDataLabel, style: const TextStyle(color: _RC.textMuted, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height / 2 - tp.height / 2));
      return;
    }

    final safeMax = axisMax <= 0 ? 1.0 : axisMax;
    final n = points.length;

    final gridPaint = Paint()
      ..color = _RC.darkTrack
      ..strokeWidth = 1;
    for (int i = 1; i < 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    Offset pointAt(int i) {
      final x = n == 1 ? size.width : (i / (n - 1)) * size.width;
      final v = points[i].clamp(0.0, safeMax);
      final y = size.height - (v / safeMax) * size.height;
      return Offset(x, y);
    }

    final fillPath = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (int i = 1; i < n; i++) {
      final p = pointAt(i);
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        fillPath, Paint()..color = color.withValues(alpha: 0.10)..style = PaintingStyle.fill);

    final linePath = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (int i = 1; i < n; i++) {
      final p = pointAt(i);
      linePath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final last = pointAt(n - 1);
    canvas.drawCircle(last, 4, Paint()..color = color);
    canvas.drawCircle(
        last, 4, Paint()..color = _RC.card..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.points.length != points.length ||
      old.awaitingDataLabel != awaitingDataLabel ||
      (points.isNotEmpty &&
          old.points.isNotEmpty &&
          (old.points.last != points.last || old.axisMax != axisMax));
}
