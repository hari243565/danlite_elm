import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/settings_provider.dart';
import 'providers/vehicle_provider.dart';
import 'services/bluetooth_classic_service.dart';
import 'services/obd_service.dart';
import 'services/trip_logger.dart';
import 'services/dtc_service.dart';
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

    await DtcLocalizations.init();

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
    final obdService = ObdService(btService);

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<VehicleProvider>.value(value: vehicles),
          ChangeNotifierProvider<TripLogger>.value(value: tripLog),
          ChangeNotifierProvider<BluetoothClassicService>.value(value: btService),
          ChangeNotifierProvider<ObdService>.value(value: obdService),
        ],
        child: const DanliteELMApp(),
      ),
    );
  }, (Object error, StackTrace stack) {
    debugPrint('[FATAL-ZONE] $error');
    debugPrint('[FATAL-ZONE] $stack');
  });
}
