import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../services/obd_service.dart';
import '../providers/settings_provider.dart';

class FuelScreen extends StatefulWidget {
  const FuelScreen({super.key});
  @override
  State<FuelScreen> createState() => _FuelScreenState();
}

class _FuelScreenState extends State<FuelScreen> {
  // Trip computer data
  double _tripDistanceKm = 0;
  double _fuelUsedL      = 0;
  double _tripTimeMin    = 0;
  Timer? _timer;
  bool _tracking = false;

  // Settings
  double _fuelPricePerL = 95.0; // ₹/litre default
  double _tankCapacityL = 45.0;

  // CO2: petrol emits ~2.31 kg/L, diesel ~2.68 kg/L
  double get _co2KgPerL => 2.31;

  double get _mpg {
    if (_fuelUsedL <= 0) return 0;
    return (_tripDistanceKm / 1.609) / (_fuelUsedL * 0.264172);
  }
  double get _lPer100km {
    if (_tripDistanceKm <= 0) return 0;
    return (_fuelUsedL / _tripDistanceKm) * 100;
  }
  double get _fuelCost => _fuelUsedL * _fuelPricePerL;
  double get _co2Kg    => _fuelUsedL * _co2KgPerL;
  double get _rangekm {
    if (_lPer100km <= 0) return 0;
    final remainingL = (_tankCapacityL * (context.read<ObdService>().data.fuelLevel ?? 50) / 100);
    return remainingL / _lPer100km * 100;
  }

