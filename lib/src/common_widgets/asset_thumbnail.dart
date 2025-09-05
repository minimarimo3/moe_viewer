import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

// AssetEntity用のメモリキャッシュ
final Map<String, Uint8List> _assetMemoryCache = {};
const int _maxAssetMemoryCacheSize = 50;

class AssetThumbnail extends StatefulWidget {
  final AssetEntity asset;
  final int width;
  final int? height;

  const AssetThumbnail({
    super.key,
    required this.asset,
    required this.width,
    this.height,
  });

  @override
  State<AssetThumbnail> createState() => _AssetThumbnailState();
}

class _AssetThumbnailState extends State<AssetThumbnail> {
  Uint8List? _thumbnailData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  String _getCacheKey() {
    final h = widget.height?.toString() ?? 'auto';
    return '${widget.asset.id}_w${widget.width}_h$h';
  }

  Future<void> _loadThumbnail() async {
    if (!mounted) return;

    final cacheKey = _getCacheKey();

    // メモリキャッシュをチェック
    if (_assetMemoryCache.containsKey(cacheKey)) {
      if (mounted) {
        setState(() {
          _thumbnailData = _assetMemoryCache[cacheKey];
          _isLoading = false;
        });
      }
      return;
    }

    try {
      // 幅が0のアセットだと整数除算が例外になるため防御
      final assetWidth = widget.asset.width == 0 ? 1 : widget.asset.width;
      final int targetHeight =
          widget.height ?? (widget.asset.height * widget.width ~/ assetWidth);

      final data = await widget.asset.thumbnailDataWithSize(
        ThumbnailSize(widget.width, targetHeight),
      );

      if (data != null) {
        // メモリキャッシュに追加
        if (_assetMemoryCache.length >= _maxAssetMemoryCacheSize) {
          _assetMemoryCache.remove(_assetMemoryCache.keys.first);
        }
        _assetMemoryCache[cacheKey] = data;

        if (mounted) {
          setState(() {
            _thumbnailData = data;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
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
            : const Icon(Icons.broken_image, color: Colors.white),
      );
    }

    return Image.memory(
      _thumbnailData!,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey[400],
          child: const Icon(Icons.broken_image, color: Colors.white),
        );
      },
    );
  }
}
