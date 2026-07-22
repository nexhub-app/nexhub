/// 在线列表周期表 Section（Phase 1.4 #7 A4-#7）。
///
/// 按 7 天（周一~周日）分组展示本周更新内容。横向 7 列 Chip，
/// 点击切换当天列表。源无法提供更新时间时回退为按 `latest` 顺序平铺。
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../models/media_item.dart';
import '../theme/app_tokens.dart';

/// 周更时间表 Section。
///
/// [items] 为近期内容列表（来自 `latest` route）；[onItemTap] 点击卡片回调。
/// 按 [MediaItem.updatedAt] 归类到对应星期；无 updatedAt 时回退为平铺列表。
class OnlineScheduleSection extends StatefulWidget {
  const OnlineScheduleSection({
    super.key,
    required this.items,
    required this.onItemTap,
    this.heroPrefix = 'online-schedule',
  });

  /// 近期内容列表（来自 `latest` route）。
  final List<MediaItem> items;

  /// 点击卡片回调。
  final void Function(MediaItem item) onItemTap;

  /// Hero 动画前缀。
  final String heroPrefix;

  @override
  State<OnlineScheduleSection> createState() => _OnlineScheduleSectionState();
}

class _OnlineScheduleSectionState extends State<OnlineScheduleSection> {
  /// 当前选中的星期（1=周一 ... 7=周日）。
  ///
  /// 默认值为"今天"的星期几（DateTime.weekday：1=Monday ... 7=Sunday）。
  late int _selectedWeekday = DateTime.now().weekday;

  /// 是否所有 items 都没有 updatedAt（用于回退为平铺列表）。
  bool get _hasNoUpdatedAt =>
      widget.items.every((it) => it.updatedAt == null);

  /// 返回某星期对应的中/英文标签。
  String _weekdayLabel(AppLocalizations l10n, int weekday) {
    return switch (weekday) {
      1 => l10n.weekdayMon,
      2 => l10n.weekdayTue,
      3 => l10n.weekdayWed,
      4 => l10n.weekdayThu,
      5 => l10n.weekdayFri,
      6 => l10n.weekdaySat,
      7 => l10n.weekdaySun,
      _ => '',
    };
  }

  /// 按 updatedAt 归类到各星期。
  Map<int, List<MediaItem>> _groupByWeekday() {
    final map = <int, List<MediaItem>>{
      1: <MediaItem>[],
      2: <MediaItem>[],
      3: <MediaItem>[],
      4: <MediaItem>[],
      5: <MediaItem>[],
      6: <MediaItem>[],
      7: <MediaItem>[],
    };
    for (final item in widget.items) {
      if (item.updatedAt == null) continue;
      map[item.updatedAt!.weekday]!.add(item);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // 回退：无 updatedAt 时按 latest 顺序平铺。
    if (_hasNoUpdatedAt) {
      return _buildFlatList(l10n, theme);
    }

    final grouped = _groupByWeekday();
    final todayItems = grouped[_selectedWeekday] ?? <MediaItem>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 星期 Chip 行
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceLg,
            vertical: AppTokens.spaceXs,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List<int>.generate(7, (i) => i + 1).map((wd) {
                final isSel = wd == _selectedWeekday;
                final hasItems = (grouped[wd]?.length ?? 0) > 0;
                return Padding(
                  padding: const EdgeInsets.only(right: AppTokens.spaceXs),
                  child: ChoiceChip(
                    label: Text(_weekdayLabel(l10n, wd)),
                    selected: isSel,
                    onSelected: hasItems
                        ? (_) => setState(() => _selectedWeekday = wd)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: AppTokens.spaceXs),
        // 当天列表
        if (todayItems.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: Text(
              l10n.emptyCategory,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          _buildDayList(todayItems, theme),
      ],
    );
  }

  /// 回退平铺列表（无 updatedAt 时使用）。
  Widget _buildFlatList(AppLocalizations l10n, ThemeData theme) {
    if (widget.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Text(
          l10n.emptyCategory,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return _buildDayList(widget.items, theme);
  }

  /// 当天/平铺列表的卡片网格。
  Widget _buildDayList(List<MediaItem> items, ThemeData theme) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        const cross = 3;
        final width = c.maxWidth;
        final itemW =
            (width - AppTokens.spaceLg * 2 - AppTokens.spaceSm * (cross - 1)) /
                cross;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            mainAxisSpacing: AppTokens.spaceLg,
            crossAxisSpacing: AppTokens.spaceSm,
            childAspectRatio: itemW / (itemW / AppTokens.coverAspectRatio + 48),
          ),
          itemCount: items.length,
          itemBuilder: (BuildContext ctx, int i) {
            final item = items[i];
            return _buildCard(context, item, itemW, theme);
          },
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    MediaItem item,
    double width,
    ThemeData theme,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onItemTap(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 封面或占位
            Expanded(
              child: item.coverUrl != null && item.coverUrl!.isNotEmpty
                  ? Image.network(
                      item.coverUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.movie, size: 32),
                      ),
                    )
                  : Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.movie, size: 32),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceXs),
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
