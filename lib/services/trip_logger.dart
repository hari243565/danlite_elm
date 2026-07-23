import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vehicle_data.dart';

/// Danlite ELM — Trip Logger
/// Records GPS + OBD data per trip, exports CSV/KML
class TripLogger extends ChangeNotifier {
  List<TripRecord> _trips = [];
  List<TripRecord> get trips => _trips;

  TripRecord? _currentTrip;
  TripRecord? get currentTrip => _currentTrip;

  bool get isLogging => _currentTrip != null;

  // Data points logged in current session
  final List<LogPoint> _currentPoints = [];


  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    await _loadTrips();
  }

  // ── Start / Stop Logging ──────────────────────────────────────────────────
  void startLogging(String vehicleName) {
    _currentTrip = TripRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      vehicleName: vehicleName,
      startTime: DateTime.now(),
      points: [],
    );
    _currentPoints.clear();
    notifyListeners();
  }

  void logPoint(VehicleData data, {double? lat, double? lng, double? altitude}) {
    if (!isLogging) return;
    _currentPoints.add(LogPoint(
      timestamp: DateTime.now(),
      rpm: data.rpm,
      speed: data.speed,
      coolantTemp: data.coolantTemp,
      throttle: data.throttle,
      engineLoad: data.engineLoad,
      fuelLevel: data.fuelLevel,
      batteryVoltage: data.batteryVoltage,
      lat: lat,
      lng: lng,
      altitude: altitude,
    ));
  }

  Future<TripRecord?> stopLogging() async {
    if (_currentTrip == null) return null;

    final trip = _currentTrip!.copyWith(
      endTime: DateTime.now(),
      points: List.from(_currentPoints),
    );

    _trips.insert(0, trip);
    _currentTrip = null;
    _currentPoints.clear();

    await _saveTrips();
    notifyListeners();
    return trip;
  }

  // ── Export CSV ────────────────────────────────────────────────────────────
  String exportCsv(TripRecord trip) {
    final sb = StringBuffer();
    sb.writeln('Timestamp,Speed(km/h),RPM,Coolant(°C),Throttle(%),Load(%),Fuel(%),Battery(V),Lat,Lng');
    for (final p in trip.points) {
      sb.writeln([
        p.timestamp.toIso8601String(),
        p.speed?.toStringAsFixed(1) ?? '',
        p.rpm?.toStringAsFixed(0) ?? '',
        p.coolantTemp?.toStringAsFixed(1) ?? '',
        p.throttle?.toStringAsFixed(1) ?? '',
        p.engineLoad?.toStringAsFixed(1) ?? '',
        p.fuelLevel?.toStringAsFixed(1) ?? '',
        p.batteryVoltage?.toStringAsFixed(2) ?? '',
        p.lat?.toStringAsFixed(6) ?? '',
        p.lng?.toStringAsFixed(6) ?? '',
      ].join(','));
    }
    return sb.toString();
  }

  // ── Statistics ────────────────────────────────────────────────────────────
  TripStats statsFor(TripRecord trip) {
    if (trip.points.isEmpty) return TripStats.empty();
    double maxSpeed = 0, maxRpm = 0, avgSpeed = 0, maxCoolant = -999;
    int count = 0;
    for (final p in trip.points) {
      if (p.speed != null) {
        if (p.speed! > maxSpeed) maxSpeed = p.speed!;
        avgSpeed += p.speed!;
        count++;
      }
      if (p.rpm != null && p.rpm! > maxRpm) maxRpm = p.rpm!;
      if (p.coolantTemp != null && p.coolantTemp! > maxCoolant) {
        maxCoolant = p.coolantTemp!;
      }
    }
    return TripStats(
      maxSpeed: maxSpeed,
      maxRpm: maxRpm,
      avgSpeed: count > 0 ? avgSpeed / count : 0,
      maxCoolantTemp: maxCoolant == -999 ? null : maxCoolant,
      durationSec: trip.endTime != null
          ? trip.endTime!.difference(trip.startTime).inSeconds
          : 0,
      pointCount: trip.points.length,
    );
  }

  // ── Persistence ───────────────────────────────────────────────────────────
  Future<void> _saveTrips() async {
    final prefs = await SharedPreferences.getInstance();
    // Save last 50 trips max
    final toSave = _trips.take(50).map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList('trips', toSave);
  }

  Future<void> _loadTrips() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('trips') ?? [];
      _trips = raw
          .map((s) => TripRecord.fromJson(jsonDecode(s)))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('[TripLogger] Load error: $e');
    }
  }

  Future<void> deleteTrip(String id) async {
    _trips.removeWhere((t) => t.id == id);
    await _saveTrips();
    notifyListeners();
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

class LogPoint {
  final DateTime timestamp;
  final double? rpm, speed, coolantTemp, throttle, engineLoad, fuelLevel, batteryVoltage;
  final double? lat, lng, altitude;

  LogPoint({
    required this.timestamp,
    this.rpm, this.speed, this.coolantTemp, this.throttle,
    this.engineLoad, this.fuelLevel, this.batteryVoltage,
    this.lat, this.lng, this.altitude,
  });

  Map<String, dynamic> toJson() => {
    'ts': timestamp.toIso8601String(),
    'rpm': rpm, 'spd': speed, 'ct': coolantTemp,
    'thr': throttle, 'el': engineLoad, 'fl': fuelLevel,
    'bv': batteryVoltage, 'lat': lat, 'lng': lng, 'alt': altitude,
  };

  factory LogPoint.fromJson(Map<String, dynamic> j) => LogPoint(
    timestamp: DateTime.parse(j['ts']),
    rpm: (j['rpm'] as num?)?.toDouble(),
    speed: (j['spd'] as num?)?.toDouble(),
    coolantTemp: (j['ct'] as num?)?.toDouble(),
    throttle: (j['thr'] as num?)?.toDouble(),
    engineLoad: (j['el'] as num?)?.toDouble(),
    fuelLevel: (j['fl'] as num?)?.toDouble(),
    batteryVoltage: (j['bv'] as num?)?.toDouble(),
    lat: (j['lat'] as num?)?.toDouble(),
    lng: (j['lng'] as num?)?.toDouble(),
    altitude: (j['alt'] as num?)?.toDouble(),
  );
}

class TripRecord {
  final String id;
  final String vehicleName;
  final DateTime startTime;
  final DateTime? endTime;
  final List<LogPoint> points;

  TripRecord({
    required this.id,
    required this.vehicleName,
    required this.startTime,
    this.endTime,
    required this.points,
  });

  TripRecord copyWith({DateTime? endTime, List<LogPoint>? points}) => TripRecord(
    id: id, vehicleName: vehicleName, startTime: startTime,
    endTime: endTime ?? this.endTime,
    points: points ?? this.points,
  );

  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);

  Map<String, dynamic> toJson() => {
    'id': id, 'vn': vehicleName,
    'st': startTime.toIso8601String(),
    'et': endTime?.toIso8601String(),
    'pts': points.map((p) => p.toJson()).toList(),
  };

  factory TripRecord.fromJson(Map<String, dynamic> j) => TripRecord(
    id: j['id'], vehicleName: j['vn'],
    startTime: DateTime.parse(j['st']),
    endTime: j['et'] != null ? DateTime.parse(j['et']) : null,
    points: (j['pts'] as List? ?? []).map((p) => LogPoint.fromJson(p)).toList(),
  );
}

class TripStats {
  final double maxSpeed, maxRpm, avgSpeed;
  final double? maxCoolantTemp;
  final int durationSec, pointCount;

  TripStats({
    required this.maxSpeed, required this.maxRpm, required this.avgSpeed,
    this.maxCoolantTemp, required this.durationSec, required this.pointCount,
  });

  factory TripStats.empty() => TripStats(
    maxSpeed: 0, maxRpm: 0, avgSpeed: 0, durationSec: 0, pointCount: 0,
  );

  String get durationFormatted {
    final h = durationSec ~/ 3600;
    final m = (durationSec % 3600) ~/ 60;
    final s = durationSec % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s}s';
  }
}
