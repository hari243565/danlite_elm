import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Danlite ELM — Analog Gauge Dial Widget
/// Torque Pro-style circular gauge: metallic bezel, tick scale, color-coded
/// gradient arc (cyan → orange → red) and an animated needle, with a
/// digital readout in the central hub.
class _GC {
  static const Color bezelDark = Color(0xFF0A0D12);
  static const Color bezelLight = Color(0xFF3A4250);
  static const Color bezelHighlight = Color(0xFF6E7A8C);
  static const Color face = Color(0xFF121821);
  static const Color faceEdge = Color(0xFF05070A);
  static const Color tickMajor = Color(0xFFE8EDF4);
  static const Color tickMinor = Color(0xFF4A5566);
  static const Color textMain = Color(0xFFEEF2F8);
  static const Color textMuted = Color(0xFF7686A0);
  static const Color neonCyan = Color(0xFF00CAFF);
  static const Color neonOrange = Color(0xFFFF8A00);
  static const Color neonRed = Color(0xFFFF1744);
  static const Color hubMetal = Color(0xFF2A323F);

  // Gradient breakpoint (fraction of gauge range) where the cyan→amber fade
  // completes and the amber→red fade begins. 0.0 = cyan, 0.65 = amber,
  // 1.0 = red, with continuous blending between them.
  static const double amberStop = 0.65;
}

class GaugeDialWidget extends StatefulWidget {
  final double? value;
  final double min;
  final double max;
  final String label;
  final String unit;
  final int decimals;
  final double size;

  const GaugeDialWidget({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.unit,
    this.decimals = 0,
    this.size = 160,
  });

  @override
  State<GaugeDialWidget> createState() => _GaugeDialWidgetState();
}

