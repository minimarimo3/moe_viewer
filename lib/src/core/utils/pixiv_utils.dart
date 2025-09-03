/// Pixiv関連のユーティリティ
class PixivUtils {
  /// ファイル名からPixivのイラストIDを推定して抽出する。
  /// - illust_（イラストID）_（ダウンロードした日）_（ダウンロード時間）.jpg
  /// マッチした最初のパターンの数字を返す。該当なしはnull。
  static String? extractPixivId(String path) {
    final fileName = path.split('/').last;
    final patterns = <RegExp>[RegExp(r'illust_(\d+)[^\d]')];

    for (final re in patterns) {
      final m = re.firstMatch(fileName);
      if (m != null) {
        // 最後のキャプチャグループから数字を取り出す
        for (var i = m.groupCount; i >= 1; i--) {
          final g = m.group(i);
          if (g != null && RegExp(r'^\d+$').hasMatch(g)) {
            return g;
          }
        }
      }
    }
    return null;
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
