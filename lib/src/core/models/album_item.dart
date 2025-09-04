class AlbumItem {
  final String path;
  final DateTime addedAt;
  final int position;

  AlbumItem({
    required this.path,
    required this.addedAt,
    required this.position,
  });

  factory AlbumItem.fromRow(Map<String, dynamic> row) {
    return AlbumItem(
      path: row['path'] as String,
      addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
      position: (row['position'] is int)
          ? row['position'] as int
          : (row['position'] is num)
          ? (row['position'] as num).toInt()
          : 0,
    );
  }
}
