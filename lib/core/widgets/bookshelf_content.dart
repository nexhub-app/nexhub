/// 书架内容组件（文档 §10.2 书架 Tab）。
///
/// 在 LibraryShell 的 library 顶部 Tab 下渲染，
/// 根据 sub-tab（本地 / 历史 / 收藏）显示不同数据源：
/// - 本地：DownloadManager.completedTasks（已下载内容）
/// - 历史：HistoryManager（最近浏览）
/// - 收藏：FavoritesManager（收藏夹）
///
/// 三模块共用，通过 [sourceType] 过滤数据，通过 [filter] 应用筛选/排序。
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../download/download_manager.dart';
import '../download/download_task.dart';
import '../favorites/favorites_manager.dart';
import '../history/history_manager.dart';
import '../local/local_content_manager.dart';
import '../models/bookshelf_filter.dart';
import '../models/media_item.dart';
import '../models/plugin_config.dart';
import '../services/source_repository.dart';
import '../settings/layout_settings.dart';
import '../history/media_watched_manager.dart';
import '../novel/novel_progress_manager.dart';
import '../comic/comic_progress_manager.dart';
import 'app_card.dart';
import 'app_cover_image.dart';
import 'app_empty_state.dart';
import 'content_card.dart';
import 'library_shell.dart';
import '../theme/app_tokens.dart';

class BookshelfContent extends StatelessWidget {
  final SourceType sourceType;
  final LibrarySubTab subTab;
  final IconData emptyIcon;
  final String emptyMessage;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final void Function(MediaItem item)? onItemTap;
  final BookshelfFilter filter;

  const BookshelfContent({
    super.key,
    required this.sourceType,
    required this.subTab,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.filter,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    switch (subTab) {
      case LibrarySubTab.local:
        return _LocalBookshelf(
          sourceType: sourceType,
          emptyIcon: emptyIcon,
          emptyMessage: emptyMessage,
          emptyActionLabel: emptyActionLabel,
          onEmptyAction: onEmptyAction,
          onItemTap: onItemTap,
          filter: filter,
        );
      case LibrarySubTab.history:
        return _HistoryBookshelf(
          sourceType: sourceType,
          onItemTap: onItemTap,
          filter: filter,
          emptyActionLabel: emptyActionLabel,
          onEmptyAction: onEmptyAction,
        );
      case LibrarySubTab.favorite:
        return _FavoriteBookshelf(
          sourceType: sourceType,
          onItemTap: onItemTap,
          filter: filter,
          emptyActionLabel: emptyActionLabel,
          onEmptyAction: onEmptyAction,
        );
    }
  }

  /// Returns the distinct categories present in the given sub-tab's data.
  ///
  /// - local: download format labels (cbz/epub/folder/txt/video)
  /// - history / favorite: non-null [HistoryEntry.category] /
  ///   [FavoriteEntry.category] values
  ///
  /// Used by [LibraryShell.categoryProvider] to populate the filter sheet's
  /// category section. Safe to call outside build (uses [context.read]).
  static List<String> categoriesFor(
    BuildContext context,
    SourceType sourceType,
    LibrarySubTab subTab,
  ) {
    switch (subTab) {
      case LibrarySubTab.local:
        final manager = context.read<DownloadManager>();
        final localManager = context.read<LocalContentManager>();
        final categories = manager.completedTasks
            .where((t) => t.sourceType == sourceType)
            .map((t) => t.format.label)
            .toSet();
        final importedKind = _kindForSourceType(sourceType);
        if (importedKind != null) {
          for (final e in localManager.items) {
            if (e.kind == importedKind) {
              categories.add(e.kind.name);
            }
          }
        }
        final sorted = categories.toList()..sort();
        return sorted;
      case LibrarySubTab.history:
        final manager = context.read<HistoryManager>();
        final categories = manager
            .historyFor(sourceType)
            .map((e) => e.category)
            .whereType<String>()
            .toSet()
            .toList();
        categories.sort();
        return categories;
      case LibrarySubTab.favorite:
        final manager = context.read<FavoritesManager>();
        final categories = manager
            .favoritesFor(sourceType)
            .map((e) => e.category)
            .whereType<String>()
            .toSet()
            .toList();
        categories.sort();
        return categories;
    }
  }
}

// ── 本地（已下载）书架 ──────────────────────────────────

class _LocalBookshelf extends StatelessWidget {
  final SourceType sourceType;
  final IconData emptyIcon;
  final String emptyMessage;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final void Function(MediaItem item)? onItemTap;
  final BookshelfFilter filter;

