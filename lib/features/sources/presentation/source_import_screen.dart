library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/scraper/collect_api_parser.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_form_field.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../core/widgets/app_segmented_tabs.dart';
import '../../../core/widgets/app_url_input_bar.dart';
import 'collect_api_import_screen.dart';

enum _ImportTab { url, file, json }

/// 源导入页：支持 URL / 本地文件 / 手动 JSON 三种方式，校验后保存。
class SourceImportScreen extends StatefulWidget {
  const SourceImportScreen({super.key});

  @override
  State<SourceImportScreen> createState() => _SourceImportScreenState();
}

class _SourceImportScreenState extends State<SourceImportScreen> {
  _ImportTab _tab = _ImportTab.url;
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _jsonController = TextEditingController();
  bool _loading = false;
  String? _error;
  PluginConfig? _preview;
  List<String> _validationErrors = const <String>[];
  bool _collectApiDetected = false;
  String? _pickedFileName;

  @override
  void dispose() {
    _urlController.dispose();
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _tryParse(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
      _validationErrors = const <String>[];
    });
    try {
      final config = PluginConfig.fromJsonString(text);
      final errors = config.validate();
      if (mounted) {
        setState(() {
          _preview = config;
          _validationErrors = errors;
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

  Future<void> _importFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (CollectApiParser.looksLikeCollectApi(url)) {
      if (mounted) setState(() => _collectApiDetected = true);
      return;
    }
    setState(() => _loading = true);
    try {
      final text = await HttpFetcher.instance.getHtml(url);
      await _tryParse(text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    _pickedFileName = result?.files.single.name;
    final text = await File(path).readAsString();
    _jsonController.text = text;
    await _tryParse(text);
  }

  void _retry() {
    if (_tab == _ImportTab.url) {
      _importFromUrl();
    } else if (_tab == _ImportTab.json) {
      _tryParse(_jsonController.text);
    } else {
      _pickFile();
    }
  }

  void _save() {
    if (_preview == null) return;
    context.read<SourceRepository>().addSource(_preview!);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).sourceImportSaved)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importSource)),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        children: <Widget>[
          AppSegmentedTabs<_ImportTab>(
            selected: <_ImportTab>{_tab},
            onSelectionChanged: (Set<_ImportTab> s) =>
                setState(() => _tab = s.first),
            segments: <ButtonSegment<_ImportTab>>[
              ButtonSegment<_ImportTab>(
                  value: _ImportTab.url, label: Text(l10n.sourceImportFromUrl)),
              ButtonSegment<_ImportTab>(
                  value: _ImportTab.file, label: Text(l10n.sourceImportFromFile)),
              ButtonSegment<_ImportTab>(
                  value: _ImportTab.json, label: Text(l10n.sourceImportFromJson)),
            ],
          ),
          const SizedBox(height: AppTokens.spaceLg),
          if (_tab == _ImportTab.url) ...<Widget>[
            AppUrlInputBar(
              controller: _urlController,
              hintText: l10n.sourceImportUrlHint,
              submitLabel: l10n.import,
              isLoading: _loading && _tab == _ImportTab.url,
              onSubmit: (_) => _importFromUrl(),
            ),
            if (_collectApiDetected) ...<Widget>[
              const SizedBox(height: AppTokens.spaceMd),
              _collectApiHint(l10n),
            ],
          ] else if (_tab == _ImportTab.file) ...<Widget>[
            FilledButton.icon(
              onPressed: _loading ? null : _pickFile,
              icon: const Icon(Icons.file_open),
              label: Text(l10n.sourceImportFilePicker),
            ),
            if (_pickedFileName != null) ...<Widget>[
              const SizedBox(height: AppTokens.spaceMd),
              Text(
                _pickedFileName!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ] else ...<Widget>[
            AppFormField(
              label: l10n.sourceImportJsonHint,
              hint: l10n.sourceImportJsonHint,
              controller: _jsonController,
              maxLines: 10,
            ),
            const SizedBox(height: AppTokens.spaceMd),
            FilledButton.icon(
              onPressed: _loading ? null : () => _tryParse(_jsonController.text),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(l10n.sourceImportValidate),
            ),
          ],
          const SizedBox(height: AppTokens.spaceLg),
          _buildPreview(l10n, scheme),
        ],
      ),
    );
  }

  Widget _collectApiHint(AppLocalizations l10n) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.sourceImportCollectApiDetected,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceMd),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CollectApiImportScreen(),
                ),
              ),
              child: Text(l10n.sourceImportCollectApiRedirect),
            ),
          ],
        ),
      );

  Widget _buildPreview(AppLocalizations l10n, ColorScheme scheme) {
    if (_loading) {
      return AppLoadingIndicator(message: l10n.loading);
    }
    if (_error != null) {
      return AppErrorState(
        message: _error!,
        onRetry: _retry,
        retryLabel: l10n.retry,
      );
    }
    if (_preview == null) return const SizedBox.shrink();
    final PluginConfig c = _preview!;
    final bool valid = _validationErrors.isEmpty;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(c.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            c.site.baseUrl,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Chip(
            label: Text(c.type.apiName),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          if (valid)
            Row(
              children: <Widget>[
                Icon(Icons.check_circle, color: scheme.primary, size: 18),
                const SizedBox(width: AppTokens.spaceXs),
                Text(l10n.sourceImportValid),
              ],
            )
          else ...<Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.error_outline, color: scheme.error, size: 18),
                const SizedBox(width: AppTokens.spaceXs),
                Text(l10n.sourceImportInvalid,
                    style: TextStyle(color: scheme.error)),
              ],
            ),
            const SizedBox(height: AppTokens.spaceXs),
            Text(l10n.sourceImportErrors,
                style: Theme.of(context).textTheme.labelMedium),
            ..._validationErrors.map(
              (e) => Padding(
                padding:
                    const EdgeInsets.only(left: AppTokens.spaceMd, top: 2),
                child: Text(
                  '• $e',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceLg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: valid ? _save : null,
              child: Text(l10n.save),
            ),
          ),
        ],
      ),
    );
  }
}
