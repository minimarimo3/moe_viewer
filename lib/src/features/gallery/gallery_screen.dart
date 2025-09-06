import 'dart:io';
import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ★★★ SystemChromeのためにインポート ★★★
import 'package:provider/provider.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../settings/settings_screen.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/repositories/image_repository.dart';
import '../../core/services/database_helper.dart';
import '../../common_widgets/pie_menu_widget.dart';
import 'widgets/gallery_grid_widget_new.dart';
import 'widgets/gallery_list_widget.dart';
import 'utils/gallery_shuffle_utils.dart';
import '../albums/albums_screen.dart';
import '../../common_widgets/dialogs.dart';
import '../../common_widgets/loading_view.dart';

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

  bool _restoringPosition = false;
  final GlobalKey<PieMenuWidgetState> _pieMenuKey =
      GlobalKey<PieMenuWidgetState>();

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

  // 設定値から AutoScrollPosition を決定
  AutoScrollPosition _resolveAutoScrollPosition(String name) {
    switch (name) {
      case 'begin':
        return AutoScrollPosition.begin;
      case 'end':
        return AutoScrollPosition.end;
      case 'middle':
      default:
        return AutoScrollPosition.middle;
    }
  }

  void _handleLongPress(dynamic item, Offset globalPosition) {
    // pie menu widget内でopenMenuForItemを呼び出すためのハンドラー
    log('--- _handleLongPress called ---');
    final pieMenuState = _pieMenuKey.currentState;
    pieMenuState?.openMenuForItem(item, globalPosition);
  }

  @override
  void initState() {
    super.initState();

    _autoScrollController = AutoScrollController(
      viewportBoundaryGetter: () =>
          Rect.fromLTRB(0, 0, 0, MediaQuery.of(context).size.height),
      axis: Axis.vertical,
    );

    _appBarAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward(); // 初期状態は表示

    _itemPositionsListener.itemPositions.addListener(_saveScrollPosition);
    _autoScrollController.addListener(_saveScrollPosition);

    _loadImages();

    // ※ PopScopeを使用するため、addScopedWillPopCallbackは不要
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
    // ※ PopScopeを使用するため、removeScopedWillPopCallbackは不要
    super.dispose();
  }

  void _saveScrollPosition() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    // スクロール保存の頻度を抑える
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      if (!mounted) return;

      // 現在表示されている最新の画像パスを保存
      String? currentImagePath;

      if (settings.gridCrossAxisCount == 1) {
        // 1列表示の場合
        final positions = _itemPositionsListener.itemPositions.value;
        if (positions.isNotEmpty && _imageFilesForDetail.isNotEmpty) {
          final visibleIndex = positions
              .where((pos) => pos.itemLeadingEdge < 1)
              .last
              .index;
          if (visibleIndex < _imageFilesForDetail.length) {
            currentImagePath = _imageFilesForDetail[visibleIndex].path;
          }
        }
      }

      // 最新の画像パスが変化した場合のみ更新
      if (currentImagePath != null &&
          currentImagePath != settings.lastViewedImagePath) {
        settings.setLastViewedImagePath(currentImagePath);
      }
    });
  }

  // 可視アイテム通知を受けて最後に見た画像パスを正確に保存
  void _onItemVisible(int index) {
    if (index < 0 || index >= _imageFilesForDetail.length) return;
    final path = _imageFilesForDetail[index].path;
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (path != settings.lastViewedImagePath) {
      settings.setLastViewedImagePath(path);
      // 互換のためインデックスもしおりとして併用
      settings.setLastScrollIndex(index);
    }
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

      // シャッフル状態の復元
      if (settings.shuffleOrder != null) {
        _applyShuffleOrder(settings.shuffleOrder!);
      }

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

  // 追加画像読み込み機能
  Future<void> _loadMoreImages() async {
    if (_status != LoadingStatus.completed) return;

    final settings = Provider.of<SettingsProvider>(context, listen: false);

    try {
      final additionalImageList = await _imageRepository.loadMoreImages(
        settings.folderSettings,
      );

      if (!mounted) return;

      if (additionalImageList.displayItems.isNotEmpty) {
        setState(() {
          _displayItems.addAll(additionalImageList.displayItems);
          _imageFilesForDetail.addAll(additionalImageList.detailFiles);
        });

        log('追加で ${additionalImageList.displayItems.length} 個のアイテムを読み込みました。');
      }
    } catch (e) {
      log('追加画像読み込みエラー: $e');
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final lastImagePath = settings.lastViewedImagePath;
      if (lastImagePath != null && _imageFilesForDetail.isNotEmpty) {
        // 最新の画像パスから対応するインデックスを検索
        int targetIndex = -1;
        for (int i = 0; i < _imageFilesForDetail.length; i++) {
          if (_imageFilesForDetail[i].path == lastImagePath) {
            targetIndex = i;
            break;
          }
        }

        // 対象の画像が見つかった場合、その位置にスクロール
        if (targetIndex >= 0 && targetIndex < _displayItems.length) {
          try {
            setState(() => _restoringPosition = true);

            if (settings.gridCrossAxisCount > 1 &&
                _autoScrollController.hasClients) {
              // グリッド表示の場合：アイテム単位でスクロール（AutoScrollTagをアイテムに付与）
              final prefer = _resolveAutoScrollPosition(
                Provider.of<SettingsProvider>(
                  context,
                  listen: false,
                ).gridScrollPreferPosition,
              );
              await _autoScrollController.scrollToIndex(
                targetIndex,
                preferPosition: prefer,
                duration: const Duration(milliseconds: 600),
              );

              // スクロール完了後、微調整のために少し待機
              await Future.delayed(const Duration(milliseconds: 200));

              // レイアウトが落ち着いた後に、ごく短い補正スクロールで位置ずれを解消
              try {
                await _autoScrollController.scrollToIndex(
                  targetIndex,
                  preferPosition: AutoScrollPosition.begin,
                  duration: const Duration(milliseconds: 1),
                );
              } catch (_) {}

              if (mounted) {
                setState(() => _restoringPosition = false);
              }
            } else if (settings.gridCrossAxisCount == 1 &&
                _itemScrollController.isAttached) {
              // リスト表示の場合：アニメーションスクロール＋アライメント指定で精度を向上
              try {
                await _itemScrollController.scrollTo(
                  index: targetIndex,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  alignment: 0.0, // 先頭合わせ
                );
                // 微調整（ごく短時間の再スクロール）
                await _itemScrollController.scrollTo(
                  index: targetIndex,
                  duration: const Duration(milliseconds: 1),
                  alignment: 0.0,
                );
              } catch (_) {
                // scrollTo未対応状態などのフォールバック
                try {
                  _itemScrollController.jumpTo(index: targetIndex);
                } catch (_) {}
              }
              if (mounted) setState(() => _restoringPosition = false);
            } else {
              setState(() => _restoringPosition = false);
            }
          } catch (e) {
            log('スクロール位置復元エラー: $e');
            if (mounted) setState(() => _restoringPosition = false);
          }
        } else {
          // 対象の画像が見つからない場合は、従来の方式（インデックスベース）でフォールバック
          final index = settings.lastScrollIndex;
          if (index > 0 && index < _displayItems.length) {
            try {
              setState(() => _restoringPosition = true);
              if (settings.gridCrossAxisCount > 1 &&
                  _autoScrollController.hasClients) {
                final prefer = _resolveAutoScrollPosition(
                  Provider.of<SettingsProvider>(
                    context,
                    listen: false,
                  ).gridScrollPreferPosition,
                );
                await _autoScrollController.scrollToIndex(
                  index,
                  preferPosition: prefer,
                  duration: const Duration(milliseconds: 600),
                );

                await Future.delayed(const Duration(milliseconds: 200));

                // 微補正
                try {
                  await _autoScrollController.scrollToIndex(
                    index,
                    preferPosition: AutoScrollPosition.begin,
                    duration: const Duration(milliseconds: 1),
                  );
                } catch (_) {}

                if (mounted) {
                  setState(() => _restoringPosition = false);
                }
              } else if (settings.gridCrossAxisCount == 1 &&
                  _itemScrollController.isAttached) {
                try {
                  await _itemScrollController.scrollTo(
                    index: index,
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    alignment: 0.0,
                  );
                  await _itemScrollController.scrollTo(
                    index: index,
                    duration: const Duration(milliseconds: 1),
                    alignment: 0.0,
                  );
                } catch (_) {
                  try {
                    _itemScrollController.jumpTo(index: index);
                  } catch (_) {}
                }
                if (mounted) setState(() => _restoringPosition = false);
              } else {
                setState(() => _restoringPosition = false);
              }
            } catch (e) {
              log('フォールバックスクロール位置復元エラー: $e');
              if (mounted) setState(() => _restoringPosition = false);
            }
          }
        }
      } else {
        // 最新画像パスがない場合は従来の方式でフォールバック
        final index = settings.lastScrollIndex;
        if (index > 0 && index < _displayItems.length) {
          try {
            setState(() => _restoringPosition = true);
            if (settings.gridCrossAxisCount > 1 &&
                _autoScrollController.hasClients) {
              final prefer = _resolveAutoScrollPosition(
                Provider.of<SettingsProvider>(
                  context,
                  listen: false,
                ).gridScrollPreferPosition,
              );
              await _autoScrollController.scrollToIndex(
                index,
                preferPosition: prefer,
                duration: const Duration(milliseconds: 600),
              );

              await Future.delayed(const Duration(milliseconds: 200));

              // 微補正
              try {
                await _autoScrollController.scrollToIndex(
                  index,
                  preferPosition: AutoScrollPosition.begin,
                  duration: const Duration(milliseconds: 1),
                );
              } catch (_) {}

              if (mounted) {
                setState(() => _restoringPosition = false);
              }
            } else if (settings.gridCrossAxisCount == 1 &&
                _itemScrollController.isAttached) {
              try {
                await _itemScrollController.scrollTo(
                  index: index,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  alignment: 0.0,
                );
                await _itemScrollController.scrollTo(
                  index: index,
                  duration: const Duration(milliseconds: 1),
                  alignment: 0.0,
                );
              } catch (_) {
                try {
                  _itemScrollController.jumpTo(index: index);
                } catch (_) {}
              }
              if (mounted) setState(() => _restoringPosition = false);
            } else {
              setState(() => _restoringPosition = false);
            }
          } catch (e) {
            log('スクロール位置復元エラー: $e');
            if (mounted) setState(() => _restoringPosition = false);
          }
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
          return const LoadingView(message: '画像を読み込んでいます');
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
                        onScrollToEnd: _loadMoreImages, // 遅延読み込み追加
                        onItemVisible: (i) {
                          // フィルタや検索が効いている場合は、見かけのindexから元のindexへ逆マップ
                          final hasActiveFilter = _isFilterActive;
                          final hasQuery =
                              _isSearchMode &&
                              _searchController.text.trim().isNotEmpty;
                          int originalIndex = i;
                          if (hasActiveFilter) {
                            if (i >= 0 && i < _activeFilterIndices.length) {
                              originalIndex = _activeFilterIndices[i];
                            }
                          } else if (hasQuery) {
                            if (i >= 0 && i < _filteredDetailIndices.length) {
                              originalIndex = _filteredDetailIndices[i];
                            }
                          }
                          _onItemVisible(originalIndex);
                        },
                      )
                    : GalleryGridWidget(
                        displayItems: effectiveDisplayItems,
                        imageFilesForDetail: effectiveDetailFiles,
                        crossAxisCount: crossAxisCount,
                        autoScrollController: _autoScrollController,
                        onLongPress: _handleLongPress,
                        onEnterDetail: () => _exitSearchMode(resetInput: false),
                        onScrollToEnd: _loadMoreImages, // 遅延読み込み追加
                        onItemVisible: (i) {
                          // グリッドも同様に逆マップ
                          final hasActiveFilter = _isFilterActive;
                          final hasQuery =
                              _isSearchMode &&
                              _searchController.text.trim().isNotEmpty;
                          int originalIndex = i;
                          if (hasActiveFilter) {
                            if (i >= 0 && i < _activeFilterIndices.length) {
                              originalIndex = _activeFilterIndices[i];
                            }
                          } else if (hasQuery) {
                            if (i >= 0 && i < _filteredDetailIndices.length) {
                              originalIndex = _filteredDetailIndices[i];
                            }
                          }
                          _onItemVisible(originalIndex);
                        },
                      ),
              ),

              // ヒットなしメッセージ
              if (showingEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '該当する画像が見つかりませんでした',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              // 前回位置への移動オーバーレイ
              if (_restoringPosition)
                Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: const Center(
                    child: LoadingView(
                      message: '前回の位置まで移動しています・・・',
                      spinnerColor: Colors.white,
                      textStyle: TextStyle(color: Colors.white, fontSize: 16),
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

    return PieMenuWidget(
      key: _pieMenuKey,
      child: PopScope(
        canPop: !_isSearchMode,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (_isSearchMode) {
            _exitSearchMode();
          }
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
                    : _isFilterActive
                    ? const Text('検索結果')
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
                        final messenger = ScaffoldMessenger.of(context);
                        final albumId = await pickAlbumDialog(context);
                        if (!mounted) return;
                        if (albumId == null) return;
                        await DatabaseHelper.instance.addImagesToAlbum(
                          albumId,
                          paths,
                        );
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('${paths.length}件をアルバムに追加しました'),
                          ),
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
                            _searchController.selection =
                                TextSelection.fromPosition(
                                  TextPosition(
                                    offset: _searchController.text.length,
                                  ),
                                );
                          }
                          _updateSuggestions();
                          _showSuggestionsOverlay();
                        });
                      }
                    },
                  ),
                  // 検索モード中はシャッフルと設定は検索と無関係なので非表示にする
                  if (!_isSearchMode) ...[
                    IconButton(
                      icon: const Icon(Icons.shuffle),
                      tooltip: '表示順をシャッフル',
                      onPressed: () {
                        _showShuffleOptionsDialog();
                      },
                    ),
                    // 設定アイコンは検索結果表示中は非表示にする
                    if (!_isFilterActive)
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
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    // テキストが変更されたら、サジェストを更新し、少し待ってから検索を適用する
    // テキストが空になっても検索モードは維持し、全件表示に戻す
    _updateSuggestions(); // Fire-and-forget
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

    // 別名を考慮して検索する：各トークンについて、元のタグ名と別名の両方で検索
    final expandedTokens = <String>[];
    for (final token in tokens) {
      expandedTokens.add(token); // 元のトークン
      // 別名があるタグも検索対象に追加
      final matchedTags = await _db.searchTagsByDisplayName(token);
      expandedTokens.addAll(matchedTags);
    }

    // DBからパスのヒットリストを取得
    final hitPaths = await _db.searchByTags(expandedTokens);
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
  void _updateSuggestions() async {
    final raw = _searchController.text;
    // 最後のトークンに対してサジェスト
    final tokens = raw
        .split(RegExp(r"\s+"))
        .where((e) => e.isNotEmpty)
        .toList();
    final last = tokens.isEmpty ? '' : tokens.last.toLowerCase();
    if (last.isEmpty) {
      setState(() {
        _suggestions = [];
      });
      _removeSuggestionsOverlay();
      return;
    }

    // 1) 既存タグから一致（元の名前で）
    final fromTags = _allTags
        .where((t) => t.toLowerCase().contains(last))
        .take(20)
        .toList();

    // 2) 別名から一致するタグを検索
    final matchedByAlias = await _db.searchTagsByDisplayName(last);

    // 3) 別名を表示用に変換
    final aliasesMap = await _db.getAllTagAliases();
    final displayTags = <String>[];

    // まず別名で表示できるもの
    for (final tag in matchedByAlias) {
      final alias = aliasesMap[tag];
      if (alias != null && alias.toLowerCase().contains(last)) {
        displayTags.add(alias);
      }
    }

    // 次に元のタグ名で一致するもの（別名がある場合は別名で表示）
    for (final tag in fromTags) {
      final displayName = aliasesMap[tag] ?? tag;
      if (!displayTags.contains(displayName)) {
        displayTags.add(displayName);
      }
    }

    setState(() {
      _suggestions = displayTags.take(20).toList();
    });
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

  // --- 検索モード終了 ---
  void _exitSearchMode({bool resetInput = true}) {
    setState(() {
      _isSearchMode = false;
      _filteredDetailIndices = [];
      _suggestions = [];
      _removeSuggestionsOverlay();
      if (resetInput) _searchController.clear();
    });
  }

  Future<void> _showShuffleOptionsDialog() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final hasShuffleState = settings.shuffleOrder != null;

    final action = await GalleryShuffleUtils.showShuffleOptionsDialog(
      context,
      hasShuffleState,
    );

    switch (action) {
      case ShuffleAction.shuffle:
        await _shuffleImages();
        break;
      case ShuffleAction.reset:
        await _resetToOriginalOrder();
        break;
      case ShuffleAction.cancel:
      case null:
        // 何もしない
        break;
    }
  }

  Future<void> _shuffleImages() async {
    // 検索中/フィルタ中は「現在画面に表示されている項目のみ」をシャッフルする。
    final hasQuery = _isSearchMode && _searchController.text.trim().isNotEmpty;
    final hasActiveFilter = _isFilterActive;

    // 表示中のインデックス配列を決定（buildBody と同様のロジック）
    List<int> indices;
    if (hasActiveFilter) {
      indices = _activeFilterIndices;
    } else if (hasQuery) {
      indices = _filteredDetailIndices;
    } else {
      indices = const [];
    }

    if (indices.isNotEmpty) {
      // マスター配列内の該当位置のみを抜き出してシャッフルし、元の位置に書き戻す
      final subsetDisplay = indices.map((i) => _displayItems[i]).toList();
      final subsetDetail = indices.map((i) => _imageFilesForDetail[i]).toList();

      final indexList = List.generate(subsetDisplay.length, (i) => i);
      indexList.shuffle();

      final shuffledDisplay = indexList.map((i) => subsetDisplay[i]).toList();
      final shuffledDetail = indexList.map((i) => subsetDetail[i]).toList();

      setState(() {
        for (var k = 0; k < indices.length; k++) {
          final idx = indices[k];
          _displayItems[idx] = shuffledDisplay[k];
          _imageFilesForDetail[idx] = shuffledDetail[k];
        }
      });
    } else {
      // 全体をシャッフル
      final result = GalleryShuffleUtils.shuffleItems(
        displayItems: _displayItems,
        imageFilesForDetail: _imageFilesForDetail,
      );

      // シャッフル順序を保存
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      await settings.saveShuffleOrder(result.shuffleOrder);

      // UIを更新
      setState(() {
        _displayItems = result.displayItems;
        _imageFilesForDetail = result.detailFiles;
      });
    }

    _resetScrollAndFilters();
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('表示順をシャッフルしました。')),
    );
  }

  Future<void> _resetToOriginalOrder() async {
    // シャッフル状態を先にクリア
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    await settings.clearShuffleOrder();

    // 元の画像データを再読み込み
    await _loadImages();

    _resetScrollAndFilters();
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('表示順を最初の状態に戻しました。')),
    );
  }

  void _resetScrollAndFilters() {
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
  }

  void _applyShuffleOrder(List<int> shuffleOrder) {
    final result = GalleryShuffleUtils.applyShuffleOrder(
      displayItems: _displayItems,
      imageFilesForDetail: _imageFilesForDetail,
      shuffleOrder: shuffleOrder,
    );

    setState(() {
      _displayItems = result.displayItems;
      _imageFilesForDetail = result.detailFiles;
    });
  }
}
