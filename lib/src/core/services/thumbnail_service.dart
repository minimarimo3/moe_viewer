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
  final bytes = await file.readAsBytes();
  final image = img.decodeImage(bytes);

  // TODO: これなんとかしたいよなぁ
  if (image == null) throw Exception('Failed to decode image');
  /*
  if (image == null) {
    // デバッグ用にどのファイルで失敗したかログを残すと親切
    print('画像のデコードに失敗しました: $filePath');
    // 例外を投げる代わりに、元のバイトデータをそのまま返す
    return bytes;
  }
  */
  // if (image == null) return Uint8List.fromList(bytes);

  final thumbnail = img.copyResize(image, width: request.width, height: request.height);
  return Uint8List.fromList(img.encodeJpg(thumbnail, quality: 90));
}

// compute関数を使って、generateThumbnailをバックグラウンドで実行する
Future<Uint8List> computeThumbnail(String filePath, int width, {int? height}) {
  return compute(_generateThumbnail, ThumbnailRequest(filePath, width, height));
}
