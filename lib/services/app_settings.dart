import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide UI preferences (language + light/dark theme), persisted locally so
/// the choice survives reloads. A single [instance] is listened to by the root
/// [MaterialApp]; changing a value rebuilds the app with the new locale/theme.
class AppSettings extends ChangeNotifier {
  AppSettings._();

  /// The shared instance used across the app.
  static final AppSettings instance = AppSettings._();

  static const _localeKey = 'ui.locale';
  static const _themeKey = 'ui.themeMode';

  /// Languages offered in the UI. Thai is the default.
  static const supportedLocales = [Locale('th'), Locale('en')];

  Locale _locale = const Locale('th');
  Locale get locale => _locale;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  /// Loads saved preferences; call once at startup before running the app.
  /// Never throws — if storage is unavailable the in-memory defaults are kept,
  /// so a preferences hiccup can't block app startup.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString(_localeKey);
      if (lang == 'th' || lang == 'en') _locale = Locale(lang!);
      _themeMode = switch (prefs.getString(_themeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // Keep defaults (Thai, system theme).
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (locale == _locale) return;
    _locale = locale;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localeKey, locale.languageCode);
    } catch (_) {
      // Applied for this session even if it couldn't be saved.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, mode.name);
    } catch (_) {
      // Applied for this session even if it couldn't be saved.
    }
  }
}
