import 'dart:io';
import 'dart:developer';

import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/folder_setting.dart';
import '../models/image_list.dart';
import '../models/rating.dart';
import '../services/nsfw_service.dart';

class ImageRepository {
  static const int _batchSize = 200; // バッチサイズを増やして効率化
  static const int _initialLoadCount = 100; // 初期表示用の画像数

  // キャッシュ用
  List<AssetPathEntity>? _cachedAlbums;
  Map<String, AssetPathEntity>? _cachedAlbumMap;
  List<String>? _cachedDirectScanPaths;

  // 遅延読み込み用の状態管理
  bool _isLoadingMore = false;
  // アルバムごとの読み込み済み件数を管理（グローバルカウンタだとスキップが発生するため）
  final Map<String, int> _loadedCountByAlbum = {};

  Future<ImageList> getAllImages(
    List<FolderSetting> folderSettings, {
    Map<Rating, bool>? visibleRatings,
  }) async {
    // セッションを開始するたびにアルバムごとの読み込み位置をリセット
    _loadedCountByAlbum.clear();
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

    _cachedDirectScanPaths ??= [];

    for (final path in selectedPaths) {
      final folderName = path.split('/').last.toLowerCase();

      // .nomediaファイルの存在をチェック
      final hasNomediaFile = await _hasNomediaFile(path);
      log('Checking folder: $path, has .nomedia: $hasNomediaFile');

      // .nomediaファイルがある場合は直接スキャンを強制
      if (hasNomediaFile) {
        log('Folder $path has .nomedia file, switching to direct scan');
        // manageExternalStorage の有無に関わらず直接スキャンを試みる
        if (!_cachedDirectScanPaths!.contains(path)) {
          _cachedDirectScanPaths!.add(path);
        }
        continue; // photo_managerによる処理をスキップ
      }

      if (_cachedAlbumMap!.containsKey(folderName)) {
        log('Found album for folder: $folderName');
        final album = _cachedAlbumMap![folderName]!;
        final totalCount = await album.assetCountAsync;
        log('Album $folderName has $totalCount assets');

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
              // レーティングフィルタリングをチェック
              if (await _shouldIncludeFile(file.path, visibleRatings)) {
                allDisplayItems.add(asset);
                allDetailFiles.add(file);
              }
            } else {
              log('Skipped null file for asset ${asset.id}');
            }
          }

          // UIの反応性を保つために小さな遅延を追加
          if (start + _batchSize < initialLoadCount) {
            await Future.delayed(
              const Duration(microseconds: 100),
            ); // マイクロ秒に変更して高速化
          }
        }

