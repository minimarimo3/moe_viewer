import 'dart:io';

import 'package:flutter/material.dart';
import '../../core/models/album.dart';
import '../../core/services/albums_service.dart';
import '../../core/services/favorites_service.dart';
import 'favorites_album_screen.dart';
import '../gallery/widgets/gallery_grid_widget.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import '../../common_widgets/pie_menu_widget.dart';
import '../../core/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import '../detail/detail_screen.dart';
import '../../common_widgets/file_thumbnail.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'widgets/album_card.dart';

class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  List<Album> _albums = [];
  bool _loading = true;
  static const _favoriteVirtualId = -1; // 仮想ID

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final albums = await AlbumsService.instance.listAlbums();
    // favoritesを仮想アルバムとして先頭に追加
    final favAlbum = Album(
      id: _favoriteVirtualId,
      name: 'お気に入り',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      sortMode: 'name_asc',
    );
    final list = [favAlbum, ...albums];
    if (!mounted) return;
    setState(() {
      _albums = list;
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
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                int crossAxisCount;
                if (width >= 1200) {
                  crossAxisCount = 5;
                } else if (width >= 900) {
                  crossAxisCount = 4;
                } else if (width >= 600) {
                  crossAxisCount = 3;
                } else {
                  crossAxisCount = 2;
                }
                const spacing = 12.0;
                const pad = 12.0;
                final itemWidth =
                    (width - pad * 2 - spacing * (crossAxisCount - 1)) /
                    crossAxisCount;
                final dpr = MediaQuery.of(context).devicePixelRatio;
                final thumbPx = (itemWidth * dpr).round();

                return GridView.builder(
                  padding: const EdgeInsets.all(pad),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    childAspectRatio: 1,
                  ),
                  itemCount: _albums.length,
                  itemBuilder: (context, index) {
                    final a = _albums[index];
                    final isFav = a.id == _favoriteVirtualId;
                    return FutureBuilder<List<File>>(
                      future: isFav
                          ? FavoritesService.instance.listFavoriteFiles()
                          : AlbumsService.instance.getAlbumFiles(
                              a.id,
                              sortMode: a.sortMode,
                            ),
                      builder: (context, snapshot) {
                        final files = snapshot.data ?? const <File>[];
                        return AlbumCard(
                          title: a.name,
                          files: files,
                          thumbPx: thumbPx,
                          isFavorite: isFav,
                          showMenu: !isFav,
                          onTap: () async {
                            if (isFav) {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const FavoritesAlbumScreen(),
                                ),
                              );
                              await _load();
                              return;
                            }
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AlbumDetailScreen(album: a),
                              ),
                            );
                            await _load();
                          },
                          onMenuSelected: (value) async {
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
                        );
                      },
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
  final GlobalKey<PieMenuWidgetState> _pieMenuKey =
      GlobalKey<PieMenuWidgetState>();
  bool _selectMode = false;
  final Set<String> _selectedPaths = {};
  String _sortMode = 'manual';

  bool _reorderUIActive = false; // 並び替えUIを表示するか（ソートモードとは独立）
  bool _reorderDirty = false; // 並び替え変更が未保存かどうか

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
                  setState(() {
                    _sortMode = selected;
                    _reorderUIActive = selected == 'manual';
                    if (_reorderUIActive) {
                      _reorderDirty = false; // 手動モード開始時は未編集
                    }
                  });
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
          : (_reorderUIActive
                ? _buildManualGrid(crossAxisCount)
                : PieMenuWidget(
                    key: _pieMenuKey,
                    albumId: widget.album.id,
                    // アルバムから削除後に一覧を更新
                    onRemove: _load,

                    child: GalleryGridWidget(
                      displayItems: _files,
                      imageFilesForDetail: _files,
                      crossAxisCount: crossAxisCount,
                      autoScrollController: _autoController,
                      onLongPress: (item, pos) {
                        if (_selectMode || _reorderUIActive) return;
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
      floatingActionButton: _reorderUIActive
          ? FloatingActionButton.extended(
              onPressed: () async {
                if (!_reorderDirty) {
                  setState(() {
                    _reorderUIActive = false; // 変更なしならそのまま終了
                  });
                  return;
                }
                final paths = _files.map((f) => f.path).toList();
                try {
                  await AlbumsService.instance.updateManualOrder(
                    widget.album.id,
                    paths,
                  );
                  if (!mounted) return;
                  setState(() {
                    _reorderUIActive = false;
                    _reorderDirty = false;
                  });
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('並び順を保存しました')));
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('保存に失敗しました')));
                }
              },
              icon: const Icon(Icons.check),
              label: const Text('完了'),
            )
          : (_sortMode == 'manual'
                ? FloatingActionButton.extended(
                    onPressed: () {
                      setState(() {
                        _reorderUIActive = true;
                        _reorderDirty = false;
                      });
                    },
                    icon: const Icon(Icons.swap_vert),
                    label: const Text('並び替える'),
                  )
                : null),
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

  Widget _buildManualGrid(int crossAxisCount) {
    final screenWidth = MediaQuery.of(context).size.width;
    final thumbnailSize =
        (screenWidth / crossAxisCount * MediaQuery.of(context).devicePixelRatio)
            .round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '手動並び替え中：ドラッグで順番を変更できます',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
        Expanded(
          child: ReorderableGridView.count(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            dragWidgetBuilder: (index, child) => child,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                final item = _files.removeAt(oldIndex);
                _files.insert(newIndex, item);
                _reorderDirty = true; // 変更フラグを立てる
              });
            },
            children: [
              for (var i = 0; i < _files.length; i++)
                ClipRRect(
                  key: ValueKey(_files[i].path),
                  borderRadius: BorderRadius.circular(6),
                  child: RepaintBoundary(
                    child: FileThumbnail(
                      key: ValueKey('${_files[i].path}_$thumbnailSize'),
                      imageFile: _files[i],
                      width: thumbnailSize,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
