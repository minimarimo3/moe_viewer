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
    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onConfigure: (db) async {
        // 外部キー制約を有効化
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE image_tags (
        path TEXT PRIMARY KEY,
        tags TEXT NOT NULL,
        analyzed_at INTEGER NOT NULL
      )
    ''');

    // v2: アルバム関連
    await db.execute('''
      CREATE TABLE albums (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE album_items (
        album_id INTEGER NOT NULL,
        path TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        PRIMARY KEY (album_id, path),
        FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS albums (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS album_items (
          album_id INTEGER NOT NULL,
          path TEXT NOT NULL,
          added_at INTEGER NOT NULL,
          PRIMARY KEY (album_id, path),
          FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE
        )
      ''');
    }
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

  // 複数タグAND検索（大文字小文字を無視）し、該当パスのみ返す
  Future<List<String>> searchByTags(List<String> tokens) async {
    final normalized = tokens
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toList();
    if (normalized.isEmpty) return <String>[];

    final db = await instance.database;
    final likeConds = List.filled(normalized.length, 'LOWER(tags) LIKE ?');
    final whereCore = likeConds.join(' AND ');
    // 既知のエラー行は除外
    final exclusion = ' AND tags NOT LIKE ? AND tags NOT LIKE ?';
    final where = whereCore + exclusion;
    final args = [
      ...normalized.map((t) => '%$t%'),
      '%AI解析エラー%',
      '%タグが見つかりませんでした%',
    ];

    final rows = await db.query(
      'image_tags',
      columns: ['path'],
      where: where,
      whereArgs: args,
    );
    return rows.map((r) => r['path'] as String).toList();
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

  // 全タグ一覧（重複除去）を取得する。大文字小文字は区別しない。
  Future<List<String>> getAllTags() async {
    final db = await instance.database;
    final rows = await db.query(
      'image_tags',
      columns: ['tags'],
      where: 'tags NOT LIKE ? AND tags NOT LIKE ?',
      whereArgs: ['%AI解析エラー%', '%タグが見つかりませんでした%'],
    );
    final set = <String>{};
    for (final r in rows) {
      final t = (r['tags'] as String?) ?? '';
      for (final raw in t.split(',')) {
        final s = raw.trim();
        if (s.isEmpty) continue;
        set.add(s);
      }
    }
    final list = set.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  // ===== アルバムAPI =====
  Future<int> createAlbum(String name) async {
    final db = await instance.database;
    final id = await db.insert('albums', {
      'name': name,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return id;
  }

  Future<List<Map<String, dynamic>>> getAlbums() async {
    final db = await instance.database;
    return db.query('albums', orderBy: 'created_at DESC');
  }

  Future<void> renameAlbum(int albumId, String newName) async {
    final db = await instance.database;
    await db.update('albums', {'name': newName}, where: 'id = ?', whereArgs: [albumId]);
  }

  Future<void> deleteAlbum(int albumId) async {
    final db = await instance.database;
    // album_items は外部キーの ON DELETE CASCADE で削除される
    await db.delete('albums', where: 'id = ?', whereArgs: [albumId]);
  }

  Future<void> addImageToAlbum(int albumId, String path) async {
    final db = await instance.database;
    await db.insert(
      'album_items',
      {
        'album_id': albumId,
        'path': path,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> addImagesToAlbum(int albumId, List<String> paths) async {
    final db = await instance.database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final p in paths) {
      batch.insert(
        'album_items',
        {'album_id': albumId, 'path': p, 'added_at': now},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeImageFromAlbum(int albumId, String path) async {
    final db = await instance.database;
    await db.delete(
      'album_items',
      where: 'album_id = ? AND path = ?',
      whereArgs: [albumId, path],
    );
  }

  Future<List<String>> getAlbumImagePaths(int albumId) async {
    final db = await instance.database;
    final rows = await db.query(
      'album_items',
      columns: ['path'],
      where: 'album_id = ?',
      whereArgs: [albumId],
      orderBy: 'added_at DESC',
    );
    return rows.map((r) => r['path'] as String).toList();
  }
}
