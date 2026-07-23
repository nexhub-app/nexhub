import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/download/download_manager.dart';
import '../../../core/favorites/favorites_manager.dart';
import '../../../core/history/history_manager.dart';
import '../../../core/history/media_watched_manager.dart';
import '../../../core/history/media_playback_position_manager.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/scraper/verification_detector.dart';
import '../../../core/resolver/webview_resolver.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_cover_image.dart';
import '../../../core/widgets/chapter_list_section.dart';
import '../../../core/widgets/content_card.dart';
import '../../../core/widgets/content_detail_shell.dart';
import '../../../core/widgets/detail_action_utils.dart';
import '../../../core/widgets/module_source_search_screen.dart';
import '../../../core/widgets/progress_card.dart';
import '../../player/presentation/video_player_screen.dart';
import '../../verification/presentation/webview_verification_screen.dart';
import '../../manga/presentation/comic_reader_screen.dart';
import '../../novel/presentation/novel_reader_screen.dart';
import 'series_detail_screen.dart';

/// 通用内容详情页（动漫 / 影视 / 小说 / 漫画 共用）。
///
/// 按 [MediaItem] 从源拉取剧集 / 章节，按线路分组；媒体类点击进入
/// [VideoPlayerScreen]，小说 / 漫画类进入对应阅读器。
///
/// 支持收藏切换、下载启动、分享、以及验证异常捕获。
///
/// M16.2 对账增强：续看 / 删除 / WebView / 浏览器 / 系统分享 / 更新时间 /
/// 标签 chip / 演员/导演 chip / 封面大图 / 选集筛选排序 / 单集下载 /
/// 已看标记 / 刷新元数据 / 下载快捷预设。
class ContentDetailScreen extends StatefulWidget {
  final MediaItem item;
  const ContentDetailScreen({super.key, required this.item});

  @override
  State<ContentDetailScreen> createState() => _ContentDetailScreenState();
}

class _ContentDetailScreenState extends State<ContentDetailScreen> {
  late Future<List<Episode>> _episodesFuture;
  List<Episode> _chapters = const <Episode>[];

  /// Recommendations future; null when the source has no recommend route.
  Future<List<MediaItem>>? _recommendationsFuture;

  /// 验证异常状态（非 null 时显示验证引导 UI）。
  VerificationRequiredException? _verificationError;
  /// 渲染后抽取请求（webview-html 模式）：非 null 时显示「抓取本页渲染内容」引导。
  WebViewHtmlRequest? _htmlCaptureRequest;
  /// 渲染后回灌的整页 HTML（重试抓取时复用源选择器解析）。
  String? _renderedHtml;

  /// detail 路由拉回的完整条目（含系列/季信息）；初始为传入的 [widget.item]，
  /// detail 路由解析成功后通过 [setState] 更新，从而控制"系列"入口显示。
  late MediaItem _fetchedDetail;

  /// 续看集索引（-1 表示无续看记录，从首集开始）。
  int _continueIndex = -1;

  /// 已加载的全部剧集列表（供 _openContent 传给播放器支持切集）。
  List<Episode> _allEpisodes = const <Episode>[];

  @override
  void initState() {
    super.initState();
    _fetchedDetail = widget.item;
    _load();
    _recordHistory();
    _loadContinueIndex();
  }

  void _loadContinueIndex() {
    try {
      // 优先从播放位置管理器取最后播放的剧集（P8.1.2 §廿一 续读进度跨章节恢复）
      final posMgr = context.read<MediaPlaybackPositionManager>();
      final lastEp = posMgr.getLastEpisode(widget.item.id);
      if (lastEp >= 0) {
        setState(() => _continueIndex = lastEp);
        return;
      }
    } catch (_) {
      // MediaPlaybackPositionManager 不可用时不影响页面。
    }
    try {
      final watched = context.read<MediaWatchedManager>();
      final list = watched.watchedList(widget.item.id);
      if (list.isNotEmpty) {
        // 续看 = 最后已看集 + 1（若超出范围则回退首集）。
        final last = list.last;
        setState(() => _continueIndex = last + 1);
      }
    } catch (_) {
      // MediaWatchedManager 不可用时不影响页面。
    }
  }

