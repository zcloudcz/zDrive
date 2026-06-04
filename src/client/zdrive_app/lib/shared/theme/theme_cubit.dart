import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/storage/app_preferences.dart';

class ThemeCubit extends Cubit<ThemeMode> {
  final AppPreferences _preferences;

  ThemeCubit(this._preferences) : super(_preferences.themeMode);

  void toggle() {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _preferences.setThemeMode(next);
    emit(next);
  }

  void setThemeMode(ThemeMode mode) {
    _preferences.setThemeMode(mode);
    emit(mode);
  }
}
