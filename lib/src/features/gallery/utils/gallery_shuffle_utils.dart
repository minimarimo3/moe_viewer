import 'dart:io';
import 'package:flutter/material.dart';

class GalleryShuffleUtils {
  static Future<bool?> showShuffleConfirmationDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('表示順のシャッフル'),
        content: const Text('画像一覧の表示順をランダムにしますか？\n（現在のスクロール位置はリセットされます）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('いいえ'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('はい'),
          ),
        ],
      ),
    );
  }

  static ShuffleResult shuffleItems({
    required List<dynamic> displayItems,
    required List<File> imageFilesForDetail,
  }) {
    final originalDisplayItems = List.from(displayItems);
    final originalDetailFiles = List.from(imageFilesForDetail);

    final indexList = List.generate(originalDisplayItems.length, (i) => i);
    indexList.shuffle();

    final shuffledDisplayItems = indexList.map((i) => originalDisplayItems[i]).toList();
    final shuffledDetailFiles = indexList
        .map((i) => originalDetailFiles[i])
        .cast<File>()
        .toList();

    return ShuffleResult(
      displayItems: shuffledDisplayItems,
      detailFiles: shuffledDetailFiles,
    );
  }
}

class ShuffleResult {
  final List<dynamic> displayItems;
  final List<File> detailFiles;

  ShuffleResult({
    required this.displayItems,
    required this.detailFiles,
  });
}
