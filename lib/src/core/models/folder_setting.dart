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
      path: map['path'],
      isEnabled: map['isEnabled'],
      isDeletable: map['isDeletable'],
    );
  }

  // FolderSettingをMapに変換するメソッド
  Map<String, dynamic> toMap() {
    return {'path': path, 'isEnabled': isEnabled, 'isDeletable': isDeletable};
  }
}
