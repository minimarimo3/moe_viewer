import '../gallery/gallery_screen.dart';
import '../permission/permission_screen.dart';
import '../../core/providers/ui_settings_provider.dart';
import '../../core/providers/folder_settings_provider.dart';
import '../../core/providers/model_provider.dart';

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
    final ui = Provider.of<UiSettingsProvider>(context, listen: false);
    final folders = Provider.of<FolderSettingsProvider>(context, listen: false);
    final model = Provider.of<ModelProvider>(context, listen: false);
    await Future.wait([ui.load(), folders.load(), model.load()]);

    // ここでは権限を要求せず、現在の状態だけを確認する
    final status = await Permission.photos.status;

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
  }

  @override
  Widget build(BuildContext context) {
    // チェック中はローディング画面を表示
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
