import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VehicleProfile {
  final String id;
  String name;
  String make;
  String model;
  int year;
  String fuelType;      // petrol / diesel / hybrid / electric
  double engineSizeL;
  int powerBhp;
  double weightKg;
  String vin;
  String notes;
  DateTime createdAt;

  VehicleProfile({
    required this.id,
    required this.name,
    this.make = '',
    this.model = '',
    this.year = 2020,
    this.fuelType = 'petrol',
    this.engineSizeL = 1.6,
    this.powerBhp = 120,
    this.weightKg = 1400,
    this.vin = '',
    this.notes = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get displayName => name.isNotEmpty ? name : '$year $make $model';

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'make': make, 'model': model,
    'year': year, 'fuel': fuelType, 'engL': engineSizeL,
    'bhp': powerBhp, 'wt': weightKg, 'vin': vin, 'notes': notes,
    'ca': createdAt.toIso8601String(),
  };

  factory VehicleProfile.fromJson(Map<String, dynamic> j) => VehicleProfile(
    id: j['id'], name: j['name'] ?? '', make: j['make'] ?? '',
    model: j['model'] ?? '', year: j['year'] ?? 2020,
    fuelType: j['fuel'] ?? 'petrol',
    engineSizeL: (j['engL'] as num?)?.toDouble() ?? 1.6,
    powerBhp: j['bhp'] ?? 120,
    weightKg: (j['wt'] as num?)?.toDouble() ?? 1400,
    vin: j['vin'] ?? '', notes: j['notes'] ?? '',
    createdAt: j['ca'] != null ? DateTime.parse(j['ca']) : DateTime.now(),
  );

  VehicleProfile copyWith({
    String? name, String? make, String? model, int? year,
    String? fuelType, double? engineSizeL, int? powerBhp,
    double? weightKg, String? vin, String? notes,
  }) => VehicleProfile(
    id: id,
    name: name ?? this.name, make: make ?? this.make,
    model: model ?? this.model, year: year ?? this.year,
    fuelType: fuelType ?? this.fuelType,
    engineSizeL: engineSizeL ?? this.engineSizeL,
    powerBhp: powerBhp ?? this.powerBhp,
    weightKg: weightKg ?? this.weightKg,
    vin: vin ?? this.vin, notes: notes ?? this.notes,
    createdAt: createdAt,
  );
}

class VehicleProvider extends ChangeNotifier {
  List<VehicleProfile> _vehicles = [];
  List<VehicleProfile> get vehicles => _vehicles;

  VehicleProfile? _active;
  VehicleProfile? get active => _active;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('vehicles') ?? [];
    _vehicles = raw.map((s) => VehicleProfile.fromJson(jsonDecode(s))).toList();
    final activeId = prefs.getString('activeVehicle');
    if (activeId != null) {
      _active = _vehicles.where((v) => v.id == activeId).firstOrNull;
    }
    if (_vehicles.isEmpty) _addDefault();
    notifyListeners();
  }

  void _addDefault() {
    final def = VehicleProfile(
      id: 'default',
      name: 'My Vehicle',
      make: 'Unknown',
      model: 'Vehicle',
      year: DateTime.now().year,
    );
    _vehicles.add(def);
    _active = def;
  }

  Future<void> addVehicle(VehicleProfile v) async {
    _vehicles.add(v);
    if (_active == null) _active = v;
    await _save();
    notifyListeners();
  }

  Future<void> updateVehicle(VehicleProfile v) async {
    final idx = _vehicles.indexWhere((x) => x.id == v.id);
    if (idx >= 0) _vehicles[idx] = v;
    if (_active?.id == v.id) _active = v;
    await _save();
    notifyListeners();
  }

  Future<void> deleteVehicle(String id) async {
    _vehicles.removeWhere((v) => v.id == id);
    if (_active?.id == id) _active = _vehicles.firstOrNull;
    await _save();
    notifyListeners();
  }

  Future<void> setActive(String id) async {
    _active = _vehicles.where((v) => v.id == id).firstOrNull;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('activeVehicle', id);
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _vehicles.map((v) => jsonEncode(v.toJson())).toList();
    await prefs.setStringList('vehicles', raw);
    if (_active != null) {
      await prefs.setString('activeVehicle', _active!.id);
    }
  }
}
