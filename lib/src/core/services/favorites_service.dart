import 'dart:io';
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

  /// お気に入りのファイルパス一覧を取得
  Future<List<String>> listFavoritePaths() async {
    final paths = await DatabaseHelper.instance.searchByTags(<String>[
      ReservedTags.favorite,
    ]);
    // 実在しないファイルは除外
    return paths.where((p) => File(p).existsSync()).toList();
  }

  /// お気に入りのファイル一覧を取得
  /// sortMode: name_asc/name_desc（それ以外はname_asc扱い）
  Future<List<File>> listFavoriteFiles({String sortMode = 'name_asc'}) async {
    final paths = await listFavoritePaths();
    final files = paths.map((p) => File(p)).toList();
    switch (sortMode) {
      case 'name_desc':
        files.sort(
          (a, b) => b.path.toLowerCase().compareTo(a.path.toLowerCase()),
        );
        break;
      case 'name_asc':
      default:
        files.sort(
          (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
        );
        break;
    }
    return files;
  }
}

// メモ:
// 将来、予約タグを増やす場合は ReservedTags にタグ名と操作関数を追加し、
// ここに専用メソッド（toggleHidden など）を追加すると見通し良く拡張できます。
