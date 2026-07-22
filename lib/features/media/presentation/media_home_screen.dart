import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/models/bookshelf_filter.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/widgets/bookshelf_content.dart';
import '../../../core/widgets/library_shell.dart';
import '../../../core/widgets/module_source_search_screen.dart';
import '../../../core/widgets/online_source_browser_screen.dart';
import '../../home/presentation/import_media_screen.dart';
import '../../player/presentation/video_player_screen.dart';
import '../../rss/presentation/rss_feed_list_screen.dart';
import '../../sources/presentation/collect_api_import_screen.dart';
import '../../sources/presentation/source_manager_screen.dart';
import 'content_detail_screen.dart';
import 'media_online_list_screen.dart';

/// Media module home — 4-tab layout backed by [LibraryShell].
///
/// The sources tab is rendered inline (source list + collect-API import FAB)
/// rather than pushing a separate [SourceManagerScreen].
class MediaHomeScreen extends StatelessWidget {
  const MediaHomeScreen({super.key});

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
      emptyIcon: Icons.movie,
      emptyMessage: l10n.emptyLocalMedia,
      onSearch: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ModuleSourceSearchScreen(
            sourceType: SourceType.animeSource,
            title: l10n.search,
            onItemTap: (MediaItem item) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ContentDetailScreen(item: item),
              ),
            ),
          ),
        ),
      ),
      libraryBodyBuilder: (LibrarySubTab subTab, BookshelfFilter filter) => BookshelfContent(
        sourceType: SourceType.animeSource,
        subTab: subTab,
        filter: filter,
        emptyIcon: Icons.movie,
        emptyMessage: l10n.emptyLocalMedia,
        emptyActionLabel: l10n.emptyLocalMediaAction,
        onEmptyAction: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ImportMediaScreen(),
          ),
        ),
        onItemTap: (MediaItem item) {
          // R3 修复（影视段）：本地导入/下载的视频优先走本地播放，不跳在线详情页。
          final extra = item.extra;
          final localPath = extra == null ? null : extra['localPath'] as String?;
          final localKind = extra == null ? null : extra['localKind'] as String?;
          if (localPath != null && localPath.isNotEmpty && localKind == 'video') {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => VideoPlayerScreen(
                  title: item.title,
                  episode: Episode(id: 'local', title: item.title, url: localPath),
                  sourceId: item.sourceId ?? '',
                  itemId: item.id,
                  localUri: localPath,
                ),
              ),
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ContentDetailScreen(item: item),
            ),
          );
        },
      ),
      onlineBody: OnlineSourceBrowserScreen(
        sourceType: SourceType.animeSource,
        onAddSource: navigateToCollectApiImport,
        onEnableRecommended:
            () => context.read<SourceRepository>().enableRecommendedSources(),
        onSourceTap: (PluginConfig source) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MediaOnlineListScreen(
              initialSource: source,
              onAddSource: navigateToCollectApiImport,
              onEnableRecommended:
                  () => context.read<SourceRepository>().enableRecommendedSources(),
            ),
          ),
        ),
      ),
      subscribeBody:
          const RssFeedListScreen(moduleType: SourceType.animeSource),
      sourcesBody: _MediaSourcesBody(
        filterType: SourceType.animeSource,
        fabSuppressed: fabSuppressed,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: navigateToCollectApiImport,
        icon: const Icon(Icons.cloud_download),
        label: Text(l10n.collectApiImportTitle),
      ),
      categoryProvider: (LibrarySubTab subTab) =>
          BookshelfContent.categoriesFor(
              context, SourceType.animeSource, subTab),
      historySourceType: SourceType.animeSource,
      fabSuppressedNotifier: fabSuppressed,
    );
  }
}

class _MediaSourcesBody extends StatelessWidget {
  final SourceType filterType;
  final ValueNotifier<bool> fabSuppressed;

  const _MediaSourcesBody({
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
