/// 下载列表页 —— 新版设计：支持按类型筛选（全部/小说/媒体/漫画）+ 状态筛选（项 11）
/// + 选择模式批量操作（暂停/继续/删除）。
library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/download/download_manager.dart';
import '../../../core/download/download_task.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_segmented_tabs.dart';
import '../../../core/widgets/layout_picker_dialog.dart';

/// 下载状态筛选（项 11）。null = 全部。
enum _DownloadStatusFilter { all, completed, inProgress, failed }

/// 下载列表页 —— 带类型 Tab 筛选 + AppBar 状态筛选 + 布局快选 + 选择模式批量操作。
class DownloadListScreen extends StatefulWidget {
  const DownloadListScreen({super.key});

  @override
  State<DownloadListScreen> createState() => _DownloadListScreenState();
}

class _DownloadListScreenState extends State<DownloadListScreen> {
  SourceType? _typeFilter; // null = 全部
  _DownloadStatusFilter _statusFilter = _DownloadStatusFilter.all;
  bool _selectMode = false;
  final Set<String> _selectedKeys = <String>{};

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final manager = context.watch<DownloadManager>();
    final allActiveTasks = manager.activeTasks;

    // 按类型 + 状态筛选
    List<DownloadTask> filteredTasks = _typeFilter == null
        ? allActiveTasks
        : allActiveTasks.where((t) => t.sourceType == _typeFilter).toList();
    if (_statusFilter != _DownloadStatusFilter.all) {
      filteredTasks = filteredTasks.where(_matchesStatus).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: _selectMode
            ? Text(l10n.selectedCount(
                _selectedKeys.length,
                filteredTasks.length,
              ))
            : Text(l10n.downloadListTitle),
        actions: <Widget>[
          if (!_selectMode) ...<Widget>[
            PopupMenuButton<_DownloadStatusFilter>(
              icon: const Icon(Icons.filter_list),
              tooltip: l10n.filter,
              onSelected: (_DownloadStatusFilter value) =>
                  setState(() => _statusFilter = value),
              itemBuilder: (BuildContext ctx) =>
                  <PopupMenuEntry<_DownloadStatusFilter>>[
                _statusMenuItem(
                    _DownloadStatusFilter.all, l10n.allLabel, ctx),
                _statusMenuItem(_DownloadStatusFilter.completed,
                    l10n.statusCompleted, ctx),
                _statusMenuItem(_DownloadStatusFilter.inProgress,
                    l10n.downloadStatusInProgress, ctx),
                _statusMenuItem(_DownloadStatusFilter.failed,
                    l10n.statusFailed, ctx),
              ],
            ),
            // 布局快选：底部弹窗，与设置页布局设置双向同步。
            IconButton(
              icon: const Icon(Icons.view_module),
              tooltip: l10n.layoutOpenSettings,
              onPressed: () => showLayoutPickerDialog(context),
            ),
            if (filteredTasks.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: l10n.clearAll,
                onPressed: () =>
                    _confirmClearAll(context, manager, filteredTasks, l10n),
              ),
            if (filteredTasks.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.checklist),
                tooltip: l10n.select,
                onPressed: () => setState(() => _selectMode = true),
              ),
          ] else ...<Widget>[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: l10n.selectAll,
              onPressed: _selectedKeys.length == filteredTasks.length
                  ? null
                  : () => setState(() {
                        _selectedKeys
                            .addAll(filteredTasks.map((t) => t.id).toSet());
                      }),
            ),
            IconButton(
              icon: const Icon(Icons.pause),
              tooltip: l10n.batchPause,
              onPressed: _selectedKeys.isEmpty
                  ? null
                  : () => _batchPause(manager),
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: l10n.batchResume,
              onPressed: _selectedKeys.isEmpty
                  ? null
                  : () => _batchResume(manager),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.deleteSelected,
              onPressed: _selectedKeys.isEmpty
                  ? null
                  : () => _confirmBatchDelete(context, manager, l10n),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.cancel,
              onPressed: () => setState(() {
                _selectMode = false;
                _selectedKeys.clear();
              }),
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
            child: AppSegmentedTabs<SourceType?>(
              selected: <SourceType?>{_typeFilter},
              onSelectionChanged: (Set<SourceType?> s) => setState(() {
                _typeFilter = s.first;
                _selectMode = false;
                _selectedKeys.clear();
              }),
              segments: <ButtonSegment<SourceType?>>[
                ButtonSegment<SourceType?>(
                    value: null, label: Text(l10n.downloadTabsAll)),
                ButtonSegment<SourceType?>(
                    value: SourceType.novelSource,
                    label: Text(l10n.downloadTabsNovel)),
                ButtonSegment<SourceType?>(
                    value: SourceType.animeSource,
                    label: Text(l10n.downloadTabsMedia)),
                ButtonSegment<SourceType?>(
                    value: SourceType.mangaSource,
                    label: Text(l10n.downloadTabsComic)),
              ],
            ),
          ),

          // 内容区
          Expanded(
            child: filteredTasks.isEmpty
                ? AppEmptyState(
                    icon: Icons.download_outlined,
                    message: l10n.noDownloads,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppTokens.spaceMd),
                    itemCount: filteredTasks.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppTokens.spaceSm),
                    itemBuilder: (context, i) => _DownloadTaskTile(
                      task: filteredTasks[i],
                      selectMode: _selectMode,
                      isSelected: _selectedKeys.contains(filteredTasks[i].id),
                      onToggle: () => setState(() {
                        final id = filteredTasks[i].id;
                        if (_selectedKeys.contains(id)) {
                          _selectedKeys.remove(id);
                        } else {
                          _selectedKeys.add(id);
                        }
                      }),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  bool _matchesStatus(DownloadTask t) {
    switch (_statusFilter) {
      case _DownloadStatusFilter.all:
        return true;
      case _DownloadStatusFilter.completed:
        return t.status == DownloadStatus.completed;
      case _DownloadStatusFilter.inProgress:
        return t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.pending;
      case _DownloadStatusFilter.failed:
        return t.status == DownloadStatus.failed;
    }
  }

  PopupMenuItem<_DownloadStatusFilter> _statusMenuItem(
    _DownloadStatusFilter value,
    String label,
    BuildContext ctx,
  ) {
    final bool selected = _statusFilter == value;
    final ColorScheme scheme = Theme.of(ctx).colorScheme;
    return PopupMenuItem<_DownloadStatusFilter>(
      value: value,
      child: Row(
        children: <Widget>[
          if (selected)
            Icon(Icons.check, size: 18, color: scheme.primary)
          else
            const SizedBox(width: 18),
          const SizedBox(width: AppTokens.spaceSm),
          Text(
            label,
            style: TextStyle(
              color: selected ? scheme.primary : scheme.onSurface,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  void _batchPause(DownloadManager manager) {
    for (final id in _selectedKeys) {
      manager.pauseTask(id);
    }
    setState(() {
      _selectMode = false;
      _selectedKeys.clear();
    });
  }

  void _batchResume(DownloadManager manager) {
    for (final id in _selectedKeys) {
      manager.resumeTask(id);
    }
    setState(() {
      _selectMode = false;
      _selectedKeys.clear();
    });
  }

  void _confirmBatchDelete(
    BuildContext context,
    DownloadManager manager,
    AppLocalizations l10n,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteSelected),
        content: Text(l10n.deleteSelectedConfirm(_selectedKeys.length)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          // 仅删除记录（保留已下载文件，可恢复）。
          TextButton(
            onPressed: () {
              for (final id in _selectedKeys) {
                manager.cancel(id, deleteFiles: false);
              }
              Navigator.pop(ctx);
              setState(() {
                _selectMode = false;
                _selectedKeys.clear();
              });
            },
            child: Text(l10n.deleteRecordOnly),
          ),
          // 删除记录与文件（彻底移除）。
          FilledButton(
            onPressed: () {
              for (final id in _selectedKeys) {
                manager.cancel(id, deleteFiles: true);
              }
              Navigator.pop(ctx);
              setState(() {
                _selectMode = false;
                _selectedKeys.clear();
              });
            },
            child: Text(l10n.deleteRecordAndFile),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(
    BuildContext context,
    DownloadManager manager,
    List<DownloadTask> tasks,
    AppLocalizations l10n,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.clearAll),
        content: Text(l10n.clearAllConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              for (final task in tasks) {
                manager.cancel(task.id, deleteFiles: false);
              }
              Navigator.pop(ctx);
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }
}

class _DownloadTaskTile extends StatelessWidget {
  final DownloadTask task;
  final bool selectMode;
  final bool isSelected;
  final VoidCallback? onToggle;

  const _DownloadTaskTile({
    required this.task,
    this.selectMode = false,
    this.isSelected = false,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final manager = context.read<DownloadManager>();

    final Widget card = Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusChip(status: task.status),
              ],
            ),
            const SizedBox(height: AppTokens.spaceSm),
            LinearProgressIndicator(
              value: task.progress,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
            const SizedBox(height: AppTokens.spaceXs),
            if (selectMode)
              const SizedBox(height: AppTokens.spaceXs)
            else
              Row(
                children: <Widget>[
                  Text(
                    '${task.downloadedChapters} / ${task.totalChapters}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const Spacer(),
                  // 操作按钮：下载中→暂停；已暂停→继续；失败→重试（项 5）
                  if (task.status == DownloadStatus.downloading)
                    _ActionButton(
                      icon: Icons.pause,
                      label: l10n.downloadPause,
                      onPressed: () => manager.pauseTask(task.id),
                    )
                  else if (task.status == DownloadStatus.paused)
                    _ActionButton(
                      icon: Icons.play_arrow,
                      label: l10n.downloadResume,
                      onPressed: () => manager.resumeTask(task.id),
                    )
                  else if (task.status == DownloadStatus.failed)
                    _ActionButton(
                      icon: Icons.refresh,
                      label: l10n.retry,
                      onPressed: () => manager.retryTask(task.id),
                    ),
                  // 取消/移除：始终可用（可移除记录，不删文件）
                  _ActionButton(
                    icon: Icons.cancel_outlined,
                    label: l10n.cancel,
                    isDestructive: true,
                    onPressed: () =>
                        manager.cancel(task.id, deleteFiles: false),
                  ),
                ],
              ),
            if (!selectMode && task.error != null) ...<Widget>[
              const SizedBox(height: AppTokens.spaceXs),
              Text(
                task.error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );

    if (!selectMode) return card;

    // 选择模式：整卡可点切换选中，右上角显示勾选角标，隐藏底部操作行。
    return Stack(
      children: <Widget>[
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          child: card,
        ),
        if (isSelected)
          Positioned(
            top: 6,
            right: 6,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: scheme.primary,
              child: const Icon(Icons.check, size: 16, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final DownloadStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final (label, color) = switch (status) {
      DownloadStatus.pending => (l10n.statusPending, scheme.outline),
      DownloadStatus.downloading =>
        (l10n.statusDownloading, scheme.primary),
      DownloadStatus.paused => (l10n.statusPaused, scheme.tertiary),
      DownloadStatus.failed => (l10n.statusFailed, scheme.error),
      DownloadStatus.completed =>
        (l10n.statusCompleted, scheme.primaryContainer),
      DownloadStatus.cancelled =>
        (l10n.statusCancelled, scheme.outline),
      DownloadStatus.waitingForWifi =>
        (l10n.statusWaitingForWifi, scheme.secondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// 下载卡片底部操作按钮（项 5）：带图标 + 文字，让操作一目了然。
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isDestructive;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = isDestructive ? scheme.error : scheme.primary;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceSm,
          vertical: 0,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
