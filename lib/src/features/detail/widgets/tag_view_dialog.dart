import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/database_helper.dart';
import '../../../core/services/nsfw_service.dart';
import '../../../core/utils/tag_category_utils.dart';
import 'tag_edit_dialog.dart';

class TagViewDialog extends StatefulWidget {
  final String imagePath;

  const TagViewDialog({super.key, required this.imagePath});

  @override
  State<TagViewDialog> createState() => _TagViewDialogState();
}

class _TagViewDialogState extends State<TagViewDialog>
    with TickerProviderStateMixin {
  List<String> _aiTags = [];
  List<String> _aiCharacterTags = [];
  List<String> _aiFeatureTags = [];
  List<String> _manualTags = [];
  Map<String, String> _tagAliases = {};
  Map<String, dynamic>? _nsfwRating;
  bool _isLoading = true;
  String _searchQuery = '';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _loadTags();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      await TagCategoryUtils.ensureLoaded();
      final db = DatabaseHelper.instance;
      final allTags = await db.getAllTagsWithCategoriesForPath(
        widget.imagePath,
      );
      final aliases = await db.getAllTagAliases();

      // NSFW判定を取得
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
            'isManual': false,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          };
        }
      }

      // タグの分類処理
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
        _tagAliases = aliases;
        _nsfwRating = nsfwRating;
        _isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getDisplayText(String tag) {
    // エイリアスがあればそれを表示、なければ元のタグ
    if (_tagAliases.containsKey(tag)) {
      return _tagAliases[tag]!;
    }
    return tag;
  }

  Color _getTagColor(String tag) {
    final theme = Theme.of(context);
    if (_aiCharacterTags.contains(tag)) {
      return theme.colorScheme.secondaryContainer;
    } else if (_aiFeatureTags.contains(tag)) {
      return theme.colorScheme.primaryContainer;
    } else if (_aiTags.contains(tag)) {
      return theme.colorScheme.tertiaryContainer;
    } else {
      return theme.colorScheme.surfaceContainerHigh;
    }
  }

  Color _getTagBorderColor(String tag) {
    final theme = Theme.of(context);
    if (_aiCharacterTags.contains(tag)) {
      return theme.colorScheme.secondary.withValues(alpha: 0.3);
    } else if (_aiFeatureTags.contains(tag)) {
      return theme.colorScheme.primary.withValues(alpha: 0.3);
    } else if (_aiTags.contains(tag)) {
      return theme.colorScheme.tertiary.withValues(alpha: 0.3);
    } else {
      return theme.colorScheme.outline.withValues(alpha: 0.3);
    }
  }

  Color _getTagTextColor(String tag) {
    final theme = Theme.of(context);
    if (_aiCharacterTags.contains(tag)) {
      return theme.colorScheme.onSecondaryContainer;
    } else if (_aiFeatureTags.contains(tag)) {
      return theme.colorScheme.onPrimaryContainer;
    } else if (_aiTags.contains(tag)) {
      return theme.colorScheme.onTertiaryContainer;
    } else {
      return theme.colorScheme.onSurface;
    }
  }

  List<String> _getFilteredTags(List<String> tags) {
    if (_searchQuery.isEmpty) return tags;
    return tags.where((tag) {
      final displayText = _getDisplayText(tag).toLowerCase();
      final originalTag = tag.toLowerCase();
      final query = _searchQuery.toLowerCase();
      return displayText.contains(query) || originalTag.contains(query);
    }).toList();
  }

  Widget _buildTagChip(String tag, {VoidCallback? onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap:
          onTap ??
          () {
            HapticFeedback.lightImpact();
            // 将来的にここで検索機能を実装
          },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _getTagColor(tag),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _getTagBorderColor(tag), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_getTagIcon(tag), size: 12, color: _getTagTextColor(tag)),
            const SizedBox(width: 4),
            Text(
              _getDisplayText(tag),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _getTagTextColor(tag),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getTagIcon(String tag) {
    if (_aiCharacterTags.contains(tag)) {
      return Icons.person;
    } else if (_aiFeatureTags.contains(tag)) {
      return Icons.auto_awesome;
    } else if (_aiTags.contains(tag)) {
      return Icons.smart_toy;
    } else {
      return Icons.label;
    }
  }

  Widget _buildTagSection(
    String title,
    List<String> tags, {
    Color? color,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    final filteredTags = _getFilteredTags(tags);
    if (filteredTags.isEmpty && _searchQuery.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: color ?? theme.colorScheme.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color ?? theme.colorScheme.onSurface,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${filteredTags.length}個',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          if (filteredTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filteredTags.map((tag) => _buildTagChip(tag)).toList(),
            ),
          ] else if (_searchQuery.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_off,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '検索条件に一致するタグがありません',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNsfwSection() {
    if (_nsfwRating == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isNsfw = _nsfwRating!['isNsfw'] as bool? ?? false;
    final isManual = _nsfwRating!['isManual'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'コンテンツ判定',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isNsfw
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  isNsfw ? Icons.warning_rounded : Icons.verified_user_rounded,
                  size: 20,
                  color: isNsfw
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isNsfw ? 'NSFW' : 'Safe',
                        style: TextStyle(
                          color: isNsfw
                              ? theme.colorScheme.onErrorContainer
                              : theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        isNsfw ? '成人向けコンテンツ' : '全年齢向けコンテンツ',
                        style: TextStyle(
                          color: isNsfw
                              ? theme.colorScheme.onErrorContainer.withValues(
                                  alpha: 0.8,
                                )
                              : theme.colorScheme.onPrimaryContainer.withValues(
                                  alpha: 0.8,
                                ),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isManual)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'AI判定',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /*
  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            color: theme.colorScheme.onSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'タグを検索...',
                border: InputBorder.none,
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.clear,
                color: theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                });
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }
  */

  Widget _buildStatsBar() {
    final theme = Theme.of(context);
    final totalTags =
        _manualTags.length +
        _aiCharacterTags.length +
        _aiFeatureTags.length +
        _aiTags.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            '合計',
            totalTags,
            Icons.label,
            theme.colorScheme.primary,
          ),
          _buildStatItem(
            'ユーザー',
            _manualTags.length,
            Icons.edit,
            theme.colorScheme.secondary,
          ),
          _buildStatItem(
            'キャラクター',
            _aiCharacterTags.length,
            Icons.person,
            theme.colorScheme.tertiary,
          ),
          _buildStatItem(
            'AI',
            _aiTags.length + _aiFeatureTags.length,
            Icons.smart_toy,
            theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'タグ一覧',
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
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'タグを読み込み中...',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatsBar(),
                        // _buildSearchBar(),
                        _buildNsfwSection(),
                        _buildTagSection(
                          'ユーザータグ',
                          _manualTags,
                          color: Theme.of(context).colorScheme.secondary,
                          icon: Icons.edit,
                        ),
                        _buildTagSection(
                          'キャラクタータグ',
                          _aiCharacterTags,
                          color: Theme.of(context).colorScheme.tertiary,
                          icon: Icons.person,
                        ),
                        _buildTagSection(
                          '特徴タグ',
                          _aiFeatureTags,
                          color: Theme.of(context).colorScheme.primary,
                          icon: Icons.auto_awesome,
                        ),
                        _buildTagSection(
                          'AIタグ',
                          _aiTags,
                          color: Theme.of(context).colorScheme.primary,
                          icon: Icons.smart_toy,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // フッター
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('閉じる'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await showDialog(
                        context: context,
                        builder: (context) =>
                            TagEditDialog(imagePath: widget.imagePath),
                      );
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('編集'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
