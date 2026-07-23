# Danlite ELM — OBD2 Vehicle Diagnostics App
### Flutter · Android & iOS · 23 Indian Languages

---

## 📱 What This App Does

**Danlite ELM** is a professional OBD2 vehicle diagnostics app — a full-featured original build with:

| Feature | Description |
|---|---|
| 🚗 Live Dashboard | Customizable arc gauges for RPM, Speed, Temp, Load, Fuel, Battery |
| ⚠️ Fault Code Reader | Read, diagnose & clear DTC codes with full descriptions |
| ⚡ Performance Testing | 0–60 mph, 0–100 km/h, Quarter Mile timer, Dyno HP estimate |
| ⛽ Fuel Economy | Trip computer, fuel cost, CO₂ emissions, range estimate |
| 📊 Live Graphs | Real-time line charts for any sensor parameter |
| 🔆 HUD Mode | Heads-up display for windscreen projection |
| 🗺️ Trip Logging | Record & export trips as CSV |
| 🚙 Vehicle Profiles | Multiple vehicle management with full specs |
| 🌐 23 Indian Languages | Full UI localisation — switch in Settings |
| 📡 Wi-Fi + Bluetooth | Works with all ELM327 OBD2 adapters |

---

## 🛠️ Setup & Installation

### Prerequisites
- Flutter SDK 3.16+ (stable channel)
- Dart SDK 3.2+
- Android Studio / Xcode
- An ELM327 OBD2 adapter (Wi-Fi recommended for iOS)

### 1. Install dependencies
```bash
cd danlite_elm
flutter pub get
```

### 2. Generate localisations
```bash
flutter gen-l10n
```

### 3. Run on Android
```bash
flutter run -d android
```

### 4. Run on iOS
```bash
cd ios && pod install && cd ..
flutter run -d ios
```

### 5. Build release APK (Android)
```bash
flutter build apk --release --split-per-abi
# Output: build/app/outputs/flutter-apk/
```

### 6. Build iOS Archive
```bash
flutter build ios --release
# Then open Xcode → Product → Archive
```

---

## 📡 Connecting an OBD2 Adapter

### Wi-Fi (works on both Android & iOS ✅)
1. Plug ELM327 Wi-Fi adapter into the car's OBD2 port
2. On your phone: Settings → Wi-Fi → Connect to adapter's hotspot (e.g. "WiFi_OBDII")
3. Open Danlite ELM → Connect → Wi-Fi tab
4. Default IP: `192.168.0.10`, Port: `35000`
5. Tap **Connect via Wi-Fi**

### Bluetooth (Android only)
1. Plug ELM327 BT adapter into OBD2 port
2. Phone Settings → Bluetooth → Pair the adapter (PIN: 1234 or 0000)
3. Open Danlite ELM → Connect → Bluetooth tab

---

## 🌐 Supported Languages (23)

| Language | Code | Script |
|---|---|---|
| English | en | Latin |
| Hindi / हिन्दी | hi | Devanagari |
| Bengali / বাংলা | bn | Bengali |
| Telugu / తెలుగు | te | Telugu |
| Marathi / मराठी | mr | Devanagari |
| Tamil / தமிழ் | ta | Tamil |
| Gujarati / ગુજરાતી | gu | Gujarati |
| Kannada / ಕನ್ನಡ | kn | Kannada |
| Malayalam / മലയാളം | ml | Malayalam |
| Odia / ଓଡ଼ିଆ | or | Odia |
| Punjabi / ਪੰਜਾਬੀ | pa | Gurmukhi |
| Assamese / অসমীয়া | as | Bengali |
| Urdu / اردو | ur | Nastaliq (RTL) |
| Sanskrit / संस्कृतम् | sa | Devanagari |
| Konkani / कोंकणी | kok | Devanagari |
| Kashmiri / كٲشُر | ks | Nastaliq (RTL) |
| Sindhi / سنڌي | sd | Arabic (RTL) |
| Manipuri / ꯃꯤꯇꯩꯂꯣꯟ | mni | Meitei Mayek |
| Bodo / बर' | brx | Devanagari |
| Dogri / डोगरी | doi | Devanagari |
| Maithili / मैथिली | mai | Devanagari |
| Santali / ᱥᱟᱱᱛᱟᱲᱤ | sat | Ol Chiki |
| Nepali / नेपाली | ne | Devanagari |

