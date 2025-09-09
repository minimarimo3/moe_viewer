import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import '../../../core/services/database_helper.dart';

class FullscreenSearchOverlay extends StatefulWidget {
  const FullscreenSearchOverlay({
    super.key,
    required this.initialQuery,
    required this.onSearchChanged,
    required this.onSearchCommitted,
    required this.onClose,
  });

  final String initialQuery;
  final void Function(String query) onSearchChanged;
  final void Function(String query) onSearchCommitted;
  final VoidCallback onClose;

  @override
  State<FullscreenSearchOverlay> createState() =>
      _FullscreenSearchOverlayState();
}

class _FullscreenSearchOverlayState extends State<FullscreenSearchOverlay>
    with TickerProviderStateMixin {
  late final TextEditingController _searchController;
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  final _db = DatabaseHelper.instance;
  List<String> _allTags = [];
  List<String> _suggestions = [];
  Timer? _searchDebounce;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _searchController = TextEditingController(text: widget.initialQuery);

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0.0, -1.0), end: Offset.zero).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    _loadTags();
    _animationController.forward();

    // 初期クエリがある場合は即座に検索を実行
    if (widget.initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateSuggestions();
        widget.onSearchChanged(widget.initialQuery);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      _allTags = await _db.getAllTags();
      setState(() {
        _isLoading = false;
      });
      if (widget.initialQuery.isNotEmpty) {
        _updateSuggestions();
      }
    } catch (e) {
      log('タグ読み込みエラー: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _updateSuggestions();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      widget.onSearchChanged(value);
    });
  }

  Future<void> _updateSuggestions() async {
    if (_isLoading) return;

    final raw = _searchController.text;
    final tokens = raw
        .split(RegExp(r"\s+"))
        .where((e) => e.isNotEmpty)
        .toList();
    final last = tokens.isEmpty ? '' : tokens.last.toLowerCase();

    if (last.isEmpty) {
      setState(() {
        _suggestions = [];
      });
      return;
    }

    try {
      // 1) 既存タグから一致（元の名前で）
      final fromTags = _allTags
          .where((t) => t.toLowerCase().contains(last))
          .take(20)
          .toList();

      // 2) 別名から一致するタグを検索
      final matchedByAlias = await _db.searchTagsByDisplayName(last);

      // 3) 別名を表示用に変換
      final aliasesMap = await _db.getAllTagAliases();
      final displayTags = <String>[];

      // まず別名で表示できるもの
      for (final tag in matchedByAlias) {
        final alias = aliasesMap[tag];
        if (alias != null && alias.toLowerCase().contains(last)) {
          displayTags.add(alias);
        }
      }

      // 次に元のタグ名で一致するもの（別名がある場合は別名で表示）
      for (final tag in fromTags) {
        final displayName = aliasesMap[tag] ?? tag;
        if (!displayTags.contains(displayName)) {
          displayTags.add(displayName);
        }
      }

      setState(() {
        _suggestions = displayTags.take(20).toList();
      });
    } catch (e) {
      log('サジェスト更新エラー: $e');
    }
  }

  void _insertSuggestion(String tag) {
    final raw = _searchController.text.trimRight();
    final parts = raw.split(RegExp(r"\s+")).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) {
      _searchController.text = tag;
    } else {
      parts.removeLast();
      parts.add(tag);
      _searchController.text = parts.join(' ');
    }
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: _searchController.text.length),
    );
    _updateSuggestions();
    widget.onSearchChanged(_searchController.text);
  }

  void _commitSearch() {
    widget.onSearchCommitted(_searchController.text.trim());
    _close();
  }

  void _clearInput() {
    _searchController.clear();
    setState(() {
      _suggestions = [];
    });
    widget.onSearchChanged('');
  }

  Future<void> _close() async {
    await _animationController.reverse();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          await _close();
        }
      },
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Material(
          color: theme.colorScheme.surface,
          child: SafeArea(
            child: Column(
              children: [
                // 検索ヘッダー
                SlideTransition(
                  position: _slideAnimation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: theme.shadowColor.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: _close,
                          tooltip: '検索を閉じる',
                        ),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: 'タグで検索（スペース区切りでAND）',
                              border: InputBorder.none,
                              hintStyle: TextStyle(color: theme.hintColor),
                            ),
                            style: theme.textTheme.bodyLarge,
                            textInputAction: TextInputAction.search,
                            onChanged: _onSearchChanged,
                            onSubmitted: (_) => _commitSearch(),
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: _clearInput,
                            tooltip: '入力をクリア',
                          ),
                        IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: _commitSearch,
                          tooltip: '検索実行',
                        ),
                      ],
                    ),
                  ),
                ),

                // サジェストリスト
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _suggestions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search,
                                size: 64,
                                color: theme.hintColor,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isEmpty
                                    ? 'タグを入力して検索してください'
                                    : 'マッチするタグが見つかりません',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(
                            left: 16.0,
                            right: 16.0,
                            bottom: 16.0,
                          ),
                          itemCount: _suggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = _suggestions[index];
                            return ListTile(
                              leading: Icon(
                                Icons.tag,
                                color: theme.colorScheme.primary,
                              ),
                              title: Text(
                                suggestion,
                                style: theme.textTheme.bodyLarge,
                              ),
                              onTap: () => _insertSuggestion(suggestion),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
