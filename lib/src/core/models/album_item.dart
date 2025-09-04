class AlbumItem {
  final String path;
  final DateTime addedAt;
  final int position;

  const AlbumItem({
    required this.path,
    required this.addedAt,
    required this.position,
  });

  factory AlbumItem.fromRow(Map<String, dynamic> row) => AlbumItem(
        path: row['path'] as String,
        addedAt:
            DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
        position: switch (row['position']) {
          final int v => v,
          final num v => v.toInt(),
          _ => 0,
        },
      );

  Map<String, dynamic> toMap() => {
        'path': path,
        'added_at': addedAt.millisecondsSinceEpoch,
        'position': position,
      };

  AlbumItem copyWith({
    String? path,
    DateTime? addedAt,
    int? position,
  }) =>
      AlbumItem(
        path: path ?? this.path,
        addedAt: addedAt ?? this.addedAt,
        position: position ?? this.position,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlbumItem &&
          other.path == path &&
          other.addedAt == addedAt &&
          other.position == position;

  @override
  int get hashCode => Object.hash(path, addedAt, position);
}
