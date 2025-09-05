import 'package:flutter/material.dart';
import '../../../core/services/database_helper.dart';

class TagEditDialog extends StatefulWidget {
  final String imagePath;

  const TagEditDialog({super.key, required this.imagePath});

  @override
  State<TagEditDialog> createState() => _TagEditDialogState();
}

class _TagEditDialogState extends State<TagEditDialog> {
  List<String> _aiTags = [];
  List<String> _manualTags = [];
  List<String> _allAvailableTags = [];
  List<String> _filteredSuggestions = [];
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
      final db = DatabaseHelper.instance;
      final allTags = await db.getAllTagsForPath(widget.imagePath);
      final availableTags = await db.getAllTags();

      setState(() {
        _aiTags = allTags['ai'] ?? [];
        _manualTags = allTags['manual'] ?? [];
        _allAvailableTags = availableTags;
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
    return Chip(
      label: Text(tag),
      backgroundColor: isManual
          ? Theme.of(context).colorScheme.secondaryContainer
          : Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.7),
      deleteIcon: const Icon(Icons.close, size: 18),
      onDeleted: () => _removeTag(tag, isAiTag: !isManual),
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
                              '手動タグ (${_manualTags.length}個)',
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

                      // AIタグセクション
                      if (_aiTags.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.psychology_outlined, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'AIによる解析タグ (${_aiTags.length}個)',
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
                          children: _aiTags
                              .map((tag) => _buildTagChip(tag, isManual: false))
                              .toList(),
                        ),
                      ],

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
}
