import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/local/local_content_manager.dart';
import '../../../core/models/bookshelf_filter.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/widgets/bookshelf_content.dart';
import '../../../core/widgets/library_shell.dart';
import '../../../core/widgets/module_source_search_screen.dart';
import '../../../core/widgets/online_source_browser_screen.dart';
import '../../home/presentation/import_comic_screen.dart';
import '../../home/presentation/local_media_viewer.dart';
import '../../rss/presentation/rss_feed_list_screen.dart';
import '../../sources/presentation/collect_api_import_screen.dart';
import '../../sources/presentation/source_manager_screen.dart';
import 'comic_detail_screen.dart';
import 'comic_reader_screen.dart';
import 'manga_online_list_screen.dart';

/// Comic module home — 4-tab layout backed by [LibraryShell].
///
/// The sources tab is rendered inline (source list + collect-API import FAB)
/// rather than pushing a separate [SourceManagerScreen].
class ComicHomeScreen extends StatelessWidget {
  const ComicHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    void navigateToCollectApiImport() {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const CollectApiImportScreen(),
      ));
    }

    // 源管理预览模式时通知外层 LibraryShell 隐藏 FAB（避免遮挡确认条）。
    final fabSuppressed = ValueNotifier<bool>(false);

    return LibraryShell(
      title: l10n.tabLibrary,
      emptyIcon: Icons.auto_stories,
      emptyMessage: l10n.emptyLocalComic,
      onSearch: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ModuleSourceSearchScreen(
            sourceType: SourceType.mangaSource,
            title: l10n.search,
            onItemTap: (MediaItem item) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ComicDetailScreen(item: item),
              ),
            ),
          ),
        ),
      ),
      libraryBodyBuilder: (LibrarySubTab subTab, BookshelfFilter filter) => BookshelfContent(
        sourceType: SourceType.mangaSource,
        subTab: subTab,
        filter: filter,
        emptyIcon: Icons.auto_stories,
        emptyMessage: l10n.emptyLocalComic,
        emptyActionLabel: l10n.emptyLocalComicAction,
        onEmptyAction: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ImportComicScreen(),
          ),
        ),
        onItemTap: (MediaItem item) {
          // R3 修复：本地导入/下载的漫画优先走阅读器本地模式，不再误跳在线详情页。
          final extra = item.extra;
          final localPath = extra == null ? null : extra['localPath'] as String?;
          final localKind = extra == null ? null : extra['localKind'] as String?;
          if (localPath != null && localPath.isNotEmpty && localKind == 'images') {
            final lower = localPath.toLowerCase();
            if (lower.endsWith('.cbz') || lower.endsWith('.zip')) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ComicReaderScreen(
                    comicId: item.id,
                    title: item.title,
                    sourceId: item.sourceId ?? '',
                    chapters: const <Episode>[],
                    localCbzPath: localPath,
                  ),
                ),
              );
              return;
            }
            // cbr/rar/单图/目录走兜底查看器。
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LocalMediaViewer(
                  title: item.title,
                  kind: LocalMediaKind.images,
                  uri: localPath,
                ),
              ),
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ComicDetailScreen(item: item),
            ),
          );
        },
      ),
      onlineBody: OnlineSourceBrowserScreen(
        sourceType: SourceType.mangaSource,
        onAddSource: navigateToCollectApiImport,
        onEnableRecommended:
            () => context.read<SourceRepository>().enableRecommendedSources(),
        onSourceTap: (PluginConfig source) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MangaOnlineListScreen(
              initialSource: source,
              onAddSource: navigateToCollectApiImport,
              onEnableRecommended:
                  () => context.read<SourceRepository>().enableRecommendedSources(),
            ),
          ),
        ),
      ),
      subscribeBody:
          const RssFeedListScreen(moduleType: SourceType.mangaSource),
      sourcesBody: _ComicSourcesBody(
        filterType: SourceType.mangaSource,
        fabSuppressed: fabSuppressed,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: navigateToCollectApiImport,
        icon: const Icon(Icons.cloud_download),
        label: Text(l10n.collectApiImportTitle),
      ),
      categoryProvider: (LibrarySubTab subTab) =>
          BookshelfContent.categoriesFor(
              context, SourceType.mangaSource, subTab),
      historySourceType: SourceType.mangaSource,
      fabSuppressedNotifier: fabSuppressed,
    );
  }
}

class _ComicSourcesBody extends StatelessWidget {
  final SourceType filterType;
  final ValueNotifier<bool> fabSuppressed;

  const _ComicSourcesBody({
    required this.filterType,
    required this.fabSuppressed,
  });

  @override
  Widget build(BuildContext context) {
    return SourceManagerScreen(
      filterType: filterType,
      embedded: true,
      onPreviewModeChanged: (v) => fabSuppressed.value = v,
    );
  }
}
