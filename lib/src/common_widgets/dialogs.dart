import 'package:flutter/material.dart';
import '../core/services/albums_service.dart';

// アプリ内のどこからでも呼び出せる情報ダイアログ関数
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String content,
}) async {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        // 長い文章でもスクロールできるようにする
        content: SingleChildScrollView(child: Text(content)),
        actions: <Widget>[
          TextButton(
            child: const Text('OK'),
            onPressed: () {
              // OKボタンを押すとダイアログを閉じる
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}

Future<int?> pickAlbumDialog(BuildContext context) async {
  final albums = await AlbumsService.instance.listAlbums();
  if (!context.mounted) return null;
  return showDialog<int>(
    context: context,
    builder: (context) {
      final controller = TextEditingController();
      return AlertDialog(
        title: const Text('アルバムを選択'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (albums.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8.0),
                  child: Text('アルバムがありません。新規作成してください。'),
                ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: albums.length,
                  itemBuilder: (context, index) {
                    final a = albums[index];
                    return ListTile(
                      leading: const Icon(Icons.photo_album_outlined),
                      title: Text(a.name),
                      onTap: () => Navigator.of(context).pop(a.id),
                    );
                  },
                ),
              ),
              const Divider(),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: '新しいアルバム名'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              final album = await AlbumsService.instance.createAlbum(name);
              if (!context.mounted) return;
              Navigator.of(context).pop(album.id);
            },
            child: const Text('作成して追加'),
          ),
        ],
      );
    },
  );
}
