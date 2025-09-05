import 'dart:io';
import 'package:pool/pool.dart';

// デバイスのCPUコア数に基づいて最適なプールサイズを決定
final thumbnailPool = Pool(_getOptimalPoolSize());

int _getOptimalPoolSize() {
  final processors = Platform.numberOfProcessors;
  // CPUコア数に基づいて、画像処理に適したプールサイズを決定
  // 4コア以下: 4、8コア以下: 6、それ以上: 8
  if (processors <= 4) {
    return 4;
  } else if (processors <= 8) {
    return 6;
  } else {
    return 8;
  }
}
