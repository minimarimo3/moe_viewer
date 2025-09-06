import 'dart:io';
import 'dart:async';
import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/ai_service.dart';
import '../services/database_helper.dart';
import '../services/file_crypto_service.dart';
import '../models/ai_model_definition.dart';
import '../models/folder_setting.dart';
import '../repositories/settings_repository.dart';
import '../repositories/image_repository.dart';
import '../services/thumbnail_service.dart';

class SettingsProvider extends ChangeNotifier {
  final SettingsRepository _settingsRepository = SettingsRepository();
  final ImageRepository _imageRepository = ImageRepository();

  bool _isAnalyzing = false;
  bool get isAnalyzing => _isAnalyzing;

  int _analysisProgress = 0;
  int _analysisTotal = 0;

  bool _isModelDownloaded = false;
  bool get isModelDownloaded => _isModelDownloaded;

  double _downloadProgress = 0.0;
  double get downloadProgress => _downloadProgress;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  // ダウンロード失敗などユーザー通知用のエラーメッセージ（イベント的に使う）
  String? _downloadErrorMessage;
  int _downloadErrorVersion = 0; // 同一メッセージの多重表示防止用の連番
  String? get downloadErrorMessage => _downloadErrorMessage;
  int get downloadErrorVersion => _downloadErrorVersion;
  void _emitDownloadError(String message) {
    _downloadErrorMessage = message;
    _downloadErrorVersion++;
    notifyListeners();
  }

  // ハッシュ不一致通知用のエラーメッセージ（イベント的に使う）
  String? _hashMismatchErrorMessage;
  int _hashMismatchErrorVersion = 0;
  String? get hashMismatchErrorMessage => _hashMismatchErrorMessage;
  int get hashMismatchErrorVersion => _hashMismatchErrorVersion;
  void _emitHashMismatchError(String message) {
    _hashMismatchErrorMessage = message;
    // _hashMismatchErrorVersion++;
    notifyListeners();
  }

  String _currentAnalyzingFile = '';
  String get currentAnalyzingFile => _currentAnalyzingFile;

  int _totalFileCount = 0;
  int get totalFileCount => _totalFileCount;
  int _analyzedFileCount = 0;
  int get analyzedFileCount => _analyzedFileCount;

  List<String> _lastFoundTags = [];
  List<String> get lastFoundTags => _lastFoundTags;

  String? _currentAnalyzedImageBase64;
  String? get currentAnalyzedImageBase64 => _currentAnalyzedImageBase64;

  int get analysisProgress => _analysisProgress;
  int get analysisTotal => _analysisTotal;

  bool _nsfwFilterEnabled = false;
  bool get nsfwFilterEnabled => _nsfwFilterEnabled;

  String _selectedModelId = 'none';
  String get selectedModelId => _selectedModelId;

  int _gridCrossAxisCount = 2;
  int get gridCrossAxisCount => _gridCrossAxisCount;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  int _lastScrollIndex = 0;
  int get lastScrollIndex => _lastScrollIndex;

  String? _lastViewedImagePath;
  String? get lastViewedImagePath => _lastViewedImagePath;

  List<FolderSetting> _folderSettings = [];
  List<FolderSetting> get folderSettings => _folderSettings;

  List<int>? _shuffleOrder;
  List<int>? get shuffleOrder => _shuffleOrder;

  /// ファイル破損チェック
  bool _isModelCorrupted = false;
  bool get isModelCorrupted => _isModelCorrupted;

  bool _isCheckingHash = false;
  bool get isCheckingHash => _isCheckingHash;

  bool _isCheckingDownload = false;
  bool get isCheckingDownload => _isCheckingDownload;

  /// ファイルダウンロードのキャンセル用
  CancelToken? _cancelToken;

