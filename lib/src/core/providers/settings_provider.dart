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
import '../services/nsfw_service.dart';
import '../models/ai_model_definition.dart';
import '../models/folder_setting.dart';
import '../models/rating.dart';
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
  // String? _hashMismatchErrorMessage;
  // int _hashMismatchErrorVersion = 0;
  // String? get hashMismatchErrorMessage => _hashMismatchErrorMessage;
  // int get hashMismatchErrorVersion => _hashMismatchErrorVersion;
  // void _emitHashMismatchError(String message) {
  // _hashMismatchErrorMessage = message;
  // _hashMismatchErrorVersion++;
  // notifyListeners();
  // }

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
  String? _lastViewedAssetId; // PhotoManager の安定ID
  String? get lastViewedAssetId => _lastViewedAssetId;

  List<FolderSetting> _folderSettings = [];
  List<FolderSetting> get folderSettings => _folderSettings;

  // フォルダ別統計情報（path -> {totalFiles, taggedFiles}）
  Map<String, Map<String, int>> _folderStats = {};
  Map<String, Map<String, int>> get folderStats => _folderStats;

  // フォルダ統計の自動更新制御
  bool _isAutoUpdateEnabled = true;
  bool get isAutoUpdateEnabled => _isAutoUpdateEnabled;

  // 統計更新中フラグ
  bool _isUpdatingStats = false;
  bool get isUpdatingStats => _isUpdatingStats;

  // 前回のフォルダパスのスナップショット（変更検出用）
  List<String> _lastFolderPaths = [];

  List<int>? _shuffleOrder;
  List<int>? get shuffleOrder => _shuffleOrder;

  // Grid scroll prefer position: 'begin' | 'middle' | 'end'
  String _gridScrollPreferPosition = 'middle';
  String get gridScrollPreferPosition => _gridScrollPreferPosition;

  Map<Rating, bool> _visibleRatings = {
    Rating.nsfw: true,
    Rating.sfw: true,
    Rating.unclassified: true,
  };
  Map<Rating, bool> get visibleRatings => _visibleRatings;

  bool _ratingSettingsChanged = false;
  bool get ratingSettingsChanged => _ratingSettingsChanged;

  // 画像自動スクロール設定（1/10秒単位、デフォルト30 = 3秒）
  int _autoScrollInterval = 30;
  int get autoScrollInterval => _autoScrollInterval;

  // BottomAppBarの使用設定（デフォルトはfalse = AppBar）
  bool _useBottomAppBar = false;
  bool get useBottomAppBar => _useBottomAppBar;

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
    // 軽量な設定を並列で読み込み、UIをブロックしない
    final settingsFutures = [
      _settingsRepository.loadSelectedModel(),
      _settingsRepository.loadGridCrossAxisCount(),
      _settingsRepository.loadThemeMode(),
      _settingsRepository.loadLastScrollIndex(),
      _settingsRepository.loadFolderSettings(),
      _settingsRepository.loadNsfwFilter(),
      _settingsRepository.loadShuffleOrder(),
      _settingsRepository.loadVisibleRatings(),
      _settingsRepository.loadUseBottomAppBar(),
    ];

    final results = await Future.wait([
      settingsFutures[0], // selectedModel
      settingsFutures[1], // gridCrossAxisCount
      settingsFutures[2], // themeMode
      settingsFutures[3], // lastScrollIndex
      settingsFutures[4], // folderSettings
      settingsFutures[5], // nsfwFilter
      settingsFutures[6], // shuffleOrder
      settingsFutures[7], // visibleRatings
      settingsFutures[8], // useBottomAppBar
      // エラー処理が必要な設定は個別に処理
      _settingsRepository.loadLastViewedImagePath().catchError((_) => null),
      _settingsRepository.loadLastViewedAssetId().catchError((_) => null),
      _settingsRepository.loadGridScrollPreferPosition().catchError(
        (_) => 'middle',
      ),
      _settingsRepository.loadAutoScrollInterval().catchError((_) => 30),
      _settingsRepository.loadIsAutoUpdateEnabled().catchError((_) => true),
    ]);

    _selectedModelId = results[0] as String;
    _gridCrossAxisCount = results[1] as int;
    _themeMode = results[2] as ThemeMode;
    _lastScrollIndex = results[3] as int;
    _folderSettings = results[4] as List<FolderSetting>;
    _nsfwFilterEnabled = results[5] as bool;
    _shuffleOrder = results[6] as List<int>?;
    _visibleRatings = results[7] as Map<Rating, bool>;
    _useBottomAppBar = results[8] as bool;
    _lastViewedImagePath = results[9] as String?;
    _lastViewedAssetId = results[10] as String?;
    _gridScrollPreferPosition = results[11] as String;
    _autoScrollInterval = results[12] as int;
    _isAutoUpdateEnabled = results[13] as bool;

    // フォルダ統計を非同期で自動更新（UIブロックを避ける）
    _checkAndAutoUpdateFolderStats();

    // フォルダ設定がある場合は初回統計を強制更新
    if (_folderSettings.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 500), () {
        forceUpdateFolderStats();
      });
    }

    // 自動スクロール間隔の最小値制限
    if (_autoScrollInterval < 5) {
      _autoScrollInterval = 5; // 最小値：0.5秒
    }

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

  Future<void> setLastViewedAssetId(String? assetId) async {
    _lastViewedAssetId = assetId;
    try {
      await _settingsRepository.saveLastViewedAssetId(assetId);
    } catch (e) {
      log('Error saving last viewed asset id: $e');
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

  Future<void> setGridScrollPreferPosition(String positionName) async {
    // 受け入れ値の簡易バリデーション
    const allowed = {'begin', 'middle', 'end'};
    if (!allowed.contains(positionName)) return;
    _gridScrollPreferPosition = positionName;
    await _settingsRepository.saveGridScrollPreferPosition(positionName);
    // UIは変えないが、他参照箇所に反映されるよう通知
    notifyListeners();
  }

  Future<void> setAutoScrollInterval(int interval) async {
    // 最小値制限：0.5秒（5）のみ設定、上限は設けない
    if (interval < 5) interval = 5; // 最小値制限：0.5秒
    _autoScrollInterval = interval;
    await _settingsRepository.saveAutoScrollInterval(interval);
    notifyListeners();
  }

  Future<void> setUseBottomAppBar(bool useBottomAppBar) async {
    _useBottomAppBar = useBottomAppBar;
    await _settingsRepository.saveUseBottomAppBar(useBottomAppBar);
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
        // _emitHashMismatchError(errorMessage);
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

      // AI解析結果からNSFW判定を保存（既存のNSFWデータベース + 特殊タグで同期）
      bool isNsfw = false;
      for (final tag in tags) {
        if (AiService().isNsfw(tag)) {
          isNsfw = true;
          break;
        }
      }
      // 特殊タグとして保存（AI判定）
      await NsfwService.instance.setAiNsfwRatingAsTags(file.path, isNsfw);

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

  void stopAiAnalysis(AiService aiService) {
    if (!_isAnalyzing) return;
    aiService.dispose();
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
      // フォルダ統計を自動更新
      _checkAndAutoUpdateFolderStats();
    }
    // 重い処理は非同期で実行
    _updateProgressAsync();
  }

  Future<void> removeFolder(String path) async {
    _folderSettings.removeWhere((f) => f.path == path);
    _folderStats.remove(path); // 統計からも削除
    await _saveFolders();
    // フォルダ統計を自動更新
    _checkAndAutoUpdateFolderStats();
    notifyListeners();
    // 重い処理は非同期で実行
    _updateProgressAsync();
  }

  Future<void> toggleFolderEnabled(String path) async {
    final folder = _folderSettings.firstWhere((f) => f.path == path);
    folder.isEnabled = !folder.isEnabled;
    await _saveFolders();
    // フォルダ統計を自動更新
    _checkAndAutoUpdateFolderStats();
    notifyListeners();
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

  Future<void> setVisibleRatings(Map<Rating, bool> visibleRatings) async {
    _visibleRatings = Map.from(visibleRatings);
    _ratingSettingsChanged = true;
    await _settingsRepository.saveVisibleRatings(_visibleRatings);
    notifyListeners();
  }

  Future<void> setRatingVisibility(Rating rating, bool isVisible) async {
    _visibleRatings[rating] = isVisible;
    _ratingSettingsChanged = true;
    await _settingsRepository.saveVisibleRatings(_visibleRatings);
    notifyListeners();
  }

  void markRatingSettingsAsProcessed() {
    _ratingSettingsChanged = false;
  }

  /// フォルダ統計を更新
  Future<void> updateFolderStats() async {
    if (_isUpdatingStats) return; // 重複実行を防ぐ

    _isUpdatingStats = true;
    notifyListeners();

    try {
      final stats = <String, Map<String, int>>{};

      for (final folder in _folderSettings) {
        try {
          // 並列で統計を取得
          final results = await Future.wait([
            _imageRepository.getTotalFileCountInFolder(folder.path),
            DatabaseHelper.instance.getTaggedImageCountInFolder(folder.path),
          ]);

          stats[folder.path] = {
            'totalFiles': results[0],
            'taggedFiles': results[1],
          };

          log(
            'Folder stats updated for ${folder.path}: totalFiles=${results[0]}, taggedFiles=${results[1]}',
          );
        } catch (e) {
          log('Error getting stats for folder ${folder.path}: $e');
          stats[folder.path] = {'totalFiles': 0, 'taggedFiles': 0};
        }
      }

      _folderStats = stats;
    } finally {
      _isUpdatingStats = false;
      notifyListeners();
    }
  }

  /// フォルダパスの変更を検出して自動更新
  void _checkAndAutoUpdateFolderStats() {
    if (!_isAutoUpdateEnabled) return;

    final currentFolderPaths = _folderSettings.map((f) => f.path).toList()
      ..sort();

    // 前回と比較して変更があった場合のみ更新
    if (_lastFolderPaths.join(',') != currentFolderPaths.join(',')) {
      _lastFolderPaths = currentFolderPaths;
      log('Folder settings changed, triggering stats update');
      // 非同期で統計を更新（UIをブロックしない）
      updateFolderStats();
    }
  }

  /// 統計を強制的に更新（設定画面表示時など）
  void forceUpdateFolderStats() {
    if (!_isAutoUpdateEnabled) return;
    log('Force updating folder stats');
    updateFolderStats();
  }

  /// 権限変更後の統計更新（キャッシュクリア付き）
  void updateFolderStatsAfterPermissionChange() {
    if (!_isAutoUpdateEnabled) return;
    log('Updating folder stats after permission change');
    // ImageRepositoryのキャッシュをクリア
    _imageRepository.clearCache();
    // 統計を更新
    updateFolderStats();
  }

  /// 自動更新の有効/無効を切り替え
  void setAutoUpdateEnabled(bool enabled) async {
    _isAutoUpdateEnabled = enabled;
    await _settingsRepository.saveIsAutoUpdateEnabled(enabled);
    notifyListeners();
  }

  /// 特定フォルダの統計を取得
  Map<String, int> getFolderStat(String folderPath) {
    return _folderStats[folderPath] ?? {'totalFiles': 0, 'taggedFiles': 0};
  }
}
