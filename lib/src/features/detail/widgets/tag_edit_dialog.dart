import 'package:flutter/material.dart';
import '../../../core/services/database_helper.dart';
import '../../../core/services/nsfw_service.dart';
import '../../../core/utils/tag_category_utils.dart';

class TagEditDialog extends StatefulWidget {
  final String imagePath;

  const TagEditDialog({super.key, required this.imagePath});

  @override
  State<TagEditDialog> createState() => _TagEditDialogState();
}

class _TagEditDialogState extends State<TagEditDialog> {
  List<String> _aiTags = [];
  List<String> _aiCharacterTags = [];
  List<String> _aiFeatureTags = [];
  List<String> _manualTags = [];
  List<String> _allAvailableTags = [];
  List<String> _filteredSuggestions = [];
  Map<String, String> _tagAliases = {}; // タグ別名のキャッシュ
  Map<String, dynamic>? _nsfwRating; // NSFW判定データ
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = true;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _loadTags();
    _textController.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      await TagCategoryUtils.ensureLoaded();
      final db = DatabaseHelper.instance;
      final allTags = await db.getAllTagsWithCategoriesForPath(
        widget.imagePath,
      );
      final availableTags = await db.getAllTags();
      final aliases = await db.getAllTagAliases();

      // NSFW判定を取得（既存のNSFWデータベース + 特殊タグからも取得）
      Map<String, dynamic>? nsfwRating = await db.getNsfwRating(
        widget.imagePath,
      );

      // 既存のNSFW判定がない場合、特殊タグから取得
      if (nsfwRating == null) {
        final nsfwFromTags = await NsfwService.instance.getNsfwRatingFromTags(
          widget.imagePath,
        );
        if (nsfwFromTags != null) {
          nsfwRating = {
            'isNsfw': nsfwFromTags,
            'isManual': false, // 特殊タグからの取得はAI判定として扱う
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          };
        }
      }

      // 予約タグを分離してマニュアルタグに統合するが、お気に入りタグは除外
      final rawAiTags = allTags['ai'] ?? [];
      final rawManualTags = allTags['manual'] ?? [];

      // rating系タグを除外
      final filteredRawAiTags = rawAiTags
          .where((tag) => !tag.startsWith('rating_'))
          .toList();

      final categorized = TagCategoryUtils.categorizeAiTags(filteredRawAiTags);
      final userTags = categorized['user'] ?? [];
      final filteredAiTags = filteredRawAiTags
          .where((tag) => !userTags.contains(tag))
          .toList();

      // マニュアルタグに予約タグを統合するが、お気に入りタグとNSFWタグは除外
      final nonSpecialUserTags = userTags
          .where(
            (tag) =>
                !TagCategoryUtils.isFavoriteTag(tag) &&
                !TagCategoryUtils.isNsfwTag(tag),
          )
          .toList();
      final filteredRawManualTags = rawManualTags
          .where(
            (tag) =>
                !TagCategoryUtils.isFavoriteTag(tag) &&
                !TagCategoryUtils.isNsfwTag(tag),
          )
          .toList();
      final combinedManualTags = <String>[
        ...filteredRawManualTags,
        ...nonSpecialUserTags,
      ];

