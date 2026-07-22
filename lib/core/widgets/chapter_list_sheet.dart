import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_tokens.dart';
import '../models/episode.dart';

/// 显示章节目录底部面板，返回选中的章节索引；取消返回 null。
///
/// 增强功能（P0-2，向后兼容漫画调用）：
/// - [enableSearch]：章节标题搜索，支持正则（[regexSearch] 切换）。
/// - [bookmarkedIndices]：若提供，则在对应章节显示书签标记，并提供"仅看书签"过滤
///   （书签的"增/删"在小说阅读器底栏完成，此处负责查看/筛选/跳转）。
/// - 定位当前 / 置顶 / 置底 快捷按钮。
Future<int?> showChapterList(
  BuildContext context,
  List<Episode> chapters,
  int currentIndex, {
  bool enableSearch = true,
  Set<int>? bookmarkedIndices,
}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChapterListBody(
        chapters: chapters,
        currentIndex: currentIndex,
        enableSearch: enableSearch,
        bookmarkedIndices: bookmarkedIndices,
      ),
    );

class _ChapterListBody extends StatefulWidget {
  final List<Episode> chapters;
  final int currentIndex;
  final bool enableSearch;
  final Set<int>? bookmarkedIndices;

  const _ChapterListBody({
    required this.chapters,
    required this.currentIndex,
    this.enableSearch = true,
    this.bookmarkedIndices,
  });

  @override
  State<_ChapterListBody> createState() => _ChapterListBodyState();
}

class _ChapterListBodyState extends State<_ChapterListBody> {
  late final ScrollController _scrollController;
  final TextEditingController _searchController = TextEditingController();
  bool _regex = false;
  String _query = '';
  bool _bookmarksOnly = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // 打开后定位到当前阅读章节。
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateCurrent());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 当前可见（经搜索/书签过滤后）的章节索引列表。
  List<int> get _visibleIndexes {
    final result = <int>[];
    for (int i = 0; i < widget.chapters.length; i++) {
      if (_bookmarksOnly && widget.bookmarkedIndices != null) {
        if (!widget.bookmarkedIndices!.contains(i)) continue;
      }
      if (_query.isNotEmpty) {
        final title = widget.chapters[i].title;
        final matches = _regex
            ? _safeRegexMatch(_query, title)
            : title.toLowerCase().contains(_query.toLowerCase());
        if (!matches) continue;
      }
      result.add(i);
    }
    return result;
  }

  /// 正则匹配；非法正则退化为不区分大小写子串匹配，避免崩溃。
  bool _safeRegexMatch(String pattern, String text) {
    try {
      return RegExp(pattern, caseSensitive: false).hasMatch(text);
    } catch (_) {
      return text.toLowerCase().contains(pattern.toLowerCase());
    }
  }

  void _locateCurrent() {
    if (!_scrollController.hasClients) return;
    final idx = widget.currentIndex;
    if (idx < 0 || idx >= widget.chapters.length) return;
    // 按估算行高定位到当前章附近（ListTile 约 56 + 可选 subtitle）。
    const double rowH = 64.0;
    final offset = (idx * rowH).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      offset,
      duration: AppTokens.durFast,
      curve: Curves.easeInOut,
    );
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.7;
    final visible = _visibleIndexes;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.chapterList,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
            if (widget.enableSearch || widget.bookmarkedIndices != null)
              _buildToolbar(l10n),
            const Divider(height: 1),
            Expanded(
              child: visible.isEmpty
                  ? Center(child: Text(l10n.noSearchResults))
                  : ListView.builder(
                      controller: _scrollController,
                      shrinkWrap: true,
                      itemCount: visible.length,
                      itemBuilder: (BuildContext ctx, int i) {
                        final idx = visible[i];
                        final chapter = widget.chapters[idx];
                        final isCurrent = idx == widget.currentIndex;
                        final isBookmarked =
                            widget.bookmarkedIndices?.contains(idx) ?? false;
                        return ListTile(
                        leading: isCurrent
                            ? Icon(
                                Icons.play_arrow,
                                color: theme.colorScheme.primary,
                              )
                            : (isBookmarked
                                ? Tooltip(
                                    message: l10n.bookmarkedHint,
                                    child: Icon(
                                      Icons.bookmark,
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    ),
                                  )
                                : null),
                          title: Text(
                            chapter.title,
                            style: isCurrent
                                ? TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  )
                                : null,
                          ),
                          subtitle: (chapter.lineName != null &&
                                  chapter.lineName!.isNotEmpty)
                              ? Text(chapter.lineName!)
                              : null,
                          selected: isCurrent,
                          onTap: () => Navigator.of(context).pop(idx),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: <Widget>[
          if (widget.enableSearch)
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: l10n.searchChapter,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                IconButton(
                  tooltip: l10n.regexSearch,
                  isSelected: _regex,
                  color: _regex ? Theme.of(context).colorScheme.primary : null,
                  icon: const Icon(Icons.alternate_email),
                  onPressed: () => setState(() => _regex = !_regex),
                ),
              ],
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              ActionChip(
                label: Text(l10n.locateCurrent),
                onPressed: _locateCurrent,
              ),
              ActionChip(
                label: Text(l10n.scrollToTop),
                onPressed: _scrollToTop,
              ),
              ActionChip(
                label: Text(l10n.scrollToBottom),
                onPressed: _scrollToBottom,
              ),
              if (widget.bookmarkedIndices != null)
                FilterChip(
                  label: Text(l10n.filterBookmarked),
                  selected: _bookmarksOnly,
                  onSelected: (bool v) => setState(() => _bookmarksOnly = v),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
