/// 详情页共享章节列表组件（M16.5 筛选/排序/显示全面增强）。
///
/// 提供"搜索框 + 筛选/排序/显示组合按钮 + 章节 ListTile + 行尾操作按钮"的
/// 统一布局，供 [ContentDetailScreen] / [ComicDetailScreen] /
/// [NovelDetailScreen] 复用。
///
/// 行尾三按钮（下载单章 / 书签 / 已读）通过回调按需启用：传入 null 则不渲染。
/// 已读条目自动降低不透明度（[Opacity(0.5)]）。
/// 非默认筛选/排序/显示设置时按钮上显示角标 dot。
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../history/chapter_fetch_time_manager.dart';
import '../models/episode.dart';
import '../theme/app_tokens.dart';
import 'detail_list_filter.dart';

/// 章节列表区。支持搜索过滤 + 筛选/排序/显示组合 + 可选的线路分组。
class ChapterListSection extends StatefulWidget {
  /// 全部章节（未排序前的原始顺序，通常为源返回顺序）。
  final List<Episode> chapters;

  /// 是否按线路（[Episode.lineName]）分组展示（影视多线路场景）。
  final bool groupByLine;

  /// 点击章节行体。
  final void Function(Episode ep, int originalIndex) onTapChapter;

  /// 下载单章回调（null 时不显示下载按钮）。
  final Future<void> Function(Episode ep, int originalIndex)? onDownloadChapter;

  /// 切换书签回调（null 时不显示书签按钮）。
  final Future<void> Function(Episode ep, int originalIndex)? onToggleBookmark;

  /// 查询某章是否有书签（null 时不显示书签按钮）。
  final bool Function(int originalIndex)? isChapterBookmarked;

  /// 切换已读回调（null 时不显示已读按钮）。
  final Future<void> Function(Episode ep, int originalIndex)? onToggleRead;

  /// 查询某章是否已读（null 时不显示已读按钮）。
  final bool Function(int originalIndex)? isChapterRead;

  /// 查询某章是否已下载（用于下载按钮的图标状态）。
  final bool Function(int originalIndex)? isChapterDownloaded;

  /// 单位词（如"章"或"集"），用于筛选弹窗的排序/显示标签。
  final String unitWord;

  /// 是否多源混合（true 时显示"按来源排序"和"显示来源标题"选项）。
  final bool isMultiSource;

  /// 是否启用网格/列表切换（默认 false；影视类设 true）。
  final bool enableGridMode;

  /// 内容 ID（用于查询每集播放进度，可选）。
  final String? contentId;

  /// 返回某集的播放位置（毫秒），0 表示无记录。null 时不显示进度指示。
  final int Function(int originalIndex)? getPosition;

  const ChapterListSection({
    super.key,
    required this.chapters,
    required this.onTapChapter,
    this.groupByLine = false,
    this.onDownloadChapter,
    this.onToggleBookmark,
    this.isChapterBookmarked,
    this.onToggleRead,
    this.isChapterRead,
    this.isChapterDownloaded,
    this.unitWord = '',
    this.isMultiSource = false,
    this.enableGridMode = false,
    this.contentId,
    this.getPosition,
  });

  @override
  State<ChapterListSection> createState() => _ChapterListSectionState();
}

