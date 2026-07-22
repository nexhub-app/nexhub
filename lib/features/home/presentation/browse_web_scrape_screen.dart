import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/local/local_content_manager.dart';
import '../../../core/scraper/verification_detector.dart';
import '../../../core/scraper/web_scrape_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_segmented_tabs.dart';
import '../../../core/widgets/app_url_input_bar.dart';
import '../../../features/verification/presentation/webview_verification_screen.dart';
import 'local_media_viewer.dart';

/// 网页爬取（浏览页占位功能之一）。
///
/// 五种模式：通用 / 小说 / 漫画 / 视频 / 文章。结果按模式差异化展示，
/// 命中验证特征时通过 [navigateToVerification] 引导用户完成验证后重试。
class BrowseWebScrapeScreen extends StatefulWidget {
  final ScrapeMode? initialMode;
  const BrowseWebScrapeScreen({super.key, this.initialMode});

  @override
  State<BrowseWebScrapeScreen> createState() => _BrowseWebScrapeScreenState();
}

class _BrowseWebScrapeScreenState extends State<BrowseWebScrapeScreen> {
  ScrapeMode _mode = ScrapeMode.general;
  final TextEditingController _urlCtl = TextEditingController();
  bool _loading = false;
  String? _error;
  ScrapeResult? _result;

  @override
  void initState() {
    super.initState();
    if (widget.initialMode != null) _mode = widget.initialMode!;
  }

  @override
  void dispose() {
    _urlCtl.dispose();
    super.dispose();
  }

