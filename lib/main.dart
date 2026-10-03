import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/entitlement_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/vehicle_provider.dart';
import 'services/bluetooth_classic_service.dart';
import 'services/error_reporting_service.dart';
import 'services/obd_service.dart';
import 'services/session_recorder.dart';
import 'services/supabase_service.dart';
import 'services/trip_logger.dart';
import 'knowledge/history_recorder.dart';
import 'knowledge/knowledge_service.dart';
import 'app.dart';

void main() {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Surface framework errors instead of letting them render as a blank box.
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('[FATAL] ${details.exceptionAsString()}');
      debugPrint('[FATAL] ${details.stack}');
    };

    // Replace the default grey/black error box with the real error text.
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        color: const Color(0xFF07090E),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SelectableText(
                  'Something went wrong',
                  style: TextStyle(
                    color: Color(0xFFFF6B6B),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  details.exceptionAsString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  '${details.stack}',
                  style: const TextStyle(
                    color: Color(0xFFB0B7C3),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    };

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Initialise providers
    final settings = SettingsProvider();
    await settings.init();
    final vehicles = VehicleProvider();
    await vehicles.init();
    final tripLog = TripLogger();
    await tripLog.init();
    final btService = BluetoothClassicService();

    // ObdService receives BT service via constructor injection
    // Tester-mode recorder: off by default, local file only (S9).
    final recorder = SessionRecorder();
    final obdService = ObdService(btService, recorder: recorder);

    // Fault knowledge store + scan history (fault Phase 1B). Created here,
    // STARTED after runApp (not awaited) so the first screen never waits on
    // the bundled-pack import. The recorder saves every engine and ABS read.
    final knowledge = KnowledgeService.forApp();
    HistoryRecorder(
      obd: obdService,
      knowledge: knowledge,
      vehicle: () => activeVehicleSnapshot(vehicles.active),
    ).attach();

    // Backend auth (Phase 2). Both calls swallow their own failures: a missing
    // or unreachable Supabase config must never stop the diagnostics app from
    // starting, since nothing is gated behind a licence until Phase 8.
    await SupabaseService.instance.init();
    final auth = AuthProvider();
    await auth.init();

    // Entitlement token (Phase 3). After AuthProvider, because it needs the
    // restored session to ask the server anything. Swallows its own failures
    // for the same reason as the two calls above: nothing is gated behind a
    // licence until Phase 8, so an unreachable backend must not stop the app.
    final entitlement = EntitlementProvider();
    await entitlement.init();

    // Error reporting (Phase 9). This wraps the existing runApp call and
    // changes nothing else: when SENTRY_DSN is absent from `.env`,
    // ErrorReportingService.init invokes the appRunner directly, so the app
    // starts exactly as it did before this line existed.
    await ErrorReportingService.init(
      appRunner: () => runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<VehicleProvider>.value(value: vehicles),
            ChangeNotifierProvider<TripLogger>.value(value: tripLog),
            ChangeNotifierProvider<BluetoothClassicService>.value(value: btService),
            ChangeNotifierProvider<ObdService>.value(value: obdService),
            ChangeNotifierProvider<SessionRecorder>.value(value: recorder),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<EntitlementProvider>.value(value: entitlement),
            ChangeNotifierProvider<KnowledgeService?>.value(value: knowledge),
          ],
          child: const DanliteELMApp(),
        ),
      ),
    );
    unawaited(knowledge.start());
  }, (Object error, StackTrace stack) {
    debugPrint('[FATAL-ZONE] $error');
    debugPrint('[FATAL-ZONE] $stack');
  });
}
