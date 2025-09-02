/// Pixiv関連のユーティリティ
class PixivUtils {
  /// ファイルパス（末尾のファイル名想定）から illust_(\d+)_ を抽出
  static String? extractPixivId(String path) {
    final fileName = path.split('/').last;
    final regExp = RegExp(r'illust_(\d+)_');
    final match = regExp.firstMatch(fileName);
    return match?.group(1);
  }
}

/// 予約タグ定義（後で増やせるように一箇所に集約）
class ReservedTags {
  static const String favorite = '__favorite__';
  // 将来: '__hidden__', '__archived__' などを追加予定

  /// タグリストにお気に入りフラグを付与/除去
  static List<String> toggleFavorite(List<String> tags, bool set) {
    final t = List<String>.from(tags);
    final has = t.contains(favorite);
    if (set && !has) t.add(favorite);
    if (!set && has) t.removeWhere((e) => e == favorite);
    return t;
  }
}
