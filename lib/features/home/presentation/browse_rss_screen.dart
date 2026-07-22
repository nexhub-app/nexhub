/// 浏览页 RSS 订阅源列表（Task 29）。
///
/// 独立于全局 [RssFeedListScreen]，数据源为 [BrowseArticleFeedManager]，
/// 与全局 RssManager 数据完全隔离。UI 仿 [RssFeedListScreen]：
/// 空状态居中 + FAB 添加订阅；点击订阅源进入 [BrowseArticleFeedDetailScreen]。
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/rss/browse_article_feed_manager.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_empty_state.dart';

import 'browse_add_article_feed_screen.dart';
import 'browse_article_feed_detail_screen.dart';

/// 浏览页 RSS 订阅源列表，使用独立的 [BrowseArticleFeedManager]。
class BrowseRssScreen extends StatelessWidget {
  const BrowseRssScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final manager = context.watch<BrowseArticleFeedManager>();
    final feeds = manager.feeds;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.browseRss)),
      body: feeds.isEmpty
          ? AppEmptyState(
              icon: Icons.rss_feed_outlined,
              message: l10n.emptyRssSubscribe,
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              itemCount: feeds.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppTokens.spaceSm),
              itemBuilder: (context, i) {
                final feed = feeds[i];
                return AppCard(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            BrowseArticleFeedDetailScreen(feed: feed),
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
                      child: Icon(Icons.rss_feed,
                          color: scheme.primary, size: 22),
                    ),
                    title: Text(
                      feed.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      feed.description ?? feed.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: scheme.onSurfaceVariant),
                      tooltip: l10n.delete,
                      onPressed: () => _confirmDelete(
                          context, manager, feed.id, feed.title),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BrowseAddArticleFeedScreen(),
              ),
            ),
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    BrowseArticleFeedManager manager,
    String feedId,
    String feedTitle,
  ) {
    final l10n = AppLocalizations.of(context);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmContent(feedTitle)),
        actions: <Widget>[
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
}
