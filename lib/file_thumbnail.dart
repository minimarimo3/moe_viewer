import 'dart:io';
import 'dart:typed_data';
import 'thumbnail_pool.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'thumbnail_service.dart';

class FileThumbnail extends StatefulWidget {
  final File imageFile;

  const FileThumbnail({super.key, required this.imageFile});

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  Uint8List? _thumbnailData;

  @override
  void initState() {
    super.initState();
    _loadOrGenerateThumbnail();
  }

  Future<void> _loadOrGenerateThumbnail() async {
    final tempDir = await getTemporaryDirectory();
    final cacheFileName = 'thumb_${widget.imageFile.path.hashCode}.jpg';
    final cacheFile = File(p.join(tempDir.path, cacheFileName));

    if (await cacheFile.exists()) {
      final data = await cacheFile.readAsBytes();
      if (mounted) setState(() => _thumbnailData = data);
    } else {
      final data = await thumbnailPool.withResource(() {
        return computeThumbnail(widget.imageFile.path);
      });

      if (mounted) setState(() => _thumbnailData = data);
      await cacheFile.writeAsBytes(data);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbnailData == null) {
      return Container(color: Colors.grey[300]);
    }
    return Image.memory(_thumbnailData!, fit: BoxFit.cover);
  }
}
