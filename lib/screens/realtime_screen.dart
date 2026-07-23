import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_strings.dart';
import '../services/obd_service.dart';
import '../models/vehicle_data.dart';
import '../widgets/gauge_dial_widget.dart';

// PIDs shown as analog dials in the gauge cluster grid; everything else
// stays in the sensor list below it.
const Set<String> _kGaugeClusterPids = {
  '010C', // RPM
  '010D', // Speed
  '0104', // Engine load
  '0111', // Throttle
  '0105', // Coolant temp
  '010B', // MAP / boost
};

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

class RealtimeScreen extends StatefulWidget {
  const RealtimeScreen({super.key});

  @override
  State<RealtimeScreen> createState() => _RealtimeScreenState();
}

class _RealtimeScreenState extends State<RealtimeScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final obd = context.watch<ObdService>();
    final data = obd.data;

    final List<_SensorItem> sensors = [
      _SensorItem(
        pid: '010C',
        name: context.tr('sensorEngineRpm'),
        value: data.rpm != null ? data.rpm!.toStringAsFixed(0) : '—',
        unit: 'RPM',
        progress: data.rpm != null ? (data.rpm! / 8000) : 0.0,
        color: _RC.neonAmber,
      ),
      _SensorItem(
        pid: '010D',
        name: context.tr('sensorVehicleSpeed'),
        value: data.speed != null ? data.speed!.toStringAsFixed(1) : '—',
        unit: 'km/h',
        progress: data.speed != null ? (data.speed! / 240) : 0.0,
        color: _RC.neonCyan,
      ),
      _SensorItem(
        pid: '0105',
        name: context.tr('sensorCoolantTemp'),
        value: data.coolantTemp != null
            ? data.coolantTemp!.toStringAsFixed(0)
            : '—',
        unit: '°C',
        progress:
            data.coolantTemp != null ? ((data.coolantTemp! + 40) / 170) : 0.0,
        color: _RC.neonAmber,
      ),
      _SensorItem(
        pid: '010F',
        name: context.tr('sensorIntakeTemp'),
        value:
            data.intakeTemp != null ? data.intakeTemp!.toStringAsFixed(0) : '—',
        unit: '°C',
        progress:
            data.intakeTemp != null ? ((data.intakeTemp! + 40) / 140) : 0.0,
        color: _RC.neonCyan,
      ),
      _SensorItem(
        pid: '0111',
        name: context.tr('sensorThrottle'),
        value: data.throttle != null ? data.throttle!.toStringAsFixed(0) : '—',
        unit: '%',
        progress: data.throttle != null ? (data.throttle! / 100) : 0.0,
        color: _RC.neonCyan,
      ),
      _SensorItem(
        pid: '0104',
        name: context.tr('sensorEngineLoad'),
        value:
            data.engineLoad != null ? data.engineLoad!.toStringAsFixed(0) : '—',
        unit: '%',
        progress: data.engineLoad != null ? (data.engineLoad! / 100) : 0.0,
        color: _RC.neonAmber,
      ),
      _SensorItem(
        pid: '0110',
        name: context.tr('sensorMaf'),
        value: data.maf != null ? data.maf!.toStringAsFixed(1) : '—',
        unit: 'g/s',
        progress: data.maf != null ? (data.maf! / 250) : 0.0,
        color: _RC.neonCyan,
      ),
      _SensorItem(
        pid: '012F',
        name: context.tr('sensorFuelLevel'),
        value: data.fuelLevel != null ? data.fuelLevel!.toStringAsFixed(0) : '—',
        unit: '%',
        progress: data.fuelLevel != null ? (data.fuelLevel! / 100) : 0.0,
        color: _RC.neonAmber,
      ),
      _SensorItem(
        pid: '010A',
        name: context.tr('sensorFuelPressure'),
        value: data.fuelPressure != null
            ? data.fuelPressure!.toStringAsFixed(0)
            : '—',
        unit: 'kPa',
        progress: data.fuelPressure != null ? (data.fuelPressure! / 765) : 0.0,
        color: _RC.neonCyan,
      ),
      _SensorItem(
        pid: '010B',
        name: context.tr('sensorMap'),
        value: data.manifoldPressure != null
            ? data.manifoldPressure!.toStringAsFixed(0)
            : '—',
        unit: 'kPa',
        progress:
            data.manifoldPressure != null ? (data.manifoldPressure! / 255) : 0.0,
        color: _RC.neonAmber,
      ),
      _SensorItem(
        pid: '010E',
        name: context.tr('sensorTiming'),
        value: data.timingAdvance != null
            ? data.timingAdvance!.toStringAsFixed(1)
            : '—',
        unit: '°',
        progress: data.timingAdvance != null
            ? ((data.timingAdvance! + 64) / 127.5)
            : 0.0,
        color: _RC.neonCyan,
      ),
      _SensorItem(
        pid: '0142',
        name: context.tr('sensorBattery'),
        value: data.batteryVoltage != null
            ? data.batteryVoltage!.toStringAsFixed(2)
            : '—',
        unit: 'V',
        progress: data.batteryVoltage != null ? (data.batteryVoltage! / 16) : 0.0,
        color: _RC.neonAmber,
      ),
      _SensorItem(
        pid: '0106',
        name: context.tr('sensorShortFuelTrim'),
        value: data.shortFuelTrim != null
            ? data.shortFuelTrim!.toStringAsFixed(1)
            : '—',
        unit: '%',
        progress: data.shortFuelTrim != null
            ? ((data.shortFuelTrim! + 100) / 200)
            : 0.0,
        color: _RC.neonCyan,
      ),
      _SensorItem(
        pid: '0107',
        name: context.tr('sensorLongFuelTrim'),
        value: data.longFuelTrim != null
            ? data.longFuelTrim!.toStringAsFixed(1)
            : '—',
        unit: '%',
        progress: data.longFuelTrim != null
            ? ((data.longFuelTrim! + 100) / 200)
            : 0.0,
        color: _RC.neonAmber,
      ),
      _SensorItem(
        pid: '011F',
        name: context.tr('sensorRunTime'),
        value: data.runTime != null ? data.runTime!.toStringAsFixed(0) : '—',
        unit: 'sec',
        progress: data.runTime != null ? (data.runTime! / 3600) : 0.0,
        color: _RC.neonCyan,
      ),
    ];

    final filteredSensors = sensors.where((sensor) {
      return sensor.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          sensor.pid.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    final gaugeSpecs = <_GaugeSpec>[
      _GaugeSpec(
        label: context.tr('sensorEngineRpm'),
        value: data.rpm,
        min: 0,
        max: 8000,
        unit: 'RPM',
      ),
      _GaugeSpec(
        label: context.tr('sensorVehicleSpeed'),
        value: data.speed,
        min: 0,
        max: 240,
        unit: 'km/h',
      ),
      _GaugeSpec(
        label: context.tr('sensorEngineLoad'),
        value: data.engineLoad,
        min: 0,
        max: 100,
        unit: '%',
      ),
      _GaugeSpec(
        label: context.tr('sensorThrottle'),
        value: data.throttle,
        min: 0,
        max: 100,
        unit: '%',
      ),
      _GaugeSpec(
        label: context.tr('sensorCoolantTemp'),
        value: data.coolantTemp,
        min: 0,
        max: 130,
        unit: '°C',
      ),
      _GaugeSpec(
        label: context.tr('sensorMap'),
        value: data.manifoldPressure,
        min: 0,
        max: 255,
        unit: 'kPa',
      ),
    ];

    final remainingSensors =
        sensors.where((s) => !_kGaugeClusterPids.contains(s.pid)).toList();

    return Scaffold(
      backgroundColor: _RC.bg,
      appBar: AppBar(
        title: Text(context.tr('liveSensorData'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: _RC.surface,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(68),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _RC.border, width: 1)),
            ),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(color: _RC.textMain),
              decoration: InputDecoration(
                hintText: context.tr('searchSensors'),
                hintStyle: const TextStyle(color: _RC.textMuted),
                prefixIcon: const Icon(Icons.search, color: _RC.textMuted),
                filled: true,
                fillColor: _RC.card,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _RC.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _RC.neonCyan)),
              ),
            ),
          ),
        ),
      ),
      body: _searchQuery.isEmpty
          ? CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.84,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 8,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, idx) => _buildGaugeTile(gaugeSpecs[idx]),
                      childCount: gaugeSpecs.length,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      context.tr('sensorsTitle'),
                      style: const TextStyle(
                        color: _RC.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, idx) =>
                          _buildSensorTile(remainingSensors[idx]),
                      childCount: remainingSensors.length,
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: filteredSensors.length,
              itemBuilder: (context, idx) =>
                  _buildSensorTile(filteredSensors[idx]),
            ),
    );
  }

  Widget _buildGaugeTile(_GaugeSpec g) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: _RC.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _RC.border),
      ),
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dialSize = constraints.maxWidth * 0.82;
          return GaugeDialWidget(
            value: g.value,
            min: g.min,
            max: g.max,
            label: g.label,
            unit: g.unit,
            size: dialSize,
          );
        },
      ),
    );
  }

  Widget _buildSensorTile(_SensorItem s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _RC.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _RC.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        style: const TextStyle(
                            color: _RC.textMain,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(s.pid,
                        style: const TextStyle(
                            color: _RC.textMuted,
                            fontSize: 10,
                            fontFamily: 'monospace')),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    s.value,
                    style: TextStyle(
                      color: s.value != '—' ? s.color : _RC.textMuted,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(s.unit,
                        style: const TextStyle(
                            color: _RC.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: s.progress.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: _RC.darkTrack,
              valueColor: AlwaysStoppedAnimation(s.color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorItem {
  final String pid;
  final String name;
  final String value;
  final String unit;
  final double progress;
  final Color color;

  const _SensorItem({
    required this.pid,
    required this.name,
    required this.value,
    required this.unit,
    required this.progress,
    required this.color,
  });
}

class _GaugeSpec {
  final String label;
  final double? value;
  final double min;
  final double max;
  final String unit;

  const _GaugeSpec({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
  });
}
