import 'package:flutter/material.dart';
import '../models/app_settings.dart';

/// アプリテーマ定義。
///
/// [AppTheme] の列挙値に応じてライト/ダークの [ThemeData] を生成する。
class AppThemes {
  static ThemeData getLightTheme(AppTheme theme) {
    switch (theme) {
      case AppTheme.green:
        return _lightThemeForSeed(Colors.green);
      case AppTheme.blue:
        return _lightThemeForSeed(Colors.blue);
      case AppTheme.purple:
        return _lightThemeForSeed(Colors.purple);
      case AppTheme.orange:
        return _lightThemeForSeed(Colors.orange);
    }
  }

  static ThemeData getDarkTheme(AppTheme theme) {
    switch (theme) {
      case AppTheme.green:
        return _darkThemeForSeed(Colors.green);
      case AppTheme.blue:
        return _darkThemeForSeed(Colors.blue);
      case AppTheme.purple:
        return _darkThemeForSeed(Colors.purple);
      case AppTheme.orange:
        return _darkThemeForSeed(Colors.orange);
    }
  }

  static ThemeData _lightThemeForSeed(Color seed) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ),
    fontFamily: 'NotoSansJP',
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
  );

  static ThemeData _darkThemeForSeed(Color seed) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ),
    brightness: Brightness.dark,
    fontFamily: 'NotoSansJP',
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
  );
}
