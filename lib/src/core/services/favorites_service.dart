import 'database_helper.dart';
import '../utils/pixiv_utils.dart';

/// お気に入りを予約タグとして image_tags に保存/読込するサービス
class FavoritesService {
  FavoritesService._();
  static final instance = FavoritesService._();

  /// 現在のタグ一覧を取得（なければ空配列）
  Future<List<String>> _getTags(String path) async {
    final tags = await DatabaseHelper.instance.getTagsForPath(path);
    return tags ?? <String>[];
  }

  /// お気に入りかどうか
  Future<bool> isFavorite(String path) async {
    final tags = await _getTags(path);
    return tags.contains(ReservedTags.favorite);
  }

  /// お気に入りトグル（真偽を返す: 変更後の状態）
  Future<bool> toggleFavorite(String path) async {
    final before = await _getTags(path);
    final isFav = before.contains(ReservedTags.favorite);
    final after = ReservedTags.toggleFavorite(before, !isFav);
    await DatabaseHelper.instance.insertOrUpdateTag(path, after);
    return !isFav;
  }
}

// メモ:
// 将来、予約タグを増やす場合は ReservedTags にタグ名と操作関数を追加し、
// ここに専用メソッド（toggleHidden など）を追加すると見通し良く拡張できます。
