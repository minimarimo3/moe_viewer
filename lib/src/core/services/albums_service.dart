import 'dart:io';
import 'dart:async';

import 'database_helper.dart';
import '../models/album.dart';
import '../models/album_item.dart';
import 'thumbnail_service.dart';

class AlbumsService {
  AlbumsService._();
  static final instance = AlbumsService._();

  // 簡単なキャッシュ機能
  final Map<int, List<AlbumItem>> _albumItemsCache = {};
  final Map<int, DateTime> _cacheTimestamps = {};
  static const _cacheValidDuration = Duration(minutes: 5); // 5分間有効

  bool _isCacheValid(int albumId) {
    if (!_cacheTimestamps.containsKey(albumId)) return false;
    final timestamp = _cacheTimestamps[albumId]!;
    return DateTime.now().difference(timestamp) < _cacheValidDuration;
  }

  void _invalidateCache(int albumId) {
    _albumItemsCache.remove(albumId);
    _cacheTimestamps.remove(albumId);
  }

  void _updateCache(int albumId, List<AlbumItem> items) {
    _albumItemsCache[albumId] = items;
    _cacheTimestamps[albumId] = DateTime.now();
  }

  Future<List<Album>> listAlbums() async {
    final rows = await DatabaseHelper.instance.getAlbums();
    return rows.map(Album.fromRow).toList();
  }

  Future<Album> createAlbum(String name) async {
    final id = await DatabaseHelper.instance.createAlbum(name);
    return Album(id: id, name: name, createdAt: DateTime.now());
  }

  Future<void> renameAlbum(int id, String name) async {
    await DatabaseHelper.instance.renameAlbum(id, name);
  }

  Future<void> deleteAlbum(int id) async {
    await DatabaseHelper.instance.deleteAlbum(id);
  }

  Future<void> addPaths(int albumId, List<String> paths) async {
    await DatabaseHelper.instance.addImagesToAlbum(albumId, paths);
    // キャッシュを無効化
    _invalidateCache(albumId);
    // 追加された画像のベースサムネイルをバックグラウンドで事前生成
    // 重くなりすぎないように短いディレイを入れつつ順次実行
    for (final p in paths) {
      // Fire-and-forget
      unawaited(precacheBaseThumbnail(p));
    }
  }

  Future<void> addFiles(int albumId, List<File> files) async {
    await addPaths(albumId, files.map((f) => f.path).toList());
  }

  Future<void> removePath(int albumId, String path) async {
    await DatabaseHelper.instance.removeImageFromAlbum(albumId, path);
    // キャッシュを無効化
    _invalidateCache(albumId);
  }

  Future<void> removePaths(int albumId, List<String> paths) async {
    for (final p in paths) {
      await DatabaseHelper.instance.removeImageFromAlbum(albumId, p);
    }
    // キャッシュを無効化
    _invalidateCache(albumId);
  }

  Future<List<AlbumItem>> getAlbumItems(int albumId) async {
    // キャッシュをチェック
    if (_isCacheValid(albumId)) {
      return _albumItemsCache[albumId]!;
    }

    final rows = await DatabaseHelper.instance.getAlbumItemsRaw(albumId);
    final items = rows.map(AlbumItem.fromRow).toList();

    // キャッシュを更新
    _updateCache(albumId, items);

    return items;
  }

  Future<List<File>> getAlbumFiles(
    int albumId, {
    String sortMode = 'manual',
  }) async {
    final items = await getAlbumItems(albumId);
    // sortMode: added_desc, added_asc, name_asc, name_desc, manual
    switch (sortMode) {
      case 'manual':
        // DBのposition順（getAlbumItemsRawでposition ASC）をそのまま使う
        return items.map((i) => File(i.path)).toList();
      case 'added_asc':
        items.sort((a, b) => a.addedAt.compareTo(b.addedAt));
        break;
      case 'name_asc':
        items.sort(
          (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
        );
        break;
      case 'name_desc':
        items.sort(
          (a, b) => b.path.toLowerCase().compareTo(a.path.toLowerCase()),
        );
        break;
      case 'added_desc':
      default:
        items.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        break;
    }
    return items.map((i) => File(i.path)).toList();
  }

  Future<List<AlbumItem>> getAlbumItemsWithOrder(int albumId) async {
    final rows = await DatabaseHelper.instance.getAlbumItemsRaw(albumId);
    return rows.map((e) => AlbumItem.fromRow(e)).toList();
  }

  Future<void> updateManualOrder(int albumId, List<String> orderedPaths) async {
    await DatabaseHelper.instance.updateAlbumPositions(albumId, orderedPaths);
    // キャッシュを無効化
    _invalidateCache(albumId);
  }

  Future<void> setAlbumSortMode(int albumId, String sortMode) async {
    await DatabaseHelper.instance.updateAlbumSortMode(albumId, sortMode);
  }
}
