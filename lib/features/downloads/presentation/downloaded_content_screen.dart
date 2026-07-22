/// 已下载内容页 —— 新版设计：支持按类型筛选（全部/小说/媒体/漫画/已删除）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/download/download_manager.dart';
import '../../../core/download/download_task.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_cover_image.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_segmented_tabs.dart';
import '../../../core/widgets/layout_picker_dialog.dart';
import '../../../core/settings/layout_settings.dart';
import 'downloaded_group_screen.dart';

enum _DownloadedTab { all, novel, media, comic, archived }

/// 已下载内容页 —— 带类型 Tab 筛选和网格视图。
class DownloadedContentScreen extends StatefulWidget {
  const DownloadedContentScreen({super.key});

  @override
  State<DownloadedContentScreen> createState() =>
      _DownloadedContentScreenState();
}

class _DownloadedContentScreenState extends State<DownloadedContentScreen> {
  _DownloadedTab _tab = _DownloadedTab.all;
  bool _selectMode = false;
  final Set<String> _selectedKeys = <String>{};

  List<DownloadTask> _getFilteredTasks(DownloadManager manager) {
    final completed = manager.completedTasks;
    switch (_tab) {
      case _DownloadedTab.all:
        return completed;
      case _DownloadedTab.novel:
        return completed
            .where((t) => t.sourceType == SourceType.novelSource)
            .toList();
      case _DownloadedTab.media:
        return completed
            .where((t) => t.sourceType == SourceType.animeSource)
            .toList();
      case _DownloadedTab.comic:
        return completed
            .where((t) => t.sourceType == SourceType.mangaSource)
            .toList();
      case _DownloadedTab.archived:
        return manager.archivedTasks;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final manager = context.watch<DownloadManager>();
    final filteredTasks = _getFilteredTasks(manager);
    final isArchivedTab = _tab == _DownloadedTab.archived;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode
            ? '${_selectedKeys.length} / ${filteredTasks.length}'
            : l10n.downloadedContent),
        actions: <Widget>[
          if (!_selectMode) ...<Widget>[
            // 布局快选：底部弹窗，与设置页布局设置双向同步（项 11）。
            IconButton(
              icon: const Icon(Icons.view_module),
              tooltip: l10n.layoutOpenSettings,
              onPressed: () => showLayoutPickerDialog(context),
            ),
            // 筛选：与顶部类型 Tab 联动的弹窗式快速筛选（底部弹窗风格）。
            IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: l10n.filter,
              onPressed: () => showDownloadedFilterSheet(
                context,
                initial: _tab,
                onApply: (value) => setState(() {
                  _tab = value;
                  _selectMode = false;
                  _selectedKeys.clear();
                }),
              ),
            ),
          ],
          if (_selectMode) ...<Widget>[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: l10n.selectAll,
              onPressed: () => setState(() {
                _selectedKeys
                    .addAll(filteredTasks.map((t) => t.id).toSet());
              }),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.delete,
              onPressed: _selectedKeys.isEmpty
                  ? null
                  : () => _confirmDelete(context, manager, l10n),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.cancel,
              onPressed: () => setState(() {
                _selectMode = false;
                _selectedKeys.clear();
              }),
            ),
          ] else if (filteredTasks.isNotEmpty &&
              !isArchivedTab) ...<Widget>[
            // Archived tab uses per-card action buttons instead of select mode.
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: l10n.select,
              onPressed: () => setState(() => _selectMode = true),
            ),
          ],
        ],
      ),
      body: Column(
        children: <Widget>[
          // 类型筛选 Tab
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg,
              vertical: AppTokens.spaceSm,
            ),
            child: AppSegmentedTabs<_DownloadedTab>(
              selected: <_DownloadedTab>{_tab},
              onSelectionChanged: (Set<_DownloadedTab> s) {
                setState(() {
                  _tab = s.first;
                  _selectMode = false;
                  _selectedKeys.clear();
                });
              },
              segments: <ButtonSegment<_DownloadedTab>>[
                ButtonSegment<_DownloadedTab>(
                    value: _DownloadedTab.all,
                    label: Text(l10n.downloadedTabsAll)),
                ButtonSegment<_DownloadedTab>(
                    value: _DownloadedTab.novel,
                    label: Text(l10n.downloadedTabsNovel)),
                ButtonSegment<_DownloadedTab>(
                    value: _DownloadedTab.media,
                    label: Text(l10n.downloadedTabsMedia)),
                ButtonSegment<_DownloadedTab>(
                    value: _DownloadedTab.comic,
                    label: Text(l10n.downloadedTabsComic)),
                ButtonSegment<_DownloadedTab>(
                    value: _DownloadedTab.archived,
                    label: Text(l10n.downloadedTabsArchived)),
              ],
            ),
          ),

          // 内容区（随布局设置实时变化：网格列数/间距 ↔ 列表模式）
          Expanded(
            child: filteredTasks.isEmpty
                ? AppEmptyState(
                    icon: isArchivedTab
                        ? Icons.archive_outlined
                        : Icons.download_done_outlined,
                    message:
                        isArchivedTab ? l10n.archivedEmpty : l10n.emptyDownloaded,
                  )
                : ListenableBuilder(
                    listenable: LayoutSettingsStore.instance,
                    builder: (BuildContext context, _) {
                      final LayoutSettings layout =
                          LayoutSettingsStore.instance.settings;
                      if (layout.layoutMode == LayoutMode.list) {
                        // 列表模式：横向卡片
                        return ListView.separated(
                          padding: const EdgeInsets.all(AppTokens.spaceMd),
                          itemCount: filteredTasks.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppTokens.spaceSm),
                          itemBuilder: (context, i) => _buildCard(
                            filteredTasks[i],
                            isArchivedTab,
                            manager,
                            l10n,
                            listMode: true,
                          ),
                        );
                      }
                      // 网格模式：按设置列数/间距渲染，高宽比跟随标题/作者开关
                      return GridView.builder(
                        padding: const EdgeInsets.all(AppTokens.spaceMd),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: layout.gridColumns.clamp(1, 8),
                          childAspectRatio: _gridAspectRatio(layout),
                          crossAxisSpacing: layout.gridSpacing,
                          mainAxisSpacing: layout.gridSpacing,
                        ),
                        itemCount: filteredTasks.length,
                        itemBuilder: (context, i) => _buildCard(
                          filteredTasks[i],
                          isArchivedTab,
                          manager,
                          l10n,
                          listMode: false,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 根据布局设置计算网格卡片高宽比（封面 + 可变文本区）。
  double _gridAspectRatio(LayoutSettings layout) {
    // 封面区域固定占比约 0.65（3:2 封面+文字）
    final baseRatio = 0.65;
    if (layout.showTitle) return baseRatio; // 有标题时标准比例
    if (layout.showAuthor) return 0.72;    // 无标题有作者，稍长
    return 0.58;                           // 全隐藏，更偏方形（接近纯封面）
  }

  /// 已下载页筛选已改为文件底部的 [showDownloadedFilterSheet]（底部弹窗）。

  /// 根据当前选择状态构建已下载卡片（列表/网格模式共用）。
  Widget _buildCard(
    DownloadTask task,
    bool isArchivedTab,
    DownloadManager manager,
    AppLocalizations l10n, {
    required bool listMode,
  }) {
    final bool isSelected = _selectedKeys.contains(task.id);
    return _DownloadedCard(
      task: task,
      listMode: listMode,
      selectMode: _selectMode,
      isSelected: isSelected,
      isArchived: isArchivedTab,
      onTap: () {
        if (_selectMode) {
          setState(() {
            if (isSelected) {
              _selectedKeys.remove(task.id);
            } else {
              _selectedKeys.add(task.id);
            }
          });
        } else if (!isArchivedTab) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DownloadedGroupScreen(task: task),
            ),
          );
        }
      },
      onLongPress: () {
        if (!_selectMode && !isArchivedTab) {
          setState(() {
            _selectMode = true;
            _selectedKeys.add(task.id);
          });
        }
      },
      onRestore: isArchivedTab
          ? () => _restoreTask(context, manager, l10n, task.id)
          : null,
      onDeletePermanently: isArchivedTab
          ? () => _confirmDeletePermanently(context, manager, l10n, task.id)
          : null,
    );
  }

  void _confirmDelete(
    BuildContext context,
    DownloadManager manager,
    AppLocalizations l10n,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.delete),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.deleteConfirm),
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              l10n.archivedHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              for (final id in _selectedKeys) {
                manager.archive(id);
              }
              setState(() {
                _selectMode = false;
                _selectedKeys.clear();
              });
              Navigator.pop(ctx);
            },
            child: Text(l10n.deleteRecordOnly),
          ),
          FilledButton(
            onPressed: () {
              for (final id in _selectedKeys) {
                manager.cancel(id, deleteFiles: true);
              }
              setState(() {
                _selectMode = false;
                _selectedKeys.clear();
              });
              Navigator.pop(ctx);
            },
            child: Text(l10n.deleteRecordAndFile),
          ),
        ],
      ),
    );
  }

  /// Restore a single archived task and show a SnackBar confirmation.
  void _restoreTask(
    BuildContext context,
    DownloadManager manager,
    AppLocalizations l10n,
    String taskId,
  ) {
    manager.unarchive(taskId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.restoreSuccess)),
    );
  }

  /// Permanently delete a single archived task with confirmation dialog.
  void _confirmDeletePermanently(
    BuildContext context,
    DownloadManager manager,
    AppLocalizations l10n,
    String taskId,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deletePermanently),
        content: Text(l10n.deleteConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              manager.cancel(taskId, deleteFiles: true);
              Navigator.pop(ctx);
            },
            child: Text(l10n.deletePermanently),
          ),
        ],
      ),
    );
  }
}

