import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../utils/pixiv_utils.dart';

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
      version: 4,
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
        created_at INTEGER NOT NULL,
        sort_mode TEXT NOT NULL DEFAULT 'manual' -- added_desc/added_asc/name_asc/name_desc/manual
      )
    ''');

    await db.execute('''
      CREATE TABLE album_items (
        album_id INTEGER NOT NULL,
        path TEXT NOT NULL,
        added_at INTEGER NOT NULL,
  position INTEGER NOT NULL,
        PRIMARY KEY (album_id, path),
        FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE
      )
    ''');

    // v4: 手動タグ用テーブル
    await db.execute('''
      CREATE TABLE manual_tags (
        path TEXT NOT NULL,
        tag TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        PRIMARY KEY (path, tag)
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS albums (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          sort_mode TEXT NOT NULL DEFAULT 'manual'
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS album_items (
          album_id INTEGER NOT NULL,
          path TEXT NOT NULL,
          added_at INTEGER NOT NULL,
          position INTEGER NOT NULL,
          PRIMARY KEY (album_id, path),
          FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 3) {
      // v3: album_items に position 列を追加し、既存行を初期化
      try {
        await db.execute('ALTER TABLE album_items ADD COLUMN position INTEGER');
      } catch (_) {
        // 既に存在する場合は無視
      }
      // 既存のNULL positionに、追加日時の逆順に近い順序を与える（新しいものが先頭になるよう負値を設定）
      await db.execute(
        'UPDATE album_items SET position = -added_at WHERE position IS NULL',
      );
    }
    if (oldVersion < 4) {
      // v4: 手動タグ用テーブルを追加
      await db.execute('''
        CREATE TABLE IF NOT EXISTS manual_tags (
          path TEXT NOT NULL,
          tag TEXT NOT NULL,
          added_at INTEGER NOT NULL,
          PRIMARY KEY (path, tag)
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

  // 手動タグを取得
  Future<List<String>> getManualTagsForPath(String path) async {
    final db = await instance.database;
    final result = await db.query(
      'manual_tags',
      columns: ['tag'],
      where: 'path = ?',
      whereArgs: [path],
      orderBy: 'added_at ASC',
    );
    return result.map((row) => row['tag'] as String).toList();
  }

  // AI解析タグと手動タグを統合して取得
  Future<Map<String, List<String>>> getAllTagsForPath(String path) async {
    final aiTags = await getTagsForPath(path) ?? [];
    final manualTags = await getManualTagsForPath(path);
    return {'ai': aiTags, 'manual': manualTags};
  }

  // 手動タグを追加
  Future<void> addManualTag(String path, String tag) async {
    final db = await instance.database;
    await db.insert('manual_tags', {
      'path': path,
      'tag': tag,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // 手動タグを削除
  Future<void> removeManualTag(String path, String tag) async {
    final db = await instance.database;
    await db.delete(
      'manual_tags',
      where: 'path = ? AND tag = ?',
      whereArgs: [path, tag],
    );
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
  // AI解析タグと手動タグの両方を検索対象とする
  Future<List<String>> searchByTags(List<String> tokens) async {
    // エイリアスを正規タグに正規化（未登録は小文字化）
    final normalized = ReservedTags.normalizeTokens(tokens);
    if (normalized.isEmpty) return <String>[];

    final db = await instance.database;

    // AI解析タグでの検索
    final aiLikeConds = List.filled(normalized.length, 'LOWER(tags) LIKE ?');
    final aiWhereCore = aiLikeConds.join(' AND ');
    final aiExclusion = ' AND tags NOT LIKE ? AND tags NOT LIKE ?';
    final aiWhere = aiWhereCore + aiExclusion;
    final aiArgs = [
      ...normalized.map((t) => '%$t%'),
      '%AI解析エラー%',
      '%タグが見つかりませんでした%',
    ];

    final aiRows = await db.query(
      'image_tags',
      columns: ['path'],
      where: aiWhere,
      whereArgs: aiArgs,
    );
    final aiPaths = aiRows.map((r) => r['path'] as String).toSet();

    // 手動タグでの検索
    final manualPaths = <String>{};
    for (final token in normalized) {
      final manualRows = await db.query(
        'manual_tags',
        columns: ['path'],
        where: 'LOWER(tag) LIKE ?',
        whereArgs: ['%$token%'],
      );
      final tokenPaths = manualRows.map((r) => r['path'] as String).toSet();

      if (manualPaths.isEmpty) {
        manualPaths.addAll(tokenPaths);
      } else {
        // AND検索なので積集合を取る
        manualPaths.retainWhere(tokenPaths.contains);
      }
    }

    // AI解析タグと手動タグの結果を統合
    final allPaths = {...aiPaths, ...manualPaths};
    return allPaths.toList();
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
  // AI解析タグと手動タグの両方を含む
  Future<List<String>> getAllTags() async {
    final db = await instance.database;

    // AI解析タグを取得
    final aiRows = await db.query(
      'image_tags',
      columns: ['tags'],
      where: 'tags NOT LIKE ? AND tags NOT LIKE ?',
      whereArgs: ['%AI解析エラー%', '%タグが見つかりませんでした%'],
    );
    final set = <String>{};
    for (final r in aiRows) {
      final t = (r['tags'] as String?) ?? '';
      for (final raw in t.split(',')) {
        final s = raw.trim();
        if (s.isEmpty) continue;
        set.add(s);
      }
    }

    // 手動タグを取得
    final manualRows = await db.query('manual_tags', columns: ['tag']);
    for (final r in manualRows) {
      final tag = (r['tag'] as String?) ?? '';
      if (tag.isNotEmpty) {
        set.add(tag);
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
    await db.update(
      'albums',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [albumId],
    );
  }

  Future<void> updateAlbumSortMode(int albumId, String sortMode) async {
    final db = await instance.database;
    await db.update(
      'albums',
      {'sort_mode': sortMode},
      where: 'id = ?',
      whereArgs: [albumId],
    );
  }

  Future<void> deleteAlbum(int albumId) async {
    final db = await instance.database;
    // album_items は外部キーの ON DELETE CASCADE で削除される
    await db.delete('albums', where: 'id = ?', whereArgs: [albumId]);
  }

  Future<void> addImageToAlbum(int albumId, String path) async {
    final db = await instance.database;
    final next = await _getNextPosition(db, albumId) + 1;
    await db.insert('album_items', {
      'album_id': albumId,
      'path': path,
      'added_at': DateTime.now().millisecondsSinceEpoch,
      'position': next,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> addImagesToAlbum(int albumId, List<String> paths) async {
    final db = await instance.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = await _getNextPosition(db, albumId);
    var pos = next;
    final batch = db.batch();
    for (final p in paths) {
      pos += 1;
      batch.insert('album_items', {
        'album_id': albumId,
        'path': p,
        'added_at': now,
        'position': pos,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
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

  Future<List<Map<String, dynamic>>> getAlbumItemsRaw(int albumId) async {
    final db = await instance.database;
    final rows = await db.query(
      'album_items',
      columns: ['path', 'added_at', 'position'],
      where: 'album_id = ?',
      whereArgs: [albumId],
      // 手動順序が優先。positionが同値/未設定の場合のフォールバックとしてadded_atを使用
      orderBy: 'position ASC, added_at DESC',
    );
    return rows;
  }

  Future<int> _getNextPosition(Database db, int albumId) async {
    final res = await db.rawQuery(
      'SELECT MAX(position) as maxpos FROM album_items WHERE album_id = ?',
      [albumId],
    );
    final v = res.first['maxpos'];
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  Future<void> updateAlbumPositions(
    int albumId,
    List<String> orderedPaths,
  ) async {
    final db = await instance.database;
    final batch = db.batch();
    for (var i = 0; i < orderedPaths.length; i++) {
      batch.update(
        'album_items',
        {'position': i + 1},
        where: 'album_id = ? AND path = ?',
        whereArgs: [albumId, orderedPaths[i]],
      );
    }
    await batch.commit(noResult: true);
  }
}
