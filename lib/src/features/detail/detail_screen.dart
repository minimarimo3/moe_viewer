import 'dart:io';
import 'dart:async';

import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../core/services/database_helper.dart';
import '../../core/providers/settings_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/pixiv_utils.dart';
import '../../core/utils/tag_category_utils.dart';
import '../../common_widgets/pie_menu_widget.dart';

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

  // SettingsProvider の参照を保持（dispose で context を使わないため）
  SettingsProvider? _settings;

  // ★★★ InteractiveViewerの拡大・移動状態を直接操作するコントローラー ★★★
  final _transformationController = TransformationController();

  // ★★★ PageViewのスワイプを有効/無効にするための変数 ★★★
  bool _isPagingEnabled = true;

  // 上スワイプで戻る判定用の変数
  double? _verticalDragStartY;
  double? _verticalDragCurrentY;
  static const double _verticalSwipeDistanceThreshold = 80.0; // px
  static const double _verticalSwipeVelocityThreshold = 500.0; // px/s

  final GlobalKey<PieMenuWidgetState> _pieMenuKey =
      GlobalKey<PieMenuWidgetState>();

  void _handleLongPress(Offset globalPosition) {
    final pieMenuState = _pieMenuKey.currentState;
    final currentFile = widget.imageFileList[_currentIndex];
    pieMenuState?.openMenuForItem(currentFile, globalPosition);
  }

  Future<void> _showImageDetails(File imageFile) async {
    // データベースからAIタグと手動タグを取得
    final allTags = await DatabaseHelper.instance
        .getAllTagsWithCategoriesForPath(imageFile.path);
    final rawAiTags = allTags['ai'] ?? [];
    final rawManualTags = allTags['manual'] ?? [];

    // 分類済みタグを取得（利用可能な場合）
    final rawAiCharacterTagsFromDB = allTags['aiCharacter'] as List<String>?;
    final rawAiFeatureTagsFromDB = allTags['aiFeature'] as List<String>?;

    // タグを別名に変換
    final db = DatabaseHelper.instance;
    final aiTags = await db.getDisplayTagNames(rawAiTags);
    final rawManualTagsFiltered = rawManualTags
        .where((tag) => !TagCategoryUtils.isFavoriteTag(tag))
        .toList();
    final manualTags = await db.getDisplayTagNames(rawManualTagsFiltered);
    final aiCharacterTagsFromDB = rawAiCharacterTagsFromDB != null
        ? await db.getDisplayTagNames(rawAiCharacterTagsFromDB)
        : null;
    final aiFeatureTagsFromDB = rawAiFeatureTagsFromDB != null
        ? await db.getDisplayTagNames(rawAiFeatureTagsFromDB)
        : null;

    // Pixiv IDを取得
    final pixivId = _extractPixivId(imageFile.path);

    if (!mounted) return;

    // タグの数に応じて初期サイズを動的に計算
    double initialSize = 0.4;
    // 分類済みタグが利用可能な場合はそれを使用、そうでない場合は従来の方法で分類
    List<String> aiCharacterTags;
    List<String> aiFeatureTags;
    List<String> combinedManualTags = List.from(manualTags);

    if (aiCharacterTagsFromDB != null && aiFeatureTagsFromDB != null) {
      // データベースから分類済みタグを使用
      aiCharacterTags = aiCharacterTagsFromDB;
      aiFeatureTags = aiFeatureTagsFromDB;
    } else {
      // 従来の方法で分類（後方互換性のため）
      await TagCategoryUtils.ensureLoaded();
      final categorizedAiTags = TagCategoryUtils.categorizeAiTags(aiTags);
      aiCharacterTags = categorizedAiTags['character'] ?? [];
      aiFeatureTags = categorizedAiTags['feature'] ?? [];

      // 予約タグ（お気に入りなど）を手動タグに統合するが、お気に入りタグは除外
      final userTags = categorizedAiTags['user'] ?? [];
      final nonFavoriteUserTags = userTags
          .where((tag) => !TagCategoryUtils.isFavoriteTag(tag))
          .toList();
      combinedManualTags.addAll(nonFavoriteUserTags);
    }

    final totalTagCount =
        combinedManualTags.length +
        aiCharacterTags.length +
        aiFeatureTags.length;
    if (totalTagCount > 20) {
      initialSize = 0.7;
    } else if (totalTagCount > 10) {
      initialSize = 0.55;
    } else if (totalTagCount > 5) {
      initialSize = 0.45;
    }

    // mountedチェックを追加してからshowModalBottomSheetを呼び出し
    if (!mounted) return;

    // DraggableScrollableSheetのコントローラーを作成
    final DraggableScrollableController draggableController =
        DraggableScrollableController();

    // 画面下からスライドアップするパネル（DraggableScrollableSheet を内包した ModalBottomSheet）を表示
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

        return DraggableScrollableSheet(
          controller: draggableController,
          expand: false,
          initialChildSize: initialSize,
          minChildSize: 0.2,
          maxChildSize: 0.95,
          snap: true,
          snapSizes: const [0.2, 0.4, 0.7, 0.95],
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).canvasColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16.0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ヘッダ部分（ドラッグハンドル + タイトル + 操作ボタン）
                  Container(
                    padding: EdgeInsets.only(
                      top: 16.0,
                      left: 16.0,
                      right: 16.0,
                      bottom: 8.0,
                    ),
                    child: Column(
                      children: [
                        // ドラッグハンドル
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16.0),
                            decoration: BoxDecoration(
                              color: Colors.grey[400],
                              borderRadius: BorderRadius.circular(2.0),
                            ),
                          ),
                        ),
                        // タイトル行
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '画像の詳細',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 展開ボタン
                                IconButton(
                                  icon: const Icon(Icons.expand_less),
                                  tooltip: '展開',
                                  onPressed: () {
                                    draggableController.animateTo(
                                      0.95,
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeOut,
                                    );
                                  },
                                ),
                                // 縮小ボタン
                                IconButton(
                                  icon: const Icon(Icons.expand_more),
                                  tooltip: '縮小',
                                  onPressed: () {
                                    draggableController.animateTo(
                                      0.2,
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeOut,
                                    );
                                  },
                                ),
                                // 閉じるボタン
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  tooltip: '閉じる',
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Divider(height: 1),
                      ],
                    ),
                  ),
                  // 本文部分
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(
                        left: 16.0,
                        right: 16.0,
                        bottom: 16.0 + bottomPadding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // 1. Pixiv連携セクション（最初に表示）
                          if (pixivId != null) ...[
                            const SizedBox(height: 8.0),
                            Row(
                              children: [
                                const Icon(Icons.open_in_new, size: 20),
                                const SizedBox(width: 8.0),
                                const Text(
                                  'Pixiv連携',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12.0),
                            InkWell(
                              onTap: () {
                                _launchURL(
                                  'https://www.pixiv.net/artworks/$pixivId',
                                );
                              },
                              borderRadius: BorderRadius.circular(8.0),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16.0),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.launch,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                    ),
                                    const SizedBox(width: 12.0),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Pixivで作品を見る',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onPrimaryContainer,
                                            ),
                                          ),
                                          const SizedBox(height: 4.0),
                                          Text(
                                            'ID: $pixivId',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onPrimaryContainer
                                                  .withValues(alpha: 0.8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24.0),
                          ],

                          // 2. ファイル情報セクション（2番目に表示）
                          Row(
                            children: [
                              const Icon(Icons.folder_outlined, size: 20),
                              const SizedBox(width: 8.0),
                              const Text(
                                'ファイル情報',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12.0),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12.0),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: SelectableText(
                              imageFile.path,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),

                          // 3. 手動タグセクション
                          if (combinedManualTags.isNotEmpty) ...[
                            const SizedBox(height: 24.0),
                            Row(
                              children: [
                                const Icon(Icons.edit, size: 20),
                                const SizedBox(width: 8.0),
                                Text(
                                  'ユーザータグ (${combinedManualTags.length}個)',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12.0),
                            Wrap(
                              spacing: 8.0,
                              runSpacing: 8.0,
                              children: combinedManualTags
                                  .map(
                                    (tag) => Chip(
                                      label: Text(tag),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                        vertical: 4.0,
                                      ),
                                      labelStyle: const TextStyle(fontSize: 13),
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],

                          // 4. AIキャラタグセクション
                          if (aiCharacterTags.isNotEmpty) ...[
                            const SizedBox(height: 24.0),
                            Row(
                              children: [
                                const Icon(Icons.person_outlined, size: 20),
                                const SizedBox(width: 8.0),
                                Text(
                                  'AIキャラタグ (${aiCharacterTags.length}個)',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12.0),
                            Wrap(
                              spacing: 8.0,
                              runSpacing: 8.0,
                              children: aiCharacterTags
                                  .map(
                                    (tag) => Chip(
                                      label: Text(tag),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                        vertical: 4.0,
                                      ),
                                      labelStyle: const TextStyle(fontSize: 13),
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withValues(alpha: 0.8),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],

                          // 5. AI特徴タグセクション
                          if (aiFeatureTags.isNotEmpty) ...[
                            const SizedBox(height: 24.0),
                            Row(
                              children: [
                                const Icon(Icons.psychology_outlined, size: 20),
                                const SizedBox(width: 8.0),
                                Text(
                                  'AI特徴タグ (${aiFeatureTags.length}個)',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12.0),
                            Wrap(
                              spacing: 8.0,
                              runSpacing: 8.0,
                              children: aiFeatureTags
                                  .map(
                                    (tag) => Chip(
                                      label: Text(tag),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                        vertical: 4.0,
                                      ),
                                      labelStyle: const TextStyle(fontSize: 13),
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withValues(alpha: 0.5),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],

                          // 下部の余白
                          const SizedBox(height: 16.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // listen: false で依存を登録せず参照のみを保持
    _settings = Provider.of<SettingsProvider>(context, listen: false);
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

    // 初期画像パスを保存
    if (_currentIndex < widget.imageFileList.length) {
      final currentImagePath = widget.imageFileList[_currentIndex].path;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final settings = Provider.of<SettingsProvider>(context, listen: false);
        settings.setLastViewedImagePath(currentImagePath);
      });
    }

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
    // 最新の画像パスを確実に保存
    if (_currentIndex < widget.imageFileList.length) {
      final currentImagePath = widget.imageFileList[_currentIndex].path;
      // dispose 中は context を使わず、事前に保持した参照を利用
      _settings?.setLastViewedImagePath(currentImagePath);
    }

    _pageController.dispose();
    // ★★★ この画面を離れるときに、必ずシステムUIを元に戻す
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
          Vector3(-position.dx * 1.5, -position.dy * 1.5, 0.0),
        )
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
    return PieMenuWidget(
      key: _pieMenuKey,
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
                      // TODO: 課金で削除
                      String shareText = "これはmoe_viewerで共有されました。\n";
                      if (PixivUtils.extractPixivId(currentImage.path) !=
                          null) {
                        shareText +=
                            "イラストのPixivのリンク: https://www.pixiv.net/artworks/${PixivUtils.extractPixivId(currentImage.path)}";
                      }
                      // XFileに変換して共有（新API）
                      SharePlus.instance.share(
                        ShareParams(
                          files: [XFile(currentImage.path)],
                          text: shareText,
                        ),
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
          onLongPressStart: (details) {
            _handleLongPress(details.globalPosition);
          },
          // 縦スワイプで戻る動作を実装（ページング有効時のみハンドラを登録して、
          // ズーム中にInteractiveViewerのジェスチャーが奪われないようにする）
          onVerticalDragStart: _isPagingEnabled
              ? (DragStartDetails details) {
                  _verticalDragStartY = details.globalPosition.dy;
                  _verticalDragCurrentY = _verticalDragStartY;
                }
              : null,
          onVerticalDragUpdate: _isPagingEnabled
              ? (DragUpdateDetails details) {
                  if (_verticalDragStartY == null) return;
                  _verticalDragCurrentY = details.globalPosition.dy;
                }
              : null,
          onVerticalDragEnd: _isPagingEnabled
              ? (DragEndDetails details) {
                  if (_verticalDragStartY == null ||
                      _verticalDragCurrentY == null) {
                    _verticalDragStartY = null;
                    _verticalDragCurrentY = null;
                    return;
                  }

                  final dy = _verticalDragCurrentY! - _verticalDragStartY!;
                  final vy = details.velocity.pixelsPerSecond.dy;

                  // 上方向のスワイプ（dyが負）で閾値を越えたらPop
                  final isSwipeUpDistance =
                      dy.abs() > _verticalSwipeDistanceThreshold && dy < 0;
                  final isSwipeUpVelocity =
                      vy < -_verticalSwipeVelocityThreshold;

                  if ((isSwipeUpDistance || isSwipeUpVelocity) && mounted) {
                    Navigator.of(context).pop();
                  }

                  _verticalDragStartY = null;
                  _verticalDragCurrentY = null;
                }
              : null,
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

              // 最新の画像パスを保存（オートスクロール機能のため）
              if (index < widget.imageFileList.length) {
                final currentImagePath = widget.imageFileList[index].path;
                final settings = Provider.of<SettingsProvider>(
                  context,
                  listen: false,
                );
                settings.setLastViewedImagePath(currentImagePath);
              }
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
                  child: Hero(
                    tag: 'imageHero_$index',
                    child: RepaintBoundary(child: Image.file(file)),
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