  Future<void> init() async {
    // 軽量な設定のみを先に読み込み、UIをブロックしない
    _selectedModelId = await _settingsRepository.loadSelectedModel();
    _gridCrossAxisCount = await _settingsRepository.loadGridCrossAxisCount();
    _themeMode = await _settingsRepository.loadThemeMode();
    _lastScrollIndex = await _settingsRepository.loadLastScrollIndex();
    try {
      _lastViewedImagePath = await _settingsRepository.loadLastViewedImagePath();
    } catch (e) {
      _lastViewedImagePath = null;
    }
    _folderSettings = await _settingsRepository.loadFolderSettings();
    _nsfwFilterEnabled = await _settingsRepository.loadNsfwFilter();
    _shuffleOrder = await _settingsRepository.loadShuffleOrder();

    // UIをすぐに更新
    notifyListeners();

    // 重い処理は非同期で実行（UIをブロックしない）
    _initializeHeavyOperations();
  }

  void _initializeHeavyOperations() async {
    try {
      await updateOverallProgress();
      notifyListeners();
    } catch (e) {
      // エラーが発生してもアプリを止めない
      log('Error during heavy initialization: $e');
    }
  }

  Future<void> setSelectedModel(String modelId) async {
    _selectedModelId = modelId;
    await _settingsRepository.saveSelectedModel(modelId);
    notifyListeners();

    // モデル選択後にダウンロード状況のみをチェック（ハッシュチェックは解析開始時に実行）
    if (modelId != 'none') {
      final selectedModelDef = availableModels.firstWhere(
        (m) => m.id == modelId,
        orElse: () => availableModels.first,
      );
      await checkModelDownloadStatus(selectedModelDef);
    }
  }

