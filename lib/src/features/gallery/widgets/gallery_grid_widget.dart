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

  const GalleryGridWidget({
    super.key,
    required this.displayItems,
    required this.imageFilesForDetail,
    required this.crossAxisCount,
    required this.autoScrollController,
    required this.onLongPress,
    this.onEnterDetail,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final thumbnailSize =
        (screenWidth / crossAxisCount * MediaQuery.of(context).devicePixelRatio)
            .round();

    return GridView.builder(
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
              key: ValueKey(item.id),
              asset: item,
              width: thumbnailSize,
            ),
          );
        } else if (item is File) {
          thumbnailWidget = RepaintBoundary(
            child: FileThumbnail(
              key: ValueKey(item.path),
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
    );
  }
}
