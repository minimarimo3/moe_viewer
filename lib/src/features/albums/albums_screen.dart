import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:isolate';
import 'dart:developer' as dev show log;

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
import '../../common_widgets/loading_view.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'widgets/album_card.dart';
import '../../core/services/thumbnail_service.dart';
// 追加: ZIP作成/保存/アップロード関連
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
          ? const LoadingView(message: 'アルバムを開いています・・・')
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
      final rows =
          (viewportHeight / (screenWidth / crossAxisCount)).ceil() + 1; // 少し多め
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
                await _handleExport();
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
              PopupMenuItem(value: 'export', child: Text('ZIPでエクスポート')),
              PopupMenuItem(value: 'sort', child: Text('並び替え')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const LoadingView(message: 'アルバムを開いています・・・')
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

  Future<void> _handleExport() async {
    if (_files.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('このアルバムにはエクスポートする画像がありません')));
      return;
    }
    final mode = await _pickExportMode(context);
    if (mode == null) return;

    if (mode == 'save') {
      // Export: save
      dev.log('Export album ${widget.album.name} (${widget.album.id})');
      File? zipFile;
      await _showProgressDialog('ZIPを作成中…', () async {
        zipFile = await _createAlbumZipToTemp(widget.album.name, _files);
      });
      if (zipFile == null) return;

      final fileName = _buildZipName(widget.album.name);
      try {
        if (kIsWeb) {
          return;
        } else {
          String? targetDirPath;
          if (Platform.isAndroid) {
            targetDirPath = "/storage/emulated/0/Download";
          } else {
            try {
              final dir = await getDownloadsDirectory();
              dev.log('getDownloadsDirectory: ${dir?.path}');
              if (dir != null && await dir.exists()) {
                targetDirPath = dir.path;
              }
            } catch (_) {
              dev.log("getDownloadsDirectory failed");
            }
          }
          if (targetDirPath == null) {
            final home = Platform.environment['HOME'];
            if (home != null) {
              final dl = Directory(p.join(home, 'Downloads'));
              if (await dl.exists()) targetDirPath = dl.path;
            }
          }
          if (targetDirPath == null) {
            targetDirPath = await FilePicker.platform.getDirectoryPath(
              dialogTitle: '保存先フォルダを選択',
            );
            if (targetDirPath == null) {
              try {
                await zipFile!.delete();
              } catch (_) {}
              return;
            }
          }
          final targetPath = p.join(targetDirPath, fileName);
          await File(zipFile!.path).copy(targetPath);
          dev.log('Saved album zip to $targetPath');
        }

        try {
          await zipFile!.delete();
        } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存しました')));
      } catch (e) {
        try {
          await zipFile!.delete();
        } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存に失敗しました')));
      }
    } else if (mode == 'share') {
      File? zipFile;
      await _showProgressDialog('ZIPを作成中…', () async {
        zipFile = await _createAlbumZipToTemp(widget.album.name, _files);
      });
      if (zipFile == null) return;

      final code = _randomSixDigits();
      final url = 'https://file-share.nijimi.yuukei.moe/$code';
      try {
        await _showProgressDialog('アップロード中…', () async {
          final dio = Dio();
          final fileLen = await zipFile!.length();
          await dio.put(
            url,
            data: zipFile!.openRead(),
            options: Options(
              headers: {
                'Content-Type': 'application/octet-stream',
                'Content-Length': fileLen.toString(),
              },
              sendTimeout: const Duration(minutes: 5),
              receiveTimeout: const Duration(minutes: 5),
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 400,
            ),
          );
        });
        try {
          await zipFile!.delete();
        } catch (_) {}

        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('共有URL'),
            content: SelectableText(url),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('URLをコピーしました')),
                    );
                  }
                },
                child: const Text('コピー'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
            ],
          ),
        );
      } catch (e) {
        try {
          await zipFile!.delete();
        } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('アップロードに失敗しました')));
      }
    }
  }

  Future<void> _showProgressDialog(
    String message,
    Future<void> Function() task,
  ) async {
    // シンプルな進捗モーダル
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
    try {
      await task();
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    }
  }

  String _randomSixDigits() {
    final r = Random.secure();
    final n = r.nextInt(900000) + 100000; // 100000..999999
    return n.toString();
  }

  String _sanitizeFilename(String input) {
    // Windowsも考慮し、共通的に問題のある文字を除去
    const invalid = r'[\\/:*?"<>|]';
    final replaced = input.replaceAll(RegExp(invalid), '_');
    final trimmed = replaced.trim();
    return trimmed.isEmpty ? 'album' : trimmed;
  }

  String _buildZipName(String albumName) {
    final name = _sanitizeFilename(albumName);
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return '$name-$stamp.zip';
  }

  Future<File> _createAlbumZipToTemp(String albumName, List<File> files) async {
    final tempDir = await Directory.systemTemp.createTemp('moe_viewer_');
    final outPath = p.join(tempDir.path, _buildZipName(albumName));
    final albumDirName = _sanitizeFilename(albumName);
    final paths = files.map((e) => e.path).toList(growable: false);

    dev.log('Creating ZIP for album: $albumName');
    dev.log('Sanitized album dir name: $albumDirName');
    dev.log('Number of files: ${files.length}');
    dev.log('Output path: $outPath');

    await Isolate.run(() async {
      await zipPathsToFile(outPath, albumDirName, paths);
    });
    return File(outPath);
  }

  // _uniqueName は isolate 側で使用するトップレベル関数に移行

  Future<String?> _pickExportMode(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('ZIPでエクスポート'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('端末に保存'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'share'),
            child: const Text('URLを使用して共有'),
          ),
        ],
      ),
    );
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

