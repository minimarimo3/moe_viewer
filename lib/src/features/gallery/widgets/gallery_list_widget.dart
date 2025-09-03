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
      final bytes = await imageFile.readAsBytes();
      final image = await decodeImageFromList(bytes);
      return Size(image.width.toDouble(), image.height.toDouble());
    });
  }

  Widget buildFullAspectRatioImage(dynamic item) {
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
              aspectRatio: aspectRatio,
              child: RepaintBoundary(
                child: Image.file(item, fit: BoxFit.cover),
              ),
            );
          } else {
            return Container(height: 300, color: Colors.grey[300]);
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
      itemBuilder: (context, index) {
        final item = displayItems[index];
        return GestureDetector(
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
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
            child: Hero(
              tag: 'imageHero_$index',
              child: buildFullAspectRatioImage(item),
            ),
          ),
        );
      },
    );
  }
}
