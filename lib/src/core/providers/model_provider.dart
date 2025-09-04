import 'dart:io';
import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/ai_model_definition.dart';
import '../repositories/settings_repository.dart';
import '../services/file_crypto_service.dart';

class ModelProvider extends ChangeNotifier {
  final SettingsRepository _repo = SettingsRepository();

  String _selectedModelId = 'none';
  String get selectedModelId => _selectedModelId;

  bool _isModelDownloaded = false;
  bool get isModelDownloaded => _isModelDownloaded;
  bool _isModelCorrupted = false;
  bool get isModelCorrupted => _isModelCorrupted;
  bool _isCheckingHash = false;
  bool get isCheckingHash => _isCheckingHash;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;
  double _downloadProgress = 0.0;
  double get downloadProgress => _downloadProgress;
  String? _downloadErrorMessage;
  String? get downloadErrorMessage => _downloadErrorMessage;
  int _downloadErrorVersion = 0;
  int get downloadErrorVersion => _downloadErrorVersion;
  CancelToken? _cancelToken;

  Future<void> load() async {
    _selectedModelId = await _repo.loadSelectedModel();
    notifyListeners();
  }

  Future<void> setSelectedModel(String id) async {
    _selectedModelId = id;
    await _repo.saveSelectedModel(id);
    notifyListeners();
  }

  void _emitDownloadError(String message) {
    _downloadErrorMessage = message;
    _downloadErrorVersion++;
    notifyListeners();
  }

  Future<String> _modelPath(String fileName) async =>
      '${(await getApplicationSupportDirectory()).path}/$fileName';
  Future<String> _labelsPath(String fileName) async =>
      '${(await getApplicationSupportDirectory()).path}/$fileName';

  Future<void> checkModelStatus(AiModelDefinition modelDef) async {
    _isCheckingHash = true;
    notifyListeners();
    final modelPath = await _modelPath(modelDef.modelFileName);
    final labelsPath = await _labelsPath(modelDef.labelFileName);
    final modelFile = File(modelPath);
    final labelsFile = File(labelsPath);
    if (await modelFile.exists() && await labelsFile.exists()) {
      final results = await Future.wait([
        computeFileHash(modelPath),
        computeFileHash(labelsPath),
      ]);
      final modelHash = results[0];
      final labelsHash = results[1];
      if (modelHash == modelDef.modelFileHash &&
          labelsHash == modelDef.labelFileHash) {
        _isModelDownloaded = true;
        _isModelCorrupted = false;
      } else {
        _isModelDownloaded = true;
        _isModelCorrupted = true;
        log(
          'Model corrupted. expected: (${modelDef.modelFileHash}, ${modelDef.labelFileHash}) actual: $modelHash, $labelsHash',
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
    if (_isDownloading && _cancelToken != null) {
      _cancelToken!.cancel('Operation cancelled by user.');
    }
  }

  Future<void> _downloadWithResume(String url, String savePath) async {
    _isDownloading = true;
    notifyListeners();
    final dio = Dio();
    int downloadedBytes = 0;
    final file = File(savePath);
    if (await file.exists()) {
      downloadedBytes = await file.length();
    }
    int totalBytes = 0;
    try {
      final response = await dio.head(url);
      totalBytes = int.parse(
        response.headers.value(Headers.contentLengthHeader) ?? '0',
      );
    } catch (e) {
      _emitDownloadError('ファイルサイズの取得に失敗しました\n$e');
      _isDownloading = false;
      notifyListeners();
      return;
    }
    if (totalBytes > 0 && downloadedBytes == totalBytes) {
      _downloadProgress = 1.0;
      return;
    }
    RandomAccessFile? raf;
    try {
      final response = await dio.get<ResponseBody>(
        url,
        cancelToken: _cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Range': 'bytes=$downloadedBytes-'},
        ),
      );
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
    } finally {
      await raf?.close();
    }
  }

  Future<void> downloadModel(AiModelDefinition modelDef) async {
    if (_isDownloading) return;
    _isDownloading = true;
    _downloadProgress = 0.0;
    _cancelToken = CancelToken();
    notifyListeners();
    final modelPath = await _modelPath(modelDef.modelFileName);
    final labelsPath = await _labelsPath(modelDef.labelFileName);
    try {
      await _downloadWithResume(modelDef.modelDownloadUrl, modelPath);
      await _downloadWithResume(modelDef.labelDownloadUrl, labelsPath);
      _isModelDownloaded = true;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        // user cancel
      } else {
        _emitDownloadError('AIモデルのダウンロードに失敗しました');
      }
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
    await checkModelStatus(modelDef);
  }
}
