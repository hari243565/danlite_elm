/// Danlite ELM — the plain-text history report, built only when the rider
/// taps Share. No VIN (history holds none), no adapter traffic, no device
/// name: date, vehicle make/model as typed, what each read established, and
/// each code with what it means now.
///
/// Pure Dart: strings and meanings come in as functions.
library;

import 'scan_history.dart';

String two(int n) => n.toString().padLeft(2, '0');

/// `2026-10-02 14:05` in the phone's local time.
String formatLocal(DateTime utc) {
  final t = utc.toLocal();
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

String buildHistoryReport(
  List<ScanSession> sessions, {
  required String Function(String key) tr,
  required String Function(ScanFaultRow fault, SessionKind kind) meaning,
}) {
  final b = StringBuffer()
    ..writeln(tr('historyShareHeader'))
    ..writeln();
  for (final s in sessions) {
    if (s.kind == SessionKind.clearCheck) continue; // internal record
    b.write('${formatLocal(s.startedAt)} · ');
    b.write(tr(s.kind == SessionKind.abs ? 'moduleAbs' : 'moduleEngine'));
    final label = (s.vehicleLabel ?? '').trim();
    if (label.isNotEmpty) b.write(' · ${noVin(label)}');
    b.writeln();
    b.writeln('  ${tr('historyReach_${s.reachState}')}');
    if (s.repeatCount > 1) {
      b.writeln('  ${tr('historyRepeat').replaceAll('{n}', '${s.repeatCount}')}');
    }
    if (s.faults.isEmpty) {
      if (s.reachState == 'answered' || s.reachState == 'clean') {
        b.writeln('  ${tr('historyNoCodes')}');
      }
    } else {
      for (final f in s.faults) {
        b.writeln('  ${f.displayCode}: ${meaning(f, s.kind)}');
      }
    }
    b.writeln();
  }
  b.writeln(tr('historyShareFooter'));
  return b.toString();
}
