import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../detail/detail_screen.dart';

class GalleryListWidget extends StatelessWidget {
  final List<dynamic> displayItems;
  final List<File> imageFilesForDetail;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final Function(dynamic item, Offset globalPosition) onLongPress;
  final Map<String, Future<Size>> imageSizeFutureCache;
  final VoidCallback? onEnterDetail;
  final VoidCallback? onScrollToEnd; // 遅延読み込み用コールバック
  final void Function(int index)? onItemVisible; // 可視アイテム通知（精度向上用）

  const GalleryListWidget({
    super.key,
    required this.displayItems,
    required this.imageFilesForDetail,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.onLongPress,
    required this.imageSizeFutureCache,
    this.onEnterDetail,
    this.onScrollToEnd,
    this.onItemVisible,
  });

  Future<Size> getImageSize(File imageFile) {
    return imageSizeFutureCache.putIfAbsent(imageFile.path, () async {
      try {
        final fileStat = await imageFile.stat();
        if (fileStat.size > 10 * 1024 * 1024) {
          return const Size(16, 9);
        }
        final bytes = await imageFile.readAsBytes();
        final image = await decodeImageFromList(bytes);
        final size = Size(image.width.toDouble(), image.height.toDouble());
        image.dispose();
        return size;
      } catch (e) {
        return const Size(4, 3);
      }
    });
  }

  Widget buildFullAspectRatioImage(dynamic item, int index) {
    if (item is AssetEntity) {
      final double aspectRatio = item.width / item.height;
      return AspectRatio(
        aspectRatio: aspectRatio,
        child: RepaintBoundary(
          child: AssetEntityImage(item, isOriginal: true, fit: BoxFit.cover),
        ),
      );
    } else if (item is File) {
      return FutureBuilder<Size>(
        future: getImageSize(item),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasData &&
              snapshot.data != null) {
            final size = snapshot.data!;
            final double aspectRatio = size.width / size.height;
            return AspectRatio(
              aspectRatio: aspectRatio.clamp(0.1, 10.0),
              child: RepaintBoundary(
                child: Image.file(
                  item,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    // レイアウトシフトを避けるため、エラー時も安定した比率で確保
                    return AspectRatio(
                      aspectRatio: (4 / 3),
                      child: Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.broken_image, size: 50),
                      ),
                    );
                  },
                ),
              ),
            );
          } else if (snapshot.hasError) {
            // 読み込み失敗時も固定高さではなく比率で領域を確保
            return AspectRatio(
              aspectRatio: (4 / 3),
              child: Container(
                color: Colors.grey[300],
                child: const Icon(Icons.error, size: 50),
              ),
            );
          } else {
            // 読み込み待機中も概ね4:3で先にレイアウトを安定させる
            return AspectRatio(
              aspectRatio: (4 / 3),
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
          }
        },
      );
    } else {
      return Container(color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (onScrollToEnd != null &&
            scrollInfo.metrics.extentAfter < 500 &&
            scrollInfo is ScrollUpdateNotification) {
          onScrollToEnd!();
        }
        return false;
      },
      child: ScrollablePositionedList.builder(
        itemScrollController: itemScrollController,
        itemPositionsListener: itemPositionsListener,
        itemCount: displayItems.length,
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: false,
        itemBuilder: (context, index) {
          final item = displayItems[index];
          return RepaintBoundary(
            child: VisibilityDetector(
              key: ValueKey('vis_list_$index'),
              onVisibilityChanged: (info) {
                if (info.visibleFraction >= 0.5) {
                  onItemVisible?.call(index);
                }
              },
              child: GestureDetector(
                onTap: () {
                  onEnterDetail?.call();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DetailScreen(
                        imageFileList: imageFilesForDetail,
                        initialIndex: index,
                      ),
                    ),
                  );
                },
                onLongPressStart: (details) {
                  onLongPress(item, details.globalPosition);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4.0,
                    horizontal: 8.0,
                  ),
                  child: Hero(
                    tag: 'imageHero_$index',
                    child: buildFullAspectRatioImage(item, index),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
