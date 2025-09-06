import '../services/database_helper.dart';

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

  /// データベースの別名機能を使用してタグを表示用に変換
  static Future<String> getDisplayName(String tag) async {
    return await DatabaseHelper.instance.getDisplayTagName(tag);
  }

  /// 複数のタグを表示用に変換
  static Future<List<String>> getDisplayNames(List<String> tags) async {
    return await DatabaseHelper.instance.getDisplayTagNames(tags);
  }

  /// 検索クエリから実際のタグ名を取得（別名も考慮）
  static Future<List<String>> searchTags(String query) async {
    return await DatabaseHelper.instance.searchTagsByDisplayName(query);
  }

  /// 初期化時に既存の「お気に入り」別名をデータベースに登録
  static Future<void> initializeDefaultAliases() async {
    final db = DatabaseHelper.instance;

    // 既存の別名が登録されているかチェック
    final existingAlias = await db.getTagAlias(favorite);
    if (existingAlias == null) {
      // 「お気に入り」タグの別名を設定
      await db.setTagAlias(favorite, 'お気に入り');
    }
  }

  /// レガシー機能：後方互換性のため残すが、新しい仕組みに移行
  static String normalizeToken(String token) {
    final k = token.trim().toLowerCase();
    if (k.isEmpty) return k;

    // 「お気に入り」エイリアス対応
    if (k == 'お気に入り') {
      return favorite;
    }

    return k;
  }

  /// レガシー機能：後方互換性のため残すが、新しい仕組みに移行
  static List<String> normalizeTokens(Iterable<String> tokens) {
    return tokens.map(normalizeToken).where((t) => t.isNotEmpty).toList();
  }

  /// レガシー機能：後方互換性のため残すが、新しい仕組みに移行
  static List<String> suggestAliasTerms(String inputLastToken) {
    final q = inputLastToken.trim().toLowerCase();
    if (q.isEmpty) return const [];

    // 「お気に入り」のサジェスト
    const aliases = ['お気に入り'];
    return aliases.where((a) => a.toLowerCase().contains(q)).toList();
  }
}