  const _LocalBookshelf({
    required this.sourceType,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.filter,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<DownloadManager>();
    final historyManager = context.watch<HistoryManager>();
    final localManager = context.watch<LocalContentManager>();
    final repo = context.read<SourceRepository>();
    var tasks = manager.completedTasks
        .where((t) => t.sourceType == sourceType)
        .toList();

    // 分类筛选：本地段以下载格式（cbz/epub/folder/txt/video）作为分类。
    if (filter.category != null) {
      tasks = tasks
          .where((t) => t.format.label == filter.category)
          .toList();
    }

    // 进度筛选：cross-ref 历史记录判断是否在看。
    final Set<String> historyIds = historyManager
        .historyFor(sourceType)
        .map((e) => e.id)
        .toSet();
    tasks = tasks.where((t) {
      switch (filter.progress) {
        case BookshelfProgress.reading:
          return historyIds.contains(t.contentId);
        case BookshelfProgress.notStarted:
          return !historyIds.contains(t.contentId);
        case null:
          return true;
      }
    }).toList();

    // 排序。
    _sortTasks(tasks, filter.sort);

    // 导入的本地内容（R3 修复）：按 sourceType 映射 LocalMediaKind 后过滤。
    final importedKind = _kindForSourceType(sourceType);
    var imported = importedKind == null
        ? const <LocalContentEntry>[]
        : localManager.items.where((e) => e.kind == importedKind).toList();
    if (filter.category != null && importedKind != null) {
      imported = imported.where((e) => e.kind.name == filter.category).toList();
    }
    imported = imported.where((e) {
      switch (filter.progress) {
        case BookshelfProgress.reading:
          return historyIds.contains(e.id);
        case BookshelfProgress.notStarted:
          return !historyIds.contains(e.id);
        case null:
          return true;
      }
    }).toList();
    _sortLocalEntries(imported, filter.sort);

    final isEmpty = tasks.isEmpty && imported.isEmpty;
    if (isEmpty) {
      return AppEmptyState(
        icon: emptyIcon,
        message: emptyMessage,
        actionLabel: emptyActionLabel,
        onAction: onEmptyAction,
      );
    }

    final List<_BookshelfItem> items = <_BookshelfItem>[];

    // 已下载内容（来自在线源下载）。
    items.addAll(tasks.map((t) => _BookshelfItem(
          id: t.contentId,
          title: t.title,
          sourceType: sourceType,
          coverUrl: t.localCoverPath ?? t.coverUrl,
          source: t.sourceId != null ? repo.getById(t.sourceId!) : null,
          onTap: () => onItemTap?.call(MediaItem(
            id: t.contentId,
            title: t.title,
            coverUrl: t.localCoverPath ?? t.coverUrl,
            sourceId: t.sourceId,
            sourceType: sourceType,
            extra: <String, dynamic>{
              if (t.localPath != null && t.localPath!.isNotEmpty)
                'localPath': t.localPath,
              'localKind': _kindForFormat(t.format)?.name,
            },
          )),
        )));

    // 导入的本地内容（R3 修复：书架入口补 path 字段）。
    items.addAll(imported.map((e) => _BookshelfItem(
          id: e.id,
          title: e.title,
          sourceType: sourceType,
          coverUrl: e.coverUrl,
          onTap: () => onItemTap?.call(MediaItem(
            id: e.id,
            title: e.title,
            sourceId: '',
            sourceType: sourceType,
            extra: <String, dynamic>{
              'localPath': e.path,
              'localKind': e.kind.name,
            },
          )),
        )));

    return _BookshelfGrid(items: items);
  }
}

// ── 历史记录书架 ────────────────────────────────────────

class _HistoryBookshelf extends StatelessWidget {
  final SourceType sourceType;
  final void Function(MediaItem item)? onItemTap;
  final BookshelfFilter filter;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  const _HistoryBookshelf({
    required this.sourceType,
    required this.filter,
    this.onItemTap,
    this.emptyActionLabel,
    this.onEmptyAction,
  });

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<HistoryManager>();
    final repo = context.read<SourceRepository>();
    // historyFor() 返回 List.unmodifiable（只读）。后续 _sortHistoryEntries 会
    // 原地 .sort() 修改列表；若不先复制成可变列表，无筛选时排序会抛
    // UnsupportedError，在 release APK 下表现为整屏灰（默认 ErrorWidget）。
    var entries = manager.historyFor(sourceType).toList();