  void _recordHistory() {
    try {
      final history = context.read<HistoryManager>();
      history.addHistory(widget.item, sourceType: SourceType.animeSource);
    } catch (_) {
      // HistoryManager 不可用时不影响页面。
    }
  }

  void _load() {
    final repo = context.read<SourceRepository>();
    final service = context.read<MediaApiService>();
    final sid = widget.item.sourceId;
    final id = widget.item.id;
    if (sid == null) {
      _episodesFuture = Future<List<Episode>>.error(
        Exception('item missing source id'),
      );
      return;
    }
    final source = repo.getById(sid);
    if (source == null) {
      _episodesFuture = Future<List<Episode>>.error(
        Exception('source not found: $sid'),
      );
      return;
    }
    final String? recommendRoute = source.routes.containsKey('recommend')
        ? 'recommend'
        : (source.routes.containsKey('related') ? 'related' : null);
    _recommendationsFuture = recommendRoute == null
        ? null
        : service.fetchApiResults(
            source,
            recommendRoute,
            vars: <String, String>{'id': id},
          );
    final future = switch (source.type) {
      SourceType.mangaSource =>
        service.fetchChapters(source, id, renderedHtml: _renderedHtml),
      SourceType.novelSource =>
        service.fetchNovelChapters(source, id, renderedHtml: _renderedHtml),
      _ => service.fetchEpisodes(source, id,
          title: widget.item.title, renderedHtml: _renderedHtml),
    };
    _episodesFuture = future;
    future.then((list) {
      if (mounted) setState(() => _chapters = list);
    }).catchError((Object error) {
      if (error is WebViewHtmlRequest && mounted) {
        setState(() => _htmlCaptureRequest = error);
      } else if (error is VerificationRequiredException && mounted) {
        setState(() => _verificationError = error);
      }
    });

    if (source.routes.containsKey('detail')) {
      service
          .fetchDetail(source, id,
              detailUrl: widget.item.detailUrl, renderedHtml: _renderedHtml)
          .then((detail) {
        if (mounted) {
          // 兜底：detail 路由产物字段可能为空（采集 API _itemFromMap 用 _s()
          // 转字段，缺失 → "" 而非 null，?? 无法兜底）。用原始列表 item 补全，
          // 防止 build 因 sourceId 空整页报错、或因 cover/title 空而空白。
          final safe = detail.copyWith(
            id: detail.id.isEmpty ? widget.item.id : detail.id,
            sourceId: (detail.sourceId != null && detail.sourceId!.isNotEmpty)
                ? detail.sourceId
                : widget.item.sourceId,
            title: detail.title.isEmpty ? widget.item.title : detail.title,
            coverUrl: (detail.coverUrl != null && detail.coverUrl!.isNotEmpty)
                ? detail.coverUrl
                : widget.item.coverUrl,
            description:
                (detail.description != null && detail.description!.isNotEmpty)
                    ? detail.description
                    : widget.item.description,
          );
          setState(() => _fetchedDetail = safe);
        }
      }).catchError((Object error) {
        if (error is WebViewHtmlRequest && mounted) {
          setState(() => _htmlCaptureRequest = error);
        }
      });
    }
  }

  void _retryAfterVerification() {
    setState(() => _verificationError = null);
    _load();
  }

  /// 渲染后抽取完成后回填 HTML 并重试抓取（xgcartoon 等 webview-html 源）。
  Future<void> _retryAfterHtmlCapture(String html) async {
    if (!mounted) return;
    setState(() {
      _htmlCaptureRequest = null;
      _verificationError = null;
      _renderedHtml = html;
    });
    _load();
  }

