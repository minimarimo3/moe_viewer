import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

// Isolateで実行されるハッシュ計算関数（MD5 に変更）
Future<String> _calculateMd5(String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) {
    return '';
  }
  // Use a stream to avoid loading the whole file into memory.
  final stream = file.openRead();
  final digest = await md5.bind(stream).first;
  return digest.toString();
}

// compute経由で呼び出すためのラッパー関数
Future<String> computeFileHash(String filePath) {
  return compute(_calculateMd5, filePath);
}
