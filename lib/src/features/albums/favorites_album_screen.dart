import 'dart:io';

import 'package:flutter/material.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:provider/provider.dart';

import '../../common_widgets/pie_menu_widget.dart';
import '../../common_widgets/loading_view.dart';
import '../../core/services/thumbnail_service.dart';
import '../../core/services/favorites_service.dart';
import '../../core/providers/settings_provider.dart';
import '../detail/detail_screen.dart';

/// 仮想アルバム「お気に入り」
class FavoritesAlbumScreen extends StatefulWidget {
  const FavoritesAlbumScreen({super.key});

  @override
  State<FavoritesAlbumScreen> createState() => _FavoritesAlbumScreenState();
}

class _FavoritesAlbumScreenState extends State<FavoritesAlbumScreen> {
  List<File> _files = [];
  bool _loading = true;
  late AutoScrollController _autoController;
  final GlobalKey<PieMenuWidgetState> _pieMenuKey =
      GlobalKey<PieMenuWidgetState>();

  @override
  void initState() {
    super.initState();
    _autoController = AutoScrollController();
    _load();
  }

  Future<void> _load() async {
    final files = await FavoritesService.instance.listFavoriteFiles();

    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });

    // バックグラウンドでサムネイルを生成
    _precacheVisibleThumbnails();
  }

  Future<void> _precacheVisibleThumbnails() async {
    if (_files.isEmpty) return;

    try {
      final screenWidth = MediaQuery.of(context).size.width;
      final targets = _files.take(20).toList(); // 最初の20枚だけプリキャッシュ

      const batchSize = 4;
      for (int i = 0; i < targets.length; i += batchSize) {
        final batch = targets.skip(i).take(batchSize);
        await Future.wait(
          batch.map(
            (f) => generateAndCacheGridThumbnail(
              f.path,
              screenWidth.round(),
              highQuality: false, // 通常のサムネイル品質を使用
            ),
          ),
        );

        if (i + batchSize < targets.length) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    } catch (_) {
      // エラーは静かに無視
    }
  }

  @override
  void dispose() {
    _autoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('お気に入り')),
      body: _loading
          ? const LoadingView(message: 'アルバムを開いています…')
          : _files.isEmpty
          ? const Center(child: Text('お気に入りがありません'))
          : PieMenuWidget(
              key: _pieMenuKey,
              // albumIdは無し（仮想）
              onRemove: _load, // 互換のため残す
              onFavoriteToggled: _load, // トグル即時反映
              child: _buildFavoriteImageList(),
            ),
    );
  }

  // お気に入り用の画像リスト表示（グリッド形式）
  Widget _buildFavoriteImageList() {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        final crossAxisCount = settings.gridCrossAxisCount;

        return GridView.builder(
          controller: _autoController,
          padding: const EdgeInsets.all(8.0),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 4.0,
            mainAxisSpacing: 4.0,
            childAspectRatio: 0.75, // やや縦長のデフォルト比率
          ),
          itemCount: _files.length,
          itemBuilder: (context, index) {
            final file = _files[index];

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DetailScreen(
                      imageFileList: _files,
                      initialIndex: index,
                    ),
                  ),
                );
              },
              onLongPressStart: (details) {
                _pieMenuKey.currentState?.openMenuForItem(
                  file,
                  details.globalPosition,
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.0),
                child: _buildAspectRatioImageForGrid(file, index),
              ),
            );
          },
        );
      },
    );
  }

  // グリッド表示用：元の比率を保った画像表示
  Widget _buildAspectRatioImageForGrid(File file, int index) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        final screenWidth = MediaQuery.of(context).size.width;
        final gridItemWidth =
            (screenWidth - 16.0 - (settings.gridCrossAxisCount - 1) * 4.0) /
            settings.gridCrossAxisCount;
        final thumbnailSize =
            (gridItemWidth * MediaQuery.of(context).devicePixelRatio).round();

        return FutureBuilder<Size>(
          future: _getImageSize(file),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done &&
                snapshot.hasData &&
                snapshot.data != null) {
              // 画像全体が見えるようにBoxFit.containを使用
              return Image.file(
                file,
                fit: BoxFit.contain, // 画像全体が見えるように
                cacheWidth: thumbnailSize,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.broken_image, size: 50),
                  );
                },
              );
            } else if (snapshot.hasError) {
              return Container(
                color: Colors.grey[300],
                child: const Icon(Icons.error, size: 50),
              );
            } else {
              return Container(
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
      },
    );
  }

  // 画像サイズを取得するキャッシュ機能付きメソッド
  final Map<String, Future<Size>> _imageSizeCache = {};

  Future<Size> _getImageSize(File file) {
    final path = file.path;
    if (_imageSizeCache.containsKey(path)) {
      return _imageSizeCache[path]!;
    }

    final future = _computeImageSize(file);
    _imageSizeCache[path] = future;
    return future;
  }

  Future<Size> _computeImageSize(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final image = await decodeImageFromList(bytes);
      return Size(image.width.toDouble(), image.height.toDouble());
    } catch (e) {
      // エラーの場合はデフォルト比率を返す
      return const Size(4, 3); // 4:3のデフォルト比率
    }
  }
}
