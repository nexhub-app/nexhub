/// 详情页阅读/观看进度卡（M16.4+ 详情页对账补全）。
///
/// 展示该内容的阅读/观看总览：总章节/集数、已读/已看、进度百分比 + 进度条，
/// 以及最近一次阅读/观看的时间与条目。
///
/// 供 [ContentDetailScreen] / [ComicDetailScreen] / [NovelDetailScreen] 复用。
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../theme/app_tokens.dart';

/// 进度卡上方的相对时间（用于"上次阅读/观看"提示）。
class ProgressLastRead {
  /// 相对时间文本（已经格式化好，如"1 天前"），不参与再次格式化。
  final String timeText;

  /// 最近阅读/观看的章节/剧集标题。
  final String chapterTitle;

  const ProgressLastRead({required this.timeText, required this.chapterTitle});
}

/// 进度类型（控制标题/标签用"章"还是"集"）。
enum ProgressKind {
  /// 小说 / 漫画：阅读进度。
  reading,

  /// 动漫 / 影视：观看进度。
  watching,
}

/// 详情页阅读/观看进度卡。
///
/// 整体视觉与 [ContentDetailShell] 中其他分组卡一致（浅灰底、圆角、无明显边框）。
class ProgressCard extends StatelessWidget {
  /// 进度类型（决定文案"阅读/观看"、"章/集"）。
  final ProgressKind kind;

  /// 总章节/集数。
  final int total;

  /// 已读/已看章节/集数。
  final int read;

  /// 最近阅读/观看信息（可为 null，即未开始）。
  final ProgressLastRead? lastRead;

  /// 点击卡片的回调（一般跳到对应章节/剧集）。
  final VoidCallback? onTap;

  const ProgressCard({
    super.key,
    required this.kind,
    required this.total,
    required this.read,
    this.lastRead,
    this.onTap,
  });

  double get _percent => total <= 0 ? 0.0 : (read / total).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isReading = kind == ProgressKind.reading;

    final String title = isReading ? l10n.readingProgress : l10n.watchingProgress;
    final String totalLabel = isReading ? l10n.totalChapters : l10n.totalEpisodes;
    final String readLabel = isReading ? l10n.chaptersRead : l10n.episodesWatched;
    final String percentText = '${(_percent * 100).toStringAsFixed(1)}%';

    final Widget card = Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLg,
        vertical: AppTokens.spaceMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 标题行
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          // 三列统计
          Row(
            children: <Widget>[
              Expanded(
                child: _StatColumn(
                  icon: Icons.menu_book_outlined,
                  value: '$total',
                  label: totalLabel,
                ),
              ),
              Expanded(
                child: _StatColumn(
                  icon: Icons.check_circle_outline,
                  value: '$read',
                  label: readLabel,
                ),
              ),
              Expanded(
                child: _StatColumn(
                  icon: Icons.percent,
                  value: percentText,
                  label: l10n.progressLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusFull),
            child: LinearProgressIndicator(
              value: total <= 0 ? null : _percent,
              minHeight: 6,
              backgroundColor:
                  scheme.surfaceContainerHighest.withValues(alpha: 0.8),
              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
            ),
          ),
          // 最近阅读/观看
          if (lastRead != null) ...<Widget>[
            const SizedBox(height: AppTokens.spaceSm),
            Row(
              children: <Widget>[
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppTokens.spaceXs),
                Expanded(
                  child: Text(
                    isReading
                        ? l10n.lastReadInfo(lastRead!.timeText, lastRead!.chapterTitle)
                        : l10n.lastWatchedInfo(
                            lastRead!.timeText, lastRead!.chapterTitle),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: card,
      ),
    );
  }
}

/// 三列统计中的单列：图标 + 数字 + 标签。
class _StatColumn extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatColumn({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

/// 工具函数：把 [DateTime] 转成"X 分钟/小时/天/周/月前"短文本。
///
/// 不到 1 分钟返回"刚刚"，未来时间（轻微时钟漂移）也按"刚刚"处理。
String formatRelativeTime(AppLocalizations l10n, DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.isNegative || diff.inMinutes < 1) return l10n.timeJustNow;
  if (diff.inMinutes < 60) return l10n.timeMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.timeHoursAgo(diff.inHours);
  if (diff.inDays < 30) return l10n.timeDaysAgo(diff.inDays);
  // 30 天以上按"X 月前"近似（30 天 = 1 月）
  final months = (diff.inDays / 30).floor();
  if (months < 12) {
    // 复用 days 字段做"X 月前"过于牵强；这里退回到 N 天前，避免引入新键。
    return l10n.timeDaysAgo(diff.inDays);
  }
  return l10n.timeDaysAgo(diff.inDays);
}
