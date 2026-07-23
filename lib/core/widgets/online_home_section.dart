/// 在线列表首页 Section（Phase 1.3 #7 A4-#7）。
///
/// 横向滚动卡片列表，含标题 + "查看全部"按钮。
/// 点击卡片进详情页；点击"查看全部"跳到对应分类 Tab。
library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../models/media_item.dart';
import '../services/source_repository.dart';
import '../theme/app_tokens.dart';
import 'content_card.dart';

/// 首页横向 Section。
///
/// [title] 由调用方传入（已 l10n 翻译）；[items] 为该 Section 的卡片数据；
/// [onItemTap] 点击卡片回调；[onViewAll] 点击"查看全部"回调（跳到对应分类 Tab）。
class OnlineHomeSection extends StatelessWidget {
  const OnlineHomeSection({
    super.key,
    required this.title,
    required this.items,
    required this.onItemTap,
    this.onViewAll,
    this.heroPrefix = 'online-home',
  });

  /// Section 标题（已 l10n 翻译）。
  final String title;

  /// 该 Section 的卡片数据（最多展示 12 条）。
  final List<MediaItem> items;

  /// 点击卡片回调。
  final void Function(MediaItem item) onItemTap;

  /// 点击"查看全部"回调（跳到对应分类 Tab）。
  final VoidCallback? onViewAll;

  /// Hero 动画前缀（避免多 Section 重复 tag）。
  final String heroPrefix;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 标题栏 + 查看全部
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceLg,
            vertical: AppTokens.spaceXs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (onViewAll != null)
                TextButton(
                  onPressed: onViewAll,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(l10n.viewAll),
                      const Icon(Icons.chevron_right, size: 16),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // 横向卡片列表
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg,
            ),
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: AppTokens.spaceSm),
            itemBuilder: (BuildContext ctx, int i) {
              final item = items[i];
              return SizedBox(
                width: 120,
                child: ContentCard(
                  title: item.title,
                  coverUrl: item.coverUrl,
                  source: ctx.read<SourceRepository>().getById(item.sourceId ?? ''),
                  subtitle: item.status,
                  meta: item.year,
                  heroTag: '$heroPrefix-${item.id}',
                  onTap: () => onItemTap(item),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
