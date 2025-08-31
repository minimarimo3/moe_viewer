import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'service/ai_service.dart';
import 'service/database_helper.dart';
import 'service/file_crypto_service.dart';
import 'service/ai_model_definitions.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

class FolderSetting {
  final String path;
  bool isEnabled;
  final bool isDeletable;

  FolderSetting({
    required this.path,
    this.isEnabled = true,
    this.isDeletable = true,
  });

  // MapからFolderSettingに変換するためのファクトリコンストラクタ
  factory FolderSetting.fromMap(Map<String, dynamic> map) {
    return FolderSetting(
      path: map['path'],
      isEnabled: map['isEnabled'],
      isDeletable: map['isDeletable'],
    );
  }

  // FolderSettingをMapに変換するメソッド
  Map<String, dynamic> toMap() {
    return {'path': path, 'isEnabled': isEnabled, 'isDeletable': isDeletable};
  }
}

class SettingsProvider extends ChangeNotifier {
  static const String _foldersKey = 'folder_settings';
  static const String _nsfwKey = 'nsfw_filter_enabled';
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

  static const String _selectedModelKey = 'selected_model';
  String _selectedModelId = 'none';
  String get selectedModelId => _selectedModelId;

  static const String _gridCrossAxisCountKey = 'grid_cross_axis_count';
  int _gridCrossAxisCount = 3;
  int get gridCrossAxisCount => _gridCrossAxisCount;

  static const String _themeModeKey = 'theme_mode';
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  static const String _lastScrollIndexKey = 'last_scroll_index';
  int _lastScrollIndex = 0;
  int get lastScrollIndex => _lastScrollIndex;

  List<FolderSetting> _folderSettings = [];
  List<FolderSetting> get folderSettings => _folderSettings;

  /// ファイル破損チェック
  bool _isModelCorrupted = false;
  bool get isModelCorrupted => _isModelCorrupted;

  bool _isCheckingHash = false;
  bool get isCheckingHash => _isCheckingHash;

  /// ファイルダウンロードのキャンセル用
  CancelToken? _cancelToken;

  // すべての設定を読み込むように名前を変更
  Future<void> init() async {
    // TODO: checkModelStatus();を実行したい。でもmodelDefが必要
    final prefs = await SharedPreferences.getInstance();

    _selectedModelId = prefs.getString(_selectedModelKey) ?? 'none';
    _gridCrossAxisCount = prefs.getInt(_gridCrossAxisCountKey) ?? 3;
    final themeIndex = prefs.getInt(_themeModeKey) ?? 0;
    _themeMode = ThemeMode.values[themeIndex];
    _lastScrollIndex = prefs.getInt(_lastScrollIndexKey) ?? 0;

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

    _nsfwFilterEnabled = prefs.getBool(_nsfwKey) ?? false;
    await updateOverallProgress();
    notifyListeners();
  }

