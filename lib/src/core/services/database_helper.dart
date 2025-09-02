import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pixiv_viewer.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE image_tags (
        path TEXT PRIMARY KEY,
        tags TEXT NOT NULL,
        analyzed_at INTEGER NOT NULL
      )
    ''');
  }

  // 解析結果を保存または更新する
  Future<void> insertOrUpdateTag(String path, List<String> tags) async {
    final db = await instance.database;
    await db.insert('image_tags', {
      'path': path,
      'tags': tags.join(','), // タグのリストをカンマ区切りの文字列に変換
      'analyzed_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // 解析済みのファイルのパスを全て取得する（ただし、エラーのものを除く）
  Future<Set<String>> getAnalyzedImagePaths() async {
    final db = await instance.database;
    // ★★★ "tags"がエラー文字列でないものだけを抽出する条件を追加 ★★★
    final result = await db.query(
      'image_tags',
      columns: ['path'],
      where: "tags NOT LIKE ? AND tags NOT LIKE ?",
      whereArgs: ['%AI解析エラー%', '%タグが見つかりませんでした%'],
    );
    return result.map((row) => row['path'] as String).toSet();
  }

  Future<List<String>?> getTagsForPath(String path) async {
    final db = await instance.database;
    final result = await db.query(
      'image_tags',
      columns: ['tags'],
      where: 'path = ?',
      whereArgs: [path],
    );

    if (result.isNotEmpty) {
      final tagsString = result.first['tags'] as String;
      return tagsString.split(','); // カンマ区切りの文字列をリストに戻す
    }
    return null; // データがなければnullを返す
  }

  // 既存タグを取得し、関数で編集して保存するユーティリティ（予約タグの拡張に備える）
  Future<void> editTags(
    String path,
    List<String> Function(List<String>) editor,
  ) async {
    final current = await getTagsForPath(path) ?? <String>[];
    final next = editor(List<String>.from(current));
    await insertOrUpdateTag(path, next);
  }

  // （将来の検索機能のための準備）
  Future<List<Map<String, dynamic>>> searchByTag(String tag) async {
    final db = await instance.database;
    return await db.query(
      'image_tags',
      where: 'tags LIKE ?',
      whereArgs: ['%$tag%'],
    );
  }

  // 解析済みのファイルの総数を取得する（ただし、エラーのものを除く）
  Future<int> getAnalyzedFileCount() async {
    final db = await instance.database;
    // TODO: AIのロードエラー？みたいなのも除外したい
    final result = await db.rawQuery(
      "SELECT COUNT(*) FROM image_tags WHERE tags NOT LIKE ? AND tags NOT LIKE ?",
      ['%AI解析エラー%', '%タグが見つかりませんでした%'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
