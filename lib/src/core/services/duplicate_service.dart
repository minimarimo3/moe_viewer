import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:photo_manager/photo_manager.dart';

import 'package:xxh3/xxh3.dart';

import '../models/folder_setting.dart';
import '../services/database_helper.dart';
import '../utils/pixiv_utils.dart';

typedef DuplicateMap = Map<String, List<String>>; // hash -> [filePaths]

class DuplicateService {
  // 1MB チャンク。小さい画像は一括読み込み、そこそこ大きい場合はストリーミング
  static const int _smallFileThreshold = 1 * 1024 * 1024;
  static const int _chunkSize = 256 * 1024; // 256KB

  Future<DuplicateMap> findDuplicates(
    List<FolderSetting> folderSettings, {
    void Function(int scanned, int duplicatesFound)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final enabledFolders = folderSettings.where((f) => f.isEnabled).toList();
    final Map<String, List<String>> groupsByHash = {};

    int scanned = 0;
    int dupFiles = 0;

    for (final folder in enabledFolders) {
      final dir = Directory(folder.path);
      if (!await dir.exists()) continue;

      try {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (shouldCancel?.call() == true) break;

          if (entity is! File) continue;
          final lower = entity.path.toLowerCase();
          if (!(lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.png') ||
              lower.endsWith('.gif') ||
              lower.endsWith('.webp') ||
              lower.endsWith('.bmp') ||
              lower.endsWith('.heic') ||
              lower.endsWith('.heif'))) {
            continue;
          }

          // .nomedia はスキップ
          if (entity.path.split('/').last == '.nomedia') continue;

          try {
            final hash = await _xxh3File(entity);
            final key = hash.toRadixString(16).padLeft(16, '0');
            final list = groupsByHash.putIfAbsent(key, () => []);
            list.add(entity.path);
            if (list.length == 2) {
              // 新たに重複が見つかったタイミングでカウント
              dupFiles += 2;
            } else if (list.length > 2) {
              dupFiles += 1;
            }
          } catch (e) {
            log('Hash error for ${entity.path}: $e');
          }

          scanned++;
          if (scanned % 50 == 0) {
            onProgress?.call(scanned, dupFiles);
            // 小休止でUIに譲る
            await Future.delayed(const Duration(milliseconds: 1));
          }
        }
      } catch (e) {
        log('Directory scan failed for ${folder.path}: $e');
      }
    }

    onProgress?.call(scanned, dupFiles);
    // 1件しかないものは除外
    groupsByHash.removeWhere((_, v) => v.length < 2);
    return groupsByHash;
  }

  Future<int> _xxh3File(File file) async {
    final length = await file.length();
    if (length <= _smallFileThreshold) {
      final bytes = await file.readAsBytes();
      return xxh3(Uint8List.fromList(bytes));
    }
    // ストリームでハッシュ
    final state = xxh3Stream();
    final raf = await file.open();
    try {
      int offset = 0;
      while (offset < length) {
        final toRead = (length - offset) < _chunkSize
            ? (length - offset)
            : _chunkSize;
        final chunk = await raf.read(toRead);
        if (chunk.isEmpty) break;
        state.update(Uint8List.fromList(chunk));
        offset += chunk.length;
      }
    } finally {
      await raf.close();
    }
    return state.digest();
  }

  /// 重複と判断されたファイルに予約タグ `__duplicate__` を付与する。
  Future<void> tagDuplicates(DuplicateMap groups) async {
    final db = DatabaseHelper.instance;
    for (final files in groups.values) {
      for (final path in files) {
        await db.editTags(path, (tags) {
          if (!tags.contains(ReservedTags.duplicate)) {
            tags.add(ReservedTags.duplicate);
          }
          return tags;
        });
      }
    }
  }

  /// 重複ファイルを削除（各グループで先頭1つを残し、それ以外を削除）
  /// 戻り値は削除したファイルパス一覧。
  Future<List<String>> deleteDuplicates(DuplicateMap groups) async {
    // TODO: 削除対象のタグを保存する側のタグにも反映させる
    final deleted = <String>[];
    for (final files in groups.values) {
      log('Deleting duplicates: $files');
      if (files.length <= 1) continue;
      // 最も古い/新しいなどのポリシーがあればここに実装。現状は先頭を残す。
      for (var i = 1; i < files.length; i++) {
        final path = files[i];
        try {
          var removed = false;

          // まず PhotoManager を使って削除を試みる（platform の権限下で安全に削除できることがある）
          try {
            // PhotoManager 側でこのパスに対応する AssetEntity を探す
            final albums = await PhotoManager.getAssetPathList(hasAll: true);
            String? foundId;
            for (final album in albums) {
              // 少数ファイルの探索を最適化するため範囲指定で取得
              final total = await album.assetCountAsync;
              const pageSize = 200;
              for (var start = 0; start < total; start += pageSize) {
                final end = (start + pageSize) > total
                    ? total - 1
                    : (start + pageSize - 1);
                final list = await album.getAssetListRange(
                  start: start,
                  end: end,
                );
                for (final a in list) {
                  try {
                    final file = await a.file;
                    if (file != null && file.path == path) {
                      foundId = a.id;
                      break;
                    }
                  } catch (_) {
                    // ignore file access errors per-asset
                  }
                }
                if (foundId != null) break;
              }
              if (foundId != null) break;
            }

            if (foundId != null) {
              final dynamic result = await PhotoManager.editor.deleteWithIds([
                foundId,
              ]);
              if (result == true || (result is List && result.isNotEmpty)) {
                deleted.add(path);
                await DatabaseHelper.instance.purgeAllForPath(path);
                log(
                  'Deleted duplicate via PhotoManager: $path (assetId=$foundId)',
                );
                removed = true;
              }
            }
          } catch (e) {
            // PhotoManager 削除が例外を投げる場合はフォールバックする
            log('PhotoManager delete failed for $path: $e');
          }

          if (removed) continue;

          // フォールバック: File.delete を試す
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
            deleted.add(f.path);
            // DBの付随情報もクリーンアップ
            await DatabaseHelper.instance.purgeAllForPath(f.path);
            log('Deleted duplicate file: ${f.path}');
          }
        } catch (e) {
          log('Failed to delete $path: $e');
        }
      }
    }
    return deleted;
  }
}