  Future<void> setGridCrossAxisCount(int count) async {
    _gridCrossAxisCount = count;
    await _settingsRepository.saveGridCrossAxisCount(count);
    // 列数変更時はグリッド用サムネイルを一掃（ベースは保持）
    try {
      await clearGridThumbnailsCache();
    } catch (e) {
      log('Failed to clear grid thumbnails on column change: $e');
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _settingsRepository.saveThemeMode(mode);
    notifyListeners();
  }

  Future<void> setLastScrollIndex(int index) async {
    _lastScrollIndex = index;
    await _settingsRepository.saveLastScrollIndex(index);
  }

  Future<void> setLastViewedImagePath(String? imagePath) async {
    _lastViewedImagePath = imagePath;
    try {
      await _settingsRepository.saveLastViewedImagePath(imagePath);
    } catch (e) {
      log('Error saving last viewed image path: $e');
    }
  }

  Future<void> saveShuffleOrder(List<int> order) async {
    _shuffleOrder = List.from(order);
    await _settingsRepository.saveShuffleOrder(order);
    notifyListeners();
  }

  Future<void> clearShuffleOrder() async {
    _shuffleOrder = null;
    await _settingsRepository.clearShuffleOrder();
    notifyListeners();
  }

  Future<void> updateOverallProgress() async {
    // --- ファイル総数の計算ロジック ---
    final enabledFolders = _folderSettings.where((f) => f.isEnabled).toList();
    final selectedPaths = enabledFolders.map((f) => f.path).toList();

    int totalCount = 0;

    final allAlbums = await PhotoManager.getAssetPathList(
      filterOption: FilterOptionGroup(includeHiddenAssets: true),
    );
    final albumMap = {
      for (var album in allAlbums) album.name.toLowerCase(): album,
    };
    final hasFullAccess =
        await Permission.manageExternalStorage.status.isGranted;

    for (final path in selectedPaths) {
      final folderName = path.split('/').last.toLowerCase();
      if (albumMap.containsKey(folderName)) {
        final album = albumMap[folderName]!;
        final assetCount = await album.assetCountAsync;
        totalCount += assetCount;
      } else if (hasFullAccess) {
        final directory = Directory(path);
        if (await directory.exists()) {
          final files = directory.listSync(recursive: true);
          for (final fileEntity in files) {
            if (fileEntity is File) {
              final filePath = fileEntity.path.toLowerCase();
              if (filePath.endsWith('.jpg') ||
                  filePath.endsWith('.png') ||
                  filePath.endsWith('.jpeg') ||
                  filePath.endsWith('.gif')) {
                totalCount += 1;
              }
            }
          }
        }
      }
    }
    _totalFileCount = totalCount;
    // --- 計算ロジックここまで ---

    final analyzedCount = await DatabaseHelper.instance.getAnalyzedFileCount();

    if (_totalFileCount < analyzedCount) {
      _totalFileCount = analyzedCount;
    }
    _analyzedFileCount = analyzedCount;
  }

  /// モデルファイルのダウンロード状況のみをチェック（ハッシュ検証なし）
  Future<void> checkModelDownloadStatus(AiModelDefinition modelDef) async {
    _isCheckingDownload = true;
    notifyListeners();

    final modelPath = await _getModelPath(modelDef.modelFileName);
    final labelsPath = await _getLabelsPath(modelDef.labelFileName);
    final modelFile = File(modelPath);
    final labelsFile = File(labelsPath);

    if (await modelFile.exists() && await labelsFile.exists()) {
      _isModelDownloaded = true;
      // ハッシュチェックは行わないので、破損フラグはリセット
      _isModelCorrupted = false;
    } else {
      _isModelDownloaded = false;
      _isModelCorrupted = false;
    }
    _isCheckingDownload = false;
    notifyListeners();
  }

  Future<void> checkModelStatus(AiModelDefinition modelDef) async {
    // ダウンロード中はハッシュチェックをスキップ（ファイルが不完全で誤検知になるため）
    if (_isDownloading) {
      log('ダウンロード中のため、ハッシュチェックをスキップします。');
      return;
    }
    _isCheckingHash = true;
    notifyListeners();

    final modelPath = await _getModelPath(modelDef.modelFileName);
    final labelsPath = await _getLabelsPath(modelDef.labelFileName);
    final modelFile = File(modelPath);
    final labelsFile = File(labelsPath);

    if (await modelFile.exists() && await labelsFile.exists()) {
      // ★★★ ファイルが存在する場合、ハッシュ値を検証 ★★★
      log(
        "ファイルのハッシュ値を計算中です。モデル: ${modelDef.modelFileName}, ラベル: ${modelDef.labelFileName}",
      );

      final modelHashFuture = computeFileHash(modelPath);
      final labelsHashFuture = computeFileHash(labelsPath);

      // 両方の計算が終わるのを待つ
      log("ハッシュ値計算を開始しました。計算完了まで待機します...");
      final results = await Future.wait([modelHashFuture, labelsHashFuture]);
      final modelHash = results[0];
      final labelsHash = results[1];

      log("ハッシュ値計算が完了しました。");
      log("モデルファイルのハッシュ: $modelHash, 期待されるハッシュ: ${modelDef.modelFileHash}");
      log("ラベルファイルのハッシュ: $labelsHash, 期待されるハッシュ: ${modelDef.labelFileHash}");

      if (modelHash == modelDef.modelFileHash &&
          labelsHash == modelDef.labelFileHash) {
        _isModelDownloaded = true;
        _isModelCorrupted = false;
        log("ファイルの整合性チェックが成功しました。");
      } else {
        _isModelDownloaded = true;
        _isModelCorrupted = true;
        final errorMessage =
            "モデルファイルのハッシュ値が一致しません。ファイルが破損している可能性があります。\n期待されるハッシュ: (${modelDef.modelFileHash}, ${modelDef.labelFileHash})\n実際のハッシュ: ($modelHash, $labelsHash)";
        log(errorMessage);
        _emitHashMismatchError(errorMessage);
      }
    } else {
      _isModelDownloaded = false;
      _isModelCorrupted = false;
      log("モデルファイルまたはラベルファイルが見つかりません。");
    }
    _isCheckingHash = false;
    notifyListeners();
  }

  void cancelDownload() {
    log('ダウンロードキャンセルが要求されました。');
    if (_isDownloading && _cancelToken != null) {
      _cancelToken!.cancel('Operation cancelled by user.');
      log('ダウンロードがキャンセルされました。');
    }
  }

  Future<void> downloadWithResume(String url, String savePath) async {
    log('ダウンロードを開始します: $url -> $savePath');
    _isDownloading = true;
    notifyListeners();

    final dio = Dio();
    int downloadedBytes = 0;
    final file = File(savePath);

    if (await file.exists()) {
      downloadedBytes = await file.length();
      log('既存のファイルサイズ: $downloadedBytes bytes');
    }

    int totalBytes = 0;
    try {
      final response = await dio.head(url);
      totalBytes = int.parse(
        response.headers.value(Headers.contentLengthHeader) ?? '0',
      );
      log('ファイルの総サイズ: $totalBytes bytes');
    } catch (e) {
      log('ファイルの総サイズ取得に失敗: $e');
      _emitDownloadError('ファイルサイズの取得に失敗しました。ネットワークやURLをご確認ください。\n$e');
      _isDownloading = false;
      notifyListeners();
      return;
    }

    if (totalBytes > 0 && downloadedBytes == totalBytes) {
      log('ダウンロードは既に完了しています。: $savePath');
      _downloadProgress = 1.0;
      return;
    }

    RandomAccessFile? raf; // finallyブロックで使えるように、外で宣言
    try {
      final response = await dio.get<ResponseBody>(
        url,
        cancelToken: _cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Range': 'bytes=$downloadedBytes-'},
        ),
      );

      final file = File(savePath);
      raf = await file.open(mode: FileMode.append);
      int currentTotalBytes = downloadedBytes;

      await for (final chunk in response.data!.stream) {
        await raf.writeFrom(chunk);
        await raf.flush();

        currentTotalBytes += chunk.length;
        if (totalBytes > 0) {
          _downloadProgress = currentTotalBytes / totalBytes;
          notifyListeners();
        }
      }
    } catch (e) {
      log('ダウンロードリクエストまたは書き込み中にエラー: $e');
      rethrow;
    } finally {
      await raf?.close();
    }
  }

