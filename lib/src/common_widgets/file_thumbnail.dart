import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import '../core/services/thumbnail_pool.dart';
import '../core/services/thumbnail_service.dart';

import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// メモリキャッシュで高速化
final Map<String, Uint8List> _memoryCache = {};
const int _maxMemoryCacheSize = 50; // メモリキャッシュの最大アイテム数

// バッチ処理用のキュー
final Map<String, Completer<Uint8List?>> _pendingRequests = {};

class FileThumbnail extends StatefulWidget {
  final File imageFile;
  final int width;
  final int? height;
  final bool highQuality; // アルバム表示など高品質が必要な場合のオプション
  final bool preserveAspectRatio; // アスペクト比を保持するかどうか

  const FileThumbnail({
    super.key,
    required this.imageFile,
    required this.width,
    this.height,
    this.highQuality = false,
    this.preserveAspectRatio = false, // デフォルトは従来通り
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
    final quality = widget.highQuality ? 'hq' : 'std';
    return '${widget.imageFile.path}_w${widget.width}_h${h}_$quality';
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

    // 既に同じリクエストが進行中の場合は待機
    if (_pendingRequests.containsKey(cacheKey)) {
      final result = await _pendingRequests[cacheKey]!.future;
      if (mounted && result != null) {
        setState(() {
          _thumbnailData = result;
          _isLoading = false;
        });
      }
      return;
    }

    // 新しいリクエストを登録
    _pendingRequests[cacheKey] = Completer<Uint8List?>();

    try {
      final tempDir = await getTemporaryDirectory();
      final h = widget.height?.toString() ?? 'auto';
      final quality = widget.highQuality ? 'hq' : 'std';
      final cacheFileName =
          'thumb_${widget.imageFile.path.hashCode}_w${widget.width}_h${h}_$quality.jpg';
      final cacheFile = File(p.join(tempDir.path, cacheFileName));

      Uint8List data;
      if (await cacheFile.exists()) {
        data = await cacheFile.readAsBytes();
      } else {
        data = await thumbnailPool.withResource(() {
          return widget.highQuality
              ? computeHighQualityThumbnail(
                  widget.imageFile.path,
                  widget.width,
                  height: widget.height,
                )
              : computeThumbnail(
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

      // 待機中のリクエストを完了
      _pendingRequests[cacheKey]?.complete(data);
      _pendingRequests.remove(cacheKey);

      if (mounted) {
        setState(() {
          _thumbnailData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      // エラーの場合も完了させる
      _pendingRequests[cacheKey]?.complete(null);
      _pendingRequests.remove(cacheKey);

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
      fit: widget.preserveAspectRatio ? BoxFit.contain : BoxFit.cover,
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
