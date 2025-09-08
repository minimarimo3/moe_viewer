import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../../common_widgets/asset_thumbnail.dart';
import '../../../common_widgets/file_thumbnail.dart';
import '../../../core/utils/shared_preferences_helper.dart';
import '../../detail/detail_screen.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/thumbnail_provider.dart';

class GalleryGridWidget extends StatefulWidget {
  final List<dynamic> displayItems;
  final List<File> imageFilesForDetail;
  final int crossAxisCount;
  final AutoScrollController autoScrollController;
  final Function(dynamic item, Offset globalPosition) onLongPress;
  final VoidCallback? onEnterDetail;
  final void Function(int index, dynamic item)? onItemTap;
  final VoidCallback? onScrollToEnd; // 遅延読み込み用コールバック
  final void Function(int index)? onItemVisible; // 可視アイテム通知（精度向上用）
  final bool? isLoadingMore; // 末尾ローディング表示

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
    this.onItemVisible,
    this.isLoadingMore,
  });

  @override
  State<GalleryGridWidget> createState() => _GalleryGridWidgetState();
}

class _GalleryGridWidgetState extends State<GalleryGridWidget> {
  // 通常GridViewのため、セルは正方形ベース。アスペクト比の可変は行わない。

  @override
  Widget build(BuildContext context) {
    final thumbnailProvider = context.read<ThumbnailProvider>();
    final screenWidth = MediaQuery.of(context).size.width;
    // スペースは左右パディング2 + セル間隔(2) * (列数 - 1) を想定
    const spacing = 2.0;
    const horizontalPadding = 2.0;
    final totalSpacing =
        (widget.crossAxisCount - 1) * spacing + horizontalPadding * 2;
    final itemWidth = (screenWidth - totalSpacing) / widget.crossAxisCount;
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
      child: GridView.builder(
        controller: widget.autoScrollController,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(horizontalPadding),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.crossAxisCount,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: 1.0, // 正方形セル
        ),
        // ロード中は末尾にローディングインジケータを1セル分追加
        itemCount:
            widget.displayItems.length +
            ((widget.isLoadingMore ?? false) ? 1 : 0),
        itemBuilder: (context, index) {
          final isLoadingCell =
              (widget.isLoadingMore ?? false) &&
              index >= widget.displayItems.length;
          if (isLoadingCell) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final item = widget.displayItems[index];
          // アイテム単位でAutoScrollTagを付与
          return AutoScrollTag(
            key: ValueKey('auto_scroll_item_$index'),
            controller: widget.autoScrollController,
            index: index,
            highlightColor: Colors.transparent,
            child: VisibilityDetector(
              key: ValueKey('vis_grid_$index'),
              onVisibilityChanged: (info) {
                // 一定以上見えているもののみ採用（50%以上）
                if (info.visibleFraction >= 0.5) {
                  widget.onItemVisible?.call(index);
                  // 可視になったら高優先度で要求
                  final item = widget.displayItems[index];
                  if (item is File) {
                    thumbnailProvider.requestThumbnail(
                      item.path,
                      thumbnailSize,
                      height: null,
                      highQuality: false,
                      priority: ThumbnailPriority.high,
                    );
                  }
                  // 可視範囲と前後のプリフェッチ更新
                  thumbnailProvider.updateVisibleWindow(
                    visibleIndices: _estimateVisibleIndices(index),
                    items: widget.displayItems,
                    width: thumbnailSize,
                    height: null,
                    highQuality: false,
                  );
                } else if (info.visibleFraction == 0) {
                  // 完全に非表示になったらデプリオライズ
                  final item = widget.displayItems[index];
                  if (item is File) {
                    thumbnailProvider.cancelOrDeprioritize(
                      item.path,
                      thumbnailSize,
                      height: null,
                      highQuality: false,
                      cancel: false,
                    );
                  }
                }
              },
              child: _buildGridThumbnail(item, index, itemWidth, thumbnailSize),
            ),
          );
        },
      ),
    );
  }

  // 現在のindexを基点に可視範囲をざっくり推定（通常Gridでも十分）
  Iterable<int> _estimateVisibleIndices(int centerIndex) {
    final radius = 30; // 少し広めに取る
    final start = (centerIndex - radius).clamp(
      0,
      widget.displayItems.length - 1,
    );
    final end = (centerIndex + radius).clamp(0, widget.displayItems.length - 1);
    return List<int>.generate(end - start + 1, (i) => start + i);
  }

  Widget _buildGridThumbnail(
    dynamic item,
    int index,
    double maxItemWidth,
    int thumbnailSize,
  ) {
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
        // Gridセルは正方形のため、縦横比維持でレターボックス表示
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
        final prefs = await SharedPreferencesHelper.instance;
        await prefs.setBool('wasOnDetailScreen', false);
      },
      onLongPressStart: (details) {
        widget.onLongPress(item, details.globalPosition);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.0),
        child: RepaintBoundary(child: thumbnailWidget),
      ),
    );
  }
}
