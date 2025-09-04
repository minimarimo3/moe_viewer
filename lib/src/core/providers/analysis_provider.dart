import 'dart:io';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/ai_model_definition.dart';
import '../models/folder_setting.dart';
import '../repositories/image_repository.dart';
import '../services/ai_service.dart';
import '../services/database_helper.dart';

class AnalysisProvider extends ChangeNotifier {
  final ImageRepository _imageRepo = ImageRepository();

  bool _isAnalyzing = false;
  bool get isAnalyzing => _isAnalyzing;
  int _analysisProgress = 0;
  int _analysisTotal = 0;
  int get analysisProgress => _analysisProgress;
  int get analysisTotal => _analysisTotal;

  String _currentAnalyzingFile = '';
  String get currentAnalyzingFile => _currentAnalyzingFile;
  List<String> _lastFoundTags = [];
  List<String> get lastFoundTags => _lastFoundTags;
  String? _currentAnalyzedImageBase64;
  String? get currentAnalyzedImageBase64 => _currentAnalyzedImageBase64;

  int _totalFileCount = 0;
  int get totalFileCount => _totalFileCount;
  int _analyzedFileCount = 0;
  int get analyzedFileCount => _analyzedFileCount;

  Future<void> updateOverallProgress(List<FolderSetting> folders) async {
    final enabledFolders = folders.where((f) => f.isEnabled).toList();
    final selectedPaths = enabledFolders.map((f) => f.path).toList();
    int totalCount = 0;
    final allAlbums = await PhotoManager.getAssetPathList(
      filterOption: FilterOptionGroup(includeHiddenAssets: true),
    );
    final albumMap = {for (var a in allAlbums) a.name.toLowerCase(): a};
    final hasFullAccess =
        await Permission.manageExternalStorage.status.isGranted;
    for (final path in selectedPaths) {
      final folderName = path.split('/').last.toLowerCase();
      if (albumMap.containsKey(folderName)) {
        final album = albumMap[folderName]!;
        totalCount += await album.assetCountAsync;
      } else if (hasFullAccess) {
        final dir = Directory(path);
        if (await dir.exists()) {
          final files = dir.listSync(recursive: true);
          for (final e in files) {
            if (e is File) {
              final p = e.path.toLowerCase();
              if (p.endsWith('.jpg') ||
                  p.endsWith('.png') ||
                  p.endsWith('.jpeg') ||
                  p.endsWith('.gif')) {
                totalCount += 1;
              }
            }
          }
        }
      }
    }
    _totalFileCount = totalCount;
    final analyzedCount = await DatabaseHelper.instance.getAnalyzedFileCount();
    if (_totalFileCount < analyzedCount) _totalFileCount = analyzedCount;
    _analyzedFileCount = analyzedCount;
    notifyListeners();
  }

  Future<void> startAiAnalysis({
    required AiService aiService,
    required List<FolderSetting> folders,
    required AiModelDefinition model,
  }) async {
    if (_isAnalyzing) return;
    _isAnalyzing = true;
    await updateOverallProgress(folders);
    notifyListeners();

    final imageList = await _imageRepo.getAllImages(folders);
    final db = DatabaseHelper.instance;
    final analyzedPaths = await db.getAnalyzedImagePaths();
    final filesToAnalyze = imageList.detailFiles
        .where((f) => !analyzedPaths.contains(f.path))
        .toList();
    _analysisTotal = filesToAnalyze.length;
    _analysisProgress = 0;
    _currentAnalyzingFile = '';
    _lastFoundTags = [];
    if (_analysisTotal == 0) {
      _isAnalyzing = false;
      notifyListeners();
      return;
    }
    for (int i = 0; i < filesToAnalyze.length; i++) {
      if (!_isAnalyzing) break;
      final file = filesToAnalyze[i];
      _currentAnalyzingFile = file.path.split('/').last;
      _analysisProgress = i + 1;
      notifyListeners();
      final result = await aiService.analyzeImage(file);
      final tags = result['tags'] as List<String>? ?? const ['AI解析エラー'];
      final imageBase64 = result['image'] as String?;
      await db.insertOrUpdateTag(file.path, tags);
      _analyzedFileCount++;
      _lastFoundTags = tags;
      _currentAnalyzedImageBase64 = imageBase64;
      notifyListeners();
    }
    _isAnalyzing = false;
    _currentAnalyzingFile = '';
    _currentAnalyzedImageBase64 = null;
    await updateOverallProgress(folders);
    notifyListeners();
    log('AI解析が完了または停止しました。');
  }

  void stopAiAnalysis() {
    _isAnalyzing = false;
    _currentAnalyzingFile = '';
    _currentAnalyzedImageBase64 = null;
    notifyListeners();
  }
}
