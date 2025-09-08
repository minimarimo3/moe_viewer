import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../core/models/folder_setting.dart';
import '../../../core/providers/settings_provider.dart';

class FolderSettingsSection extends StatefulWidget {
  const FolderSettingsSection({super.key});

  @override
  State<FolderSettingsSection> createState() => _FolderSettingsSectionState();
}

class _FolderSettingsSectionState extends State<FolderSettingsSection> {
  bool _hasFullAccess = false;

  @override
  void initState() {
    super.initState();
    _checkFullAccessPermission();
  }

  Future<void> _checkFullAccessPermission() async {
    final status = await Permission.manageExternalStorage.status;
    if (!mounted) return;
    setState(() {
      _hasFullAccess = status.isGranted;
    });
  }

  Future<void> _requestFullAccessPermission() async {
    final status = await Permission.manageExternalStorage.request();
    if (!mounted) return;
    setState(() {
      _hasFullAccess = status.isGranted;
    });

    final settings = context.read<SettingsProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _hasFullAccess ? '全ファイルへのアクセスが許可されました！' : '権限が許可されませんでした。',
        ),
        backgroundColor: _hasFullAccess ? Colors.green : Colors.red,
      ),
    );

    if (_hasFullAccess) {
      // 権限が許可された場合、フォルダ統計を再スキャン
      settings.updateFolderStatsAfterPermissionChange();
    }
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
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                        : const Icon(Icons.folder_outlined),
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
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Theme.of(context).colorScheme.primary,
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
                      style: const TextStyle(fontSize: 12),
                    ),
                    // パスはトレーリングの前に薄く表示
                    // 既存のUIに近づけるため、ListTileの下に小さく表示
                    isThreeLine: true,
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
          ],
        );
      },
    );
  }
}
