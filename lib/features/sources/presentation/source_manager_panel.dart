/// 单模块源管理面板（升级版）。
///
/// 用于各模块首页的「源」区块，提供：
/// - 源列表（[UnifiedSourceTile] 更多菜单，含 开关/编辑/删除/隐藏/镜像设置）
/// - 本地导入：选择文件 或 选择文件夹（递归扫描 json/txt/xml）→ 预览勾选 → 确认导入
/// - 空状态时引导「选择文件夹导入」与「采集 API 导入」
///
/// 仅显示 [filterType] 对应的源（不含三模块 Tab）。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/unified_source_tile.dart';
import 'source_mirror_screen.dart';

/// 本地导入预览项。
class _ImportPreviewItem {
  final String path;
  final String fileName;
  final PluginConfig? config;
  final bool isValid;
  final String? error;

  _ImportPreviewItem({
    required this.path,
    required this.fileName,
    this.config,
    this.isValid = false,
    this.error,
  });
}

/// 单模块源管理面板。
class SourceManagerPanel extends StatefulWidget {
  final SourceType filterType;
  final VoidCallback? onImportFromCollectApi;

  const SourceManagerPanel({
    super.key,
    required this.filterType,
    this.onImportFromCollectApi,
  });

  @override
  State<SourceManagerPanel> createState() => _SourceManagerPanelState();
}

