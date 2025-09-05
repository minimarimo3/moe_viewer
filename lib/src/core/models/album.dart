class Album {
  final int id;
  final String name;
  final DateTime createdAt;
  final String sortMode; // 'added_desc' 等

  Album({
    required this.id,
    required this.name,
    required this.createdAt,
    this.sortMode = 'manual',
  });

  factory Album.fromRow(Map<String, dynamic> row) {
    return Album(
      id: row['id'] as int,
      name: row['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      sortMode: (row['sort_mode'] as String?) ?? 'manual',
    );
  }
}
