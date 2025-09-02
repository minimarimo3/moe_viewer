import 'dart:io';
import 'dart:typed_data';

import '../core/services/thumbnail_pool.dart';
import '../core/services/thumbnail_service.dart';

import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class FileThumbnail extends StatefulWidget {
  final File imageFile;
  final int width;
  final int? height;

  const FileThumbnail({super.key, required this.imageFile, required this.width, this.height});

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

    @override
  void didUpdateWidget(covariant FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // もし要求されるサイズが変わったら、サムネイルを再生成する
    if (oldWidget.width != widget.width || oldWidget.imageFile.path != widget.imageFile.path) {
      _loadOrGenerateThumbnail();
    }
  }

  Future<void> _loadOrGenerateThumbnail() async {
    // 画面に表示される前にsetStateが呼ばれるのを防ぐ
    if (!mounted) return;
  // 以前はここで一旦nullにしていたが、ちらつきの原因になるのでやめる
    
    final tempDir = await getTemporaryDirectory();
    // TODO: 多分だけどここで全てのサムネを生成してる？これは容量の爆増を招くので修正すべき
    //  もしアルバム内のファイルならサムネの生成は無効でいいはず。(元々してないかもしれないけど)
    // final cacheFileName = 'thumb_${widget.imageFile.path.hashCode}.jpg';
  final h = widget.height?.toString() ?? 'auto';
  final cacheFileName = 'thumb_${widget.imageFile.path.hashCode}_w${widget.width}_h$h.jpg';
    final cacheFile = File(p.join(tempDir.path, cacheFileName));

    if (await cacheFile.exists()) {
      final data = await cacheFile.readAsBytes();
      if (mounted) setState(() => _thumbnailData = data);
    } else {
      final data = await thumbnailPool.withResource(() {
        return computeThumbnail(widget.imageFile.path, widget.width, height: widget.height);
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: Image.memory(
        _thumbnailData!,
        key: ValueKey(_thumbnailData?.hashCode),
        fit: BoxFit.cover,
      ),
    );
  }
}
