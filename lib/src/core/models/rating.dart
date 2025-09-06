enum Rating { nsfw, sfw, unclassified }

extension RatingExtension on Rating {
  String get displayName {
    switch (this) {
      case Rating.nsfw:
        return '官能的';
      case Rating.sfw:
        return 'U18';
      case Rating.unclassified:
        return '未分類';
    }
  }
}
