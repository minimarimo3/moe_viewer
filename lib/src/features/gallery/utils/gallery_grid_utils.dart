import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../detail/detail_screen.dart';
import '../../../core/utils/shared_preferences_helper.dart';

/// Gallery Grid Widget共通のユーティリティ
class GalleryGridUtils {
  /// 行数を計算
  static int calculateRowCount(int itemCount, int crossAxisCount) {
    return (itemCount / crossAxisCount).ceil();
  }

  /// アイテムの幅を計算
  static double calculateItemWidth(double screenWidth, int crossAxisCount) {
    return (screenWidth - 4.0 * (crossAxisCount - 1)) / crossAxisCount;
  }

  /// サムネイルサイズを計算（DPRを考慮）
  static int calculateThumbnailSize(double itemWidth, double devicePixelRatio) {
    return (itemWidth * devicePixelRatio).round();
  }

  /// アイテムの高さを計算（正方形基準）
  static double calculateItemHeight(double itemWidth) {
    return itemWidth;
  }

  /// アイテムタップ処理の共通ロジック
  static Future<void> handleItemTap(
    BuildContext context,
    int index,
    dynamic item,
    List<File> imageFilesForDetail,
    void Function(int index, dynamic item)? onItemTap,
    VoidCallback? onEnterDetail,
  ) async {
    if (onItemTap != null) {
      onItemTap(index, item);
      return;
    }

    onEnterDetail?.call();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailScreen(
          imageFileList: imageFilesForDetail,
          initialIndex: index,
        ),
      ),
    );

    // Detail画面から戻った際の状態を保存
    final prefs = await SharedPreferencesHelper.instance;
    await prefs.setBool('wasOnDetailScreen', false);
  }

  /// アイテムの種類判定
  static bool isPhotoManagerAsset(dynamic item) {
    return item is AssetEntity;
  }

  /// アイテムの種類判定
  static bool isFile(dynamic item) {
    return item is File;
  }
}
