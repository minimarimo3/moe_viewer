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
import 'widgets/pie_menu_widget.dart';
import 'widgets/gallery_grid_widget.dart';
import 'widgets/gallery_list_widget.dart';
import 'utils/gallery_shuffle_utils.dart';

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
  }

  @override
  void dispose() {
    // ★★★ 画面を離れるときにシステムUIを元に戻す ★★★
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _autoScrollController.dispose();
    _debounce?.cancel();
    _appBarAnimationController.dispose();
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
    final imageList = await _imageRepository.getAllImages(
      settings.folderSettings,
    );

    setState(() {
      _displayItems = imageList.displayItems;
      _imageFilesForDetail = imageList.detailFiles;
      _status = _displayItems.isEmpty
          ? LoadingStatus.empty
          : LoadingStatus.completed;
    });

    log('合計 ${imageList.displayItems.length} 個のアイテムが見つかりました（詳細画面用リストも準備完了）。');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      final index = settings.lastScrollIndex;
      if (index > 0) {
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
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget buildBody() {
      final crossAxisCount = Provider.of<SettingsProvider>(
        context,
      ).gridCrossAxisCount;

      if (crossAxisCount > 1 && !_isAppBarVisible) {
        _appBarAnimationController.forward();
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); // UI表示
        _isAppBarVisible = true;
      }

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
              // メイン表示ウィジェット
              if (crossAxisCount == 1)
                // ★★★ `UserScrollNotification` から `ScrollNotification` に変更 ★★★
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    // ★★★ スクロール開始時と終了時は無視し、スクロール中のみ処理 ★★★
                    if (notification is ScrollUpdateNotification) {
                      final scrollDelta =
                          notification.metrics.pixels - _lastScrollOffset;
                      const scrollThreshold = 15.0; // しきい値

                      if (scrollDelta.abs() > scrollThreshold) {
                        if (scrollDelta > 0 && _isAppBarVisible) {
                          // 下にスクロール
                          _appBarAnimationController.reverse();
                          // ★★★ ステータスバーなどを非表示（没入モード） ★★★
                          SystemChrome.setEnabledSystemUIMode(
                            SystemUiMode.immersiveSticky,
                          );
                          _isAppBarVisible = false;
                        } else if (scrollDelta < 0 && !_isAppBarVisible) {
                          // 上にスクロール
                          _appBarAnimationController.forward();
                          // ★★★ ステータスバーなどを表示 ★★★
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
                  child: GalleryListWidget(
                    displayItems: _displayItems,
                    imageFilesForDetail: _imageFilesForDetail,
                    itemScrollController: _itemScrollController,
                    itemPositionsListener: _itemPositionsListener,
                    onLongPress: _handleLongPress,
                    imageSizeFutureCache: _imageSizeFutureCache,
                  ),
                )
              else
                GalleryGridWidget(
                  displayItems: _displayItems,
                  imageFilesForDetail: _imageFilesForDetail,
                  crossAxisCount: crossAxisCount,
                  autoScrollController: _autoScrollController,
                  onLongPress: _handleLongPress,
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

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: SizeTransition(
          sizeFactor: _appBarAnimationController,
          child: AppBar(
            title: const Text('Pixiv Viewer'),
            actions: [
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
      body: GalleryPieMenuWidget(
        key: _pieMenuKey,
        onMenuRequest: (item, globalPosition) {
          // この処理はGalleryPieMenuWidget内で自動的に行われるため、空でOK
        },
        child: Center(child: buildBody()),
      ),
    );
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
}
