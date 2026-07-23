import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Danlite ELM — Settings Provider
/// Manages language, units, and all user preferences
class SettingsProvider extends ChangeNotifier {

  // ── Language ──────────────────────────────────────────────────────────────
  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  // ── Units ─────────────────────────────────────────────────────────────────
  bool _useMetric = true;
  bool get useMetric => _useMetric;

  // ── WiFi Settings ─────────────────────────────────────────────────────────
  String _wifiIp   = '192.168.0.10';
  int    _wifiPort = 35000;
  String get wifiIp   => _wifiIp;
  int    get wifiPort => _wifiPort;

  // ── Dashboard Layout ──────────────────────────────────────────────────────
  List<String> _dashboardPids = ['010C', '010D', '0105', '0111'];
  List<String> get dashboardPids => _dashboardPids;

  // ── Supported Languages ───────────────────────────────────────────────────
  static const List<LanguageOption> supportedLanguages = [
    LanguageOption('en',  'English',               'English'),
    LanguageOption('hi',  'Hindi',                 'हिन्दी'),
    LanguageOption('bn',  'Bengali',               'বাংলা'),
    LanguageOption('te',  'Telugu',                'తెలుగు'),
    LanguageOption('mr',  'Marathi',               'मराठी'),
    LanguageOption('ta',  'Tamil',                 'தமிழ்'),
    LanguageOption('gu',  'Gujarati',              'ગુજરાતી'),
    LanguageOption('kn',  'Kannada',               'ಕನ್ನಡ'),
    LanguageOption('ml',  'Malayalam',             'മലയാളം'),
    LanguageOption('or',  'Odia',                  'ଓଡ଼ିଆ'),
    LanguageOption('pa',  'Punjabi',               'ਪੰਜਾਬੀ'),
    LanguageOption('as',  'Assamese',              'অসমীয়া'),
    LanguageOption('ur',  'Urdu',                  'اردو'),
    LanguageOption('sa',  'Sanskrit',              'संस्कृतम्'),
    LanguageOption('kok', 'Konkani',               'कोंकणी'),
    LanguageOption('ks',  'Kashmiri',              'كٲشُر'),
    LanguageOption('sd',  'Sindhi',                'سنڌي'),
    LanguageOption('mni', 'Manipuri',              'ꯃꯤꯇꯩꯂꯣꯟ'),
    LanguageOption('brx', 'Bodo',                  'बर\''),
    LanguageOption('doi', 'Dogri',                 'डोगरी'),
    LanguageOption('mai', 'Maithili',              'मैथिली'),
    LanguageOption('sat', 'Santali',               'ᱥᱟᱱᱛᱟᱲᱤ'),
    LanguageOption('ne',  'Nepali',                'नेपाली'),
  ];

  // ── RTL Languages ─────────────────────────────────────────────────────────
  static const Set<String> rtlLanguages = {'ur', 'ks', 'sd'};
  bool get isRtl => rtlLanguages.contains(_locale.languageCode);

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString('language') ?? 'en';
    _locale    = Locale(langCode);
    _useMetric = prefs.getBool('useMetric') ?? true;
    _wifiIp    = prefs.getString('wifiIp')   ?? '192.168.0.10';
    _wifiPort  = prefs.getInt('wifiPort')    ?? 35000;
    final savedPids = prefs.getStringList('dashboardPids');
    if (savedPids != null) _dashboardPids = savedPids;
    notifyListeners();
  }

  // ── Set Language ──────────────────────────────────────────────────────────
  Future<void> setLanguage(String langCode) async {
    _locale = Locale(langCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', langCode);
    notifyListeners();
  }

  // ── Toggle Units ──────────────────────────────────────────────────────────
  Future<void> toggleUnits() async {
    _useMetric = !_useMetric;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useMetric', _useMetric);
    notifyListeners();
  }

  // ── Save WiFi Settings ────────────────────────────────────────────────────
  Future<void> saveWifiSettings(String ip, int port) async {
    _wifiIp   = ip;
    _wifiPort = port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wifiIp', ip);
    await prefs.setInt('wifiPort', port);
    notifyListeners();
  }

  // ── Current Language Option ───────────────────────────────────────────────
  LanguageOption get currentLanguage {
    return supportedLanguages.firstWhere(
      (l) => l.code == _locale.languageCode,
      orElse: () => supportedLanguages.first,
    );
  }

  // ── Speed Unit ────────────────────────────────────────────────────────────
  String get speedUnit => _useMetric ? 'km/h' : 'mph';
  String get tempUnit  => _useMetric ? '°C' : '°F';

  double convertSpeed(double? kmh) {
    if (kmh == null) return 0;
    return _useMetric ? kmh : kmh * 0.621371;
  }

  double convertTemp(double? celsius) {
    if (celsius == null) return 0;
    return _useMetric ? celsius : (celsius * 9 / 5) + 32;
  }
}

/// Language Option Model
class LanguageOption {
  final String code;
  final String nameEn;
  final String nameNative;

  const LanguageOption(this.code, this.nameEn, this.nameNative);
}
