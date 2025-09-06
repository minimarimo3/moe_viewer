import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
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
    final itemWidth = (screenWidth - (widget.crossAxisCount + 1) * 2) / widget.crossAxisCount;
    final thumbnailSize = (itemWidth * MediaQuery.of(context).devicePixelRatio).round();

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
      child: CustomScrollView(
        controller: widget.autoScrollController,
        slivers: [
          SliverToBoxAdapter(
            child: _buildAspectRatioPreservedGrid(itemWidth, thumbnailSize),
          ),
        ],
      ),
    );
  }

  Widget _buildAspectRatioPreservedGrid(double itemWidth, int thumbnailSize) {
    return MasonryGridView.count(
      crossAxisCount: widget.crossAxisCount,
      crossAxisSpacing: 2.0,
      mainAxisSpacing: 2.0,
      itemCount: widget.displayItems.length,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemBuilder: (context, index) {
        final item = widget.displayItems[index];
        // AutoScrollTagでラップして、スクロール位置追跡を可能にする
        return AutoScrollTag(
          key: ValueKey('auto_scroll_$index'),
          controller: widget.autoScrollController,
          index: index,
          child: _buildFlexibleThumbnail(item, index, itemWidth, thumbnailSize),
        );
      },
    );
  }

  Widget _buildFlexibleThumbnail(dynamic item, int index, double maxItemWidth, int thumbnailSize) {
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
        preserveAspectRatio: true,
      );
    } else {
      thumbnailWidget = Container(color: Colors.red);
    }

    return GestureDetector(
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.0),
        child: RepaintBoundary(
          child: _buildAspectRatioWidget(item, thumbnailWidget, maxItemWidth),
        ),
      ),
    );
  }

  Widget _buildAspectRatioWidget(dynamic item, Widget thumbnailWidget, double maxItemWidth) {
    if (item is AssetEntity) {
      // AssetEntityの場合、実際のアスペクト比を使用
      if (item.height > 0) {
        final aspectRatio = item.width / item.height;
        return AspectRatio(
          aspectRatio: aspectRatio,
          child: thumbnailWidget,
        );
      }
    } else if (item is File) {
      // Fileの場合、FutureBuilderでアスペクト比を取得
      return FutureBuilder<double>(
        future: _getImageAspectRatio(item),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final aspectRatio = snapshot.data!;
            return AspectRatio(
              aspectRatio: aspectRatio,
              child: thumbnailWidget,
            );
          }
          // ロード中はデフォルトの比率を使用
          return AspectRatio(
            aspectRatio: 0.75,
            child: Container(
              color: Colors.grey[200],
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
        },
      );
    }
    
    // デフォルトケース
    return AspectRatio(
      aspectRatio: 1.0,
      child: thumbnailWidget,
    );
  }
}
