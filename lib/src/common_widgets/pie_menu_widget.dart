import 'dart:io';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:pie_menu/pie_menu.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/services/favorites_service.dart';
import '../core/utils/pixiv_utils.dart';
import 'package:photo_manager/photo_manager.dart';
import '../core/services/albums_service.dart';
import 'dialogs.dart';

class PieMenuWidget extends StatefulWidget {
  final Widget child;
  final int? albumId; // アルバム詳細画面で使用（そのアルバムからの削除）
  // アルバムから削除後に親画面を更新するコールバック
  final Future<void> Function()? onRemove;

  const PieMenuWidget({
    super.key,
    required this.child,
    this.albumId,
    this.onRemove,
  });

  @override
  State<PieMenuWidget> createState() => PieMenuWidgetState();
}

class PieMenuWidgetState extends State<PieMenuWidget> {
  final PieMenuController _pieController = PieMenuController();
  final GlobalKey _canvasKey = GlobalKey();
  bool _isMenuOpen = false;
  String? _currentTargetPath;
  String? _currentPixivId;
  bool? _isCurrentFavorite;

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

    // 現在のお気に入り状態を取得
    final fav = await FavoritesService.instance.isFavorite(path);
    if (!mounted) return;

    log('Resolved path: $path, pixivId: $id, isFavorite: $fav');

    setState(() {
      _currentTargetPath = path;
      _currentPixivId = id;
      _isCurrentFavorite = fav;
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
            actions: _buildPieActions(),
            child: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  List<PieAction> _buildPieActions() {
    return [
      if (_currentPixivId == null)
        PieAction(
          buttonTheme: PieButtonTheme(
            backgroundColor: Colors.blueGrey,
            iconColor: Colors.white,
          ),
          tooltip: const Text('Pixivの作品IDが見つかりません'),
          onSelect: () {
            log('No Pixiv ID available for this item: $_currentTargetPath');
          },
          child: const Icon(Icons.open_in_new),
        ),
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
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('リンクを開けませんでした')));
            }
          },
          child: const Icon(Icons.open_in_new),
        ),
      PieAction(
        tooltip: Text((_isCurrentFavorite ?? false) ? 'お気に入りを解除' : 'お気に入りに登録'),
        onSelect: () async {
          final path = _currentTargetPath;
          if (path == null) return;
          final newState = await FavoritesService.instance.toggleFavorite(path);
          if (!mounted) return;
          // ローカル状態を更新
          setState(() {
            _isCurrentFavorite = newState;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(newState ? 'お気に入りに追加しました' : 'お気に入りを解除しました')),
          );
        },
        child: Icon(
          (_isCurrentFavorite ?? false)
              ? Icons.favorite
              : Icons.favorite_border,
        ),
      ),
      PieAction(
        tooltip: const Text('アルバムに追加'),
        onSelect: () async {
          final path = _currentTargetPath;
          if (path == null) return;
          final albumId = await pickAlbumDialog(context);
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
            // 確認ダイアログ
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('アルバムから削除'),
                content: const Text('この画像をアルバムから削除しますか？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('キャンセル'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('削除'),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
            await AlbumsService.instance.removePath(aid, path);
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('アルバムから削除しました')));
            // 親画面を更新
            if (widget.onRemove != null) {
              await widget.onRemove!();
            }
          },
          child: const Icon(Icons.remove_circle_outline),
        ),
    ];
  }
}
