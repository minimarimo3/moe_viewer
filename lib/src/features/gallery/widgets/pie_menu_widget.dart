import 'dart:io';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:pie_menu/pie_menu.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/favorites_service.dart';
import '../../../core/utils/pixiv_utils.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../core/services/albums_service.dart';

class GalleryPieMenuWidget extends StatefulWidget {
  final Widget child;
  final Function(dynamic item, Offset? globalPosition)? onMenuRequest;
  final int? albumId; // アルバム詳細画面で使用（そのアルバムからの削除）

  const GalleryPieMenuWidget({
    super.key,
    required this.child,
    this.onMenuRequest,
    this.albumId,
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
    log(
      '--- openMenuForItem called with item: $item at position: $globalPosition ---',
    );

    // パスとPixivIDを解決
    String path = "";
    if (item is File) {
      path = item.path;
    } else if (item is AssetEntity) {
      // 実ファイルパス（できればfile、だめならoriginFile）
      final file = await item.file;
      final origin = file ?? await item.originFile;
      if (origin == null) return;
      path = origin.path;
    }

    if (!mounted) return;

    final id = PixivUtils.extractPixivId(path);
    if (!mounted) return;

    log('Resolved path: $path, pixivId: $id');

    setState(() {
      _currentTargetPath = path;
      _currentPixivId = id;
    });

    // setState後のフレームで開く
    final capturedGlobal = globalPosition;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      log('Opening pie menu...');
      if (capturedGlobal != null && _canvasKey.currentContext != null) {
        final box = _canvasKey.currentContext!.findRenderObject() as RenderBox?;
        if (box != null) {
          final localPosition = box.globalToLocal(capturedGlobal);
          log('Opening at local position: $localPosition');
          _pieController.openMenu(menuDisplacement: localPosition);
          return;
        }
      }
      log('Opening at center');
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
                    final uri = Uri.parse('https://www.pixiv.net/artworks/$id');
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
                      content: Text(newState ? 'お気に入りに追加しました' : 'お気に入りを解除しました'),
                    ),
                  );
                },
                child: const Icon(Icons.favorite_border),
              ),
              PieAction(
                tooltip: const Text('アルバムに追加'),
                onSelect: () async {
                  final path = _currentTargetPath;
                  if (path == null) return;
                  final albumId = await _pickAlbumDialog(context);
                  if (albumId == null) return;
                  await AlbumsService.instance.addPaths(albumId, [path]);
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('アルバムに追加しました')));
                },
                child: const Icon(Icons.playlist_add),
              ),
              if (widget.albumId != null)
                PieAction(
                  tooltip: const Text('このアルバムから削除'),
                  onSelect: () async {
                    final path = _currentTargetPath;
                    final aid = widget.albumId;
                    if (path == null || aid == null) return;
                    await AlbumsService.instance.removePath(aid, path);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('アルバムから削除しました')),
                    );
                  },
                  child: const Icon(Icons.remove_circle_outline),
                ),
            ],
            child: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<int?> _pickAlbumDialog(BuildContext context) async {
    final albums = await AlbumsService.instance.listAlbums();
    return showDialog<int>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('アルバムを選択'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (albums.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0),
                    child: Text('アルバムがありません。新規作成してください。'),
                  ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: albums.length,
                    itemBuilder: (context, index) {
                      final a = albums[index];
                      return ListTile(
                        leading: const Icon(Icons.photo_album_outlined),
                        title: Text(a.name),
                        onTap: () => Navigator.of(context).pop(a.id),
                      );
                    },
                  ),
                ),
                const Divider(),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(labelText: '新しいアルバム名'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                final album = await AlbumsService.instance.createAlbum(name);
                if (!context.mounted) return;
                Navigator.of(context).pop(album.id);
              },
              child: const Text('作成して追加'),
            ),
          ],
        );
      },
    );
  }
}
