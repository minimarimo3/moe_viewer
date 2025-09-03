import 'dart:io';

import 'database_helper.dart';
import '../models/album.dart';

class AlbumsService {
  AlbumsService._();
  static final instance = AlbumsService._();

  Future<List<Album>> listAlbums() async {
    final rows = await DatabaseHelper.instance.getAlbums();
    return rows.map(Album.fromRow).toList();
  }

  Future<Album> createAlbum(String name) async {
    final id = await DatabaseHelper.instance.createAlbum(name);
    return Album(
      id: id,
      name: name,
      createdAt: DateTime.now(),
    );
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

  Future<List<File>> getAlbumFiles(int albumId) async {
    final paths = await DatabaseHelper.instance.getAlbumImagePaths(albumId);
    return paths.map((p) => File(p)).toList();
  }
}