        // アルバムごとの読み込み位置を保存
        _loadedCountByAlbum[folderName] = initialLoadCount;
      } else if (!_cachedDirectScanPaths!.contains(path)) {
        log('Album not found for folder: $folderName, adding to direct scan');
        // アルバム未検出時も権限に依存せず直接スキャンを試みる
        _cachedDirectScanPaths!.add(path);
      }
    }

    // --- 特殊ルート (dart:io) の最適化 ---
    log('Processing direct scan paths: ${_cachedDirectScanPaths!}');
    for (final path in _cachedDirectScanPaths!) {
      final directory = Directory(path);
      if (await directory.exists()) {
        // 権限・可読性のプローブ（デバッグ強化）
        final manageGranted =
            await Permission.manageExternalStorage.status.isGranted;
        final legacyStorageGranted = await Permission.storage.status.isGranted;
        log(
          'Direct scan permission probe for $path => manageExternalStorage: $manageGranted, storage(read): $legacyStorageGranted',
        );

        // ルート直下に .nomedia があるか（この場合は明示選択なのでブロックしない）
        final rootHasNomedia = await _hasNomediaFile(path);

        // 先に1件だけ列挙できるか軽く確認（端末/OS差異時の見える化）
        int probeCount = 0;
        try {
          await for (final _ in directory.list(recursive: false).take(1)) {
            probeCount++;
          }
        } catch (e) {
          log('Directory probe error for $path: $e');
        }
        log(
          'Starting direct scan for: $path (probe entries: $probeCount, root .nomedia: $rootHasNomedia)',
        );

        await _scanDirectoryOptimized(
          directory,
          allDisplayItems,
          allDetailFiles,
          visibleRatings,
          rootPath: path,
          ignoreNomediaAtRoot: rootHasNomedia,
        );
      } else {
        log('Directory does not exist: $path');
      }
    }

    log('Total items found: ${allDisplayItems.length}');
    return ImageList(allDisplayItems, allDetailFiles);
  }

  /// レーティングフィルタリングに基づいて、ファイルを含めるかどうかを判定
  Future<bool> _shouldIncludeFile(
    String filePath,
    Map<Rating, bool>? visibleRatings,
  ) async {
    // レーティングフィルタが指定されていない場合は全て表示
    if (visibleRatings == null) return true;

    // ファイルのレーティングを取得
    final rating = await NsfwService.instance.getRatingFromTags(filePath);

    // レーティングの表示設定を確認
    return visibleRatings[rating] ?? true;
  }

  // 追加で画像を読み込む機能
  Future<ImageList> loadMoreImages(
    List<FolderSetting> folderSettings, {
    Map<Rating, bool>? visibleRatings,
  }) async {
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

          // 当該アルバムの読み込み済み件数を参照（未登録なら0）
          final loadedCount = _loadedCountByAlbum[folderName] ?? 0;

          if (loadedCount < totalCount) {
            final nextBatchEnd = (loadedCount + _batchSize > totalCount)
                ? totalCount
                : loadedCount + _batchSize;

            final assets = await album.getAssetListRange(
              start: loadedCount,
              end: nextBatchEnd,
            );

            for (final asset in assets) {
              final file = await asset.file;
              if (file != null) {
                // レーティングフィルタリングをチェック
                if (await _shouldIncludeFile(file.path, visibleRatings)) {
                  additionalDisplayItems.add(asset);
                  additionalDetailFiles.add(file);
                }
              }
            }

            // 読み込み位置を更新
            _loadedCountByAlbum[folderName] = nextBatchEnd;
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
    Map<Rating, bool>? visibleRatings, {
    required String rootPath,
    required bool ignoreNomediaAtRoot,
  }) async {
    final List<FileSystemEntity> entities = [];

    try {
      log('Starting directory scan: ${directory.path}');
      int totalFiles = 0;
      int validImageFiles = 0;
      int nomediaBlockedFiles = 0;

      // ストリームを使用してメモリ効率を向上
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          totalFiles++;
          final fileName = entity.path.split('/').last;

          // .nomediaファイルは除外
          if (fileName == '.nomedia') {
            log('Found .nomedia file at: ${entity.path}');
            continue;
          }

          final filePath = entity.path.toLowerCase();
          if (filePath.endsWith('.jpg') ||
              filePath.endsWith('.png') ||
              filePath.endsWith('.jpeg') ||
              filePath.endsWith('.gif') ||
              filePath.endsWith('.webp')) {
            // .nomediaファイルによってブロックされているかチェック
            if (await _isBlockedByNomediaConsideringRoot(
              entity.path,
              rootPath: rootPath,
              ignoreNomediaAtRoot: ignoreNomediaAtRoot,
            )) {
              nomediaBlockedFiles++;
              log('File blocked by .nomedia: ${entity.path}');
              continue;
            }

            // WebPサポートも追加
            entities.add(entity);
            validImageFiles++;

            // バッチサイズごとに処理
            if (entities.length >= _batchSize) {
              await _addBatchToLists(
                entities,
                allDisplayItems,
                allDetailFiles,
                visibleRatings,
              );
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
        await _addBatchToLists(
          entities,
          allDisplayItems,
          allDetailFiles,
          visibleRatings,
        );
      }

      log('Directory scan completed: ${directory.path}');
      log(
        'Total files: $totalFiles, Valid images: $validImageFiles, Blocked by .nomedia: $nomediaBlockedFiles',
      );
    } catch (e) {
      // ディレクトリアクセスエラーを静かに処理
      log('Directory scan error for ${directory.path}: $e');
    }
  }

  Future<void> _addBatchToLists(
    List<FileSystemEntity> entities,
    List<dynamic> allDisplayItems,
    List<File> allDetailFiles,
    Map<Rating, bool>? visibleRatings,
  ) async {
    for (final entity in entities) {
      if (entity is File) {
        // レーティングフィルタリングをチェック
        if (await _shouldIncludeFile(entity.path, visibleRatings)) {
          allDisplayItems.add(entity);
          allDetailFiles.add(entity);
        }
      }
    }
  }

  // キャッシュをクリアするメソッド（設定変更時に使用）
  void clearCache() {
    _cachedAlbums = null;
    _cachedAlbumMap = null;
    _cachedDirectScanPaths = null;
    _isLoadingMore = false;
    _loadedCountByAlbum.clear();
  }

  /// 指定フォルダの画像ファイル総数を取得
  Future<int> getTotalFileCountInFolder(String folderPath) async {
    try {
      // photo_managerからアルバムを検索
      final folderName = folderPath.split('/').last.toLowerCase();

      if (_cachedAlbums == null || _cachedAlbumMap == null) {
        final filterOption = FilterOptionGroup(includeHiddenAssets: true);
        _cachedAlbums = await PhotoManager.getAssetPathList(
          filterOption: filterOption,
        );
        _cachedAlbumMap = {
          for (var album in _cachedAlbums!) album.name.toLowerCase(): album,
        };
      }

      if (_cachedAlbumMap!.containsKey(folderName)) {
        final album = _cachedAlbumMap![folderName]!;
        return await album.assetCountAsync;
      }

      // 直接ディレクトリスキャン（権限に依存せず試行）
      final directory = Directory(folderPath);
      if (await directory.exists()) {
        int count = 0;
        await for (final entity in directory.list(recursive: true)) {
          if (entity is File) {
            final fileName = entity.path.split('/').last;

            // .nomediaファイルは除外
            if (fileName == '.nomedia') {
              continue;
            }

            // .nomediaファイルによってブロックされているかチェック
            if (await _isBlockedByNomedia(entity.path)) {
              continue;
            }

            final extension = entity.path.split('.').last.toLowerCase();
            if ([
              'jpg',
              'jpeg',
              'png',
              'gif',
              'bmp',
              'webp',
              'heic',
              'heif',
            ].contains(extension)) {
              count++;
            }
          }
        }
        return count;
      }

      return 0;
    } catch (e) {
      log('Error counting files in folder $folderPath: $e');
      return 0;
    }
  }

  /// 指定されたディレクトリに.nomediaファイルが存在するかチェック
  Future<bool> _hasNomediaFile(String directoryPath) async {
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        return false;
      }

      final nomediaFile = File('$directoryPath/.nomedia');
      return await nomediaFile.exists();
    } catch (e) {
      log('Error checking .nomedia file in $directoryPath: $e');
      return false;
    }
  }

  /// 指定されたファイルパスが.nomediaファイルによってブロックされているかチェック
  Future<bool> _isBlockedByNomedia(String filePath) async {
    try {
      // ファイルの親ディレクトリから、親ディレクトリまで遡って.nomediaファイルをチェック
      Directory currentDir = File(filePath).parent;

      while (currentDir.path != currentDir.parent.path) {
        final nomediaFile = File('${currentDir.path}/.nomedia');
        if (await nomediaFile.exists()) {
          log('File $filePath is blocked by .nomedia at ${currentDir.path}');
          return true;
        }
        currentDir = currentDir.parent;
      }

      return false;
    } catch (e) {
      log('Error checking .nomedia blocking for $filePath: $e');
      return false;
    }
  }

  /// ルート直下の .nomedia は「ユーザーが明示的に選んだフォルダ」であるため無視できる版
  /// - ignoreNomediaAtRoot=true のとき、rootPath 以下で見つかる .nomedia はブロックしない
  /// - rootPath より上位で見つかる .nomedia はブロック（一般的な意図しない隠し）
  Future<bool> _isBlockedByNomediaConsideringRoot(
    String filePath, {
    required String rootPath,
    required bool ignoreNomediaAtRoot,
  }) async {
    try {
      Directory currentDir = File(filePath).parent;
      final root = Directory(rootPath).absolute.path;

      while (currentDir.path != currentDir.parent.path) {
        final nomediaFile = File('${currentDir.path}/.nomedia');
        if (await nomediaFile.exists()) {
          // ルート直下の .nomedia は無視（明示選択されたフォルダのため）
          if (ignoreNomediaAtRoot && currentDir.path == root) {
            return false;
          }
          log('File $filePath is blocked by .nomedia at ${currentDir.path}');
          return true;
        }
        currentDir = currentDir.parent;
      }

      return false;
    } catch (e) {
      log('Error checking .nomedia(block considering root) for $filePath: $e');
      return false;
    }
  }
}