  Future<void> downloadModel(
    AiModelDefinition modelDef, {
    bool isReset = false,
  }) async {
    if (_isDownloading) return;

    _isDownloading = true;
    _downloadProgress = 0.0;
    _cancelToken = CancelToken();
    notifyListeners();

    final modelPath = await _getModelPath(modelDef.modelFileName);
    final labelsPath = await _getLabelsPath(modelDef.labelFileName);
    if (isReset && await File(modelPath).exists()) {
      await File(modelPath).delete();
    }
    if (isReset && await File(labelsPath).exists()) {
      await File(labelsPath).delete();
    }

    try {
      await downloadWithResume(modelDef.modelDownloadUrl, modelPath);
      await downloadWithResume(modelDef.labelDownloadUrl, labelsPath);

      _isModelDownloaded = true;
      log("モデルのダウンロードが完了しました。");
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        log('ユーザーがダウンロードをキャンセルしました。');
      } else {
        log("ダウンロードエラー: $e");
        _emitDownloadError('AIモデルのダウンロードに失敗しました。通信状況をご確認のうえ再試行してください。');
      }
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
    await checkModelDownloadStatus(modelDef);
  }

  Future<String> _getModelPath(String fileName) async {
    final directory = await getApplicationSupportDirectory();
    return '${directory.path}/$fileName';
  }

  Future<String> _getLabelsPath(String fileName) async {
    final directory = await getApplicationSupportDirectory();
    return '${directory.path}/$fileName';
  }

