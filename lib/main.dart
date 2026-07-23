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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
}
