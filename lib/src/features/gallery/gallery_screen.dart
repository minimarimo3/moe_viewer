import 'dart:io';
import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart'; // ★★★ SystemChromeのためにインポート ★★★
import 'package:provider/provider.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../settings/settings_screen.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/repositories/image_repository.dart';
import '../../core/services/database_helper.dart';
import 'widgets/pie_menu_widget.dart';
import 'widgets/gallery_grid_widget.dart';
import 'widgets/gallery_list_widget.dart';
import 'utils/gallery_shuffle_utils.dart';
import '../albums/albums_screen.dart';
import '../../core/services/albums_service.dart';

enum LoadingStatus {
  loading, // 読み込み中
  completed, // 完了（画像あり）
  empty, // 完了（画像なし）
  errorUnknown, // エラー
  errorPermissionDenied, // 権限拒否
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  final _imageRepository = ImageRepository();
  final _db = DatabaseHelper.instance;
  // 一覧で表示されるアイテムのリスト
  List<dynamic> _displayItems = [];
  // 詳細画面で表示される画像ファイルのリスト
  List<File> _imageFilesForDetail = [];
  LoadingStatus _status = LoadingStatus.loading;

  // ファイル画像のサイズ取得をキャッシュして、無駄な再デコードを防ぐ
  final Map<String, Future<Size>> _imageSizeFutureCache = {};

  late AutoScrollController _autoScrollController;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  Timer? _debounce;

  final bool _isAutoScrolling = false;
  final GlobalKey<GalleryPieMenuWidgetState> _pieMenuKey =
      GlobalKey<GalleryPieMenuWidgetState>();

  // AppBarアニメーション用コントローラー
  late AnimationController _appBarAnimationController;
  bool _isAppBarVisible = true;
  // ★★★ 前回のスクロール位置を保持する変数 ★★★
  double _lastScrollOffset = 0.0;

  // 検索状態
  bool _isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  // 検索により絞り込まれた index リスト（detailFiles のインデックスを保持）
  List<int> _filteredDetailIndices = [];
  // サジェスト関連
  List<String> _allTags = [];
  List<String> _suggestions = [];
  OverlayEntry? _suggestionsOverlay;
  // 検索結果の固定（Enter確定）
  bool _isFilterActive = false;
  List<int> _activeFilterIndices = [];
  String? _lastCommittedQuery;

  void _handleLongPress(dynamic item, Offset globalPosition) {
    // pie menu widget内でopenMenuForItemを呼び出すためのハンドラー
    log('--- _handleLongPress called ---');
    if (mounted) {
      log('Long press detected on item: $item at position: $globalPosition');

      // GlobalKeyを使用して直接アクセス
      final pieMenuState = _pieMenuKey.currentState;
      if (pieMenuState != null) {
        log('Using GlobalKey to call openMenuForItem...');
        pieMenuState.openMenuForItem(item, globalPosition);
        return;
      }

      // findAncestorStateOfTypeも試してみる
      final pieMenuWidget = context
          .findAncestorStateOfType<GalleryPieMenuWidgetState>();
      log('Found pie menu widget: ${pieMenuWidget != null}');
      if (pieMenuWidget != null) {
        log('Calling openMenuForItem...');
        pieMenuWidget.openMenuForItem(item, globalPosition);
      } else {
        log('ERROR: Could not find GalleryPieMenuWidgetState ancestor!');
      }
    }
  }

