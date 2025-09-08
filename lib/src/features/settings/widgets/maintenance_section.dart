import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common_widgets/dialogs.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/duplicate_service.dart';
import '../../../core/utils/search_navigator.dart';
import '../../../core/utils/pixiv_utils.dart';

class MaintenanceSection extends StatelessWidget {
  const MaintenanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('メンテナンス', style: TextStyle(fontWeight: FontWeight.bold)),
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
            // ignore: use_build_context_synchronously
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
                                    onPressed: () => Navigator.of(c).pop(false),
                                    child: const Text('キャンセル'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(c).pop(true),
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
      ],
    );
  }
}
