import 'package:flutter/material.dart';

import '../repositories/settings_repository.dart';

class UiSettingsProvider extends ChangeNotifier {
  final SettingsRepository _repo = SettingsRepository();

  ThemeMode _themeMode = ThemeMode.system;
  int _gridCrossAxisCount = 3;
  int _lastScrollIndex = 0;
  bool _nsfwFilterEnabled = false;

  ThemeMode get themeMode => _themeMode;
  int get gridCrossAxisCount => _gridCrossAxisCount;
  int get lastScrollIndex => _lastScrollIndex;
  bool get nsfwFilterEnabled => _nsfwFilterEnabled;

  Future<void> load() async {
    _themeMode = await _repo.loadThemeMode();
    _gridCrossAxisCount = await _repo.loadGridCrossAxisCount();
    _lastScrollIndex = await _repo.loadLastScrollIndex();
    _nsfwFilterEnabled = await _repo.loadNsfwFilter();
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _repo.saveThemeMode(mode);
    notifyListeners();
  }

  Future<void> setGridCrossAxisCount(int count) async {
    _gridCrossAxisCount = count;
    await _repo.saveGridCrossAxisCount(count);
    notifyListeners();
  }

  Future<void> setLastScrollIndex(int index) async {
    if (_lastScrollIndex == index) return;
    _lastScrollIndex = index;
    await _repo.saveLastScrollIndex(index);
  }

  Future<void> setNsfwFilter(bool enabled) async {
    _nsfwFilterEnabled = enabled;
    await _repo.saveNsfwFilter(enabled);
    notifyListeners();
  }
}
