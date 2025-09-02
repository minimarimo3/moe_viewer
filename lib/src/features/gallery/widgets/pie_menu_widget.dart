import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pie_menu/pie_menu.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/favorites_service.dart';
import '../../../core/utils/pixiv_utils.dart';
import 'package:photo_manager/photo_manager.dart';

class GalleryPieMenuWidget extends StatefulWidget {
  final Widget child;
  final Function(dynamic item, Offset? globalPosition)? onMenuRequest;

  const GalleryPieMenuWidget({
    super.key,
    required this.child,
    this.onMenuRequest,
  });

  @override
  State<GalleryPieMenuWidget> createState() => GalleryPieMenuWidgetState();
}

class GalleryPieMenuWidgetState extends State<GalleryPieMenuWidget> {
  final PieMenuController _pieController = PieMenuController();
  final GlobalKey _canvasKey = GlobalKey();
  bool _isMenuOpen = false;
  String? _currentTargetPath;
  String? _currentPixivId;

  @override
  void initState() {
    super.initState();
    // コールバック関数を設定
    if (widget.onMenuRequest != null) {
      // 何らかの形でonMenuRequestをopenMenuForItemに接続
    }
  }

  void openMenuForItem(dynamic item, [Offset? globalPosition]) async {
    print('--- openMenuForItem called with item: $item at position: $globalPosition ---');
    
    // パスとPixivIDを解決
    String path = "";
    if (item is File) {
      path = item.path;
    } else if (item is AssetEntity) {
      final title = await item.titleAsync;
      if (title.isNotEmpty) {
        path = title;
      } else {
        final f = await item.originFile;
        if (f == null) return;
        path = f.path;
      }
    }

    if (!mounted) return;

    final id = PixivUtils.extractPixivId(path);
    if (!mounted) return;
    
    print('Resolved path: $path, pixivId: $id');
    
    setState(() {
      _currentTargetPath = path;
      _currentPixivId = id;
    });

    // setState後のフレームで開く
    final capturedGlobal = globalPosition;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      print('Opening pie menu...');
      if (capturedGlobal != null && _canvasKey.currentContext != null) {
        final box = _canvasKey.currentContext!.findRenderObject() as RenderBox?;
        if (box != null) {
          final localPosition = box.globalToLocal(capturedGlobal);
          print('Opening at local position: $localPosition');
          _pieController.openMenu(menuDisplacement: localPosition);
          return;
        }
      }
      print('Opening at center');
      _pieController.openMenu();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PieCanvas(
      key: _canvasKey,
      onMenuToggle: (open) {
        _isMenuOpen = open;
      },
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (_isMenuOpen) {
                _pieController.closeMenu();
              }
              return false;
            },
            child: widget.child,
          ),
          PieMenu(
            controller: _pieController,
            actions: [
              if (_currentPixivId != null)
                PieAction(
                  tooltip: const Text('Pixivを開く'),
                  onSelect: () async {
                    final id = _currentPixivId;
                    if (id == null) return;
                    final uri = Uri.parse(
                      'https://www.pixiv.net/artworks/$id',
                    );
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('リンクを開けませんでした')),
                      );
                    }
                  },
                  child: const Icon(Icons.open_in_new),
                ),
              PieAction(
                tooltip: const Text('お気に入りを切替'),
                onSelect: () async {
                  final path = _currentTargetPath;
                  if (path == null) return;
                  final newState = await FavoritesService.instance
                      .toggleFavorite(path);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        newState ? 'お気に入りに追加しました' : 'お気に入りを解除しました',
                      ),
                    ),
                  );
                },
                child: const Icon(Icons.favorite_border),
              ),
            ],
            child: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
