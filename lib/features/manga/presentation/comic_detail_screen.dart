/// 漫画详情页（M16.3 对账）。
///
/// 独立于通用 [ContentDetailScreen]，专漫画场景：
/// - 章节获取走 `fetchChapters`
/// - 章节点击进入 [ComicReaderScreen]
/// - 续读索引来自 [ComicProgressManager]
/// - 章节行三按钮：下载单章 / 书签（[ComicBookmarkManager]）/ 已读（[MediaWatchedManager]）
/// - AppBar：收藏 / 下载 / 分享 / 刷新元数据 / 删除
/// - 操作行：续读或开始阅读 / 应用内浏览 / 外部浏览器
/// - 封面点击查看大图、更新时间、题材标签、作者/状态/年份 chips、相关推荐
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import '../../../core/settings/general_settings.dart';
import 'package:provider/provider.dart';

import '../../../core/comic/comic_bookmark_manager.dart';
import '../../../core/comic/comic_progress_manager.dart';
import '../../../core/download/download_manager.dart';
import '../../../core/favorites/favorites_manager.dart';
import '../../../core/history/history_manager.dart';
import '../../../core/history/media_watched_manager.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/scraper/verification_detector.dart';
import '../../../core/resolver/webview_resolver.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_cover_image.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/chapter_list_section.dart';
import '../../../core/widgets/content_card.dart';
import '../../../core/widgets/content_detail_shell.dart';
import '../../../core/widgets/detail_action_utils.dart';
import '../../../core/widgets/module_source_search_screen.dart';
import '../../../core/widgets/source_url_browse_screen.dart';
import '../../../core/widgets/progress_card.dart';
import '../../downloads/presentation/download_list_screen.dart';
import '../../verification/presentation/webview_verification_screen.dart';
import 'comic_reader_screen.dart';

/// 漫画详情页。
class ComicDetailScreen extends StatefulWidget {
  final MediaItem item;

  const ComicDetailScreen({super.key, required this.item});

  @override
  State<ComicDetailScreen> createState() => _ComicDetailScreenState();
}

class _ComicDetailScreenState extends State<ComicDetailScreen> {
  late Future<List<Episode>> _chaptersFuture;
  List<Episode> _chapters = const <Episode>[];
  Future<List<MediaItem>>? _recommendationsFuture;
  VerificationRequiredException? _verificationError;
  /// 渲染后抽取请求（webview-html 模式）：非 null 时显示「抓取本页渲染内容」引导。
  WebViewHtmlRequest? _htmlCaptureRequest;
  /// 渲染后回灌的整页 HTML（重试抓取时复用源选择器解析）。
  String? _renderedHtml;
  late MediaItem _fetchedDetail;

  /// 续读章节索引（-1 表示无进度记录）。
  int _continueIndex = -1;

  /// 当前漫画的书签章节索引集合（本地缓存，供章节行同步查询）。
  final Set<int> _bookmarkedIndices = <int>{};

  final ComicProgressManager _progress = ComicProgressManager();
  final ComicBookmarkManager _bookmarks = ComicBookmarkManager();

  @override
  void initState() {
    super.initState();
    _fetchedDetail = widget.item;
    _load();
    _recordHistory();
    _loadContinueIndex();
    _loadBookmarks();
  }

  void _recordHistory() {
    try {
      context.read<HistoryManager>().addHistory(
            widget.item,
            sourceType: SourceType.mangaSource,
          );
    } on Object {
      // HistoryManager 不可用时不影响页面。
    }
  }

  Future<void> _loadContinueIndex() async {
    try {
      final p = await _progress.get(widget.item.id);
      if (mounted && p != null) {
        setState(() => _continueIndex = p.chapterIndex);
      }
    } on Object {
      // 进度读取失败不影响页面。
    }
  }

  Future<void> _loadBookmarks() async {
    try {
      final list = await _bookmarks.listFor(widget.item.id);
      if (mounted) {
        setState(() {
          _bookmarkedIndices
            ..clear()
            ..addAll(list.map((ComicBookmark b) => b.chapterIndex));
        });
      }
    } on Object {
      // 书签读取失败不影响页面。
    }
  }

