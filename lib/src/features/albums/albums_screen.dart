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
import '../detail/detail_screen.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import '../../common_widgets/pie_menu_widget.dart';
import '../../core/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import '../../common_widgets/loading_view.dart';
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
// ドラッグ&ドロップでの並べ替え用
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  List<Album> _albums = [];
  bool _loading = true;
  static const _favoriteVirtualId = -1; // 仮想ID

  // ファイルリストのキャッシュ
  final Map<int, List<File>> _filesCache = {};
  final Map<int, bool> _filesCacheLoading = {};

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

    // 非同期でファイルリストを事前読み込み
    _preloadFilesLists();
  }

  Future<void> _preloadFilesLists() async {
    for (final album in _albums) {
      if (_filesCacheLoading[album.id] == true) continue;
      _filesCacheLoading[album.id] = true;

      try {
        List<File> files;
        if (album.id == _favoriteVirtualId) {
          files = await FavoritesService.instance.listFavoriteFiles();
        } else {
          files = await AlbumsService.instance.getAlbumFiles(
            album.id,
            sortMode: album.sortMode,
          );
        }

        if (mounted) {
          setState(() {
            _filesCache[album.id] = files;
            _filesCacheLoading[album.id] = false;
          });
        }
      } catch (e) {
        _filesCacheLoading[album.id] = false;
      }
    }
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
                    final files = _filesCache[a.id] ?? <File>[];
                    final isLoading = _filesCacheLoading[a.id] == true;

                    return AlbumCard(
                      title: a.name,
                      files: files,
                      thumbPx: thumbPx,
                      isFavorite: isFav,
                      showMenu: !isFav,
                      isLoading: isLoading,
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
                                  onPressed: () =>
                                      Navigator.pop(context, ctrl.text.trim()),
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

    // バックグラウンドでサムネイルを生成（UI表示後）
    _precacheVisibleThumbnails();
  }

  Future<void> _precacheVisibleThumbnails() async {
    if (_files.isEmpty) return;

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
          (viewportHeight / (screenWidth / crossAxisCount)).ceil() +
          2; // 余裕を持たせる
      final visibleCount = (crossAxisCount * rows).clamp(0, _files.length);

      // 見える範囲のサムネイルを高品質で事前生成
      final targets = _files.take(visibleCount).toList();

      // 並列処理数を制限してメモリ使用量を抑制
      const batchSize = 4;
      for (int i = 0; i < targets.length; i += batchSize) {
        final batch = targets.skip(i).take(batchSize);
        await Future.wait(
          batch.map(
            (f) => generateAndCacheGridThumbnail(
              f.path,
              tileSize,
              highQuality: false, // 通常のサムネイル品質を使用
            ),
          ),
        );

        // バッチ間で少し休憩してUIをブロックしない
        if (i + batchSize < targets.length) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    } catch (e) {
      // エラーは静かに無視
      dev.log('Thumbnail precaching error: $e');
    }
  }

  // アルバム用の画像リスト表示（元の比率を保持）
  Widget _buildAlbumImageList() {
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
                  // 詳細画面に遷移
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
              onLongPress: () {
                if (_selectMode || _reorderUIActive) return;
                _pieMenuKey.currentState?.openMenuForItem(
                  file,
                  const Offset(0, 0), // 適当な位置
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8.0),
                  border: _selectedPaths.contains(file.path)
                      ? Border.all(
                          color: Theme.of(context).primaryColor,
                          width: 3,
                        )
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: _buildAspectRatioImageForGrid(file, index),
                ),
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

  @override
  Widget build(BuildContext context) {
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
                ? _buildManualReorderList()
                : PieMenuWidget(
                    key: _pieMenuKey,
                    albumId: widget.album.id,
                    // アルバムから削除後に一覧を更新
                    onRemove: _load,

                    child: _buildAlbumImageList(),
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
                final scaffoldMessenger = ScaffoldMessenger.of(context);
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
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text('並び順を保存しました')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text('保存に失敗しました')),
                  );
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

      try {
        // ZIP作成
        await _showProgressDialog('ZIPを作成中…', () async {
          zipFile = await _createAlbumZipToTemp(widget.album.name, _files);
        });

        if (zipFile == null) return;

        final code = _randomSixDigits();
        final url = 'https://file-share.nijimi.yuukei.moe/$code';

        // アップロード
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
          if (zipFile != null) {
            await zipFile!.delete();
          }
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
    bool dialogShown = false;

    // プログレスダイアログを表示
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
    ).then((_) {
      // ダイアログが閉じられたときの処理
      dialogShown = false;
    });
    dialogShown = true;

    try {
      await task();
    } catch (e) {
      rethrow;
    } finally {
      if (mounted && dialogShown) {
        Navigator.of(context).pop(); // rootNavigator: trueを削除
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
        children: [
          RadioGroup<String>(
            onChanged: (v) => Navigator.pop(context, v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: modes.entries
                  .map(
                    (e) => RadioListTile<String>(
                      value: e.key,
                      title: Text(e.value),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualReorderList() {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        final crossAxisCount = settings.gridCrossAxisCount;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '手動並び替え中：画像をドラッグ&ドロップで順番を変更できます',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
            Expanded(
              child: ReorderableGridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 4.0,
                mainAxisSpacing: 4.0,
                childAspectRatio: 0.75, // やや縦長のデフォルト比率
                padding: const EdgeInsets.all(8.0),
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    final item = _files.removeAt(oldIndex);
                    _files.insert(newIndex, item);
                    _reorderDirty = true; // 変更フラグを立てる
                  });
                },
                children: _files.asMap().entries.map((entry) {
                  final index = entry.key;
                  final file = entry.value;

                  return Container(
                    key: ValueKey(file.path),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Colors.grey.shade300, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: Stack(
                        children: [
                          // 画像本体
                          _buildAspectRatioImageForGrid(file, index),
                          // ドラッグハンドルアイコン
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(
                                Icons.drag_handle,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                          // 順番番号を表示
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
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
      final zipPath = p.join(albumDirName, name);

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
