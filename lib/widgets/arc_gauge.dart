import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Danlite ELM — Arc Gauge Widget
/// Premium semicircular gauge with animated needle, color zones, digital readout
class ArcGauge extends StatefulWidget {
  final double? value;
  final double min;
  final double max;
  final String label;
  final String unit;
  final double? warningThreshold;
  final double? criticalThreshold;
  final double size;
  final bool showDigital;

  const ArcGauge({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.unit,
    this.warningThreshold,
    this.criticalThreshold,
    this.size = 180,
    this.showDigital = true,
  });

  @override
  State<ArcGauge> createState() => _ArcGaugeState();
}

class _ArcGaugeState extends State<ArcGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _prevValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(ArcGauge old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && widget.value != null) {
      _animation = Tween<double>(
        begin: _prevValue,
        end: widget.value!.clamp(widget.min, widget.max),
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
      _controller.forward(from: 0);
      _prevValue = widget.value!.clamp(widget.min, widget.max);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getValueColor(double? value) {
    if (value == null) return AppColors.gaugeTrack;
    if (widget.criticalThreshold != null && value >= widget.criticalThreshold!) {
      return AppColors.gaugeRed;
    }
    if (widget.warningThreshold != null && value >= widget.warningThreshold!) {
      return AppColors.gaugeOrange;
    }
    return AppColors.gaugeGreen;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final animValue = widget.value == null ? null : _animation.value;
        final valueColor = _getValueColor(widget.value);

        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(widget.size * 0.12),
            boxShadow: [
              BoxShadow(
                color: AppColors.navyMid.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                // ── Gauge Arc ─────────────────────────────────────────────
                Expanded(
                  child: CustomPaint(
                    painter: _ArcGaugePainter(
                      value: animValue,
                      min: widget.min,
                      max: widget.max,
                      valueColor: valueColor,
                      warningThreshold: widget.warningThreshold,
                      criticalThreshold: widget.criticalThreshold,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Digital readout
                          if (widget.showDigital) ...[
                            Text(
                              animValue != null
                                ? animValue.toStringAsFixed(
                                    widget.unit == 'RPM' ? 0 : 1)
                                : '--',
                              style: TextStyle(
                                fontSize: widget.size * 0.16,
                                fontWeight: FontWeight.w800,
                                color: valueColor,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              widget.unit,
                              style: TextStyle(
                                fontSize: widget.size * 0.085,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          SizedBox(height: widget.size * 0.05),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Label ────────────────────────────────────────────────
                const SizedBox(height: 4),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: widget.size * 0.085,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ArcGaugePainter extends CustomPainter {
  final double? value;
  final double min;
  final double max;
  final Color valueColor;
  final double? warningThreshold;
  final double? criticalThreshold;

  _ArcGaugePainter({
    required this.value,
    required this.min,
    required this.max,
    required this.valueColor,
    this.warningThreshold,
    this.criticalThreshold,
  });

  static const double _startAngle = 150 * math.pi / 180;  // 7 o'clock
  static const double _sweepAngle = 240 * math.pi / 180;  // 240° sweep

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.58);
    final radius = math.min(size.width, size.height * 1.1) * 0.42;
    final strokeW = radius * 0.18;

    // ── Background track ──────────────────────────────────────────────────
    final trackPaint = Paint()
      ..color = AppColors.gaugeTrack
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepAngle,
      false,
      trackPaint,
    );

    // ── Colored zones ─────────────────────────────────────────────────────
    if (warningThreshold != null) {
      // Green zone
      final greenSweep = _sweepAngle * (warningThreshold! - min) / (max - min);
      final greenPaint = Paint()
        ..color = AppColors.gaugeGreen.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW * 0.3
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        _startAngle,
        greenSweep,
        false,
        greenPaint,
      );

      // Orange zone
      if (criticalThreshold != null) {
        final orangeStart = _startAngle + greenSweep;
        final orangeSweep = _sweepAngle *
            (criticalThreshold! - warningThreshold!) / (max - min);
        final orangePaint = Paint()
          ..color = AppColors.gaugeOrange.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW * 0.3
          ..strokeCap = StrokeCap.butt;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          orangeStart,
          orangeSweep,
          false,
          orangePaint,
        );

        // Red zone
        final redStart = orangeStart + orangeSweep;
        final redSweep = _sweepAngle - greenSweep - orangeSweep;
        final redPaint = Paint()
          ..color = AppColors.gaugeRed.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW * 0.3
          ..strokeCap = StrokeCap.butt;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          redStart,
          redSweep,
          false,
          redPaint,
        );
      }
    }

    // ── Value arc ─────────────────────────────────────────────────────────
    if (value != null) {
      final clampedVal = value!.clamp(min, max);
      final valueSweep = _sweepAngle * (clampedVal - min) / (max - min);

      final valuePaint = Paint()
        ..color = valueColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        _startAngle,
        valueSweep,
        false,
        valuePaint,
      );

      // ── Needle dot ───────────────────────────────────────────────────────
      final needleAngle = _startAngle + valueSweep;
      final needleX = center.dx + radius * math.cos(needleAngle);
      final needleY = center.dy + radius * math.sin(needleAngle);

      final needlePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(needleX, needleY), strokeW * 0.55, needlePaint);

      final needleBorderPaint = Paint()
        ..color = valueColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(
          Offset(needleX, needleY), strokeW * 0.55, needleBorderPaint);
    }

    // ── Min/Max labels ────────────────────────────────────────────────────
    _drawLabel(canvas, center, radius, strokeW,
        _startAngle, min.toInt().toString(), const Offset(-1, 1));
    _drawLabel(canvas, center, radius, strokeW,
        _startAngle + _sweepAngle, max.toInt().toString(), const Offset(1, 1));
  }

  void _drawLabel(Canvas canvas, Offset center, double radius, double strokeW,
      double angle, String text, Offset direction) {
    final labelRadius = radius + strokeW * 1.1;
    final x = center.dx + labelRadius * math.cos(angle);
    final y = center.dy + labelRadius * math.sin(angle);

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: AppColors.textHint,
          fontSize: radius * 0.18,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas,
        Offset(x - tp.width / 2, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(_ArcGaugePainter old) =>
      old.value != value || old.valueColor != valueColor;
}

/// ── Linear/Bar Gauge (for fuel, battery) ───────────────────────────────────
class LinearGauge extends StatelessWidget {
  final double? value;
  final double min;
  final double max;
  final String label;
  final String unit;
  final Color? color;
  final bool reversed; // true = low is bad (fuel)

  const LinearGauge({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.unit,
    this.color,
    this.reversed = false,
  });

  Color _barColor(double fraction) {
    if (reversed) {
      if (fraction < 0.15) return AppColors.gaugeRed;
      if (fraction < 0.30) return AppColors.gaugeOrange;
      return color ?? AppColors.gaugeGreen;
    }
    if (fraction > 0.85) return AppColors.gaugeRed;
    if (fraction > 0.70) return AppColors.gaugeOrange;
    return color ?? AppColors.gaugeGreen;
  }

  @override
  Widget build(BuildContext context) {
    final fraction = value != null
        ? ((value! - min) / (max - min)).clamp(0.0, 1.0)
        : 0.0;
    final barColor = _barColor(fraction);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.navyMid.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  )),
              Text(
                value != null
                    ? '${value!.toStringAsFixed(1)} $unit'
                    : '-- $unit',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: barColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              backgroundColor: AppColors.gaugeTrack,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}