class _DownloadedCard extends StatelessWidget {
  final DownloadTask task;
  final bool selectMode;
  final bool isSelected;
  final bool isArchived;
  final bool listMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onRestore;
  final VoidCallback? onDeletePermanently;

  const _DownloadedCard({
    required this.task,
    required this.selectMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    this.isArchived = false,
    this.listMode = false,
    this.onRestore,
    this.onDeletePermanently,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context);
    // 全部跟随布局设置（与在线浏览页 ContentCard / ListItem 一致）。
    final LayoutSettings layout = LayoutSettingsStore.instance.settings;
    final double radius = layout.coverRadius;

    final Widget body = listMode
        ? Row(
            children: <Widget>[
              SizedBox(
                width: 64,
                height: 90,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    AppCoverImage(
                      coverUrl: task.coverUrl,
                      fit: BoxFit.cover,
                      radius: radius,
                    ),
                    if (isArchived)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.statusArchived,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: scheme.onSecondaryContainer),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (layout.showTitle)
                        Text(
                          task.title,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontSize: layout.titleFontSize),
                          maxLines: layout.titleMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const Spacer(),
                      _metaRow(context, scheme, l10n, layout),
                    ],
                  ),
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    AppCoverImage(
                      coverUrl: task.coverUrl,
                      fit: BoxFit.cover,
                      radius: radius,
                    ),
                    if (isArchived)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.statusArchived,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: scheme.onSecondaryContainer),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (layout.showTitle)
                        Text(
                          task.title,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontSize: layout.titleFontSize),
                          maxLines: layout.titleMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const Spacer(),
                      _metaRow(context, scheme, l10n, layout),
                    ],
                  ),
                ),
              ),
            ],
          );

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        children: <Widget>[
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
            child: body,
          ),
          if (selectMode && isSelected)
            Positioned(
              top: 4,
              right: 4,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: scheme.primary,
                child: Icon(Icons.check, size: 16, color: scheme.onPrimary),
              ),
            ),
        ],
      ),
    );
  }

  /// 底部元信息行：归档态显示「恢复 / 彻底删除」操作，普通态显示章节数。
  /// [layout] 用于判断是否显示作者/章节数信息（showAuthor）。
  Widget _metaRow(BuildContext context, ColorScheme scheme, AppLocalizations l10n, [LayoutSettings? layout]) {
    if (isArchived && onRestore != null && onDeletePermanently != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: l10n.restore,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onRestore,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: l10n.deletePermanently,
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onDeletePermanently,
          ),
        ],
      );
    }
    // showAuthor 关闭时隐藏章节数/作者信息
    if (layout != null && !layout.showAuthor) return const SizedBox.shrink();
    return Text(
      task.sourceType == SourceType.mangaSource
          ? l10n.chapterN(task.totalChapters)
          : task.sourceType == SourceType.novelSource
              ? l10n.novelChapterN(task.totalChapters)
              : l10n.episodeN(task.totalChapters),
      style: Theme.of(context)
          .textTheme
          .labelSmall
          ?.copyWith(color: scheme.onSurfaceVariant),
    );
  }
}

