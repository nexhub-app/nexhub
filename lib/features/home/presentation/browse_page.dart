/// 浏览首页：图文宫格式布局，提供四大入口（本地文件、网络文件、网页爬取、RSS 订阅）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_tokens.dart';

import 'browse_local_screen.dart';
import 'browse_network_screen.dart';
import 'browse_rss_screen.dart';
import 'browse_web_scrape_screen.dart';

/// 浏览页入口项数据模型。
class _BrowseEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  const _BrowseEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });
}

/// 宫格卡片：上方图标 + 背景色，下方标题与副标题。
class _BrowseGridCard extends StatelessWidget {
  final _BrowseEntry entry;
  const _BrowseGridCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: entry.onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 上半部：图标 + 背景色
            Expanded(
              child: Container(
                color: entry.color,
                alignment: Alignment.center,
                child: Icon(entry.icon, size: 40, color: entry.iconColor),
              ),
            ),
            // 下半部：标题 + 副标题（固定高度，居中对齐）
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceSm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: <Widget>[
                    Text(
                      entry.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppTokens.spaceXs),
                    Text(
                      entry.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 浏览页面：图文宫格式布局，无 AppBar 操作按钮。
class BrowsePage extends StatelessWidget {
  const BrowsePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final List<_BrowseEntry> entries = <_BrowseEntry>[
      _BrowseEntry(
        icon: Icons.folder_outlined,
        title: l10n.browseLocalFiles,
        subtitle: l10n.browseLocalFilesSubtitle,
        color: scheme.primaryContainer,
        iconColor: scheme.onPrimaryContainer,
        onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BrowseLocalScreen(),
              ),
            ),
      ),
      _BrowseEntry(
        icon: Icons.cloud_download_outlined,
        title: l10n.browseNetworkFiles,
        subtitle: l10n.browseNetworkFilesSubtitle,
        color: scheme.secondaryContainer,
        iconColor: scheme.onSecondaryContainer,
        onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BrowseNetworkScreen(),
              ),
            ),
      ),
      _BrowseEntry(
        icon: Icons.travel_explore_outlined,
        title: l10n.browseWebScrape,
        subtitle: l10n.browseWebScrapeSubtitle,
        color: scheme.tertiaryContainer,
        iconColor: scheme.onTertiaryContainer,
        onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BrowseWebScrapeScreen(),
              ),
            ),
      ),
      _BrowseEntry(
        icon: Icons.rss_feed_outlined,
        title: l10n.browseRss,
        subtitle: l10n.browseRssSubtitle,
        color: scheme.errorContainer,
        iconColor: scheme.onErrorContainer,
        onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BrowseRssScreen(),
              ),
            ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.browsePageTitle),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(AppTokens.spaceSm),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          childAspectRatio: 0.95,
          mainAxisSpacing: AppTokens.spaceSm,
          crossAxisSpacing: AppTokens.spaceSm,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) =>
            _BrowseGridCard(entry: entries[index]),
      ),
    );
  }
}
