import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

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

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final int targetHeight =
        widget.height ??
        (widget.asset.height * widget.width ~/ widget.asset.width);

    final data = await widget.asset.thumbnailDataWithSize(
      ThumbnailSize(widget.width, targetHeight),
    );
    if (mounted) {
      // ウィジェットがまだ画面に存在する場合のみ更新
      setState(() {
        _thumbnailData = data;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbnailData == null) {
      // データ取得中は灰色のボックスを表示
      return Container(color: Colors.grey[300]);
    }
    // データ取得後はImage.memoryで画像を表示
    return Image.memory(_thumbnailData!, fit: BoxFit.cover);
  }
}
