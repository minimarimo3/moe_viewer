import 'package:flutter/material.dart';
import 'package:moe_viewer/dispatch_screen.dart';

import 'detail_screen.dart';
import 'file_thumbnail.dart';
import 'settings_screen.dart';
import 'asset_thumbnail.dart';
import 'settings_provider.dart';

import 'dart:io'; // ファイルやディレクトリを操作するためのライブラリ
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';
// import 'package:path_provider/path_provider.dart'; // フォルダのパスを取得するためのパッケージ
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

enum LoadingStatus {
  loading, // 読み込み中
  completed, // 完了（画像あり）
  empty, // 完了（画像なし）
  errorUnknown, // エラー
  errorPermissionDenied, // 権限拒否
}

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => SettingsProvider(),
      child: const MyApp(),
    ),
  );
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moe Viewer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      // home: const MyHomePage(title: 'Moe Viewer Home Page'),
      home: const DispatchScreen()
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
  // List<AssetEntity> _assets = [];
  // 一覧で表示されるアイテムのリスト
  List<dynamic> _displayItems = [];
  // 詳細画面で表示される画像ファイルのリスト
  List<File> _imageFilesForDetail = [];
  LoadingStatus _status = LoadingStatus.loading;

  // initStateは、画面が作成されたときに一度だけ呼ばれる特別な場所です
  @override
  void initState() {
    super.initState();
    // _requestPermissionAndLoadImages(); // ← 画面が表示される前に、権限リクエストの処理を呼び出す
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // TODO: 適切な権限の要求をする
    //  具体的には、もうちょい軽い権限（例えば、写真ライブラリへのアクセス）を要求する
    //  PhotoManager.requestPermissionExtend();

    // 画面の初回描画が終わった直後に処理を開始させるおまじない
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // --- 1. 設定の読み込みを待つ ---
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      await settings.init();

      // --- 2. 権限を要求する ---
      // final status = await Permission.manageExternalStorage.request();
      _loadImages();

      // --- 3. 結果に応じて画像を読み込む ---
      /*
      if (status.isGranted) {
        _loadImages(); // この時点では、settingsは必ず初期化済み
      } else {
        setState(() {
          _status = LoadingStatus.errorPermissionDenied;
        });
        print("全ファイルへのアクセスが拒否されました。");
      }
      */
    });
  }

  /*
  Future<void> _loadImages() async {
    setState(() {
      _status = LoadingStatus.loading;
    });

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final selectedPaths = settings.selectedPaths;
    List<dynamic> allItems = [];

    // --- 公式ルート (photo_manager) ---
    // まず、OSが「アルバム」として認識しているフォルダのリストを取得します。
    final filterOption = FilterOptionGroup(includeHiddenAssets: true);
    final allAlbums = await PhotoManager.getAssetPathList(
      filterOption: filterOption,
    );

    // 処理を高速化するため、アルバム名をキーにしたMapを作成しておきます。
    final albumMap = {
      for (var album in allAlbums) album.name.toLowerCase(): album,
    };

    // --- 特殊ルート (dart:io) のための準備 ---
    // 公式ルートで見つからなかったパスを、後で直接スキャンするために分けておきます。
    List<String> pathsForDirectScan = [];

    // ユーザーが選んだ各パスをチェックします。
    for (final path in selectedPaths) {
      final folderName = path.split('/').last.toLowerCase();

      if (albumMap.containsKey(folderName)) {
        // もしパスが公式アルバムリストにあれば、高速な公式ルートを使います。
        final album = albumMap[folderName]!;
        final assets = await album.getAssetListRange(
          start: 0,
          end: await album.assetCountAsync,
        );
        allItems.addAll(assets); // AssetEntityを直接リストに追加
      } else {
        print('公式アルバムリストに見つかりませんでした: $path');
        // なければ、後で直接スキャンするリストに入れます。
        pathsForDirectScan.add(path);
      }
    }

    // 特殊ルートに残ったパスを直接スキャンします。
    for (final path in pathsForDirectScan) {
      final directory = Directory(path);
      if (await directory.exists()) {
        final files = directory.listSync(recursive: true);
        for (final file in files) {
          final filePath = file.path.toLowerCase();
          print('直接スキャン中: $filePath');
          if (filePath.endsWith('.jpg') ||
              filePath.endsWith('.png') ||
              filePath.endsWith('.jpeg') ||
              filePath.endsWith('.gif')) {
            allItems.add(File(file.path)); // Fileを直接リストに追加
          }
        }
      }
    }

    setState(() {
      _displayItems = allItems;
      _status = _displayItems.isEmpty
          ? LoadingStatus.empty
          : LoadingStatus.completed;
    });

    print('合計 ${_displayItems.length} 個のアイテムが見つかりました。');
  }
  */
  // in _MyHomePageState class