  Future<void> startAiAnalysis(AiService aiService) async {
    log("AI解析を準備しています...");
    if (_isAnalyzing) return;

    final selectedModelDef = availableModels.firstWhere(
      (m) => m.id == _selectedModelId,
      orElse: () => availableModels.first,
    );

    // 解析開始直後にUI上のモデル切替を禁止するため、早めにフラグを立てる
    _isAnalyzing = true;
    notifyListeners();

    // まず最初にモデルの整合性をチェック（ハッシュ値計算を完了させる）
    log("ファイルの整合性をチェックしています...");
    await checkModelStatus(selectedModelDef);
    if (!_isModelDownloaded || _isModelCorrupted) {
      log("モデルが利用可能ではありません。ダウンロードまたは修復してください。");
      // チェックに失敗した場合は解析を中止し、フラグを解除
      _isAnalyzing = false;
      notifyListeners();
      return;
    }

    // ハッシュチェックが成功してからモデルをロード
    log("ファイルの整合性チェックが完了しました。モデルをロードしています...");
    await aiService.ensureModelLoaded(selectedModelDef);
    await updateOverallProgress();
    notifyListeners();

    final imageList = await _imageRepository.getAllImages(_folderSettings);

    final dbHelper = DatabaseHelper.instance;
    final analyzedPaths = await dbHelper.getAnalyzedImagePaths();

    final filesToAnalyze = imageList.detailFiles
        .where((file) => !analyzedPaths.contains(file.path))
        .toList();

    _analysisTotal = filesToAnalyze.length;
    _analysisProgress = 0;
    _currentAnalyzingFile = '';
    _lastFoundTags = [];

    if (_analysisTotal == 0) {
      log("解析対象の新しいファイルはありません。");
      _isAnalyzing = false;
      notifyListeners();
      return;
    }
    notifyListeners();

    log("AI解析を開始します。");
    for (int i = 0; i < filesToAnalyze.length; i++) {
      if (!_isAnalyzing) {
        log("AI解析がキャンセルされました。");
        break;
      }
      final file = filesToAnalyze[i];
      _currentAnalyzingFile = file.path.split('/').last;
      _analysisProgress = i + 1;
      notifyListeners();

      final result = await aiService.analyzeImage(file);
      final tags = result['tags'] as List<String>? ?? ['AI解析エラー'];
      final characterTags = result['characterTags'] as List<String>?;
      final featureTags = result['featureTags'] as List<String>?;
      final imageBase64 = result['image'] as String?;

      await dbHelper.insertOrUpdateTagWithCategories(
        file.path,
        tags,
        characterTags,
        featureTags,
      );

      _analyzedFileCount++;
      _lastFoundTags = tags;
      _currentAnalyzedImageBase64 = imageBase64;
      notifyListeners();
    }

    _isAnalyzing = false;
    _currentAnalyzingFile = '';
    _currentAnalyzedImageBase64 = null;
    await updateOverallProgress();
    notifyListeners();
    log("AI解析が完了または停止しました。");
  }

  void stopAiAnalysis() {
    _isAnalyzing = false;
    _currentAnalyzingFile = '';
    _currentAnalyzedImageBase64 = null;
    notifyListeners();
  }

  Future<void> _saveFolders() async {
    await _settingsRepository.saveFolderSettings(_folderSettings);
    // フォルダ設定が変更されたらImageRepositoryのキャッシュをクリア
    _imageRepository.clearCache();
    notifyListeners();
  }

  Future<void> addFolder(String newPath) async {
    if (!_folderSettings.any((f) => f.path == newPath)) {
      _folderSettings.add(FolderSetting(path: newPath));
      await _saveFolders();
    }
    // 重い処理は非同期で実行
    _updateProgressAsync();
  }

  Future<void> removeFolder(String path) async {
    _folderSettings.removeWhere((f) => f.path == path);
    await _saveFolders();
    // 重い処理は非同期で実行
    _updateProgressAsync();
  }

  Future<void> toggleFolderEnabled(String path) async {
    final folder = _folderSettings.firstWhere((f) => f.path == path);
    folder.isEnabled = !folder.isEnabled;
    await _saveFolders();
    // 重い処理は非同期で実行
    _updateProgressAsync();
  }

  void _updateProgressAsync() async {
    try {
      await updateOverallProgress();
      notifyListeners();
    } catch (e) {
      log('Progress update error: $e');
    }
  }

  Future<void> setNsfwFilter(bool isEnabled) async {
    _nsfwFilterEnabled = isEnabled;
    await _settingsRepository.saveNsfwFilter(isEnabled);
    notifyListeners();
  }
}