  @override
  void initState() {
    super.initState();

    _autoScrollController = AutoScrollController();

    _appBarAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward(); // 初期状態は表示

    _itemPositionsListener.itemPositions.addListener(_saveScrollPosition);
    _autoScrollController.addListener(_saveScrollPosition);

    _loadImages();

    // ルートポップ時に検索を閉じる
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ModalRoute.of(context)?.addScopedWillPopCallback(_onWillPop);
    });
  }

  @override
  void dispose() {
    // ★★★ 画面を離れるときにシステムUIを元に戻す ★★★
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _autoScrollController.dispose();
    _debounce?.cancel();
    _appBarAnimationController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _removeSuggestionsOverlay();
    ModalRoute.of(context)?.removeScopedWillPopCallback(_onWillPop);
    super.dispose();
  }

  void _saveScrollPosition() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    // スクロール保存の頻度を抑える
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      if (!mounted) return;

      int index = 0;
      if (settings.gridCrossAxisCount > 1) {
        // グリッド表示の場合 (近似値)
        if (_autoScrollController.hasClients) {
          final screenWidth = MediaQuery.of(context).size.width;
          final itemSize = screenWidth / settings.gridCrossAxisCount;
          index =
              (_autoScrollController.offset / itemSize).floor() *
              settings.gridCrossAxisCount;
        }
      } else {
        // 1列表示の場合 (正確な値)
        final positions = _itemPositionsListener.itemPositions.value;
        if (positions.isNotEmpty) {
          index = positions.where((pos) => pos.itemLeadingEdge < 1).last.index;
        }
      }
      // 値が変化したときのみ更新（無駄なリビルドを防止）
      if (settings.lastScrollIndex != index) {
        settings.setLastScrollIndex(index);
      }
    });
  }

  Future<void> _loadImages() async {
    setState(() {
      _status = LoadingStatus.loading;
    });

    final settings = Provider.of<SettingsProvider>(context, listen: false);

    try {
      // タグの先読みを非同期で実行（UIをブロックしない）
      _loadTagsAsync();

      final imageList = await _imageRepository.getAllImages(
        settings.folderSettings,
      );

      if (!mounted) return; // ウィジェットが破棄されている場合は処理を停止

      setState(() {
        _displayItems = imageList.displayItems;
        _imageFilesForDetail = imageList.detailFiles;
        _status = _displayItems.isEmpty
            ? LoadingStatus.empty
            : LoadingStatus.completed;
        // 通常モードに戻す（ここでは直接代入して二重setStateを避ける）
        _isSearchMode = false;
        _filteredDetailIndices = [];
      });

      log('合計 ${imageList.displayItems.length} 個のアイテムが見つかりました（詳細画面用リストも準備完了）。');

      // スクロール位置の復元も非同期で実行
      _restoreScrollPositionAsync(settings);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = LoadingStatus.errorUnknown;
      });
      log('画像読み込みエラー: $e');
    }
  }

  void _loadTagsAsync() async {
    try {
      _allTags = await _db.getAllTags();
    } catch (e) {
      log('タグ読み込みエラー: $e');
    }
  }

  void _restoreScrollPositionAsync(SettingsProvider settings) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = settings.lastScrollIndex;
      if (index > 0 && index < _displayItems.length) {
        try {
          if (settings.gridCrossAxisCount > 1 &&
              _autoScrollController.hasClients) {
            _autoScrollController.scrollToIndex(
              index,
              preferPosition: AutoScrollPosition.begin,
            );
          } else if (settings.gridCrossAxisCount == 1 &&
              _itemScrollController.isAttached) {
            _itemScrollController.jumpTo(index: index);
          }
        } catch (e) {
          log('スクロール位置復元エラー: $e');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget buildBody() {
      final crossAxisCount = Provider.of<SettingsProvider>(
        context,
      ).gridCrossAxisCount;

      // appBar の表示/非表示はスクロールによって制御する。
      // 以前はグリッド表示 (crossAxisCount > 1) のときに強制的に表示していたが、
      // グリッドでもスクロールで非表示にしたいためその動作を削除する。

      // 有効な検索（Enter確定）や入力中の検索を反映
      final hasActiveFilter = _isFilterActive;
      final hasQuery =
          _isSearchMode && _searchController.text.trim().isNotEmpty;
      List<int> indices;
      if (hasActiveFilter) {
        indices = _activeFilterIndices;
      } else if (hasQuery) {
        indices = _filteredDetailIndices;
      } else {
        indices = const [];
      }
      final effectiveDisplayItems = (hasActiveFilter || hasQuery)
          ? indices.map((i) => _displayItems[i]).toList()
          : _displayItems;
      final effectiveDetailFiles = (hasActiveFilter || hasQuery)
          ? indices.map((i) => _imageFilesForDetail[i]).toList()
          : _imageFilesForDetail;
      final showingEmpty =
          (hasActiveFilter || hasQuery) && effectiveDisplayItems.isEmpty;

      switch (_status) {
        case LoadingStatus.loading:
          return const CircularProgressIndicator();
        case LoadingStatus.empty:
          return const Text(
            '画像が見つかりません。\n設定からフォルダを追加してください。',
            textAlign: TextAlign.center,
          );
        case LoadingStatus.completed:
          return Stack(
            children: [
              // メイン表示ウィジェット（リスト/グリッド両方をスクロール通知で監視）
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // スクロール中のみ処理
                  if (notification is ScrollUpdateNotification) {
                    final scrollDelta =
                        notification.metrics.pixels - _lastScrollOffset;
                    const scrollThreshold = 15.0; // しきい値

                    if (scrollDelta.abs() > scrollThreshold) {
                      if (scrollDelta > 0 && _isAppBarVisible) {
                        // 下にスクロール
                        _appBarAnimationController.reverse();
                        // ステータスバーなどを非表示（没入モード）
                        SystemChrome.setEnabledSystemUIMode(
                          SystemUiMode.immersiveSticky,
                        );
                        _isAppBarVisible = false;
                      } else if (scrollDelta < 0 && !_isAppBarVisible) {
                        // 上にスクロール
                        _appBarAnimationController.forward();
                        // ステータスバーなどを表示
                        SystemChrome.setEnabledSystemUIMode(
                          SystemUiMode.edgeToEdge,
                        );
                        _isAppBarVisible = true;
                      }
                    }
                    _lastScrollOffset = notification.metrics.pixels;
                  }
                  return true;
                },
                child: crossAxisCount == 1
                    ? GalleryListWidget(
                        displayItems: effectiveDisplayItems,
                        imageFilesForDetail: effectiveDetailFiles,
                        itemScrollController: _itemScrollController,
                        itemPositionsListener: _itemPositionsListener,
                        onEnterDetail: () => _exitSearchMode(resetInput: false),
                        onLongPress: _handleLongPress,
                        imageSizeFutureCache: _imageSizeFutureCache,
                      )
                    : GalleryGridWidget(
                        displayItems: effectiveDisplayItems,
                        imageFilesForDetail: effectiveDetailFiles,
                        crossAxisCount: crossAxisCount,
                        autoScrollController: _autoScrollController,
                        onLongPress: _handleLongPress,
                        onEnterDetail: () => _exitSearchMode(resetInput: false),
                      ),
              ),

              // ヒットなしメッセージ
              if (showingEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '該当する画像が見つかりませんでした',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              // ローディング表示
              if (_isAutoScrolling)
                Container(
                  color: Colors.black.withAlpha((255 * 0.5).round()),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text(
                          '前回見ていた（大体の）位置へ移動中...',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        case LoadingStatus.errorUnknown:
          return const Text('不明なエラーが発生しました。');
        case LoadingStatus.errorPermissionDenied:
          return const Text(
            'ファイルを表示するのに必要な権限が拒否されました。アプリの設定（右上）から権限を付与してください。',
          );
      }
    }

    return GalleryPieMenuWidget(
      key: _pieMenuKey,
      onMenuRequest: (item, globalPosition) {
        // _handleLongPressから直接GlobalKey経由で呼び出すため、ここは空でOK
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: SizeTransition(
            sizeFactor: _appBarAnimationController,
            child: AppBar(
              title: _isSearchMode
                  ? FocusScope(
                      child: Focus(
                        onFocusChange: (has) {
                          if (!has) {
                            // 検索以外をタップしたら現在の結果で確定
                            _commitSearch();
                          }
                        },
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'タグで検索（スペース区切りでAND）',
                            border: InputBorder.none,
                          ),
                          textInputAction: TextInputAction.search,
                          onChanged: _onSearchChanged,
                          onSubmitted: (_) => _commitSearch(),
                        ),
                      ),
                    )
                  : const Text('Pixiv Viewer'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.photo_album_outlined),
                  tooltip: 'アルバム',
                  onPressed: () async {
                    _exitSearchMode();
                    if (!mounted) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AlbumsScreen()),
                    );
                  },
                ),
                if (_isFilterActive)
                  IconButton(
                    icon: const Icon(Icons.playlist_add),
                    tooltip: '検索結果をアルバムへ追加',
                    onPressed: () async {
                      // 現在の有効なリスト（フィルタ確定済み）をアルバムに一括追加
                      final indices = _activeFilterIndices;
                      if (indices.isEmpty) return;
                      final paths = indices
                          .map((i) => _imageFilesForDetail[i].path)
                          .toList();
                      final albumId = await _pickAlbumDialog(context);
                      if (albumId == null) return;
                      await DatabaseHelper.instance.addImagesToAlbum(
                        albumId,
                        paths,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${paths.length}件をアルバムに追加しました')),
                      );
                    },
                  ),
                if (_isFilterActive && !_isSearchMode)
                  IconButton(
                    icon: const Icon(Icons.filter_alt_off),
                    tooltip: '検索結果をクリア',
                    onPressed: _clearCommittedFilter,
                  ),
                if (_isSearchMode)
                  IconButton(
                    icon: const Icon(Icons.backspace),
                    tooltip: '入力クリア',
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  ),
                IconButton(
                  icon: Icon(_isSearchMode ? Icons.close : Icons.search),
                  tooltip: _isSearchMode ? '検索を閉じる' : 'タグ検索',
                  onPressed: () {
                    if (_isSearchMode) {
                      _exitSearchMode();
                    } else {
                      setState(() {
                        _isSearchMode = true;
                        // 検索結果画面から開いた場合は前回のクエリを復元
                        if (_isFilterActive &&
                            (_lastCommittedQuery?.isNotEmpty ?? false)) {
                          _searchController.text = _lastCommittedQuery!;
                          _searchController
                              .selection = TextSelection.fromPosition(
                            TextPosition(offset: _searchController.text.length),
                          );
                        }
                        _updateSuggestions();
                        _showSuggestionsOverlay();
                      });
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.shuffle),
                  tooltip: '表示順をシャッフル',
                  onPressed: () {
                    _showShuffleConfirmationDialog();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () async {
                    _exitSearchMode();
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                    _loadImages();
                  },
                ),
              ],
            ),
          ),
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            if (_isSearchMode) {
              FocusScope.of(context).unfocus();
              _commitSearch();
            }
          },
          child: Center(child: buildBody()),
        ),
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    // テキストが変更されたら、サジェストを更新し、少し待ってから検索を適用する
    // テキストが空になっても検索モードは維持し、全件表示に戻す
    _updateSuggestions();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _applySearch);
  }

  Future<void> _applySearch() async {
    if (!_isSearchMode) return;
    final raw = _searchController.text.trim();
    // 空なら全解除
    if (raw.isEmpty) {
      setState(() {
        _filteredDetailIndices = [];
      });
      return;
    }

    // スペース区切りでAND検索
    final tokens = raw.split(RegExp(r"\s+"));
    // DBからパスのヒットリストを取得
    final hitPaths = await _db.searchByTags(tokens);
    // 現在の detailFiles のインデックスに変換
    final hitSet = hitPaths.toSet();
    final indices = <int>[];
    for (var i = 0; i < _imageFilesForDetail.length; i++) {
      final p = _imageFilesForDetail[i].path;
      if (hitSet.contains(p)) indices.add(i);
    }
    setState(() {
      _filteredDetailIndices = indices;
    });
  }

  Future<void> _commitSearch() async {
    final raw = _searchController.text.trim();
    if (raw.isEmpty) {
      _clearCommittedFilter();
      _exitSearchMode();
      return;
    }
    // まず現在の結果を確定するために検索を実行
    await _applySearch();
    setState(() {
      _isFilterActive = true;
      _activeFilterIndices = List<int>.from(_filteredDetailIndices);
      _lastCommittedQuery = raw;
    });
    _exitSearchMode();
  }

  void _clearCommittedFilter() {
    setState(() {
      _isFilterActive = false;
      _activeFilterIndices = [];
      _lastCommittedQuery = null;
    });
  }

  // --- サジェスト ---
  void _updateSuggestions() {
    final raw = _searchController.text;
    // 最後のトークンに対してサジェスト
    final tokens = raw
        .split(RegExp(r"\s+"))
        .where((e) => e.isNotEmpty)
        .toList();
    final last = tokens.isEmpty ? '' : tokens.last.toLowerCase();
    if (last.isEmpty) {
      _suggestions = [];
      _removeSuggestionsOverlay();
      return;
    }
    final matched = _allTags
        .where((t) => t.toLowerCase().contains(last))
        .take(20)
        .toList();
    _suggestions = matched;
    if (_isSearchMode) _showSuggestionsOverlay();
  }

  void _insertSuggestion(String tag) {
    final raw = _searchController.text.trimRight();
    final parts = raw.split(RegExp(r"\s+")).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) {
      _searchController.text = tag;
    } else {
      parts.removeLast();
      parts.add(tag);
      _searchController.text = parts.join(' ');
    }
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: _searchController.text.length),
    );
    _updateSuggestions();
    _applySearch();
  }

  void _showSuggestionsOverlay() {
    _removeSuggestionsOverlay();
    if (!_isSearchMode || _suggestions.isEmpty) return;
    // Ensure we insert into the top-most overlay so it renders over grid/list
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    final theme = Theme.of(context);
    _suggestionsOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.of(context).padding.top + kToolbarHeight,
          child: Material(
            elevation: 4,
            color: theme.colorScheme.surface,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  primary: false,
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    final s = _suggestions[index];
                    return ListTile(
                      title: Text(s),
                      onTap: () => _insertSuggestion(s),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay?.insert(_suggestionsOverlay!);
  }

  void _removeSuggestionsOverlay() {
    _suggestionsOverlay?.remove();
    _suggestionsOverlay = null;
  }

  // --- 戻るキー/他画面遷移で検索を中断 ---
  Future<bool> _onWillPop() async {
    if (_isSearchMode) {
      await _commitSearch();
      return false; // popは止める
    }
    if (_isFilterActive) {
      _clearCommittedFilter();
      return false; // popは止める（メインに戻す）
    }
    return true;
  }

  void _exitSearchMode({bool resetInput = true}) {
    setState(() {
      _isSearchMode = false;
      _filteredDetailIndices = [];
      _suggestions = [];
      _removeSuggestionsOverlay();
      if (resetInput) _searchController.clear();
    });
  }

  Future<void> _showShuffleConfirmationDialog() async {
    final confirm = await GalleryShuffleUtils.showShuffleConfirmationDialog(
      context,
    );

    if (confirm == true) {
      _shuffleImages();
    }
  }

  void _shuffleImages() {
    // 新しいユーティリティを使用してシャッフル
    final result = GalleryShuffleUtils.shuffleItems(
      displayItems: _displayItems,
      imageFilesForDetail: _imageFilesForDetail,
    );

    // UIを更新
    setState(() {
      _displayItems = result.displayItems;
      _imageFilesForDetail = result.detailFiles;
    });

    // 検索中なら再フィルタ
    final hasQuery = _isSearchMode && _searchController.text.trim().isNotEmpty;
    if (hasQuery) {
      // 非同期だが結果は setState 内で反映
      _applySearch();
    }
    // コミット済みフィルタがある場合はパスで再マッピング
    if (_isFilterActive && _activeFilterIndices.isNotEmpty) {
      final prevPaths = _activeFilterIndices
          .map((i) => _imageFilesForDetail[i].path)
          .toSet();
      final remapped = <int>[];
      for (var i = 0; i < _imageFilesForDetail.length; i++) {
        if (prevPaths.contains(_imageFilesForDetail[i].path)) {
          remapped.add(i);
        }
      }
      setState(() {
        _activeFilterIndices = remapped;
      });
    }

    // しおりをリセット
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    settings.setLastScrollIndex(0);

    // 表示を一番上に戻す
    if (settings.gridCrossAxisCount > 1 && _autoScrollController.hasClients) {
      _autoScrollController.jumpTo(0);
    } else if (settings.gridCrossAxisCount == 1 &&
        _itemScrollController.isAttached) {
      _itemScrollController.jumpTo(index: 0);
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('表示順をシャッフルしました。')));
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
