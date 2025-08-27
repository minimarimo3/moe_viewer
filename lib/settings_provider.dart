import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FolderSetting {
  final String path;
  bool isEnabled;

  FolderSetting({required this.path, this.isEnabled = true});

  // MapからFolderSettingに変換するためのファクトリコンストラクタ
  factory FolderSetting.fromMap(Map<String, dynamic> map) {
    return FolderSetting(path: map['path'], isEnabled: map['isEnabled']);
  }

  // FolderSettingをMapに変換するメソッド
  Map<String, dynamic> toMap() {
    return {'path': path, 'isEnabled': isEnabled};
  }
}

class SettingsProvider extends ChangeNotifier {
  // static const String _pathsKey = 'selected_paths';
  static const String _foldersKey = 'folder_settings';
  static const String _nsfwKey = 'nsfw_filter_enabled';

  // List<String> _selectedPaths = [];
  List<FolderSetting> _folderSettings = [];
  bool _nsfwFilterEnabled = false; // ★★★ NSFW設定用の変数を追加

  // List<String> get selectedPaths => _selectedPaths;
  List<FolderSetting> get folderSettings => _folderSettings;
  bool get nsfwFilterEnabled => _nsfwFilterEnabled; // ★★★ NSFW設定用のゲッターを追加

  // SettingsProvider() { loadSettings(); // 起動時にすべての設定を読み込む }

  // すべての設定を読み込むように名前を変更
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // ★★★ JSON文字列として保存された設定を読み込む ★★★
    final String? foldersJson = prefs.getString(_foldersKey);
    if (foldersJson != null) {
      final List<dynamic> folderList = jsonDecode(foldersJson);
      _folderSettings = folderList
          .map((map) => FolderSetting.fromMap(map))
          .toList();
    } else {
      // 初期値
      _folderSettings = [
        FolderSetting(path: '/storage/emulated/0/Pictures/pixiv'),
      ];
    }

    _nsfwFilterEnabled = prefs.getBool(_nsfwKey) ?? false;
    notifyListeners();
  }
  /*
    final prefs = await SharedPreferences.getInstance();
    _selectedPaths =
        prefs.getStringList(_foldersKey) ??
        ['/storage/emulated/0/Pictures/pixiv'];
    _nsfwFilterEnabled =
        prefs.getBool(_nsfwKey) ?? false; // ★★★ NSFW設定を読み込む処理を追加
    notifyListeners();
  }
  */

  Future<void> _saveFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> folderList = _folderSettings
        .map((f) => f.toMap())
        .toList();
    await prefs.setString(_foldersKey, jsonEncode(folderList));
    notifyListeners();
  }

  Future<void> addFolder(String newPath) async {
    if (!_folderSettings.any((f) => f.path == newPath)) {
      _folderSettings.add(FolderSetting(path: newPath));
      await _saveFolders();
    }
  }

  Future<void> removeFolder(String path) async {
    _folderSettings.removeWhere((f) => f.path == path);
    await _saveFolders();
  }

  // ★★★ フォルダの有効/無効を切り替える新しい関数 ★★★
  Future<void> toggleFolderEnabled(String path) async {
    final folder = _folderSettings.firstWhere((f) => f.path == path);
    folder.isEnabled = !folder.isEnabled;
    await _saveFolders();
  }

  /*
  Future<void> addPath(String newPath) async {
    // (変更なし)
    if (!_selectedPaths.contains(newPath)) {
      _selectedPaths.add(newPath);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_foldersKey, _selectedPaths);
      notifyListeners();
    }
  }

  Future<void> removePath(String path) async {
    // (変更なし)
    _selectedPaths.remove(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_foldersKey, _selectedPaths);
    notifyListeners();
  }
  */

  // ★★★ NSFW設定を変更・保存する関数を追加 ★★★
  Future<void> setNsfwFilter(bool isEnabled) async {
    _nsfwFilterEnabled = isEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_nsfwKey, isEnabled);
    notifyListeners();
  }
}
