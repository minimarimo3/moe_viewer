import 'package:flutter/material.dart';

import 'settings_screen.dart';
import 'detail_screen.dart';
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
  List<AssetEntity> _assets = [];
  LoadingStatus _status = LoadingStatus.loading;

  // initStateは、画面が作成されたときに一度だけ呼ばれる特別な場所です
  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoadImages(); // ← 画面が表示される前に、権限リクエストの処理を呼び出す
  }

  // 権限リクエストと画像読み込みをまとめて行う関数
  Future<void> _requestPermissionAndLoadImages() async {
    // photo_managerが提供する、より丁寧な権限リクエスト
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    print("Permission state is: $ps");
    if (ps == PermissionState.authorized || ps == PermissionState.limited) {
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
            // グリッドのレイアウトを定義
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, // 1行に表示するアイテム数
              crossAxisSpacing: 2.0, // アイテム間の水平方向のスペース
              mainAxisSpacing: 2.0, // アイテム間の垂直方向のスペース
            ),
            // 表示するアイテムの総数
            itemCount: _assets.length,
            // 各アイテム（グリッドの1マス）をどのように描画するかを定義
            itemBuilder: (BuildContext context, int index) {
              final asset = _assets[index];
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
