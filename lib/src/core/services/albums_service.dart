import 'dart:io';

import 'database_helper.dart';
import '../models/album.dart';
import '../models/album_item.dart';

class AlbumsService {
  AlbumsService._();
  static final instance = AlbumsService._();

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
  }

  Future<void> addFiles(int albumId, List<File> files) async {
    await addPaths(albumId, files.map((f) => f.path).toList());
  }

  Future<void> removePath(int albumId, String path) async {
    await DatabaseHelper.instance.removeImageFromAlbum(albumId, path);
  }

  Future<void> removePaths(int albumId, List<String> paths) async {
    for (final p in paths) {
      await DatabaseHelper.instance.removeImageFromAlbum(albumId, p);
    }
  }

  Future<List<AlbumItem>> getAlbumItems(int albumId) async {
    final rows = await DatabaseHelper.instance.getAlbumItemsRaw(albumId);
    return rows.map(AlbumItem.fromRow).toList();
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
  }

  Future<void> setAlbumSortMode(int albumId, String sortMode) async {
    await DatabaseHelper.instance.updateAlbumSortMode(albumId, sortMode);
  }
}
