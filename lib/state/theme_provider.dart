import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the app's light/dark/system theme choice and persists it
/// across launches. Defaults to Dark so nothing visually changes for
/// existing installs until someone opens Settings > Theme and picks
/// something else.
///
/// Only stores the user's *choice* (ThemeMode). Resolving "System" to
/// an actual Brightness, and keeping AppColors.isLight in sync with
/// that resolution, is main.dart's job — this class doesn't know or
/// care what the OS brightness currently is.
class ThemeProvider extends ChangeNotifier {
  static const _prefsKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_prefsKey)) {
      case 'light':
        _mode = ThemeMode.light;
        break;
      case 'system':
        _mode = ThemeMode.system;
        break;
      case 'dark':
      default:
        _mode = ThemeMode.dark;
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_prefsKey, value);
  }
}
