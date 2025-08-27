import 'package:flutter/material.dart';
import 'detail_screen.dart';
import 'asset_thumbnail.dart';

import 'dart:io'; // ファイルやディレクトリを操作するためのライブラリ
import 'package:photo_manager/photo_manager.dart';
// import 'package:path_provider/path_provider.dart'; // フォルダのパスを取得するためのパッケージ
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
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
      // TODO: ここでユーザーに設定画面へ誘導するなどの処理も可能
      // await PhotoManager.openSetting();
    }
  }

  // photo_managerを使って画像を読み込む新しい関数
  Future<void> _loadImages() async {
    // ① すべてのアルバム（フォルダ）を取得
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      // .nomedia対策
      filterOption: FilterOptionGroup(includeHiddenAssets: true),
    );

    if (albums.isEmpty) {
      print("アルバムが見つかりませんでした。");
      return;
    }

    // ② "Pixiv" という名前のアルバムを探す
    AssetPathEntity? pixivAlbum;
    for (var album in albums) {
      if (album.name.toLowerCase() == 'pixiv') {
        // 小文字に変換して比較
        pixivAlbum = album;
        break;
      }
    }

    if (pixivAlbum != null) {
      // ③ アルバム内のすべてのアセット（画像・動画）を取得
      final List<AssetEntity> assets = await pixivAlbum.getAssetListRange(
        start: 0,
        end: await pixivAlbum.assetCountAsync,
      );

      setState(() {
        _assets = assets;
      });
      print('${_assets.length} 個の画像が見つかりました。');
    } else {
      print('Pixiv アルバムが見つかりませんでした。');
      // デバッグ用に、見つかったすべてのアルバム名を表示してみる
      print('見つかったアルバム: ${albums.map((a) => a.name).toList()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // backgroundColor: Colors.amber,
        title: const Text('Pixiv Viewer'),
      ),
      // body: _images.isEmpty
      body: _assets.isEmpty
          ? const Center(
              // 画像がまだない場合は、ローディングインジケーターを表示
              child: CircularProgressIndicator(),
            )
          : GridView.builder(
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
            ),
    );
  }
}