Future<void> _loadImages() async {
  setState(() { _status = LoadingStatus.loading; });

  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final enabledFolders = settings.folderSettings.where((f) => f.isEnabled).toList();
  final selectedPaths = enabledFolders.map((f) => f.path).toList();
  // final selectedPaths = settings.selectedPaths;

  List<dynamic> allDisplayItems = [];
  List<File> allDetailFiles = []; // ★★★ 詳細画面用のリストもここで作成

  // --- 公式ルート (photo_manager) ---
  final filterOption = FilterOptionGroup(includeHiddenAssets: true);
  final allAlbums = await PhotoManager.getAssetPathList(filterOption: filterOption);
  final albumMap = {for (var album in allAlbums) album.name.toLowerCase(): album};

  final hasFullAccess = await Permission.manageExternalStorage.status.isGranted;
  List<String> pathsForDirectScan = [];

  for (final path in selectedPaths) {
    final folderName = path.split('/').last.toLowerCase();

    if (albumMap.containsKey(folderName)) {
      final album = albumMap[folderName]!;
      final assets = await album.getAssetListRange(start: 0, end: await album.assetCountAsync);
      for (final asset in assets) {
        allDisplayItems.add(asset); // サムネイル用リストに追加
        final file = await asset.file; // ★★★ ここでFileに変換
        if (file != null) {
          allDetailFiles.add(file); // 詳細画面用リストに追加
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
          if (filePath.endsWith('.jpg') || filePath.endsWith('.png') || filePath.endsWith('.jpeg') || filePath.endsWith('.gif')) {
            allDisplayItems.add(fileEntity); // サムネイル用リストに追加
            allDetailFiles.add(fileEntity); // 詳細画面用リストに追加
          }
        }
      }
    }
  }

  setState(() {
    _displayItems = allDisplayItems;
    _imageFilesForDetail = allDetailFiles; // ★★★ 作成したリストを保存
    _status = _displayItems.isEmpty ? LoadingStatus.empty : LoadingStatus.completed;
  });

  print('合計 ${_displayItems.length} 個のアイテムが見つかりました（詳細画面用リストも準備完了）。');
}

  @override
  Widget build(BuildContext context) {
    Widget _buildBody() {
      switch (_status) {
        case LoadingStatus.loading:
          return const CircularProgressIndicator();
        case LoadingStatus.empty:
          return const Text(
            '画像が見つかりません。\n設定からフォルダを追加してください。',
            textAlign: TextAlign.center,
          );
        case LoadingStatus.completed:
          return GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
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
                thumbnailWidget = AssetThumbnail(asset: item);
              } else if (item is File) {
                // Fileの場合は、一旦フルサイズの画像を表示します。（後で最適化します）
                // thumbnailWidget = Image.file(item, fit: BoxFit.cover);
                thumbnailWidget = FileThumbnail(imageFile: item);
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
                        imageFileList: _imageFilesForDetail, // ★★★ 準備済みのリストを渡す
                        initialIndex: index, // タップされたインデックスはそのまま
                      ),
                    ),
                  );
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('wasOnDetailScreen', false);
                  /*
                  File? imageFile;
                  // タップされたアイテムの型に応じてFileオブジェクトを取得します。
                  if (item is AssetEntity) {
                    imageFile = await item.file;
                  } else if (item is File) {
                    imageFile = item;
                  }

                  if (imageFile != null && mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            DetailScreen(imageFile: imageFile!),
                      ),
                    );
                  }
                */
                },
                child: thumbnailWidget,
              );
            },
          );
        case LoadingStatus.errorUnknown:
          return const Text('不明なエラーが発生しました。');
        case LoadingStatus.errorPermissionDenied:
          return const Text('ファイルを表示するのに必要な権限が拒否されました。アプリの設定（右上）から権限を付与してください。');
      }
    }

    return Scaffold(
      appBar: AppBar(
        // backgroundColor: Colors.amber,
        title: const Text('Pixiv Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              // 設定画面に移動し、戻ってくるのを待つ
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              // ★★★ 戻ってきたら、画像を再読み込みする
              _loadImages();
            },
          ),
        ],
      ),
      body: Center(
        // Centerで囲む
        child: _buildBody(), // body部分を別メソッドに切り出す
      ),
    );
  }
}
