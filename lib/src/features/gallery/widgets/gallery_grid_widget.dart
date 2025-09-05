import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../common_widgets/asset_thumbnail.dart';
import '../../../common_widgets/file_thumbnail.dart';
import '../../detail/detail_screen.dart';

class GalleryGridWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final thumbnailSize =
        (screenWidth / crossAxisCount * MediaQuery.of(context).devicePixelRatio)
            .round();

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        // スクロールが最下部に近づいた時に追加読み込みを実行
        if (onScrollToEnd != null &&
            scrollInfo.metrics.extentAfter < 500 && // 500px手前で読み込み開始
            scrollInfo is ScrollUpdateNotification) {
          onScrollToEnd!();
        }
        return false;
      },
      child: GridView.builder(
        controller: autoScrollController,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 2.0,
          mainAxisSpacing: 2.0,
        ),
        itemCount: displayItems.length,
        itemBuilder: (BuildContext context, int index) {
          final item = displayItems[index];

          Widget thumbnailWidget;
          if (item is AssetEntity) {
            thumbnailWidget = RepaintBoundary(
              child: AssetThumbnail(
                key: ValueKey('${item.id}_$thumbnailSize'),
                asset: item,
                width: thumbnailSize,
              ),
            );
          } else if (item is File) {
            thumbnailWidget = RepaintBoundary(
              child: FileThumbnail(
                key: ValueKey('${item.path}_$thumbnailSize'),
                imageFile: item,
                width: thumbnailSize,
              ),
            );
          } else {
            thumbnailWidget = Container(color: Colors.red);
          }

          return AutoScrollTag(
            key: ValueKey(index),
            controller: autoScrollController,
            index: index,
            child: GestureDetector(
              onTap: () async {
                if (onItemTap != null) {
                  onItemTap!(index, item);
                  return;
                }
                onEnterDetail?.call();
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DetailScreen(
                      imageFileList: imageFilesForDetail,
                      initialIndex: index,
                    ),
                  ),
                );
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('wasOnDetailScreen', false);
              },
              onLongPressStart: (details) {
                onLongPress(item, details.globalPosition);
              },
              child: thumbnailWidget,
            ),
          );
        },
      ),
    );
  }
}