class _ChapterListSectionState extends State<ChapterListSection> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  DetailListQuery _filterQuery = const DetailListQuery();

  /// 网格/列表显示模式（仅当 [ChapterListSection.enableGridMode] 为 true 时可切换）。
  bool _isGridMode = false;

  /// 快捷选集区间（null 表示显示全部）。
  int? _rangeStart;
  static const int _rangeSize = 12;

  /// 当前选中的线路（null 表示全部线路）。仅当 [groupByLine] 且线路数 > 1 时有效。
  String? _selectedLine;

  /// 区间 chips 横向滚动控制器（选中后自动居中）。
  final ScrollController _chipScrollCtrl = ScrollController();

  /// 本地首次获取时间（毫秒），key = 章节 [Episode.id]。
  /// 当源未提供 [Episode.updatedAt] 时用作兜底展示，且只在首次加载时记录。
  final Map<String, int> _localFetchTimes = <String, int>{};

  @override
  void initState() {
    super.initState();
    _loadLocalFetchTimes();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _chipScrollCtrl.dispose();
    super.dispose();
  }

  /// 源未提供更新时间时，记录并缓存"本地首次获取时间"，之后不再变动。
  Future<void> _loadLocalFetchTimes() async {
    final contentId = widget.contentId;
    if (contentId == null) return;
    final mgr = ChapterFetchTimeManager();
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final ep in widget.chapters) {
      if (ep.updatedAt != null || ep.id.isEmpty) continue;
      final t = await mgr.recordIfAbsent(contentId, ep.id, now);
      if (_localFetchTimes[ep.id] != t) {
        _localFetchTimes[ep.id] = t;
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  /// 章节的有效更新时间：优先源提供的 [Episode.updatedAt]，否则用本地首次获取时间。
  DateTime? _effectiveUpdatedAt(int index) {
    final ep = widget.chapters[index];
    if (ep.updatedAt != null) return ep.updatedAt;
    final contentId = widget.contentId;
    if (contentId != null) {
      final t = _localFetchTimes[ep.id];
      if (t != null) return DateTime.fromMillisecondsSinceEpoch(t);
    }
    return null;
  }

  /// 格式化每章更新时间。当天显示 HH:mm，否则显示 YYYY-MM-DD。
  String _formatChapterDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${two(dt.hour)}:${two(dt.minute)}';
    }
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }

  /// 对原始索引列表应用搜索 + 筛选 + 排序 + 区间过滤。
  List<int> _processIndices(List<Episode> source, List<int> indices) {
    var result = indices;

    // 快捷选集区间过滤
    if (_rangeStart != null) {
      result = result
          .where((i) => i >= _rangeStart! && i < _rangeStart! + _rangeSize)
          .toList();
    }

    // 搜索过滤
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result
          .where((i) => source[i].title.toLowerCase().contains(q))
          .toList();
    }

    // 筛选过滤
    final f = _filterQuery.filter;
    if (!f.isEmpty) {
      result = result.where((i) {
        if (f.unread && widget.isChapterRead != null && widget.isChapterRead!(i)) {
          return false;
        }
        if (f.downloaded &&
            (widget.isChapterDownloaded == null || !widget.isChapterDownloaded!(i))) {
          return false;
        }
        if (f.bookmarked &&
            (widget.isChapterBookmarked == null || !widget.isChapterBookmarked!(i))) {
          return false;
        }
        return true;
      }).toList();
    }

    // 排序
    final s = _filterQuery.sort;
    if (s.key == DetailSortKey.byIndex) {
      if (s.descending) result = result.reversed.toList();
    } else {
      result.sort((a, b) {
        int cmp;
        switch (s.key) {
          case DetailSortKey.name:
            cmp = source[a].title.compareTo(source[b].title);
            break;
          case DetailSortKey.uploadDate:
            final aDate = _effectiveUpdatedAt(a);
            final bDate = _effectiveUpdatedAt(b);
            if (aDate == null && bDate == null) {
              cmp = 0;
            } else if (aDate == null) {
              cmp = 1;
            } else if (bDate == null) {
              cmp = -1;
            } else {
              cmp = aDate.compareTo(bDate);
            }
            break;
          case DetailSortKey.source:
            final aLine = source[a].lineName ?? '';
            final bLine = source[b].lineName ?? '';
            cmp = aLine.compareTo(bLine);
            break;
          case DetailSortKey.byIndex:
            cmp = 0;
            break;
        }
        return s.descending ? -cmp : cmp;
      });
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    if (widget.chapters.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Center(child: Text(l10n.emptyContent)),
      );
    }

    // 按线路分组
    if (widget.groupByLine) {
      final lines = <String, List<int>>{};
      for (var i = 0; i < widget.chapters.length; i++) {
        final line = widget.chapters[i].lineName ?? l10n.defaultLine;
        lines.putIfAbsent(line, () => <int>[]).add(i);
      }

      // 多线路（>1）时，在选集上方显示线路选择 chips。
      final bool showChips = lines.length > 1;
      // 当前选中线路对应的分组（null = 全部线路）。
      final renderLines = _selectedLine == null
          ? lines
          : (lines.containsKey(_selectedLine)
              ? <String, List<int>>{_selectedLine!: lines[_selectedLine]!}
              : lines);

      // 对每组的索引应用搜索 + 筛选 + 排序
      final processedLines = <String, List<int>>{};
      for (final entry in renderLines.entries) {
        final processed = _processIndices(widget.chapters, entry.value);
        if (processed.isNotEmpty) {
          processedLines[entry.key] = processed;
        }
      }

      final List<Widget> children = <Widget>[
        _buildSearchBar(context, l10n, scheme),
      ];
      if (showChips) {
        children.add(_buildLineChips(context, l10n, scheme, lines.keys.toList()));
      }
      for (final entry in processedLines.entries) {
        // 仅"全部线路"模式（且显示 chips 时）保留分组标题；选中单线路时由 chip 标明。
        if (showChips && _selectedLine == null) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceLg, AppTokens.spaceMd, AppTokens.spaceLg, AppTokens.spaceSm),
              child: Text(
                l10n.episodesWithLine(entry.key),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }
        children.addAll(_buildChapterTiles(context, l10n, scheme, entry.value));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

    final indices = _processIndices(
      widget.chapters,
      List<int>.generate(widget.chapters.length, (i) => i),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildSearchBar(context, l10n, scheme),
        _buildRangeChips(context, l10n, scheme, widget.chapters.length),
        if (indices.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: Center(child: Text(l10n.noChaptersFound)),
          )
        else if (_isGridMode && widget.enableGridMode)
          _buildChapterGrid(context, l10n, scheme, indices)
        else
          ..._buildChapterTiles(context, l10n, scheme, indices),
      ],
    );
  }

  Widget _buildSearchBar(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceLg, vertical: AppTokens.spaceSm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.searchChapter,
                prefixIcon: const Icon(Icons.search, size: 20),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceSm, vertical: AppTokens.spaceXs),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          // 筛选/排序/显示组合按钮
          Stack(
            children: <Widget>[
              IconButton(
                tooltip: l10n.filterTitle,
                icon: const Icon(Icons.tune, size: 22),
                onPressed: () async {
                  final result = await DetailListFilterSheet.show(
                    context,
                    initialQuery: _filterQuery,
                    unitWord: widget.unitWord,
                    isMultiSource: widget.isMultiSource,
                  );
                  if (result != null) {
                    setState(() => _filterQuery = result);
                  }
                },
              ),
              // 非默认设置时显示角标 dot
              if (!_filterQuery.isDefault)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          // 网格/列表切换
          if (widget.enableGridMode)
            IconButton(
              icon: Icon(
                _isGridMode ? Icons.view_list : Icons.grid_view,
                size: 22,
              ),
              tooltip: _isGridMode ? l10n.listView : l10n.gridView,
              onPressed: () => setState(() => _isGridMode = !_isGridMode),
            ),
        ],
      ),
    );
  }

  /// 快捷选集区间 chips（章节数 > 2 × rangeSize 时显示）。
  Widget _buildRangeChips(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
    int totalCount,
  ) {
    if (totalCount <= _rangeSize * 2) return const SizedBox.shrink();
    final ranges = <int>[];
    for (int i = 0; i < totalCount; i += _rangeSize) {
      ranges.add(i);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceLg, vertical: AppTokens.spaceXs),
      child: SizedBox(
        width: MediaQuery.of(context).size.width - AppTokens.spaceLg * 2,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _chipScrollCtrl,
          child: Row(
            children: <Widget>[
              FilterChip(
                label: Text(l10n.all),
                selected: _rangeStart == null,
                onSelected: (_) {
                  setState(() => _rangeStart = null);
                  _scrollChipToCenter(0);
                },
              ),
              const SizedBox(width: AppTokens.spaceSm),
              for (final start in ranges) ...<Widget>[
                FilterChip(
                  label: Text(
                      '${start + 1}-${start + _rangeSize > totalCount ? totalCount : start + _rangeSize}'),
                  selected: _rangeStart == start,
                  onSelected: (_) {
                    setState(() => _rangeStart = start);
                    _scrollChipToCenter(ranges.indexOf(start) + 1);
                  },
                ),
                const SizedBox(width: AppTokens.spaceSm),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 将区间 chips 滚动到选中项居中显示。
  void _scrollChipToCenter(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chipScrollCtrl.hasClients) return;
      const chipExtent = 80.0;
      final targetOffset =
          index * chipExtent - (_chipScrollCtrl.position.viewportDimension / 2) + (chipExtent / 2);
      _chipScrollCtrl.animateTo(
        targetOffset.clamp(0.0, _chipScrollCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// 多线路选择 chips（仅当 [groupByLine] 且线路数 > 1 时显示在选集上方）。
  Widget _buildLineChips(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
    List<String> lineNames,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceLg, vertical: AppTokens.spaceXs),
      child: SizedBox(
        width: MediaQuery.of(context).size.width - AppTokens.spaceLg * 2,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              ChoiceChip(
                label: Text(l10n.all),
                selected: _selectedLine == null,
                onSelected: (_) => setState(() => _selectedLine = null),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              for (final line in lineNames) ...<Widget>[
                ChoiceChip(
                  label: Text(line),
                  selected: _selectedLine == line,
                  onSelected: (_) => setState(() => _selectedLine = line),
                ),
                const SizedBox(width: AppTokens.spaceSm),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 网格模式渲染：紧凑卡片（序号 + 标题 + 进度指示）。
  Widget _buildChapterGrid(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
    List<int> indices,
  ) {
    final display = _filterQuery.display;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 2.4,
          crossAxisSpacing: AppTokens.spaceSm,
          mainAxisSpacing: AppTokens.spaceSm,
        ),
        itemCount: indices.length,
        itemBuilder: (BuildContext ctx, int gridIndex) {
          final i = indices[gridIndex];
          final ep = widget.chapters[i];
          final bool isRead =
              widget.isChapterRead != null && widget.isChapterRead!(i);
          final bool hasProgress =
              widget.getPosition != null && widget.getPosition!(i) > 0;

          String label = ep.title;
          if (display.number) {
            final numStr =
                ep.number != null ? '${ep.number}' : '${i + 1}';
            label = '$numStr. ${ep.title}';
          }

          final Widget card = Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              border: hasProgress
                  ? Border.all(
                      color: scheme.primary.withValues(alpha: 0.5),
                      width: 1.5)
                  : null,
            ),
            child: Stack(
              children: <Widget>[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.spaceXs, vertical: 2),
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                    ),
                  ),
                ),
                if (hasProgress)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          );

          return GestureDetector(
            onTap: () => widget.onTapChapter(ep, i),
            child: isRead ? Opacity(opacity: 0.5, child: card) : card,
          );
        },
      ),
    );
  }

  List<Widget> _buildChapterTiles(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
    List<int> indices,
  ) {
    final display = _filterQuery.display;
    return indices.map<Widget>((i) {
      final ep = widget.chapters[i];
      final bool isRead =
          widget.isChapterRead != null && widget.isChapterRead!(i);
      final bool hasProgress =
          widget.getPosition != null && widget.getPosition!(i) > 0;

      // 显示序号前缀
      String titleText = ep.title;
      if (display.number) {
        final numStr = ep.number != null
            ? '${ep.number}'
            : '${i + 1}';
        titleText = '$numStr. ${ep.title}';
      }

      // 副标题：来源标题（可选）+ 每章更新时间（需求6）
      final List<String> subtitleParts = <String>[];
      if (display.sourceTitle && ep.lineName != null) {
        subtitleParts.add(ep.lineName!);
      }
      final DateTime? effectiveDate = _effectiveUpdatedAt(i);
      if (effectiveDate != null) {
        subtitleParts.add(_formatChapterDate(effectiveDate));
      }
      final String? subtitle =
          subtitleParts.isEmpty ? null : subtitleParts.join(' · ');

      final Widget tile = ListTile(
        leading: widget.isChapterRead != null
            ? Icon(
                isRead ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20,
                color: isRead ? scheme.primary : scheme.outline,
              )
            : null,
        title: Text(titleText, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle != null
            ? Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ))
            : null,
        onTap: () => widget.onTapChapter(ep, i),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (hasProgress)
              Padding(
                padding: const EdgeInsets.only(right: AppTokens.spaceXs),
                child: Icon(
                  Icons.fiber_manual_record,
                  size: 10,
                  color: scheme.primary,
                ),
              ),
            if (widget.onDownloadChapter != null)
              IconButton(
                icon: Icon(
                  widget.isChapterDownloaded != null &&
                          widget.isChapterDownloaded!(i)
                      ? Icons.download_done
                      : Icons.download_outlined,
                  size: 20,
                ),
                tooltip: l10n.downloadSingleChapter,
                onPressed: () => widget.onDownloadChapter!(ep, i),
              ),
            if (widget.onToggleBookmark != null)
              IconButton(
                icon: Icon(
                  widget.isChapterBookmarked != null &&
                          widget.isChapterBookmarked!(i)
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  size: 20,
                ),
                tooltip: l10n.chapterBookmark,
                onPressed: () => widget.onToggleBookmark!(ep, i),
              ),
            if (widget.onToggleRead != null)
              IconButton(
                icon: Icon(
                  isRead ? Icons.visibility : Icons.visibility_outlined,
                  size: 20,
                ),
                tooltip: l10n.chapterRead,
                onPressed: () => widget.onToggleRead!(ep, i),
              ),
          ],
        ),
      );

      // 已读条目降低不透明度
      return isRead
          ? Opacity(opacity: 0.5, child: tile)
          : tile;
    }).toList();
  }
}
