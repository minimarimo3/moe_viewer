import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/ai_model_definition.dart';

/// タグのカテゴリ（character/yearなど）を扱うユーティリティ
class TagCategoryUtils {
  static Map<String, String>?
  _tagToCategoryLower; // key: tag(lower), value: category(lower)
  static bool _loaded = false;

  /// ラベルJSON（metadata）から tag_to_category を読み込む
  static Future<void> ensureLoaded() async {
    if (_loaded && _tagToCategoryLower != null) return;

    final dir = await getApplicationSupportDirectory();

    // 候補のラベルファイルを順に探す（存在する最初のものを採用）
    final candidates = <String>[
      for (final m in availableModels)
        if (m.labelFileName.isNotEmpty) '${dir.path}/${m.labelFileName}',
    ];

    String? labelPath;
    for (final p in candidates) {
      if (await File(p).exists()) {
        labelPath = p;
        break;
      }
    }

    // 見つからなければ空で継続
    if (labelPath == null) {
      _tagToCategoryLower = {};
      _loaded = true;
      return;
    }

    try {
      final raw = await File(labelPath).readAsString();
      final j = json.decode(raw) as Map<String, dynamic>;
      final map = j['dataset_info']?['tag_mapping']?['tag_to_category'];
      if (map is Map) {
        _tagToCategoryLower = map.map(
          (k, v) =>
              MapEntry(k.toString().toLowerCase(), v.toString().toLowerCase()),
        );
      } else {
        _tagToCategoryLower = {};
      }
    } catch (_) {
      _tagToCategoryLower = {};
    } finally {
      _loaded = true;
    }
  }

  static bool isCharacter(String tag) {
    final t = tag.toLowerCase();
    final cat = _tagToCategoryLower?[t];
    return cat == 'character';
  }

  static bool isYear(String tag) {
    final t = tag.toLowerCase();
    final cat = _tagToCategoryLower?[t];
    if (cat == 'year') return true;
    // フォールバック: 4桁の西暦（1900-2099）
    return RegExp(r'^(19|20)\d{2}$').hasMatch(tag);
  }

  /// 予約タグかどうかを判定する
  static bool isReservedTag(String tag) {
    // 予約タグは __で始まり__で終わるパターン
    return tag.startsWith('__') && tag.endsWith('__');
  }

  /// 「お気に入り」タグかどうかを判定する
  static bool isFavoriteTag(String tag) {
    return tag == '__favorite__' || tag == '__お気に入り__';
  }

  /// AIタグをキャラタグ、特徴タグ、その他に分類する
  static Map<String, List<String>> categorizeAiTags(List<String> aiTags) {
    final characterTags = <String>[];
    final featureTags = <String>[];
    final otherTags = <String>[];
    final userTags = <String>[]; // 予約タグ（お気に入りなど）をユーザータグとして分類

    for (final tag in aiTags) {
      if (isReservedTag(tag)) {
        userTags.add(tag);
      } else if (isCharacter(tag)) {
        characterTags.add(tag);
      } else if (isYear(tag)) {
        otherTags.add(tag);
      } else {
        featureTags.add(tag);
      }
    }

    return {
      'character': characterTags,
      'feature': featureTags,
      'other': otherTags,
      'user': userTags,
    };
  }
}
