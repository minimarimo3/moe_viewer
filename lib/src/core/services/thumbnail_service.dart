import 'dart:io';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

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

    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception('Failed to decode image');
    }

    // メモリ効率のために最大サイズを制限
    final maxDimension = 1024;
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

    return result;
  } catch (e) {
    log('Thumbnail generation failed for $filePath: $e');
    // エラーの場合は空のバイト配列を返す
    return Uint8List(0);
  }
}

// compute関数を使って、generateThumbnailをバックグラウンドで実行する
Future<Uint8List> computeThumbnail(String filePath, int width, {int? height}) {
  return compute(_generateThumbnail, ThumbnailRequest(filePath, width, height));
}
