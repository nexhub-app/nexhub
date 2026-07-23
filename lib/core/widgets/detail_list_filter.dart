/// 详情页章节/剧集列表的筛选 / 排序 / 显示组合组件。
///
/// 移植自旧版 `detail_list_filter.dart`，适配当前项目的
/// `flutter_gen` l10n 与 [AppCard] 组件。
library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../theme/app_tokens.dart';
import 'app_card.dart';

/// 多选过滤条件模型。
class DetailItemFilter {
  const DetailItemFilter({
    this.downloaded = false,
    this.unread = false,
    this.bookmarked = false,
  });
  final bool downloaded;
  final bool unread;
  final bool bookmarked;

  bool get isEmpty => !downloaded && !unread && !bookmarked;

  DetailItemFilter copyWith({
    bool? downloaded,
    bool? unread,
    bool? bookmarked,
  }) =>
      DetailItemFilter(
        downloaded: downloaded ?? this.downloaded,
        unread: unread ?? this.unread,
        bookmarked: bookmarked ?? this.bookmarked,
      );
}

/// 排序键枚举。
enum DetailSortKey { source, byIndex, uploadDate, name }

/// 排序状态：键 + 升降序。
class DetailItemSort {
  const DetailItemSort({
    this.key = DetailSortKey.byIndex,
    this.descending = false,
  });
  final DetailSortKey key;
  final bool descending;

  DetailItemSort copyWith({DetailSortKey? key, bool? descending}) =>
      DetailItemSort(
        key: key ?? this.key,
        descending: descending ?? this.descending,
      );
}

/// 多选显示选项。
class DetailItemDisplay {
  const DetailItemDisplay({
    this.sourceTitle = false,
    this.number = false,
  });
  final bool sourceTitle;
  final bool number;

  DetailItemDisplay copyWith({bool? sourceTitle, bool? number}) =>
      DetailItemDisplay(
        sourceTitle: sourceTitle ?? this.sourceTitle,
        number: number ?? this.number,
      );
}

/// 组合的筛选 / 排序 / 显示状态。
class DetailListQuery {
  const DetailListQuery({
    this.filter = const DetailItemFilter(),
    this.sort = const DetailItemSort(),
    this.display = const DetailItemDisplay(),
  });
  final DetailItemFilter filter;
  final DetailItemSort sort;
  final DetailItemDisplay display;

  bool get isDefault =>
      filter.isEmpty &&
      sort.key == DetailSortKey.byIndex &&
      !sort.descending &&
      !display.sourceTitle &&
      !display.number;

  DetailListQuery copyWith({
    DetailItemFilter? filter,
    DetailItemSort? sort,
    DetailItemDisplay? display,
  }) =>
      DetailListQuery(
        filter: filter ?? this.filter,
        sort: sort ?? this.sort,
        display: display ?? this.display,
      );

  /// 返回当前激活的过滤标签摘要；无过滤时返回 [AppLocalizations.allLabel]。
  String summary(AppLocalizations l10n) {
    final parts = <String>[];
    if (filter.unread) parts.add(l10n.filterUnread);
    if (filter.downloaded) parts.add(l10n.filterDownloaded);
    if (filter.bookmarked) parts.add(l10n.filterBookmarked);
    if (parts.isEmpty) return l10n.allLabel;
    return parts.join(' / ');
  }
}

/// 筛选 / 排序 / 显示底部弹窗。
///
/// 调用方传入 [unitWord]（如"章"或"集"），用于插入本地化的排序/显示标签。
/// 弹窗返回确认后的 [DetailListQuery]。
class DetailListFilterSheet extends StatefulWidget {
  final DetailListQuery initialQuery;
  final String unitWord;
  final bool isMultiSource;

  const DetailListFilterSheet({
    super.key,
    required this.initialQuery,
    required this.unitWord,
    this.isMultiSource = false,
  });

  @override
  State<DetailListFilterSheet> createState() => _DetailListFilterSheetState();

  /// 便捷方法：弹出 sheet 并等待结果。
  static Future<DetailListQuery?> show(
    BuildContext context, {
    required DetailListQuery initialQuery,
    required String unitWord,
    bool isMultiSource = false,
  }) {
    return showModalBottomSheet<DetailListQuery>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DetailListFilterSheet(
        initialQuery: initialQuery,
        unitWord: unitWord,
        isMultiSource: isMultiSource,
      ),
    );
  }
}