  Future<void> setSelectedModel(String modelId) async {
    _selectedModelId = modelId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedModelKey, modelId);
    notifyListeners();
    // TODO: モデル別のデータベースを作成:w
  }

    Future<void> setGridCrossAxisCount(int count) async {
    _gridCrossAxisCount = count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_gridCrossAxisCountKey, count);
    notifyListeners();
  }

    Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
    notifyListeners();
  }

    Future<void> setLastScrollIndex(int index) async {
    _lastScrollIndex = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastScrollIndexKey, index);
    // 注: ここではUI全体の再描画は不要なため、notifyListeners()は呼ばない
  }

  Future<void> updateOverallProgress() async {
    // --- ファイル総数の計算ロジック ---
    final enabledFolders = _folderSettings.where((f) => f.isEnabled).toList();
    final selectedPaths = enabledFolders.map((f) => f.path).toList();
    List<File> allImageFiles = [];

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
        // ★★★ ここではAssetEntityの数を数えるだけで、Fileには変換しない（高速化） ★★★
        final assetCount = await album.assetCountAsync;
        _totalFileCount += assetCount;
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
                allImageFiles.add(fileEntity);
              }
            }
          }
        }
      }
    }
    _totalFileCount = allImageFiles.length;
    // --- 計算ロジックここまで ---

    final analyzedCount = await DatabaseHelper.instance.getAnalyzedFileCount();

    if (_totalFileCount < analyzedCount) {
      _totalFileCount = analyzedCount;
    }
    _analyzedFileCount = analyzedCount;
  }

  Future<void> checkModelStatus(AiModelDefinition modelDef) async {
    _isCheckingHash = true;
    notifyListeners();

    final modelPath = await _getModelPath(modelDef.modelFileName);
    final labelsPath = await _getLabelsPath(modelDef.labelFileName);
    final modelFile = File(modelPath);
    final labelsFile = File(labelsPath);

    if (await modelFile.exists() && await labelsFile.exists()) {
      // ★★★ ファイルが存在する場合、ハッシュ値を検証 ★★★
      // final modelBytes = await modelFile.readAsBytes();
      // final modelHash = sha256.convert(modelBytes).toString();

      // final labelsBytes = await labelsFile.readAsBytes();
      // final labelsHash = sha256.convert(labelsBytes).toString();
      final modelHashFuture = computeFileHash(modelPath);
      final labelsHashFuture = computeFileHash(labelsPath);

      // 両方の計算が終わるのを待つ
      final results = await Future.wait([modelHashFuture, labelsHashFuture]);
      final modelHash = results[0];
      final labelsHash = results[1];

      if (modelHash == modelDef.modelFileHash &&
          labelsHash == modelDef.labelFileHash) {
        _isModelDownloaded = true;
        _isModelCorrupted = false;
      } else {
        _isModelDownloaded = true;
        _isModelCorrupted = true;
        // これはUIに表示されるので通知を飛ばさなくていい
        log(
          "ファイルが破損しています。: 期待されるハッシュ: (${modelDef.modelFileHash}, ${modelDef.labelFileHash}), 実際のハッシュ: $modelHash, $labelsHash",
        );
      }
    } else {
      _isModelDownloaded = false;
      _isModelCorrupted = false;
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
      _isDownloading = false;
      notifyListeners();
      return;
    }

    if (totalBytes > 0 && downloadedBytes == totalBytes) {
      log('ダウンロードは既に完了しています。: $savePath');
      _downloadProgress = 1.0;
      // isDownloadingは、呼び出し元のdownloadModel関数で最後にfalseにするのでここでは変えない
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

      // ★★★ .listenの代わりにawait forを使い、ストリームを順番に処理する ★★★
      await for (final chunk in response.data!.stream) {
        await raf.writeFrom(chunk);
        await raf.flush(); // ★★★ これで、安全に毎回flushできる ★★★

        currentTotalBytes += chunk.length;
        if (totalBytes > 0) {
          _downloadProgress = currentTotalBytes / totalBytes;
          notifyListeners();
        }
      }
    } catch (e) {
      log('ダウンロードリクエストまたは書き込み中にエラー: $e');
      rethrow; // エラーを呼び出し元に伝える
    } finally {
      // ★★★ 成功しようが失敗しようが、必ずファイルを閉じる ★★★
      await raf?.close();
    }
  }

  Future<void> downloadModel(AiModelDefinition modelDef) async {
    if (_isDownloading) return;

    _isDownloading = true;
    _downloadProgress = 0.0;
    _cancelToken = CancelToken();
    notifyListeners();

    final modelPath = await _getModelPath(modelDef.modelFileName);
    final labelsPath = await _getLabelsPath(modelDef.labelFileName);

    try {
      await downloadWithResume(modelDef.modelDownloadUrl, modelPath);
      await downloadWithResume(modelDef.labelDownloadUrl, labelsPath);

      _isModelDownloaded = true;
      log("モデルのダウンロードが完了しました。");
    } catch (e) {
      // TODO: ダウンロードエラーをユーザーに通知する
      //  確か通知できてなかったと思う。解析開始時に破損チェックすればいいかな？
      if (e is DioException && e.type == DioExceptionType.cancel) {
        log('ユーザーがダウンロードをキャンセルしました。');
      } else {
        log("ダウンロードエラー: $e");
      }
      // エラー発生時はダウンロードしたファイルを削除
      if (await File(modelPath).exists()) {
        await File(modelPath).delete();
      }
      if (await File(labelsPath).exists()) {
        await File(labelsPath).delete();
      }
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
    await checkModelStatus(modelDef);
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
    // log("この関数は次の関数から呼び出されました: ${StackTrace.current}");
    if (_isAnalyzing) return;

    // 1. 現在選択されているモデルの定義を取得
    final selectedModelDef = availableModels.firstWhere(
      (m) => m.id == _selectedModelId,
      orElse: () => availableModels.first,
    );

    // 2. モデルがダウンロード済みかチェック
    await checkModelStatus(selectedModelDef);
    if (!_isModelDownloaded || _isModelCorrupted) {
      log("モデルが利用可能ではありません。ダウンロードまたは修復してください。");
      return;
    }

    // 3. AIサービスに必要なモデルがロードされているか確認・準備させる
    await aiService.ensureModelLoaded(selectedModelDef);

    _isAnalyzing = true;

    await updateOverallProgress();
    notifyListeners();

    // --- ここからファイルリスト構築ロジック ---
    final enabledFolders = _folderSettings.where((f) => f.isEnabled).toList();
    final selectedPaths = enabledFolders.map((f) => f.path).toList();
    List<File> allImageFiles = [];

    final allAlbums = await PhotoManager.getAssetPathList(
      filterOption: FilterOptionGroup(includeHiddenAssets: true),
    );
    final albumMap = {
      for (var album in allAlbums) album.name.toLowerCase(): album,
    };
    final hasFullAccess =
        await Permission.manageExternalStorage.status.isGranted;
    List<String> pathsForDirectScan = [];

    for (final path in selectedPaths) {
      final folderName = path.split('/').last.toLowerCase();
      if (albumMap.containsKey(folderName)) {
        final album = albumMap[folderName]!;
        final assets = await album.getAssetListRange(
          start: 0,
          end: await album.assetCountAsync,
        );
        for (final asset in assets) {
          final file = await asset.file;
          if (file != null) allImageFiles.add(file);
        }
      } else if (hasFullAccess) {
        pathsForDirectScan.add(path);
      }
    }

    for (final path in pathsForDirectScan) {
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
              allImageFiles.add(fileEntity);
            }
          }
        }
      }
    }
    // --- ファイルリスト構築ロジックここまで ---

    final dbHelper = DatabaseHelper.instance;
    final analyzedPaths = await dbHelper.getAnalyzedImagePaths();

    // 解析済みファイルを除外
    final filesToAnalyze = allImageFiles
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

      /*
      final tags = await AiService().analyzeImage(file);
      log("解析結果: ${file.path} -> $tags");
      await dbHelper.insertOrUpdateTag(file.path, tags);
      */
      final result = await aiService.analyzeImage(file);
      // final tags = await AiService().analyzeImage(file);
      final tags = result['tags'] as List<String>? ?? ['AI解析エラー'];
      final imageBase64 = result['image'] as String?;

      await dbHelper.insertOrUpdateTag(file.path, tags);

      _analyzedFileCount++;
      _lastFoundTags = tags;
      _currentAnalyzedImageBase64 = imageBase64; // ★★★ 解析結果から画像を取得
      notifyListeners();

      _analyzedFileCount++;
      _lastFoundTags = tags;
      // AIが見ている画像をBase64で取得
      // _currentAnalyzedImageBase64 = AiService().latestAnalyzedImageBase64;
      _currentAnalyzedImageBase64 = null;
      _analysisProgress = i + 1;
      notifyListeners();
    }

    _isAnalyzing = false;
    _currentAnalyzingFile = '';
    _currentAnalyzedImageBase64 = null;
    await updateOverallProgress();
    notifyListeners();
    log("AI解析が完了または停止しました。");
  }

  // ★★★ AI解析を停止する新しい関数 ★★★
  void stopAiAnalysis() {
    _isAnalyzing = false;
    _currentAnalyzingFile = '';
    _currentAnalyzedImageBase64 = null;
    notifyListeners();
  }

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
    await updateOverallProgress();
  }

  Future<void> removeFolder(String path) async {
    _folderSettings.removeWhere((f) => f.path == path);
    await _saveFolders();
    await updateOverallProgress();
  }

  // ★★★ フォルダの有効/無効を切り替える新しい関数 ★★★
  Future<void> toggleFolderEnabled(String path) async {
    final folder = _folderSettings.firstWhere((f) => f.path == path);
    folder.isEnabled = !folder.isEnabled;
    await _saveFolders();
    await updateOverallProgress();
  }

  // ★★★ NSFW設定を変更・保存する関数を追加 ★★★
  Future<void> setNsfwFilter(bool isEnabled) async {
    // TODO: これ使ってなかったと思う。
    _nsfwFilterEnabled = isEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_nsfwKey, isEnabled);
    notifyListeners();
  }
}
