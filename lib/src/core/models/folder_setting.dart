class FolderSetting {
  final String path;
  bool isEnabled;
  final bool isDeletable;

  FolderSetting({
    required this.path,
    this.isEnabled = true,
    this.isDeletable = true,
  });

  // MapからFolderSettingに変換するためのファクトリコンストラクタ
  factory FolderSetting.fromMap(Map<String, dynamic> map) {
    return FolderSetting(
      path: map['path'] as String,
      isEnabled: (map['isEnabled'] as bool?) ?? true,
      isDeletable: (map['isDeletable'] as bool?) ?? true,
    );
  }

  // FolderSettingをMapに変換するメソッド
  Map<String, dynamic> toMap() => {
    'path': path,
    'isEnabled': isEnabled,
    'isDeletable': isDeletable,
  };

  FolderSetting copyWith({String? path, bool? isEnabled, bool? isDeletable}) =>
      FolderSetting(
        path: path ?? this.path,
        isEnabled: isEnabled ?? this.isEnabled,
        isDeletable: isDeletable ?? this.isDeletable,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FolderSetting &&
          other.path == path &&
          other.isEnabled == isEnabled &&
          other.isDeletable == isDeletable;

  @override
  int get hashCode => Object.hash(path, isEnabled, isDeletable);
}
