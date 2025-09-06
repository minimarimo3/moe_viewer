import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../common_widgets/asset_thumbnail.dart';
import '../../../common_widgets/file_thumbnail.dart';
import '../../detail/detail_screen.dart';

class GalleryGridWidget extends StatefulWidget {
  final List<dynamic> displayItems;
  final List<File> imageFilesForDetail;
  final int crossAxisCount;
  final AutoScrollController autoScrollController;
  final Function(dynamic item, Offset globalPosition) onLongPress;
  final VoidCallback? onEnterDetail;
  final void Function(int index, dynamic item)? onItemTap;
  final VoidCallback? onScrollToEnd; // 遅延読み込み用コールバック

  const GalleryGridWidget({
    super.key,
    required this.displayItems,
    required this.imageFilesForDetail,
    required this.crossAxisCount,
    required this.autoScrollController,
    required this.onLongPress,
    this.onEnterDetail,
    this.onItemTap,
    this.onScrollToEnd,
  });

  @override
  State<GalleryGridWidget> createState() => _GalleryGridWidgetState();
}

class _GalleryGridWidgetState extends State<GalleryGridWidget> {
  final Map<String, double> _aspectRatioCache = {};

  // 画像のアスペクト比を取得
  Future<double> _getImageAspectRatio(File imageFile) async {
    final cacheKey = imageFile.path;
    if (_aspectRatioCache.containsKey(cacheKey)) {
      return _aspectRatioCache[cacheKey]!;
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final aspectRatio = image.width / image.height;
      _aspectRatioCache[cacheKey] = aspectRatio;

      image.dispose();
      codec.dispose();

      return aspectRatio;
    } catch (e) {
      // エラーの場合はデフォルト比率を返す
      return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth =
        (screenWidth - (widget.crossAxisCount + 1) * 2) / widget.crossAxisCount;
    final thumbnailSize = (itemWidth * MediaQuery.of(context).devicePixelRatio)
        .round();

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        // スクロールが最下部に近づいた時に追加読み込みを実行
        if (widget.onScrollToEnd != null &&
            scrollInfo.metrics.extentAfter < 500 && // 500px手前で読み込み開始
            scrollInfo is ScrollUpdateNotification) {
          widget.onScrollToEnd!();
        }
        return false;
      },
      child: ListView.builder(
        controller: widget.autoScrollController,
        itemCount: _calculateRowCount(),
        itemBuilder: (context, rowIndex) {
          return AutoScrollTag(
            key: ValueKey('row_$rowIndex'),
            controller: widget.autoScrollController,
            index: rowIndex,
            child: _buildRow(rowIndex, itemWidth, thumbnailSize),
          );
        },
      ),
    );
  }

  int _calculateRowCount() {
    return (widget.displayItems.length / widget.crossAxisCount).ceil();
  }

  Widget _buildRow(int rowIndex, double itemWidth, int thumbnailSize) {
    final startIndex = rowIndex * widget.crossAxisCount;
    final endIndex = (startIndex + widget.crossAxisCount).clamp(
      0,
      widget.displayItems.length,
    );

    return FutureBuilder<List<Widget>>(
      future: _buildRowItems(startIndex, endIndex, itemWidth, thumbnailSize),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 1.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: snapshot.data!,
            ),
          );
        }

        // ローディング中または空の場合
        return SizedBox(
          height: itemWidth, // 仮の高さ
          child: Row(
            children: List.generate(
              endIndex - startIndex,
              (index) => Expanded(
                child: Container(
                  margin: const EdgeInsets.all(1.0),
                  color: Colors.grey[200],
                  child: const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<List<Widget>> _buildRowItems(
    int startIndex,
    int endIndex,
    double itemWidth,
    int thumbnailSize,
  ) async {
    final List<Widget> items = [];

    for (int i = startIndex; i < endIndex; i++) {
      final item = widget.displayItems[i];
      final widget_ = await _buildThumbnailWithAspectRatio(
        item,
        i,
        thumbnailSize,
        itemWidth,
      );
      items.add(Expanded(child: widget_));
    }

    // 最後の行で足りない分は空のWidgetで埋める
    while (items.length < widget.crossAxisCount) {
      items.add(Expanded(child: Container()));
    }

    return items;
  }

  Future<Widget> _buildThumbnailWithAspectRatio(
    dynamic item,
    int index,
    int thumbnailSize,
    double itemWidth,
  ) async {
    double aspectRatio = 0.75; // デフォルト値

    if (item is AssetEntity) {
      // AssetEntityの場合はwidth/heightから計算
      if (item.height > 0) {
        aspectRatio = item.width / item.height;
      }
    } else if (item is File) {
      aspectRatio = await _getImageAspectRatio(item);
    }

    // 実際のアスペクト比を使用して高さを計算
    final itemHeight = itemWidth / aspectRatio;

    Widget thumbnailWidget;
    if (item is AssetEntity) {
      thumbnailWidget = AssetThumbnail(
        key: ValueKey('${item.id}_$thumbnailSize'),
        asset: item,
        width: thumbnailSize,
      );
    } else if (item is File) {
      thumbnailWidget = FileThumbnail(
        key: ValueKey('${item.path}_$thumbnailSize'),
        imageFile: item,
        width: thumbnailSize,
        preserveAspectRatio: true, // アスペクト比を保持
      );
    } else {
      thumbnailWidget = Container(color: Colors.red);
    }

    return AutoScrollTag(
      key: ValueKey(index),
      controller: widget.autoScrollController,
      index: index,
      child: GestureDetector(
        onTap: () async {
          if (widget.onItemTap != null) {
            widget.onItemTap!(index, item);
            return;
          }
          widget.onEnterDetail?.call();
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DetailScreen(
                imageFileList: widget.imageFilesForDetail,
                initialIndex: index,
              ),
            ),
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('wasOnDetailScreen', false);
        },
        onLongPressStart: (details) {
          widget.onLongPress(item, details.globalPosition);
        },
        child: SizedBox(
          width: itemWidth,
          height: itemHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4.0),
            child: RepaintBoundary(
              child: Container(
                width: itemWidth,
                height: itemHeight,
                color: Colors.grey[200],
                child: FittedBox(
                  fit: BoxFit.cover, // 画像を枠いっぱいにフィットさせつつ、比率は保持
                  child: thumbnailWidget,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