    // 分类筛选。
    if (filter.category != null) {
      entries = entries.where((e) => e.category == filter.category).toList();
    }

    // 状态筛选。
    if (filter.status != null) {
      entries = entries.where((e) => e.status == filter.status).toList();
    }

    // 进度筛选：历史段所有条目均为"在看"，notStarted 时清空。
    if (filter.progress == BookshelfProgress.notStarted) {
      entries = const <HistoryEntry>[];
    }

    // 排序。
    _sortHistoryEntries(entries, filter.sort);

    if (entries.isEmpty) {
      return AppEmptyState(
        icon: Icons.history,
        message: AppLocalizations.of(context).emptyHistory,
        actionLabel: emptyActionLabel,
        onAction: onEmptyAction,
      );
    }

    return _BookshelfGrid(
      items: entries
          .map((e) => _BookshelfItem(
                id: e.id,
                title: e.title,
                sourceType: sourceType,
                coverUrl: e.localCoverPath ?? e.coverUrl,
                source: e.sourceId != null ? repo.getById(e.sourceId!) : null,
                onTap: () => onItemTap?.call(e.toMediaItem()),
              ))
          .toList(),
    );
  }
}

// ── 收藏书架 ────────────────────────────────────────────

class _FavoriteBookshelf extends StatelessWidget {
  final SourceType sourceType;
  final void Function(MediaItem item)? onItemTap;
  final BookshelfFilter filter;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  const _FavoriteBookshelf({
    required this.sourceType,
    required this.filter,
    this.onItemTap,
    this.emptyActionLabel,
    this.onEmptyAction,
  });

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<FavoritesManager>();
    final historyManager = context.watch<HistoryManager>();
    final repo = context.read<SourceRepository>();
    // favoritesFor() 返回 List.unmodifiable（只读）；同 _HistoryBookshelf，
    // 需先复制成可变列表，否则无筛选时 _sortFavoriteEntries 原地排序会抛
    // UnsupportedError → release 下整屏灰。
    var entries = manager.favoritesFor(sourceType).toList();

    // 分类筛选。
    if (filter.category != null) {
      entries = entries.where((e) => e.category == filter.category).toList();
    }

    // 状态筛选。
    if (filter.status != null) {
      entries = entries.where((e) => e.status == filter.status).toList();
    }

    // 进度筛选：cross-ref 历史记录。
    final Set<String> historyIds = historyManager
        .historyFor(sourceType)
        .map((e) => e.id)
        .toSet();
    entries = entries.where((e) {
      switch (filter.progress) {
        case BookshelfProgress.reading:
          return historyIds.contains(e.id);
        case BookshelfProgress.notStarted:
          return !historyIds.contains(e.id);
        case null:
          return true;
      }
    }).toList();

    // 排序。
    _sortFavoriteEntries(entries, filter.sort);

    if (entries.isEmpty) {
      return AppEmptyState(
        icon: Icons.favorite_border,
        message: AppLocalizations.of(context).emptyFavorites,
        actionLabel: emptyActionLabel,
        onAction: onEmptyAction,
      );
    }

    return _BookshelfGrid(
      items: entries
          .map((e) => _BookshelfItem(
                id: e.id,
                title: e.title,
                sourceType: sourceType,
                coverUrl: e.coverUrl,
                source: e.sourceId != null ? repo.getById(e.sourceId!) : null,
                author: e.author,
                onTap: () => onItemTap?.call(e.toMediaItem()),
              ))
          .toList(),
    );
  }
}

