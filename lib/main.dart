import 'detail_screen.dart';
import 'package:flutter/material.dart';

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
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<File> _images = [];
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
      // ここでユーザーに設定画面へ誘導するなどの処理も可能
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

      // ④ AssetEntityをFileオブジェクトに変換
      List<File> imageFiles = [];
      for (var asset in assets) {
        // タイプが画像のものだけを対象にする
        if (asset.type == AssetType.image) {
          final file = await asset.file;
          if (file != null) {
            imageFiles.add(file);
          }
        }
      }

      setState(() {
        _images = imageFiles;
      });
      print('${_images.length} 個の画像が見つかりました。');
    } else {
      print('Pixiv アルバムが見つかりませんでした。');
      // デバッグ用に、見つかったすべてのアルバム名を表示してみる
      print('見つかったアルバム: ${albums.map((a) => a.name).toList()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // backgroundColor: Colors.amber,
        // title: Text(widget.title),
        title: const Text('Pixiv Viewer'),
      ),
      body: _images.isEmpty
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
              itemCount: _images.length,
              // 各アイテム（グリッドの1マス）をどのように描画するかを定義
              itemBuilder: (BuildContext context, int index) {
                final imageFile = _images[index];
                return GestureDetector(
                  onTap: () {
                    // 画像がタップされたときの処理
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DetailScreen(imageFile: imageFile),
                      ),
                    );
                  },
                  child: Image.file(
                    imageFile,
                    fit: BoxFit.cover, // 画像を枠に合わせてトリミング
                  ),
                );
              },
            ),
    );
  }
}
