import 'dart:io';
import 'package:flutter/material.dart';

enum ShuffleAction { cancel, reset, shuffle }

class GalleryShuffleUtils {
  static Future<ShuffleAction?> showShuffleOptionsDialog(
    BuildContext context,
    bool hasShuffleState,
  ) async {
    return await showDialog<ShuffleAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('表示順の変更'),
        content: hasShuffleState
            ? const Text('現在の表示順をどのように変更しますか？')
            : const Text('画像一覧の表示順をランダムにしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(ShuffleAction.cancel),
            child: const Text('キャンセル'),
          ),
          if (hasShuffleState)
            TextButton(
              onPressed: () => Navigator.of(context).pop(ShuffleAction.reset),
              child: const Text('最初の状態に戻す'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(ShuffleAction.shuffle),
            child: const Text('ランダム'),
          ),
        ],
      ),
    );
  }

  // 後方互換性のため残しておく
  static Future<bool?> showShuffleConfirmationDialog(
    BuildContext context,
  ) async {
    final action = await showShuffleOptionsDialog(context, false);
    return action == ShuffleAction.shuffle;
  }

  static ShuffleResult shuffleItems({
    required List<dynamic> displayItems,
    required List<File> imageFilesForDetail,
  }) {
    final originalDisplayItems = List.from(displayItems);
    final originalDetailFiles = List.from(imageFilesForDetail);

    final indexList = List.generate(originalDisplayItems.length, (i) => i);
    indexList.shuffle();

    final shuffledDisplayItems = indexList
        .map((i) => originalDisplayItems[i])
        .toList();
    final shuffledDetailFiles = indexList
        .map((i) => originalDetailFiles[i])
        .cast<File>()
        .toList();

    return ShuffleResult(
      displayItems: shuffledDisplayItems,
      detailFiles: shuffledDetailFiles,
      shuffleOrder: indexList,
    );
  }

  static ShuffleResult applyShuffleOrder({
    required List<dynamic> displayItems,
    required List<File> imageFilesForDetail,
    required List<int> shuffleOrder,
  }) {
    // シャッフル順序が適用可能かチェック
    if (shuffleOrder.length != displayItems.length) {
      // サイズが合わない場合は元のままを返す
      return ShuffleResult(
        displayItems: displayItems,
        detailFiles: imageFilesForDetail,
        shuffleOrder: List.generate(displayItems.length, (i) => i),
      );
    }

    final originalDisplayItems = List.from(displayItems);
    final originalDetailFiles = List.from(imageFilesForDetail);

    final shuffledDisplayItems = shuffleOrder
        .map((i) => originalDisplayItems[i])
        .toList();
    final shuffledDetailFiles = shuffleOrder
        .map((i) => originalDetailFiles[i])
        .cast<File>()
        .toList();

    return ShuffleResult(
      displayItems: shuffledDisplayItems,
      detailFiles: shuffledDetailFiles,
      shuffleOrder: shuffleOrder,
    );
  }
}

class ShuffleResult {
  final List<dynamic> displayItems;
  final List<File> detailFiles;
  final List<int> shuffleOrder;

  ShuffleResult({
    required this.displayItems,
    required this.detailFiles,
    required this.shuffleOrder,
  });
}
