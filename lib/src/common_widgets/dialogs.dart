import 'package:flutter/material.dart';

// アプリ内のどこからでも呼び出せる情報ダイアログ関数
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String content,
}) async {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        // 長い文章でもスクロールできるようにする
        content: SingleChildScrollView(child: Text(content)),
        actions: <Widget>[
          TextButton(
            child: const Text('OK'),
            onPressed: () {
              // OKボタンを押すとダイアログを閉じる
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}
