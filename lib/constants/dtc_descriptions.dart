/// Danlite ELM — DTC (Diagnostic Trouble Code) Database
/// Comprehensive descriptions for P, C, B, U codes
class DtcDatabase {
  DtcDatabase._();

  static const Map<String, Map<String, String>> codes = {

    // ── Powertrain (P) Codes ──────────────────────────────────────────────
    'P0100': {
      'desc': 'Mass or Volume Air Flow Circuit Malfunction',
      'cause': 'Dirty/faulty MAF sensor, air leaks, wiring issue',
      'severity': 'high',
      'action': 'Inspect and clean or replace MAF sensor',
    },
    'P0101': {
      'desc': 'Mass or Volume Air Flow Circuit Range/Performance',
      'cause': 'Air filter clogged, MAF sensor dirty, vacuum leak',
      'severity': 'medium',
      'action': 'Clean MAF sensor, check air filter',
    },
    'P0110': {
      'desc': 'Intake Air Temperature Circuit Malfunction',
      'cause': 'Faulty IAT sensor or wiring',
      'severity': 'low',
      'action': 'Check/replace IAT sensor',
    },
    'P0115': {
      'desc': 'Engine Coolant Temperature Circuit Malfunction',
      'cause': 'Faulty coolant temp sensor or wiring',
      'severity': 'high',
      'action': 'Replace coolant temperature sensor',
    },
    'P0117': {
      'desc': 'Engine Coolant Temperature Circuit Low Input',
      'cause': 'Short to ground in ECT circuit, faulty sensor',
      'severity': 'high',
      'action': 'Test ECT sensor resistance, check wiring',
    },
    'P0118': {
      'desc': 'Engine Coolant Temperature Circuit High Input',
      'cause': 'Open circuit in ECT wiring, faulty sensor',
      'severity': 'high',
      'action': 'Test ECT sensor, inspect wiring harness',
    },
    'P0120': {
      'desc': 'Throttle/Pedal Position Sensor A Circuit Malfunction',
      'cause': 'Faulty TPS, wiring issue, poor connection',
      'severity': 'high',
      'action': 'Check TPS wiring, replace sensor if needed',
    },
    'P0128': {
      'desc': 'Coolant Thermostat (Coolant Temp Below Thermostat Regulating Temp)',
      'cause': 'Thermostat stuck open',
      'severity': 'medium',
      'action': 'Replace thermostat',
    },
    'P0130': {
      'desc': 'O2 Sensor Circuit Malfunction (Bank 1, Sensor 1)',
      'cause': 'Faulty O2 sensor, exhaust leak, wiring issue',
      'severity': 'medium',
      'action': 'Inspect O2 sensor and wiring, check for exhaust leaks',
    },
    'P0171': {
      'desc': 'System Too Lean (Bank 1)',
      'cause': 'Vacuum leak, weak fuel pump, dirty fuel injectors, faulty MAF',
      'severity': 'medium',
      'action': 'Check for vacuum leaks, test fuel pressure, clean injectors',
    },
    'P0172': {
      'desc': 'System Too Rich (Bank 1)',
      'cause': 'Faulty fuel pressure regulator, leaking injectors, faulty MAF',
      'severity': 'medium',
      'action': 'Check fuel pressure, inspect injectors, clean MAF',
    },
    'P0200': {
      'desc': 'Injector Circuit Malfunction',
      'cause': 'Open/short in injector wiring, faulty injector',
      'severity': 'high',
      'action': 'Test injector resistance, check wiring',
    },
    'P0300': {
      'desc': 'Random/Multiple Cylinder Misfire Detected',
      'cause': 'Worn spark plugs, faulty ignition coil, fuel delivery issue',
      'severity': 'high',
      'action': 'Replace spark plugs, check ignition coils and fuel system',
    },
    'P0301': {
      'desc': 'Cylinder 1 Misfire Detected',
      'cause': 'Faulty spark plug, coil, or injector on cylinder 1',
      'severity': 'high',
      'action': 'Replace spark plug and/or coil on cylinder 1',
    },
    'P0302': {
      'desc': 'Cylinder 2 Misfire Detected',
      'cause': 'Faulty spark plug, coil, or injector on cylinder 2',
      'severity': 'high',
      'action': 'Replace spark plug and/or coil on cylinder 2',
    },
    'P0303': {
      'desc': 'Cylinder 3 Misfire Detected',
      'cause': 'Faulty spark plug, coil, or injector on cylinder 3',
      'severity': 'high',
      'action': 'Replace spark plug and/or coil on cylinder 3',
    },
    'P0304': {
      'desc': 'Cylinder 4 Misfire Detected',
      'cause': 'Faulty spark plug, coil, or injector on cylinder 4',
      'severity': 'high',
      'action': 'Replace spark plug and/or coil on cylinder 4',
    },
    'P0340': {
      'desc': 'Camshaft Position Sensor A Circuit Malfunction',
      'cause': 'Faulty cam sensor, wiring issue, timing chain issue',
      'severity': 'high',
      'action': 'Replace camshaft position sensor',
    },
    'P0400': {
      'desc': 'Exhaust Gas Recirculation Flow Malfunction',
      'cause': 'Clogged EGR valve or passages, faulty EGR solenoid',
      'severity': 'medium',
      'action': 'Clean or replace EGR valve',
    },
    'P0420': {
      'desc': 'Catalyst System Efficiency Below Threshold (Bank 1)',
      'cause': 'Failing catalytic converter, faulty O2 sensors',
      'severity': 'medium',
      'action': 'Test O2 sensors, replace catalytic converter if needed',
    },
    'P0440': {
      'desc': 'Evaporative Emission Control System Malfunction',
      'cause': 'Loose or faulty gas cap, leak in EVAP system',
      'severity': 'low',
      'action': 'Tighten fuel cap, inspect EVAP hoses and canister',
    },
    'P0442': {
      'desc': 'Evaporative Emission Control System Leak Detected (Small Leak)',
      'cause': 'Small leak in EVAP system, loose gas cap',
      'severity': 'low',
      'action': 'Check gas cap, inspect EVAP lines',
    },
    'P0455': {
      'desc': 'Evaporative Emission Control System Leak Detected (Large Leak)',
      'cause': 'Missing/faulty gas cap, large EVAP leak',
      'severity': 'medium',
      'action': 'Replace gas cap, pressure-test EVAP system',
    },
    'P0500': {
      'desc': 'Vehicle Speed Sensor Malfunction',
      'cause': 'Faulty VSS, wiring issue, faulty ABS module',
      'severity': 'medium',
      'action': 'Check VSS and wiring, inspect ABS module',
    },
    'P0505': {
      'desc': 'Idle Control System Malfunction',
      'cause': 'Dirty or faulty IAC valve, vacuum leak',
      'severity': 'medium',
      'action': 'Clean or replace IAC valve, check for vacuum leaks',
    },
    'P0600': {
      'desc': 'Serial Communication Link Malfunction',
      'cause': 'ECM/PCM communication failure',
      'severity': 'high',
      'action': 'Check wiring harness and ECM connections',
    },
    'P0700': {
      'desc': 'Transmission Control System Malfunction',
      'cause': 'Faulty TCM, solenoid, or wiring in transmission',
      'severity': 'high',
      'action': 'Scan for specific transmission codes, check TCM',
    },

    // ── Body (B) Codes ────────────────────────────────────────────────────
    'B0001': {
      'desc': 'Driver Frontal Stage 1 Deployment Control',
      'cause': 'Airbag system fault',
      'severity': 'high',
      'action': 'Have airbag system inspected immediately',
    },

    // ── Chassis (C) Codes ─────────────────────────────────────────────────
    'C0035': {
      'desc': 'Left Front Wheel Speed Sensor Circuit Malfunction',
      'cause': 'Faulty wheel speed sensor or wiring',
      'severity': 'high',
      'action': 'Replace wheel speed sensor, check ABS wiring',
    },

    // ── Network (U) Codes ─────────────────────────────────────────────────
    'U0001': {
      'desc': 'High Speed CAN Communication Bus',
      'cause': 'CAN bus wiring fault, faulty module',
      'severity': 'high',
      'action': 'Check CAN bus wiring and module connections',
    },
    'U0100': {
      'desc': 'Lost Communication With ECM/PCM',
      'cause': 'ECM failure, wiring fault',
      'severity': 'critical',
      'action': 'Check ECM power and ground connections',
    },
  };

  static Map<String, String> lookup(String code) {
    return codes[code] ?? {
      'desc': '',
      'cause': '',
      'severity': 'unknown',
      'action': '',
    };
  }

  static String getSeverityLabel(String severity) {
    switch (severity) {
      case 'critical': return '🔴 Critical';
      case 'high':     return '🟠 High';
      case 'medium':   return '🟡 Medium';
      case 'low':      return '🟢 Low';
      default:         return '⚪ Unknown';
    }
  }
}
