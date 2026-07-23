/// RSS 更新通知设置页（文档 §10.2 + 16.13 RSS 更新通知）。
///
/// 提供：
/// - 启用/禁用 RSS 更新检测开关
/// - 轮询间隔选择（15min/30min/1h/2h/4h）
/// - 立即检测按钮
/// - 总未读数显示
library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/rss/rss_update_checker.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_list_tile.dart';

class SettingsRssNotificationsScreen extends StatelessWidget {
  const SettingsRssNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final checker = context.watch<RssUpdateChecker>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.rssNotificationsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        children: <Widget>[
          // ── 启用开关 ──
          AppCard(
            child: AppListTile(
              leading: Icon(
                Icons.notifications_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(l10n.rssNotificationEnabled),
              subtitle: Text(l10n.rssNotificationEnabledSubtitle),
              trailing: Switch(
                value: checker.enabled,
                onChanged: (v) => checker.setEnabled(v),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),

          // ── 轮询间隔 ──
          if (checker.enabled) ...<Widget>[
            AppCard(
              child: Column(
                children: <Widget>[
                  AppListTile(
                    leading: Icon(
                      Icons.schedule,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(l10n.rssUpdateInterval),
                    subtitle: Text(_intervalLabel(l10n, checker.interval)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showIntervalPicker(context, checker),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),

            // ── 立即检测 ──
            AppCard(
              child: AppListTile(
                leading: Icon(
                  Icons.refresh,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(l10n.rssCheckNow),
                subtitle: Text(
                  l10n.rssTotalNewCount(checker.totalNewCount),
                ),
                onTap: () async {
                  await checker.checkAllFeeds();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.rssCheckDone)),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
          ],

          // ── 说明 ──
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceSm,
            ),
            child: Text(
              l10n.rssNotificationHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  String _intervalLabel(AppLocalizations l10n, RssUpdateInterval interval) {
    switch (interval) {
      case RssUpdateInterval.minutes15:
        return l10n.interval15m;
      case RssUpdateInterval.minutes30:
        return l10n.interval30m;
      case RssUpdateInterval.hour1:
        return l10n.interval1h;
      case RssUpdateInterval.hours2:
        return l10n.interval2h;
      case RssUpdateInterval.hours4:
        return l10n.interval4h;
    }
  }

  void _showIntervalPicker(
    BuildContext context,
    RssUpdateChecker checker,
  ) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.rssUpdateInterval),
        children: RssUpdateInterval.values.map((i) {
          return SimpleDialogOption(
            onPressed: () {
              checker.setInterval(i);
              Navigator.pop(ctx);
            },
            child: Row(
              children: <Widget>[
                if (checker.interval == i)
                  Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                else
                  const SizedBox(width: 24),
                const SizedBox(width: AppTokens.spaceSm),
                Text(_intervalLabel(l10n, i)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