  Future<void> _scrape(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await WebScrapeService.instance.scrape(url, _mode);
      if (mounted) {
        setState(() {
          _result = result;
          _loading = false;
        });
      }
    } on VerificationRequiredException catch (e) {
      if (!mounted) return;
      final ok = await navigateToVerification(context, url: url, exception: e);
      if (ok && mounted) {
        _scrape(url);
      } else if (mounted) {
        setState(() => _loading = false);
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

  void _scrapeUrl(String url) {
    _urlCtl.text = url;
    _scrape(url);
  }

  Future<void> _openNovelText(String title) async {
    if (_result == null || _result!.paragraphs.isEmpty) return;
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'scrape_${DateTime.now().microsecondsSinceEpoch}.txt'));
    await file.writeAsString(_result!.paragraphs.join('\n\n'));
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalMediaViewer(
          title: title,
          kind: LocalMediaKind.text,
          uri: file.path,
        ),
      ),
    );
  }

  Future<void> _openImages(String title) async {
    if (_result == null || _result!.imageUrls.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalMediaViewer(
          title: title,
          kind: LocalMediaKind.images,
          uri: _result!.imageUrls.first,
          gallery: _result!.imageUrls,
        ),
      ),
    );
  }

  Future<void> _launch(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).loadFailed)),
        );
      }
    }
  }

  Future<void> _openVideoInApp(String url, AppLocalizations l10n) async {
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LocalMediaViewer(
            title: _result?.pageTitle ?? l10n.scrapeResultTitle,
            kind: LocalMediaKind.video,
            uri: url,
          ),
        ),
      );
    } catch (_) {
      await _launch(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.browseWebScrape)),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: Column(
              children: <Widget>[
                AppSegmentedTabs<ScrapeMode>(
                  selected: <ScrapeMode>{_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                  segments: <ButtonSegment<ScrapeMode>>[
                    ButtonSegment<ScrapeMode>(value: ScrapeMode.general, label: Text(l10n.scrapeModeGeneral)),
                    ButtonSegment<ScrapeMode>(value: ScrapeMode.novel, label: Text(l10n.scrapeModeNovel)),
                    ButtonSegment<ScrapeMode>(value: ScrapeMode.comic, label: Text(l10n.scrapeModeComic)),
                    ButtonSegment<ScrapeMode>(value: ScrapeMode.video, label: Text(l10n.scrapeModeVideo)),
                    ButtonSegment<ScrapeMode>(value: ScrapeMode.article, label: Text(l10n.scrapeModeArticle)),
                  ],
                ),
                const SizedBox(height: AppTokens.spaceMd),
                AppUrlInputBar(
                  controller: _urlCtl,
                  hintText: l10n.scrapeUrlHint,
                  isLoading: _loading,
                  submitLabel: l10n.scrapeStart,
                  onSubmit: _scrape,
                ),
              ],
            ),
          ),
          Expanded(child: _buildResult(l10n, scheme)),
        ],
      ),
    );
  }

  Widget _buildResult(AppLocalizations l10n, ColorScheme scheme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return AppErrorState(message: l10n.loadFailed, onRetry: () => _scrape(_urlCtl.text), retryLabel: l10n.retry);
    }
    final result = _result;
    if (result == null) {
      return AppEmptyState(icon: Icons.travel_explore, message: l10n.scrapeUrlHint);
    }
    if (result.isEmpty) {
      return AppEmptyState(icon: Icons.search_off, message: l10n.scrapeNoResults);
    }

    final title = result.pageTitle ?? l10n.scrapeResultTitle;

    return ListView(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      children: <Widget>[
        if (result.pageTitle != null)
          Text(result.pageTitle!, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppTokens.spaceMd),
        if (_mode == ScrapeMode.general) ..._buildLinks(l10n),
        if (_mode == ScrapeMode.novel || _mode == ScrapeMode.article) ..._buildText(l10n, title, scheme),
        if (_mode == ScrapeMode.comic) ..._buildImages(l10n, title, scheme),
        if (_mode == ScrapeMode.video) ..._buildVideos(l10n, scheme),
      ],
    );
  }

  List<Widget> _buildLinks(AppLocalizations l10n) => <Widget>[
        Text(l10n.scrapeResultLinks, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppTokens.spaceSm),
        ..._result!.links.map((link) => ListTile(
              leading: const Icon(Icons.link),
              title: Text(link.text.isEmpty ? link.url : link.text, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(link.url, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.open_in_new),
                tooltip: l10n.openInBrowser,
                onPressed: () => _launch(link.url),
              ),
              onTap: () => _scrapeUrl(link.url),
            )),
      ];

  List<Widget> _buildText(AppLocalizations l10n, String title, ColorScheme scheme) => <Widget>[
        if (_result!.paragraphs.isNotEmpty)
          FilledButton.icon(
            onPressed: () => _openNovelText(title),
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(l10n.scrapeOpenInReader),
          ),
        const SizedBox(height: AppTokens.spaceMd),
        if (_result!.imageUrls.isNotEmpty) ..._buildImages(l10n, title, scheme),
        const SizedBox(height: AppTokens.spaceMd),
        SelectableText(
          _result!.paragraphs.join('\n\n'),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ];

  List<Widget> _buildImages(AppLocalizations l10n, String title, ColorScheme scheme) => <Widget>[
        Text(l10n.scrapeResultImages, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppTokens.spaceSm),
        FilledButton.icon(
          onPressed: () => _openImages(title),
          icon: const Icon(Icons.visibility_outlined),
          label: Text(l10n.scrapeOpenInReader),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceSm,
          children: _result!.imageUrls
              .take(12)
              .map((u) => InkWell(
                    onTap: () => _openImages(title),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      child: Image.network(u, width: 96, height: 128, fit: BoxFit.cover),
                    ),
                  ))
              .toList(),
        ),
      ];

  List<Widget> _buildVideos(AppLocalizations l10n, ColorScheme scheme) => <Widget>[
        Text(l10n.scrapeResultVideos, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppTokens.spaceSm),
        FilledButton.icon(
          onPressed: () => _openVideoInApp(_result!.videoUrls.first, l10n),
          icon: const Icon(Icons.play_arrow_outlined),
          label: Text(l10n.scrapeOpenInPlayer),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        ..._result!.videoUrls.map((u) => ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(u, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _openVideoInApp(u, l10n),
            )),
      ];
}
