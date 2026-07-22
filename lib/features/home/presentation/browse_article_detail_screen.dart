/// RSS article detail reader (Browse -> RSS -> feed detail -> article).
///
/// Renders the article HTML body in-app via [flutter_html] instead of stripping
/// tags to plain text. Supports reading settings (font size / line height /
/// night mode) persisted through [ArticleReadingPreferencesNotifier].
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/article/article_reading_preferences.dart';
import '../../../core/settings/general_settings.dart';
import '../../../core/rss/rss_feed.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_cover_image.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';

/// Single RSS article detail reader page.
class BrowseArticleDetailScreen extends StatelessWidget {
  final RssItem item;
  const BrowseArticleDetailScreen({super.key, required this.item});

  String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    return GeneralSettingsStore.instance.settings.dateFormat.format(
      dt,
      withTime: true,
    );
  }

  Future<void> _openInBrowser(BuildContext context, AppLocalizations l10n) async {
    try {
      await launchUrl(Uri.parse(item.url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.loadFailed)),
        );
      }
    }
  }

  void _showReadingSettingsSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return Consumer<ArticleReadingPreferencesNotifier>(
          builder: (BuildContext ctx, ArticleReadingPreferencesNotifier notifier, _) {
            final prefs = notifier.prefs;
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceLg,
                AppTokens.spaceSm,
                AppTokens.spaceLg,
                AppTokens.spaceLg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.articleReadingSettings,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  Text(l10n.articleFontSize),
                  Row(
                    children: <Widget>[
                      const Text('A'),
                      Expanded(
                        child: Slider(
                          min: 12,
                          max: 24,
                          divisions: 12,
                          value: prefs.fontSize,
                          label: prefs.fontSize.toStringAsFixed(0),
                          onChanged: notifier.setFontSize,
                        ),
                      ),
                      const Text('A',
                          style: TextStyle(fontSize: 22)),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(l10n.articleLineHeight),
                  Slider(
                    min: 1.0,
                    max: 2.5,
                    divisions: 15,
                    value: prefs.lineHeight,
                    label: prefs.lineHeight.toStringAsFixed(1),
                    onChanged: notifier.setLineHeight,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.articleNightMode),
                    value: prefs.isNightMode,
                    onChanged: (_) => notifier.toggleNightMode(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String html = item.content ?? item.description ?? '';

    return Consumer<ArticleReadingPreferencesNotifier>(
      builder: (BuildContext context, ArticleReadingPreferencesNotifier notifier, _) {
        final prefs = notifier.prefs;
        final bool isNight = prefs.isNightMode;
        final Color? bg = isNight ? Colors.grey[900] : null;
        final Color textColor = isNight ? Colors.grey[100]! : Theme.of(context).textTheme.bodyLarge!.color!;
        final Color metaColor = isNight ? Colors.grey[400]! : Theme.of(context).textTheme.bodySmall!.color!;

        final Map<String, Style> htmlStyle = <String, Style>{
          'body': Style(
            fontSize: FontSize(prefs.fontSize),
            lineHeight: LineHeight(prefs.lineHeight),
            color: textColor,
            margin: Margins.zero,
          ),
          'p': Style(
            fontSize: FontSize(prefs.fontSize),
            lineHeight: LineHeight(prefs.lineHeight),
            color: textColor,
          ),
        };

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: <Widget>[
              AppIconButton(
                icon: Icons.text_fields_outlined,
                tooltip: l10n.articleReadingSettings,
                onPressed: () => _showReadingSettingsSheet(context),
              ),
              AppIconButton(
                icon: Icons.open_in_browser_outlined,
                tooltip: l10n.articleDetailReadFull,
                onPressed: () => _openInBrowser(context, l10n),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openInBrowser(context, l10n),
            icon: const Icon(Icons.open_in_new_outlined),
            label: Text(l10n.articleDetailReadFull),
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            children: <Widget>[
              if (item.author != null || item.publishedAt != null)
                Row(
                  children: <Widget>[
                    if (item.author != null)
                      Expanded(
                        child: Text('${l10n.articleDetailAuthor}：${item.author}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: metaColor)),
                      ),
                    if (item.publishedAt != null)
                      AnimatedBuilder(
                        animation: GeneralSettingsStore.instance,
                        builder: (context, _) => Text(
                          '${l10n.articleDetailPublishedAt}：${_formatDate(item.publishedAt)}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: metaColor),
                        ),
                      ),
                  ],
                ),
              if (item.author != null || item.publishedAt != null)
                const SizedBox(height: AppTokens.spaceMd),
              if (item.coverUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  child: AppCoverImage(coverUrl: item.coverUrl, fit: BoxFit.cover),
                ),
              if (item.coverUrl != null) const SizedBox(height: AppTokens.spaceMd),
              if (html.isNotEmpty)
                Html(data: html, style: htmlStyle)
              else
                AppEmptyState(icon: Icons.article_outlined, message: l10n.articleDetailEmpty),
            ],
          ),
        );
      },
    );
  }
}
