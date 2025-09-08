import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/providers/settings_provider.dart';
import '../../common_widgets/dialogs.dart';
import '../../common_widgets/auto_scroll_interval_selector.dart';
import '../../core/services/ai_service.dart';
import '../../core/services/duplicate_service.dart';
import '../../core/utils/pixiv_utils.dart';
import '../../core/utils/search_navigator.dart';
import '../../core/models/ai_model_definition.dart';
import '../../core/models/folder_setting.dart';
import '../../core/models/rating.dart';
import 'licenses_screen.dart';

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

    _checkFullAccessPermission();
  }

  @override
  void dispose() {
    super.dispose();
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

  Future<bool> _hasNomediaFile(String directoryPath) async {
    try {
      final directory = Directory(directoryPath);
      if (!await directory.exists()) {
        return false;
      }

      final nomediaFile = File('$directoryPath/.nomedia');
      return await nomediaFile.exists();
    } catch (e) {
      return false;
    }
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
      final settings = context.read<SettingsProvider>();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _hasFullAccess ? '全ファイルへのアクセスが許可されました！' : '権限が許可されませんでした。',
          ),
          backgroundColor: _hasFullAccess ? Colors.green : Colors.red,
        ),
      );

      // 権限が許可された場合、フォルダ統計を再スキャン
      if (_hasFullAccess) {
        settings.updateFolderStatsAfterPermissionChange();
      }
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
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  '表示対象のフォルダ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

              for (FolderSetting folder in settings.folderSettings)
                FutureBuilder<bool>(
                  future: _hasNomediaFile(folder.path),
                  builder: (context, nomediaSnapshot) {
                    final hasNomedia = nomediaSnapshot.data ?? false;
                    final isRestricted = _isRestrictedPath(folder.path);
                    final needsPermission =
                        (isRestricted || hasNomedia) && !_hasFullAccess;

                    String tooltipMessage;
                    String dialogContent;
                    if (hasNomedia) {
                      tooltipMessage =
                          'このフォルダには.nomediaファイルがあります。「すべてのフォルダをスキャンする」権限の許可が必要です。';
                      dialogContent =
                          'このフォルダには.nomediaファイルがあり、システムから隠されています。\n\n'
                          'このフォルダのスキャンには「すべてのフォルダをスキャンする」権限の許可が必要です。\n\n'
                          'この権限を許可すると、OSの標準アルバム以外の、あらゆる場所にある画像フォルダをアプリで表示できるようになります。';
                    } else {
                      tooltipMessage =
                          'このフォルダのスキャンには「すべてのフォルダをスキャンする」権限の許可が必要です。';
                      dialogContent =
                          'このフォルダのスキャンには「すべてのフォルダをスキャンする」権限の許可が必要です。\n\n'
                          'この権限を許可すると、OSの標準アルバム以外の、あらゆる場所にある画像フォルダをアプリで表示できるようになります。';
                    }

                    return ListTile(
                      leading: needsPermission
                          ? Tooltip(
                              message: tooltipMessage,
                              child: Icon(
                                hasNomedia
                                    ? Icons.visibility_off
                                    : Icons.warning_amber_rounded,
                                color: hasNomedia ? Colors.red : Colors.orange,
                              ),
                            )
                          : Icon(Icons.folder_outlined),
                      title: Builder(
                        builder: (context) {
                          final stats = settings.getFolderStat(folder.path);
                          final totalFiles = stats['totalFiles'] ?? 0;
                          final taggedFiles = stats['taggedFiles'] ?? 0;
                          final isUpdating = settings.isUpdatingStats;

                          final folderName = folder.path.split('/').last;
                          final titleColor = needsPermission
                              ? Theme.of(context).disabledColor
                              : null;

                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  folderName,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: titleColor),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (isUpdating && totalFiles == 0)
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'スキャン中...',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.color,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(
                                  '（ファイル数: $totalFiles  |  タグ付け済み: $taggedFiles）',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.color,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      subtitle: Text(
                        folder.path,
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (folder.isDeletable)
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: const Text('フォルダの削除'),
                                      content: Text(
                                        '「${folder.path}」の表示を解除しますか？\n（フォルダ内の画像ファイルは削除されません）',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(),
                                          child: const Text('キャンセル'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                            settings.removeFolder(folder.path);
                                          },
                                          child: const Text('解除する'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),

                          Checkbox(
                            value: folder.isEnabled,
                            onChanged: (bool? value) {
                              if (value != null) {
                                settings.toggleFolderEnabled(folder.path);
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () async {
                        if (needsPermission) {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('追加の権限が必要です'),
                              content: SingleChildScrollView(
                                child: Text(dialogContent),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('キャンセル'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
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
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('表示するフォルダを追加する'),
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
                  'メンテナンス',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

              ListTile(
                leading: const Icon(Icons.copy_all_outlined),
                title: const Text('重複画像をチェック'),
                subtitle: const Text('XXH3ハッシュで同一画像を検出します'),
                onTap: () async {
                  final duplicateService = context.read<DuplicateService>();
                  bool canceled = false;
                  final scannedVN = ValueNotifier<int>(0);
                  final dupVN = ValueNotifier<int>(0);

                  // 進捗ダイアログ
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) {
                      return AlertDialog(
                        title: const Text('重複チェック中...'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const LinearProgressIndicator(),
                            const SizedBox(height: 12),
                            ValueListenableBuilder<int>(
                              valueListenable: scannedVN,
                              builder: (_, v, __) => Text('スキャン済み: $v'),
                            ),
                            ValueListenableBuilder<int>(
                              valueListenable: dupVN,
                              builder: (_, v, __) => Text('重複候補ファイル数: $v'),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              canceled = true;
                            },
                            child: const Text('中止'),
                          ),
                        ],
                      );
                    },
                  );

                  final groups = await duplicateService.findDuplicates(
                    settings.folderSettings,
                    onProgress: (scanned, dup) {
                      scannedVN.value = scanned;
                      dupVN.value = dup;
                    },
                    shouldCancel: () => canceled,
                  );

                  if (context.mounted) Navigator.of(context).pop(); // 進捗を閉じる

                  if (!context.mounted) return;
                  if (groups.isEmpty) {
                    showInfoDialog(
                      context,
                      title: '重複なし',
                      content: '重複画像は見つかりませんでした。',
                    );
                  } else {
                    final totalGroups = groups.length;
                    final totalFiles = groups.values.fold<int>(
                      0,
                      (p, e) => p + e.length,
                    );

                    // __duplicate__ タグを付与
                    await duplicateService.tagDuplicates(groups);

                    if (!context.mounted) return;
                    // 選択肢を提示
                    // ignore: use_build_context_synchronously
                    showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (ctx) {
                        return SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.search),
                                title: const Text('重複ファイルを確認する'),
                                subtitle: Text(
                                  '重複グループ: $totalGroups / ファイル: $totalFiles',
                                ),
                                onTap: () async {
                                  Navigator.of(ctx).pop();
                                  await SearchNavigator.openSearchResults(
                                    context,
                                    query: ReservedTags.duplicate,
                                  );
                                },
                              ),
                              const Divider(height: 0),
                              ListTile(
                                leading: const Icon(
                                  Icons.delete_forever,
                                  color: Colors.red,
                                ),
                                title: const Text(
                                  '削除する',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: const Text('各グループで1つだけ残し、他を削除します'),
                                onTap: () async {
                                  Navigator.of(ctx).pop();
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('重複ファイルの削除'),
                                      content: Text(
                                        '重複グループ: $totalGroups\n対象ファイル: $totalFiles\n\n各グループで1つを残し、他を削除します。よろしいですか？',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(c).pop(false),
                                          child: const Text('キャンセル'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(c).pop(true),
                                          child: const Text('削除する'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm != true) return;

                                  final deleted = await duplicateService
                                      .deleteDuplicates(groups);
                                  if (!context.mounted) return;
                                  showInfoDialog(
                                    context,
                                    title: '削除完了',
                                    content: '削除したファイル数: ${deleted.length}',
                                  );
                                  // 統計を更新
                                  if (deleted.isNotEmpty) {
                                    settings.updateFolderStats();
                                  }
                                },
                              ),
                              const Divider(height: 0),
                              ListTile(
                                leading: const Icon(Icons.close),
                                title: const Text('キャンセル'),
                                onTap: () => Navigator.of(ctx).pop(),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        );
                      },
                    );
                  }
                },
              ),

              const Divider(),
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  '表示設定',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                subtitle: AutoScrollIntervalSelector(
                  currentValue: settings.autoScrollInterval,
                  onChanged: (value) {
                    settings.setAutoScrollInterval(value);
                  },
                ),
              ),

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

              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('表示するレーティング'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Wrap(
                    spacing: 8.0,
                    children: Rating.values.map((rating) {
                      final isVisible = settings.visibleRatings[rating] ?? true;
                      return FilterChip(
                        label: Text(rating.displayName),
                        selected: isVisible,
                        onSelected: (bool selected) {
                          settings.setRatingVisibility(rating, selected);
                        },
                        selectedColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        checkmarkColor: Theme.of(
                          context,
                        ).colorScheme.onPrimaryContainer,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        labelStyle: TextStyle(
                          color: isVisible
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: isVisible
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

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
                                    final aiService = context.read<AiService>();
                                    if (settings.isAnalyzing) {
                                      settings.stopAiAnalysis(aiService);
                                    } else {
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
