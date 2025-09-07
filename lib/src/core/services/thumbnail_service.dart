import 'dart:io';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ThumbnailRequest {
  final String filePath;
  final int width;
  final int? height; // ★★★ 高さはnullを許容

  ThumbnailRequest(this.filePath, this.width, this.height);
}

// Isolate（バックグラウンド）で実行されるサムネイル生成関数
Future<Uint8List> _generateThumbnail(ThumbnailRequest request) async {
  final String filePath = request.filePath;
  final file = File(filePath);

  log('Generating thumbnail for: $filePath');

  try {
    // ファイルサイズをチェックして大きなファイルは処理をスキップ
    final fileStat = await file.stat();
    if (fileStat.size > 50 * 1024 * 1024) {
      // 50MB以上の場合はスキップ
      throw Exception('File too large: ${fileStat.size} bytes');
    }

    // 入力ソースは元ファイル
    final String srcPath = filePath;

    // メモリ効率のために最大サイズを制限
    const maxDimension = 2048;
    int targetWidth = request.width;
    int? targetHeight = request.height;

    if (targetWidth > maxDimension) {
      final scale = maxDimension / targetWidth;
      targetWidth = maxDimension;
      if (targetHeight != null) {
        targetHeight = (targetHeight * scale).round();
      }
    }

    // flutter_image_compress による高速リサイズ&圧縮
    final compressed = await fic.FlutterImageCompress.compressWithFile(
      srcPath,
      minWidth: targetWidth,
      // 高さ未指定の場合は縦長でも過度に小さくならないよう、それなりの下限を与える
      minHeight: targetHeight ?? (targetWidth * 2 ~/ 3),
      quality: 85,
      format: fic.CompressFormat.jpeg,
      keepExif: false,
      autoCorrectionAngle: true,
    );

    final result = Uint8List.fromList(compressed ?? const <int>[]);
    log('Thumbnail generation completed for: $filePath');

    return result;
  } catch (e) {
    log('Thumbnail generation failed for $filePath: $e');
    // エラーの場合は空のバイト配列を返す
    return Uint8List(0);
  }
}

// 高品質版のサムネイル生成関数（アルバム表示用）
Future<Uint8List> _generateHighQualityThumbnail(
  ThumbnailRequest request,
) async {
  final String filePath = request.filePath;
  final file = File(filePath);

  log('Generating high quality thumbnail for: $filePath');

  try {
    // ファイルサイズをチェック（高品質版では少し大きめまで許可）
    final fileStat = await file.stat();
    if (fileStat.size > 100 * 1024 * 1024) {
      // 100MB以上の場合はスキップ
      throw Exception('File too large: ${fileStat.size} bytes');
    }

    // 入力ソースは常にオリジナル（高品質重視）
    const maxDimension = 4096;
    int targetWidth = request.width;
    int? targetHeight = request.height;

    if (targetWidth > maxDimension) {
      final scale = maxDimension / targetWidth;
      targetWidth = maxDimension;
      if (targetHeight != null) {
        targetHeight = (targetHeight * scale).round();
      }
    }

    final compressed = await fic.FlutterImageCompress.compressWithFile(
      filePath,
      minWidth: targetWidth,
      minHeight: targetHeight ?? (targetWidth * 2 ~/ 3),
      quality: 95,
      format: fic.CompressFormat.jpeg,
      keepExif: false,
      autoCorrectionAngle: true,
    );

    final result = Uint8List.fromList(compressed ?? const <int>[]);
    log('High quality thumbnail generation completed for: $filePath');

    return result;
  } catch (e) {
    log('High quality thumbnail generation failed for $filePath: $e');
    // エラーの場合は空のバイト配列を返す
    return Uint8List(0);
  }
}

// compute関数を使って、generateThumbnailをバックグラウンドで実行する
Future<Uint8List> computeThumbnail(
  String filePath,
  int width, {
  int? height,
}) async {
  // flutter_image_compressはプラグインのためIsolateでは利用できない
  // そのため直接関数を呼び出す
  return _generateThumbnail(ThumbnailRequest(filePath, width, height));
}

// 高品質版のサムネイル生成（アルバム表示用）
Future<Uint8List> computeHighQualityThumbnail(
  String filePath,
  int width, {
  int? height,
}) async {
  return _generateHighQualityThumbnail(
    ThumbnailRequest(filePath, width, height),
  );
}

/// グリッド用サムネイルのキャッシュを一掃する。
Future<void> clearGridThumbnailsCache() async {
  try {
    await DefaultCacheManager().emptyCache();
  } catch (e) {
    log('clearGridThumbnailsCache failed: $e');
  }
}

/// 古い自前キャッシュファイルを削除する。
/// flutter_cache_manager移行に伴い、path_providerで作成された古いキャッシュファイルを削除。
Future<void> clearLegacyThumbnailCache() async {
  try {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(tempDir.path);
    if (!await dir.exists()) return;

    final entries = await dir.list().toList();
    int deletedCount = 0;

    for (final e in entries) {
      if (e is File) {
        final name = p.basename(e.path);
        // 旧命名規則のキャッシュファイルを削除
        if (name.startsWith('thumb_') || name.startsWith('thumbbase_')) {
          try {
            await e.delete();
            deletedCount++;
          } catch (err) {
            // 個別ファイルのエラーは無視
          }
        }
      }
    }

    log('Cleared $deletedCount legacy thumbnail cache files');
  } catch (e) {
    log('clearLegacyThumbnailCache failed: $e');
  }
}

/// 指定の幅/高さでグリッド用サムネイルを生成し、
/// flutter_cache_managerに保存する。
/// これにより表示時はディスクから即読み込みが可能になり、グレー表示を避けられる。
Future<void> generateAndCacheGridThumbnail(
  String filePath,
  int width, {
  int? height,
  bool highQuality = false,
}) async {
  try {
    final data = highQuality
        ? await computeHighQualityThumbnail(filePath, width, height: height)
        : await computeThumbnail(filePath, width, height: height);
    if (data.isEmpty) return;

    final h = height?.toString() ?? 'auto';
    final quality = highQuality ? 'hq' : 'std';
    final cacheKey = 'thumb_${filePath.hashCode}_w${width}_h${h}_$quality';

    // flutter_cache_managerに保存
    await DefaultCacheManager().putFile(cacheKey, data, fileExtension: '.jpg');
  } catch (e) {
    log('generateAndCacheGridThumbnail failed for $filePath: $e');
  }
}
