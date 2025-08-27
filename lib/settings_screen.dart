import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  // StatefulWidgetからStatelessWidgetに変更してOK
  const SettingsScreen({super.key});
  // bool _enableNsfwFilter = false; // NSFWフィルタのON/OFF状態（仮）

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return Scaffold(
          appBar: AppBar(title: const Text('設定')),
          body: ListView(
            children: [
              // --- ディレクトリ設定 ---
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('表示するフォルダを選択'),
                subtitle: const Text('現在選択中のフォルダ: Pixiv'), // 今は仮表示
                onTap: () async {
                  // フォルダピッカーを開く
                  String? result = await FilePicker.platform.getDirectoryPath();
                  if (result != null) {
                    // 選択されたパスをProviderに追加
                    settings.addPath(result);
                  }
                },
              ),
              const Divider(),
              // --- 現在選択中のフォルダ一覧 ---
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  '現在選択中のフォルダ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              // settings.selectedPaths の内容をリスト表示
              for (String path in settings.selectedPaths)
                ListTile(
                  title: Text(path),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      // パスを削除
                      settings.removePath(path);
                    },
                  ),
                ),

              const Divider(),

              // --- NSFWフィルタ設定 ---
              SwitchListTile(
                secondary: const Icon(Icons.visibility_off_outlined),
                title: const Text('AIによるNSFW判定を有効にする'),
                subtitle: const Text('（準備中）'),
                value: settings.nsfwFilterEnabled, // ★★★ Providerから値を取得
                onChanged: (newValue) {
                  settings.setNsfwFilter(newValue); // ★★★ Providerの関数を呼び出す
                },
              ),

              const Divider(),

              // --- 寄付・サポート ---
              ListTile(
                leading: const Icon(Icons.favorite_border),
                title: const Text('開発者をサポート'),
                subtitle: const Text('（準備中）'),
                onTap: () {
                  // TODO: 寄付ページへのリンクなどを開く
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
