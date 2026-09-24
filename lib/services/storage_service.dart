import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService extends ChangeNotifier {
  SharedPreferences? _prefs;

  final Map<String, dynamic> _cache = {
    'haptics_enabled': true,
    'camera_sound': true,
    'hd_quality': true,
    'biometric_enabled': false,
    'anonymous_scanning': false,
    'onboarding_completed': false,
    'onboarding_goal': '',
    'onboarding_focus': '',
    'onboarding_experience': '',
  };

  StorageService({SharedPreferences? prefs}) : _prefs = prefs {
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      // Hydrate memory cache with persisted values
      for (final key in _cache.keys) {
        if (_prefs!.containsKey(key)) {
          final val = _prefs!.get(key);
          if (val != null) {
            _cache[key] = val;
          }
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  bool getBool(String key, {bool defaultValue = false}) {
    return _cache[key] as bool? ?? defaultValue;
  }

  void setBool(String key, bool value) {
    _cache[key] = value;
    _prefs?.setBool(key, value);
    notifyListeners();
  }

  String? getString(String key) {
    return _cache[key] as String?;
  }

  void setString(String key, String value) {
    _cache[key] = value;
    _prefs?.setString(key, value);
    notifyListeners();
  }

}
