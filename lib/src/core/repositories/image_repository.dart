import 'dart:io';

import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/folder_setting.dart';
import '../models/image_list.dart';

class ImageRepository {
  Future<ImageList> getAllImages(List<FolderSetting> folderSettings) async {
    final enabledFolders = folderSettings.where((f) => f.isEnabled).toList();
    final selectedPaths = enabledFolders.map((f) => f.path).toList();

    List<dynamic> allDisplayItems = [];
    List<File> allDetailFiles = [];

    // --- 公式ルート (photo_manager) ---
    final filterOption = FilterOptionGroup(includeHiddenAssets: true);
    final allAlbums = await PhotoManager.getAssetPathList(
      filterOption: filterOption,
    );
    final albumMap = {
      for (var album in allAlbums) album.name.toLowerCase(): album,
    };

    final hasFullAccess =
        await Permission.manageExternalStorage.status.isGranted;
    List<String> pathsForDirectScan = [];

    for (final path in selectedPaths) {
      final folderName = path.split('/').last.toLowerCase();

      if (albumMap.containsKey(folderName)) {
        final album = albumMap[folderName]!;
        final assets = await album.getAssetListRange(
          start: 0,
          end: await album.assetCountAsync,
        );
        for (final asset in assets) {
          final file = await asset.file;
          // ファイルが取得できるものだけを表示対象にする（インデックス不整合を防止）
          if (file != null) {
            allDisplayItems.add(asset);
            allDetailFiles.add(file);
          }
        }
      } else if (hasFullAccess) {
        pathsForDirectScan.add(path);
      }
    }

    // --- 特殊ルート (dart:io) ---
    for (final path in pathsForDirectScan) {
      final directory = Directory(path);
      if (await directory.exists()) {
        final files = directory.listSync(recursive: true);
        for (final fileEntity in files) {
          if (fileEntity is File) {
            final filePath = fileEntity.path.toLowerCase();
            if (filePath.endsWith('.jpg') ||
                filePath.endsWith('.png') ||
                filePath.endsWith('.jpeg') ||
                filePath.endsWith('.gif')) {
              allDisplayItems.add(fileEntity);
              allDetailFiles.add(fileEntity);
            }
          }
        }
      }
    }
    return ImageList(allDisplayItems, allDetailFiles);
  }
}
