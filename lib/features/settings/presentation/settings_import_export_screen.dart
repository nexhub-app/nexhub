/// Data import / export screen — supports custom export folder (persisted)
/// and real JSON bundle round-trip (D4 import / D5 export).
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../core/favorites/favorites_manager.dart';
import '../../../core/history/history_manager.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/settings/data_export_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';

/// Export scope selected from the three export entries.
enum _ExportScope { all, subscription, plugins }

class SettingsImportExportScreen extends StatefulWidget {
  const SettingsImportExportScreen({super.key});

  @override
  State<SettingsImportExportScreen> createState() =>
      _SettingsImportExportScreenState();
}

class _SettingsImportExportScreenState
    extends State<SettingsImportExportScreen> {
  String _exportFolder = '';
  final DataExportConfigStore _store = DataExportConfigStore();

  @override
  void initState() {
    super.initState();
    _store.load().then((config) {
      if (mounted) setState(() => _exportFolder = config.exportFolder);
    });
  }

  Future<String?> _pickExportFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      initialDirectory: _exportFolder.isNotEmpty ? _exportFolder : null,
    );
    if (result != null && mounted) {
      setState(() => _exportFolder = result);
      await _store.save(DataExportConfig(exportFolder: result));
      return result;
    }
    return null;
  }

  // ── D4: Import ──────────────────────────────────────────────────────────────

  Future<void> _pickImportFile() async {
    final l10n = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    if (result == null || !mounted) return;

    final filePath = result.files.single.path;
    if (filePath == null) {
      _snack(l10n.importDataInvalidFormat);
      return;
    }

    _snack(l10n.importDataParsing);
    try {
      final text = await File(filePath).readAsString();
      final data = jsonDecode(text);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid bundle structure');
      }
      final plugins = data['plugins'];
      final favorites = data['favorites'];
      final history = data['history'];
      if ((plugins != null && plugins is! List) ||
          (favorites != null && favorites is! List) ||
          (history != null && history is! List)) {
        throw const FormatException('Invalid bundle structure');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await _showImportPreview(
        plugins: plugins as List<dynamic>? ?? const <dynamic>[],
        favorites: favorites as List<dynamic>? ?? const <dynamic>[],
        history: history as List<dynamic>? ?? const <dynamic>[],
      );
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _snack(l10n.importDataInvalidFormat);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _snack(l10n.importDataFailed);
    }
  }

  Future<void> _showImportPreview({
    required List<dynamic> plugins,
    required List<dynamic> favorites,
    required List<dynamic> history,
  }) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.importPreviewTitle(
            plugins.length + favorites.length + history.length)),
        content: Text(
          l10n.importDataSummary(
            plugins.length,
            favorites.length,
            history.length,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirmImport),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final repo = context.read<SourceRepository>();
    final fav = context.read<FavoritesManager>();
    final hist = context.read<HistoryManager>();
    try {
      repo.importFromList(plugins);
      await fav.importFromList(favorites);
      await hist.importFromList(history);
      if (!mounted) return;
      _snack(
        l10n.importDataSummary(
          plugins.length,
          favorites.length,
          history.length,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _snack(l10n.importDataFailed);
    }
  }

  // ── D5: Export ─────────────────────────────────────────────────────────────

  void _showExportFolderPicker(BuildContext context,
      {required _ExportScope scope}) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXl),
        ),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: AppTokens.spaceMd),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(AppTokens.radiusFull),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppTokens.spaceLg),
                child: Text(
                  l10n.selectExportFolder,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.folder_special),
                title: Text(l10n.exportFolderDefault),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Navigator.pop(ctx);
                  final dir = await getApplicationDocumentsDirectory();
                  final exportDir = Directory('${dir.path}/NexHub/Exports');
                  if (!exportDir.existsSync()) {
                    exportDir.createSync(recursive: true);
                  }
                  if (!mounted) return;
                  await _doExport(exportDir.path, scope);
                },
              ),
              ListTile(
                leading: const Icon(Icons.save_outlined),
                title: Text(l10n.exportFolderCustom),
                subtitle:
                    _exportFolder.isNotEmpty ? Text(_exportFolder) : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Navigator.pop(ctx);
                  final folder = await _pickExportFolder();
                  if (folder != null && mounted) {
                    await _doExport(folder, scope);
                  }
                },
              ),
              const SizedBox(height: AppTokens.spaceXl),
            ],
          ),
        );
      },
    );
  }

  Future<void> _doExport(String folder, _ExportScope scope) async {
    final l10n = AppLocalizations.of(context);
    final repo = context.read<SourceRepository>();
    final fav = context.read<FavoritesManager>();
    final hist = context.read<HistoryManager>();

    final bundle = <String, dynamic>{};
    if (scope == _ExportScope.all || scope == _ExportScope.plugins) {
      bundle['plugins'] = repo.exportToJson();
    }
    if (scope == _ExportScope.all || scope == _ExportScope.subscription) {
      bundle['favorites'] = fav.exportToJson();
      bundle['history'] = hist.exportToJson();
    }

    final isEmpty = bundle.values.every((v) => v is List && v.isEmpty);
    if (isEmpty) {
      _snack(l10n.exportNothingToExport);
      return;
    }

    _snack(l10n.exportDataInProgress);
    try {
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final filePath = '$folder/nexhub_export_$stamp.json';
      final json = const JsonEncoder.withIndent('  ').convert(bundle);
      await File(filePath).writeAsString(json);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _snack(l10n.exportDataFileSaved(filePath));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _snack(l10n.exportDataFailed);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.dataImportExportTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        children: <Widget>[
          // ── Import ──
          _ImportExportGroupHeader(label: l10n.importData),
          AppListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: Text(l10n.importData),
            subtitle: Text(l10n.importDataDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickImportFile(),
          ),

          // ── Export ──
          const SizedBox(height: AppTokens.spaceXl),
          _ImportExportGroupHeader(label: l10n.exportData),

          AppListTile(
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.exportData),
            subtitle: Text(l10n.exportDataDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                _showExportFolderPicker(context, scope: _ExportScope.all),
          ),

          AppListTile(
            leading: const Icon(Icons.rss_feed_outlined),
            title: Text(l10n.exportSubscription),
            subtitle: Text(l10n.exportSubscriptionDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showExportFolderPicker(
                context, scope: _ExportScope.subscription),
          ),

          AppListTile(
            leading: const Icon(Icons.extension_outlined),
            title: Text(l10n.exportPlugins),
            subtitle: Text(l10n.exportPluginsDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                _showExportFolderPicker(context, scope: _ExportScope.plugins),
          ),

          // ── Custom export folder hint ──
          const SizedBox(height: AppTokens.spaceXl),
          Padding(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            child: Container(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              decoration: BoxDecoration(
                color:
                    Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  Expanded(
                    child: Text(
                      l10n.selectExportFolder,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable group header for import/export sections.
// ─────────────────────────────────────────────────────────────────────────────

class _ImportExportGroupHeader extends StatelessWidget {
  final String label;
  const _ImportExportGroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
