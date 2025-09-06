import 'dart:io';

import 'package:flutter/material.dart';
import '../../../common_widgets/file_thumbnail.dart';

class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.title,
    required this.files,
    required this.thumbPx,
    required this.onTap,
    this.onLongPress,
    this.onMenuSelected,
    this.showMenu = true,
    this.isFavorite = false,
    this.isLoading = false,
  });

  final String title;
  final List<File> files;
  final int thumbPx; // device pixels for full card width; mosaic uses half
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<String>? onMenuSelected;
  final bool showMenu;
  final bool isFavorite;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(14);

    // Up to 2 images for mosaic
    final coverFiles = files.take(2).toList(growable: false);
    final countText = files.length.toString();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: ShapeDecoration(
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            shadows: kElevationToShadow[2],
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cover
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: (isLoading || coverFiles.isEmpty)
                            ? _PlaceholderCover(
                                isFavorite: isFavorite,
                                isLoading: isLoading,
                              )
                            : _MosaicCover(files: coverFiles, thumbPx: thumbPx),
                      ),
                      // Gradient for readable text
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 72,
                        child: IgnorePointer(
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Color.fromARGB(180, 0, 0, 0),
                                  Color.fromARGB(0, 0, 0, 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Menu button
                      if (showMenu)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: _CardMenuButton(onSelected: onMenuSelected),
                        ),
                      // Title and count
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 10,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  shadows: const [
                                    Shadow(
                                      color: Colors.black54,
                                      offset: Offset(0, 1),
                                      blurRadius: 3,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                countText,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: Colors.white,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MosaicCover extends StatelessWidget {
  const _MosaicCover({required this.files, required this.thumbPx});
  final List<File> files;
  final int thumbPx;

  @override
  Widget build(BuildContext context) {
    // Each cell roughly half width in square card for 2 images
    final cellPx = (thumbPx / 2).round();
    if (files.length == 1) {
      return _thumb(files[0], thumbPx, BoxFit.cover);
    }
    // Display 2 images side by side
    return Row(
      children: [
        Expanded(child: _thumb(files[0], cellPx, BoxFit.cover)),
        const SizedBox(width: 1),
        Expanded(child: _thumb(files[1], cellPx, BoxFit.cover)),
      ],
    );
  }

  Widget _thumb(File file, int px, BoxFit fit) {
    return ClipRect(
      child: FittedBox(
        fit: fit,
        clipBehavior: Clip.hardEdge,
        child: FileThumbnail(
          imageFile: file,
          width: px,
          key: ValueKey('${file.path}_$px'),
          // アルバム表示では軽量版で高速化（標準品質使用）
          highQuality: false,
        ),
      ),
    );
  }
}

class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover({required this.isFavorite, this.isLoading = false});
  final bool isFavorite;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.primaryContainer;
    final onBase = theme.colorScheme.onPrimaryContainer;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [base.withValues(alpha: 0.9), base.withValues(alpha: 0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: isLoading
            ? CircularProgressIndicator(
                color: onBase.withValues(alpha: 0.9),
                strokeWidth: 2,
              )
            : Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.photo_library_rounded,
                size: 48,
                color: onBase.withValues(alpha: 0.9),
              ),
      ),
    );
  }
}

class _CardMenuButton extends StatelessWidget {
  const _CardMenuButton({this.onSelected});
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Material(
        color: Colors.black45,
        child: PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_horiz, color: Colors.white),
          onSelected: onSelected,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', child: Text('名前変更')),
            PopupMenuItem(value: 'delete', child: Text('削除')),
          ],
        ),
      ),
    );
  }
}
