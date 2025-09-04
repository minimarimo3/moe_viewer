class Album {
  final int id;
  final String name;
  final DateTime createdAt;
  final String sortMode; // 'added_desc' など

  const Album({
    required this.id,
    required this.name,
    required this.createdAt,
    this.sortMode = 'added_desc',
  });

  factory Album.fromRow(Map<String, dynamic> row) => Album(
    id: row['id'] as int,
    name: row['name'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    sortMode: (row['sort_mode'] as String?) ?? 'added_desc',
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'created_at': createdAt.millisecondsSinceEpoch,
    'sort_mode': sortMode,
  };

  Album copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    String? sortMode,
  }) {
    return Album(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      sortMode: sortMode ?? this.sortMode,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Album &&
        other.id == id &&
        other.name == name &&
        other.createdAt == createdAt &&
        other.sortMode == sortMode;
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt, sortMode);
}
