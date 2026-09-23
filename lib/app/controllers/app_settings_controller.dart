import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../core/models/app_settings.dart';

const String appSettingsBox = 'appSettings';

class AppSettingsController extends ChangeNotifier {
  late AppSettings _settings;
  final Box<AppSettings> _box;

  AppSettings get settings => _settings;

  bool get isDarkMode => _settings.isDarkMode;
  String get locale => _settings.locale;

  AppSettingsController({required Box<AppSettings> box}) : _box = box {
    _loadSettings();
  }

  void _loadSettings() {
    try {
      _settings = _box.get('app_settings') ?? AppSettings.defaults();
    } catch (e) {
      _settings = AppSettings.defaults();
    }
  }

  Future<void> setDarkMode(bool isDark) async {
    _settings.isDarkMode = isDark;
    await _box.put('app_settings', _settings);
    notifyListeners();
  }

  Future<void> setLocale(String newLocale) async {
    _settings.locale = newLocale;
    await _box.put('app_settings', _settings);
    notifyListeners();
  }

  ThemeMode get themeMode {
    return _settings.isDarkMode ? ThemeMode.dark : ThemeMode.light;
  }
}
