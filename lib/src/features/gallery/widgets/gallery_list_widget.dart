import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../detail/detail_screen.dart';

class GalleryListWidget extends StatelessWidget {
  final List<dynamic> displayItems;
  final List<File> imageFilesForDetail;
  final ItemScrollController itemScrollController;
  final ItemPositionsListener itemPositionsListener;
  final Function(dynamic item, Offset globalPosition) onLongPress;
  final Map<String, Future<Size>> imageSizeFutureCache;
  final VoidCallback? onEnterDetail;

  const GalleryListWidget({
    super.key,
    required this.displayItems,
    required this.imageFilesForDetail,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.onLongPress,
    required this.imageSizeFutureCache,
    this.onEnterDetail,
  });

  Future<Size> getImageSize(File imageFile) {
    return imageSizeFutureCache.putIfAbsent(imageFile.path, () async {
      try {
        // ファイルサイズが大きい場合は軽量化した読み込みを行う
        final fileStat = await imageFile.stat();
        if (fileStat.size > 10 * 1024 * 1024) {
          // 10MB以上の場合
          // 大きなファイルの場合はデフォルトアスペクト比を使用
          return const Size(16, 9); // 16:9のデフォルト比率
        }

        final bytes = await imageFile.readAsBytes();
        final image = await decodeImageFromList(bytes);
        final size = Size(image.width.toDouble(), image.height.toDouble());
        image.dispose(); // メモリリークを防ぐ
        return size;
      } catch (e) {
        // エラーが発生した場合はデフォルトサイズを返す
        return const Size(4, 3); // 4:3のデフォルト比率
      }
    });
  }

  Widget buildFullAspectRatioImage(dynamic item, int index) {
    if (item is AssetEntity) {
      final double aspectRatio = item.width / item.height;
      return AspectRatio(
        aspectRatio: aspectRatio,
        child: RepaintBoundary(
          child: AssetEntityImage(
            item,
            isOriginal: true, // 高画質を維持
            fit: BoxFit.cover,
          ),
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
              aspectRatio: aspectRatio.clamp(0.1, 10.0), // 極端なアスペクト比を制限
              child: RepaintBoundary(
                child: Image.file(
                  item,
                  fit: BoxFit.cover,
                  // cacheWidthを削除して高画質を維持
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image, size: 50),
                    );
                  },
                ),
              ),
            );
          } else if (snapshot.hasError) {
            return Container(
              height: 200,
              color: Colors.grey[300],
              child: const Icon(Icons.error, size: 50),
            );
          } else {
            return Container(
              height: 200,
              color: Colors.grey[200],
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
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
    return ScrollablePositionedList.builder(
      itemScrollController: itemScrollController,
      itemPositionsListener: itemPositionsListener,
      itemCount: displayItems.length,
      addAutomaticKeepAlives: true, // ビューポート外のアイテムをキャッシュして滑らかなスクロール
      addRepaintBoundaries: false, // RepaintBoundaryを手動で制御
      itemBuilder: (context, index) {
        final item = displayItems[index];
        return RepaintBoundary(
          // アイテム全体をRepaintBoundaryで囲む
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
        );
      },
    );
  }
}
