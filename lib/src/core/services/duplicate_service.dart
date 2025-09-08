import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:xxh3/xxh3.dart';

import '../models/folder_setting.dart';

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
}
