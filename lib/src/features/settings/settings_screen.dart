import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/ai_model_definition.dart';
import '../../core/providers/settings_provider.dart';
import 'licenses_screen.dart';
import 'widgets/ai_analysis_section.dart';
import 'widgets/display_settings_section.dart';
import 'widgets/folder_settings_section.dart';
import 'widgets/maintenance_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _shownDownloadErrorVersion = 0; // SnackBar多重表示防止

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 現在選択されているモデルの定義を取得
      final settings = context.read<SettingsProvider>();
      final selectedModelDef = availableModels.firstWhere(
        (m) => m.id == settings.selectedModelId,
        orElse: () => availableModels.first,
      );

      // モデルのダウンロード状況のみをチェック（ハッシュチェックは行わない）
      await settings.checkModelDownloadStatus(selectedModelDef);

      // フォルダ統計を強制更新
      settings.forceUpdateFolderStats();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        // ダウンロード失敗時のユーザー通知（SnackBar）
        if (settings.downloadErrorMessage != null &&
            settings.downloadErrorVersion != _shownDownloadErrorVersion) {
          _shownDownloadErrorVersion = settings.downloadErrorVersion;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final msg = settings.downloadErrorMessage!;
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          });
        }

        return Scaffold(
          appBar: AppBar(title: const Text('設定')),
          body: ListView(
            children: [
              const FolderSettingsSection(),
              const MaintenanceSection(),
              const DisplaySettingsSection(),
              const AiAnalysisSection(),

              const Divider(),

              ListTile(
                leading: const Icon(Icons.favorite_border),
                title: const Text('開発者をサポート'),
                subtitle: const Text('（準備中）'),
                onTap: () {},
              ),

              const Divider(),

              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('使用ライブラリとライセンス'),
                subtitle: const Text('このアプリで使用しているライブラリの一覧とライセンスを表示します'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (ctx) => const LicensesScreen()),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
