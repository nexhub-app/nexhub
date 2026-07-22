/// 书架筛选面板（文档 §10.2 + 雷区 18）。
///
/// 由 [LibraryShell] 的筛选按钮唤起（替代原"功能暂未实现"桩），
/// 提供「排序 + 分类 + 状态 + 进度」四段筛选，点"应用"回传新的 [BookshelfFilter]。
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../models/bookshelf_filter.dart';
import '../theme/app_tokens.dart';

/// 唤起书架筛选底部面板，返回用户确认后的筛选状态；取消则返回 null。
Future<BookshelfFilter?> showBookshelfFilterSheet(
  BuildContext context, {
  required BookshelfFilter initialFilter,
  required List<String> categories,
}) {
  return showModalBottomSheet<BookshelfFilter>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTokens.radiusLg),
      ),
    ),
    builder: (BuildContext ctx) => _BookshelfFilterSheet(
      initialFilter: initialFilter,
      categories: categories,
    ),
  );
}

class _BookshelfFilterSheet extends StatefulWidget {
  final BookshelfFilter initialFilter;
  final List<String> categories;

  const _BookshelfFilterSheet({
    required this.initialFilter,
    required this.categories,
  });

  @override
  State<_BookshelfFilterSheet> createState() => _BookshelfFilterSheetState();
}

class _BookshelfFilterSheetState extends State<_BookshelfFilterSheet> {
  late BookshelfFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.spaceMd,
          AppTokens.spaceSm,
          AppTokens.spaceMd,
          AppTokens.spaceMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Handle(),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              l10n.filterTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _Section(label: l10n.sortBy, children: <Widget>[
                      _ChoiceChip(
                        label: l10n.sortRecent,
                        selected: _filter.sort == BookshelfSort.recent,
                        onSelected: (_) => setState(() => _filter =
                            _filter.copyWith(sort: BookshelfSort.recent)),
                      ),
                      _ChoiceChip(
                        label: l10n.sortTitle,
                        selected: _filter.sort == BookshelfSort.title,
                        onSelected: (_) => setState(() => _filter =
                            _filter.copyWith(sort: BookshelfSort.title)),
                      ),
                    ]),
                    const SizedBox(height: AppTokens.spaceMd),
                    _Section(label: l10n.filterByStatus, children: <Widget>[
                      _ChoiceChip(
                        label: l10n.allLabel,
                        selected: _filter.status == null,
                        onSelected: (_) => setState(() =>
                            _filter = _filter.copyWith(status: null)),
                      ),
                      _ChoiceChip(
                        label: l10n.statusOngoing,
                        selected: _filter.status == l10n.statusOngoing,
                        onSelected: (_) => setState(() => _filter =
                            _filter.copyWith(status: l10n.statusOngoing)),
                      ),
                      _ChoiceChip(
                        label: l10n.statusCompleted,
                        selected: _filter.status == l10n.statusCompleted,
                        onSelected: (_) => setState(() => _filter =
                            _filter.copyWith(status: l10n.statusCompleted)),
                      ),
                    ]),
                    const SizedBox(height: AppTokens.spaceMd),
                    _Section(label: l10n.filterByCategory, children: <
                        Widget>[
                      _ChoiceChip(
                        label: l10n.allLabel,
                        selected: _filter.category == null,
                        onSelected: (_) => setState(() =>
                            _filter = _filter.copyWith(category: null)),
                      ),
                      ...widget.categories.map(
                        (String c) => _ChoiceChip(
                          label: c,
                          selected: _filter.category == c,
                          onSelected: (_) => setState(() =>
                              _filter = _filter.copyWith(category: c)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: AppTokens.spaceMd),
                    _Section(label: l10n.filterByProgress, children: <Widget>[
                      _ChoiceChip(
                        label: l10n.allLabel,
                        selected: _filter.progress == null,
                        onSelected: (_) => setState(() =>
                            _filter = _filter.copyWith(progress: null)),
                      ),
                      _ChoiceChip(
                        label: l10n.progressReading,
                        selected:
                            _filter.progress == BookshelfProgress.reading,
                        onSelected: (_) => setState(() => _filter =
                            _filter.copyWith(
                                progress: BookshelfProgress.reading)),
                      ),
                      _ChoiceChip(
                        label: l10n.progressNotStarted,
                        selected: _filter.progress ==
                            BookshelfProgress.notStarted,
                        onSelected: (_) => setState(() => _filter =
                            _filter.copyWith(
                                progress: BookshelfProgress.notStarted)),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _filter = _filter.reset()),
                    child: Text(l10n.filterReset),
                  ),
                ),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_filter),
                    child: Text(l10n.filterApply),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: AppTokens.spaceXs),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _Section({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AppTokens.spaceXs),
        Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceXs,
          children: children,
        ),
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
    );
  }
}
