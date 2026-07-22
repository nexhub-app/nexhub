/// 插件管理页 —— 统一管理所有已导入的插件（源），支持导入/导出。
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/unified_source_tile.dart';
import '../../sources/presentation/source_import_screen.dart';
import '../../sources/presentation/source_mirror_screen.dart';

/// 插件管理主页面（总管理：展示所有类型的源）。
class PluginManagementScreen extends StatefulWidget {
  const PluginManagementScreen({super.key});

  @override
  State<PluginManagementScreen> createState() =>
      _PluginManagementScreenState();
}

class _PluginManagementScreenState extends State<PluginManagementScreen> {
  Future<void> _openImport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SourceImportScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _exportPlugins() async {
    final repo = context.read<SourceRepository>();
    final all = repo.all;
    if (all.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).emptySources)),
        );
      }
      return;
    }

    // 收集所有源的 JSON 配置
    final List<Map<String, dynamic>> exportList =
        all.map((c) => c.toJson()).toList();
    final jsonString = jsonEncode(exportList);

    // 选择导出目录
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) {
      final file = File('$dir/nexhub_plugins_export.json');
      await file.writeAsString(jsonString);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).exportPlugins)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final repo = context.watch<SourceRepository>();
    final all = repo.all;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.pluginManagement)),
      body: all.isEmpty
          ? AppEmptyState(
              icon: Icons.extension,
              message: l10n.emptySources,
              actionLabel: l10n.addSource,
              onAction: _openImport,
            )
          : Column(
              children: <Widget>[
                // 顶部操作栏
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceLg),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _openImport,
                          icon: const Icon(Icons.add),
                          label: Text(l10n.addSource),
                        ),
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _exportPlugins,
                          icon: const Icon(Icons.upload_outlined),
                          label: Text(l10n.exportPlugins),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(AppTokens.spaceMd),
                    itemCount: all.length,
                    itemBuilder: (ctx, i) {
                      final s = all[i];
                      return UnifiedSourceTile(
                        name: s.name,
                        url: s.site.baseUrl,
                        enabled: s.isEnabled,
                        deprecated: s.isDeprecated,
                        deprecatedLabel: l10n.deprecated,
                        mirrorSettingsTooltip: l10n.mirrorSettings,
                        onMirrorSettings: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SourceMirrorScreen(source: s),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}