  void _load() {
    final repo = context.read<SourceRepository>();
    final service = context.read<MediaApiService>();
    final sid = widget.item.sourceId;
    final id = widget.item.id;
    if (sid == null) {
      _chaptersFuture = Future<List<Episode>>.error(
        Exception('item missing source id'),
      );
      return;
    }
    final source = repo.getById(sid);
    if (source == null) {
      _chaptersFuture = Future<List<Episode>>.error(
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
    final future = service.fetchChapters(source, id, renderedHtml: _renderedHtml);
    _chaptersFuture = future;
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
        if (mounted) setState(() => _fetchedDetail = detail);
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

  /// 渲染后抽取完成后回填 HTML 并重试抓取（baozimh 等 webview-html 源）。
  Future<void> _retryAfterHtmlCapture(String html) async {
    if (!mounted) return;
    setState(() {
      _htmlCaptureRequest = null;
      _verificationError = null;
      _renderedHtml = html;
    });
    _load();
  }

  /// 打开漫画阅读器。
  void _openChapter(Episode ep, int index) {
    final sid = widget.item.sourceId;
    if (sid == null) return;
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
  }

  Future<void> _toggleFavorite() async {
    final l10n = AppLocalizations.of(context);
    final fav = context.read<FavoritesManager>();
    final wasFavorite = fav.isFavorite(widget.item.id, SourceType.mangaSource);
    await fav.toggleFavorite(widget.item);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(wasFavorite ? l10n.favoriteRemoved : l10n.favoriteAdded),
        ),
      );
    }
  }

