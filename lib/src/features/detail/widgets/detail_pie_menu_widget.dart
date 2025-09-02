import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pie_menu/pie_menu.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/favorites_service.dart';
import '../../../core/utils/pixiv_utils.dart';

class DetailPieMenuWidget extends StatefulWidget {
  final Widget child;
  final File currentFile;

  const DetailPieMenuWidget({
    super.key,
    required this.child,
    required this.currentFile,
  });

  @override
  State<DetailPieMenuWidget> createState() => DetailPieMenuWidgetState();
}

class DetailPieMenuWidgetState extends State<DetailPieMenuWidget> {
  final PieMenuController _pieController = PieMenuController();
  final GlobalKey _canvasKey = GlobalKey();

  void openMenuAtPosition([Offset? globalPosition]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (globalPosition != null && _canvasKey.currentContext != null) {
        final box = _canvasKey.currentContext!.findRenderObject() as RenderBox?;
        if (box != null) {
          final localPosition = box.globalToLocal(globalPosition);
          _pieController.openMenu(menuDisplacement: localPosition);
          return;
        }
      }
      _pieController.openMenu();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PieCanvas(
      key: _canvasKey,
      child: Stack(
        children: [
          widget.child,
          PieMenu(
            controller: _pieController,
            actions: _buildPieActions(),
            child: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  List<PieAction> _buildPieActions() {
    return [
      if (PixivUtils.extractPixivId(widget.currentFile.path) != null)
        PieAction(
          tooltip: const Text('Pixivを開く'),
          onSelect: () async {
            final id = PixivUtils.extractPixivId(widget.currentFile.path);
            if (id != null) {
              final uri = Uri.parse(
                'https://www.pixiv.net/artworks/$id',
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('リンクを開けませんでした')),
                );
              }
            }
          },
          child: const Icon(Icons.open_in_new),
        ),
      PieAction(
        tooltip: const Text('お気に入りを切替'),
        onSelect: () async {
          final newState = await FavoritesService.instance
              .toggleFavorite(widget.currentFile.path);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                newState ? 'お気に入りに追加しました' : 'お気に入りを解除しました',
              ),
            ),
          );
        },
        child: const Icon(Icons.favorite_border),
      ),
    ];
  }
}