class _SourceManagerPanelState extends State<SourceManagerPanel> {
  List<_ImportPreviewItem> _previewItems = <_ImportPreviewItem>[];
  Set<int> _selectedPreviewIndices = <int>{};
  bool _previewMode = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_previewMode) return _buildImportPreview(l10n);

    final SourceRepository repo = context.watch<SourceRepository>();
    final List<PluginConfig> sources = repo.all
        .where((PluginConfig c) => c.type == widget.filterType)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      children: <Widget>[
        _buildImportBar(l10n),
        const SizedBox(height: AppTokens.spaceMd),
        if (sources.isEmpty)
          AppEmptyState(
            icon: Icons.extension_outlined,
            message: l10n.sourceListEmpty,
            actionLabel: l10n.selectFolder,
            onAction: _pickLocalFolder,
            secondaryActionLabel: l10n.collectApiImportTitle,
            onSecondaryAction: widget.onImportFromCollectApi,
          )
        else
          ...sources.map((s) => _buildSourceTile(l10n, s)),
      ],
    );
  }

  /// 顶部「本地导入」操作条（选择文件 / 选择文件夹）。
  Widget _buildImportBar(AppLocalizations l10n) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.file_present_outlined),
                label: Text(l10n.localImportPickFile),
                onPressed: _previewMode ? null : _pickLocalFile,
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.folder_outlined),
                label: Text(l10n.selectFolder),
                onPressed: _previewMode ? null : _pickLocalFolder,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单个源的列表项（更多菜单含完整操作）。
  Widget _buildSourceTile(AppLocalizations l10n, PluginConfig s) {
    final repo = context.read<SourceRepository>();
    return UnifiedSourceTile(
      name: s.name,
      url: s.site.baseUrl,
      enabled: s.isEnabled,
      deprecated: s.isDeprecated,
      isHidden: s.isHidden,
      deprecatedLabel: l10n.deprecated,
      mirrorSettingsTooltip: l10n.mirrorSettings,
      hideTooltip: l10n.sourceHide,
      unhideTooltip: l10n.sourceShowHidden,
      editTooltip: l10n.sourceEdit,
      deleteTooltip: l10n.sourceDelete,
      useMoreMenu: true,
      moreMenuTooltip: l10n.moreActions,
      onToggle: (bool value) => repo.setEnabled(s.id, value),
      onMirrorSettings: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SourceMirrorScreen(source: s)),
      ),
      onHide: () => repo.setHidden(s.id, !s.isHidden),
      onEdit: () => _showEditDialog(s),
      onDelete: () => _showDeleteConfirm(s),
    );
  }

  // ── 本地导入：选择 ───────────────────────────────────────────────

  Future<void> _pickLocalFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json', 'txt', 'xml'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    _processPickedPaths(
      result.files.map((f) => f.path).whereType<String>().toList(),
    );
  }

  Future<void> _pickLocalFolder() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null || dirPath.isEmpty) return;
    final files = <String>[];
    try {
      final dir = Directory(dirPath);
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (ext == '.json' || ext == '.txt' || ext == '.xml') {
            files.add(entity.path);
          }
        }
      }
    } on Object {
      // 目录读取失败忽略
    }
    if (files.isEmpty) return;
    _processPickedPaths(files);
  }

  Future<void> _processPickedPaths(List<String> paths) async {
    final items = <_ImportPreviewItem>[];
    for (final path in paths) {
      final fileName = p.basename(path);
      try {
        final raw = await File(path).readAsString();
        final config = PluginConfig.fromJsonString(raw);
        items.add(_ImportPreviewItem(
          path: path,
          fileName: fileName,
          config: config,
          isValid: true,
        ));
      } on Object catch (e) {
        items.add(_ImportPreviewItem(
          path: path,
          fileName: fileName,
          isValid: false,
          error: e.toString(),
        ));
      }
    }
    if (!mounted) return;
    setState(() {
      _previewItems = items;
      _selectedPreviewIndices = <int>{
        for (int i = 0; i < items.length; i++)
          if (items[i].isValid) i,
      };
      _previewMode = true;
    });
  }

  // ── 本地导入：预览 + 确认 ─────────────────────────────────────────

  Widget _buildImportPreview(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: l10n.back,
              onPressed: () => setState(() {
                _previewMode = false;
                _previewItems = <_ImportPreviewItem>[];
                _selectedPreviewIndices = <int>{};
              }),
            ),
            Expanded(
              child: Text(
                l10n.importPreviewTitle(_previewItems.length),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: _previewItems.isEmpty
                  ? null
                  : () => setState(() {
                        _selectedPreviewIndices =
                            <int>{for (int i = 0; i < _previewItems.length; i++) i};
                      }),
              child: Text(l10n.selectAll),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceSm),
        if (_previewItems.isEmpty)
          AppEmptyState(
            icon: Icons.folder_open_outlined,
            message: l10n.localImportHint,
          )
        else
          ..._previewItems.asMap().entries.map((e) {
            final i = e.key;
            final item = e.value;
            return CheckboxListTile(
              value: _selectedPreviewIndices.contains(i),
              onChanged: item.isValid
                  ? (v) => setState(() {
                        if (v == true) {
                          _selectedPreviewIndices.add(i);
                        } else {
                          _selectedPreviewIndices.remove(i);
                        }
                      })
                  : null,
              title: Text(item.fileName),
              subtitle: item.isValid
                  ? Text(item.config?.name ?? item.fileName)
                  : Text(item.error ?? l10n.sourceImportInvalid,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
              controlAffinity: ListTileControlAffinity.leading,
            );
          }),
        const SizedBox(height: AppTokens.spaceMd),
        FilledButton.icon(
          icon: const Icon(Icons.check),
          label: Text(l10n.confirmImport),
          onPressed: _selectedPreviewIndices.isEmpty ? null : _confirmImport,
        ),
      ],
    );
  }

  Future<void> _confirmImport() async {
    final l10n = AppLocalizations.of(context);
    final repo = context.read<SourceRepository>();
    final total = _selectedPreviewIndices.length;
    int success = 0;
    for (final i in _selectedPreviewIndices) {
      final item = _previewItems[i];
      if (item.isValid && item.config != null) {
        repo.addSource(item.config!);
        success++;
      }
    }
    if (!mounted) return;
    setState(() {
      _previewMode = false;
      _previewItems = <_ImportPreviewItem>[];
      _selectedPreviewIndices = <int>{};
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.sourceImportResult(success, total))),
    );
  }

  // ── 单源操作：编辑 / 删除 ─────────────────────────────────────────

  void _showEditDialog(PluginConfig s) {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: s.name);
    final urlCtrl = TextEditingController(text: s.site.baseUrl);
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.sourceEdit),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: l10n.sourceName),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.requiredHint : null,
              ),
              const SizedBox(height: AppTokens.spaceSm),
              TextFormField(
                controller: urlCtrl,
                decoration: InputDecoration(labelText: l10n.sourceBaseUrl),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.requiredHint : null,
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              final ok = context.read<SourceRepository>().updateSource(
                    s.id,
                    name: nameCtrl.text.trim(),
                    baseUrl: urlCtrl.text.trim(),
                  );
              Navigator.of(dialogContext).pop();
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.sourceCannotEdit)),
                );
              }
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(PluginConfig s) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmContent(s.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final ok =
                  context.read<SourceRepository>().removeSource(s.id);
              Navigator.of(dialogContext).pop();
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.sourceCannotDelete)),
                );
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}
