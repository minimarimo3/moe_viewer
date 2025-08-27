import 'dart:io';
import 'package:flutter/material.dart';

class DetailScreen extends StatelessWidget {
  final File imageFile;

  // 前の画面から表示したい画像ファイルを受け取る
  const DetailScreen({super.key, required this.imageFile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBarがあると、自動的に「戻る」ボタンが配置される
      appBar: AppBar(),
      // backgroundColorを黒にすると、より画像が引き立つ
      backgroundColor: Colors.black,
      body: Center(
        // InteractiveViewerで囲むだけで、ピンチ操作による拡大・縮小が可能になる
        child: InteractiveViewer(
          child: Image.file(imageFile),
        ),
      ),
    );
  }
}