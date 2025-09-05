import 'dart:io';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ThumbnailRequest {
  final String filePath;
  final int width;
  final int? height; // ★★★ 高さはnullを許容
  // 可能なら元画像の代わりに使うベースキャッシュ（プリジェネ）パス
  final String? baseCachePath;
  ThumbnailRequest(
    this.filePath,
    this.width,
    this.height, {
    this.baseCachePath,
  });
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

    // まずはベースキャッシュ（プリジェネ済み）があればそれを優先して読み込む
    Uint8List bytes;
    if (request.baseCachePath != null &&
        await File(request.baseCachePath!).exists()) {
      bytes = await File(request.baseCachePath!).readAsBytes();
      log('Using base cached image for: $filePath');
    } else {
      bytes = await file.readAsBytes();
    }
    final image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception('Failed to decode image');
    }

    // メモリ効率のために最大サイズを制限
    final maxDimension = 2048;
    int targetWidth = request.width;
    int? targetHeight = request.height;

    if (targetWidth > maxDimension) {
      final scale = maxDimension / targetWidth;
      targetWidth = maxDimension;
      if (targetHeight != null) {
        targetHeight = (targetHeight * scale).round();
      }
    }

    final thumbnail = img.copyResize(
      image,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.linear, // 高品質な補間を指定
    );

    final result = Uint8List.fromList(
      img.encodeJpg(thumbnail, quality: 90),
    ); // 高品質を維持
    log('Thumbnail generation completed for: $filePath');

    return result;
  } catch (e) {
    log('Thumbnail generation failed for $filePath: $e');
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
  // プリジェネ済みのベースキャッシュがあれば、それをソースに用いるためにパスを渡す
  final tempDir = await getTemporaryDirectory();
  final baseCacheFileName = 'thumbbase_${filePath.hashCode}.jpg';
  final baseCachePath = p.join(tempDir.path, baseCacheFileName);
  return compute(
    _generateThumbnail,
    ThumbnailRequest(filePath, width, height, baseCachePath: baseCachePath),
  );
}

// --- 追加ユーティリティ: プリジェネ（ベースキャッシュ）とクリア処理 ---

/// 指定した画像の「ベース」サムネイルを事前生成して、一意のパスに保存する。
/// 表示時のサムネイル生成は、このベース画像からの縮小に切り替わるため軽くなる。
/// 生成先: getTemporaryDirectory()/thumbbase_<hash>.jpg
Future<void> precacheBaseThumbnail(
  String filePath, {
  int baseWidth = 2048,
}) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final baseCacheFileName = 'thumbbase_${filePath.hashCode}.jpg';
    final baseCachePath = p.join(tempDir.path, baseCacheFileName);

    final baseFile = File(baseCachePath);
    if (await baseFile.exists()) {
      // 既に存在する場合はスキップ
      return;
    }

    // ベース画像の生成（高さは自動）
    final data = await compute(
      _generateThumbnail,
      ThumbnailRequest(
        filePath,
        baseWidth,
        null,
        // baseCachePath は入力としては不要だが、将来の最適化に備えて渡しておく
        baseCachePath: null,
      ),
    );
    if (data.isEmpty) return;
    await baseFile.writeAsBytes(data, flush: false);
  } catch (e) {
    log('precacheBaseThumbnail failed for $filePath: $e');
  }
}

/// 一覧グリッド用（幅/高さが動的に変わる）サムネイルのキャッシュを一掃する。
/// ベースキャッシュ（thumbbase_）は保持し、幅依存のキャッシュ（thumb_..._w*_h*.jpg）のみ削除する。
Future<void> clearGridThumbnailsCache() async {
  try {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory(tempDir.path);
    if (!await dir.exists()) return;
    final entries = await dir.list().toList();
    for (final e in entries) {
      if (e is File) {
        final name = p.basename(e.path);
        // width/heightを含む通常サムネイルのみ削除（ベースは保持）
        if (name.startsWith('thumb_') && name.contains('_w')) {
          try {
            await e.delete();
          } catch (err) {
            // ignore per-file errors
          }
        }
      }
    }
  } catch (e) {
    log('clearGridThumbnailsCache failed: $e');
  }
}

/// 指定の幅/高さでグリッド用サムネイルを生成し、
/// FileThumbnail と同じ命名規則のキャッシュファイル（thumb_..._w*_h*.jpg）に保存する。
/// これにより表示時はディスクから即読み込みが可能になり、グレー表示を避けられる。
Future<void> generateAndCacheGridThumbnail(
  String filePath,
  int width, {
  int? height,
}) async {
  try {
    final data = await computeThumbnail(filePath, width, height: height);
    if (data.isEmpty) return;
    final tempDir = await getTemporaryDirectory();
    final h = height?.toString() ?? 'auto';
    final cacheFileName = 'thumb_${filePath.hashCode}_w${width}_h$h.jpg';
    final cacheFile = File(p.join(tempDir.path, cacheFileName));
    if (await cacheFile.exists()) return; // 既にあるならスキップ
    await cacheFile.writeAsBytes(data, flush: false);
  } catch (e) {
    log('generateAndCacheGridThumbnail failed for $filePath: $e');
  }
}
