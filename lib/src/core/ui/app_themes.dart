import 'package:flutter/material.dart';

/// アプリ全体のテーマ設定を管理
class AppThemes {
  static const String _fontFamily = 'NotoSansJP';
  static const Color _seedColor = Colors.deepPurple;

  /// ライトテーマ
  static ThemeData get lightTheme => ThemeData(
    brightness: Brightness.light,
    fontFamily: _fontFamily,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    ),
    useMaterial3: true,
  );

  /// ダークテーマ
  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    fontFamily: _fontFamily,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );
}