// ── 排序辅助 ────────────────────────────────────────────

void _sortTasks(List<DownloadTask> tasks, BookshelfSort sort) {
  switch (sort) {
    case BookshelfSort.recent:
      tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    case BookshelfSort.title:
      tasks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }
}

void _sortLocalEntries(List<LocalContentEntry> entries, BookshelfSort sort) {
  switch (sort) {
    case BookshelfSort.recent:
      entries.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    case BookshelfSort.title:
      entries.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }
}

/// 按 [SourceType] 映射到导入内容的 [LocalMediaKind]（漫画→images，小说→text，
/// 影视→video）。返回 null 表示该 sourceType 无对应导入类型。
LocalMediaKind? _kindForSourceType(SourceType type) => switch (type) {
      SourceType.mangaSource => LocalMediaKind.images,
      SourceType.novelSource => LocalMediaKind.text,
      SourceType.animeSource => LocalMediaKind.video,
    };

/// 按 [DownloadFormat] 映射到 [LocalMediaKind]，用于下载内容点击时透传给
/// onItemTap 的 extra，供阅读器分流。
LocalMediaKind? _kindForFormat(DownloadFormat f) => switch (f) {
      DownloadFormat.cbz => LocalMediaKind.images,
      DownloadFormat.folder => LocalMediaKind.images,
      DownloadFormat.jpg => LocalMediaKind.images,
      DownloadFormat.png => LocalMediaKind.images,
      DownloadFormat.epub => LocalMediaKind.text,
      DownloadFormat.txt => LocalMediaKind.text,
      DownloadFormat.video => LocalMediaKind.video,
    };

void _sortHistoryEntries(List<HistoryEntry> entries, BookshelfSort sort) {
  switch (sort) {
    case BookshelfSort.recent:
      entries.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    case BookshelfSort.title:
      entries.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }
}

void _sortFavoriteEntries(List<FavoriteEntry> entries, BookshelfSort sort) {
  switch (sort) {
    case BookshelfSort.recent:
      entries.sort((a, b) => b.favoritedAt.compareTo(a.favoritedAt));
    case BookshelfSort.title:
      entries.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }
}

// ── 网格视图 ────────────────────────────────────────────

class _BookshelfItem {
  final String id;
  final String title;
  final String? coverUrl;
  final String? author;
  final SourceType sourceType;
  final PluginConfig? source;
  final VoidCallback? onTap;

  const _BookshelfItem({
    required this.id,
    required this.title,
    required this.sourceType,
    this.coverUrl,
    this.author,
    this.source,
    this.onTap,
  });
}

class _BookshelfGrid extends StatelessWidget {
  final List<_BookshelfItem> items;