  void _openContent(Episode ep, int index) {
    final l10n = AppLocalizations.of(context);
    final sid = widget.item.sourceId;
    if (widget.item.sourceType == SourceType.animeSource && sid != null) {
      // 标记已看。
      try {
        context.read<MediaWatchedManager>().markWatched(widget.item.id, index);
      } catch (_) {}
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VideoPlayerScreen(
            title: widget.item.title,
            episode: ep,
            sourceId: sid,
            itemId: widget.item.id,
            episodes: _allEpisodes.isNotEmpty ? _allEpisodes : null,
            initialEpisodeIndex: index,
            favoriteType: widget.item.sourceType,
            detailUrl: _fetchedDetail.detailUrl ?? widget.item.detailUrl,
            coverUrl: _fetchedDetail.coverUrl ?? widget.item.coverUrl,
          ),
        ),
      );
    } else if (widget.item.sourceType == SourceType.mangaSource && sid != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ComicReaderScreen(
            comicId: widget.item.id,
            title: widget.item.title,
            sourceId: sid,
            chapters: _chapters,
            initialChapterIndex: index,
            restoreProgress: false,
            detailUrl: _fetchedDetail.detailUrl ?? widget.item.detailUrl,
            coverUrl: _fetchedDetail.coverUrl ?? widget.item.coverUrl,
          ),
        ),
      );
    } else if (widget.item.sourceType == SourceType.novelSource && sid != null) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NovelReaderScreen(
            novelId: widget.item.id,
            title: widget.item.title,
            sourceId: sid,
            chapters: _chapters,
            initialChapterIndex: index,
            detailUrl: _fetchedDetail.detailUrl ?? widget.item.detailUrl,
            coverUrl: _fetchedDetail.coverUrl ?? widget.item.coverUrl,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.loading)),
      );
    }
  }

  Future<void> _toggleFavorite() async {
    final l10n = AppLocalizations.of(context);
    final fav = context.read<FavoritesManager>();
    final type = widget.item.sourceType ?? SourceType.animeSource;
    final wasFavorite = fav.isFavorite(widget.item.id, type);
    await fav.toggleFavorite(widget.item);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(wasFavorite ? l10n.favoriteRemoved : l10n.favoriteAdded),
        ),
      );
    }
  }

  /// 从收藏移除并返回上一页。
  Future<void> _removeFromFavorites() async {
    final l10n = AppLocalizations.of(context);
    final fav = context.read<FavoritesManager>();
    final type = widget.item.sourceType ?? SourceType.animeSource;
    await fav.removeFavorite(widget.item.id, type);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.removeFromFavorites)),
      );
      Navigator.of(context).pop();
    }
  }

  /// 刷新元数据：重新拉取详情/剧集。
  void _refreshMetadata() {
    setState(() {
      _chapters = const <Episode>[];
    });
    _load();
  }

  /// 下拉刷新回调。
  Future<void> _onRefresh() async {
    setState(() {
      _chapters = const <Episode>[];
    });
    _load();
    try {
      await _episodesFuture;
    } catch (_) {
      // 错误状态由 FutureBuilder 展示
    }
  }

  /// 弹出全屏封面大图查看器。
  void _showCoverViewer(BuildContext context) {
    final coverUrl = _fetchedDetail.coverUrl ?? widget.item.coverUrl;
    if (coverUrl == null || coverUrl.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CoverViewerScreen(
          coverUrl: coverUrl,
          title: widget.item.title,
          source: widget.item.sourceId == null
              ? null
              : context.read<SourceRepository>().getById(widget.item.sourceId!),
        ),
      ),
    );
  }

  Future<void> _startDownload() async {
    final l10n = AppLocalizations.of(context);
    final dl = context.read<DownloadManager>();
    if (dl.isItemDownloaded(widget.item.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.alreadyDownloaded)),
      );
      return;
    }
    if (_chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.emptyContent)),
      );
      return;
    }
    final selected = await _showEpisodeSelectionSheet();
    if (selected == null || selected.isEmpty || !mounted) return;
    await dl.addTask(
      item: widget.item,
      chapters: _chapters,
      chapterIndices: selected,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.downloadStarted)),
      );
    }
  }

  /// 下载单集。
  Future<void> _downloadSingleEpisode(Episode ep, int index) async {
    final l10n = AppLocalizations.of(context);
    final dl = context.read<DownloadManager>();
    await dl.addTask(
      item: widget.item,
      chapters: _chapters,
      chapterIndices: <int>[index],
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.downloadStarted)),
      );
    }
  }

  /// 切换某集已看状态。
  Future<void> _toggleWatched(Episode ep, int index) async {
    try {
      await context.read<MediaWatchedManager>().toggleWatched(
            widget.item.id,
            index,
          );
    } catch (_) {}
  }

  Future<List<int>?> _showEpisodeSelectionSheet() {
    final l10n = AppLocalizations.of(context);
    final Set<int> selected = <int>{};
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController();

    return showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetCtx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, void Function(void Function()) setSheetState) {
            final total = _chapters.length;
            void selectAll() => setSheetState(() {
                  selected
                    ..clear()
                    ..addAll(List<int>.generate(total, (i) => i));
                });
            void deselectAll() => setSheetState(() => selected.clear());
            void applyRange() {
              final s = int.tryParse(startCtrl.text);
              final e = int.tryParse(endCtrl.text);
              if (s == null || e == null) return;
              final start = s.clamp(1, total);
              final end = e.clamp(1, total);
              final lo = start < end ? start : end;
              final hi = start < end ? end : start;
              setSheetState(() {
                selected
                  ..clear()
                  ..addAll(List<int>.generate(hi - lo + 1, (i) => lo - 1 + i));
              });
            }

            // 下载快捷预设。
            void presetLatest(int n) => setSheetState(() {
                  selected
                    ..clear()
                    ..addAll(List<int>.generate(
                        n > total ? total : n, (i) => total - 1 - i));
                });
            void presetUnread() {
              final watched = context.read<MediaWatchedManager>();
              final watchedSet = watched.watchedList(widget.item.id).toSet();
              setSheetState(() {
                selected
                  ..clear()
                  ..addAll(List<int>.generate(total, (i) => i)
                      .where((i) => !watchedSet.contains(i)));
              });
            }

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(AppTokens.spaceMd),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              l10n.downloadEpisodes,
                              style: Theme.of(ctx).textTheme.titleMedium,
                            ),
                          ),
                          TextButton(onPressed: selectAll, child: Text(l10n.selectAll)),
                          TextButton(onPressed: deselectAll, child: Text(l10n.deselectAll)),
                        ],
                      ),
                    ),
                    // 快捷预设按钮行。
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.spaceMd),
                      child: Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          ActionChip(
                            label: Text(l10n.downloadPreset1),
                            onPressed: () => presetLatest(1),
                          ),
                          ActionChip(
                            label: Text(l10n.downloadPreset5),
                            onPressed: () => presetLatest(5),
                          ),
                          ActionChip(
                            label: Text(l10n.downloadPreset10),
                            onPressed: () => presetLatest(10),
                          ),
                          ActionChip(
                            label: Text(l10n.downloadUnread),
                            onPressed: presetUnread,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
                      child: Row(
                        children: <Widget>[
                          Text(l10n.episodeRange),
                          const SizedBox(width: AppTokens.spaceSm),
                          SizedBox(
                            width: 56,
                            child: TextField(
                              controller: startCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: l10n.rangeStart,
                              ),
                            ),
                          ),
                          const Text(' - '),
                          SizedBox(
                            width: 56,
                            child: TextField(
                              controller: endCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: l10n.rangeEnd,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTokens.spaceSm),
                          TextButton(onPressed: applyRange, child: Text(l10n.applyRange)),
                        ],
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: total,
                        itemBuilder: (BuildContext _, int i) {
                          final ep = _chapters[i];
                          return CheckboxListTile(
                            value: selected.contains(i),
                            onChanged: (bool? v) => setSheetState(() {
                              if (v == true) {
                                selected.add(i);
                              } else {
                                selected.remove(i);
                              }
                            }),
                            title: Text(ep.title),
                            subtitle: ep.lineName != null && ep.lineName!.isNotEmpty
                                ? Text(ep.lineName!)
                                : null,
                          );
                        },
                      ),
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(AppTokens.spaceMd),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(l10n.selectedCount(selected.length, total)),
                          ),
                          FilledButton(
                            onPressed: selected.isEmpty
                                ? null
                                : () => Navigator.of(ctx).pop(selected.toList()..sort()),
                            child: Text(l10n.addToDownload),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _share() {
    shareContent(context, widget.item.title, widget.item.detailUrl);
  }

  /// 统一搜索（需求7、8）：标签 / 作者 / 导演 / 主演 / 作品名 全部走同一个
  /// 全字段关键词搜索入口（[ModuleSourceSearchScreen] 的 searchField 传 null），
  /// 点击结果进入对应详情页。
  void _openUnifiedSearch(MediaItem item, String query, {String? field}) {
    final String q = query.trim();
    if (q.isEmpty) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final SourceType type = item.sourceType ?? SourceType.animeSource;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ModuleSourceSearchScreen(
          sourceType: type,
          title: l10n.search,
          initialQuery: q,
          searchField: field,
          onItemTap: (MediaItem tapped) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ContentDetailScreen(item: tapped),
            ),
          ),
        ),
      ),
    );
  }

  /// 构造元信息 chips：导演 / 演员 / 年份（影视无作者概念，状态改由 shell 徽标展示）。
  List<Widget> _buildInfoChips(MediaItem item, AppLocalizations l10n) {
    final chips = <Widget>[];
    for (final name in splitMultiValue(item.director)) {
      chips.add(ActionChip(
        label: Text(name),
        tooltip: l10n.searchByDirector,
        onPressed: () => _openUnifiedSearch(item, name, field: 'director'),
      ));
    }
    for (final name in splitMultiValue(item.actors)) {
      chips.add(ActionChip(
        label: Text(name),
        tooltip: l10n.searchByActor,
        onPressed: () => _openUnifiedSearch(item, name, field: 'actors'),
      ));
    }
    if (item.year != null && item.year!.isNotEmpty) {
      chips.add(Chip(label: Text(item.year!)));
    }
    return chips;
  }

  /// 构造题材标签 chips（点击走统一搜索）。
  List<Widget> _buildTags(MediaItem item, AppLocalizations l10n) {
    if (item.tags == null || item.tags!.isEmpty) return const <Widget>[];
    return item.tags!.map((tag) => ActionChip(
      label: Text(tag),
      tooltip: l10n.searchByTag,
      onPressed: () => _openUnifiedSearch(item, tag, field: 'tags'),
    )).toList();
  }

  /// 构建观看进度卡：总集数 / 已看 / 进度% + 进度条 + "上次观看" 提示。
  ///
  /// 数据源：
  /// - 已看 = `MediaWatchedManager` 已看集合长度。
  /// - 上次观看集标题优先用 `MediaPlaybackPositionManager.getLastEpisode`，
  ///   兜底用已看集合的最后一集。
  /// - 时间取自 [HistoryManager] 的 `viewedAt`。
  /// 剧集解析失败时的内联错误条（不覆盖整页，详情头部照常显示）。
  Widget _buildEpisodeError(AppLocalizations l10n, Object error) {
    final msg = error is SourceResolveException
        ? l10n.resolveFailed(error.message)
        : (error is HttpStatusException
            ? l10n.loadFailed
            : l10n.loadFailed);
    return Padding(
      padding: const EdgeInsets.only(
        left: AppTokens.spaceLg,
        right: AppTokens.spaceLg,
        top: AppTokens.spaceMd,
        bottom: AppTokens.spaceSm,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline,
              size: 18, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Text(
              msg,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: () => setState(_load),
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(
    BuildContext context,
    AppLocalizations l10n,
    int total,
    int read,
  ) {
    final itemId = widget.item.id;
    String? episodeTitle;
    if (_continueIndex >= 0 && _continueIndex < _chapters.length) {
      episodeTitle = _chapters[_continueIndex].title;
    } else if (read > 0) {
      final watched = context.read<MediaWatchedManager>().watchedList(itemId);
      if (watched.isNotEmpty && watched.last < _chapters.length) {
        episodeTitle = _chapters[watched.last].title;
      }
    }
    ProgressLastRead? lastRead;
    if (episodeTitle != null && episodeTitle.isNotEmpty) {
      DateTime? at;
      try {
        final h = context.read<HistoryManager>().findById(itemId,
            sourceType: widget.item.sourceType ?? SourceType.animeSource);
        if (h != null && h.viewedAt > 0) {
          at = DateTime.fromMillisecondsSinceEpoch(h.viewedAt);
        }
      } catch (_) {
        at = null;
      }
      if (at != null) {
        lastRead = ProgressLastRead(
          timeText: formatRelativeTime(l10n, at),
          chapterTitle: episodeTitle,
        );
      }
    }
    return ProgressCard(
      kind: ProgressKind.watching,
      total: total,
      read: read,
      lastRead: lastRead,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final item = _fetchedDetail;

    // 旧数据兜底：sourceId 缺失（历史/收藏入库时未持久化）→ 明确提示而非灰屏。
    if (item.sourceId == null || item.sourceId!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(item.title)),
        body: AppErrorState(
          message: l10n.contentExpired,
          onRetry: () => Navigator.of(context).pop(),
          retryLabel: l10n.back,
        ),
      );
    }

    final source = context.read<SourceRepository>().getById(item.sourceId ?? '');
    final isManga = source?.type == SourceType.mangaSource;
    final isNovel = source?.type == SourceType.novelSource;
    final isChapterBased = isManga || isNovel;

    // 渲染后抽取请求 → 显示「抓取本页渲染内容」引导（webview-html 源）。
    if (_htmlCaptureRequest != null) {
      return Scaffold(
        appBar: AppBar(title: Text(item.title)),
        body: AppErrorState(
          message: l10n.captureHint,
          onRetry: () async {
            final outcome = await navigateToHtmlCapture(
              context,
              request: _htmlCaptureRequest!,
            );
            if (outcome?.hasRenderedHtml == true) {
              await _retryAfterHtmlCapture(outcome!.renderedHtml!);
            }
          },
          retryLabel: l10n.captureFromPage,
        ),
      );
    }

    // 验证异常 → 显示验证引导。
    if (_verificationError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(item.title)),
        body: AppErrorState(
          message: l10n.errorVerification,
          onRetry: () async {
            final shouldRetry = await navigateToVerification(
              context,
              url: _verificationError!.url,
              exception: _verificationError,
            );
            if (shouldRetry) _retryAfterVerification();
          },
          retryLabel: l10n.openInBrowser,
        ),
      );
    }

    final favorites = context.watch<FavoritesManager>();
    final downloadMgr = context.watch<DownloadManager>();
    final watchedMgr = context.watch<MediaWatchedManager>();
    final type = item.sourceType ?? SourceType.animeSource;
    final isFav = favorites.isFavorite(item.id, type);
    final isDl = downloadMgr.isItemDownloaded(item.id);

    return Scaffold(
      body: FutureBuilder<List<Episode>>(
        future: _episodesFuture,
        builder: (BuildContext context, AsyncSnapshot<List<Episode>> snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final episodes = snap.data ?? <Episode>[];
          // 剧集解析失败时不再整页替换为错误页（否则会把已加载的封面/标题
          // 一并覆盖，表现为「闪一下正常→变错误页」）。改为头部照常显示，
          // 仅剧集区上方给出内联错误 + 重试，保证详情页始终可用。
          final episodeError = snap.hasError ? snap.error : null;
          _allEpisodes = episodes;
          final hasContinue = _continueIndex >= 0 && _continueIndex < episodes.length;
          final readCount = watchedMgr.watchedCount(item.id);
          return ContentDetailShell(
            coverUrl: item.coverUrl,
            source: source,
            title: item.title,
            description: item.description ?? l10n.noDescription,
            updatedAt: item.updatedAt ?? latestEpisodeUpdatedAt(episodes),
            statusText: item.status,
            sourceName: source?.name,
            detailUrl: _fetchedDetail.detailUrl ?? widget.item.detailUrl,
            infoChips: _buildInfoChips(item, l10n),
            tags: _buildTags(item, l10n),
            onCoverTap: () => _showCoverViewer(context),
            appBarActions: <Widget>[
              IconButton(
                icon: Icon(isFav ? Icons.bookmark : Icons.bookmark_border),
                tooltip: l10n.subTabFavorite,
                onPressed: _toggleFavorite,
              ),
              IconButton(
                icon: Icon(isDl
                    ? Icons.download_done
                    : Icons.download_outlined),
                tooltip: l10n.download,
                onPressed: isDl ? null : _startDownload,
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: l10n.share,
                onPressed: _share,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l10n.refreshMetadata,
                onPressed: _refreshMetadata,
              ),
              if (isFav)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.removeFromFavorites,
                  onPressed: _removeFromFavorites,
                ),
            ],
            onRefresh: _onRefresh,
            fallbackIcon: isChapterBased
                ? (isManga ? Icons.menu_book : Icons.auto_stories_outlined)
                : Icons.movie_outlined,
            progressSection: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (episodeError != null)
                  _buildEpisodeError(l10n, episodeError),
                _buildProgressCard(
                  context,
                  l10n,
                  episodes.length,
                  readCount,
                ),
              ],
            ),
            actions: <Widget>[
              // 续看 / 从头开始。
              if (hasContinue)
                FilledButton.icon(
                  onPressed: () => _openContent(episodes[_continueIndex], _continueIndex),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.continueReading),
                )
              else
                FilledButton.icon(
                  onPressed: episodes.isEmpty
                      ? null
                      : () => _openContent(episodes.first, 0),
                  icon: Icon(isChapterBased ? Icons.auto_stories_outlined : Icons.play_arrow),
                  label: Text(isChapterBased ? l10n.readChapter : l10n.play),
                ),
              // 系列入口：仅当 detail 路由返回了季列表时显示。
              if (_fetchedDetail.seasons != null &&
                  _fetchedDetail.seasons!.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SeriesDetailScreen(series: _fetchedDetail),
                    ),
                  ),
                  icon: const Icon(Icons.tv),
                  label: Text(l10n.seriesTitle),
                ),
            ],
            chaptersList: isChapterBased
                ? ChapterListSection(
                    chapters: episodes,
                    onTapChapter: _openContent,
                    onDownloadChapter: _downloadSingleEpisode,
                    onToggleRead: isManga ? null : _toggleWatched,
                    isChapterRead: isManga
                        ? null
                        : (i) => watchedMgr.isWatched(item.id, i),
                    unitWord: isManga
                        ? l10n.unitWordComicChapter
                        : l10n.unitWordChapter,
                  )
                : ChapterListSection(
                    chapters: episodes,
                    groupByLine: true,
                    onTapChapter: _openContent,
                    onDownloadChapter: _downloadSingleEpisode,
                    onToggleRead: _toggleWatched,
                    isChapterRead: (i) => watchedMgr.isWatched(item.id, i),
                    unitWord: l10n.unitWordEpisode,
                    isMultiSource: true,
                    enableGridMode: true,
                    contentId: item.id,
                    getPosition: (i) => context
                        .read<MediaPlaybackPositionManager>()
                        .getPosition(item.id, i),
                  ),
            recommendations: _buildRecommendations(context, l10n),
          );
        },
      ),
    );
  }

  Widget _buildRecommendations(BuildContext context, AppLocalizations l10n) {
    final future = _recommendationsFuture;
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<List<MediaItem>>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<List<MediaItem>> snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l10n.recommendations,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppTokens.spaceMd),
                const CircularProgressIndicator(),
              ],
            ),
          );
        }
        final items = snap.data;
        if (items == null || items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l10n.recommendations,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppTokens.spaceMd),
                Text(
                  l10n.noRecommendation,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          );
        }
        const double cardW = 100;
        const double cardH = cardW / AppTokens.coverAspectRatio + 48;
        return Padding(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.recommendations,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppTokens.spaceMd),
              SizedBox(
                height: cardH,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (BuildContext _, int __) =>
                      const SizedBox(width: AppTokens.spaceMd),
                  itemBuilder: (BuildContext _, int i) {
                    final MediaItem m = items[i];
                    return ContentCard(
                      coverUrl: m.coverUrl,
                      title: m.title,
                      subtitle: m.author,
                      width: cardW,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ContentDetailScreen(item: m),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 全屏封面大图查看器：点击关闭。
class _CoverViewerScreen extends StatelessWidget {
  final String coverUrl;
  final String title;
  final PluginConfig? source;

  const _CoverViewerScreen(
      {required this.coverUrl, required this.title, this.source});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l10n.coverViewer),
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            child: AppCoverImage(
              coverUrl: coverUrl,
              source: source,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
