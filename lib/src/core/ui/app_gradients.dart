import 'package:flutter/material.dart';

/// アプリ全体で使用する共通のグラデーション定義
class AppGradients {
  // オーバーレイ用の縦方向グラデーション（下から上へ透明に）
  static const LinearGradient textOverlay = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color.fromARGB(180, 0, 0, 0), Color.fromARGB(0, 0, 0, 0)],
  );

  /// プレースホルダー用のグラデーション
  static LinearGradient placeholderGradient(ColorScheme colorScheme) {
    final base = colorScheme.primaryContainer;
    return LinearGradient(
      colors: [base.withValues(alpha: 0.9), base.withValues(alpha: 0.6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}
