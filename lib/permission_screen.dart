import 'main.dart';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  // 権限を要求し、許可されたらメイン画面に遷移する関数
  Future<void> _requestAndProceed() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth || ps.hasAccess) {
      // 権限が許可されたら、この画面を破棄してメイン画面に遷移
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const MyHomePage(title: "Moe Viewer Home Page"),
        ),
      );
    } else {
      // 権限が拒否されたことを伝える（任意）
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('写真へのアクセスが許可されませんでした。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "ようこそ！",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "はじめに",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    "このアプリは@minimarimo3が個人で開発しているものです。\n\n"
                    "アプリのレシピ（ソースコード）はGitHubで公開されています。\n\n"
                    "バグ報告や機能要望なんかは気軽に設定の「フィードバック」からどうぞ！",
                  ),
                  const SizedBox(height: 20),
                  // Image.asset('assets/images/explanation.gif'),
                  const Text("ここにgif"),
                  const SizedBox(height: 20),
                  const Text(
                    "PixivフォルダやDownloadした画像、Twitterで保存した画像にアクセスするために、「デバイスの写真へのアクセス許可」というものが必要です。\n\n"
                    "フォルダの中身が外部に漏れるとかそういうヤバいことは起きないので安心してください。\n\n"
                    "下のボタンを押して「写真へのアクセスを全て許可」を押してください。\n\n",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text("写真へのアクセスを許可する"),
                    onPressed: _requestAndProceed,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
