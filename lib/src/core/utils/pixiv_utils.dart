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

  // --- 検索エイリアス定義とユーティリティ ---
  /// 予約タグ（正規）に対する自然言語エイリアス
  /// 例: '__favorite__' <- ['お気に入り', '好き']
  static const Map<String, List<String>> aliases = {
    favorite: ['お気に入り', '好き'],
  };

  /// エイリアスから正規タグを引くための逆引きマップ（小文字化したキーで一致）
  static final Map<String, String> _aliasToCanonical = {
    // 正規名自身も自分にマップしておく（大小区別なし）
    favorite.toLowerCase(): favorite,
    for (final entry in aliases.entries)
      for (final a in entry.value) a.toLowerCase(): entry.key,
  };

  /// 単一トークンを正規化（エイリアスを正規タグに変換、未登録はそのまま小文字化）
  static String normalizeToken(String token) {
    final k = token.trim().toLowerCase();
    if (k.isEmpty) return k;
    return _aliasToCanonical[k] ?? k;
  }

  /// トークン配列を正規化
  static List<String> normalizeTokens(Iterable<String> tokens) {
    return tokens.map(normalizeToken).where((t) => t.isNotEmpty).toList();
  }

  /// 入力中の最後のトークンに対して、エイリアス候補を返す
  static List<String> suggestAliasTerms(String inputLastToken) {
    final q = inputLastToken.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final terms = <String>{};
    for (final list in aliases.values) {
      for (final a in list) {
        if (a.toLowerCase().contains(q)) terms.add(a);
      }
    }
    return terms.take(20).toList();
  }
}
