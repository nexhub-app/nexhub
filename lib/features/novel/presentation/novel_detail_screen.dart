/// 小说详情页（M16.4 对账）。
///
/// 独立于通用 [ContentDetailScreen]，专小说场景：
/// - 章节获取走 `fetchNovelChapters`
/// - 章节点击进入 [NovelReaderScreen]
/// - 续读索引来自 [NovelProgressManager]
/// - 章节行三按钮：下载单章 / 书签（[NovelBookmarkManager]）/ 已读（[MediaWatchedManager]）
/// - AppBar：收藏 / 下载 / 分享 / 刷新元数据 / 删除
/// - 操作行：续读或开始阅读 / 应用内浏览 / 外部浏览器
/// - 封面点击查看大图、更新时间、题材标签、作者/状态/年份 chips、相关推荐
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/download/download_manager.dart';
import '../../../core/favorites/favorites_manager.dart';
import '../../../core/history/history_manager.dart';
import '../../../core/history/media_watched_manager.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/novel/novel_progress_manager.dart';
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
import '../../../core/widgets/progress_card.dart';
import '../../verification/presentation/webview_verification_screen.dart';
import 'novel_bookmark_manager.dart';
import 'novel_reader_screen.dart';

/// 小说详情页。
class NovelDetailScreen extends StatefulWidget {
  final MediaItem item;

  const NovelDetailScreen({super.key, required this.item});

  @override
  State<NovelDetailScreen> createState() => _NovelDetailScreenState();
}

class _NovelDetailScreenState extends State<NovelDetailScreen> {
  late Future<List<Episode>> _chaptersFuture;
  List<Episode> _chapters = const <Episode>[];
  /// 章节是否仍在后台渐进加载（首屏已可渲染前若干章，剩余目录继续抓取）。
  bool _chaptersLoading = false;
  Future<List<MediaItem>>? _recommendationsFuture;
  VerificationRequiredException? _verificationError;
  /// 渲染后抽取请求（webview-html 模式）：非 null 时显示「抓取本页渲染内容」引导。
  WebViewHtmlRequest? _htmlCaptureRequest;
  /// 渲染后回灌的整页 HTML（重试抓取时复用源选择器解析）。
  String? _renderedHtml;
  late MediaItem _fetchedDetail;

  /// 续读章节索引（-1 表示无进度记录）。
  int _continueIndex = -1;

  /// 当前小说的书签章节索引集合（本地缓存，供章节行同步查询）。
  final Set<int> _bookmarkedIndices = <int>{};

  final NovelProgressManager _progress = NovelProgressManager();
  final NovelBookmarkManager _bookmarks = NovelBookmarkManager();

  @override
  void initState() {
    super.initState();
    _fetchedDetail = widget.item;
    _load();
    _recordHistory();
    _loadContinueIndex();
    _loadBookmarks();
  }

  @override
  void dispose() {
    _chapterThrottleTimer?.cancel();
    _chapterThrottleTimer = null;
    super.dispose();
  }