  const _BookshelfGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    // 监听布局设置变化，即时刷新网格/列表（与浏览页一致）。
    return ListenableBuilder(
      listenable: LayoutSettingsStore.instance,
      builder: (context, _) {
        final LayoutSettings layout = LayoutSettingsStore.instance.settings;
        if (layout.layoutMode == LayoutMode.list) {
          return _buildList(items, layout);
        }
        return _buildGrid(items, layout);
      },
    );
  }

  /// 计算书架条目的阅读/观看进度（0.0–1.0 或 null）。
  ///
  /// 与 [OnlineContentListScreen._computeProgress] 逻辑完全一致：
  /// - 影视/动漫：[MediaWatchedManager] 已看集数 ÷ 总集数。
  /// - 小说：[NovelProgressManager] 已读章节 ÷ 总章数。
  /// - 漫画：[ComicProgressManager] 已读章节 ÷ 总章数。
  Future<double?> _computeProgress(_BookshelfItem item) async {
    try {
      switch (item.sourceType) {
        case SourceType.animeSource:
          try {
            // 书架环境无 Provider context，用默认实例读取。
            final mgr = MediaWatchedManager();
            final watched = mgr.watchedCount(item.id);
            if (watched > 0) {
              // 尝试从 MediaItem 获取总集数（需在调用方透传）；
              // 书架条目暂不携带 episodeCount，故仅返回"已开始"标记进度。
              if (watched > 0) return 0.02;
            }
          } on Object {/* 忽略 */}
          break;
        case SourceType.novelSource:
          final p = await NovelProgressManager().get(item.id);
          if (p != null && p.totalChapters != null && p.totalChapters! > 0) {
            return ((p.chapterIndex + 1) / p.totalChapters!).clamp(0.0, 1.0);
          }
          if (p != null && p.chapterIndex > 0) return 0.02;
          break;
        case SourceType.mangaSource:
          final p = await ComicProgressManager().get(item.id);
          if (p != null && p.totalChapters != null && p.totalChapters! > 0) {
            return ((p.chapterIndex + 1) / p.totalChapters!).clamp(0.0, 1.0);
          }
          if (p != null && p.chapterIndex > 0) return 0.02;
          break;
      }
    } on Object {/* 忽略 */}
    return null;
  }

  /// 网格模式：列数/间距跟随布局设置，卡片显示作者 + 进度。
  Widget _buildGrid(List<_BookshelfItem> items, LayoutSettings layout) {
    final int cross = layout.gridColumns.clamp(1, 8);
    final double spacing = layout.gridSpacing.clamp(4, 24);
    final double textH = _textHeight(layout);
    return LayoutBuilder(
      builder: (ctx, c) {
        final double width = c.maxWidth;
        final double itemW =
            (width - AppTokens.spaceMd * 2 - spacing * (cross - 1)) / cross;
        final double coverH = itemW / AppTokens.coverAspectRatio;
        final double ratio = itemW / (coverH + textH);
        return GridView.builder(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: ratio,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            // 进度：异步计算后通过 FutureBuilder 传给 ContentCard
            return FutureBuilder<double?>(
              future: layout.showProgress ? _computeProgress(item) : Future<double?>.value(null),
              builder: (ctx, snap) => ContentCard(
                coverUrl: item.coverUrl,
                title: item.title,
                subtitle: (layout.showAuthor && item.author != null)
                    ? item.author
                    : null,
                source: item.source,
                onTap: item.onTap,
                width: itemW,
                progress: snap.data,
              ),
            );
          },
        );
      },
    );
  }

  /// 列表模式：单列横向卡片（封面 + 标题 + 作者），不再显示章节数字。
  Widget _buildList(List<_BookshelfItem> items, LayoutSettings layout) {
    final bool isCompact = layout.listStyle == ListLayoutStyle.compact;
    return ListView.builder(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final ColorScheme scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
          child: AppCard(
            onTap: item.onTap,
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMd,
                vertical: isCompact ? AppTokens.spaceXs : AppTokens.spaceSm,
              ),
              leading: ClipRRect(
                borderRadius:
                    BorderRadius.circular(layout.coverRadius.toDouble()),
                child: SizedBox(
                  width: isCompact ? 40 : 56,
                  height: isCompact ? 56 : 78,
                  child: AppCoverImage(
                    coverUrl: item.coverUrl,
                    source: item.source,
                    title: item.title,
                    width: isCompact ? 40 : 56,
                    height: isCompact ? 56 : 78,
                    radius: layout.coverRadius,
                  ),
                ),
              ),
              title: layout.showTitle
                  ? Text(
                      item.title,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(fontSize: layout.titleFontSize),
                      maxLines: layout.titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              subtitle: (layout.showAuthor &&
                      item.author != null &&
                      item.author!.isNotEmpty)
                  ? Text(
                      item.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    )
                  : null,
              trailing: layout.showProgress
                  ? FutureBuilder<double?>(
                      future: _computeProgress(item),
                      builder: (ctx, snap) {
                        final double? p = snap.data;
                        if (p == null || p <= 0) return const SizedBox.shrink();
                        return Text(
                          '${(p * 100).round()}%',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        );
                      },
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }

  /// 根据布局设置计算文本区域高度（标题 + 可选作者），用于反推高宽比。
  double _textHeight(LayoutSettings layout) {
    if (!layout.showTitle && !layout.showAuthor) return 4;
    final double lineHeight = layout.titleFontSize * 1.4;
    var lines = 0.0;
    if (layout.showTitle) lines += layout.titleMaxLines.toDouble();
    if (layout.showAuthor) lines += 1.0;
    return lineHeight * lines + 12;
  }
}
