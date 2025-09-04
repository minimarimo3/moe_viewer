import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/providers/ui_settings_provider.dart';
import '../../core/providers/folder_settings_provider.dart';
import '../../core/providers/model_provider.dart';
import '../../core/providers/analysis_provider.dart';
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

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final model = context.read<ModelProvider>();
      final aiService = context.read<AiService>();
      final analysis = context.read<AnalysisProvider>();
      final folders = context.read<FolderSettingsProvider>();
      final selectedModelDef = availableModels.firstWhere(
        (m) => m.id == model.selectedModelId,
        orElse: () => availableModels.first,
      );
      await aiService.switchModel(selectedModelDef);
      await model.checkModelStatus(selectedModelDef);
      // 解析対象総数の更新
      await analysis.updateOverallProgress(folders.folders);
    });

    _checkFullAccessPermission();
  }

  // 権限制御: 一般的な公開ディレクトリ以外なら制限ありとみなす
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
    if (!mounted) return;
    setState(() => _hasFullAccess = status.isGranted);
  }

  Future<void> _requestFullAccessPermission() async {
    final status = await Permission.manageExternalStorage.request();
    if (!mounted) return;
    setState(() => _hasFullAccess = status.isGranted);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _hasFullAccess ? '全ファイルへのアクセスが許可されました！' : '権限が許可されませんでした。',
        ),
        backgroundColor: _hasFullAccess ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer4<
      UiSettingsProvider,
      FolderSettingsProvider,
      ModelProvider,
      AnalysisProvider
    >(
      builder: (context, ui, folders, model, analysis, child) {
        // ダウンロード失敗を一度だけ通知
        if (model.downloadErrorMessage != null &&
            model.downloadErrorVersion != _shownDownloadErrorVersion) {
          _shownDownloadErrorVersion = model.downloadErrorVersion;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(model.downloadErrorMessage!),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          });
        }

        final selectedModel = availableModels.firstWhere(
          (m) => m.id == model.selectedModelId,
          orElse: () => availableModels.first,
        );
        final selectedModelDef = selectedModel;

        return Scaffold(
          appBar: AppBar(title: const Text('設定')),
          body: ListView(
            children: [
              // フォルダ追加
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('表示するフォルダを選択'),
                onTap: () async {
                  final result = await FilePicker.platform.getDirectoryPath();
                  if (result != null) folders.addFolder(result);
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
              for (final FolderSetting folder in folders.folders)
                ListTile(
                  leading: (_isRestrictedPath(folder.path) && !_hasFullAccess)
                      ? Tooltip(
                          message: 'このフォルダのスキャンには「すべてのフォルダをスキャンする」権限の許可が必要です。',
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                          ),
                        )
                      : const Icon(Icons.folder_outlined),
                  title: Text(
                    folder.path.split('/').last,
                    style: TextStyle(
                      color: (_isRestrictedPath(folder.path) && !_hasFullAccess)
                          ? Theme.of(context).disabledColor
                          : null,
                    ),
                  ),
                  subtitle: Text(
                    folder.path,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: folder.isEnabled,
                        onChanged: (v) {
                          if (v != null)
                            folders.toggleFolderEnabled(folder.path);
                        },
                      ),
                      if (folder.isDeletable)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => folders.removeFolder(folder.path),
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
                      if (confirm == true) {
                        await _requestFullAccessPermission();
                      }
                    }
                  },
                ),

              const Divider(),

              // グリッド列数
              ListTile(
                leading: const Icon(Icons.grid_view_outlined),
                title: Text('一覧の列数 (${ui.gridCrossAxisCount})'),
                subtitle: Slider(
                  value: ui.gridCrossAxisCount.toDouble(),
                  min: 1,
                  max: 8,
                  divisions: 7,
                  label: ui.gridCrossAxisCount.toString(),
                  onChanged: (v) => ui.setGridCrossAxisCount(v.toInt()),
                ),
              ),

              const Divider(),

              // テーマ
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: const Text('アプリのテーマ'),
                trailing: DropdownButton<ThemeMode>(
                  value: ui.themeMode,
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
                  onChanged: (mode) {
                    if (mode != null) ui.setThemeMode(mode);
                  },
                ),
              ),

              const Divider(),

              // AI 情報とモデル選択
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
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      tooltip: '機能の詳細を表示',
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
              ),
              ListTile(
                leading: const Icon(Icons.memory),
                title: const Text('AIモデルを選択'),
                trailing: DropdownButton<String>(
                  value: model.selectedModelId,
                  onChanged: model.isDownloading
                      ? null
                      : (String? newModelId) async {
                          if (newModelId == null) return;
                          await model.setSelectedModel(newModelId);
                          final def = availableModels.firstWhere(
                            (m) => m.id == newModelId,
                          );
                          await model.checkModelStatus(def);
                        },
                  items: [
                    for (final def in availableModels)
                      DropdownMenuItem<String>(
                        value: def.id,
                        child: Text(def.displayName),
                      ),
                  ],
                ),
              ),

              if (model.selectedModelId != 'none')
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: model.isCheckingHash
                      ? const ListTile(
                          leading: CircularProgressIndicator(),
                          title: Text('モデルの整合性をチェック中...'),
                        )
                      : model.isModelDownloaded
                      ? Column(
                          children: [
                            if (model.isModelCorrupted)
                              ListTile(
                                leading: const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.red,
                                ),
                                title: const Text('モデルファイルが破損しています'),
                                trailing: ElevatedButton(
                                  onPressed: () async {
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
                                      await model.downloadModel(selectedModel);
                                    }
                                  },
                                  child: const Text('修復'),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '解析インデックス達成度 (解析済み：${analysis.analyzedFileCount})',
                                  ),
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                    value: analysis.totalFileCount > 0
                                        ? analysis.analyzedFileCount /
                                              analysis.totalFileCount
                                        : 0,
                                    minHeight: 8,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              ),
                            ),
                            if (!model.isModelCorrupted)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                ),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: analysis.isAnalyzing
                                        ? Colors.red
                                        : null,
                                  ),
                                  onPressed: () {
                                    if (analysis.isAnalyzing) {
                                      analysis.stopAiAnalysis();
                                    } else {
                                      final aiService = context
                                          .read<AiService>();
                                      analysis.startAiAnalysis(
                                        aiService: aiService,
                                        folders: folders.folders,
                                        model: selectedModel,
                                      );
                                    }
                                  },
                                  child: Text(
                                    analysis.isAnalyzing ? '解析を停止' : '解析を開始',
                                  ),
                                ),
                              ),
                            if (analysis.isAnalyzing &&
                                analysis.currentAnalyzingFile.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  0,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (analysis.currentAnalyzedImageBase64 !=
                                        null)
                                      Container(
                                        width: 80,
                                        height: 80,
                                        margin: const EdgeInsets.only(right: 8),
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
                                          child: Builder(
                                            builder: (context) {
                                              final s = analysis
                                                  .currentAnalyzedImageBase64!;
                                              final comma = s.indexOf(',');
                                              final payload =
                                                  (s.startsWith('data:') &&
                                                      comma != -1)
                                                  ? s.substring(comma + 1)
                                                  : s;
                                              final bytes = base64Decode(
                                                payload,
                                              );
                                              return Image.memory(
                                                bytes,
                                                fit: BoxFit.cover,
                                                gaplessPlayback: true,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'ファイル: ${analysis.currentAnalyzingFile}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (analysis.lastFoundTags.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: [
                                                  for (final tag
                                                      in analysis.lastFoundTags)
                                                    Chip(
                                                      label: Text(tag),
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      padding:
                                                          const EdgeInsets.all(
                                                            2,
                                                          ),
                                                      labelStyle:
                                                          const TextStyle(
                                                            fontSize: 11,
                                                          ),
                                                    ),
                                                ],
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
                            model.isDownloading
                                ? Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: LinearProgressIndicator(
                                              value: model.downloadProgress,
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
                                                log(
                                                  'ユーザーがダウンロード中止を確認しました。キャンセル処理を実行します。',
                                                );
                                                model.cancelDownload();
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${(model.downloadProgress * 100).toStringAsFixed(1)}%',
                                      ),
                                    ],
                                  )
                                : ElevatedButton.icon(
                                    icon: const Icon(Icons.download),
                                    label: const Text('解析用ファイルをダウンロード'),
                                    onPressed: () async {
                                      await model.downloadModel(selectedModel);
                                    },
                                  ),
                          ],
                        ),
                ),

              const Divider(),

              // 寄付・サポート
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
