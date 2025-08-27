// lib/settings_provider.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static const String _pathsKey = 'selected_paths';
  static const String _nsfwKey = 'nsfw_filter_enabled'; // ★★★ NSFW設定用のキーを追加

  List<String> _selectedPaths = [];
  bool _nsfwFilterEnabled = false; // ★★★ NSFW設定用の変数を追加

  List<String> get selectedPaths => _selectedPaths;
  bool get nsfwFilterEnabled => _nsfwFilterEnabled; // ★★★ NSFW設定用のゲッターを追加

  SettingsProvider() {
    loadSettings(); // 起動時にすべての設定を読み込む
  }

  // すべての設定を読み込むように名前を変更
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedPaths =
        prefs.getStringList(_pathsKey) ??
        ['/storage/emulated/0/Pictures/pixiv'];
    _nsfwFilterEnabled =
        prefs.getBool(_nsfwKey) ?? false; // ★★★ NSFW設定を読み込む処理を追加
    notifyListeners();
  }

  Future<void> addPath(String newPath) async {
    // (変更なし)
    if (!_selectedPaths.contains(newPath)) {
      _selectedPaths.add(newPath);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_pathsKey, _selectedPaths);
      notifyListeners();
    }
  }

  Future<void> removePath(String path) async {
    // (変更なし)
    _selectedPaths.remove(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pathsKey, _selectedPaths);
    notifyListeners();
  }

  // ★★★ NSFW設定を変更・保存する関数を追加 ★★★
  Future<void> setNsfwFilter(bool isEnabled) async {
    _nsfwFilterEnabled = isEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_nsfwKey, isEnabled);
    notifyListeners();
  }
}