class _GaugeDialWidgetState extends State<GaugeDialWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animation;
  double _prevValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _prevValue = (widget.value ?? widget.min).clamp(widget.min, widget.max);
    _animation = Tween<double>(begin: _prevValue, end: _prevValue)
        .animate(_controller);
  }

  @override
  void didUpdateWidget(covariant GaugeDialWidget old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value ||
        old.min != widget.min ||
        old.max != widget.max) {
      final target =
          (widget.value ?? widget.min).clamp(widget.min, widget.max);
      _animation = Tween<double>(begin: _prevValue, end: target).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );
      _controller.forward(from: 0);
      _prevValue = target;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size.square(widget.size),
                    painter: _GaugeDialPainter(
                      animValue: _animation.value,
                      hasValue: widget.value != null,
                      min: widget.min,
                      max: widget.max,
                    ),
                  ),
                  _DigitalReadout(
                    text: widget.value != null
                        ? widget.value!.toStringAsFixed(widget.decimals)
                        : '—',
                    unit: widget.unit,
                    size: widget.size,
                  ),
                ],
              );
            },
          ),
        ),
        SizedBox(height: widget.size * 0.05),
        Text(
          widget.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _GC.textMuted,
            fontSize: (widget.size * 0.085).clamp(10.0, 14.0),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _DigitalReadout extends StatelessWidget {
  final String text;
  final String unit;
  final double size;

  const _DigitalReadout(
      {required this.text, required this.unit, required this.size});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(
            color: _GC.textMain,
            fontSize: size * 0.15,
            fontWeight: FontWeight.w800,
            height: 1.0,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          unit,
          style: TextStyle(
            color: _GC.textMuted,
            fontSize: size * 0.065,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _GaugeDialPainter extends CustomPainter {
  final double animValue;
  final bool hasValue;
  final double min;
  final double max;

  _GaugeDialPainter({
    required this.animValue,
    required this.hasValue,
    required this.min,
    required this.max,
  });

  // 7 o'clock start, sweeping 240° clockwise to 5 o'clock.
  static const double _startAngle = 150 * math.pi / 180;
  static const double _sweepAngle = 240 * math.pi / 180;

  // The sweep gradient is authored over a slightly wider span than the arc it
  // paints. The extra tail is solid red, so anti-aliasing at the arc's final
  // pixel can never sample past the last stop and wrap back to the first
  // color (the cyan sliver bug).
  static const double _gradientPad = 2 * math.pi / 180;
  // Maps an arc fraction (0..1) onto the padded gradient's stop space.
  static const double _gradientScale =
      _sweepAngle / (_sweepAngle + _gradientPad);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;

    _paintBezel(canvas, center, outerRadius);

    final faceRadius = outerRadius * 0.90;
    _paintFace(canvas, center, faceRadius);

    final arcRadius = faceRadius * 0.80;
    final arcWidth = faceRadius * 0.11;
    _paintColorArc(canvas, center, arcRadius, arcWidth);

    _paintTicks(canvas, center, arcRadius - arcWidth * 0.85, faceRadius);

    if (hasValue && max > min) {
      final fraction = ((animValue - min) / (max - min)).clamp(0.0, 1.0);
      final angle = _startAngle + _sweepAngle * fraction;
      _paintNeedle(canvas, center, faceRadius * 0.78, angle, fraction);
    }

    _paintHub(canvas, center, faceRadius * 0.30);
  }

  void _paintBezel(Canvas canvas, Offset center, double outerRadius) {
    final rimPaint = Paint()..color = _GC.faceEdge;
    canvas.drawCircle(center, outerRadius, rimPaint);

    final bezelWidth = outerRadius * 0.11;
    final bezelRect = Rect.fromCircle(center: center, radius: outerRadius);
    final bezelPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bezelWidth
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _GC.bezelHighlight,
          _GC.bezelLight,
          _GC.bezelDark,
          _GC.bezelLight,
          _GC.bezelHighlight,
        ],
        stops: [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(bezelRect);
    canvas.drawCircle(center, outerRadius - bezelWidth / 2, bezelPaint);

    final innerLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black.withValues(alpha: 0.6);
    canvas.drawCircle(center, outerRadius - bezelWidth, innerLinePaint);
  }

  void _paintFace(Canvas canvas, Offset center, double faceRadius) {
    final facePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        radius: 1.1,
        colors: const [_GC.face, _GC.faceEdge],
      ).createShader(Rect.fromCircle(center: center, radius: faceRadius));
    canvas.drawCircle(center, faceRadius, facePaint);
  }

  void _paintColorArc(
      Canvas canvas, Offset center, double radius, double strokeWidth) {
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..color = _GC.tickMinor.withValues(alpha: 0.25);
    canvas.drawArc(rect, _startAngle, _sweepAngle, false, trackPaint);

    final gradientPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..shader = SweepGradient(
        // The gradient frame is rotated so its 0 rad points along the arc's
        // start. This is load-bearing: SweepGradient derives its sample angle
        // from atan2, which is always in [0, 2*pi). The arc runs 150deg ->
        // 390deg, so its final 30deg would be sampled as 0deg..30deg — below a
        // literal `startAngle: _startAngle` — and TileMode.clamp would pin it
        // to stop 0.0 (cyan). That is the cyan tail. Rotating the frame puts
        // the atan2 discontinuity exactly on the arc's start, where the color
        // is cyan on both sides, so the seam is invisible.
        transform: const GradientRotation(_startAngle),
        // Angles below are in the rotated frame: 0 == arc start, _sweepAngle
        // == arc end, plus the solid-red safety tail for anti-aliasing.
        startAngle: 0.0,
        endAngle: _sweepAngle + _gradientPad,
        tileMode: TileMode.clamp,
        colors: const [
          _GC.neonCyan,
          _GC.neonOrange,
          _GC.neonRed,
          _GC.neonRed,
        ],
        stops: const [
          0.0,
          _GC.amberStop * _gradientScale,
          _gradientScale,
          1.0,
        ],
      ).createShader(rect);
    canvas.drawArc(rect, _startAngle, _sweepAngle, false, gradientPaint);
  }

  // Continuous color ramp matching the arc's sweep gradient exactly:
  // cyan → amber (0.0–0.65) → deep orange-red (0.65–1.0).
  static Color _arcColorAt(double fraction) {
    final f = fraction.clamp(0.0, 1.0);
    if (f <= _GC.amberStop) {
      return Color.lerp(_GC.neonCyan, _GC.neonOrange, f / _GC.amberStop)!;
    }
    return Color.lerp(_GC.neonOrange, _GC.neonRed,
        (f - _GC.amberStop) / (1.0 - _GC.amberStop))!;
  }

  double _niceStep(double range, int targetSteps) {
    if (range <= 0) return 1;
    final rawStep = range / targetSteps;
    final mag =
        math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
    final norm = rawStep / mag;
    double niceNorm;
    if (norm < 1.5) {
      niceNorm = 1;
    } else if (norm < 3) {
      niceNorm = 2;
    } else if (norm < 7) {
      niceNorm = 5;
    } else {
      niceNorm = 10;
    }
    return niceNorm * mag;
  }

  void _paintTicks(
      Canvas canvas, Offset center, double outerR, double faceRadius) {
    if (max <= min) return;
    final step = _niceStep(max - min, 6);
    if (step <= 0) return;
    const minorPerMajor = 5;
    final minorStep = step / minorPerMajor;
    final totalMinorTicks = ((max - min) / minorStep).round();

    final majorLen = faceRadius * 0.12;
    final minorLen = faceRadius * 0.06;
    final labelPos = outerR - majorLen - faceRadius * 0.17;

    final majorPaint = Paint()
      ..color = _GC.tickMajor
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final minorPaint = Paint()
      ..color = _GC.tickMinor
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i <= totalMinorTicks; i++) {
      final v = min + i * minorStep;
      if (v > max + 0.0001) break;
      final isMajor = i % minorPerMajor == 0;
      final fraction = ((v - min) / (max - min)).clamp(0.0, 1.0);
      final angle = _startAngle + _sweepAngle * fraction;
      final len = isMajor ? majorLen : minorLen;

      final outer = Offset(
        center.dx + outerR * math.cos(angle),
        center.dy + outerR * math.sin(angle),
      );
      final inner = Offset(
        center.dx + (outerR - len) * math.cos(angle),
        center.dy + (outerR - len) * math.sin(angle),
      );
      canvas.drawLine(inner, outer, isMajor ? majorPaint : minorPaint);

      if (isMajor) {
        _drawTickLabel(canvas, center, labelPos, angle, v, faceRadius);
      }
    }
  }

  void _drawTickLabel(Canvas canvas, Offset center, double labelRadius,
      double angle, double value, double faceRadius) {
    final text = value >= 1000
        ? '${(value / 1000).toStringAsFixed(0)}k'
        : value.toStringAsFixed(0);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _GC.textMuted,
          fontSize: faceRadius * 0.11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final x = center.dx + labelRadius * math.cos(angle);
    final y = center.dy + labelRadius * math.sin(angle);
    tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
  }

  void _paintNeedle(Canvas canvas, Offset center, double tipRadius,
      double angle, double fraction) {
    final needleColor = _arcColorAt(fraction);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final path = Path()
      ..moveTo(-tipRadius * 0.18, -tipRadius * 0.05)
      ..lineTo(tipRadius, 0)
      ..lineTo(-tipRadius * 0.18, tipRadius * 0.05)
      ..close();

    final glowPaint = Paint()
      ..color = needleColor.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path, glowPaint);

    canvas.drawPath(path, Paint()..color = needleColor);

    canvas.restore();
  }

  void _paintHub(Canvas canvas, Offset center, double radius) {
    final hubPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        colors: const [_GC.bezelHighlight, _GC.hubMetal, _GC.faceEdge],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, hubPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black.withValues(alpha: 0.5);
    canvas.drawCircle(center, radius, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugeDialPainter old) =>
      old.animValue != animValue ||
      old.hasValue != hasValue ||
      old.min != min ||
      old.max != max;
}
