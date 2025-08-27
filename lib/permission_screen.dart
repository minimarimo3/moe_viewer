// lib/permission_screen.dart

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'main.dart';

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
                  Image.asset('assets/images/explanation.gif'),
                  const SizedBox(height: 20),
                  const Text(
                    "このアプリを動作させるには、デバイスの写真へのアクセス許可が必要です。\n\n"
                    "あなたの写真データが外部に送信されることは決してありません。全ての処理はあなたのデバイス内で完結します。",
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
