import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class AppPreferences {
  static const _boxName = 'preferences';
  static const _themeModeKey = 'theme_mode';
  static const _localeKey = 'locale';

  late Box<dynamic> _box;

  @PostConstruct(preResolve: true)
  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  ThemeMode get themeMode {
    final value = _box.get(_themeModeKey, defaultValue: 'system') as String;
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _box.put(_themeModeKey, mode.name);
  }

  String get locale => _box.get(_localeKey, defaultValue: 'en') as String;

  Future<void> setLocale(String locale) async {
    await _box.put(_localeKey, locale);
  }
}