  Future<void> _removeFromFavorites() async {
    final l10n = AppLocalizations.of(context);
    final fav = context.read<FavoritesManager>();
    await fav.removeFavorite(widget.item.id, SourceType.mangaSource);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.removeFromFavorites)),
      );
      Navigator.of(context).pop();
    }
  }

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
      await _chaptersFuture;
    } catch (_) {
      // 错误状态由 FutureBuilder 展示
    }
  }

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
    final selected = await _showChapterSelectionSheet();
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

  Future<void> _downloadSingleChapter(Episode ep, int index) async {
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

  /// 切换章节书签。
  Future<void> _toggleBookmark(Episode ep, int index) async {
    try {
      if (_bookmarkedIndices.contains(index)) {
        // 删除该章节的全部书签（一条章节可能有多条书签，统一清除）。
        final list = await _bookmarks.listFor(widget.item.id);
        for (final b in list) {
          if (b.chapterIndex == index) {
            await _bookmarks.remove(b.key);
          }
        }
        if (mounted) {
          setState(() => _bookmarkedIndices.remove(index));
        }
      } else {
        final bookmark = ComicBookmark(
          comicId: widget.item.id,
          chapterIndex: index,
          chapterId: ep.id,
          chapterTitle: ep.title,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
        await _bookmarks.add(bookmark);
        if (mounted) {
          setState(() => _bookmarkedIndices.add(index));
        }
      }
    } on Object {
      // 书签操作失败静默忽略。
    }
  }

  /// 切换章节已读状态。
  Future<void> _toggleRead(Episode ep, int index) async {
    try {
      await context.read<MediaWatchedManager>().toggleWatched(
            widget.item.id,
            index,
          );
    } on Object {
      // 已读切换失败静默忽略。
    }
  }

  Future<List<int>?> _showChapterSelectionSheet() {
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

  /// 处理三点菜单的选择。
  void _handlePopupAction(String action, AppLocalizations l10n) {
    switch (action) {
      case 'share':
        _share();
      case 'setAsShelfCover':
        _setAsShelfCover(l10n);
      case 'openDownloadManager':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const DownloadListScreen(),
          ),
        );
      case 'details':
        _showDetailsSheet(l10n);
    }
  }

  /// 将当前漫画封面设为书架封面（更新收藏条目的 coverUrl）。
  Future<void> _setAsShelfCover(AppLocalizations l10n) async {
    final item = _fetchedDetail;
    final type = item.sourceType ?? SourceType.mangaSource;
    final ok = await context.read<FavoritesManager>().updateCover(
          item.id,
          type,
          item.coverUrl,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? l10n.coverUpdated : l10n.coverUpdateFailed),
      ),
    );
  }

  /// 显示漫画详情信息面板。
  void _showDetailsSheet(AppLocalizations l10n) {
    final item = _fetchedDetail;
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(item.title, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: AppTokens.spaceSm),
              if (item.author != null && item.author!.isNotEmpty)
                Text('${l10n.authorLabel}: ${item.author}'),
              if (item.status != null && item.status!.isNotEmpty)
                Text('${l10n.statusLabel}: ${item.status}'),
              if (item.updatedAt != null)
                AnimatedBuilder(
                  animation: GeneralSettingsStore.instance,
                  builder: (context, _) => Text(l10n.updatedAt(
                      GeneralSettingsStore.instance.settings.dateFormat
                          .format(item.updatedAt!, withTime: true))),
                ),
              if (item.description != null && item.description!.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppTokens.spaceSm),
                Text(item.description!),
              ],
              const SizedBox(height: AppTokens.spaceMd),
            ],
          ),
        ),
      ),
    );
  }

  /// 统一搜索（需求7、8）：作者 / 标签 / 作品名 全部走同一个全字段关键词
  /// 搜索入口（searchField 传 null），点击结果进入漫画详情页。
  /// 作为「没有真实链接」时的兜底：有详情页抓到的真实落地页链接时，
  /// 优先走 [_openSourceUrl]（打开该页为浏览列表，见下）。
  void _openUnifiedSearch(
    String query, {
    String? field,
    String? extractedUrl,
  }) {
    final String q = query.trim();
    final AppLocalizations l10n = AppLocalizations.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ModuleSourceSearchScreen(
          sourceType: SourceType.mangaSource,
          title: l10n.search,
          initialQuery: q,
          searchField: field,
          extractedUrl: extractedUrl,
          onItemTap: (MediaItem tapped) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ComicDetailScreen(item: tapped),
            ),
          ),
        ),
      ),
    );
  }

  /// 打开「按真实网址浏览」列表页：点作者/标签时，用详情页抓到的真实落地页
  /// 链接（如 /manga-author/pi-ka-pi）直接打开该页，当作站点上的作者/标签页
  /// 浏览（而非关键词搜索）。绕开站点拼音代号限制，源侧零改动。
  void _openSourceUrl(String seedUrl, String title) {
    final source = context.read<SourceRepository>().getById(widget.item.sourceId ?? '');
    if (source == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SourceUrlBrowseScreen(
          source: source,
          title: title,
          seedUrl: seedUrl,
          onItemTap: (MediaItem tapped) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ComicDetailScreen(item: tapped),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildInfoChips(MediaItem item, AppLocalizations l10n) {
    final chips = <Widget>[];
    final authors = splitMultiValue(item.author);
    final authorUrls = item.authorUrl != null
        ? item.authorUrl!.split(',')
        : const <String>[];
    for (var i = 0; i < authors.length; i++) {
      final url = i < authorUrls.length ? authorUrls[i].trim() : '';
      chips.add(ActionChip(
        label: Text(authors[i]),
        tooltip: l10n.searchByAuthor,
        // 有真实作者链接 → 打开该作者页为浏览列表；没有 → 退回按作者名关键词搜索。
        onPressed: () => url.isNotEmpty
            ? _openSourceUrl(url, '${l10n.authorColon}${authors[i]}')
            : _openUnifiedSearch(authors[i], field: 'author'),
      ));
    }
    if (item.year != null && item.year!.isNotEmpty) {
      chips.add(Chip(label: Text(item.year!)));
    }
    return chips;
  }

  List<Widget> _buildTags(MediaItem item, AppLocalizations l10n) {
    if (item.tags == null || item.tags!.isEmpty) return const <Widget>[];
    final tagUrls = item.tagUrls ?? const <String>[];
    return <Widget>[
      for (var i = 0; i < item.tags!.length; i++)
        ActionChip(
          label: Text(item.tags![i]),
          tooltip: l10n.searchByTag,
          // 有真实标签链接 → 打开该标签页为浏览列表；没有 → 退回按标签名关键词搜索。
          onPressed: () => (i < tagUrls.length && tagUrls[i].trim().isNotEmpty)
              ? _openSourceUrl(tagUrls[i].trim(), '${l10n.tagColon}${item.tags![i]}')
              : _openUnifiedSearch(item.tags![i], field: 'tags'),
        ),
    ];
  }

  /// 构建阅读进度卡：总章节 / 已读 / 进度% + 进度条 + "上次阅读" 提示。
  ///
  /// 数据源同小说详情页：进度 = `MediaWatchedManager` 已读数；上次阅读 =
  /// `ComicProgressManager` 续读索引对应的章节标题 + `HistoryManager` 时间。
  Widget _buildProgressCard(
    BuildContext context,
    AppLocalizations l10n,
    int total,
    int read,
  ) {
    final itemId = widget.item.id;
    String? chapterTitle;
    if (_continueIndex >= 0 && _continueIndex < _chapters.length) {
      chapterTitle = _chapters[_continueIndex].title;
    } else if (read > 0) {
      final watched = context.read<MediaWatchedManager>().watchedList(itemId);
      if (watched.isNotEmpty && watched.last < _chapters.length) {
        chapterTitle = _chapters[watched.last].title;
      }
    }
    ProgressLastRead? lastRead;
    if (chapterTitle != null && chapterTitle.isNotEmpty) {
      DateTime? at;
      try {
        final h = context.read<HistoryManager>().findById(itemId,
            sourceType: SourceType.mangaSource);
        if (h != null && h.viewedAt > 0) {
          at = DateTime.fromMillisecondsSinceEpoch(h.viewedAt);
        }
      } catch (_) {
        at = null;
      }
      if (at != null) {
        lastRead = ProgressLastRead(
          timeText: formatRelativeTime(l10n, at),
          chapterTitle: chapterTitle,
        );
      }
    }
    return ProgressCard(
      kind: ProgressKind.reading,
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

    final source = context.read<SourceRepository>().getById(item.sourceId!);
    final favorites = context.watch<FavoritesManager>();
    final downloadMgr = context.watch<DownloadManager>();
    final watchedMgr = context.watch<MediaWatchedManager>();
    final isFav = favorites.isFavorite(item.id, SourceType.mangaSource);
    final isDl = downloadMgr.isItemDownloaded(item.id);

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

    return Scaffold(
      body: FutureBuilder<List<Episode>>(
        future: _chaptersFuture,
        builder: (BuildContext context, AsyncSnapshot<List<Episode>> snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final err = snap.error;
            final msg = err is SourceResolveException
                ? l10n.resolveFailed(err.message)
                : (source == null ? l10n.sourceNotFound : l10n.loadFailed);
            return AppErrorState(
              message: msg,
              onRetry: () => setState(_load),
              retryLabel: l10n.retry,
            );
          }
          final episodes = snap.data ?? <Episode>[];
          final hasContinue =
              _continueIndex >= 0 && _continueIndex < episodes.length;
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
                icon: Icon(isDl ? Icons.download_done : Icons.download_outlined),
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
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: l10n.moreActions,
                onSelected: (String value) => _handlePopupAction(value, l10n),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'share',
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.share_outlined),
                        const SizedBox(width: AppTokens.spaceSm),
                        Text(l10n.share),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'setAsShelfCover',
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.image_outlined),
                        const SizedBox(width: AppTokens.spaceSm),
                        Text(l10n.setAsShelfCover),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'openDownloadManager',
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.folder_open_outlined),
                        const SizedBox(width: AppTokens.spaceSm),
                        Text(l10n.openDownloadManager),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'details',
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.info_outline),
                        const SizedBox(width: AppTokens.spaceSm),
                        Text(l10n.details),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            onRefresh: _onRefresh,
            fallbackIcon: Icons.menu_book,
            progressSection: _buildProgressCard(
              context,
              l10n,
              episodes.length,
              readCount,
            ),
            actions: <Widget>[
              if (hasContinue)
                FilledButton.icon(
                  onPressed: () => _openChapter(episodes[_continueIndex], _continueIndex),
                  icon: const Icon(Icons.auto_stories_outlined),
                  label: Text(l10n.continueReading),
                )
              else
                FilledButton.icon(
                  onPressed: episodes.isEmpty
                      ? null
                      : () => _openChapter(episodes.first, 0),
                  icon: const Icon(Icons.auto_stories_outlined),
                  label: Text(l10n.readChapter),
                ),
            ],
            chaptersList: ChapterListSection(
              chapters: episodes,
              onTapChapter: _openChapter,
              onDownloadChapter: _downloadSingleChapter,
              onToggleBookmark: _toggleBookmark,
              isChapterBookmarked: (i) => _bookmarkedIndices.contains(i),
              onToggleRead: _toggleRead,
              isChapterRead: (i) => watchedMgr.isWatched(item.id, i),
              unitWord: l10n.unitWordComicChapter,
              contentId: item.id,
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
                          builder: (_) => ComicDetailScreen(item: m),
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