  void _startTracking() {
    final obd = context.read<ObdService>();
    setState(() { _tracking = true; _tripDistanceKm = 0; _fuelUsedL = 0; _tripTimeMin = 0; });
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _update());
  }

  void _stopTracking() {
    _timer?.cancel();
    setState(() => _tracking = false);
  }

  void _update() {
    final obd = context.read<ObdService>();
    final speed = obd.data.speed ?? 0;
    // Distance: speed(km/h) × 5sec = km
    final deltaKm = speed * (5 / 3600);
    // Fuel: rough estimate from speed + load
    final load = (obd.data.engineLoad ?? 30) / 100;
    final rpm  = (obd.data.rpm ?? 800) / 1000;
    // Instantaneous consumption estimate: L/h ≈ 0.5 × load × rpm × engine_size
    final lPerH = 0.5 * load * rpm * 1.6; // assuming 1.6L engine
    final deltaL = lPerH * (5 / 3600);
    setState(() {
      _tripDistanceKm += deltaKm;
      _fuelUsedL += deltaL;
      _tripTimeMin += 5 / 60;
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final obd      = context.watch<ObdService>();
    final settings = context.watch<SettingsProvider>();
    final fuel     = obd.data.fuelLevel;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Fuel Economy'),
        backgroundColor: AppColors.navyMid,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Fuel tank visual ──────────────────────────────────────
            _FuelTankWidget(level: fuel ?? 0, rangekm: _rangekm),
            const SizedBox(height: 16),

            // ── Trip computer card ────────────────────────────────────
            _SectionCard(
              title: '🚗 Trip Computer',
              child: Column(children: [
                Row(children: [
                  _MetricTile(label: 'Distance',
                      value: '${_tripDistanceKm.toStringAsFixed(1)} km'),
                  _MetricTile(label: 'Fuel Used',
                      value: '${_fuelUsedL.toStringAsFixed(2)} L'),
                  _MetricTile(label: 'Time',
                      value: '${_tripTimeMin.toStringAsFixed(0)} min'),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _MetricTile(label: settings.useMetric ? 'L/100km' : 'MPG',
                      value: settings.useMetric
                          ? (_lPer100km > 0 ? _lPer100km.toStringAsFixed(1) : '--')
                          : (_mpg > 0 ? _mpg.toStringAsFixed(1) : '--'),
                      highlight: true),
                  _MetricTile(label: 'Fuel Cost',
                      value: '₹${_fuelCost.toStringAsFixed(0)}'),
                  _MetricTile(label: 'CO₂ Emitted',
                      value: '${_co2Kg.toStringAsFixed(2)} kg'),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: ElevatedButton.icon(
                    onPressed: obd.isConnected && !_tracking ? _startTracking : null,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Start Trip'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: _tracking ? _stopTracking : null,
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Stop'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error)),
                  )),
                ]),
              ]),
            ),
            const SizedBox(height: 14),

            // ── Fuel price settings ───────────────────────────────────
            _SectionCard(
              title: '⛽ Fuel Settings',
              child: Column(children: [
                Row(children: [
                  Expanded(child: _SliderTile(
                    label: 'Fuel Price (₹/L)',
                    value: _fuelPricePerL,
                    min: 50, max: 150,
                    displayValue: '₹${_fuelPricePerL.toStringAsFixed(0)}',
                    onChanged: (v) => setState(() => _fuelPricePerL = v),
                  )),
                ]),
                const SizedBox(height: 10),
                _SliderTile(
                  label: 'Tank Capacity (L)',
                  value: _tankCapacityL,
                  min: 20, max: 80,
                  displayValue: '${_tankCapacityL.toStringAsFixed(0)} L',
                  onChanged: (v) => setState(() => _tankCapacityL = v),
                ),
              ]),
            ),
            const SizedBox(height: 14),

            // ── CO2 Emissions summary ─────────────────────────────────
            _SectionCard(
              title: '🌿 CO₂ Emissions',
              child: Column(children: [
                Row(children: [
                  _MetricTile(label: 'This Trip', value: '${_co2Kg.toStringAsFixed(2)} kg'),
                  _MetricTile(label: 'Per 100km',
                      value: '${(_co2KgPerL * _lPer100km).toStringAsFixed(1)} kg'),
                  _MetricTile(label: 'g/km',
                      value: _lPer100km > 0
                          ? '${(_co2KgPerL * _lPer100km * 10).toStringAsFixed(0)} g'
                          : '--'),
                ]),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.bgSecondary,
                    borderRadius: BorderRadius.circular(8)),
                  child: const Text(
                    'Average petrol vehicle emits ~2.31 kg CO₂ per litre. '
                    'EU standard: <130 g/km. Your vehicle\'s rating is estimated from OBD2 data.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5)),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Fuel Tank Widget ──────────────────────────────────────────────────────────
class _FuelTankWidget extends StatelessWidget {
  final double level, rangekm;
  const _FuelTankWidget({required this.level, required this.rangekm});

  Color get _color {
    if (level < 10) return AppColors.error;
    if (level < 25) return AppColors.warning;
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.navyGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        // Tank visual
        Column(children: [
          Container(
            width: 54, height: 100,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white38, width: 2),
              borderRadius: BorderRadius.circular(6)),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 600),
                width: double.infinity,
                height: level.clamp(0, 100),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.8),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Icon(Icons.local_gas_station, color: Colors.white60, size: 18),
        ]),
        const SizedBox(width: 20),
        // Stats
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${level.toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: _color)),
          const Text('Fuel Remaining', style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 10),
          if (rangekm > 0)
            Text('~${rangekm.toStringAsFixed(0)} km range',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        ])),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title; final Widget child;
  const _SectionCard({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
            color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        child,
      ]),
    ),
  );
}

class _MetricTile extends StatelessWidget {
  final String label, value; final bool highlight;
  const _MetricTile({required this.label, required this.value, this.highlight = false});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
          color: highlight ? AppColors.flameOrange : AppColors.textPrimary)),
      const SizedBox(height: 2),
      Text(label, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
    ]),
  );
}

class _SliderTile extends StatelessWidget {
  final String label, displayValue;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  const _SliderTile({required this.label, required this.value,
      required this.min, required this.max, required this.displayValue,
      required this.onChanged});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Text(displayValue, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
            color: AppColors.navyMid)),
      ]),
      Slider(value: value, min: min, max: max, onChanged: onChanged,
          activeColor: AppColors.navyMid, inactiveColor: AppColors.gaugeTrack),
    ],
  );
}
