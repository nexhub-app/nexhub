/// RSS 订阅源列表页 —— 新版设计。
///
/// 空状态居中显示图标+提示文字，右下角 FAB 添加订阅。
/// 有数据时显示列表。
///
/// 三模块共用，通过 [moduleType] 过滤订阅源。
/// 也用于浏览页全局 RSS（moduleType = null）。
library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/rss/rss_feed.dart';
import '../../../core/rss/rss_manager.dart';
import '../../../core/rss/rss_update_checker.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_empty_state.dart';
import 'rss_feed_detail_screen.dart';
import 'rss_add_subscription_screen.dart';

class RssFeedListScreen extends StatefulWidget {
  /// 绑定的模块类型（null = 浏览页全局 RSS）。
  final SourceType? moduleType;

  const RssFeedListScreen({super.key, this.moduleType});

  @override
  State<RssFeedListScreen> createState() => _RssFeedListScreenState();
}

class _RssFeedListScreenState extends State<RssFeedListScreen> {
  /// 测速结果：feedId → 延迟毫秒（-1 = 失败，null = 测试中）。
  final Map<String, int?> _speeds = {};
  bool _testingAll = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final manager = context.watch<RssManager>();
    final checker = context.watch<RssUpdateChecker>();
    final feeds = manager.feedsFor(widget.moduleType);

    // 根据类型选择不同的空状态图标
    final IconData emptyIcon = switch (widget.moduleType) {
      SourceType.novelSource => Icons.menu_book_outlined,
      SourceType.animeSource => Icons.movie_outlined,
      SourceType.mangaSource => Icons.auto_stories_outlined,
      _ => Icons.rss_feed_outlined,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.rssFeedListTitle),
        actions: <Widget>[
          if (feeds.isNotEmpty)
            IconButton(
              icon: _testingAll
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.speed),
              tooltip: l10n.rssTestAllSpeed,
              onPressed: _testingAll ? null : () => _testAllSpeed(manager),
            ),
        ],
      ),
      body: feeds.isEmpty
          ? AppEmptyState(
              icon: emptyIcon,
              message: l10n.emptyRssSubscribe,
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              itemCount: feeds.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppTokens.spaceSm),
              itemBuilder: (context, i) {
                final feed = feeds[i];
                final newCount = checker.newCountFor(feed.id);
                return AppCard(
                  onTap: () {
                    // 进入详情时清零未读数
                    if (newCount > 0) {
                      checker.markRead(feed.id);
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RssFeedDetailScreen(feed: feed),
                      ),
                    );
                  },
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceLg,
                      vertical: AppTokens.spaceXs,
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusSm),
                      ),
                      child:
                          Icon(Icons.rss_feed, color: scheme.primary, size: 22),
                    ),
                    title: Text(
                      feed.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _speedSubtitle(feed, l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (newCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(
                                  AppTokens.radiusFull),
                            ),
                            child: Text(
                              '$newCount',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: scheme.onPrimary),
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        // 测速指示器
                        _buildSpeedIndicator(feed, scheme),
                        IconButton(
                          icon: Icon(Icons.edit_outlined,
                              color: scheme.onSurfaceVariant),
                          tooltip: l10n.editRoute,
                          onPressed: () =>
                              _showEditDialog(context, manager, feed),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: scheme.onSurfaceVariant),
                          tooltip: l10n.delete,
                          onPressed: () => _confirmDelete(
                              context, manager, feed.id, feed.title),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      // 右下角 FAB 添加按钮（匹配截图 7）
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToAdd(context),
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 测速结果的副标题显示。
  String _speedSubtitle(RssFeed feed, AppLocalizations l10n) {
    final speed = _speeds[feed.id];
    if (speed == null) return feed.description ?? feed.url;
    if (speed < 0) return '${feed.description ?? feed.url} · ${l10n.rssSpeedFailed}';
    return '${feed.description ?? feed.url} · ${l10n.rssSpeedMs(speed)}';
  }

  /// 单条订阅源的测速指示器。
  Widget _buildSpeedIndicator(RssFeed feed, ColorScheme scheme) {
    final speed = _speeds[feed.id];
    if (speed == null) return const SizedBox.shrink();
    if (speed < 0) {
      return Icon(Icons.error_outline, color: scheme.error, size: 20);
    }
    final color = speed < 500
        ? scheme.primary
        : speed < 2000
            ? scheme.tertiary
            : scheme.outline;
    return Icon(Icons.check_circle_outline, color: color, size: 20);
  }

  /// 一键测速全部订阅源（P8.2.3 §廿二）。
  Future<void> _testAllSpeed(RssManager manager) async {
    setState(() {
      _testingAll = true;
      _speeds.clear();
    });
    await manager.testAllFeeds(
      onProgress: (feedId, ms) {
        if (mounted) {
          setState(() => _speeds[feedId] = ms);
        }
      },
    );
    if (mounted) setState(() => _testingAll = false);
  }

  void _navigateToAdd(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RssAddSubscriptionScreen(
          moduleType: widget.moduleType,
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    RssManager manager,
    String feedId,
    String feedTitle,
  ) {
    final l10n = AppLocalizations.of(context);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmContent(feedTitle)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              manager.removeFeed(feedId);
              Navigator.of(dialogContext).pop();
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  /// 编辑订阅的 RSS 路由（URL）与标题，保存即调用 [RssManager.updateFeed]。
  void _showEditDialog(
    BuildContext context,
    RssManager manager,
    RssFeed feed,
  ) {
    final l10n = AppLocalizations.of(context);
    final titleCtrl = TextEditingController(text: feed.title);
    final urlCtrl = TextEditingController(text: feed.url);
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.editRoute),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: titleCtrl,
                decoration: InputDecoration(labelText: l10n.routeTitle),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.requiredHint : null,
              ),
              const SizedBox(height: AppTokens.spaceSm),
              TextFormField(
                controller: urlCtrl,
                decoration: InputDecoration(labelText: l10n.routeUrl),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.requiredHint : null,
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              manager.updateFeed(
                feed.copyWith(
                  title: titleCtrl.text.trim(),
                  url: urlCtrl.text.trim(),
                ),
              );
              Navigator.of(dialogContext).pop();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.routeSaved)),
                );
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}