  void _recordHistory() {
    try {
      context.read<HistoryManager>().addHistory(
            widget.item,
            sourceType: SourceType.novelSource,
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
            ..addAll(list.map((NovelBookmark b) => b.chapterIndex));
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

    // 渐进加载状态（独立于 FutureBuilder，仅做叠加层）。
    _chaptersLoading = true;
    _chapters = const <Episode>[];

    // 直接用 fetchNovelChapters 的返回值作为 _chaptersFuture（与旧版一致），
    // 保证 FutureBuilder 的 waiting/hasError/data 行为完全不变（无回归风险）。
    // onProgress 回调仅通过独立 _chapters 状态提供"首屏快显"叠加效果。
    _chaptersFuture = service.fetchNovelChapters(
      source,
      id,
      renderedHtml: _renderedHtml,
      // 渐进批次：按章节 id 去重合并到 _chapters，节流后触发 setState 避免卡顿。
      onProgress: _throttledChapterBatch,
    );
    // 终态校正：Future 完成后用最终列表覆盖渐进中间态（确保数据一致性）。
    _chaptersFuture.then((list) {
      if (!mounted) return;
      setState(() {
        _chapters = list;
        _chaptersLoading = false;
      });
    }).catchError((Object error) {
      if (!mounted) return;
      setState(() => _chaptersLoading = false);
      if (error is WebViewHtmlRequest) {
        setState(() => _htmlCaptureRequest = error);
      } else if (error is VerificationRequiredException) {
        setState(() => _verificationError = error);
      }
      // 注：普通错误不在此处理——由 FutureBuilder 的 hasError 分支统一展示
      // （与旧版行为一致），避免重复错误 UI 或掩盖验证/HTML 捕获类错误。
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

  /// 节流渐进批次回调：超长书目录（如诡秘之主 1416 章 / 71 页）每页都触发一次
  /// onProgress，若每次都 setState 会导致 UI 卡顿（71 次/秒级重建）。
  /// 本方法将批量合并到 300ms 窗口内最多触发一次 setState，兼顾"首屏快显"
  /// 与"流畅不卡"。[Timer?] 在 dispose 时取消，避免内存泄漏。
  Timer? _chapterThrottleTimer;
  List<Episode> _pendingChapterBatch = const <Episode>[];

  void _throttledChapterBatch(List<Episode> batch) {
    _pendingChapterBatch = <Episode>[
      ..._pendingChapterBatch,
      ...batch,
    ];
    // 已有待执行的节流定时器 → 合并等待；否则启动新的 300ms 定时器。
    if (_chapterThrottleTimer != null) return;
    _chapterThrottleTimer = Timer(const Duration(milliseconds: 300), () {
      _chapterThrottleTimer = null;
      if (!mounted || _pendingChapterBatch.isEmpty) return;
      final incoming = _pendingChapterBatch;
      _pendingChapterBatch = const <Episode>[];
      setState(() {
        final map = <String, Episode>{for (final e in _chapters) e.id: e};
        for (final e in incoming) {
          map[e.id] = e;
        }
        _chapters = map.values.toList();
      });
    });
  }

  /// 渲染后抽取完成后回填 HTML 并重试抓取（webview-html 源）。
  Future<void> _retryAfterHtmlCapture(String html) async {
    if (!mounted) return;
    setState(() {
      _htmlCaptureRequest = null;
      _verificationError = null;
      _renderedHtml = html;
    });
    _load();
  }

  /// 打开小说阅读器。
  void _openChapter(Episode ep, int index) {
    final sid = widget.item.sourceId;
    if (sid == null) return;
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
  }

  Future<void> _toggleFavorite() async {
    final l10n = AppLocalizations.of(context);
    final fav = context.read<FavoritesManager>();
    final wasFavorite = fav.isFavorite(widget.item.id, SourceType.novelSource);
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
    await fav.removeFavorite(widget.item.id, SourceType.novelSource);
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
        final bookmark = NovelBookmark(
          novelId: widget.item.id,
          chapterIndex: index,
          chapterId: ep.id,
          chapterTitle: ep.title,
          page: 0,
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

  /// 统一搜索（需求7、8）：作者 / 标签 / 作品名 全部走同一个全字段关键词
  /// 搜索入口（searchField 传 null），点击结果进入小说详情页。
  void _openUnifiedSearch(String query, {String? field}) {
    final String q = query.trim();
    if (q.isEmpty) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ModuleSourceSearchScreen(
          sourceType: SourceType.novelSource,
          title: l10n.search,
          initialQuery: q,
          searchField: field,
          onItemTap: (MediaItem tapped) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => NovelDetailScreen(item: tapped),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildInfoChips(MediaItem item, AppLocalizations l10n,
      {int episodeCount = 0}) {
    final chips = <Widget>[];
    for (final name in splitMultiValue(item.author)) {
      chips.add(ActionChip(
        label: Text(name),
        tooltip: l10n.searchByAuthor,
        onPressed: () => _openUnifiedSearch(name, field: 'author'),
      ));
    }
    if (item.year != null && item.year!.isNotEmpty) {
      chips.add(Chip(label: Text(item.year!)));
    }
    if (item.wordCount != null && item.wordCount!.isNotEmpty) {
      chips.add(Chip(label: Text('${l10n.wordCount} ${item.wordCount}')));
    }
    if (episodeCount > 0) {
      chips.add(Chip(label: Text(l10n.updatedTo(episodeCount))));
    }
    return chips;
  }

  List<Widget> _buildTags(MediaItem item, AppLocalizations l10n) {
    if (item.tags == null || item.tags!.isEmpty) return const <Widget>[];
    return item.tags!.map((tag) => ActionChip(
      label: Text(tag),
      tooltip: l10n.searchByTag,
      onPressed: () => _openUnifiedSearch(tag, field: 'tags'),
    )).toList();
  }

  /// 构建阅读进度卡：总章节 / 已读 / 进度% + 进度条 + "上次阅读" 提示。
  ///
  /// 优先级：
  /// 1. 进度条数据来自 [MediaWatchedManager]（按章节标记的已读集合）。
  /// 2. "上次阅读" 时间取自 [HistoryManager] 的 `viewedAt`（之前进入详情页/阅读的最近时间）。
  /// 3. "上次阅读" 章节标题优先用进度管理器记录的章节索引；都没有则隐藏整行。
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
      // 没续读索引但有已读 → 取已读集合最后一章的标题。
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
            sourceType: SourceType.novelSource);
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
    final isFav = favorites.isFavorite(item.id, SourceType.novelSource);
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

    // ── 章节区域：FutureBuilder（等待/错误态）+ 渐进叠加（首屏快显） ──
    // FutureBuilder 的 waiting/hasError/data 行为与旧版完全一致（无回归风险）。
    // 渐进更新通过独立 _chapters 状态叠加：当 _chapters 非空时优先使用（已抓到的
    // 前若干章），否则回退到 snap.data（Future 最终结果）。_chaptersLoading 控制
    // ChapterListSection 底部"加载中…"提示。
    return Scaffold(
      body: FutureBuilder<List<Episode>>(
        future: _chaptersFuture,
        builder: (BuildContext context, AsyncSnapshot<List<Episode>> snap) {
          // ── 等待中：显示全局加载指示（与旧版一致）──
          if (snap.connectionState == ConnectionState.waiting) {
            // 已有渐进数据 → 用渐进数据渲染（首屏快显），不再白屏等全部目录
            if (_chapters.isNotEmpty) {
              return _buildDetailBody(
                context, l10n, source, item,
                episodes: _chapters,
                watchedMgr: watchedMgr,
                isFav: isFav, isDl: isDl,
              );
            }
            return const Center(child: CircularProgressIndicator());
          }

          // ── 错误：已通过 onProgress 渐进加载到部分章节时保留并展示，
          //   仅在完全无数据时才显示全屏错误态（避免长目录中途失败时
          //   丢失已抓到的几百章）。
          //   注意：_chaptersLoading==false 表示 Future 已终态（.then/.catchError 已执行），
          //   此时 _chapters 就是最终结果，不再显示"部分加载"警告条。──
          if (snap.hasError) {
            // 仍在加载中且有渐进数据 → 展示部分章节 + 顶部警告条
            if (_chapters.isNotEmpty && _chaptersLoading) {
              return _buildDetailBody(
                context, l10n, source, item,
                episodes: _chapters,
                watchedMgr: watchedMgr,
                isFav: isFav, isDl: isDl,
                partialError: snap.error,
              );
            }
            // 加载完成但有数据 → 直接展示最终结果（不显示警告）
            // 完全无数据 → 全屏错误
            if (_chapters.isNotEmpty) {
              return _buildDetailBody(
                context, l10n, source, item,
                episodes: _chapters,
                watchedMgr: watchedMgr,
                isFav: isFav, isDl: isDl,
              );
            }
            // 完全无数据 → 全屏错误
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

          // ── 数据就绪：优先用渐进 _chapters（可能比 snap.data 更新），否则用终态 ──
          final episodes = (_chapters.isNotEmpty && _chaptersLoading)
              ? _chapters
              : (snap.data ?? <Episode>[]);
          // Future 完成后校正：确保最终状态一致
          if (!_chaptersLoading && snap.data != null) {
            // snap.data 是权威终态
          }
          return _buildDetailBody(
            context, l10n, source, item,
            episodes: episodes,
            watchedMgr: watchedMgr,
            isFav: isFav, isDl: isDl,
          );
        },
      ),
    );
  }

  /// 构建详情页主体（封面/简介/操作/章节列表/推荐），从 build() 中抽离以避免
  /// FutureBuilder builder 嵌套过深。参数 [episodes] 为当前应渲染的章节列表
  /// （渐进中间态或最终完整列表）。[partialError] 非空时表示目录加载中途失败，
  /// 已展示部分章节但未完整，需在顶部显示警告条。
  Widget _buildDetailBody(
    BuildContext context,
    AppLocalizations l10n,
    PluginConfig? source,
    MediaItem item, {
    required List<Episode> episodes,
    required MediaWatchedManager watchedMgr,
    required bool isFav,
    required bool isDl,
    Object? partialError,
  }) {
    final hasContinue = _continueIndex >= 0 && _continueIndex < episodes.length;
    final readCount = watchedMgr.watchedCount(item.id);

    // 渐进加载中途失败的警告条：告知用户当前仅显示部分章节。
    final warningBanner = partialError != null
        ? Material(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12,
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.chapterLoadPartial(episodes.length),
                      style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(_load),
                    child: Text(l10n.retry, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          )
        : null;

    return Scaffold(
      body: Column(
        children: [
          if (warningBanner != null) warningBanner,
          Expanded(
            child: ContentDetailShell(
        coverUrl: item.coverUrl,
        source: source,
        title: item.title,
        description: item.description ?? l10n.noDescription,
        updatedAt: item.updatedAt ?? latestEpisodeUpdatedAt(episodes),
        statusText: item.status,
        sourceName: source?.name,
        detailUrl: _fetchedDetail.detailUrl ?? widget.item.detailUrl,
        infoChips: _buildInfoChips(item, l10n,
            episodeCount: episodes.length),
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
        ],
        onRefresh: _onRefresh,
        fallbackIcon: Icons.auto_stories_outlined,
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
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(l10n.continueReading),
            )
          else
            FilledButton.icon(
              onPressed: episodes.isEmpty
                  ? null
                  : () => _openChapter(episodes.first, 0),
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(l10n.readChapter),
            ),
        ],
        chaptersList: ChapterListSection(
          chapters: episodes,
          loadingMore: _chaptersLoading,
          onTapChapter: _openChapter,
          onDownloadChapter: _downloadSingleChapter,
          onToggleBookmark: _toggleBookmark,
          isChapterBookmarked: (i) => _bookmarkedIndices.contains(i),
          onToggleRead: _toggleRead,
          isChapterRead: (i) => watchedMgr.isWatched(item.id, i),
          unitWord: l10n.unitWordChapter,
          contentId: item.id,
        ),
        recommendations: _buildRecommendations(context, l10n),
      ),
          ),
        ],
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
                          builder: (_) => NovelDetailScreen(item: m),
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
