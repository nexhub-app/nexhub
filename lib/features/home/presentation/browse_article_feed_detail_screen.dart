/// 浏览页文章订阅源详情页（Task 29）。
///
/// 展示某订阅源下的文章列表，数据源为独立的 [BrowseArticleFeedManager]，
/// 与全局 [RssManager] 完全隔离。点击文章进入 [BrowseArticleDetailScreen]。
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/rss/browse_article_feed_manager.dart';
import '../../../core/rss/rss_feed.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_loading_indicator.dart';

import 'browse_article_detail_screen.dart';

/// 订阅源详情：展示某订阅源下的文章列表。
class BrowseArticleFeedDetailScreen extends StatefulWidget {
  final RssFeed feed;

  const BrowseArticleFeedDetailScreen({super.key, required this.feed});

  @override
  State<BrowseArticleFeedDetailScreen> createState() =>
      _BrowseArticleFeedDetailScreenState();
}

class _BrowseArticleFeedDetailScreenState
    extends State<BrowseArticleFeedDetailScreen> {
  ParsedFeed? _parsed;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  Future<void> _loadFeed() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final manager = context.read<BrowseArticleFeedManager>();
      final result = await manager.fetchFeed(widget.feed);
      if (mounted) {
        setState(() {
          _parsed = result;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.feed.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.retry,
            onPressed: _loadFeed,
          ),
        ],
      ),
      body: _buildBody(context, l10n, scheme),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
  ) {
    if (_loading) {
      return const Center(child: AppLoadingIndicator());
    }

    if (_error != null) {
      return AppErrorState(
        message: l10n.loadFailed,
        onRetry: _loadFeed,
      );
    }

    final items = _parsed?.items ?? const <RssItem>[];

    if (items.isEmpty) {
      return AppEmptyState(
        icon: Icons.article_outlined,
        message: l10n.emptyRssItems,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFeed,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final item = items[i];
          return _ArticleItemTile(item: item, scheme: scheme);
        },
      ),
    );
  }
}

/// 文章列表项。
class _ArticleItemTile extends StatelessWidget {
  final RssItem item;
  final ColorScheme scheme;

  const _ArticleItemTile({required this.item, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: AppTokens.spaceXs,
      ),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (item.description != null)
            Text(
              _stripHtml(item.description!),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          const SizedBox(height: AppTokens.spaceXs),
          Row(
            children: <Widget>[
              if (item.author != null) ...<Widget>[
                Icon(Icons.person_outline,
                    size: 12, color: scheme.onSurfaceVariant),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    item.author!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(width: AppTokens.spaceSm),
              ],
              if (item.publishedAt != null) ...<Widget>[
                Icon(Icons.schedule,
                    size: 12, color: scheme.onSurfaceVariant),
                const SizedBox(width: 2),
                Text(
                  _formatDate(item.publishedAt!),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ],
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BrowseArticleDetailScreen(item: item),
          ),
        );
      },
    );
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
