import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/folder_setting.dart';
import '../models/rating.dart';

class SettingsRepository {
  static const String _foldersKey = 'folder_settings';
  static const String _nsfwKey = 'nsfw_filter_enabled';
  static const String _selectedModelKey = 'selected_model';
  static const String _gridCrossAxisCountKey = 'grid_cross_axis_count';
  static const String _themeModeKey = 'theme_mode';
  static const String _lastScrollIndexKey = 'last_scroll_index';
  static const String _lastViewedImagePathKey = 'last_viewed_image_path';
  static const String _shuffleOrderKey = 'shuffle_order';
  static const String _gridScrollPreferPositionKey =
      'grid_scroll_prefer_position'; // 'begin' | 'middle' | 'end'
  static const String _visibleRatingsKey = 'visible_ratings';

  Future<void> saveFolderSettings(List<FolderSetting> folderSettings) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> folderList = folderSettings
        .map((f) => f.toMap())
        .toList();
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
    return prefs.getInt(_gridCrossAxisCountKey) ?? 2;
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

  Future<void> saveLastViewedImagePath(String? imagePath) async {
    final prefs = await SharedPreferences.getInstance();
    if (imagePath != null) {
      await prefs.setString(_lastViewedImagePathKey, imagePath);
    } else {
      await prefs.remove(_lastViewedImagePathKey);
    }
  }

  Future<String?> loadLastViewedImagePath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastViewedImagePathKey);
  }

  Future<void> saveNsfwFilter(bool isEnabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_nsfwKey, isEnabled);
  }

  Future<bool> loadNsfwFilter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_nsfwKey) ?? false;
  }

  Future<void> saveShuffleOrder(List<int> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shuffleOrderKey, jsonEncode(order));
  }

  Future<List<int>?> loadShuffleOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final String? orderJson = prefs.getString(_shuffleOrderKey);
    if (orderJson != null) {
      final List<dynamic> orderList = jsonDecode(orderJson);
      return orderList.cast<int>();
    }
    return null;
  }

  Future<void> clearShuffleOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_shuffleOrderKey);
  }

  // --- Grid scroll prefer position (internal toggle) ---
  Future<void> saveGridScrollPreferPosition(String positionName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gridScrollPreferPositionKey, positionName);
  }

  Future<String> loadGridScrollPreferPosition() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_gridScrollPreferPositionKey) ?? 'middle';
  }

  // --- Visible ratings settings ---
  Future<void> saveVisibleRatings(Map<Rating, bool> visibleRatings) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, bool> ratingsMap = visibleRatings.map(
      (rating, isVisible) => MapEntry(rating.name, isVisible),
    );
    await prefs.setString(_visibleRatingsKey, jsonEncode(ratingsMap));
  }

  Future<Map<Rating, bool>> loadVisibleRatings() async {
    final prefs = await SharedPreferences.getInstance();
    final String? ratingsJson = prefs.getString(_visibleRatingsKey);

    if (ratingsJson != null) {
      final Map<String, dynamic> ratingsMap = jsonDecode(ratingsJson);
      return ratingsMap.map(
        (key, value) => MapEntry(
          Rating.values.firstWhere((r) => r.name == key),
          value as bool,
        ),
      );
    } else {
      // デフォルトでは全てのレーティングを表示
      return {Rating.nsfw: true, Rating.sfw: true, Rating.unclassified: true};
    }
  }
}
