import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light/dark appearance chosen by the user, saved on the device.
class ThemeService {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  static const String _prefsKey = 'theme_mode';

  final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  /// Restores the saved choice; falls back to following the system.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      mode.value = ThemeMode.values.firstWhere(
        (m) => m.name == saved,
        orElse: () => ThemeMode.system,
      );
    } catch (e) {
      debugPrint('Error loading theme mode: $e');
    }
  }

  Future<void> setMode(ThemeMode newMode) async {
    mode.value = newMode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, newMode.name);
    } catch (e) {
      debugPrint('Error saving theme mode: $e');
    }
  }
}
