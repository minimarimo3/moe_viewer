import 'dart:developer';

import '../gallery/gallery_screen.dart';
import '../permission/permission_screen.dart';
import '../../core/providers/settings_provider.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

class DispatchScreen extends StatefulWidget {
  const DispatchScreen({super.key});

  @override
  State<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends State<DispatchScreen> {
  @override
  void initState() {
    super.initState();
    _dispatch();
  }

  Future<void> _dispatch() async {
    try {
      final settings = Provider.of<SettingsProvider>(context, listen: false);

      // 設定の初期化を非同期で開始（UIをブロックしない）
      final initFuture = settings.init();

      // 権限チェックを並行して実行
      final statusFuture = Permission.photos.status;

      // 両方の処理が完了するまで待機
      final results = await Future.wait([initFuture, statusFuture]);
      final status = results[1] as PermissionStatus;

      if (!mounted) return;

      if (status.isGranted || status.isLimited) {
        // 権限があればメイン画面へ
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const MyHomePage(title: "Moe Viewer Home Page"),
          ),
        );
      } else {
        // 権限がなければ権限要求画面へ
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PermissionScreen()),
        );
      }
    } catch (e) {
      // エラーが発生した場合でもアプリを停止させない
      log('Dispatch error: $e');
      if (!mounted) return;

      // エラーが発生した場合は権限画面へ
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PermissionScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // チェック中はローディング画面を表示
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('アプリを準備中...', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
