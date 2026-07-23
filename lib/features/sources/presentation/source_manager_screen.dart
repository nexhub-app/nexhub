/// 源管理页 —— 新版设计：Tab 式布局（源列表 / 网络导入 / 本地导入）。
///
/// 支持按类型过滤，不同模块的源管理不互通。
library;

import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_segmented_tabs.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/unified_source_tile.dart';
import '../../shuyuan/presentation/shuyuan_import_screen.dart';
import '../../shuyuan/shuyuan_adapter.dart';
import '../../shuyuan/shuyuan_source_service.dart';
import 'collect_api_import_screen.dart';
import 'source_mirror_screen.dart';

enum _SourceTab { list, network, local }

/// 源管理主页面。
class SourceManagerScreen extends StatefulWidget {
  /// 可选的类型过滤（null = 显示全部类型，用于设置页总入口）。
  final SourceType? filterType;

  /// 嵌入模式：为 [true] 时不包裹 Scaffold/AppBar/FAB，
  /// 仅输出 Tab 栏 + 内容区 Column，供各模块首页的 sourcesBody 使用。
  final bool embedded;

  /// 预览模式变化回调。嵌入模式下，外层 [LibraryShell] 用此回调
  /// 在预览期间隐藏自己的 FAB（避免遮挡底部的确认条）。
  final void Function(bool isPreview)? onPreviewModeChanged;

  const SourceManagerScreen({
    super.key,
    this.filterType,
    this.embedded = false,
    this.onPreviewModeChanged,
  });

  @override
  State<SourceManagerScreen> createState() => _SourceManagerScreenState();
}

class _SourceManagerScreenState extends State<SourceManagerScreen> {
  _SourceTab _tab = _SourceTab.list;
  final TextEditingController _urlController = TextEditingController();

  // 是否显示隐藏源
  bool _showHidden = false;

  // 网络导入状态
  bool _networkLoading = false;
  String? _networkError;
  PluginConfig? _networkPreview;
  List<String> _validationErrors = <String>[];

  // 本地导入状态
  String? _pickedFileName;
  List<_ImportPreviewItem> _previewItems = <_ImportPreviewItem>[];
  Set<int> _selectedPreviewIndices = <int>{};
  bool _previewMode = false;

  // 类型筛选时被跳过的其他类型源数量（用于预览提示横幅）
  int _skippedByTypeCount = 0;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // ── 源列表 ──
  List<PluginConfig> _getFilteredSources(SourceRepository repo) {
    var sources = repo.all;
    if (widget.filterType != null) {
      sources = sources.where((c) => c.type == widget.filterType).toList();
    }
    // 隐藏源默认不显示，除非用户开启「显示隐藏源」
    if (!_showHidden) {
      sources = sources.where((c) => !c.isHidden).toList();
    }
    return sources;
  }

  /// 按分类 Tab 过滤源（项 7）。
  /// [category] 对应 Tab 索引：0=novel, 1=media, 2=comic。
  List<PluginConfig> _getCategorySources(
    List<PluginConfig> sources,
    int category,
  ) {
    switch (category) {
      case 0:
        return sources.where((c) => c.type == SourceType.novelSource).toList();
      case 1:
        // 媒体 Tab：animeSource（无 type 的旧源默认归 media，但 PluginConfig
        // 强制 type 非空，因此此处无需额外兜底）。
        return sources.where((c) => c.type == SourceType.animeSource).toList();
      case 2:
        return sources.where((c) => c.type == SourceType.mangaSource).toList();
      default:
        return sources;
    }
  }

