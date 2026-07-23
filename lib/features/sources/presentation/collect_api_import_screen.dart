library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/models/category_entry.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/scraper/collect_api_parser.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_form_field.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../core/widgets/app_url_input_bar.dart';
import '../../../core/widgets/content_card.dart';

/// 采集 API 导入页：识别 MacCMS 类采集接口，预览内容并生成源配置。
class CollectApiImportScreen extends StatefulWidget {
  const CollectApiImportScreen({super.key});

  @override
  State<CollectApiImportScreen> createState() => _CollectApiImportScreenState();
}

class _CollectApiImportScreenState extends State<CollectApiImportScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _detected = false;
  String _baseUrl = '';
  List<MediaItem> _items = const <MediaItem>[];
  List<CategoryEntry> _categories = const <CategoryEntry>[];
  SourceType _sourceType = SourceType.animeSource;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  PluginConfig _tempSource(String url) => PluginConfig(
        id: 'temp',
        name: 'temp',
        type: _sourceType,
        site: SiteConfig(
          domain: Uri.tryParse(url)?.host ?? '',
          baseUrl: _baseUrl,
        ),
        parser: const ParserConfig(type: 'builtin'),
      );

  Future<void> _detect(String url) async {
    url = url.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      if (mounted) setState(() => _error = AppLocalizations.of(context).collectApiInvalidUrl);
      return;
    }
    final origin = uri.origin;
    setState(() {
      _loading = true;
      _error = null;
      _detected = false;
      _baseUrl = origin;
    });
    try {
      final json = await HttpFetcher.instance.getJson(url);
      final items = CollectApiParser.parseList(json, _tempSource(url));
      final cats = CollectApiParser.parseCategories(json);
      if (mounted) {
        setState(() {
          _items = items;
          _categories = cats;
          _detected = true;
          _loading = false;
          if (_nameController.text.isEmpty) {
            _nameController.text = uri.host;
          }
          if (_idController.text.isEmpty) {
            _idController.text = uri.host.replaceAll(RegExp(r'[^a-z0-9]'), '');
          }
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

  PluginConfig _buildConfig() => PluginConfig(
        id: _idController.text.trim().isEmpty
            ? _baseUrl
            : _idController.text.trim(),
        name: _nameController.text.trim().isEmpty
            ? _baseUrl
            : _nameController.text.trim(),
        type: _sourceType,
        site: SiteConfig(
          domain: Uri.tryParse(_baseUrl)?.host ?? _baseUrl,
          baseUrl: _baseUrl,
        ),
        parser: const ParserConfig(type: 'builtin'),
        routes: <String, RouteConfig>{
          'latest': RouteConfig(
              url: '$_baseUrl/api.php/provide/vod/?ac=list&pg={page}'),
          'search': RouteConfig(
              url: '$_baseUrl/api.php/provide/vod/?ac=list&wd={keyword}'),
          'detail': RouteConfig(
              url: '$_baseUrl/api.php/provide/vod/?ac=detail&ids={id}'),
          'episodes': RouteConfig(
              url: '$_baseUrl/api.php/provide/vod/?ac=detail&ids={id}'),
        },
        category: const CategoryConfig(dynamicCategories: true),
      );

  void _save() {
    context.read<SourceRepository>().addSource(_buildConfig());
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).collectApiSaved)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.collectApiImportTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        children: <Widget>[
          AppUrlInputBar(
            controller: _urlController,
            hintText: l10n.collectApiUrlHint,
            submitLabel: l10n.collectApiDetect,
            isLoading: _loading,
            onSubmit: _detect,
          ),
          const SizedBox(height: AppTokens.spaceLg),
          if (_loading) AppLoadingIndicator(message: l10n.collectApiDetecting),
          if (_error != null)
            AppErrorState(
              message: _error!,
              onRetry: () => _detect(_urlController.text),
              retryLabel: l10n.retry,
            ),
          if (_detected) ...<Widget>[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.collectApiSiteName,
                      style: Theme.of(context).textTheme.labelMedium),
                  Text(_baseUrl,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppTokens.spaceSm),
                  Text('${l10n.collectApiCategories}: ${_categories.length}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            if (_categories.isNotEmpty) ...<Widget>[
              Text(l10n.collectApiCategories,
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: AppTokens.spaceSm),
              Wrap(
                spacing: AppTokens.spaceSm,
                runSpacing: AppTokens.spaceXs,
                children: _categories
                    .map((c) => Chip(
                          label: Text(c.title),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
              const SizedBox(height: AppTokens.spaceMd),
            ],
            if (_items.isNotEmpty) ...<Widget>[
              Text(l10n.collectApiPreview,
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: AppTokens.spaceSm),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 130,
                  childAspectRatio: AppTokens.coverAspectRatio,
                  crossAxisSpacing: AppTokens.spaceSm,
                  mainAxisSpacing: AppTokens.spaceSm,
                ),
                itemCount: _items.length > 6 ? 6 : _items.length,
                itemBuilder: (ctx, i) {
                  final item = _items[i];
                  return ContentCard(
                    coverUrl: item.coverUrl,
                    source: ctx.read<SourceRepository>().getById(item.sourceId ?? ''),
                    title: item.title,
                    subtitle: item.status,
                    width: 120,
                  );
                },
              ),
              const SizedBox(height: AppTokens.spaceMd),
            ],
            Text(l10n.sourceType,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppTokens.spaceSm),
            SegmentedButton<SourceType>(
              segments: <ButtonSegment<SourceType>>[
                ButtonSegment<SourceType>(
                  value: SourceType.animeSource,
                  label: Text(l10n.sourceTypeAnime),
                ),
                ButtonSegment<SourceType>(
                  value: SourceType.mangaSource,
                  label: Text(l10n.sourceTypeManga),
                ),
                ButtonSegment<SourceType>(
                  value: SourceType.novelSource,
                  label: Text(l10n.sourceTypeNovel),
                ),
              ],
              selected: <SourceType>{_sourceType},
              onSelectionChanged: (Set<SourceType> selection) {
                setState(() => _sourceType = selection.first);
              },
            ),
            const SizedBox(height: AppTokens.spaceMd),
            AppFormField(
              label: l10n.collectApiSourceName,
              controller: _nameController,
            ),
            const SizedBox(height: AppTokens.spaceMd),
            AppFormField(
              label: l10n.collectApiSourceId,
              controller: _idController,
            ),
            const SizedBox(height: AppTokens.spaceLg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: Text(l10n.collectApiSave),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
