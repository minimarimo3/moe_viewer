import 'dart:io';

import 'package:flutter/material.dart';
import '../../core/models/album.dart';
import '../../core/services/albums_service.dart';
import '../gallery/widgets/gallery_grid_widget.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import '../gallery/widgets/pie_menu_widget.dart';

class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  List<Album> _albums = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final albums = await AlbumsService.instance.listAlbums();
    if (!mounted) return;
    setState(() {
      _albums = albums;
      _loading = false;
    });
  }

  Future<void> _createAlbum() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新しいアルバム'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'アルバム名'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {
                final n = controller.text.trim();
                if (n.isEmpty) return;
                Navigator.of(context).pop(n);
              },
              child: const Text('作成'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    await AlbumsService.instance.createAlbum(name);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('アルバム'),
        actions: [
          IconButton(
            tooltip: '新規作成',
            onPressed: _createAlbum,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _albums.isEmpty
              ? const Center(child: Text('アルバムがありません。右上から作成できます。'))
              : ListView.builder(
                  itemCount: _albums.length,
                  itemBuilder: (context, index) {
                    final a = _albums[index];
                    return ListTile(
                      leading: const Icon(Icons.photo_album_outlined),
                      title: Text(a.name),
                      subtitle: Text(
                        '作成日: ${a.createdAt.toLocal().toString().split(".").first}',
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AlbumDetailScreen(album: a),
                          ),
                        );
                        await _load();
                      },
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'rename') {
                            final ctrl = TextEditingController(text: a.name);
                            final newName = await showDialog<String>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('名前を変更'),
                                content: TextField(controller: ctrl),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('キャンセル'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(
                                      context,
                                      ctrl.text.trim(),
                                    ),
                                    child: const Text('保存'),
                                  ),
                                ],
                              ),
                            );
                            if (newName != null && newName.isNotEmpty) {
                              await AlbumsService.instance
                                  .renameAlbum(a.id, newName);
                              await _load();
                            }
                          } else if (value == 'delete') {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('アルバムを削除'),
                                content: Text('${a.name} を削除しますか？'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('キャンセル'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('削除'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await AlbumsService.instance.deleteAlbum(a.id);
                              await _load();
                            }
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'rename', child: Text('名前変更')),
                          PopupMenuItem(value: 'delete', child: Text('削除')),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class AlbumDetailScreen extends StatefulWidget {
  final Album album;
  const AlbumDetailScreen({super.key, required this.album});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  List<File> _files = [];
  bool _loading = true;
  late AutoScrollController _autoController;
  final GlobalKey<GalleryPieMenuWidgetState> _pieMenuKey =
      GlobalKey<GalleryPieMenuWidgetState>();

  @override
  void initState() {
    super.initState();
  _autoController = AutoScrollController();
    _load();
  }

  Future<void> _load() async {
    final files = await AlbumsService.instance.getAlbumFiles(widget.album.id);
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'export') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('エクスポート機能は後で実装します')),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'export',
                child: Text('ZIPでエクスポート（準備中）'),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(child: Text('このアルバムにはまだ画像がありません'))
              : GalleryPieMenuWidget(
                  key: _pieMenuKey,
                  onMenuRequest: (item, pos) {},
                  child: GalleryGridWidget(
                    displayItems: _files,
                    imageFilesForDetail: _files,
                    crossAxisCount: 3,
                    autoScrollController: _autoController,
                    onLongPress: (item, pos) {
                      _pieMenuKey.currentState?.openMenuForItem(item, pos);
                    },
                  ),
                ),
    );
  }

  @override
  void dispose() {
    _autoController.dispose();
    super.dispose();
  }
}
