import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/folder_setting.dart';

class SettingsRepository {
  static const String _foldersKey = 'folder_settings';
  static const String _nsfwKey = 'nsfw_filter_enabled';
  static const String _selectedModelKey = 'selected_model';
  static const String _gridCrossAxisCountKey = 'grid_cross_axis_count';
  static const String _themeModeKey = 'theme_mode';
  static const String _lastScrollIndexKey = 'last_scroll_index';

  Future<void> saveFolderSettings(List<FolderSetting> folderSettings) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> folderList =
        folderSettings.map((f) => f.toMap()).toList();
    await prefs.setString(_foldersKey, jsonEncode(folderList));
  }

  Future<List<FolderSetting>> loadFolderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final String? foldersJson = prefs.getString(_foldersKey);
    if (foldersJson != null) {
      final List<dynamic> folderList = jsonDecode(foldersJson);
      return folderList.map((map) => FolderSetting.fromMap(map)).toList();
    } else {
      return [
        FolderSetting(
          path: '/storage/emulated/0/Pictures/pixiv',
          isDeletable: false,
        ),
        FolderSetting(
          path: '/storage/emulated/0/Pictures/Twitter',
          isDeletable: false,
        ),
      ];
    }
  }

  Future<void> saveSelectedModel(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedModelKey, modelId);
  }

  Future<String> loadSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedModelKey) ?? 'none';
  }

  Future<void> saveGridCrossAxisCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_gridCrossAxisCountKey, count);
  }

  Future<int> loadGridCrossAxisCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_gridCrossAxisCountKey) ?? 3;
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
  }

  Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeModeKey) ?? 0;
    return ThemeMode.values[themeIndex];
  }

  Future<void> saveLastScrollIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastScrollIndexKey, index);
  }

  Future<int> loadLastScrollIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastScrollIndexKey) ?? 0;
  }

  Future<void> saveNsfwFilter(bool isEnabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_nsfwKey, isEnabled);
  }

  Future<bool> loadNsfwFilter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_nsfwKey) ?? false;
  }
}
