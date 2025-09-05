import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../common_widgets/file_thumbnail.dart';
import '../../common_widgets/pie_menu_widget.dart';
import '../../common_widgets/loading_view.dart';
import '../../core/services/thumbnail_service.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/favorites_service.dart';
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
    // 画面表示前に見える範囲のサムネイルを生成
    try {
      final crossAxisCount = Provider.of<SettingsProvider>(
        context,
        listen: false,
      ).gridCrossAxisCount;
      final screenWidth = MediaQuery.of(context).size.width;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final tileSize = (screenWidth / crossAxisCount * dpr).round();
      final viewportHeight = MediaQuery.of(context).size.height;
      final rows = (viewportHeight / (screenWidth / crossAxisCount)).ceil() + 1;
      final visibleCount = (crossAxisCount * rows).clamp(0, files.length);
      final targets = files.take(visibleCount).toList();
      await Future.wait(
        targets.map((f) => generateAndCacheGridThumbnail(f.path, tileSize)),
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _autoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = Provider.of<SettingsProvider>(
      context,
    ).gridCrossAxisCount;
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
              child: GridView.builder(
                padding: const EdgeInsets.all(2),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  final f = _files[index];
                  final thumbnailSize =
                      (MediaQuery.of(context).size.width /
                              crossAxisCount *
                              MediaQuery.of(context).devicePixelRatio)
                          .round();
                  return GestureDetector(
                    onLongPressStart: (d) => _pieMenuKey.currentState
                        ?.openMenuForItem(f, d.globalPosition),
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: RepaintBoundary(
                        child: FileThumbnail(
                          key: ValueKey('${f.path}_$thumbnailSize'),
                          imageFile: f,
                          width: thumbnailSize,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
