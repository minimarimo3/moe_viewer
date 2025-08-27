import 'package:flutter/material.dart';

import 'detail_screen.dart';
import 'file_thumbnail.dart'; 
import 'settings_screen.dart';
import 'asset_thumbnail.dart';
import 'settings_provider.dart';

import 'dart:io'; // ファイルやディレクトリを操作するためのライブラリ
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';
// import 'package:path_provider/path_provider.dart'; // フォルダのパスを取得するためのパッケージ
import 'package:permission_handler/permission_handler.dart';

enum LoadingStatus {
  loading, // 読み込み中
  completed, // 完了（画像あり）
  empty, // 完了（画像なし）
  error, // エラー
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
      home: const MyHomePage(title: 'Moe Viewer Home Page'),
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
  List<dynamic> _displayItems = [];
  LoadingStatus _status = LoadingStatus.loading;

  // initStateは、画面が作成されたときに一度だけ呼ばれる特別な場所です
  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoadImages(); // ← 画面が表示される前に、権限リクエストの処理を呼び出す
  }

  // 権限リクエストと画像読み込みをまとめて行う関数
  Future<void> _requestPermissionAndLoadImages() async {
    // photo_managerが提供する、より丁寧な権限リクエスト。こちらの場合、Pixivフォルダ等のアルバムまでしかアクセスできない。
    // final PermissionState ps = await PhotoManager.requestPermissionExtend();
    // こちらは、MANAGE_EXTERNAL_STORAGE権限を直接リクエストする方法。より強力だが、Google Playのポリシーに注意。
    var ps = await Permission.manageExternalStorage.request();
    if (ps.isGranted) {
      // 許可された場合
      print("写真へのアクセスが許可されました。");
      _loadImages();
    } else {
      // 拒否された場合
      print("写真へのアクセスが拒否されました。");
      // 権限が拒否されたら、状態を「空」にしてメッセージ表示
      setState(() {
        _status = LoadingStatus.empty;
      });
      // TODO: ここでユーザーに設定画面へ誘導するなどの処理も可能
      // await PhotoManager.openSetting();
    }
  }

  /*
  Future<void> _loadImages() async {
    // Providerから設定データを取得（listen: false で、UIの再構築は要求しない）
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final selectedPaths = settings.selectedPaths;

    setState(() {
      _status = LoadingStatus.loading; // 読み込み開始
    });

    // 選択されたフォルダ名だけを抽出 (例: "/path/to/Pixiv" -> "Pixiv")
    final selectedFolderNames = selectedPaths
        .map((path) => path.split('/').last.toLowerCase())
        .toList();

    // .nomediaを無視するフィルタ設定
    final filterOption = FilterOptionGroup(includeHiddenAssets: true);

    // すべてのアルバムを取得
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      filterOption: filterOption,
    );

    if (albums.isEmpty) {
      print("アルバムが見つかりませんでした。");
      return;
    }

    // 結果を格納するための空のリストを用意
    List<AssetEntity> allAssets = [];

    // すべてのアルバムをチェック
    for (final album in albums) {
      // アルバム名が、選択されたフォルダ名のリストに含まれているかチェック
      if (selectedFolderNames.contains(album.name.toLowerCase())) {
        print('${album.name} フォルダを発見。画像を読み込みます。');
        final assets = await album.getAssetListRange(
          start: 0,
          end: await album.assetCountAsync,
        );
        allAssets.addAll(assets); // 見つかった画像をリストに追加
      }
    }

    // 最終的に見つかったすべてのアセットでUIを更新
    setState(() {
      _assets = allAssets;
      if (_assets.isEmpty) {
        _status = LoadingStatus.empty; // 結果が0件なら「空」状態に
      } else {
        _status = LoadingStatus.completed; // 1件以上あれば「完了」状態に
      }
    });

    print('合計 ${_assets.length} 個の画像が見つかりました。');
  }
  */
  // in _MyHomePageState class

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
          print('直接スキャン中: ${filePath}');
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
                },
                child: thumbnailWidget,
              );
            },
          );
        /*
          return GridView.builder(
            // グリッドのレイアウトを定義
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, // 1行に表示するアイテム数
              crossAxisSpacing: 2.0, // アイテム間の水平方向のスペース
              mainAxisSpacing: 2.0, // アイテム間の垂直方向のスペース
            ),
            // 表示するアイテムの総数
            // itemCount: _assets.length,
            itemCount: _displayItems.length,
            // 各アイテム（グリッドの1マス）をどのように描画するかを定義
            itemBuilder: (BuildContext context, int index) {
              // final asset = _assets[index];
              final asset = _displayItems[index];
              return GestureDetector(
                onTap: () async {
                  // 詳細画面に遷移する直前に、高解像度のFileを取得する
                  final file = await asset.file;
                  if (file != null && mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DetailScreen(imageFile: file),
                      ),
                    );
                  }
                },
                // ここで自作した AssetThumbnail ウィジェットを使う
                child: AssetThumbnail(asset: asset),
              );
            },
          );
          */
        case LoadingStatus.error:
          return const Text('エラーが発生しました。');
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
