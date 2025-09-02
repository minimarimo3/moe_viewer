import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

// Isolateで実行されるハッシュ計算関数
Future<String> _calculateSha256(String filePath) async {
  final file = File(filePath);
  if (!await file.exists()) {
    return '';
  }
  final bytes = await file.readAsBytes();
  return sha256.convert(bytes).toString();
}

// compute経由で呼び出すためのラッパー関数
Future<String> computeFileHash(String filePath) {
  return compute(_calculateSha256, filePath);
}