class _DetailListFilterSheetState extends State<DetailListFilterSheet> {
  late DetailItemFilter _filter;
  late DetailItemSort _sort;
  late DetailItemDisplay _display;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialQuery.filter;
    _sort = widget.initialQuery.sort;
    _display = widget.initialQuery.display;
  }

  void _reset() {
    setState(() {
      _filter = const DetailItemFilter();
      _sort = const DetailItemSort();
      _display = const DetailItemDisplay();
    });
  }

  void _confirm() {
    Navigator.of(context).pop(
      DetailListQuery(filter: _filter, sort: _sort, display: _display),
    );
  }

  String _sortKeyLabel(DetailSortKey key, AppLocalizations l10n) {
    switch (key) {
      case DetailSortKey.source:
        return l10n.sortBySource;
      case DetailSortKey.byIndex:
        return l10n.sortByIndex(widget.unitWord);
      case DetailSortKey.uploadDate:
        return l10n.sortByUploadDate;
      case DetailSortKey.name:
        return l10n.sortByName(widget.unitWord);
    }
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceLg),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceSm,
            vertical: AppTokens.spaceSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceSm,
                  AppTokens.spaceSm,
                  AppTokens.spaceSm,
                  AppTokens.spaceXs,
                ),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ─── 过滤 ───
                _buildSection(
                  title: l10n.filterTitle,
                  children: <Widget>[
                    CheckboxListTile(
                      value: _filter.downloaded,
                      onChanged: (v) => setState(() {
                        _filter = _filter.copyWith(downloaded: v);
                      }),
                      title: Text(l10n.filterDownloaded),
                    ),
                    CheckboxListTile(
                      value: _filter.unread,
                      onChanged: (v) => setState(() {
                        _filter = _filter.copyWith(unread: v);
                      }),
                      title: Text(l10n.filterUnread),
                    ),
                    CheckboxListTile(
                      value: _filter.bookmarked,
                      onChanged: (v) => setState(() {
                        _filter = _filter.copyWith(bookmarked: v);
                      }),
                      title: Text(l10n.filterBookmarked),
                    ),
                  ],
                ),

                // ─── 排序 ───
                _buildSection(
                  title: l10n.sortSectionTitle,
                  children: <Widget>[
                    for (final key in DetailSortKey.values)
                      if (widget.isMultiSource || key != DetailSortKey.source)
                        RadioListTile<DetailSortKey>(
                          value: key,
                          groupValue: _sort.key,
                          onChanged: (v) => setState(() {
                            _sort = _sort.copyWith(key: v);
                          }),
                          title: Text(_sortKeyLabel(key, l10n)),
                        ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.spaceSm),
                      child: SegmentedButton<bool>(
                        segments: <ButtonSegment<bool>>[
                          ButtonSegment(
                            value: false,
                            label: Text(l10n.sortAscendingLabel),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text(l10n.sortDescendingLabel),
                          ),
                        ],
                        selected: <bool>{_sort.descending},
                        onSelectionChanged: (selection) => setState(() {
                          _sort =
                              _sort.copyWith(descending: selection.first);
                        }),
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
                  ],
                ),

                // ─── 显示 ───
                _buildSection(
                  title: l10n.displayTitle,
                  children: <Widget>[
                    if (widget.isMultiSource)
                      CheckboxListTile(
                        value: _display.sourceTitle,
                        onChanged: (v) => setState(() {
                          _display = _display.copyWith(sourceTitle: v);
                        }),
                        title: Text(l10n.displaySourceTitle),
                      ),
                    CheckboxListTile(
                      value: _display.number,
                      onChanged: (v) => setState(() {
                        _display = _display.copyWith(number: v);
                      }),
                      title: Text(l10n.displayNumber(widget.unitWord)),
                    ),
                  ],
                ),

                // ─── 操作行 ───
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.spaceXs),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      TextButton(
                        onPressed: _reset,
                        child: Text(l10n.resetButton),
                      ),
                      FilledButton(
                        onPressed: _confirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.primary,
                        ),
                        child: Text(l10n.doneButton),
                      ),
                    ],
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
