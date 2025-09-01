import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/providers/settings_provider.dart';
import '../../common_widgets/dialogs.dart';
import '../../core/services/ai_service.dart';
import '../../core/models/ai_model_definition.dart';
import '../../core/models/folder_setting.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _hasFullAccess = false;

  @override
  void initState() {
    super.initState();

    // TODO: これハルシネーションかもしれん
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Providerから現在の設定とAiServiceを取得
      final settings = context.read<SettingsProvider>();
      final aiService = context.read<AiService>();

      // 現在選択されているモデルの定義を取得
      final selectedModelDef = availableModels.firstWhere(
        (m) => m.id == settings.selectedModelId,
        orElse: () => availableModels.first,
      );

      // AiServiceに、このモデルで起動するように命令
      await aiService.switchModel(selectedModelDef);

      // 起動したモデルの状態（ダウンロード済みか、破損していないか）をチェック
      await settings.checkModelStatus(selectedModelDef);
    });

    _checkFullAccessPermission();
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
        final selectedModel = availableModels.firstWhere(
          (m) => m.id == settings.selectedModelId,
          orElse: () => availableModels.first,
        );

        final selectedModelDef = availableModels.firstWhere(
          (m) => m.id == settings.selectedModelId,
        );

        return Scaffold(
          appBar: AppBar(title: const Text('設定')),
          body: ListView(
            children: [
              // --- ディレクトリ設定（表示するフォルダを選択） ---
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('表示するフォルダを選択'),
                onTap: () async {
                  // フォルダピッカーを開く
                  String? result = await FilePicker.platform.getDirectoryPath();
                  if (result != null) {
                    // 選択されたパスをProviderに追加
                    settings.addFolder(result);
                  }
                },
              ),

              const Divider(),

              // --- 現在選択中のフォルダ ---
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  '現在選択中のフォルダ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              // settings.selectedPaths の内容をリスト表示
              // --- 実際のフォルダリスト ---
              // TODO: これPaddingのchildrenに入れるべきな気がする
              for (FolderSetting folder in settings.folderSettings)
                ListTile(
                  // ★★★ 条件に応じてアイコンを表示 ★★★
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
                      // Pixiv等の特定フォルダは削除不可にする
                      if (folder.isDeletable)
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
                  onTap: () async {
                    if (_isRestrictedPath(folder.path) && !_hasFullAccess) {
                      /*
                      showInfoDialog(
                        context,
                        title: '追加の権限が必要です',
                        content:
                            'このフォルダ内の画像をスキャンするには、「すべてのフォルダをスキャンする」権限を許可する必要があります。\n\n'
                            'この設定をONにすると、OSのアルバムに登録されていない、あらゆる場所の画像フォルダを読み込めるようになります。',
                      );
                      */
                      // 1. まず説明ダイアログを表示
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('追加の権限が必要です'),
                          content: const SingleChildScrollView(
                            // 長文でもスクロール可能
                            child: Text(
                              'このフォルダ内の画像をスキャンするには、「全ファイルへのアクセス」権限が必要です。\n\n'
                              'この権限を許可すると、OSの標準アルバム以外の、あらゆる場所にある画像フォルダをアプリで表示できるようになります。',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('許可する'),
                            ),
                          ],
                        ),
                      );

                      // 2. ユーザーが「許可する」を押した場合のみ、OSの権限要求を実行
                      if (confirm == true) {
                        await _requestFullAccessPermission();
                      }
                    }
                  },
                ),

              const Divider(),

              // --- 一覧表示グリッドの列数設定 ---
              ListTile(
                leading: const Icon(Icons.grid_view_outlined),
                title: Text('一覧の列数 (${settings.gridCrossAxisCount})'),
                subtitle: Slider(
                  value: settings.gridCrossAxisCount.toDouble(),
                  min: 1, // 最小1列
                  max: 8, // 最大8列
                  divisions: 7, // 刻み数 (8-1)
                  label: settings.gridCrossAxisCount.toString(),
                  onChanged: (double value) {
                    settings.setGridCrossAxisCount(value.toInt());
                  },
                ),
              ),

              const Divider(),

              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: const Text('アプリのテーマ'),
                trailing: DropdownButton<ThemeMode>(
                  value: settings.themeMode,
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('システム設定に従う'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('ライト'),
                    ),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('ダーク')),
                  ],
                  onChanged: (ThemeMode? newMode) {
                    if (newMode != null) {
                      settings.setThemeMode(newMode);
                    }
                  },
                ),
              ),

              const Divider(),

              // --- オフラインAIによる画像解析設定 ---
              ListTile(
                leading: const Icon(Icons.psychology_outlined),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 左側にタイトルとサブタイトルを配置
                    const Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('オフラインAIによる画像解析'),
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
                                  'この機能を有効にすることでアプリはデバイス内で画像の内容を分析し、タグ付けを行うことができます。\n\n'
                                  'これにより金髪といった特徴で画像を検索できたり、ジャンル別でのフィルタリングが可能になります。\n\n'
                                  'この処理はすべてオフラインで完結し、あなたの画像が外部に送信されることはありません。\n\n'
                                  'また、この機能を有効にしても、画像が機械学習に用いられたりすることはありません。',
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // ---  AIモデルの選択 ---
              ListTile(
                leading: const Icon(Icons.memory),
                title: const Text('AIモデルを選択'),
                trailing: DropdownButton<String>(
                  value: settings.selectedModelId,
                  onChanged: settings.isDownloading
                      ? null
                      : (String? newModelId) async {
                          log("モデル変更のドロップダウンが呼ばれました");
                          if (newModelId != null) {
                            log("新しいモデルID: $newModelId");
                            await settings.setSelectedModel(newModelId);
                            final selectedModelDef = availableModels.firstWhere(
                              (m) => m.id == newModelId,
                            );
                            await settings.checkModelStatus(selectedModelDef);
                          }
                        },
                  items: availableModels.map<DropdownMenuItem<String>>((model) {
                    return DropdownMenuItem<String>(
                      value: model.id,
                      child: Text(model.displayName),
                    );
                  }).toList(),
                ),
              ),

              // --- モデルのダウンロード状況 ---
              if (settings.selectedModelId != 'none')
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: settings.isCheckingHash
                      ? const ListTile(
                          leading: CircularProgressIndicator(),
                          title: Text('モデルの整合性をチェック中...'),
                        )
                      : settings.isModelDownloaded
                      // --- ダウンロード済みの場合 ---
                      ? Column(
                          children: [
                            // もしモデルが破損していたら、警告と修復ボタンを表示
                            if (settings.isModelCorrupted)
                              ListTile(
                                leading: Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.red,
                                ),
                                title: Text('モデルファイルが破損しています'),
                                trailing: ElevatedButton(
                                  child: const Text('修復'),
                                  onPressed: () async {
                                    // ★★★ 再ダウンロードの確認ダイアログを表示 ★★★
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('モデルの再ダウンロード'),
                                        content: const Text(
                                          'モデルファイルを再ダウンロードして修復しますか？',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(
                                              context,
                                            ).pop(false),
                                            child: const Text('キャンセル'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(true),
                                            child: const Text('再ダウンロード'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      settings.downloadModel(selectedModel);
                                    }
                                  },
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16.0,
                                8.0,
                                16.0,
                                8.0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '解析インデックス達成度 (解析済み：${settings.analyzedFileCount})',
                                  ),
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                    value: settings.totalFileCount > 0
                                        ? settings.analyzedFileCount /
                                              settings.totalFileCount
                                        : 0,
                                    minHeight: 8, // バーの太さを少し太くする
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              ),
                            ),
                            if (!settings.isModelCorrupted)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                ),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: settings.isAnalyzing
                                        ? Colors.red
                                        : null,
                                  ),
                                  onPressed: () {
                                    if (settings.isAnalyzing) {
                                      settings.stopAiAnalysis();
                                    } else {
                                      final aiService = context
                                          .read<AiService>();
                                      settings.startAiAnalysis(aiService);
                                    }
                                  },
                                  child: Text(
                                    settings.isAnalyzing ? '解析を停止' : '解析を開始',
                                  ),
                                ),
                              ),

                            /*
                          if (settings.isAnalyzing && settings.currentAnalyzingFile.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16.0,
                                8.0,
                                16.0,
                                0,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '解析対象: ${settings.currentAnalyzingFile}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (settings.lastFoundTags.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Wrap(
                                        spacing: 6.0,
                                        runSpacing: 4.0,
                                        children: settings.lastFoundTags
                                            .map(
                                              (tag) => Chip(
                                                label: Text(tag),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: const EdgeInsets.all(
                                                  2.0,
                                                ),
                                                labelStyle: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          */
                            if (settings.isAnalyzing &&
                                settings.currentAnalyzingFile.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16.0,
                                  8.0,
                                  16.0,
                                  0,
                                ),
                                child: Row(
                                  // ★★★ Rowで横並びにする ★★★
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ★★★ 左側: AIが見ている画像 ★★★
                                    if (settings.currentAnalyzedImageBase64 !=
                                        null)
                                      Container(
                                        width: 80, // 画像の幅
                                        height: 80, // 画像の高さ
                                        margin: const EdgeInsets.only(
                                          right: 8.0,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          child: Image.memory(
                                            base64Decode(
                                              settings
                                                  .currentAnalyzedImageBase64!,
                                            ),
                                            fit: BoxFit.cover,
                                            gaplessPlayback:
                                                true, // 画像が更新されてもちらつかないように
                                          ),
                                        ),
                                      ),
                                    // ★★★ 右側: 解析結果のタグとファイル名 ★★★
                                    Expanded(
                                      // 残りのスペースをタグとファイル名が使う
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'ファイル: ${settings.currentAnalyzingFile}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (settings.lastFoundTags.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4.0,
                                              ),
                                              child: Wrap(
                                                spacing: 6.0,
                                                runSpacing: 4.0,
                                                children: settings.lastFoundTags
                                                    .map(
                                                      (tag) => Chip(
                                                        label: Text(tag),
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        padding:
                                                            const EdgeInsets.all(
                                                              2.0,
                                                            ),
                                                        labelStyle:
                                                            const TextStyle(
                                                              fontSize: 11,
                                                            ),
                                                      ),
                                                    )
                                                    .toList(),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        )
                      // --- 未ダウンロードの場合 ---
                      : Column(
                          children: [
                            Text(
                              '解析のために解析用ファイル（${selectedModelDef.displaySize}）をダウンロードする必要があります。',
                            ),
                            const SizedBox(height: 8),
                            settings.isDownloading
                                ? /*Column(
                                    children: [
                                      LinearProgressIndicator(
                                        value: settings.downloadProgress,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${(settings.downloadProgress * 100).toStringAsFixed(1)}%',
                                      ),
                                    ],
                                  )
                                  */ Column(
                                    children: [
                                      // ★★★ 進捗バーとキャンセルボタンを横並びにする ★★★
                                      Row(
                                        children: [
                                          // 進捗バーが残りのスペースを全て使うようにする
                                          Expanded(
                                            child: LinearProgressIndicator(
                                              value: settings.downloadProgress,
                                            ),
                                          ),

                                          // キャンセルボタン
                                          IconButton(
                                            icon: const Icon(Icons.close),
                                            tooltip: 'ダウンロードを中止',
                                            onPressed: () async {
                                              // ★★★ 確認ダイアログを表示 ★★★
                                              final confirm = await showDialog<bool>(
                                                context: context,
                                                builder: (context) => AlertDialog(
                                                  title: const Text(
                                                    'ダウンロードの中止',
                                                  ),
                                                  content: const Text(
                                                    'ダウンロードを中止しますか？\n（解析用ファイルは削除されます）',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            context,
                                                          ).pop(false),
                                                      child: const Text('いいえ'),
                                                    ),
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            context,
                                                          ).pop(true),
                                                      child: const Text('はい'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirm == true) {
                                                log(
                                                  'ユーザーがダウンロード中止を確認しました。キャンセル処理を実行します。',
                                                );
                                                settings.cancelDownload();
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${(settings.downloadProgress * 100).toStringAsFixed(1)}%',
                                      ),
                                    ],
                                  )
                                : ElevatedButton.icon(
                                    icon: const Icon(Icons.download),
                                    label: const Text('解析用ファイルをダウンロード'),
                                    onPressed: () async {
                                      // 引数なしの関数の中で、引数を付けて呼び出す
                                      await settings.downloadModel(
                                        selectedModel,
                                      );
                                    },
                                  ),
                          ],
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
