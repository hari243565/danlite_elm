import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  static const Color neonGreen = Color(0xFF00E39C);
}

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  static const double _stopThreshold = 100.0; // km/h — timer stops here
  static const double _rearmThreshold = 1.0; // km/h — must coast below this to re-arm

  bool _armed = true; // watching for the next speed > 0 crossing
  bool _running = false;
  bool _awaitingRearm = false; // just finished — waiting for the car to stop before re-arming
  DateTime? _startTime;
  double _elapsed = 0;
  double? _lastResultSeconds;
  double? _bestResultSeconds;
  Timer? _tickTimer;
  ObdService? _obd;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    _tickTimer?.cancel();
    super.dispose();
  }

  void _onObdData() {
    final obd = _obd;
    if (obd == null) return;

    if (!obd.isConnected) {
      _abort();
      return;
    }

    final speed = obd.data.speed ?? 0.0;

    if (_awaitingRearm) {
      if (speed <= _rearmThreshold) {
        setState(() {
          _awaitingRearm = false;
          _armed = true;
        });
      }
      return;
    }

    if (_armed && !_running && speed > 0) {
      _startRun();
      return;
    }
    if (_running && speed >= _stopThreshold) {
      _stopRun();
      return;
    }
  }

  void _startRun() {
    _startTime = DateTime.now();
    setState(() {
      _running = true;
      _armed = false;
      _elapsed = 0;
    });
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      final start = _startTime;
      if (!mounted || start == null) return;
      setState(() => _elapsed = DateTime.now().difference(start).inMilliseconds / 1000.0);
    });
  }

  void _stopRun() {
    _tickTimer?.cancel();
    final start = _startTime;
    final result = start != null
        ? DateTime.now().difference(start).inMilliseconds / 1000.0
        : _elapsed;
    setState(() {
      _running = false;
      _elapsed = result;
      _lastResultSeconds = result;
      if (_bestResultSeconds == null || result < _bestResultSeconds!) {
        _bestResultSeconds = result;
      }
      _awaitingRearm = true;
    });
  }

  void _abort() {
    if (!_running && !_awaitingRearm) return;
    _tickTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _running = false;
      _armed = true;
      _awaitingRearm = false;
      _elapsed = 0;
      _startTime = null;
    });
  }

  void _manualReset() {
    _tickTimer?.cancel();
    setState(() {
      _running = false;
      _armed = true;
      _awaitingRearm = false;
      _elapsed = 0;
      _startTime = null;
      _lastResultSeconds = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final obd = context.watch<ObdService>();

    return Scaffold(
      backgroundColor: _RC.bg,
      appBar: AppBar(
        backgroundColor: _RC.surface,
        elevation: 0,
        title: const Text('0-60 Sprint Timer',
            style: TextStyle(color: _RC.textMain, fontWeight: FontWeight.w800)),
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
              child: const Icon(Icons.timer_off_rounded, size: 48, color: _RC.textMuted),
            ),
            const SizedBox(height: 20),
            const Text('ADAPTER NOT CONNECTED',
                style: TextStyle(
                    color: _RC.textMain,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 1.2)),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Connect your ELM327 adapter to run the sprint timer.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _RC.textMuted, fontSize: 13),
              ),
            ),
          ],
        ),
      );

  Widget _buildConnected(ObdService obd) {
    final speed = obd.data.speed ?? 0.0;
    final progress = (speed / _stopThreshold).clamp(0.0, 1.0);

    String statusLabel;
    Color statusColor;
    if (_running) {
      statusLabel = 'RUNNING';
      statusColor = _RC.neonAmber;
    } else if (_awaitingRearm) {
      statusLabel = 'COMPLETE · COAST TO 0 TO RE-ARM';
      statusColor = _RC.neonGreen;
    } else {
      statusLabel = 'ARMED · WAITING FOR LAUNCH';
      statusColor = _RC.neonCyan;
    }

    final displayValue = _running ? _elapsed : (_lastResultSeconds ?? 0.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 30),
            decoration: BoxDecoration(
              color: _RC.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                    color: statusColor.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                      ),
                      const SizedBox(width: 6),
                      Text(statusLabel,
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8)),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  displayValue.toStringAsFixed(2),
                  style: const TextStyle(
                      color: _RC.textMain,
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace'),
                ),
                const Text('SECONDS',
                    style: TextStyle(color: _RC.textMuted, fontSize: 12, letterSpacing: 2)),
                const SizedBox(height: 20),
                Text('${speed.toStringAsFixed(0)} km/h',
                    style: const TextStyle(
                        color: _RC.textMain, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: _RC.darkTrack,
                      valueColor: AlwaysStoppedAnimation(statusColor),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text('0 → 100 km/h', style: TextStyle(color: _RC.textMuted, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _resultCard('LAST RUN', _lastResultSeconds)),
              const SizedBox(width: 12),
              Expanded(child: _resultCard('BEST RUN', _bestResultSeconds)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _manualReset,
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: const Text('Reset Timer', style: TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _RC.textMain,
                side: const BorderSide(color: _RC.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: _RC.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _RC.border)),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How it works',
                    style: TextStyle(
                        color: _RC.textMain, fontSize: 13, fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text(
                  'The timer arms automatically. It starts the instant vehicle speed rises '
                  'above 0 km/h and stops the instant speed reaches 100 km/h. Coast back to '
                  'a stop to re-arm for another run, or tap Reset to clear results.',
                  style: TextStyle(color: _RC.textMuted, fontSize: 12, height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(String label, double? value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
            color: _RC.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _RC.border)),
        child: Column(
          children: [
            Text(value != null ? '${value.toStringAsFixed(2)}s' : '—',
                style: const TextStyle(
                    color: _RC.neonAmber,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace')),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    color: _RC.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ],
        ),
      );
}
