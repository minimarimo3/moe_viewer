import 'dart:io';

class ImageList {
  final List<dynamic> displayItems;
  final List<File> detailFiles;

  const ImageList({
    required this.displayItems,
    required this.detailFiles,
  });

  ImageList copyWith({
    List<dynamic>? displayItems,
    List<File>? detailFiles,
  }) =>
      ImageList(
        displayItems: displayItems ?? this.displayItems,
        detailFiles: detailFiles ?? this.detailFiles,
      );
}