// ==== Isolate-safe helpers (top-level) ====
Future<void> zipPathsToFile(
  String outPath,
  String albumDirName,
  List<String> filePaths,
) async {
  final archive = Archive();
  final nameCount = <String, int>{};

  // ファイルをアーカイブに追加
  for (final path in filePaths) {
    try {
      final file = File(path);
      if (!await file.exists()) {
        dev.log('File does not exist: $path');
        continue; // ファイルが存在しない場合はスキップ
      }

      final bytes = await file.readAsBytes();
      final base = p.basename(path);
      final name = _uniqueNameTopLevel(base, nameCount);
      // ZIPファイル内では常にフォワードスラッシュを使用
      final zipPath = '$albumDirName/$name';

      // ファイルをアーカイブに追加
      final archiveFile = ArchiveFile(zipPath, bytes.length, bytes);
      archive.addFile(archiveFile);

      dev.log('Added file to archive: $zipPath (${bytes.length} bytes)');
      dev.log('  Original path: $path');
      dev.log('  Base name: $base');
      dev.log('  Unique name: $name');
      dev.log('  ZIP path: $zipPath');
    } catch (e) {
      // エラーログを出力してデバッグしやすくする
      dev.log('Failed to add file to zip: $path, error: $e');
    }
  }

  // アーカイブをファイルに書き込み
  final zipBytes = ZipEncoder().encode(archive);
  await File(outPath).writeAsBytes(zipBytes);
  dev.log('ZIP file created: $outPath with ${archive.files.length} files');
}

String _uniqueNameTopLevel(String baseName, Map<String, int> counter) {
  var name = baseName;
  if (!counter.containsKey(baseName)) {
    counter[baseName] = 0;
    return name;
  }
  final stem = p.basenameWithoutExtension(baseName);
  final ext = p.extension(baseName);
  var idx = (counter[baseName] ?? 0) + 1;
  while (true) {
    final candidate = '$stem($idx)$ext';
    if (!counter.containsKey(candidate)) {
      counter[baseName] = idx;
      counter[candidate] = 0;
      name = candidate;
      break;
    }
    idx++;
  }
  return name;
}
