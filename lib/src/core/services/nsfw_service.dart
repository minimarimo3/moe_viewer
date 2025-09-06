import 'dart:developer';
import 'database_helper.dart';
import '../utils/pixiv_utils.dart';
import '../models/rating.dart';

/// NSFWの判定を予約タグとして管理するサービス
class NsfwService {
  NsfwService._();
  static final instance = NsfwService._();

  /// 現在のタグ一覧を取得（なければ空配列）
  Future<List<String>> _getTags(String path) async {
    final tags = await DatabaseHelper.instance.getTagsForPath(path);
    return tags ?? <String>[];
  }

  /// NSFWかどうかを特殊タグから判定
  Future<bool?> getNsfwRatingFromTags(String path) async {
    final tags = await _getTags(path);
    return ReservedTags.getNsfwRating(tags);
  }

  /// レーティングを特殊タグから判定
  Future<Rating> getRatingFromTags(String path) async {
    final tags = await _getTags(path);
    final nsfwRating = ReservedTags.getNsfwRating(tags);
    if (nsfwRating == true) return Rating.nsfw;
    if (nsfwRating == false) return Rating.sfw;
    return Rating.unclassified;
  }

  /// NSFWの判定を特殊タグとして設定（AI判定の場合）
  Future<void> setAiNsfwRatingAsTags(String path, bool isNsfw) async {
    // 既存のNSFW判定データベースに手動設定があるかチェック
    final existingRating = await DatabaseHelper.instance.getNsfwRating(path);
    if (existingRating != null && existingRating['isManual'] == true) {
      // 手動設定がある場合は何もしない
      return;
    }

    // タグベースでNSFW判定を設定
    final currentTags = await _getTags(path);
    final updatedTags = ReservedTags.setNsfwRating(currentTags, isNsfw);
    await DatabaseHelper.instance.insertOrUpdateTag(path, updatedTags);

    // 既存のNSFWデータベースも更新（UI表示用）
    await DatabaseHelper.instance.setAiNsfwRating(path, isNsfw);
  }

  /// NSFWの判定を特殊タグとして設定（手動設定の場合）
  Future<void> setManualNsfwRatingAsTags(String path, bool isNsfw) async {
    // タグベースでNSFW判定を設定
    final currentTags = await _getTags(path);
    final updatedTags = ReservedTags.setNsfwRating(currentTags, isNsfw);
    await DatabaseHelper.instance.insertOrUpdateTag(path, updatedTags);

    // 既存のNSFWデータベースも更新（UI表示用）
    await DatabaseHelper.instance.setNsfwRating(path, isNsfw);
  }

  /// 既存のNSFW判定データベースからタグへの移行
  Future<void> migrateExistingNsfwRatings() async {
    final db = DatabaseHelper.instance;

    // 既存のNSFW判定データを取得
    final dbInstance = await db.database;
    final ratings = await dbInstance.query('nsfw_ratings');

    int migratedCount = 0;
    for (final row in ratings) {
      final path = row['path'] as String;
      final isNsfw = (row['is_nsfw'] as int) == 1;

      // 既存のタグに特殊タグが既に含まれているかチェック
      final currentTags = await _getTags(path);
      final hasNsfwTag = ReservedTags.getNsfwRating(currentTags) != null;

      if (!hasNsfwTag) {
        // 特殊タグがない場合のみ追加
        final updatedTags = ReservedTags.setNsfwRating(currentTags, isNsfw);
        await db.insertOrUpdateTag(path, updatedTags);
        migratedCount++;
      }
    }

    log('NSFW判定データ移行完了: $migratedCount 件のファイルに特殊タグを追加');
  }

  /// タグからNSFW判定を削除
  Future<void> clearNsfwRatingFromTags(String path) async {
    final currentTags = await _getTags(path);
    final updatedTags = List<String>.from(currentTags);
    updatedTags.removeWhere(
      (tag) => tag == ReservedTags.nsfw || tag == ReservedTags.sfw,
    );
    await DatabaseHelper.instance.insertOrUpdateTag(path, updatedTags);
  }
}