To switch: **Settings → Language** → pick from list

---

## 📁 Project Structure

```
danlite_elm/
├── lib/
│   ├── main.dart                  # App entry point
│   ├── app.dart                   # Routes & MaterialApp
│   ├── constants/
│   │   ├── app_colors.dart        # Brand color system
│   │   ├── obd_pids.dart          # All OBD2 PIDs + parsers
│   │   └── dtc_descriptions.dart  # DTC fault code database
│   ├── theme/
│   │   └── app_theme.dart         # Full Material 3 theme
│   ├── models/
│   │   └── vehicle_data.dart      # VehicleData, DtcCode models
│   ├── services/
│   │   ├── obd_service.dart       # ELM327 WiFi/BT communication
│   │   └── trip_logger.dart       # Trip recording & CSV export
│   ├── providers/
│   │   ├── settings_provider.dart # Language, units, preferences
│   │   └── vehicle_provider.dart  # Vehicle profile management
│   ├── screens/
│   │   ├── splash_screen.dart     # Animated splash
│   │   ├── home_screen.dart       # Bottom nav hub
│   │   ├── connection_screen.dart # WiFi/BT setup
│   │   ├── dashboard_screen.dart  # Main gauge dashboard
│   │   ├── realtime_screen.dart   # All sensor list
│   │   ├── dtc_screen.dart        # Fault codes
│   │   ├── performance_screen.dart# 0-60, dyno, quarter mile
│   │   ├── fuel_screen.dart       # Fuel economy + trip computer
│   │   ├── graph_screen.dart      # Live charts
│   │   ├── hud_screen.dart        # HUD mode
│   │   ├── settings_screen.dart   # All settings + language
│   │   ├── vehicle_profile_screen.dart
│   │   ├── trip_history_screen.dart
│   │   └── about_screen.dart
│   └── widgets/
│       └── arc_gauge.dart         # Custom arc + linear gauges
├── l10n/                          # 23 language ARB files
│   ├── app_en.arb
│   ├── app_hi.arb
│   └── ... (all 23)
├── android/                       # Android config
├── ios/                           # iOS config
├── l10n.yaml                      # Localisation config
└── pubspec.yaml
```

---

## 🔧 OBD2 Parameters Supported

- Engine RPM (010C)
- Vehicle Speed (010D)
- Coolant Temperature (0105)
- Intake Air Temperature (010F)
- Throttle Position (0111)
- Engine Load (0104)
- Fuel Level (012F)
- Fuel Pressure (010A)
- Mass Air Flow (0110)
- Intake Manifold Pressure (010B)
- Timing Advance (010E)
- Battery Voltage (0142)
- Short/Long Term Fuel Trim (0106/0107)
- Engine Run Time (011F)
- DTC Read (Mode 03) / Clear (Mode 04)
- Emission Readiness (Mode 01 PID 41)

---

## 🎨 Brand Colors (from Danlite ELM logo)

| Element | Color | Hex |
|---|---|---|
| App Background | Soft Light Blue | `#E8F4FD` |
| Primary (Navy) | Deep Navy Blue | `#1E3A6E` |
| Accent (Flame) | Warm Orange | `#E87722` |
| Gold (Flame tip) | Amber Gold | `#F5A623` |

---

## ⚠️ Important Notes

- **iOS Bluetooth**: Classic BT (SPP) is NOT supported on iOS. Use Wi-Fi adapter.
- **Android permissions**: Bluetooth + Location permissions needed on Android 12+.
- **ELM327 version**: Use v1.5 or higher for best compatibility.
- **OBD2 port**: Found under the dashboard, driver's side. Present in all cars made after 2001.

---

## 📝 Version History

| Version | Notes |
|---|---|
| 1.0.0 | Initial release — full feature app with 23 Indian languages |

---

*Built for Danlite ELM · Professional OBD2 Vehicle Diagnostics*
