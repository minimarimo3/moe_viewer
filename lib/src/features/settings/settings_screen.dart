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
  int _shownDownloadErrorVersion = 0; // SnackBar多重表示防止
  int _shownHashMismatchErrorVersion = 0; // ハッシュ不一致エラーSnackBar多重表示防止

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Providerから現在の設定を取得
      final settings = context.read<SettingsProvider>();

      // 現在選択されているモデルの定義を取得
      final selectedModelDef = availableModels.firstWhere(
        (m) => m.id == settings.selectedModelId,
        orElse: () => availableModels.first,
      );

      // モデルのダウンロード状況のみをチェック（ハッシュチェックは行わない）
      await settings.checkModelDownloadStatus(selectedModelDef);
    });

    _checkFullAccessPermission();
  }

  bool _isRestrictedPath(String path) {
    const standardMediaDirs = [
      '/Pictures',
      '/DCIM',
      '/Download',
      '/Movies',
      '/Music',
      '/Documents',
    ];
    for (final dir in standardMediaDirs) {
      if (path.contains(dir)) return false;
    }
    return true;
  }

  Future<void> _checkFullAccessPermission() async {
    final status = await Permission.manageExternalStorage.status;
    if (mounted) {
      setState(() {
        _hasFullAccess = status.isGranted;
      });
    }
  }

  Future<void> _requestFullAccessPermission() async {
    final status = await Permission.manageExternalStorage.request();
    setState(() {
      _hasFullAccess = status.isGranted;
    });

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

        // ハッシュ不一致時のユーザー通知（SnackBar）
        if (settings.hashMismatchErrorMessage != null &&
            settings.hashMismatchErrorVersion !=
                _shownHashMismatchErrorVersion) {
          _shownHashMismatchErrorVersion = settings.hashMismatchErrorVersion;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final msg = settings.hashMismatchErrorMessage!;
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                backgroundColor: Colors.orange,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 5),
              ),
            );
          });
        }

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
                  String? result = await FilePicker.platform.getDirectoryPath();
                  if (result != null) {
                    settings.addFolder(result);
                  }
                },
              ),

              const Divider(),

              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  '現在選択中のフォルダ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

              for (FolderSetting folder in settings.folderSettings)
                ListTile(
                  leading: _isRestrictedPath(folder.path) && !_hasFullAccess
                      ? Tooltip(
                          message: 'このフォルダのスキャンには「すべてのフォルダをスキャンする」権限の許可が必要です。',
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                          ),
                        )
                      : Icon(Icons.folder_outlined),
                  title: Text(
                    folder.path.split('/').last,
                    style: TextStyle(
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
                      if (folder.isDeletable)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => settings.removeFolder(folder.path),
                        ),
                    ],
                  ),
                  onTap: () async {
                    if (_isRestrictedPath(folder.path) && !_hasFullAccess) {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('追加の権限が必要です'),
                          content: const SingleChildScrollView(
                            child: Text(
                              'このフォルダのスキャンには「すべてのフォルダをスキャンする」権限の許可が必要です。\n\n'
                              'この権限を許可すると、OSの標準アルバム以外の、あらゆる場所にある画像フォルダをアプリで表示できるようになります。\n\n',
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
                      if (confirm == true) await _requestFullAccessPermission();
                    }
                  },
                ),

              const Divider(),

              ListTile(
                leading: const Icon(Icons.grid_view_outlined),
                title: Text('一覧の列数 (${settings.gridCrossAxisCount})'),
                subtitle: Slider(
                  value: settings.gridCrossAxisCount.toDouble(),
                  min: 1,
                  max: 8,
                  divisions: 7,
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
                    if (newMode != null) settings.setThemeMode(newMode);
                  },
                ),
              ),

              const Divider(),

              ListTile(
                leading: const Icon(Icons.psychology_outlined),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.info_outline),
                          tooltip: '機能の詳細を表示',
                          onPressed: () {
                            showInfoDialog(
                              context,
                              title: 'AIによる画像解析とは',
                              content:
                                  'この機能を有効にすることでアプリはデバイス内で画像の内容を分析し、タグ付けを行うことができます。\n\n'
                                  'これによりキャラ名で画像を検索できたり、ジャンル別でのフィルタリングが可能になります。\n\n'
                                  'この処理はすべてオフラインで完結し、あなたの画像が外部に送信されることはありません。\n\n'
                                  'また、この機能を有効にしても、画像が機械学習に用いられたりすることはありません.',
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              ListTile(
                leading: const Icon(Icons.memory),
                title: const Text('AIモデルを選択'),
                trailing: DropdownButton<String>(
                  value: settings.selectedModelId,
                  // モデルの切替はダウンロード中または解析中は許可しない
                  onChanged: (settings.isDownloading || settings.isAnalyzing)
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

              if (settings.selectedModelId != 'none')
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: settings.isCheckingHash
                      ? const ListTile(
                          leading: CircularProgressIndicator(),
                          title: Text('解析用ファイルが破損していないかチェック中...\n（少し時間がかかります）'),
                        )
                      : settings.isCheckingDownload
                      ? const ListTile(
                          leading: CircularProgressIndicator(),
                          title: Text('モデルファイルを確認中...'),
                        )
                      : settings.isDownloading
                      ? Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: LinearProgressIndicator(
                                          value: settings.downloadProgress,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close),
                                        tooltip: 'ダウンロードを中止',
                                        onPressed: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text('ダウンロードの中止'),
                                              content: const Text(
                                                'ダウンロードを中止しますか？\n（解析用ファイルは削除されます）',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(
                                                    context,
                                                  ).pop(false),
                                                  child: const Text('いいえ'),
                                                ),
                                                TextButton(
                                                  onPressed: () => Navigator.of(
                                                    context,
                                                  ).pop(true),
                                                  child: const Text('はい'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
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
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        )
                      : settings.isModelDownloaded
                      ? Column(
                          children: [
                            if (settings.isModelCorrupted)
                              Card(
                                color: Colors.red.shade50,
                                child: ListTile(
                                  leading: Icon(
                                    Icons.error_outline,
                                    color: Colors.red,
                                    size: 32,
                                  ),
                                  title: Text(
                                    '解析用ファイルが破損しています',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'ファイルが破損しています。\n修復ボタンからモデルの修復をお願いします。\n何度修復を押しても治らない場合、お手数ですが「その他→バグ報告」からご連絡ください。\n（すみません🙇）',
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                  trailing: ElevatedButton.icon(
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('修復'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () async {
                                      await showModalBottomSheet<void>(
                                        context: context,
                                        showDragHandle: true,
                                        builder: (ctx) {
                                          return SafeArea(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ListTile(
                                                  leading: const Icon(
                                                    Icons.cleaning_services,
                                                    color: Colors.red,
                                                  ),
                                                  title: const Text(
                                                    '一から再ダウンロード（推奨）',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  subtitle: const Text(
                                                    '壊れたファイルを削除して最初から取り直します',
                                                  ),
                                                  onTap: () async {
                                                    Navigator.of(ctx).pop();
                                                    await settings
                                                        .downloadModel(
                                                          selectedModel,
                                                          isReset: true,
                                                        );
                                                  },
                                                ),
                                                const Divider(height: 0),
                                                ListTile(
                                                  leading: const Icon(
                                                    Icons.download,
                                                  ),
                                                  title: const Text('途中から再開'),
                                                  subtitle: const Text(
                                                    '前回の続きから再ダウンロードを試みます',
                                                  ),
                                                  onTap: () async {
                                                    Navigator.of(ctx).pop();
                                                    await settings
                                                        .downloadModel(
                                                          selectedModel,
                                                        );
                                                  },
                                                ),
                                                const SizedBox(height: 8),
                                              ],
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            if (!settings.isModelCorrupted)
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
                                      minHeight: 8,
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (settings.currentAnalyzedImageBase64 !=
                                        null)
                                      Container(
                                        width: 80,
                                        height: 80,
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
                                            (() {
                                              final s = settings
                                                  .currentAnalyzedImageBase64!;
                                              final comma = s.indexOf(',');
                                              final payload =
                                                  (s.startsWith('data:') &&
                                                      comma != -1)
                                                  ? s.substring(comma + 1)
                                                  : s;
                                              return base64Decode(payload);
                                            })(),
                                            fit: BoxFit.cover,
                                            gaplessPlayback: true,
                                          ),
                                        ),
                                      ),
                                    Expanded(
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
                      : Column(
                          children: [
                            Text(
                              '解析のために解析用ファイル（${selectedModelDef.displaySize}）をダウンロードする必要があります。',
                            ),
                            const SizedBox(height: 8),
                            settings.isDownloading
                                ? Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: LinearProgressIndicator(
                                              value: settings.downloadProgress,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close),
                                            tooltip: 'ダウンロードを中止',
                                            onPressed: () async {
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
                                      await settings.downloadModel(
                                        selectedModel,
                                      );
                                    },
                                  ),
                          ],
                        ),
                ),

              const Divider(),

              ListTile(
                leading: const Icon(Icons.favorite_border),
                title: const Text('開発者をサポート'),
                subtitle: const Text('（準備中）'),
                onTap: () {},
              ),
            ],
          ),
        );
      },
    );
  }
}
