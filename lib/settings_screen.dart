import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'settings_provider.dart';
import '../utils/dialogs.dart';

class SettingsScreen extends StatefulWidget {
  // ★★★ StatefulWidgetに変更
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // StatefulWidgetからStatelessWidgetに変更してOK
  // const SettingsScreen({super.key});
  // bool _enableNsfwFilter = false; // NSFWフィルタのON/OFF状態（仮）

  bool _hasFullAccess = false; // ★★★ 権限の状態を保持する変数

  @override
  void initState() {
    super.initState();
    _checkFullAccessPermission(); // 画面表示時に現在の権限状態をチェック
  }

  // ★★★ どのパスが特別権限を必要とするか判断するヘルパー関数 ★★★
  bool _isRestrictedPath(String path) {
    // 標準的な公共メディアディレクトリのキーワード
    const standardMediaDirs = [
      '/Pictures',
      '/DCIM',
      '/Download',
      '/Movies',
      '/Music',
      '/Documents',
    ];

    // パスに標準ディレクトリのキーワードが含まれていれば、それは公共エリアなのでfalse
    for (final dir in standardMediaDirs) {
      if (path.contains(dir)) {
        return false;
      }
    }

    // それ以外の場合（例: /storage/emulated/0/MyIllustsなど）は個室とみなし、true
    return true;
  }

  // ★★★ 全ファイルアクセス権限の現在の状態を確認する関数
  Future<void> _checkFullAccessPermission() async {
    final status = await Permission.manageExternalStorage.status;
    if (mounted) {
      setState(() {
        _hasFullAccess = status.isGranted;
      });
    }
  }

