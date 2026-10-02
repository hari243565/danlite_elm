/// Replies for the Phase A-4 context reads, for [EngineSim].
///
/// Hand-written from SAE J1979 as published in public references — NOT
/// recorded from a real bike. Every function returns the extra-reply map
/// entries to add to `EngineSim.extra`; a `null` value is a request the bike
/// never answers (silence); `NO DATA` is the adapter saying nothing answered.
library;

/// `payload` (service byte first) framed as one CAN single frame from the
/// engine ECU: 11-bit (`7E8`) or 29-bit (`18 DA F1 10`).
String frame(String payload, {bool can29 = false}) {
  final n = payload.trim().split(RegExp(r'\s+')).length;
  final len = n.toRadixString(16).padLeft(2, '0').toUpperCase();
  return can29 ? '18 DA F1 10 $len $payload' : '7E8 $len $payload';
}

/// A bike with a Mode 02 snapshot: the trigger code's two bytes, a support
/// list covering the brief's fixed set, and a value for each. [only] limits
/// the values the bike keeps (and so its support list); [replies] overrides
/// individual requests (e.g. `'020500': null` for a value that never answers).
Map<String, String?> snapshotBike({
  String trigger = '03 01', // P0301
  bool can29 = false,
  Set<int>? only,
  Map<String, String?> replies = const <String, String?>{},
}) {
  String f(String p) => frame(p, can29: can29);

  // Value replies (data after the frame byte), keyed by PID.
  const data = <int, String>{
    0x03: '02 00', // closed loop
    0x04: '80', // 50.2 %
    0x05: '7B', // 83 °C
    0x06: '90', // +12.5 %
    0x07: '80', // 0 %
    0x0B: '63', // 99 kPa
    0x0C: '0F A0', // 1000 RPM
    0x0D: '3C', // 60 km/h
    0x0F: '41', // 25 °C
    0x11: 'FF', // 100 %
    0x42: '36 B0', // 14.0 V
  };
  final kept = <int>{for (final p in data.keys) if (only == null || only.contains(p)) p};

  // Support lists: PID n lives in block (n-1)~/32 at bit (n-1)%32, MSB first.
  List<int> mask(int base) {
    final b = List<int>.filled(4, 0);
    for (final p in kept) {
      if (p <= base || p > base + 32) continue;
      final i = p - base - 1;
      b[i ~/ 8] |= 0x80 >> (i % 8);
    }
    // PID 0x20 (bit 32 of block 0) says the next block's list exists.
    if (base == 0 && kept.any((p) => p > 0x20)) b[3] |= 0x01;
    return b;
  }

  String hex(List<int> bytes) => bytes
      .map((x) => x.toRadixString(16).toUpperCase().padLeft(2, '0'))
      .join(' ');

  final out = <String, String?>{
    '020200': f('42 02 00 $trigger'),
    '020000': f('42 00 00 ${hex(mask(0))}'),
    '024000': f('42 40 00 ${hex(mask(0x40))}'),
    for (final e in data.entries)
      '02${e.key.toRadixString(16).toUpperCase().padLeft(2, '0')}00':
          f('42 ${e.key.toRadixString(16).toUpperCase().padLeft(2, '0')} 00 ${e.value}'),
  };
  out.addAll(replies);
  return out;
}

/// A bike with no snapshot stored: PID 02 answers `0000`.
Map<String, String?> noSnapshotBike({bool can29 = false}) => <String, String?>{
      '020200': frame('42 02 00 00 00', can29: can29),
    };

/// A bike that does not do Mode 02 at all: everything is `NO DATA`.
Map<String, String?> mode02Unsupported() => <String, String?>{
      '020200': 'NO DATA',
      '020000': 'NO DATA',
      '024000': 'NO DATA',
    };

/// Mode 01 context PIDs: lamp/self-checks and the five counters.
///
///  * `0101`: lamp on, 3 codes; spark ignition; misfire / fuel / components
///    supported and complete; catalyst, evaporative, O2 sensor, O2 heater and
///    EGR supported — evaporative NOT complete.
///  * `0121` 120 km lamp distance, `0131` 480 km since cleared, `014D` 95 min
///    lamp time, `014E` 310 min since cleared, `0130` 7 warm-ups.
Map<String, String?> contextBike({
  bool can29 = false,
  Map<String, String?> replies = const <String, String?>{},
}) {
  String f(String p) => frame(p, can29: can29);
  return <String, String?>{
    '0101': f('41 01 83 07 E5 04'),
    '0121': f('41 21 00 78'),
    '0131': f('41 31 01 E0'),
    '014D': f('41 4D 00 5F'),
    '014E': f('41 4E 01 36'),
    '0130': f('41 30 07'),
    ...replies,
  };
}

/// The commands the context reads send (so a test can look for them on the
/// wire): every Mode 02 request, PID 01 01 and the five counters.
bool isContextCommand(String c) {
  final u = c.trim().toUpperCase();
  return u.startsWith('02') ||
      const {'0101', '0121', '0131', '014D', '014E', '0130'}.contains(u);
}