      setState(() {
        _aiTags = filteredAiTags;
        _aiCharacterTags = allTags['aiCharacter'] ?? [];
        _aiFeatureTags = allTags['aiFeature'] ?? [];
        _manualTags = combinedManualTags;
        _allAvailableTags = availableTags;
        _tagAliases = aliases;
        _nsfwRating = nsfwRating;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onTextChanged() {
    final text = _textController.text.trim().toLowerCase();
    if (text.isEmpty) {
      setState(() {
        _filteredSuggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    final suggestions = _allAvailableTags
        .where(
          (tag) =>
              tag.toLowerCase().contains(text) &&
              !_manualTags.contains(tag) &&
              !_aiTags.contains(tag),
        )
        .take(10)
        .toList();

    setState(() {
      _filteredSuggestions = suggestions;
      _showSuggestions = suggestions.isNotEmpty;
    });
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      setState(() {
        _showSuggestions = false;
      });
    } else {
      _onTextChanged(); // フォーカス時にサジェストを更新
    }
  }

  Future<void> _addTag(String tag) async {
    if (tag.trim().isEmpty) return;
    if (_manualTags.contains(tag) || _aiTags.contains(tag)) return;

    try {
      await DatabaseHelper.instance.addManualTag(widget.imagePath, tag);
      setState(() {
        _manualTags.add(tag);
        _textController.clear();
        _showSuggestions = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('タグの追加に失敗しました: $e')));
      }
    }
  }

  Future<void> _removeTag(String tag, {bool isAiTag = false}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('タグを削除'),
        content: Text(
          '「$tag」を削除しますか？${isAiTag ? '\n（AIタグは非表示になりますが、復元可能です）' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (isAiTag) {
        await DatabaseHelper.instance.deleteAiTag(widget.imagePath, tag);
        setState(() {
          _aiTags.remove(tag);
        });
      } else {
        await DatabaseHelper.instance.removeManualTag(widget.imagePath, tag);
        setState(() {
          _manualTags.remove(tag);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('タグの削除に失敗しました: $e')));
      }
    }
  }

  Widget _buildTagChip(String tag, {bool isManual = false}) {
    final displayName = _tagAliases[tag] ?? tag;

    return Chip(
      label: GestureDetector(
        onTap: () => _showTagAliasDialog(tag),
        child: Text(displayName),
      ),
      backgroundColor: isManual
          ? Theme.of(context).colorScheme.secondaryContainer
          : Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.7),
      deleteIcon: const Icon(Icons.close, size: 18),
      onDeleted: () => _showTagDeleteDialog(tag, isAiTag: !isManual),
      labelStyle: TextStyle(
        fontSize: 13,
        color: isManual
            ? Theme.of(context).colorScheme.onSecondaryContainer
            : Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
  }

  Widget _buildSuggestionsOverlay() {
    if (!_showSuggestions || _filteredSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _filteredSuggestions.length,
        itemBuilder: (context, index) {
          final suggestion = _filteredSuggestions[index];
          return ListTile(
            dense: true,
            title: Text(suggestion),
            onTap: () {
              _addTag(suggestion);
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'タグ編集',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              // タグ追加セクション
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      decoration: const InputDecoration(
                        hintText: 'タグを追加...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: _addTag,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _addTag(_textController.text),
                  ),
                ],
              ),

              // サジェスト
              _buildSuggestionsOverlay(),

              const SizedBox(height: 24),

              // タグ表示セクション
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 手動タグセクション
                      if (_manualTags.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.edit, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'ユーザータグ (${_manualTags.length}個)',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          children: _manualTags
                              .map((tag) => _buildTagChip(tag, isManual: true))
                              .toList(),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // NSFW判定セクション
                      Row(
                        children: [
                          const Icon(Icons.security, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'NSFW判定',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _updateNsfwRating(false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 12.0,
                                ),
                                decoration: BoxDecoration(
                                  color: (_nsfwRating?['isNsfw'] == false)
                                      ? Colors.grey.withValues(alpha: 0.3)
                                      : Colors.grey.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8.0),
                                  border: Border.all(
                                    color: (_nsfwRating?['isNsfw'] == false)
                                        ? Colors.grey[600]!
                                        : Colors.grey.withValues(alpha: 0.3),
                                    width: (_nsfwRating?['isNsfw'] == false)
                                        ? 2.0
                                        : 1.0,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.child_friendly,
                                      color: Colors.grey[600],
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8.0),
                                    Text(
                                      'U-18',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _updateNsfwRating(true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 12.0,
                                ),
                                decoration: BoxDecoration(
                                  color: (_nsfwRating?['isNsfw'] == true)
                                      ? Colors.pink.withValues(alpha: 0.3)
                                      : Colors.pink.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8.0),
                                  border: Border.all(
                                    color: (_nsfwRating?['isNsfw'] == true)
                                        ? Colors.pink[300]!
                                        : Colors.pink.withValues(alpha: 0.3),
                                    width: (_nsfwRating?['isNsfw'] == true)
                                        ? 2.0
                                        : 1.0,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.favorite,
                                      color: Colors.pink[300],
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8.0),
                                    Text(
                                      '官能的',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.pink[300],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_nsfwRating != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          (_nsfwRating!['isManual'] as bool)
                              ? '手動設定済み'
                              : 'AI判定',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // AIキャラタグセクション
                      if (_aiTags.isNotEmpty) ...[..._buildAiTagSections()],

                      // タグがない場合のメッセージ
                      if (_manualTags.isEmpty && _aiTags.isEmpty)
                        const Center(
                          child: Text(
                            'タグがありません\n上の入力欄でタグを追加してください',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAiTagSections() {
    // 分類済みタグが利用可能な場合はそれを使用、そうでない場合は従来の方法で分類
    List<String> aiCharacterTags;
    List<String> aiFeatureTags;

    if (_aiCharacterTags.isNotEmpty || _aiFeatureTags.isNotEmpty) {
      // データベースから分類済みタグを使用
      aiCharacterTags = _aiCharacterTags;
      aiFeatureTags = _aiFeatureTags;
    } else {
      // 従来の方法で分類（後方互換性のため）
      final categorizedTags = TagCategoryUtils.categorizeAiTags(_aiTags);
      aiCharacterTags = categorizedTags['character'] ?? [];
      aiFeatureTags = categorizedTags['feature'] ?? [];
    }

    final List<Widget> sections = [];

    // AIキャラタグセクション
    if (aiCharacterTags.isNotEmpty) {
      sections.addAll([
        Row(
          children: [
            const Icon(Icons.person_outlined, size: 20),
            const SizedBox(width: 8),
            Text(
              'AIキャラタグ (${aiCharacterTags.length}個)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: aiCharacterTags
              .map((tag) => _buildTagChip(tag, isManual: false))
              .toList(),
        ),
        const SizedBox(height: 24),
      ]);
    }

    // AI特徴タグセクション
    if (aiFeatureTags.isNotEmpty) {
      sections.addAll([
        Row(
          children: [
            const Icon(Icons.psychology_outlined, size: 20),
            const SizedBox(width: 8),
            Text(
              'AI特徴タグ (${aiFeatureTags.length}個)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: aiFeatureTags
              .map((tag) => _buildTagChip(tag, isManual: false))
              .toList(),
        ),
      ]);
    }

    return sections;
  }

  /// タグの別名設定ダイアログを表示
  Future<void> _showTagAliasDialog(String tag) async {
    final TextEditingController aliasController = TextEditingController();
    final currentAlias = _tagAliases[tag];
    aliasController.text = currentAlias ?? '';

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('タグ「$tag」の別名'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('元のタグ名: $tag'),
            const SizedBox(height: 16),
            TextField(
              controller: aliasController,
              decoration: const InputDecoration(
                labelText: '別名',
                hintText: '別名を入力してください',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          if (currentAlias != null)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('別名を削除'),
            ),
          TextButton(
            onPressed: () {
              final alias = aliasController.text.trim();
              Navigator.pop(context, alias.isEmpty ? null : alias);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _setTagAlias(tag, result.isEmpty ? null : result);
    }
  }

  /// タグ削除ダイアログを表示（タグ削除 vs 別名削除を選択可能）
  Future<void> _showTagDeleteDialog(String tag, {bool isAiTag = false}) async {
    final hasAlias = _tagAliases.containsKey(tag);
    final displayName = _tagAliases[tag] ?? tag;

    List<Widget> actions = [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
    ];

    if (hasAlias) {
      actions.addAll([
        TextButton(
          onPressed: () => Navigator.pop(context, 'remove_alias'),
          child: const Text('別名を削除'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'remove_tag'),
          child: const Text('タグを削除'),
        ),
      ]);
    } else {
      actions.add(
        TextButton(
          onPressed: () => Navigator.pop(context, 'remove_tag'),
          child: const Text('削除'),
        ),
      );
    }

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除操作'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('タグ: $displayName'),
            if (hasAlias) ...[
              const SizedBox(height: 8),
              Text('元のタグ名: $tag'),
              const SizedBox(height: 16),
              const Text('削除する内容を選択してください：'),
            ] else ...[
              const SizedBox(height: 16),
              Text(
                '「$displayName」を削除しますか？${isAiTag ? '\n（AIタグは非表示になりますが、復元可能です）' : ''}',
              ),
            ],
          ],
        ),
        actions: actions,
      ),
    );

    if (result == 'remove_alias') {
      await _setTagAlias(tag, null);
    } else if (result == 'remove_tag') {
      await _removeTag(tag, isAiTag: isAiTag);
    }
  }

  /// タグの別名を設定
  Future<void> _setTagAlias(String tag, String? alias) async {
    try {
      final db = DatabaseHelper.instance;
      if (alias != null && alias.isNotEmpty) {
        await db.setTagAlias(tag, alias);
        setState(() {
          _tagAliases[tag] = alias;
        });
      } else {
        await db.removeTagAlias(tag);
        setState(() {
          _tagAliases.remove(tag);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('別名の設定に失敗しました: $e')));
      }
    }
  }

  /// NSFW判定を変更
  Future<void> _updateNsfwRating(bool isNsfw) async {
    try {
      // 特殊タグとしてNSFW判定を設定
      await NsfwService.instance.setManualNsfwRatingAsTags(
        widget.imagePath,
        isNsfw,
      );

      setState(() {
        _nsfwRating = {
          'isNsfw': isNsfw,
          'isManual': true,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        };
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('NSFW判定の更新に失敗しました: $e')));
      }
    }
  }
}
