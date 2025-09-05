import 'dart:io';
import 'dart:developer';

import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/folder_setting.dart';
import '../models/image_list.dart';

class ImageRepository {
  static const int _batchSize = 200; // バッチサイズを増やして効率化
  static const int _initialLoadCount = 100; // 初期表示用の画像数

  // キャッシュ用
  List<AssetPathEntity>? _cachedAlbums;
  Map<String, AssetPathEntity>? _cachedAlbumMap;
  List<String>? _cachedDirectScanPaths;

  // 遅延読み込み用の状態管理
  bool _isLoadingMore = false;
  int _currentLoadedCount = 0;
  Future<ImageList> getAllImages(List<FolderSetting> folderSettings) async {
    final enabledFolders = folderSettings.where((f) => f.isEnabled).toList();
    final selectedPaths = enabledFolders.map((f) => f.path).toList();

    List<dynamic> allDisplayItems = [];
    List<File> allDetailFiles = [];

    // --- キャッシュされた公式ルート (photo_manager) ---
    if (_cachedAlbums == null || _cachedAlbumMap == null) {
      final filterOption = FilterOptionGroup(includeHiddenAssets: true);
      _cachedAlbums = await PhotoManager.getAssetPathList(
        filterOption: filterOption,
      );
      _cachedAlbumMap = {
        for (var album in _cachedAlbums!) album.name.toLowerCase(): album,
      };
    }

    final hasFullAccess =
        await Permission.manageExternalStorage.status.isGranted;
    _cachedDirectScanPaths ??= [];

    for (final path in selectedPaths) {
      final folderName = path.split('/').last.toLowerCase();

      if (_cachedAlbumMap!.containsKey(folderName)) {
        final album = _cachedAlbumMap![folderName]!;
        final totalCount = await album.assetCountAsync;

        // 初期読み込みは最初の一部のみ
        final initialLoadCount = totalCount < _initialLoadCount
            ? totalCount
            : _initialLoadCount;

        // バッチで読み込んで処理を分散
        for (int start = 0; start < initialLoadCount; start += _batchSize) {
          final end = (start + _batchSize > initialLoadCount)
              ? initialLoadCount
              : start + _batchSize;
          final assets = await album.getAssetListRange(start: start, end: end);

          for (final asset in assets) {
            final file = await asset.file;
            // ファイルが取得できるものだけを表示対象にする（インデックス不整合を防止）
            if (file != null) {
              allDisplayItems.add(asset);
              allDetailFiles.add(file);
            }
          }

          // UIの反応性を保つために小さな遅延を追加
          if (start + _batchSize < initialLoadCount) {
            await Future.delayed(
              const Duration(microseconds: 100),
            ); // マイクロ秒に変更して高速化
          }
        }

        _currentLoadedCount = initialLoadCount;
      } else if (hasFullAccess && !_cachedDirectScanPaths!.contains(path)) {
        _cachedDirectScanPaths!.add(path);
      }
    }

    // --- 特殊ルート (dart:io) の最適化 ---
    for (final path in _cachedDirectScanPaths!) {
      final directory = Directory(path);
      if (await directory.exists()) {
        await _scanDirectoryOptimized(
          directory,
          allDisplayItems,
          allDetailFiles,
        );
      }
    }

    return ImageList(allDisplayItems, allDetailFiles);
  }

  // 追加で画像を読み込む機能
  Future<ImageList> loadMoreImages(List<FolderSetting> folderSettings) async {
    if (_isLoadingMore) return ImageList([], []);

    _isLoadingMore = true;

    try {
      final enabledFolders = folderSettings.where((f) => f.isEnabled).toList();
      final selectedPaths = enabledFolders.map((f) => f.path).toList();

      List<dynamic> additionalDisplayItems = [];
      List<File> additionalDetailFiles = [];

      for (final path in selectedPaths) {
        final folderName = path.split('/').last.toLowerCase();

        if (_cachedAlbumMap!.containsKey(folderName)) {
          final album = _cachedAlbumMap![folderName]!;
          final totalCount = await album.assetCountAsync;

          if (_currentLoadedCount < totalCount) {
            final nextBatchEnd = (_currentLoadedCount + _batchSize > totalCount)
                ? totalCount
                : _currentLoadedCount + _batchSize;

            final assets = await album.getAssetListRange(
              start: _currentLoadedCount,
              end: nextBatchEnd,
            );

            for (final asset in assets) {
              final file = await asset.file;
              if (file != null) {
                additionalDisplayItems.add(asset);
                additionalDetailFiles.add(file);
              }
            }

            _currentLoadedCount = nextBatchEnd;
          }
        }
      }

      return ImageList(additionalDisplayItems, additionalDetailFiles);
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> _scanDirectoryOptimized(
    Directory directory,
    List<dynamic> allDisplayItems,
    List<File> allDetailFiles,
  ) async {
    final List<FileSystemEntity> entities = [];

    try {
      // ストリームを使用してメモリ効率を向上
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final filePath = entity.path.toLowerCase();
          if (filePath.endsWith('.jpg') ||
              filePath.endsWith('.png') ||
              filePath.endsWith('.jpeg') ||
              filePath.endsWith('.gif') ||
              filePath.endsWith('.webp')) {
            // WebPサポートも追加
            entities.add(entity);

            // バッチサイズごとに処理
            if (entities.length >= _batchSize) {
              _addBatchToLists(entities, allDisplayItems, allDetailFiles);
              entities.clear();
              // UIの反応性を保つために小さな遅延を追加
              await Future.delayed(
                const Duration(microseconds: 100),
              ); // マイクロ秒に変更して高速化
            }
          }
        }
      }

      // 残りのファイルを処理
      if (entities.isNotEmpty) {
        _addBatchToLists(entities, allDisplayItems, allDetailFiles);
      }
    } catch (e) {
      // ディレクトリアクセスエラーを静かに処理
      log('Directory scan error for ${directory.path}: $e');
    }
  }

  void _addBatchToLists(
    List<FileSystemEntity> entities,
    List<dynamic> allDisplayItems,
    List<File> allDetailFiles,
  ) {
    for (final entity in entities) {
      if (entity is File) {
        allDisplayItems.add(entity);
        allDetailFiles.add(entity);
      }
    }
  }

  // キャッシュをクリアするメソッド（設定変更時に使用）
  void clearCache() {
    _cachedAlbums = null;
    _cachedAlbumMap = null;
    _cachedDirectScanPaths = null;
    _currentLoadedCount = 0;
    _isLoadingMore = false;
  }
}
