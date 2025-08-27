// アルバムに存在しないフォルダの画像のサムネイルを生成するサービス

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// Isolate（バックグラウンド）で実行されるサムネイル生成関数
Future<Uint8List> generateThumbnail(String filePath) async {
  final file = File(filePath);
  print('Generating thumbnail for: $filePath');
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

  final thumbnail = img.copyResize(image, width: 200);
  return Uint8List.fromList(img.encodeJpg(thumbnail, quality: 90));
}

// compute関数を使って、generateThumbnailをバックグラウンドで実行する
Future<Uint8List> computeThumbnail(String filePath) {
  return compute(generateThumbnail, filePath);
}
