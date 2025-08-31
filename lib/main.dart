import 'dart:io';
import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'detail_screen.dart';
import 'file_thumbnail.dart';
import 'settings_screen.dart';
import 'dispatch_screen.dart';
import 'asset_thumbnail.dart';
import 'settings_provider.dart';
import 'service/ai_service.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

enum LoadingStatus {
  loading, // 読み込み中
  completed, // 完了（画像あり）
  empty, // 完了（画像なし）
  errorUnknown, // エラー
  errorPermissionDenied, // 権限拒否
}

void main() {
  runApp(
    MultiProvider(
      providers: [
        // 1. 設定を管理するProvider (変更なし)
        ChangeNotifierProvider(create: (_) => SettingsProvider()),

        /*
        // 2. 設定に応じてAiServiceを構築するProxyProvider
        ProxyProvider<SettingsProvider, AiService>(
          update: (context, settings, previousAiService) {
            // 現在選択されているモデルの定義を探します
            final selectedModel = availableModels.firstWhere(
              (model) => model.id == settings.selectedModelId,
              orElse: () => availableModels.first, // 見つからなければデフォルト
            );

            // もしモデルが変更されていなければ、古いサービスを再利用します
            if (previousAiService != null &&
                previousAiService.modelDefinition.id == selectedModel.id) {
              return previousAiService;
            }

            // モデルが変更されたら、古いサービスを破棄し、新しいモデルで新しいサービスを作成します
            log("AI Serviceを再構築します: ${selectedModel.displayName}");
            previousAiService?.dispose();
            return AiService(modelDefinition: selectedModel);
          },
          // アプリ終了時に最後のサービスを破棄します
          dispose: (_, aiService) => aiService.dispose(),
        ),
        */
        Provider(
          create: (_) => AiService(),
          dispose: (_, aiService) => aiService.dispose(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return MaterialApp(
          title: 'Moe Viewer',
          theme: ThemeData(
            brightness: Brightness.light,
            fontFamily: 'NotoSansJP',
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: 'NotoSansJP',
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: settings.themeMode,
          /*
      theme: ThemeData(
        fontFamily: 'NotoSansJP',
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      */
          home: const DispatchScreen(),
        );
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  // 一覧で表示されるアイテムのリスト
  List<dynamic> _displayItems = [];
  // 詳細画面で表示される画像ファイルのリスト
  List<File> _imageFilesForDetail = [];
  LoadingStatus _status = LoadingStatus.loading;

  late AutoScrollController _autoScrollController;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  Timer? _debounce;

  bool _isAutoScrolling = false;

  // initStateは、画面が作成されたときに一度だけ呼ばれる特別な場所です
  @override
  void initState() {
    super.initState();

    _autoScrollController = AutoScrollController();

    // ★★★ スクロール位置の保存リスナーを、両対応に ★★★
    _itemPositionsListener.itemPositions.addListener(_saveScrollPosition);
    _autoScrollController.addListener(_saveScrollPosition);

    /*
    // ★★★ スクロールが終わるたびに、位置を保存するリスナーを追加 ★★★
    _scrollController.addListener(() {
      // スクロールが終わるのを少し待つ（デバウンス処理）
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 90), () {
        // スクロール位置からおおよそのインデックスを計算
        // この計算は固定サイズのグリッド表示で最も効果的です
        final settings = Provider.of<SettingsProvider>(context, listen: false);
        if (settings.gridCrossAxisCount > 1 && _scrollController.hasClients) {
          final itemSize =
              MediaQuery.of(context).size.width / settings.gridCrossAxisCount;
          final index =
              (_scrollController.offset / itemSize).floor() *
              settings.gridCrossAxisCount;
          settings.setLastScrollIndex(index);
        } else {
          // 画面幅の1.2倍を、平均的な画像の高さと仮定する
          final estimatedItemHeight = MediaQuery.of(context).size.width * 1.2;
          final index = (_scrollController.offset / estimatedItemHeight)
              .floor();
          settings.setLastScrollIndex(index);
        }
      });
    });
    */

    _loadImages();
  }

  @override
  void dispose() {
    _autoScrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _saveScrollPosition() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    // TODO: これちょっとみじかすぎるかも？ 100ms
    _debounce = Timer(const Duration(milliseconds: 100), () {
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
      settings.setLastScrollIndex(index);
    });
  }

  Future<void> _loadImages() async {
    setState(() {
      _status = LoadingStatus.loading;
    });

    // TODO: 確かここのファイル検索は同じ実装がどっかにあったのでそれは修正すべき
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final enabledFolders = settings.folderSettings
        .where((f) => f.isEnabled)
        .toList();
    final selectedPaths = enabledFolders.map((f) => f.path).toList();

    List<dynamic> allDisplayItems = [];
    List<File> allDetailFiles = [];

    // --- 公式ルート (photo_manager) ---
    final filterOption = FilterOptionGroup(includeHiddenAssets: true);
    final allAlbums = await PhotoManager.getAssetPathList(
      filterOption: filterOption,
    );
    final albumMap = {
      for (var album in allAlbums) album.name.toLowerCase(): album,
    };

    final hasFullAccess =
        await Permission.manageExternalStorage.status.isGranted;
    List<String> pathsForDirectScan = [];

    for (final path in selectedPaths) {
      final folderName = path.split('/').last.toLowerCase();

      if (albumMap.containsKey(folderName)) {
        final album = albumMap[folderName]!;
        final assets = await album.getAssetListRange(
          start: 0,
          end: await album.assetCountAsync,
        );
        for (final asset in assets) {
          allDisplayItems.add(asset);
          final file = await asset.file;
          if (file != null) {
            allDetailFiles.add(file);
          }
        }
      } else if (hasFullAccess) {
        pathsForDirectScan.add(path);
      }
    }

    // --- 特殊ルート (dart:io) ---
    for (final path in pathsForDirectScan) {
      final directory = Directory(path);
      if (await directory.exists()) {
        final files = directory.listSync(recursive: true);
        for (final fileEntity in files) {
          if (fileEntity is File) {
            final filePath = fileEntity.path.toLowerCase();
            if (filePath.endsWith('.jpg') ||
                filePath.endsWith('.png') ||
                filePath.endsWith('.jpeg') ||
                filePath.endsWith('.gif')) {
              allDisplayItems.add(fileEntity); // サムネイル用リストに追加
              allDetailFiles.add(fileEntity); // 詳細画面用リストに追加
            }
          }
        }
      }
    }

    setState(() {
      _displayItems = allDisplayItems;
      _imageFilesForDetail = allDetailFiles;
      _status = _displayItems.isEmpty
          ? LoadingStatus.empty
          : LoadingStatus.completed;
    });

    log('合計 ${_displayItems.length} 個のアイテムが見つかりました（詳細画面用リストも準備完了）。');
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
    // ★★★ Fileオブジェクトから画像のサイズを取得するための新しいヘルパー関数 ★★★
    Future<Size> _getImageSize(File imageFile) async {
      final bytes = await imageFile.readAsBytes();
      final image = await decodeImageFromList(bytes);
      return Size(image.width.toDouble(), image.height.toDouble());
    }

    // ★★★ 1列表示用の画像を構築するための新しいヘルパー関数 ★★★
    Widget _buildFullAspectRatioImage(dynamic item) {
      if (item is AssetEntity) {
        // AssetEntityはアスペクト比を直接持っている
        final double aspectRatio = item.width / item.height;
        return AspectRatio(
          aspectRatio: aspectRatio,
          // isOriginal: trueで高解像度版を要求
          child: AssetEntityImage(item, isOriginal: true, fit: BoxFit.cover),
        );
      } else if (item is File) {
        // Fileはアスペクト比を知るために、中身を非同期で読み込む必要がある
        return FutureBuilder<Size>(
          // 画像のサイズを取得するFuture
          future: _getImageSize(item),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done &&
                snapshot.hasData &&
                snapshot.data != null) {
              // サイズが取得できたら、正しいアスペクト比で画像を表示
              final size = snapshot.data!;
              final double aspectRatio = size.width / size.height;
              return AspectRatio(
                aspectRatio: aspectRatio,
                child: Image.file(item, fit: BoxFit.cover),
              );
            } else {
              // 読み込み中は、仮の高さを持つプレースホルダーを表示
              return Container(
                height: 300, // 仮の高さ
                color: Colors.grey[300],
              );
            }
          },
        );
      } else {
        return Container(color: Colors.red);
      }
    }

    Widget _buildBody() {
      final crossAxisCount = Provider.of<SettingsProvider>(
        context,
      ).gridCrossAxisCount;

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
              // --- 背景のリスト表示 (GridViewまたはListView) ---
              Builder(
                builder: (context) {
                  if (crossAxisCount == 1) {
                    return ScrollablePositionedList.builder(
                      itemScrollController: _itemScrollController,
                      itemPositionsListener: _itemPositionsListener,
                      itemCount: _displayItems.length,
                      itemBuilder: (context, index) {
                        final item = _displayItems[index];
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DetailScreen(
                                  imageFileList: _imageFilesForDetail,
                                  initialIndex: index,
                                ),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4.0,
                              horizontal: 8.0,
                            ),
                            child: Hero(
                              tag: 'imageHero_$index',
                              // ★★★ 型に応じて、アスペクト比を解決してから画像を表示 ★★★
                              child: _buildFullAspectRatioImage(item),
                            ),
                          ),
                        );
                      },
                    );
                  }
                  // 二列以上の場合

                  final screenWidth = MediaQuery.of(context).size.width;
                  final thumbnailSize =
                      (screenWidth /
                              crossAxisCount *
                              MediaQuery.of(context).devicePixelRatio)
                          .round();

                  return GridView.builder(
                    controller: _autoScrollController,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 2.0,
                      mainAxisSpacing: 2.0,
                    ),
                    itemCount: _displayItems.length,
                    itemBuilder: (BuildContext context, int index) {
                      final item = _displayItems[index];

                      Widget thumbnailWidget;
                      if (item is AssetEntity) {
                        // ★★★ 幅だけを指定（高さはnull）
                        thumbnailWidget = AssetThumbnail(
                          asset: item,
                          width: thumbnailSize,
                        );
                      } else if (item is File) {
                        // ★★★ 幅だけを指定（高さはnull）
                        thumbnailWidget = FileThumbnail(
                          imageFile: item,
                          width: thumbnailSize,
                        );
                      } else {
                        thumbnailWidget = Container(color: Colors.red);
                      }

                      return AutoScrollTag(
                        key: ValueKey(index),
                        controller: _autoScrollController,
                        index: index,
                        child: GestureDetector(
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DetailScreen(
                                  imageFileList: _imageFilesForDetail,
                                  initialIndex: index,
                                ),
                              ),
                            );
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('wasOnDetailScreen', false);
                          },
                          child: Hero(
                            tag: 'imageHero_$index',
                            child: thumbnailWidget,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),

              // --- 前面のローディング表示 ---
              // ★★★ _isAutoScrollingがtrueの場合のみ表示 ★★★
              if (_isAutoScrolling)
                Container(
                  color: Colors.black.withValues(alpha: 0.5), // 半透明の背景
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

        // 一列に２枚以上の写真がある

        /*
          return GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 2.0,
              mainAxisSpacing: 2.0,
            ),
            itemCount: _displayItems.length,
            itemBuilder: (BuildContext context, int index) {
              final item = _displayItems[index];

              // アイテムの型によって表示するウィジェットを切り替えます。
              Widget thumbnailWidget;
              if (item is AssetEntity) {
                // AssetEntityの場合は、以前作った高速なAssetThumbnailを使います。
                thumbnailWidget = AssetThumbnail(
                  asset: item,
                  width: thumbnailSize,
                );
              } else if (item is File) {
                // Fileの場合は、自作のサムネイル機構を使います。
                thumbnailWidget = FileThumbnail(
                  imageFile: item,
                  width: thumbnailSize,
                );
              } else {
                // 予期せぬエラーの場合は赤いボックスを表示します。
                thumbnailWidget = Container(color: Colors.red);
              }

              return GestureDetector(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DetailScreen(
                        imageFileList: _imageFilesForDetail,
                        initialIndex: index,
                      ),
                    ),
                  );
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('wasOnDetailScreen', false);
                },
                // child: thumbnailWidget,
                child: Hero(
                  // タグには、画像ごとにユニークなもの（ファイルパスなど）を指定
                  tag: 'imageHero_$index',
                  child: thumbnailWidget,
                ),
              );
            },
          );
          */
        case LoadingStatus.errorUnknown:
          return const Text('不明なエラーが発生しました。');
        case LoadingStatus.errorPermissionDenied:
          return const Text(
            'ファイルを表示するのに必要な権限が拒否されました。アプリの設定（右上）から権限を付与してください。',
          );
      }
    }

    return Scaffold(
      appBar: AppBar(
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
              // 設定画面に移動し、戻ってくるのを待つ
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              _loadImages();
            },
          ),
        ],
      ),
      body: Center(
        child: _buildBody(), // body部分を別メソッドに切り出す
      ),
    );
  }

  Future<void> _showShuffleConfirmationDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('表示順のシャッフル'),
        content: const Text('画像一覧の表示順をランダムにしますか？\n（現在のスクロール位置はリセットされます）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('いいえ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('はい'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _shuffleImages();
    }
  }
  // in lib/main.dart, _MyHomePageState class

void _shuffleImages() {
  // 1. 現在のリストの安全なコピーを作成
  final originalDisplayItems = List.from(_displayItems);
  final originalDetailFiles = List.from(_imageFilesForDetail);

  // 2. インデックスのリストを作成してシャッフル（あなたの正しいロジック）
  final indexList = List.generate(originalDisplayItems.length, (i) => i);
  indexList.shuffle();

  // 3. Flutterに「今からUIを更新します」と伝える
  setState(() {
    // 4. setStateの「中」で、シャッフルされた新しいリストを代入する
    _displayItems = indexList.map((i) => originalDisplayItems[i]).toList();
    _imageFilesForDetail = indexList.map((i) => originalDetailFiles[i]).cast<File>().toList();
  });

  // --- これ以降の処理はUI更新後なので、setStateの外でOK ---

  // しおりをリセット
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  settings.setLastScrollIndex(0);

  // 表示を一番上に戻す
  if (settings.gridCrossAxisCount > 1 && _autoScrollController.hasClients) {
    _autoScrollController.jumpTo(0);
  } else if (settings.gridCrossAxisCount == 1 && _itemScrollController.isAttached) {
    _itemScrollController.jumpTo(index: 0);
  }
  
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('表示順をシャッフルしました。')),
  );
}
}