  // ★★★ 権限を要求するための関数
  Future<void> _requestFullAccessPermission() async {
    final status = await Permission.manageExternalStorage.request();
    setState(() {
      _hasFullAccess = status.isGranted;
    });

    // ユーザーに結果をフィードバック
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _hasFullAccess ? '全ファイルへのアクセスが許可されました！' : '権限が許可されませんでした。',
          ),
          backgroundColor: _hasFullAccess ? Colors.green : Colors.red,
        ),
      );
    }
  }

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
                // subtitle: const Text('現在選択中のフォルダ: Pixiv'), // 今は仮表示
                onTap: () async {
                  // フォルダピッカーを開く
                  String? result = await FilePicker.platform.getDirectoryPath();
                  if (result != null) {
                    // 選択されたパスをProviderに追加
                    // settings.addPath(result);
                    settings.addFolder(result);
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
              // for (String path in settings.selectedPaths)
              for (FolderSetting folder in settings.folderSettings)
                ListTile(
                  // ★★★ 条件に応じてアイコンを表示 ★★★
                  // leading: (_isRestrictedPath(path) && !_hasFullAccess)
                  leading: (_isRestrictedPath(folder.path) && !_hasFullAccess)
                      ? Tooltip(
                          // アイコンにマウスカーソルを合わせるとメッセージが出る
                          message: 'このフォルダのスキャンには「すべてのフォルダをスキャンする」権限の許可が必要です。',
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                          ),
                        )
                      : Icon(Icons.folder_outlined), // 通常のフォルダアイコン
                  title: Text(
                    folder.path.split('/').last, // パスの最後の部分（フォルダ名）だけ表示
                    style: TextStyle(
                      // ★★★ 条件に応じて文字色を少し薄くする ★★★
                      color: (_isRestrictedPath(folder.path) && !_hasFullAccess)
                          ? Theme.of(context).disabledColor
                          : null,
                    ),
                  ),
                  subtitle: Text(folder.path, style: TextStyle(fontSize: 12)),
                  /*
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      // settings.removePath(path);
                      settings.removeFolder(folder.path);
                    },
                  ),
                  */
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: folder.isEnabled,
                        onChanged: (bool? value) {
                          if (value != null) {
                            settings.toggleFolderEnabled(folder.path);
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          settings.removeFolder(
                            folder.path,
                          ); // ★★★ removeFolderを呼び出し
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    // if (_isRestrictedPath(path) && !_hasFullAccess) {
                    if (_isRestrictedPath(folder.path) && !_hasFullAccess) {
                      showInfoDialog(
                        context,
                        title: '追加の権限が必要です',
                        content:
                            'このフォルダ内の画像をスキャンするには、「すべてのフォルダをスキャンする」権限を許可する必要があります。\n\n'
                            'この設定をONにすると、OSのアルバムに登録されていない、あらゆる場所の画像フォルダを読み込めるようになります。',
                      );
                    }
                  },
                ),

              /*
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
                */
              const Divider(),

              // --- NSFWフィルタ設定 ---
              /*
              SwitchListTile(
                // secondary: const Icon(Icons.visibility_off_outlined),
                secondary: IconButton(
                  icon: const Icon(Icons.info_outline),
                  onPressed: () {
                    showInfoDialog(
                      context,
                      title: 'AIによる画像解析とは',
                      content:
                          '（ここにNSFW機能に関する詳しい説明文を入れます）\n\n'
                          'この機能を有効にすると、アプリはデバイス内で画像のタグを分析し、不適切な可能性のある画像を自動的にフィルタリングします。\n\n'
                          'この処理はすべてオフラインで完結し、あなたの画像が外部に送信されたり、画像が学習に使用されたりすることはありません。',
                    );
                  },
                ),
                title: const Text('オフラインAIによる画像解析を有効にする'),
                subtitle: const Text('（準備中）'),
                value: settings.nsfwFilterEnabled, // ★★★ Providerから値を取得
                onChanged: (newValue) {
                  settings.setNsfwFilter(newValue); // ★★★ Providerの関数を呼び出す
                },
              ),
              */
              ListTile(
                // ★★★ アイコンは元のものに戻す
                leading: const Icon(Icons.visibility_off_outlined),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 左側にタイトルとサブタイトルを配置
                    const Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('オフラインAIによる画像解析を有効にする'),
                          Text(
                            '画像が機械学習に用いられたり、外部に送信されたりすることはありません',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    // 右側に情報アイコンとスイッチを配置
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ★★★ 有効化ボタン（スイッチ）の直前に情報アイコンを配置
                        IconButton(
                          icon: const Icon(Icons.info_outline),
                          tooltip: '機能の詳細を表示', // 長押しでヒント表示
                          onPressed: () {
                            showInfoDialog(
                              context,
                              title: 'AIによる画像解析とは',
                              content:
                                  'この機能を有効にすると、アプリはデバイス内で画像の内容を分析し、タグ付けを行います。\n\n'
                                  'これにより金髪といった言葉で画像を検索できたり、ジャンル別にフィルタリングすることが可能になります。\n\n'
                                  'この処理はすべてオフラインで完結し、あなたの画像が外部に送信されることはありません。\n\n'
                                  'また、この機能を有効にしても、画像が機械学習に用いられたりすることはありません。',
                            );
                          },
                        ),
                        Switch(
                          value: settings.nsfwFilterEnabled,
                          onChanged: (newValue) {
                            settings.setNsfwFilter(newValue);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(),

              ListTile(
                leading: Icon(
                  _hasFullAccess
                      ? Icons.folder_special
                      : Icons.folder_special_outlined,
                  color: _hasFullAccess ? Colors.blue : null,
                ),
                title: const Text('すべてのフォルダをスキャンする'),
                subtitle: Text(
                  _hasFullAccess ? '許可されています' : 'アルバム以外のフォルダも検索します',
                ),
                trailing: ElevatedButton(
                  // 許可済みの場合はボタンを無効化
                  onPressed: _hasFullAccess
                      ? null
                      : _requestFullAccessPermission,
                  child: Text(_hasFullAccess ? '許可済み' : '許可する'),
                ),
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
