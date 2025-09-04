import 'package:flutter/foundation.dart';

import '../models/folder_setting.dart';
import '../repositories/settings_repository.dart';

class FolderSettingsProvider extends ChangeNotifier {
  final SettingsRepository _repo = SettingsRepository();
  List<FolderSetting> _folders = [];
  List<FolderSetting> get folders => List.unmodifiable(_folders);

  Future<void> load() async {
    _folders = await _repo.loadFolderSettings();
    notifyListeners();
  }

  Future<void> addFolder(String newPath) async {
    if (_folders.any((f) => f.path == newPath)) return;
    _folders.add(FolderSetting(path: newPath));
    await _save();
  }

  Future<void> removeFolder(String path) async {
    _folders.removeWhere((f) => f.path == path);
    await _save();
  }

  Future<void> toggleFolderEnabled(String path) async {
    final folder = _folders.firstWhere((f) => f.path == path);
    folder.isEnabled = !folder.isEnabled;
    await _save();
  }

  Future<void> _save() async {
    await _repo.saveFolderSettings(_folders);
    notifyListeners();
  }
}
