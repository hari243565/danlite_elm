import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../services/trip_logger.dart';

class TripHistoryScreen extends StatelessWidget {
  const TripHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logger = context.watch<TripLogger>();

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Trip History'),
        backgroundColor: AppColors.navyMid,
        actions: [
          if (logger.isLogging)
            TextButton.icon(
              onPressed: () => logger.stopLogging(),
              icon: const Icon(Icons.stop_circle, color: AppColors.flameGold),
              label: const Text('STOP LOG',
                  style: TextStyle(color: AppColors.flameGold,
                      fontWeight: FontWeight.w700)),
            )
          else
            TextButton.icon(
              onPressed: () => logger.startLogging('My Vehicle'),
              icon: const Icon(Icons.fiber_manual_record, color: AppColors.error),
              label: const Text('RECORD',
                  style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Active logging banner
          if (logger.isLogging)
            Container(
              color: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                const Icon(Icons.fiber_manual_record, color: Colors.white, size: 14),
                const SizedBox(width: 8),
                const Text('Recording trip…',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${logger.currentTrip?.points.length ?? 0} pts',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),

          // Trips list
          Expanded(
            child: logger.trips.isEmpty
                ? _EmptyTrips(isLogging: logger.isLogging)
                : ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: logger.trips.length,
                    itemBuilder: (_, i) => _TripCard(
                      trip: logger.trips[i],
                      stats: logger.statsFor(logger.trips[i]),
                      onDelete: () => logger.deleteTrip(logger.trips[i].id),
                      onExport: () => _exportCsv(context, logger, logger.trips[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context, TripLogger logger, TripRecord trip) async {
    final csv = logger.exportCsv(trip);
    await Clipboard.setData(ClipboardData(text: csv));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trip CSV copied to clipboard! Paste into Excel/Sheets.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}

class _TripCard extends StatelessWidget {
  final TripRecord trip; final TripStats stats;
  final VoidCallback onDelete, onExport;
  const _TripCard({required this.trip, required this.stats,
      required this.onDelete, required this.onExport});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.navyMid.withValues(alpha: 0.07),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: AppColors.navyGradient,
                borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.route, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trip.vehicleName, style: const TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(_formatDate(trip.startTime),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ])),
            // Duration chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.bgSecondary, borderRadius: BorderRadius.circular(8)),
              child: Text(stats.durationFormatted,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: AppColors.navyMid)),
            ),
          ]),
          const SizedBox(height: 14),

          // Stats grid
          Row(children: [
            _StatBox(label: 'Max Speed',
                value: '${stats.maxSpeed.toStringAsFixed(0)} km/h',
                icon: Icons.speed_rounded),
            _StatBox(label: 'Avg Speed',
                value: '${stats.avgSpeed.toStringAsFixed(0)} km/h',
                icon: Icons.trending_flat),
            _StatBox(label: 'Max RPM',
                value: stats.maxRpm.toStringAsFixed(0),
                icon: Icons.rotate_right),
            _StatBox(label: 'Data Points',
                value: stats.pointCount.toString(),
                icon: Icons.analytics_outlined),
          ]),

          if (stats.maxCoolantTemp != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.thermostat, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text('Peak coolant temp: ${stats.maxCoolantTemp!.toStringAsFixed(0)}°C',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ],

          const SizedBox(height: 12),

          // Actions
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Export CSV'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.navyMid,
                  side: const BorderSide(color: AppColors.navyMid)),
            )),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onDelete,
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: const Icon(Icons.delete_outline, size: 18),
            ),
          ]),
        ]),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final d = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][dt.weekday - 1];
    final m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][dt.month - 1];
    return '$d, ${dt.day} $m ${dt.year} · ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }
}

class _StatBox extends StatelessWidget {
  final String label, value; final IconData icon;
  const _StatBox({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Icon(icon, size: 16, color: AppColors.navyMid),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
          color: AppColors.textPrimary)),
      Text(label, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 9, color: AppColors.textSecondary, height: 1.2)),
    ]),
  );
}

class _EmptyTrips extends StatelessWidget {
  final bool isLogging;
  const _EmptyTrips({required this.isLogging});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.route_outlined, size: 80, color: AppColors.textHint),
      const SizedBox(height: 16),
      const Text('No Trips Recorded', style: TextStyle(fontSize: 20,
          fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 8),
      Text(
        isLogging
            ? 'Recording… data will appear when you stop.'
            : 'Tap RECORD above while connected\nto log your next drive.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary, height: 1.5)),
    ]),
  );
}
