/// RSS 订阅源详情页——展示某订阅源的条目列表（文档 §10.2）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/rss/rss_feed.dart';
import '../../../core/rss/rss_manager.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../home/presentation/browse_article_detail_screen.dart';
import 'package:provider/provider.dart';

class RssFeedDetailScreen extends StatefulWidget {
  final RssFeed feed;

  const RssFeedDetailScreen({super.key, required this.feed});

  @override
  State<RssFeedDetailScreen> createState() => _RssFeedDetailScreenState();
}

class _RssFeedDetailScreenState extends State<RssFeedDetailScreen> {
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
      final manager = context.read<RssManager>();
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
        title: Text(widget.feed.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
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
          return _RssItemTile(item: item, scheme: scheme);
        },
      ),
    );
  }
}

class _RssItemTile extends StatelessWidget {
  final RssItem item;
  final ColorScheme scheme;

  const _RssItemTile({required this.item, required this.scheme});

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
        children: [
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
            children: [
              if (item.author != null) ...[
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
              if (item.publishedAt != null) ...[
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