  // ── 网络导入逻辑 ──
  Future<void>_fetchFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _networkLoading = true;
      _networkError = null;
      _networkPreview = null;
      _validationErrors = <String>[];
    });

    try {
      // 这里需要 HttpFetcher，但为避免循环依赖，用基础的 HttpClient
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      httpClient.close();

      final config = PluginConfig.fromJsonString(text);
      final errors = config.validate();

      if (mounted) {
        setState(() {
          _networkPreview = config;
          _validationErrors = errors;
          _networkLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _networkError = e.toString();
          _networkLoading = false;
        });
      }
    }
  }

  void _saveNetworkSource() {
    if (_networkPreview == null || _validationErrors.isNotEmpty) return;
    context.read<SourceRepository>().addSource(_networkPreview!);
    setState(() {
      _urlController.clear();
      _networkPreview = null;
      _validationErrors = <String>[];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).sourceImportSaved)),
    );
  }

  // ── 本地导入逻辑（支持文件 + 文件夹 + 预览勾选）──
  Future<void> _pickLocalFile() async {
    // 支持选择单个文件或文件夹
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['json', 'txt', 'xml'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    _processPickedPaths(result.files.map((f) => f.path).whereType<String>().toList());
  }

  /// 选择文件夹导入。
  Future<void> _pickLocalFolder() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return;

    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    // 扫描目录下的所有支持的源文件
    final files = <String>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase().replaceFirst('.', '');
        if (const ['json', 'txt', 'xml'].contains(ext)) {
          files.add(entity.path);
        }
      }
    }

    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).noLocalSource)),
        );
      }
      return;
    }

    _processPickedPaths(files);
  }

  /// 处理选中的文件路径列表：解析预览 → 弹出勾选对话框 → 导入选中项。
  Future<void> _processPickedPaths(List<String> paths) async {
    var items = <_ImportPreviewItem>[];
    for (final path in paths) {
      try {
        final text = await File(path).readAsString();
        _ImportPreviewItem item;
        try {
          final config = PluginConfig.fromJsonString(text);
          item = _ImportPreviewItem(
            path: path,
            fileName: p.basename(path),
            config: config,
            type: config.type,
            isValid: config.validate().isEmpty,
          );
        } on PluginConfigException catch (pe) {
          // 旧格式源（Legado 书源等）缺少 "type" 字段或字段名不同。
          // 回退到 ShuyuanSourceService 解析 Legado/阅读 格式，再通过
          // ShuyuanAdapter 转为 PluginConfig。
          if (widget.filterType != null) {
            try {
              final shuyuanService = ShuyuanSourceService();
              final shuyuanSources = shuyuanService.parseSources(text);
              if (shuyuanSources.isNotEmpty) {
                final config = ShuyuanAdapter.toPluginConfig(
                  shuyuanSources.first,
                );
                item = _ImportPreviewItem(
                  path: path,
                  fileName: p.basename(path),
                  config: config,
                  type: config.type,
                  isValid: config.validate().isEmpty,
                );
              } else {
                item = _ImportPreviewItem(
                  path: path,
                  fileName: p.basename(path),
                  config: null,
                  type: widget.filterType,
                  isValid: false,
                  error: '${AppLocalizations.of(context).shuyuanImportParseFailed}: ${pe.message}',
                );
              }
            } on Object catch (re) {
              item = _ImportPreviewItem(
                path: path,
                fileName: p.basename(path),
                config: null,
                type: widget.filterType,
                isValid: false,
                error: re.toString(),
              );
            }
          } else {
            item = _ImportPreviewItem(
              path: path,
              fileName: p.basename(path),
              config: null,
              type: null,
              isValid: false,
              error: pe.toString(),
            );
          }
        } on Object catch (e) {
          item = _ImportPreviewItem(
            path: path,
            fileName: p.basename(path),
            config: null,
            type: null,
            isValid: false,
            error: e.toString(),
          );
        }
        items.add(item);
      } on Object catch (e) {
        items.add(_ImportPreviewItem(
          path: path,
          fileName: p.basename(path),
          config: null,
          type: null,
          isValid: false,
          error: e.toString(),
        ));
      }
    }

    // 自动按类型筛选：在「专属类型」源管理页（如小说源页）只保留该类型，
    // 其他类型源被跳过（解析失败的文件仍保留以显示错误）。
    int skippedByType = 0;
    if (widget.filterType != null) {
      final filtered = <_ImportPreviewItem>[];
      for (final it in items) {
        if (it.config != null && it.type != widget.filterType) {
          skippedByType++;
        } else {
          filtered.add(it);
        }
      }
      items = filtered;
    }

    if (!mounted) return;

    // 专属类型页导入时，文件夹/文件中没有任何可导入的当前类型源。
    if (items.isEmpty && widget.filterType != null) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.importNoMatchingType(
              _typeLabel(widget.filterType!, l10n),
              skippedByType,
            ),
          ),
        ),
      );
      return;
    }

    setState(() {
      _previewItems = items;
      _selectedPreviewIndices = items
          .asMap()
          .entries
          .where((e) => e.value.isValid)
          .map((e) => e.key)
          .toSet();
      _previewMode = true;
      _pickedFileName = null;
      _skippedByTypeCount = skippedByType;
    });
    widget.onPreviewModeChanged?.call(true);
  }

  /// 将 SourceType 映射为本地化分类标签。
  String _typeLabel(SourceType type, AppLocalizations l10n) {
    switch (type) {
      case SourceType.novelSource:
        return l10n.sourceCategoryNovel;
      case SourceType.animeSource:
        return l10n.sourceCategoryMedia;
      case SourceType.mangaSource:
        return l10n.sourceCategoryComic;
    }
  }

  /// 确认导入选中的预览项。
  void _confirmImport() {
    final selected = _previewItems
        .asMap()
        .entries
        .where((e) => _selectedPreviewIndices.contains(e.key) && e.value.isValid)
        .map((e) => e.value)
        .toList();

    int successCount = 0;
    for (final item in selected) {
      try {
        context.read<SourceRepository>().addSource(item.config!);
        successCount++;
      } on Object { /* 单个失败不影响其他 */ }
    }

    if (mounted) {
      setState(() {
        _previewItems = <_ImportPreviewItem>[];
        _selectedPreviewIndices = <int>{};
        _previewMode = false;
        _skippedByTypeCount = 0;
      });
      widget.onPreviewModeChanged?.call(false);

      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.sourceImportResult(successCount, selected.length)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final repo = context.watch<SourceRepository>();
    final filteredSources = _getFilteredSources(repo);

    // 嵌入模式：直接返回 Tab 内容（由外层 LibraryShell 提供 Scaffold/FAB）。
    if (widget.embedded) return _buildBody(l10n, scheme, filteredSources);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sourceManagementTitle),
        actions: <Widget>[
          IconButton(
            icon: Icon(
              _showHidden ? Icons.visibility : Icons.visibility_off_outlined,
            ),
            tooltip: l10n.sourceShowHidden,
            onPressed: () => setState(() => _showHidden = !_showHidden),
          ),
        ],
      ),
      body: _buildBody(l10n, scheme, filteredSources),

      // 媒体类型的采集 API 导入 FAB；小说类型的书源导入 FAB（仅非嵌入模式）
      floatingActionButton: widget.embedded ? null : _buildFab(l10n),
    );
  }

  /// 构建主体内容（Tab 栏 + 内容区），供嵌入模式和完整模式共用。
  Widget _buildBody(AppLocalizations l10n, ColorScheme scheme, List<PluginConfig> filteredSources) {
    return Column(
      children: <Widget>[
        // 顶部 Tab 切换（M3 等宽分段）
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg,
              vertical: AppTokens.spaceSm,
            ),
            child: AppSegmentedTabs<_SourceTab>(
              selected: <_SourceTab>{_tab},
              onSelectionChanged: (sel) {
                if (sel.isNotEmpty) {
                  setState(() => _tab = sel.first);
                }
              },
              segments: <ButtonSegment<_SourceTab>>[
                ButtonSegment<_SourceTab>(
                  value: _SourceTab.list,
                  icon: const Icon(Icons.list),
                  label: Text(l10n.sourceListTab),
                ),
                ButtonSegment<_SourceTab>(
                  value: _SourceTab.network,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(l10n.networkImportTab),
                ),
                ButtonSegment<_SourceTab>(
                  value: _SourceTab.local,
                  icon: const Icon(Icons.file_present_outlined),
                  label: Text(l10n.localImportTab),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Tab 内容
          Expanded(
            child: <Widget>[
              _buildListTab(l10n, filteredSources, scheme),
              _buildNetworkImportTab(l10n, scheme),
              _buildLocalImportTab(l10n, scheme),
            ][_tab.index],
          ),
        ],
    );
  }

  // 根据 filterType 选择对应的导入入口 FAB：
  // - animeSource/null：采集 API 导入（MacCMS）
  // - novelSource：书源导入（@css/@xpath/@json/@js + ## 正则）
  // 仅在「源列表」Tab 且非预览模式显示，避免遮挡网络/本地导入内容。
  Widget? _buildFab(AppLocalizations l10n) {
    if (_tab != _SourceTab.list || _previewMode) return null;
    if (widget.filterType == SourceType.novelSource) {
      return FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ShuyuanImportScreen(),
          ),
        ),
        icon: const Icon(Icons.menu_book),
        label: Text(l10n.importShuyuan),
      );
    }
    if (widget.filterType == SourceType.animeSource ||
        widget.filterType == null) {
      return FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const CollectApiImportScreen(),
          ),
        ),
        icon: const Icon(Icons.cloud_download),
        label: Text(l10n.collectApiImportTitle),
      );
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Tab 1: 源列表
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildListTab(
    AppLocalizations l10n,
    List<PluginConfig> sources,
    ColorScheme scheme,
  ) {
    // 若指定了 filterType（从模块设置页进入），直接显示单列表，不加分类 Tab。
    if (widget.filterType != null) {
      if (sources.isEmpty) {
        return AppEmptyState(
          icon: Icons.extension,
          message: l10n.sourceListEmpty,
          actionLabel: l10n.addSource,
          onAction: () => setState(() => _tab = _SourceTab.network),
          secondaryActionLabel: l10n.enableRecommendedSources,
          onSecondaryAction: () => _enableRecommended(l10n),
        );
      }
      return _buildSourceListView(l10n, sources);
    }

    // filterType == null（设置页总入口）：3 分类 Tab（项 7）。
    return DefaultTabController(
      length: 3,
      child: Column(
        children: <Widget>[
          if (sources.isNotEmpty) _buildEnableRecommendedTile(l10n),
          Material(
            color: scheme.surface,
            child: TabBar(
              tabs: <Widget>[
                Tab(icon: const Icon(Icons.book), text: l10n.sourceCategoryNovel),
                Tab(icon: const Icon(Icons.movie), text: l10n.sourceCategoryMedia),
                Tab(icon: const Icon(Icons.image), text: l10n.sourceCategoryComic),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _buildCategoryList(l10n, _getCategorySources(sources, 0),
                    l10n.sourceCategoryNovel),
                _buildCategoryList(l10n, _getCategorySources(sources, 1),
                    l10n.sourceCategoryMedia),
                _buildCategoryList(l10n, _getCategorySources(sources, 2),
                    l10n.sourceCategoryComic),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单个分类下的源列表（含空状态）。
  Widget _buildCategoryList(
    AppLocalizations l10n,
    List<PluginConfig> sources,
    String categoryLabel,
  ) {
    if (sources.isEmpty) {
      return AppEmptyState(
        icon: Icons.extension,
        message: l10n.sourceCategoryEmpty(categoryLabel),
        actionLabel: l10n.addSource,
        onAction: () => setState(() => _tab = _SourceTab.network),
      );
    }
    return _buildSourceListView(l10n, sources);
  }

  /// 构建源列表 ListView（复用于单列表与分类 Tab）。
  Widget _buildSourceListView(
    AppLocalizations l10n,
    List<PluginConfig> sources,
  ) {
    return ListView(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      children: <Widget>[
        ...sources.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
            child: AppCard(
              padding: EdgeInsets.zero,
              child: UnifiedSourceTile(
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
                migrateTooltip: l10n.sourceMigrate,
                // 源管理页：操作收进「更多」菜单，更清爽
                useMoreMenu: true,
                moreMenuTooltip: l10n.moreActions,
                onToggle: (bool value) =>
                    context.read<SourceRepository>().setEnabled(s.id, value),
                onMirrorSettings: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SourceMirrorScreen(source: s),
                  ),
                ),
                onHide: () =>
                    context.read<SourceRepository>().setHidden(s.id, !s.isHidden),
                onEdit: () => _showEditDialog(s),
                onDelete: () => _showDeleteConfirm(s),
                onMigrate: s.migrationMessage != null
                    ? () => _showMigrateDialog(s)
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnableRecommendedTile(AppLocalizations l10n) {
    final repo = context.read<SourceRepository>();
    final hasDisabled = repo.all.any(
      (c) =>
          !c.isDeprecated &&
          !c.id.toLowerCase().contains('example') &&
          !c.isEnabled,
    );
    if (!hasDisabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: AppCard(
        onTap: () => _enableRecommended(l10n),
        child: ListTile(
          leading: const Icon(Icons.playlist_add_check),
          title: Text(l10n.enableRecommendedSources),
          subtitle: Text(l10n.enableRecommendedSourcesHint),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }

  Future<void> _enableRecommended(AppLocalizations l10n) async {
    final count =
        await context.read<SourceRepository>().enableRecommendedSources();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.recommendedSourcesEnabled(count))),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Tab 2: 网络导入
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildNetworkImportTab(AppLocalizations l10n, ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      children: <Widget>[
        Text(
          l10n.networkImportHint,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppTokens.spaceMd),

        TextField(
          controller: _urlController,
          decoration: InputDecoration(
            hintText: l10n.networkImportPasteHint,
            prefixIcon: const Icon(Icons.link),
            border: const OutlineInputBorder(),
            suffixIcon: _networkLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: _fetchFromUrl,
                  ),
          ),
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _fetchFromUrl(),
        ),

        // 预览区域
        const SizedBox(height: AppTokens.spaceLg),
        if (_networkLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceXl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CircularProgressIndicator(),
                  const SizedBox(height: AppTokens.spaceMd),
                  Text(l10n.networkImportPasteHint),
                ],
              ),
            ),
          )
        else if (_networkError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceXl),
              child: Text(
                _networkError!,
                style: TextStyle(color: scheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else if (_networkPreview != null)
          _buildNetworkPreview(l10n, scheme)
        else
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceXl),
              child: Text(
                l10n.networkImportPasteHint,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNetworkPreview(AppLocalizations l10n, ColorScheme scheme) {
    final config = _networkPreview!;
    final isValid = _validationErrors.isEmpty;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(config.name,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            config.site.baseUrl,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          if (isValid)
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
            ..._validationErrors.map(
              (e) => Padding(
                padding: EdgeInsets.only(
                    left: AppTokens.spaceMd, top: 2),
                child: Text('• $e',
                    style:
                        Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                            )),
              ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceLg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isValid ? _saveNetworkSource : null,
              child: Text(l10n.save),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Tab 3: 本地导入（文件/文件夹 + 预览勾选）
  // ═══════════════════════════════════════════════════════════════════════
  Widget _buildLocalImportTab(AppLocalizations l10n, ColorScheme scheme) {
    // 预览模式：显示已扫描的源列表 + 勾选 + 确认
    if (_previewMode && _previewItems.isNotEmpty) {
      return _buildImportPreview(l10n, scheme);
    }

    // 默认模式：选择文件或文件夹
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.description_outlined,
              size: 64,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: AppTokens.spaceLg),
            Text(
              l10n.localImportTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              l10n.localImportFormats,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTokens.spaceLg),

            // 导入方式：单文件 / 多文件 / 文件夹
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _pickLocalFile,
                  icon: const Icon(Icons.file_open, size: 18),
                  label: Text(l10n.selectFile),
                ),
                const SizedBox(width: AppTokens.spaceMd),
                OutlinedButton.icon(
                  onPressed: _pickLocalFolder,
                  icon: const Icon(Icons.folder_outlined, size: 18),
                  label: Text(l10n.selectFolder),
                ),
              ],
            ),

            if (_pickedFileName != null) ...<Widget>[
              const SizedBox(height: AppTokens.spaceMd),
              Text(
                _pickedFileName!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                    ),
              ),
            ],

            const SizedBox(height: AppTokens.spaceXl),
            Text(
              l10n.localImportHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 预览勾选界面。
  Widget _buildImportPreview(AppLocalizations l10n, ColorScheme scheme) {
    final validCount = _previewItems.where((e) => e.isValid).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 标题栏
        Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () {
                  setState(() {
                    _previewMode = false;
                    _previewItems = <_ImportPreviewItem>[];
                    _selectedPreviewIndices = <int>{};
                    _skippedByTypeCount = 0;
                  });
                  widget.onPreviewModeChanged?.call(false);
                },
                tooltip: l10n.cancel ?? 'Cancel',
              ),
              Expanded(
                child: Text(
                  l10n.importPreviewTitle(_previewItems.length),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (validCount > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextButton(
                      onPressed: () {
                        // 全选有效项
                        setState(() {
                          _selectedPreviewIndices = _previewItems
                              .asMap()
                              .entries
                              .where((e) => e.value.isValid)
                              .map((e) => e.key)
                              .toSet();
                        });
                      },
                      child: Text(l10n.selectAll ?? 'Select All'),
                    ),
                    TextButton(
                      onPressed: () {
                        // 全不选
                        setState(() {
                          _selectedPreviewIndices = <int>{};
                        });
                      },
                      child: Text(l10n.deselectAll ?? 'Deselect All'),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // 类型筛选提示：在专属类型页导入时，仅导入该类型源
        if (widget.filterType != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
              vertical: AppTokens.spaceSm,
            ),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              children: <Widget>[
                Icon(Icons.filter_alt_outlined, size: 16,
                    color: scheme.onSurfaceVariant),
                const SizedBox(width: AppTokens.spaceXs),
                Expanded(
                  child: Text(
                    _skippedByTypeCount > 0
                        ? '${l10n.importTypeOnly(_typeLabel(widget.filterType!, l10n))}  '
                            '${l10n.importTypeFiltered(_skippedByTypeCount)}'
                        : l10n.importTypeOnly(_typeLabel(widget.filterType!, l10n)),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),

        const Divider(height: 1),

        // 文件列表（带复选框）
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(AppTokens.spaceSm),
            itemCount: _previewItems.length,
            itemBuilder: (context, i) {
              final item = _previewItems[i];
              final isSelected = _selectedPreviewIndices.contains(i);
              return Card(
                margin: const EdgeInsets.only(bottom: AppTokens.spaceXs),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceSm,
                    vertical: AppTokens.spaceXs,
                  ),
                  leading: Checkbox(
                    value: isSelected && item.isValid,
                    onChanged: item.isValid ? (v) {
                      setState(() {
                        if (v == true) {
                          _selectedPreviewIndices.add(i);
                        } else {
                          _selectedPreviewIndices.remove(i);
                        }
                      });
                    } : null,
                  ),
                  title: Text(
                    item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (item.isValid) ...<Widget>[
                        Text(
                          item.config?.name ?? '',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.primary,
                              ),
                        ),
                        Text(
                          item.config?.site.baseUrl ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        if (item.type != null)
                          Text(
                            '${l10n.sourceType}：${_typeLabel(item.type!, l10n)}',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                      ] else ...<Widget>[
                        Text(
                          item.error ?? l10n.sourceImportInvalid,
                          style: TextStyle(color: scheme.error, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                  trailing: Icon(
                    item.isValid ? Icons.check_circle : Icons.error_outline,
                    color: item.isValid ? Colors.green : scheme.error,
                    size: 20,
                  ),
                ),
              );
            },
          ),
        ),

        // 底部操作栏
        Container(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
            ),
          ),
          child: Row(
            children: <Widget>[
              Text(
                l10n.importSelectedCount(_selectedPreviewIndices.length),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _selectedPreviewIndices.isNotEmpty
                    ? _confirmImport
                    : null,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text(l10n.confirmImport ?? 'Confirm Import'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────── 编辑/删除/迁移对话框（P6.1.1/P6.1.2） ───────────────────────

  /// 编辑源对话框（仅导入源可编辑）。
  Future<void> _showEditDialog(PluginConfig source) async {
    final l10n = AppLocalizations.of(context);
    final repo = context.read<SourceRepository>();
    final isImported = repo.importedSources.any((c) => c.id == source.id);
    if (!isImported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sourceEditBuiltinNotAllowed)),
      );
      return;
    }
    final nameCtl = TextEditingController(text: source.name);
    final urlCtl = TextEditingController(text: source.site.baseUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.sourceEdit),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: nameCtl,
              decoration: InputDecoration(labelText: l10n.sourceNameLabel),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            TextField(
              controller: urlCtl,
              decoration: InputDecoration(labelText: l10n.sourceUrlLabel),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final ok = repo.updateSource(
      source.id,
      name: nameCtl.text.trim(),
      baseUrl: urlCtl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? l10n.sourceEditSaved : l10n.sourceEditFailed)),
      );
    }
  }

  /// 删除源确认对话框（仅导入源可删除）。
  Future<void> _showDeleteConfirm(PluginConfig source) async {
    final l10n = AppLocalizations.of(context);
    final repo = context.read<SourceRepository>();
    final isImported = repo.importedSources.any((c) => c.id == source.id);
    if (!isImported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sourceDeleteBuiltinNotAllowed)),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmContent(source.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = repo.removeSource(source.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? l10n.sourceDeleted : l10n.sourceDeleteFailed)),
      );
    }
  }

  /// 弃用源迁移提示对话框。
  Future<void> _showMigrateDialog(PluginConfig source) async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.sourceMigrate),
        content: Text(source.migrationMessage ?? l10n.sourceDeprecatedHint),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }
}

/// 本地导入预览项 —— 扫描到的单个源文件信息。
class _ImportPreviewItem {
  final String path;
  final String fileName;
  final PluginConfig? config;
  final SourceType? type;
  final bool isValid;
  final String? error;

  _ImportPreviewItem({
    required this.path,
    required this.fileName,
    required this.config,
    this.type,
    required this.isValid,
    this.error,
  });
}
