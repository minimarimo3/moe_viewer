import 'dart:io';
import 'dart:typed_data';

import '../core/services/thumbnail_pool.dart';
import '../core/services/thumbnail_service.dart';

import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// メモリキャッシュで高速化
final Map<String, Uint8List> _memoryCache = {};
const int _maxMemoryCacheSize = 50; // メモリキャッシュの最大アイテム数

class FileThumbnail extends StatefulWidget {
  final File imageFile;
  final int width;
  final int? height;

  const FileThumbnail({
    super.key,
    required this.imageFile,
    required this.width,
    this.height,
  });

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  Uint8List? _thumbnailData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrGenerateThumbnail();
  }

  @override
  void didUpdateWidget(covariant FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // もし要求されるサイズが変わったら、サムネイルを再生成する
    if (oldWidget.width != widget.width ||
        oldWidget.imageFile.path != widget.imageFile.path) {
      _isLoading = true;
      _loadOrGenerateThumbnail();
    }
  }

  String _getCacheKey() {
    final h = widget.height?.toString() ?? 'auto';
    return '${widget.imageFile.path}_w${widget.width}_h$h';
  }

  Future<void> _loadOrGenerateThumbnail() async {
    // 画面に表示される前にsetStateが呼ばれるのを防ぐ
    if (!mounted) return;

    final cacheKey = _getCacheKey();

    // メモリキャッシュをチェック
    if (_memoryCache.containsKey(cacheKey)) {
      if (mounted) {
        setState(() {
          _thumbnailData = _memoryCache[cacheKey];
          _isLoading = false;
        });
      }
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final h = widget.height?.toString() ?? 'auto';
    final cacheFileName =
        'thumb_${widget.imageFile.path.hashCode}_w${widget.width}_h$h.jpg';
    final cacheFile = File(p.join(tempDir.path, cacheFileName));

    try {
      Uint8List data;
      if (await cacheFile.exists()) {
        data = await cacheFile.readAsBytes();
      } else {
        data = await thumbnailPool.withResource(() {
          return computeThumbnail(
            widget.imageFile.path,
            widget.width,
            height: widget.height,
          );
        });

        // 非同期でディスクキャッシュに保存
        cacheFile.writeAsBytes(data).catchError((e) {
          // エラーは無視（次回も生成される）
          return cacheFile; // File型を返す
        });
      }

      // メモリキャッシュに追加（LRU的に管理）
      if (_memoryCache.length >= _maxMemoryCacheSize) {
        // 最初のキーを削除（簡易的なLRU）
        _memoryCache.remove(_memoryCache.keys.first);
      }
      _memoryCache[cacheKey] = data;

      if (mounted) {
        setState(() {
          _thumbnailData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _thumbnailData == null) {
      return Container(
        color: Colors.grey[300],
        child: _isLoading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      );
    }

    return Image.memory(
      _thumbnailData!,
      fit: BoxFit.cover,
      gaplessPlayback: true, // 画像切り替え時のちらつきを防ぐ
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey[400],
          child: const Icon(Icons.broken_image, color: Colors.white),
        );
      },
    );
  }
}
