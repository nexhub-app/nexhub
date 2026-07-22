import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/rss/browse_article_feed_manager.dart';
import '../../../core/rss/rss_feed.dart';
import '../../../core/rss/rsshub_routes.dart';
import '../../../core/settings/rsshub_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_form_field.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/app_url_input_bar.dart';

/// 添加 RSS 订阅源（浏览页 → 添加订阅入口）。
///
/// 表单（URL / 标题 / 描述）经 [AppFormField] 统一，
/// 支持「测试连接」预览，保存写入独立的 [BrowseArticleFeedManager]。
class BrowseAddArticleFeedScreen extends StatefulWidget {
  final String? initialUrl;
  const BrowseAddArticleFeedScreen({super.key, this.initialUrl});

  @override
  State<BrowseAddArticleFeedScreen> createState() => _BrowseAddArticleFeedScreenState();
}

class _BrowseAddArticleFeedScreenState extends State<BrowseAddArticleFeedScreen> {
  final TextEditingController _urlCtl = TextEditingController();
  final TextEditingController _titleCtl = TextEditingController();
  final TextEditingController _descCtl = TextEditingController();
  ParsedFeed? _preview;
  bool _testing = false;
  bool _saving = false;
  String? _error;
  String _rssHubBase = 'https://rsshub.app';

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) _urlCtl.text = widget.initialUrl!;
    RssHubConfigStore().load().then((cfg) {
      if (mounted) setState(() => _rssHubBase = cfg.effectiveUrl);
    });
  }

  @override
  void dispose() {
    _urlCtl.dispose();
    _titleCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final url = _urlCtl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _testing = true;
      _error = null;
      _preview = null;
    });
    try {
      final parsed = await context.read<BrowseArticleFeedManager>().discoverFeed(url);
      if (mounted) setState(() => _preview = parsed);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final url = _urlCtl.text.trim();
    if (url.isEmpty) return;
    setState(() => _saving = true);
    try {
      await context.read<BrowseArticleFeedManager>().addFeed(
            url: url,
            title: _titleCtl.text.trim().isEmpty ? null : _titleCtl.text.trim(),
            description: _descCtl.text.trim().isEmpty ? null : _descCtl.text.trim(),
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).rssFeedSaved)),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.addRssFeed),
        actions: <Widget>[
          AppIconButton(
            icon: Icons.check,
            tooltip: l10n.save,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        children: <Widget>[
          AppUrlInputBar(
            controller: _urlCtl,
            hintText: l10n.rssFeedUrlHint,
            labelText: l10n.rssFeedUrl,
            isLoading: _testing,
            submitLabel: l10n.rssFeedTestConnection,
            onSubmit: (_) => _test(),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          AppFormField(
            label: l10n.rssFeedTitle,
            hint: l10n.rssFeedTitle,
            controller: _titleCtl,
            prefixIcon: const Icon(Icons.title),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          AppFormField(
            label: l10n.rssFeedDescription,
            hint: l10n.rssFeedDescription,
            controller: _descCtl,
            prefixIcon: const Icon(Icons.notes),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          if (_error != null)
            AppErrorState(message: l10n.rssFeedTestFailed, onRetry: _test, retryLabel: l10n.retry),
          if (_preview != null) _buildPreview(l10n),
          // RSSHub 路由推荐区
          const SizedBox(height: AppTokens.spaceLg),
          Text(l10n.rsshubRouteRecommend, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTokens.spaceSm),
          ...routesForType(null, l10n).map((route) => ListTile(
                leading: const Icon(Icons.route_outlined),
                title: Text(route.label),
                subtitle: Text(route.path),
                trailing: const Icon(Icons.add),
                onTap: () {
                  _urlCtl.text = '$_rssHubBase${route.path}';
                  setState(() {});
                },
              )),
        ],
      ),
    );
  }

  Widget _buildPreview(AppLocalizations l10n) {
    final feed = _preview!;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.rssFeedPreview, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceSm),
            Text(feed.title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppTokens.spaceSm),
            ...feed.items.take(3).map((item) => AppListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                )),
          ],
        ),
      ),
    );
  }
}