/// 已下载页筛选底部弹窗：与顶部类型 Tab 联动，选中后回写 [_tab]。
///
/// 风格与 [showOnlineFilterSheet] 一致（modal bottom sheet + 单选行 + 应用按钮）。
Future<void> showDownloadedFilterSheet(
  BuildContext context, {
  required _DownloadedTab initial,
  required ValueChanged<_DownloadedTab> onApply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTokens.radiusLg),
      ),
    ),
    builder: (ctx) => _DownloadedFilterSheet(
      initial: initial,
      onApply: onApply,
    ),
  );
}

class _DownloadedFilterSheet extends StatefulWidget {
  const _DownloadedFilterSheet({
    required this.initial,
    required this.onApply,
  });

  final _DownloadedTab initial;
  final ValueChanged<_DownloadedTab> onApply;

  @override
  State<_DownloadedFilterSheet> createState() =>
      _DownloadedFilterSheetState();
}

class _DownloadedFilterSheetState extends State<_DownloadedFilterSheet> {
  late _DownloadedTab _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  String _label(AppLocalizations l10n, _DownloadedTab tab) => switch (tab) {
        _DownloadedTab.all => l10n.downloadedTabsAll,
        _DownloadedTab.novel => l10n.downloadedTabsNovel,
        _DownloadedTab.media => l10n.downloadedTabsMedia,
        _DownloadedTab.comic => l10n.downloadedTabsComic,
        _DownloadedTab.archived => l10n.downloadedTabsArchived,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTokens.spaceLg,
          right: AppTokens.spaceLg,
          top: AppTokens.spaceMd,
          bottom:
              MediaQuery.of(context).viewInsets.bottom + AppTokens.spaceMd,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(l10n.filter, style: theme.textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const Divider(),
              _FilterRow(
                label: _label(l10n, _DownloadedTab.all),
                selected: _selected == _DownloadedTab.all,
                onTap: () => setState(() => _selected = _DownloadedTab.all),
              ),
              _FilterRow(
                label: _label(l10n, _DownloadedTab.novel),
                selected: _selected == _DownloadedTab.novel,
                onTap: () => setState(() => _selected = _DownloadedTab.novel),
              ),
              _FilterRow(
                label: _label(l10n, _DownloadedTab.media),
                selected: _selected == _DownloadedTab.media,
                onTap: () => setState(() => _selected = _DownloadedTab.media),
              ),
              _FilterRow(
                label: _label(l10n, _DownloadedTab.comic),
                selected: _selected == _DownloadedTab.comic,
                onTap: () => setState(() => _selected = _DownloadedTab.comic),
              ),
              _FilterRow(
                label: _label(l10n, _DownloadedTab.archived),
                selected: _selected == _DownloadedTab.archived,
                onTap: () =>
                    setState(() => _selected = _DownloadedTab.archived),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    widget.onApply(_selected);
                    Navigator.of(context).maybePop();
                  },
                  child: Text(l10n.filterApply),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 筛选单选行：label + 选中勾。
class _FilterRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = selected ? scheme.primary : scheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppTokens.spaceXs,
          horizontal: AppTokens.spaceSm,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (selected) Icon(Icons.check, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
