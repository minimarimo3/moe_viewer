import 'dart:io';
import 'dart:async';

import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../core/services/database_helper.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pie_menu/pie_menu.dart';
import '../../core/services/favorites_service.dart';
import '../../core/utils/pixiv_utils.dart';

class DetailScreen extends StatefulWidget {
  final List<File> imageFileList;
  final int initialIndex;

  const DetailScreen({
    super.key,
    required this.imageFileList,
    required this.initialIndex,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  bool _isUiVisible = true;
  late int _currentIndex;
  // ★★★ ダブルタップ時のアニメーションを管理するコントローラー ★★★
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;

  // ★★★ InteractiveViewerの拡大・移動状態を直接操作するコントローラー ★★★
  final _transformationController = TransformationController();

  // ★★★ PageViewのスワイプを有効/無効にするための変数 ★★★
  bool _isPagingEnabled = true;

  Future<void> _showImageDetails(File imageFile) async {
    // 画像のバイトデータを読み込み
    /*
    final bytes = await imageFile.readAsBytes();
    // 画像をデコードして解像度を取得（重い）
    final image = img.decodeImage(bytes);
    final dimensions = (image != null)
        ? '${image.width} x ${image.height}'
        : '不明';
    // ファイルサイズを取得してフォーマット
    final sizeInBytes = await imageFile.length();
    final sizeFormatted = _formatBytes(sizeInBytes, 2);
    */

    // データベースからタグを取得
    final tags = await DatabaseHelper.instance.getTagsForPath(imageFile.path);
    // Pixiv IDを取得
    final pixivId = _extractPixivId(imageFile.path);

    if (!mounted) return;

    // 画面下からスライドアップするパネル（ModalBottomSheet）を表示
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          // padding: const EdgeInsets.all(16.0),
          padding: EdgeInsets.only(
            top: 16.0,
            left: 8.0,
            right: 8.0,
            // 下の余白に、システムのUI分(ナビゲーションバーの高さ)を追加する
            bottom: 16.0 + MediaQuery.of(context).viewPadding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '画像の詳細',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Divider(),
              if (tags != null && tags.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.psychology_outlined),
                  title: const Text('AIによる解析タグ'),
                  // Wrapウィジェットでタグを自動で折り返し表示
                  subtitle: Wrap(
                    spacing: 6.0,
                    runSpacing: 4.0,
                    children: tags
                        .map(
                          (tag) => Chip(
                            label: Text(tag),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4.0,
                              vertical: 0,
                            ),
                            labelStyle: const TextStyle(fontSize: 12),
                          ),
                        )
                        .toList(),
                  ),
                ),
              /*
              ListTile(
                leading: Icon(Icons.photo_size_select_actual_outlined),
                title: Text('解像度: $dimensions'),
              ),
              ListTile(
                leading: Icon(Icons.sd_storage_outlined),
                title: Text('ファイルサイズ: $sizeFormatted'),
              ),
              */
              ListTile(
                leading: Icon(Icons.folder_outlined),
                title: Text('ファイルパス'),
                subtitle: Text(imageFile.path),
              ),
              if (pixivId != null)
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('Pixivで作品を見る'),
                  subtitle: Text('ID: $pixivId'),
                  onTap: () {
                    _launchURL('https://www.pixiv.net/artworks/$pixivId');
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // ★★★ バイト数をKB, MB, GBに変換するヘルパー関数 ★★★
  /*
  String _formatBytes(int bytes, int decimals) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }
  */

  // ★★★ ファイル名からPixivのイラストIDを抽出する関数 ★★★
  String? _extractPixivId(String path) {
    // ファイル名の部分だけを取得 (例: illust_12345_p0.jpg)
    final fileName = path.split('/').last;

    // 正規表現で 'illust_' と '_' の間の数字を探す
    final regExp = RegExp(r'illust_(\d+)_');
    final match = regExp.firstMatch(fileName);

    // パターンに一致すれば、数字の部分 (グループ1) を返す
    if (match != null) {
      return match.group(1);
    }

    return null; // 一致しなければnullを返す
  }

  // ★★★ URLを開くための関数 ★★★
  void _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // エラーハンドリング（例: メッセージ表示）
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('このリンクを開けませんでした: $url')));
      }
    }
  }

  void _precacheAdjacentImages(int index) {
    // 次の画像を先読み
    if (index + 1 < widget.imageFileList.length) {
      final nextImageFile = widget.imageFileList[index + 1];
      precacheImage(FileImage(nextImageFile), context);
    }
    // 前の画像を先読み（逆方向にスワイプする場合のため）
    if (index - 1 >= 0) {
      final prevImageFile = widget.imageFileList[index - 1];
      precacheImage(FileImage(prevImageFile), context);
    }
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _saveCurrentState();

    // ★★★ InteractiveViewerのスケール（拡大率）が変化したのをリッスンする ★★★
    _transformationController.addListener(() {
      // 拡大率が1.0（等倍）でない場合、ページングを無効にする
      final isZoomed =
          _transformationController.value.getMaxScaleOnAxis() != 1.0;
      if (isZoomed != !_isPagingEnabled) {
        setState(() {
          _isPagingEnabled = !isZoomed;
        });
      }
    });

    // ★★★ 画面の初回描画が終わった後に、最初の先読みを実行 ★★★
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheAdjacentImages(_currentIndex);
    });

    // ★★★ 画面を開いて0秒後に自動でUIを隠す
    Timer(const Duration(seconds: 0), () {
      if (mounted) {
        _toggleUiVisibility();
      }
    });
  }

  // ★★★ 現在の状態をSharedPreferencesに保存する関数 ★★★
  Future<void> _saveCurrentState() async {
    final prefs = await SharedPreferences.getInstance();
    // FileリストをStringのリスト（パスのリスト）に変換
    final pathList = widget.imageFileList.map((file) => file.path).toList();

    await prefs.setBool('wasOnDetailScreen', true); // 詳細画面にいた、というフラグ
    await prefs.setStringList('lastViewedPaths', pathList); // 画像リスト
    await prefs.setInt('lastViewedIndex', _currentIndex); // 現在のインデックス
  }

  @override
  void dispose() {
    // NOTE: 追加忘れ？
    _pageController.dispose();
    // ★★★ この画面を離れるときに、必ずシステムUIを元に戻す
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _animationController.dispose(); // ★★★ disposeを追加
    _transformationController.dispose(); // ★★★ disposeを追加
    super.dispose();
  }

  // ★★★ ダブルタップ時の処理 ★★★
  void _onDoubleTap(TapDownDetails details) {
    final position = details.localPosition;
    final currentScale = _transformationController.value.getMaxScaleOnAxis();

    Matrix4 endMatrix;
    if (currentScale > 1.0) {
      // 現在拡大されている場合は、元に戻す
      endMatrix = Matrix4.identity();
    } else {
      // 拡大されていない場合は、タップした位置を中心に2.5倍に拡大
      endMatrix = Matrix4.identity()
        ..translateByVector3(
            Vector3(-position.dx * 1.5, -position.dy * 1.5, 0.0))
        ..scaleByVector3(Vector3(2.5, 2.5, 1.0));
    }

    // アニメーションを開始
    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: endMatrix,
    ).animate(CurveTween(curve: Curves.easeOut).animate(_animationController));
    _animation!.addListener(() {
      _transformationController.value = _animation!.value;
    });
    _animationController.forward(from: 0);
  }

  // ★★★ UIの表示/非表示を切り替える関数 ★★★
  void _toggleUiVisibility() {
    setState(() {
      _isUiVisible = !_isUiVisible;

      if (_isUiVisible) {
        // UIを表示する（システムUIも元に戻す）
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } else {
        // UIを隠す（システムUIも全て隠す）
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PieCanvas(
      theme: const PieTheme(
        overlayColor: Colors.transparent,
        buttonTheme: PieButtonTheme(backgroundColor: Colors.white, iconColor: Colors.black87),
        buttonThemeHovered: PieButtonTheme(backgroundColor: Colors.blueAccent, iconColor: Colors.white),
        regularPressShowsMenu: false,
        longPressShowsMenu: true,
        longPressDuration: Duration(milliseconds: 350),
      ),
      child: Scaffold(
      // ★★★ _isUiVisibleの値に応じてAppBarを表示/非表示
      appBar: _isUiVisible
          ? AppBar(
              backgroundColor: Colors.grey,
              actions: [
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () {
                    final currentImage = widget.imageFileList[_currentIndex];
                    // XFileに変換して共有（新API）
                    SharePlus.instance.share(
                      ShareParams(files: [XFile(currentImage.path)]),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  onPressed: () {
                    final currentImage = widget.imageFileList[_currentIndex];
                    _showImageDetails(currentImage);
                  },
                ),
              ],
            )
          : null,
      // AppBarの高さを考慮するために必要
      extendBodyBehindAppBar: true,
      // ★★★ 画面全体をGestureDetectorで囲んでタップを検知
  body: GestureDetector(
        onTap: _toggleUiVisibility,
        onDoubleTapDown: _onDoubleTap,
        child: PageView.builder(
          controller: _pageController,
          physics: _isPagingEnabled
              ? const PageScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
            _saveCurrentState();
            _precacheAdjacentImages(index);
          },
          itemCount: widget.imageFileList.length,
          itemBuilder: (context, index) {
            final file = widget.imageFileList[index];
            return InteractiveViewer(
              transformationController: _transformationController,
              onInteractionEnd: (details) {
                if (_transformationController.value.getMaxScaleOnAxis() <=
                    1.0) {
                  // 必要ならここで isPagingEnabled を true に戻すロジックを追加
                  setState(() {
                    _isPagingEnabled = true;
                  });
                }
              },
              child: Center(
                // ★★★ ここからHeroウィジェットを追加 ★★★
                child: PieMenu(
                  actions: [
                    if (PixivUtils.extractPixivId(file.path) != null)
                      PieAction(
                        tooltip: const Text('Pixivを開く'),
                        onSelect: () async {
                          final id = PixivUtils.extractPixivId(file.path);
                          if (id != null) {
                            final uri = Uri.parse('https://www.pixiv.net/artworks/$id');
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
                        final newState = await FavoritesService.instance.toggleFavorite(file.path);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(newState ? 'お気に入りに追加しました' : 'お気に入りを解除しました')),
                        );
                      },
                      child: const Icon(Icons.favorite_border),
                    ),
                  ],
                  // メイン画面と同じルールでタグを生成
                  child: Hero(
                    tag: 'imageHero_$index',
                    child: RepaintBoundary(child: Image.file(file)),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      ),
    );
  }
}