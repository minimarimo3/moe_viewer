import 'package:flutter/material.dart';

import '../../features/gallery/gallery_screen.dart';

/// アプリ共通で「指定ワードの検索結果をギャラリーで開く」ためのユーティリティ。
/// 今後、設定画面など他の場所からも再利用できるように切り出し。
class SearchNavigator {
  /// 指定された検索クエリでギャラリー画面を開き、結果表示まで行う。
  ///
  /// 既存スタックにギャラリーがある場合の特殊最適化は現状せず、
  /// 新規にプッシュする実装とする（必要になれば最適化可能）。
  static Future<void> openSearchResults(
    BuildContext context, {
    required String query,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MyHomePage(
          title: 'Moe Viewer Home Page',
          initialSearchQuery: trimmed,
        ),
      ),
    );
  }
}
