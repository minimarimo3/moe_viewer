import 'dart:io';

import 'package:flutter/material.dart';
import '../../core/models/album.dart';
import '../../core/services/albums_service.dart';
import '../gallery/widgets/gallery_grid_widget.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import '../gallery/widgets/pie_menu_widget.dart';
import '../../core/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import '../detail/detail_screen.dart';
import '../../common_widgets/file_thumbnail.dart';

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

  Future<String?> _pickSortMode(
    BuildContext context, {
    String initial = 'added_desc',
  }) async {
    const modes = {
      'added_desc': '追加が新しい順',
      'added_asc': '追加が古い順',
      'name_asc': '名前(昇順)',
      'name_desc': '名前(降順)',
      'manual': '手動（ドラッグで並び替え）',
    };
    return showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          var selected = initial;
          return SimpleDialog(
            title: const Text('並び替え'),
            children: modes.entries
                .map(
                  (e) => RadioListTile<String>(
                    value: e.key,
                    groupValue: selected,
                    onChanged: (v) => Navigator.pop(context, v),
                    title: Text(e.value),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
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
                return FutureBuilder<List<File>>(
                  future: AlbumsService.instance.getAlbumFiles(
                    a.id,
                    sortMode: a.sortMode,
                  ),
                  builder: (context, snapshot) {
                    final cover =
                        (snapshot.data != null && snapshot.data!.isNotEmpty)
                        ? snapshot.data!.first
                        : null;
                    return ListTile(
                      leading: SizedBox(
                        width: 56,
                        height: 56,
                        child: cover != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: FileThumbnail(
                                  imageFile: cover,
                                  width: 56,
                                  height: 56,
                                ),
                              )
                            : const Icon(Icons.photo_album_outlined, size: 40),
                      ),
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
                              await AlbumsService.instance.renameAlbum(
                                a.id,
                                newName,
                              );
                              await _load();
                            }
                          } else if (value == 'sort') {
                            final selected = await _pickSortMode(
                              context,
                              initial: a.sortMode,
                            );
                            if (selected != null) {
                              await AlbumsService.instance.setAlbumSortMode(
                                a.id,
                                selected,
                              );
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
                                    onPressed: () =>
                                        Navigator.pop(context, true),
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
                          PopupMenuItem(value: 'sort', child: Text('並び替え')),
                          PopupMenuItem(value: 'delete', child: Text('削除')),
                        ],
                      ),
                    );
                  },
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
  bool _selectMode = false;
  final Set<String> _selectedPaths = {};
  String _sortMode = 'added_desc';
  bool get _manualMode => _sortMode == 'manual';

  @override
  void initState() {
    super.initState();
    _autoController = AutoScrollController();
    _sortMode = widget.album.sortMode;
    _load();
  }

  Future<void> _load() async {
    final files = await AlbumsService.instance.getAlbumFiles(
      widget.album.id,
      sortMode: _sortMode,
    );
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = Provider.of<SettingsProvider>(
      context,
    ).gridCrossAxisCount;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.album.name),
        actions: [
          if (_selectMode)
            IconButton(
              tooltip: '選択解除',
              onPressed: () => setState(() {
                _selectedPaths.clear();
                _selectMode = false;
              }),
              icon: const Icon(Icons.close),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'export') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('エクスポート機能は後で実装します')),
                );
              } else if (v == 'sort') {
                final selected = await _pickSortMode(context);
                if (selected != null) {
                  setState(() => _sortMode = selected);
                  await AlbumsService.instance.setAlbumSortMode(
                    widget.album.id,
                    selected,
                  );
                  await _load();
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('ZIPでエクスポート（準備中）')),
              PopupMenuItem(value: 'sort', child: Text('並び替え')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
          ? const Center(child: Text('このアルバムにはまだ画像がありません'))
          : (_manualMode
                ? _buildManualList()
                : GalleryPieMenuWidget(
                    key: _pieMenuKey,
                    albumId: widget.album.id,
                    onMenuRequest: (item, pos) {},
                    child: GalleryGridWidget(
                      displayItems: _files,
                      imageFilesForDetail: _files,
                      crossAxisCount: crossAxisCount,
                      autoScrollController: _autoController,
                      onLongPress: (item, pos) {
                        if (_selectMode) return;
                        _pieMenuKey.currentState?.openMenuForItem(item, pos);
                      },
                      onItemTap: (index, item) {
                        if (_selectMode) {
                          final p = _files[index].path;
                          setState(() {
                            if (_selectedPaths.contains(p)) {
                              _selectedPaths.remove(p);
                            } else {
                              _selectedPaths.add(p);
                            }
                          });
                        } else {
                          // 通常遷移（詳細画面）
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DetailScreen(
                                imageFileList: _files,
                                initialIndex: index,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  )),
      floatingActionButton: _files.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                setState(() => _selectMode = !_selectMode);
              },
              icon: Icon(_selectMode ? Icons.close : Icons.select_all),
              label: Text(_selectMode ? '選択解除' : '複数選択'),
            ),
    );
  }

  @override
  void dispose() {
    _autoController.dispose();
    super.dispose();
  }

  Future<String?> _pickSortMode(BuildContext context) async {
    const modes = {
      'added_desc': '追加が新しい順',
      'added_asc': '追加が古い順',
      'name_asc': '名前(昇順)',
      'name_desc': '名前(降順)',
      'manual': '手動（ドラッグで並び替え）',
    };
    return showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('並び替え'),
        children: modes.entries
            .map(
              (e) => RadioListTile<String>(
                value: e.key,
                groupValue: _sortMode,
                onChanged: (v) => Navigator.pop(context, v),
                title: Text(e.value),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildManualList() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      onReorder: (oldIndex, newIndex) async {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = _files.removeAt(oldIndex);
          _files.insert(newIndex, item);
        });
        await AlbumsService.instance.updateManualOrder(
          widget.album.id,
          _files.map((f) => f.path).toList(),
        );
      },
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final f = _files[index];
        return ListTile(
          key: ValueKey(f.path),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: FileThumbnail(imageFile: f, width: 56, height: 56),
          ),
          title: Text(
            f.path.split(Platform.pathSeparator).last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.drag_handle),
        );
      },
    );
  }
}
