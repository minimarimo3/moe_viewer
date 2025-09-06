import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/thumbnail_provider.dart';

class FileThumbnail extends StatelessWidget {
  final File imageFile;
  final int width;
  final int? height;
  final bool highQuality;
  final bool preserveAspectRatio;

  const FileThumbnail({
    super.key,
    required this.imageFile,
    required this.width,
    this.height,
    this.highQuality = false,
    this.preserveAspectRatio = false,
  });

  @override
  Widget build(BuildContext context) {
    final key = ThumbnailProvider.makeKey(
      imageFile.path,
      width,
      height,
      highQuality,
    );
    return Selector<ThumbnailProvider, Uint8List?>(
      selector: (_, p) => p.getCachedByKey(key),
      shouldRebuild: (prev, next) => !identical(prev, next),
      builder: (context, bytes, _) {
        if (bytes == null) {
          return Container(
            color: Colors.grey[200],
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return Image.memory(
          bytes,
          fit: preserveAspectRatio ? BoxFit.contain : BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[400],
              child: const Icon(Icons.broken_image, color: Colors.white),
            );
          },
        );
      },
    );
  }
}
