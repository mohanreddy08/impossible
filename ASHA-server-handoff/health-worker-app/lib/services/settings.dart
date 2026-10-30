import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/clock.dart';
import '../data/api/api_client.dart';

/// Secrets (the API key) live in the platform keystore/keychain, never in SharedPreferences or SQLite.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class PlatformSecretStore implements SecretStore {
  PlatformSecretStore([FlutterSecureStorage? s])
    : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String? value) =>
      value == null ? _s.delete(key: key) : _s.write(key: key, value: value);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String? value) async =>
      value == null ? _m.remove(key) : _m[key] = value;
}

/// Demo records are anchored at this date (see backend datasets); demo mode pins "today" to it.
final demoAnchorDate = DateTime(2026, 10, 13);

class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs, this._secrets, this.clock);
  final SharedPreferences _prefs;
  final SecretStore _secrets;
  final AppClock clock;

  static const _kLang = 'lang',
      _kUrl = 'base_url',
      _kDemoDate = 'use_demo_date',
      _kPhone = 'escalation_phone',
      _kAlerts = 'urgent_alerts',
      _kAiAssist = 'ai_assist',
      _kOnlineSpeech = 'online_speech',
      _kOnboarded = 'onboarding_done',
      _kKey = 'api_key';

  String? _apiKey;

  Future<void> load() async {
    _apiKey = await _secrets.read(_kKey);
    clock.demoDate = useDemoDate ? demoAnchorDate : null;
  }

  /// 'en' or 'te'. Defaults to English until the worker chooses.
  String get language => _prefs.getString(_kLang) ?? 'en';
  String get baseUrl => _prefs.getString(_kUrl) ?? '';
  bool get useDemoDate => _prefs.getBool(_kDemoDate) ?? false;
  String get escalationPhone => _prefs.getString(_kPhone) ?? '';

  /// First-run flow finished (or skipped). Phones that already had settings saved before this flow existed count as done, so an
  /// update never forces a working installation back through the welcome screens.
  bool get onboardingDone =>
      _prefs.getBool(_kOnboarded) ??
      (_prefs.containsKey(_kLang) ||
          _prefs.containsKey(_kUrl) ||
          _prefs.containsKey(_kDemoDate));

  /// Optional online helpers (the server's /query fallback and the AI box). OFF by default so the app gives the same answer
  /// with or without a network: everything shown then comes from the phone's own safety rules and protocol library.
  bool get aiAssist => _prefs.getBool(_kAiAssist) ?? false;

  /// Use the phone's ONLINE speech service when the chosen language cannot be recognised on the device. OFF by default: then voice
  /// never sends audio anywhere, and where the phone has no offline pack the app says so instead of silently using the cloud.
  bool get allowOnlineSpeech => _prefs.getBool(_kOnlineSpeech) ?? false;
  bool get alertsEnabled => _prefs.getBool(_kAlerts) ?? true;
  bool get hasApiKey => (_apiKey ?? '').isNotEmpty;

  Future<void> setOnboardingDone() async {
    await _prefs.setBool(_kOnboarded, true);
    notifyListeners();
  }

  Future<void> setAiAssist(bool on) async {
    await _prefs.setBool(_kAiAssist, on);
    notifyListeners();
  }

  Future<void> setAllowOnlineSpeech(bool on) async {
    await _prefs.setBool(_kOnlineSpeech, on);
    notifyListeners();
  }

  Future<void> setAlertsEnabled(bool on) async {
    await _prefs.setBool(_kAlerts, on);
    notifyListeners();
  }

  Future<void> setLanguage(String l) async {
    await _prefs.setString(_kLang, l);
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    await _prefs.setString(_kUrl, url.trim());
    notifyListeners();
  }

  Future<void> setApiKey(String? key) async {
    final k = (key ?? '').trim();
    _apiKey = k.isEmpty ? null : k;
    await _secrets.write(_kKey, _apiKey);
    notifyListeners();
  }

  Future<void> setUseDemoDate(bool v) async {
    await _prefs.setBool(_kDemoDate, v);
    clock.demoDate = v ? demoAnchorDate : null;
    notifyListeners();
  }

  Future<void> setEscalationPhone(String p) async {
    await _prefs.setString(_kPhone, p.trim());
    notifyListeners();
  }

  Future<ApiConfig?> apiConfig() async =>
      baseUrl.isEmpty ? null : ApiConfig(baseUrl, _apiKey);

  /// Plain http to a non-local host sends health-worker data and the key unencrypted: Settings warns about it.
  static bool isInsecureRemote(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || u.scheme != 'http') return false;
    final h = u.host;
    return !(h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '10.0.2.2' ||
        h.startsWith('192.168.') ||
        h.startsWith('10.') ||
        h.endsWith('.local'));
  }
}
