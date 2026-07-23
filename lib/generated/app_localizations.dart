import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_as.dart';
import 'app_localizations_bn.dart';
import 'app_localizations_brx.dart';
import 'app_localizations_doi.dart';
import 'app_localizations_en.dart';
import 'app_localizations_gu.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_kn.dart';
import 'app_localizations_kok.dart';
import 'app_localizations_ks.dart';
import 'app_localizations_mai.dart';
import 'app_localizations_ml.dart';
import 'app_localizations_mni.dart';
import 'app_localizations_mr.dart';
import 'app_localizations_ne.dart';
import 'app_localizations_or.dart';
import 'app_localizations_pa.dart';
import 'app_localizations_sa.dart';
import 'app_localizations_sat.dart';
import 'app_localizations_sd.dart';
import 'app_localizations_ta.dart';
import 'app_localizations_te.dart';
import 'app_localizations_ur.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('as'),
    Locale('bn'),
    Locale('brx'),
    Locale('doi'),
    Locale('en'),
    Locale('gu'),
    Locale('hi'),
    Locale('kn'),
    Locale('kok'),
    Locale('ks'),
    Locale('mai'),
    Locale('ml'),
    Locale('mni'),
    Locale('mr'),
    Locale('ne'),
    Locale('or'),
    Locale('pa'),
    Locale('sa'),
    Locale('sat'),
    Locale('sd'),
    Locale('ta'),
    Locale('te'),
    Locale('ur')
  ];

  /// Application name
  ///
  /// In en, this message translates to:
  /// **'OBD Danlite'**
  String get appName;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @liveData.
  ///
  /// In en, this message translates to:
  /// **'Live Data'**
  String get liveData;

  /// No description provided for @faultCodes.
  ///
  /// In en, this message translates to:
  /// **'Fault Codes'**
  String get faultCodes;

  /// No description provided for @performance.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get performance;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connecting;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection Failed'**
  String get connectionFailed;

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not Connected'**
  String get notConnected;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @searchLanguage.
  ///
  /// In en, this message translates to:
  /// **'Search language…'**
  String get searchLanguage;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageChanged.
  ///
  /// In en, this message translates to:
  /// **'Language changed successfully'**
  String get languageChanged;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @rpm.
  ///
  /// In en, this message translates to:
  /// **'RPM'**
  String get rpm;

  /// No description provided for @speed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get speed;

  /// No description provided for @coolantTemp.
  ///
  /// In en, this message translates to:
  /// **'Coolant Temp'**
  String get coolantTemp;

  /// No description provided for @intakeTemp.
  ///
  /// In en, this message translates to:
  /// **'Intake Air Temp'**
  String get intakeTemp;

  /// No description provided for @throttle.
  ///
  /// In en, this message translates to:
  /// **'Throttle'**
  String get throttle;

  /// No description provided for @engineLoad.
  ///
  /// In en, this message translates to:
  /// **'Engine Load'**
  String get engineLoad;

  /// No description provided for @fuelLevel.
  ///
  /// In en, this message translates to:
  /// **'Fuel Level'**
  String get fuelLevel;

  /// No description provided for @fuelPressure.
  ///
  /// In en, this message translates to:
  /// **'Fuel Pressure'**
  String get fuelPressure;

  /// No description provided for @massAirFlow.
  ///
  /// In en, this message translates to:
  /// **'Mass Air Flow'**
  String get massAirFlow;

  /// No description provided for @manifoldPressure.
  ///
  /// In en, this message translates to:
  /// **'Manifold Pressure'**
  String get manifoldPressure;

  /// No description provided for @timingAdvance.
  ///
  /// In en, this message translates to:
  /// **'Timing Advance'**
  String get timingAdvance;

  /// No description provided for @batteryVoltage.
  ///
  /// In en, this message translates to:
  /// **'Battery Voltage'**
  String get batteryVoltage;

  /// No description provided for @readCodes.
  ///
  /// In en, this message translates to:
  /// **'Read Codes'**
  String get readCodes;

  /// No description provided for @clearCodes.
  ///
  /// In en, this message translates to:
  /// **'Clear Codes'**
  String get clearCodes;

  /// No description provided for @noFaultCodes.
  ///
  /// In en, this message translates to:
  /// **'No fault codes found'**
  String get noFaultCodes;

  /// No description provided for @clearAllCodesQ.
  ///
  /// In en, this message translates to:
  /// **'Clear All Fault Codes?'**
  String get clearAllCodesQ;

  /// No description provided for @clearCodesWarning.
  ///
  /// In en, this message translates to:
  /// **'This will erase all stored DTCs and turn off the Check Engine light.'**
  String get clearCodesWarning;

  /// No description provided for @vehicleSpeed.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Speed'**
  String get vehicleSpeed;

  /// No description provided for @engineRpm.
  ///
  /// In en, this message translates to:
  /// **'Engine RPM'**
  String get engineRpm;

  /// No description provided for @connectionType.
  ///
  /// In en, this message translates to:
  /// **'Connection Type'**
  String get connectionType;

  /// No description provided for @wifi.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get wifi;

  /// No description provided for @bluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get bluetooth;

  /// No description provided for @ipAddress.
  ///
  /// In en, this message translates to:
  /// **'Adapter IP Address'**
  String get ipAddress;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @scan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scan;

  /// No description provided for @tripHistory.
  ///
  /// In en, this message translates to:
  /// **'Trip History'**
  String get tripHistory;

  /// No description provided for @startTrip.
  ///
  /// In en, this message translates to:
  /// **'Start Trip'**
  String get startTrip;

  /// No description provided for @stopTrip.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopTrip;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get exportCsv;

  /// No description provided for @noTrips.
  ///
  /// In en, this message translates to:
  /// **'No Trips Recorded'**
  String get noTrips;

  /// No description provided for @recording.
  ///
  /// In en, this message translates to:
  /// **'Recording trip…'**
  String get recording;

  /// No description provided for @vehicleProfiles.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Profiles'**
  String get vehicleProfiles;

  /// No description provided for @addVehicle.
  ///
  /// In en, this message translates to:
  /// **'Add Vehicle'**
  String get addVehicle;

  /// No description provided for @editVehicle.
  ///
  /// In en, this message translates to:
  /// **'Edit Vehicle'**
  String get editVehicle;

  /// No description provided for @deleteVehicle.
  ///
  /// In en, this message translates to:
  /// **'Delete Vehicle?'**
  String get deleteVehicle;

  /// No description provided for @noVehicles.
  ///
  /// In en, this message translates to:
  /// **'No Vehicles Added'**
  String get noVehicles;

  /// No description provided for @setActive.
  ///
  /// In en, this message translates to:
  /// **'Set Active'**
  String get setActive;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get active;

  /// No description provided for @fuelEconomy.
  ///
  /// In en, this message translates to:
  /// **'Fuel Economy'**
  String get fuelEconomy;

  /// No description provided for @fuelRemaining.
  ///
  /// In en, this message translates to:
  /// **'Fuel Remaining'**
  String get fuelRemaining;

  /// No description provided for @range.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get range;

  /// No description provided for @tripDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get tripDistance;

  /// No description provided for @fuelUsed.
  ///
  /// In en, this message translates to:
  /// **'Fuel Used'**
  String get fuelUsed;

  /// No description provided for @tripTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get tripTime;

  /// No description provided for @fuelCost.
  ///
  /// In en, this message translates to:
  /// **'Fuel Cost'**
  String get fuelCost;

  /// No description provided for @co2Emitted.
  ///
  /// In en, this message translates to:
  /// **'CO₂ Emitted'**
  String get co2Emitted;

  /// No description provided for @performanceTests.
  ///
  /// In en, this message translates to:
  /// **'Performance Tests'**
  String get performanceTests;

  /// No description provided for @accelTest.
  ///
  /// In en, this message translates to:
  /// **'Acceleration Test'**
  String get accelTest;

  /// No description provided for @quarterMile.
  ///
  /// In en, this message translates to:
  /// **'Quarter Mile'**
  String get quarterMile;

  /// No description provided for @dyno.
  ///
  /// In en, this message translates to:
  /// **'Dyno'**
  String get dyno;

  /// No description provided for @startTest.
  ///
  /// In en, this message translates to:
  /// **'Start Test'**
  String get startTest;

  /// No description provided for @stopTest.
  ///
  /// In en, this message translates to:
  /// **'Stop Test'**
  String get stopTest;

  /// No description provided for @seconds.
  ///
  /// In en, this message translates to:
  /// **'seconds'**
  String get seconds;

  /// No description provided for @liveGraphs.
  ///
  /// In en, this message translates to:
  /// **'Live Graphs'**
  String get liveGraphs;

  /// No description provided for @hudMode.
  ///
  /// In en, this message translates to:
  /// **'HUD Mode'**
  String get hudMode;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @units.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get units;

  /// No description provided for @metric.
  ///
  /// In en, this message translates to:
  /// **'Metric'**
  String get metric;

  /// No description provided for @imperial.
  ///
  /// In en, this message translates to:
  /// **'Imperial'**
  String get imperial;

  /// No description provided for @alarms.
  ///
  /// In en, this message translates to:
  /// **'Alarms & Warnings'**
  String get alarms;

  /// No description provided for @maxRpmAlarm.
  ///
  /// In en, this message translates to:
  /// **'Max RPM Alarm'**
  String get maxRpmAlarm;

  /// No description provided for @maxCoolantAlarm.
  ///
  /// In en, this message translates to:
  /// **'Max Coolant Temp'**
  String get maxCoolantAlarm;

  /// No description provided for @minFuelAlarm.
  ///
  /// In en, this message translates to:
  /// **'Min Fuel Level'**
  String get minFuelAlarm;

  /// No description provided for @minBatteryAlarm.
  ///
  /// In en, this message translates to:
  /// **'Min Battery Voltage'**
  String get minBatteryAlarm;

  /// No description provided for @adapterSetup.
  ///
  /// In en, this message translates to:
  /// **'Adapter Setup'**
  String get adapterSetup;

  /// No description provided for @vehicleNickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get vehicleNickname;

  /// No description provided for @vehicleMake.
  ///
  /// In en, this message translates to:
  /// **'Make'**
  String get vehicleMake;

  /// No description provided for @vehicleModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get vehicleModel;

  /// No description provided for @vehicleYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get vehicleYear;

  /// No description provided for @fuelType.
  ///
  /// In en, this message translates to:
  /// **'Fuel Type'**
  String get fuelType;

  /// No description provided for @engineSize.
  ///
  /// In en, this message translates to:
  /// **'Engine Size'**
  String get engineSize;

  /// No description provided for @power.
  ///
  /// In en, this message translates to:
  /// **'Power (BHP)'**
  String get power;

  /// No description provided for @weight.
  ///
  /// In en, this message translates to:
  /// **'Weight (kg)'**
  String get weight;

  /// No description provided for @vin.
  ///
  /// In en, this message translates to:
  /// **'VIN'**
  String get vin;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @emissionReadiness.
  ///
  /// In en, this message translates to:
  /// **'Emission Readiness'**
  String get emissionReadiness;

  /// No description provided for @freezeFrame.
  ///
  /// In en, this message translates to:
  /// **'Freeze Frame'**
  String get freezeFrame;

  /// No description provided for @storedCodes.
  ///
  /// In en, this message translates to:
  /// **'Stored'**
  String get storedCodes;

  /// No description provided for @possibleCause.
  ///
  /// In en, this message translates to:
  /// **'Possible Cause'**
  String get possibleCause;

  /// No description provided for @recommendedAction.
  ///
  /// In en, this message translates to:
  /// **'Recommended Action'**
  String get recommendedAction;

  /// No description provided for @customizeGauges.
  ///
  /// In en, this message translates to:
  /// **'Customize Gauges'**
  String get customizeGauges;

  /// No description provided for @dashboardTheme.
  ///
  /// In en, this message translates to:
  /// **'Dashboard Theme'**
  String get dashboardTheme;

  /// No description provided for @lightTheme.
  ///
  /// In en, this message translates to:
  /// **'Light (Default)'**
  String get lightTheme;

  /// No description provided for @sportTheme.
  ///
  /// In en, this message translates to:
  /// **'Sport Red'**
  String get sportTheme;

  /// No description provided for @nightTheme.
  ///
  /// In en, this message translates to:
  /// **'Night Mode'**
  String get nightTheme;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'as',
        'bn',
        'brx',
        'doi',
        'en',
        'gu',
        'hi',
        'kn',
        'kok',
        'ks',
        'mai',
        'ml',
        'mni',
        'mr',
        'ne',
        'or',
        'pa',
        'sa',
        'sat',
        'sd',
        'ta',
        'te',
        'ur'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'as':
      return AppLocalizationsAs();
    case 'bn':
      return AppLocalizationsBn();
    case 'brx':
      return AppLocalizationsBrx();
    case 'doi':
      return AppLocalizationsDoi();
    case 'en':
      return AppLocalizationsEn();
    case 'gu':
      return AppLocalizationsGu();
    case 'hi':
      return AppLocalizationsHi();
    case 'kn':
      return AppLocalizationsKn();
    case 'kok':
      return AppLocalizationsKok();
    case 'ks':
      return AppLocalizationsKs();
    case 'mai':
      return AppLocalizationsMai();
    case 'ml':
      return AppLocalizationsMl();
    case 'mni':
      return AppLocalizationsMni();
    case 'mr':
      return AppLocalizationsMr();
    case 'ne':
      return AppLocalizationsNe();
    case 'or':
      return AppLocalizationsOr();
    case 'pa':
      return AppLocalizationsPa();
    case 'sa':
      return AppLocalizationsSa();
    case 'sat':
      return AppLocalizationsSat();
    case 'sd':
      return AppLocalizationsSd();
    case 'ta':
      return AppLocalizationsTa();
    case 'te':
      return AppLocalizationsTe();
    case 'ur':
      return AppLocalizationsUr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
