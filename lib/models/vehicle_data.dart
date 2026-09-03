/// Danlite ELM — Vehicle Real-Time Data Model
class VehicleData {
  final double? rpm;
  final double? speed;
  final double? coolantTemp;
  final double? intakeTemp;
  final double? throttle;
  final double? engineLoad;
  final double? fuelLevel;
  final double? fuelPressure;
  final double? maf;
  final double? manifoldPressure;
  final double? timingAdvance;
  final double? batteryVoltage;
  final double? shortFuelTrim;
  final double? longFuelTrim;
  final double? runTime;
  final DateTime timestamp;

  const VehicleData({
    this.rpm,
    this.speed,
    this.coolantTemp,
    this.intakeTemp,
    this.throttle,
    this.engineLoad,
    this.fuelLevel,
    this.fuelPressure,
    this.maf,
    this.manifoldPressure,
    this.timingAdvance,
    this.batteryVoltage,
    this.shortFuelTrim,
    this.longFuelTrim,
    this.runTime,
    required this.timestamp,
  });

  VehicleData copyWith({
    double? rpm,
    double? speed,
    double? coolantTemp,
    double? intakeTemp,
    double? throttle,
    double? engineLoad,
    double? fuelLevel,
    double? fuelPressure,
    double? maf,
    double? manifoldPressure,
    double? timingAdvance,
    double? batteryVoltage,
    double? shortFuelTrim,
    double? longFuelTrim,
    double? runTime,
  }) {
    return VehicleData(
      rpm: rpm ?? this.rpm,
      speed: speed ?? this.speed,
      coolantTemp: coolantTemp ?? this.coolantTemp,
      intakeTemp: intakeTemp ?? this.intakeTemp,
      throttle: throttle ?? this.throttle,
      engineLoad: engineLoad ?? this.engineLoad,
      fuelLevel: fuelLevel ?? this.fuelLevel,
      fuelPressure: fuelPressure ?? this.fuelPressure,
      maf: maf ?? this.maf,
      manifoldPressure: manifoldPressure ?? this.manifoldPressure,
      timingAdvance: timingAdvance ?? this.timingAdvance,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      shortFuelTrim: shortFuelTrim ?? this.shortFuelTrim,
      longFuelTrim: longFuelTrim ?? this.longFuelTrim,
      runTime: runTime ?? this.runTime,
      timestamp: DateTime.now(),
    );
  }

  static VehicleData empty() => VehicleData(timestamp: DateTime.now());

  /// Get value for a specific PID command
  double? valueForPid(String command) {
    switch (command) {
      case '010C': return rpm;
      case '010D': return speed;
      case '0105': return coolantTemp;
      case '010F': return intakeTemp;
      case '0111': return throttle;
      case '0104': return engineLoad;
      case '012F': return fuelLevel;
      case '010A': return fuelPressure;
      case '0110': return maf;
      case '010B': return manifoldPressure;
      case '010E': return timingAdvance;
      case '0142': return batteryVoltage;
      case '0106': return shortFuelTrim;
      case '0107': return longFuelTrim;
      case '011F': return runTime;
      default: return null;
    }
  }
}

/// DTC Fault Code Model
class DtcCode {
  final String code;
  final String description;
  final String possibleCause;
  final String severity;   // critical / high / medium / low / unknown
  final String action;
  final bool isPending;

  // ── Chassis/ABS extensions ────────────────────────────────────────────────
  // All optional with defaults, so every existing engine-code construction
  // site is untouched. They carry the extra columns a manufacturer chassis
  // service table provides, which the generic powertrain path has no analogue
  // for.

  /// Which diagnostic module reported this code — `'engine'` (OBD-II Mode 03
  /// on the functional address) or `'chassis'` (UDS against a physically
  /// addressed ABS/chassis module). Distinct from the code's SAE letter.
  final String module;

  /// Manufacturer's internal "Failure Component" token (e.g. `RFP/RFP_HW`).
  /// Never translated — a technician matches it against the manual verbatim.
  final String component;

  /// Manufacturer's "Query" column: what the fault actually indicates.
  final String query;

  /// Manufacturer's "Remedy" column: the prescribed fix.
  final String remedy;

  /// ISO 14229 failure-type byte, when the code came from a UDS reply
  /// (the `-04` in `C1015-04`). Null for OBD-II Mode 03 codes.
  final int? failureTypeByte;

  /// True when the module reported this code as a confirmed, stored fault
  /// (UDS status bit 3) rather than a single unconfirmed test failure.
  final bool isConfirmed;

  const DtcCode({
    required this.code,
    required this.description,
    required this.possibleCause,
    required this.severity,
    required this.action,
    this.isPending = false,
    this.module = 'engine',
    this.component = '',
    this.query = '',
    this.remedy = '',
    this.failureTypeByte,
    this.isConfirmed = true,
  });

  bool get isChassis => module == 'chassis';
}

/// Connection State
enum ConnectionStatus { disconnected, scanning, connecting, connected, error }

/// Connection Type
enum ConnectionType { wifi, bluetooth }
