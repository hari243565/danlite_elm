/// S8, second line of defence: Sentry, configured exactly as the app
/// configures it, never transmits adapter traffic or a VIN — and still
/// reports ordinary errors.
///
/// The real Sentry SDK runs with a capturing transport in place of the HTTP
/// one, so nothing leaves the machine; the test inspects the exact bytes the
/// SDK would have sent.
library;

import 'dart:convert';

import 'package:danlite_elm/services/error_reporting_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'support/engine_sim.dart';

class _CapturingTransport implements Transport {
  _CapturingTransport(this.options);
  final SentryOptions options;
  final List<String> sent = <String>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    final bytes = <int>[];
    await for (final chunk in envelope.envelopeStream(options)) {
      bytes.addAll(chunk);
    }
    sent.add(utf8.decode(bytes, allowMalformed: true));
    return SentryId.newId();
  }
}

const _vin = 'MD2A12AZ5LWB12345';

/// Strings that would only be in a payload if vehicle data leaked.
final _leaks = <String>[
  '43 01 01 33', '430101', 'ELM327', 'ATDPN', 'NO DATA', 'TX>', 'RX<',
  '[WIRE]', 'P0133', _vin,
];

void main() {
  late _CapturingTransport transport;

  setUp(() async {
    await Sentry.init((options) {
      options.dsn = 'https://public@o0.ingest.sentry.io/0';
      ErrorReportingService.applyPrivacyOptions(options);
      transport = _CapturingTransport(options);
      options.transport = transport;
    });
  });

  tearDown(() async => Sentry.close());

  test('the app\'s options switch off print breadcrumbs and PII', () {
    final options = SentryOptions(dsn: 'https://public@o0.ingest.sentry.io/0');
    ErrorReportingService.applyPrivacyOptions(options);
    expect(options.enablePrintBreadcrumbs, isFalse);
    expect(options.sendDefaultPii, isFalse);
    expect(options.beforeBreadcrumb, isNotNull);
    expect(options.beforeSend, isNotNull);
  });

  test('a session that logs traffic leaves nothing in any Sentry payload',
      () async {
    // A real simulated session, so the wire log holds real traffic.
    final sim = EngineSim(mode03: '43 01 01 33');
    final obd = await connectSim(sim);
    await obd.readEngineDtcs();
    final wire = List<String>.of(obd.wireLog);
    expect(wire.any((l) => l.contains('43 01 01 33')), isTrue);

    // Worst case: every wire line offered to Sentry as a breadcrumb, as the
    // print integration used to do, plus a VIN and fault codes.
    for (final line in wire) {
      Sentry.addBreadcrumb(Breadcrumb(message: '[WIRE] $line'));
      Sentry.addBreadcrumb(Breadcrumb(message: line, category: 'console'));
    }
    Sentry.addBreadcrumb(Breadcrumb(message: 'vehicle VIN $_vin'));
    Sentry.addBreadcrumb(Breadcrumb(message: 'codes P0133 U0100'));
    // An ordinary breadcrumb must survive.
    Sentry.addBreadcrumb(Breadcrumb(message: 'navigated to /dtc'));

    // An error whose message quotes a raw reply and a VIN.
    await Sentry.captureException(
        StateError('unexpected reply 7E8 04 43 01 01 33 from $_vin'));

    await obd.disconnect();
    await sim.close();

    expect(transport.sent, hasLength(1));
    final payload = transport.sent.single;
    for (final leak in _leaks) {
      expect(payload.contains(leak), isFalse, reason: 'leaked "$leak"');
    }
    // Still diagnosable: the error type and the ordinary breadcrumb arrive.
    expect(payload, contains('StateError'));
    expect(payload, contains('navigated to /dtc'));
  });

  test('a normal error is still reported unchanged', () async {
    await Sentry.captureException(
        StateError('Supabase session refresh failed: 401'));
    expect(transport.sent, hasLength(1));
    expect(transport.sent.single,
        contains('Supabase session refresh failed: 401'));
  });

  test('scrubber unit checks', () {
    expect(VehicleTrafficScrubber.containsVehicleData('7E8 03 7F 03 22'), isTrue);
    expect(VehicleTrafficScrubber.containsVehicleData('7E8037F0322'), isTrue);
    expect(VehicleTrafficScrubber.containsVehicleData('UNABLE TO CONNECT'), isTrue);
    expect(VehicleTrafficScrubber.containsVehicleData('ATSH7B0'), isTrue);
    expect(VehicleTrafficScrubber.containsVehicleData(_vin), isTrue);
    expect(VehicleTrafficScrubber.containsVehicleData('Connection refused'),
        isFalse);
    expect(VehicleTrafficScrubber.scrubBreadcrumb(Breadcrumb(message: 'RX<41 0C')),
        isNull);
    expect(VehicleTrafficScrubber.mask('code P1100 at $_vin'),
        'code ${VehicleTrafficScrubber.masked} at ${VehicleTrafficScrubber.masked}');
  });
}
