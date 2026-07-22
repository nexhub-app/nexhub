import 'dart:io';
import 'dart:async';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/comic/comic_progress_manager.dart';
import '../../../core/comic/models/reader_preferences.dart';
import '../../../core/settings/reader_default_settings.dart';
import '../../../core/favorites/favorites_manager.dart';
import '../../../core/local/local_content_manager.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../core/widgets/chapter_list_sheet.dart';
import '../../../core/widgets/detail_action_utils.dart';
import '../../../core/resolver/webview_resolver.dart';
import '../../../core/widgets/source_image.dart';
import '../../verification/presentation/webview_verification_screen.dart';
import 'reader_image_actions.dart';
import 'reader_image_filter.dart';
import 'reader_settings_sheet.dart';
import 'reader_tap_zones.dart';

/// 漫画阅读器（Phase 4）。
///
/// 支持 5 种阅读模式、点击区域布局、双击/滚轮缩放、进度自动保存、
/// 末页前预加载下一章。复用统一 Token 与 [ReaderPreferences]。
///
/// 本地模式（Task O4.B.1）：传入 [localImages] 或 [localCbzPath] 时进入本地模式，
/// 跳过在线源解析，直接渲染本地图片。本地模式下隐藏章节列表 / WebView / 分享等
/// 在线专属 UI，保留书签、进度、点击区域、图像滤镜。调用方需将 [comicId] 设为
/// `'local_${file.path.hashCode}'` 以隔离本地与在线进度。
class ComicReaderScreen extends StatefulWidget {
  final String comicId;
  final String title;
  final String sourceId;
  final List<Episode> chapters;
  final int initialChapterIndex;

  /// 本地模式：直接传入本地图片路径列表（跳过在线源解析）。
  final List<String>? localImages;

  /// 本地模式：传入本地 CBZ/ZIP 文件路径，阅读器内部解压取图。
  final String? localCbzPath;

  /// 是否用已保存的阅读进度恢复章节/页码。
  /// - true（默认）：从书架/历史「继续阅读」进入时恢复上次进度；
  /// - false：从详情页明确选择某话进入时，以 [initialChapterIndex] 为准。
  final bool restoreProgress;

  /// 详情页 URL（用于收藏时透传，避免历史/收藏详情灰屏）。
  final String? detailUrl;

  /// 封面 URL（用于收藏时透传，避免收藏书架缺封面）。
  final String? coverUrl;

  const ComicReaderScreen({
    super.key,
    required this.comicId,
    required this.title,
    required this.sourceId,
    required this.chapters,
    this.initialChapterIndex = 0,
    this.localImages,
    this.localCbzPath,
    this.restoreProgress = true,
    this.detailUrl,
    this.coverUrl,
  });

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen>
    with SingleTickerProviderStateMixin {
  final ReaderPreferencesStore _store = ReaderPreferencesStore();
  final ComicProgressManager _progress = ComicProgressManager();
  final TransformationController _zoomController = TransformationController();

  late ReaderPreferences _prefs;
  int _chapterIndex = 0;
  int _savedPage = 0;

  List<String> _images = const <String>[];
  bool _loading = true;
  String? _error;
  PluginConfig? _source;

  bool _loadingChapter = false;
  final Map<int, List<String>> _preload = <int, List<String>>{};
  /// 正在预加载的章节下标集合（防止同一章重复发起请求）。
  final Set<int> _preloading = <int>{};

  /// 渲染后抽取请求（webview-html 模式，如 manga_goda / manga_baozimh 的
  /// images 脚本路由）：非 null 时显示「抓取本页渲染内容」引导，抓取后回填
  /// 渲染 HTML 重试（修复 useWebview 脚本源「漫画图片解析不到内容」）。
  WebViewHtmlRequest? _htmlCaptureRequest;

  /// 按章节缓存渲染后 HTML：每个章节 images 路由 URL 不同，需分别抓取回灌。
  final Map<int, String> _renderedHtmlByChapter = <int, String>{};

  PageController? _pageController;
  ScrollController? _scrollController;
  int _currentPage = 0;
  bool _uiVisible = false;
  bool _isFav = false;

  /// 每页旋转的 quarterTurns（0/1/2/3），仅在用户主动旋转时记录。
  final Map<int, int> _pageRotations = <int, int>{};

  /// 内联设置面板可见性（右侧滑出）。
  bool _settingsPanelVisible = false;

  /// 进度滑条本地拖动值（拖动中暂存，松手后跳页并清空）。
  double? _progressDragValue;

  /// 翻页闪光动画控制器与覆盖层状态。
  late final AnimationController _flashController;
  double _flashOpacity = 0.0;
  Color _flashColor = Colors.black;

  /// 章节切换过渡标题卡状态。
  bool _transitionVisible = false;
  String _transitionTitle = '';
  Timer? _transitionTimer;

  MediaApiService get _service => context.read<MediaApiService>();
  SourceRepository get _repo => context.read<SourceRepository>();

  /// 是否为本地文件模式（Task O4.B.1）。
  bool get _isLocalMode =>
      widget.localImages != null || widget.localCbzPath != null;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _chapterIndex = widget.initialChapterIndex;
    _prefs = const ReaderPreferences();
    _init();
  }

  Future<void> _init() async {
    final defaults = await ReaderDefaultSettingsStore().load();
    _prefs = (await _store.get(widget.comicId))
        .mergedWith(defaults.toReaderPreferences());
    // 从详情页明确选择某话时，不要覆盖成「继续阅读」的进度。
    if (widget.restoreProgress) {
      final saved = await _progress.get(widget.comicId);
      if (saved != null && saved.chapterIndex < widget.chapters.length) {
        _chapterIndex = saved.chapterIndex;
        _savedPage = saved.currentPage;
      }
    }
    _refreshFavorite();
    // 本地漫画（无章节/无在线源）默认显示控制栏，避免「只有图片没有操控面板」。
    // 联网漫画仍保持沉浸式（点屏切换显隐）。
    if (_isLocalMode) _uiVisible = true;
    if (mounted) setState(() {});
    _applyOrientation();
    _applyFullscreen();
    _applyWakelock();
    if (_isLocalMode) {
      await _loadLocalImages(restorePage: _savedPage);
    } else {
      await _loadChapter(_chapterIndex, restorePage: _savedPage);
    }
  }

  /// 本地模式加载图片：优先使用 [widget.localImages]，否则解压 [widget.localCbzPath]。
  Future<void> _loadLocalImages({int restorePage = 0}) async {
    if (mounted) setState(() => _loading = true);
    try {
      List<String> imgs;
      if (widget.localImages != null && widget.localImages!.isNotEmpty) {
        imgs = List<String>.unmodifiable(widget.localImages!);
      } else if (widget.localCbzPath != null) {
        imgs = await _extractCbz(widget.localCbzPath!);
      } else {
        imgs = const <String>[];
      }
      if (!mounted) return;
      if (imgs.isEmpty) {
        setState(() {
          _images = const <String>[];
          _loading = false;
          _error = AppLocalizations.of(context).localFileLoadFailed;
        });
        return;
      }
      setState(() {
        _images = imgs;
        _loading = false;
        _error = null;
      });
      _setupControllers(restorePage: restorePage);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// 解压 CBZ/ZIP 文件取图片路径（参考 local_media_viewer._extractCbz）。
  ///
  /// R3 修复：若 [path] 为 Android SAF URI（`content://`），`File(path)` 无法
  /// 读取，抛出明确异常由上层 `_loadLocalImages` 的 catch 转为 `localFileLoadFailed`
  /// 错误态展示给用户，而非静默吞异常导致空白页。
  Future<List<String>> _extractCbz(String path) async {
    if (isAndroidSafUri(path)) {
      throw FileSystemException(
        'Android SAF URI cannot be read via dart:io File',
        path,
      );
    }
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final tempDir = await getTemporaryDirectory();
    final out = <String>[];
    for (final file in archive) {
      if (file.isFile && isImageFile(file.name)) {
        final content = file.content;
        if (content == null) continue;
        final target = File(
          p.join(tempDir.path, '${file.name.hashCode}_${p.basename(file.name)}'),
        );
        await target.writeAsBytes(content as List<int>);
        out.add(target.path);
      }
    }
    out.sort();
    return out;
  }

  /// 刷新收藏状态（init 与切换收藏后调用）。
  void _refreshFavorite() {
    final fav = context.read<FavoritesManager>();
    _isFav = fav.isFavorite(widget.comicId, SourceType.mangaSource);
  }

  /// 切换收藏状态（顶栏收藏按钮回调）。
  Future<void> _toggleFavorite() async {
    final l10n = AppLocalizations.of(context);
    final fav = context.read<FavoritesManager>();
    final wasFavorite = _isFav;
    final item = MediaItem(
      id: widget.comicId,
      title: widget.title,
      sourceId: widget.sourceId,
      sourceType: SourceType.mangaSource,
      detailUrl: widget.detailUrl,
      coverUrl: widget.coverUrl,
    );
    await fav.toggleFavorite(item);
    if (mounted) {
      setState(() => _isFav = !wasFavorite);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(wasFavorite ? l10n.favoriteRemoved : l10n.favoriteAdded),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _scrollController?.dispose();
    _zoomController.dispose();
    _flashController.dispose();
    _transitionTimer?.cancel();
    try {
      SystemChrome.setPreferredOrientations(<DeviceOrientation>[]);
    } on Object {
      // 测试环境忽略。
    }
    try {
      // 退出阅读器：恢复系统 UI 模式（沉浸全屏 → edgeToEdge）。
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } on Object {
      // 测试环境忽略。
    }
    try {
      // 退出阅读器：关闭屏幕常亮。
      WakelockPlus.disable();
    } on Object {
      // 测试环境忽略。
    }
    super.dispose();
  }

  // ─────────────────────── 数据加载 ───────────────────────

  Future<void> _loadChapter(int index,
      {int restorePage = 0, bool restoreToLast = false}) async {
    if (_loadingChapter) return;
    _loadingChapter = true;
    if (mounted) setState(() => _loading = true);
    try {
      final source = _repo.getById(widget.sourceId);
      if (source == null) throw Exception('source not found: ${widget.sourceId}');
      _source = source;
      final chapter = widget.chapters[index];
      final List<String> imgs = _preload.remove(index) ??
          await _service.fetchImages(
            source,
            comicId: widget.comicId,
            chapterId: chapter.id,
            renderedHtml: _renderedHtmlByChapter[index],
          );
      if (!mounted) return;
      // 回到上一话末页时 restoreToLast=true，落点为该章最后一页。
      final int rp = restoreToLast
          ? (imgs.isEmpty ? 0 : imgs.length - 1)
          : restorePage;
      setState(() {
        _images = imgs;
        _loading = false;
        _error = null;
      });
      _setupControllers(restorePage: rp);
      _saveProgress(rp);
    } on WebViewHtmlRequest catch (req) {
      // useWebview 脚本源（manga_goda / manga_baozimh 等）需在内嵌 WebView
      // 加载章节页、等待 JS 渲染后取回整页 HTML，再回灌给脚本解析图片。
      // 捕获请求后展示「抓取本页渲染内容」引导，用户触发回填并重试。
      if (mounted) {
        setState(() {
          _htmlCaptureRequest = req;
          _loading = false;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    } finally {
      _loadingChapter = false;
    }
  }

  /// 渲染后抽取完成后回填 HTML 并重试抓取当前章节图片（webview-html 源）。
  Future<void> _captureAndRetry() async {
    final req = _htmlCaptureRequest;
    if (req == null || !mounted) return;
    final outcome = await navigateToHtmlCapture(context, request: req);
    if (!mounted) return;
    if (outcome?.hasRenderedHtml == true && outcome!.renderedHtml != null) {
      _renderedHtmlByChapter[_chapterIndex] = outcome.renderedHtml!;
      setState(() => _htmlCaptureRequest = null);
      await _loadChapter(_chapterIndex, restorePage: _currentPage);
    } else {
      // 用户取消或未取到渲染 HTML：退回错误态，可重试或退出。
      if (mounted) {
        setState(() {
          _htmlCaptureRequest = null;
          _error = AppLocalizations.of(context).loadFailed;
          _loading = false;
        });
      }
    }
  }

  void _setupControllers({int restorePage = 0}) {
    // 旧控制器延迟到下一帧释放：避免旧 PageView 在 dispose→setState 之间
    // 访问已释放控制器导致崩溃/白屏，从而进度条/页码没有更新。
    final PageController? oldPageController = _pageController;
    final ScrollController? oldScrollController = _scrollController;
    _pageController = null;
    _scrollController = null;
    _currentPage = restorePage;
    if (_prefs.readingMode.isPaged) {
      // 越界保护：initialPage 必须在 [0, itemCount-1]，否则 PageView 抛异常
      // 导致双页/单页切换后白屏（隐藏崩溃防护）。
      final int maxInitial = (_controllerPageCount - 1).clamp(0, 1 << 30);
      final initial = _isDoublePage
          ? (restorePage ~/ 2).clamp(0, maxInitial)
          : restorePage.clamp(0, maxInitial);
      _pageController = PageController(initialPage: initial)
        ..addListener(_onPagedScroll);
      // 关键修复：PageView 在 controller 被替换（双页↔单页切换）时会复用同一个
      // ScrollPosition，新 PageController 的 initialPage 不会被重新应用，position
      // 停留在旧页，导致「进度条/页码正确（_currentPage 已更新）但图片停在旧页」。
      // 因此在布局完成后强制跳转到目标页，确保切换后图片与进度一致。
      if (initial != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pageController?.jumpToPage(initial);
        });
      }
    } else {
      _scrollController = ScrollController()..addListener(_onWebtoonScroll);
    }
    if (mounted) setState(() {});
    if (oldPageController != null || oldScrollController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldPageController?.dispose();
        oldScrollController?.dispose();
      });
    }
  }

  void _onPagedScroll() {
    final p = _pageController?.page;
    if (p == null) return;
    if (_controllerPageCount == 0) return;
    final controllerMax = _controllerPageCount - 1;
    final spreadIdx = p.round().clamp(0, controllerMax);
    // 双页模式以跨页的【左页】作为当前逻辑页。
    // 这样切回单页时不会跳到右页，进度条/保存也更稳定。
    final idx = _isDoublePage
        ? (spreadIdx * 2).clamp(0, _images.length - 1)
        : spreadIdx;
    if (idx != _currentPage) {
      _currentPage = idx;
      _saveProgress(idx);
      // 索引变化时刷新进度条（页码/滑条），否则点按翻页后进度条不更新。
      if (mounted) setState(() {});
    }
    _maybePreload(idx);
  }

  void _onWebtoonScroll() {
    final sc = _scrollController;
    if (sc == null || !sc.hasClients) return;
    final max = sc.position.maxScrollExtent;
    final frac = max > 0 ? sc.position.pixels / max : 0;
    final total = _images.length;
    final idx = total <= 1
        ? 0
        : (frac * (total - 1)).round().clamp(0, total - 1);
    if (idx != _currentPage) {
      _currentPage = idx;
      _saveProgress(idx);
      // 索引变化时刷新进度条（页码/滑条），否则翻页后进度条不更新。
      if (mounted) setState(() {});
    }
    _maybePreload(idx);
  }

  void _maybePreload(int idx) {
    // 接近章末：预加载下一章（末页翻下一张不再等待网络）。
    if (idx >= _images.length - 4) _preloadChapter(_chapterIndex + 1);
    // 接近章首：预加载上一章（首页翻上一张回到上一话末页不卡顿）。
    if (idx <= 3) _preloadChapter(_chapterIndex - 1);
  }

  /// 预加载指定章节图片到 [_preload] 缓存（best-effort，失败静默忽略）。
  void _preloadChapter(int index) {
    if (index < 0 || index >= widget.chapters.length) return;
    if (_preload.containsKey(index) || _preloading.contains(index)) return;
    _preloading.add(index);
    final source = _repo.getById(widget.sourceId);
    if (source == null) {
      _preloading.remove(index);
      return;
    }
    _service
        .fetchImages(
          source,
          comicId: widget.comicId,
          chapterId: widget.chapters[index].id,
          renderedHtml: _renderedHtmlByChapter[index],
        )
        .then((imgs) {
          if (mounted) _preload[index] = imgs;
        })
        .catchError((Object _) {})
        .whenComplete(() => _preloading.remove(index));
  }

  void _saveProgress(int page) {
    if (widget.chapters.isEmpty) return;
    final chapter = widget.chapters[_chapterIndex];
    _progress.save(
      widget.comicId,
      chapter.id,
      page,
      _chapterIndex,
      totalChapters: widget.chapters.length,
    );
    // 更新收藏条目的 lastRead 时间戳（P8.1.3 §廿一 收藏切换不丢 lastRead）
    try {
      context.read<FavoritesManager>().updateLastRead(
            widget.comicId,
            SourceType.mangaSource,
          );
    } catch (_) {
      // FavoritesManager 不可用时静默忽略。
    }
  }

  // ─────────────────────── 导航 ───────────────────────

  void _goNextPage() {
    _triggerFlash();
    if (_prefs.readingMode.isWebtoon) {
      final sc = _scrollController;
      if (sc == null || !sc.hasClients) return;
      // 滚动到底部（保留 2px 容差）时翻下一张 = 进入下一章。
      if (sc.offset >= sc.position.maxScrollExtent - 2) {
        _goNextChapter();
      } else {
        _scrollByPage(1);
      }
      return;
    }
    final pc = _pageController;
    if (pc == null || !pc.hasClients) return;
    final total = _controllerPageCount;
    if (total <= 1) {
      _goNextChapter();
      return;
    }
    // page 可能为 null（未 layout 时），用当前逻辑页/跨页兜底。
    final current = _isDoublePage ? (_currentPage ~/ 2) : _currentPage;
    final page = pc.page ?? current.toDouble();
    // 必须离最后一页/跨页足够近（<0.5）才进下一章，避免浮点误差或回弹导致误判。
    if (page < total - 1 - 0.5) {
      pc.nextPage(duration: AppTokens.durFast, curve: Curves.easeInOut);
    } else {
      _goNextChapter();
    }
  }

  void _goPrevPage() {
    _triggerFlash();
    if (_prefs.readingMode.isWebtoon) {
      final sc = _scrollController;
      if (sc == null || !sc.hasClients) return;
      // 滚动到顶部时翻上一张 = 回到上一章最后一页。
      if (sc.offset <= sc.position.minScrollExtent + 2) {
        _goPrevChapter();
      } else {
        _scrollByPage(-1);
      }
      return;
    }
    final pc = _pageController;
    if (pc == null || !pc.hasClients) return;
    final current = _isDoublePage ? (_currentPage ~/ 2) : _currentPage;
    final page = pc.page ?? current.toDouble();
    if (page > 0.5) {
      pc.previousPage(duration: AppTokens.durFast, curve: Curves.easeInOut);
    } else {
      _goPrevChapter();
    }
  }

  void _scrollByPage(int dir) {
    final sc = _scrollController;
    if (sc == null || !sc.hasClients) return;
    final h = sc.position.viewportDimension;
    final target = (sc.offset + dir * h)
        .clamp(0.0, sc.position.maxScrollExtent)
        .toDouble();
    sc.animateTo(target, duration: AppTokens.durFast, curve: Curves.easeInOut);
  }

  /// 翻页闪光：仅在 [ReaderPreferences.flashEnabled] 时触发，延迟
  /// [ReaderPreferences.flashInterval] 毫秒后播放一次。
  void _triggerFlash() {
    final p = _prefs;
    if (!p.flashEnabled || !mounted) return;
    final dur = Duration(milliseconds: p.flashTime);
    Future.delayed(Duration(milliseconds: p.flashInterval), () {
      if (!mounted) return;
      switch (p.flashColor) {
        case ReaderFlashColor.black:
          _runFlash(Colors.black, dur);
        case ReaderFlashColor.white:
          _runFlash(Colors.white, dur);
        case ReaderFlashColor.blackWhite:
          _runFlash(Colors.black, dur, () => _runFlash(Colors.white, dur));
      }
    });
  }

  /// 播放一段「淡入→淡出」的闪光（opacity 0→1→0）。[onDone] 用于黑→白连续闪。
  void _runFlash(Color color, Duration dur, [VoidCallback? onDone]) {
    _flashController.stop();
    _flashController.duration = dur;
    _flashController.clearListeners();
    _flashController.addListener(() {
      if (mounted) setState(() => _flashOpacity = _flashController.value);
    });
    setState(() => _flashColor = color);
    _flashController.forward(from: 0).then((_) {
      _flashController.reverse(from: 1).then((_) {
        if (mounted) setState(() => _flashOpacity = 0.0);
        onDone?.call();
      });
    });
  }

  void _goNextChapter() {
    if (_chapterIndex < widget.chapters.length - 1) {
      final next = _chapterIndex + 1;
      _triggerChapterTransition(widget.chapters[next].title);
      _chapterIndex = next;
      _loadChapter(_chapterIndex);
    }
  }

  void _goPrevChapter() {
    if (_chapterIndex > 0) {
      final prev = _chapterIndex - 1;
      _triggerChapterTransition(widget.chapters[prev].title);
      _chapterIndex = prev;
      // 回到上一话的【最后一页】，保证「首页翻上一张」连贯。
      _loadChapter(_chapterIndex, restoreToLast: true);
    }
  }

  /// 章节切换过渡标题卡：若开启 [ReaderPreferences.showChapterTransition]，
  /// 在章节切换时短暂居中显示章节标题，约 1.2s 后淡出。
  void _triggerChapterTransition(String title) {
    if (!_prefs.showChapterTransition || !mounted) return;
    setState(() {
      _transitionTitle = title;
      _transitionVisible = true;
    });
    _transitionTimer?.cancel();
    _transitionTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _transitionVisible = false);
    });
  }

  /// 双击缩放：在「适配宽下限」与 [ReaderPreferences.doubleTapZoomScale] 之间切换。
  /// 以 [focal]（视口坐标）或视口中心为锚点；preventShrink 时下限锁定为 1.0（适配宽）。
  /// [focal] 为 null 时使用中心（双击兜底），非空时用于桌面 Shift+左键定点缩放。
  void _toggleZoom([Offset? focal]) {
    final m = _zoomController.value;
    final cur = m.getMaxScaleOnAxis();
    final double floor = _prefs.preventShrink ? 1.0 : 0.5;
    final target = cur > floor * 1.01 ? floor : _prefs.doubleTapZoomScale;
    final Offset anchor = focal ??
        Offset(
          MediaQuery.of(context).size.width / 2,
          MediaQuery.of(context).size.height / 2,
        );
    final realFactor = target / cur;
    _zoomController.value = Matrix4.identity()
      ..translate(anchor.dx * (1 - realFactor), anchor.dy * (1 - realFactor))
      ..scale(realFactor)
      ..multiply(m);
  }

  /// 打开右侧设置面板（承载 [ReaderSettingsBody]）。
  ///
  /// 自动保存模式：面板内任何改动经由 [_applySettingsAuto] 即时生效并落盘，
  /// 无需「确认」；关闭面板即结束，不会回滚。
  void _showSettingsPanel() {
    setState(() => _settingsPanelVisible = true);
  }

  /// 关闭设置面板（不回滚，改动已即时保存）。
  void _hideSettingsPanel() {
    if (!mounted) return;
    setState(() => _settingsPanelVisible = false);
  }

  /// 设置面板内的改动：即时预览 + 自动保存。
  ///
  /// 仅对「影响系统 UI / 控制器结构」的字段做重应用，避免亮度/滤镜等连续
  /// 滑块拖动时反复重建控制器或切换全屏造成卡顿：
  /// - orientation / fullscreen / keepScreenOn 变化 → 重应用系统 UI；
  /// - readingMode / splitDoublePage 变化 → 重建控制器（paged↔webtoon、单↔双页）。
  ///
  /// 注意：先同步更新 [_prefs]（不单独 setState），再由 [_setupControllers]
  /// 一次性 setState，避免「新 prefs + 旧控制器」的中间帧导致进度条/页码不同步。
  Future<void> _applySettingsAuto(ReaderPreferences next) async {
    if (!mounted) return;
    final prev = _prefs;
    _prefs = next;
    await _store.save(widget.comicId, next);
    if (prev.orientation != next.orientation) _applyOrientation();
    if (prev.fullscreen != next.fullscreen) _applyFullscreen();
    if (prev.keepScreenOn != next.keepScreenOn) _applyWakelock();
    if (prev.readingMode != next.readingMode ||
        prev.splitDoublePage != next.splitDoublePage) {
      if (_images.isNotEmpty) {
        _setupControllers(restorePage: _currentPage);
        return;
      }
    }
    if (mounted) setState(() {});
  }

  /// 即时落盘偏好变更（用于底栏快捷工具栏的开关，例如裁剪 / 模式切换）。
  /// 同样避免「新 prefs + 旧控制器」的中间帧。
  Future<void> _onPrefsChanged(ReaderPreferences next) async {
    if (!mounted) return;
    _prefs = next;
    await _store.save(widget.comicId, next);
    _applyOrientation();
    _applyWakelock();
    _applyFullscreen();
    if (_images.isNotEmpty) {
      _setupControllers(restorePage: _currentPage);
    } else {
      if (mounted) setState(() {});
    }
  }

  /// 给当前页旋转 90°（quarterTurns +1，模 4）。
  void _rotateCurrentPage() {
    final idx = _currentPage.clamp(0, _images.length - 1);
    final cur = _pageRotations[idx] ?? 0;
    final next = (cur + 1) % 4;
    setState(() {
      _pageRotations[idx] = next;
      // 单页旋转 + rotateLandscape：强制横屏。
      if (_prefs.rotateLandscape && next != 0) {
        // 与 _applyOrientation 协同：仅当 orientation 为 default/followSystem 时
        // 才临时切横屏，否则尊重用户锁定的方向。
        if (_prefs.orientation == ScreenOrientation.defaultMode ||
            _prefs.orientation == ScreenOrientation.followSystem) {
          try {
            SystemChrome.setPreferredOrientations(<DeviceOrientation>[
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
          } on Object {
            // 测试环境忽略。
          }
        }
      }
    });
  }

  /// 屏幕常亮：按 [ReaderPreferences.keepScreenOn] 启用 / 关闭 wakelock。
  void _applyWakelock() {
    try {
      if (_prefs.keepScreenOn) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    } on Object {
      // 测试环境忽略。
    }
  }

  /// 沉浸全屏：进入阅读器时切到 immersiveSticky；dispose 时恢复 edgeToEdge。
  /// 与 [_applyOrientation] 协同：orientation 改 preferredOrientations，不动 system UI mode。
  void _applyFullscreen() {
    try {
      // 按 [ReaderPreferences.fullscreen] 决定：开启=沉浸全屏，关闭=恢复系统栏。
      SystemChrome.setEnabledSystemUIMode(
        _prefs.fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } on Object {
      // 测试环境忽略。
    }
  }

  /// 章内跳页：paged 用 PageController，webtoon 按比例跳到对应滚动位置。
  void _jumpToPage(int target) {
    final total = _images.length;
    if (total == 0) return;
    final t = target.clamp(0, total - 1);
    if (_prefs.readingMode.isWebtoon) {
      final sc = _scrollController;
      if (sc == null || !sc.hasClients) return;
      final max = sc.position.maxScrollExtent;
      final ratio = total > 1 ? t / (total - 1) : 0.0;
      sc.jumpTo((ratio * max).clamp(0.0, max));
    } else {
      _pageController?.jumpToPage(_isDoublePage ? (t ~/ 2) : t);
    }
  }

  void _applyOrientation() {
    List<DeviceOrientation>? orient;
    switch (_prefs.orientation) {
      case ScreenOrientation.portrait:
      case ScreenOrientation.lockPortrait:
        orient = const <DeviceOrientation>[DeviceOrientation.portraitUp];
      case ScreenOrientation.landscape:
        orient = const <DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight
        ];
      case ScreenOrientation.lockLandscape:
        orient = const <DeviceOrientation>[DeviceOrientation.landscapeLeft];
      case ScreenOrientation.reversePortrait:
        orient = const <DeviceOrientation>[DeviceOrientation.portraitDown];
      case ScreenOrientation.defaultMode:
      case ScreenOrientation.followSystem:
        orient = const <DeviceOrientation>[];
    }
    try {
      SystemChrome.setPreferredOrientations(orient);
    } on Object {
      // 测试环境忽略。
    }
  }

  // ─────────────────────── 构建 ───────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _prefs.resolveBackgroundColor(isDark);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: <Widget>[
          _buildContent(l10n),
          if (!_loading && _error == null && _images.isNotEmpty)
            ReaderTapZones(
              layout: _prefs.tapZoneLayout,
              tapZoneInvert: _prefs.tapZoneInvert,
              isVertical: _prefs.readingMode.isWebtoon,
              onPrev: _goPrevPage,
              onNext: _goNextPage,
              onToggleUi: () {
                setState(() => _uiVisible = !_uiVisible);
              },
              onZoom: _toggleZoom,
              onZoomAt: (pos) => _toggleZoom(pos),
              onLongPress: (_images.isEmpty || !_prefs.showLongPressMenu)
                  ? null
                  : () => showReaderImageActions(
                        context: context,
                        url: _images[_currentPage.clamp(0, _images.length - 1)],
                        source: _source,
                        comicId: widget.comicId,
                        sourceType: SourceType.mangaSource,
                      ),
            ),
          if (_prefs.flashEnabled)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: _flashColor.withValues(alpha: _flashOpacity),
                ),
              ),
            ),
          if (_transitionVisible)
            Center(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _transitionVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Card(
                    color: Colors.black54,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      child: Text(
                        _transitionTitle,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_uiVisible)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(l10n, bg),
            ),
          if (_uiVisible)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomBar(l10n),
            ),
          if (_uiVisible && _prefs.progressBarOnRight && _images.isNotEmpty)
            _buildRightProgressBar(l10n),
          if (_settingsPanelVisible) ...<Widget>[
            // 内联面板背景遮罩：点击遮罩 = 关闭面板（改动已自动保存，不回滚）。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _hideSettingsPanel,
                child: const ColoredBox(color: Colors.black54),
              ),
            ),
            _buildSettingsPanel(l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: AppLoadingIndicator());
    }
    // useWebview 脚本源：需先抓取渲染后 HTML 才能解析图片（见 _captureAndRetry）。
    if (_htmlCaptureRequest != null) {
      return _CenterMessage(
        icon: Icons.cloud_download_outlined,
        message: l10n.captureHint,
        onRetry: _captureAndRetry,
      );
    }
    if (_error != null) {
      return _CenterMessage(
        icon: Icons.error_outline,
        message: _isLocalMode ? l10n.localFileLoadFailed : l10n.loadFailed,
        onRetry: _isLocalMode
            ? () => _loadLocalImages(restorePage: _currentPage)
            : () => _loadChapter(_chapterIndex, restorePage: _currentPage),
      );
    }
    if (_images.isEmpty) {
      return _CenterMessage(icon: Icons.image_not_supported, message: l10n.noImages);
    }
    if (_prefs.readingMode.isWebtoon) return _buildWebtoon();
    return _buildPaged();
  }

  /// 双页并排是否生效：仅横排单页模式（LTR/RTL）支持。
  /// 竖排 / 长条模式下「双页拆分」开关会被自动关闭（见设置面板 _buildReadingMode /
  /// _buildSplitDoublePage 的联动），以保证开关始终「有作用」。
  bool get _isDoublePage =>
      _prefs.splitDoublePage &&
      (_prefs.readingMode == ReadingMode.singleLTR ||
          _prefs.readingMode == ReadingMode.singleRTL);

  /// 左右留白像素值（sideMargin 占屏宽比例 → 实际像素）。
  double get _sideMarginPx =>
      _prefs.sideMargin * MediaQuery.of(context).size.width;

  /// 跨页（spread）数量：双页模式下 PageView 的 itemCount。
  int get _spreadCount => (_images.length / 2).ceil();

  /// PageController 的单位总数：双页模式 = 跨页数，否则 = 单页数。
  int get _controllerPageCount => _isDoublePage ? _spreadCount : _images.length;

  Widget _buildPaged() {
    if (_isDoublePage) return _buildPagedSpread();
    final pc = _pageController;
    if (pc == null) return const SizedBox.shrink();
    return PageView.builder(
      controller: pc,
      scrollDirection: _prefs.readingMode == ReadingMode.singleVertical
          ? Axis.vertical
          : Axis.horizontal,
      reverse: _prefs.readingMode == ReadingMode.singleRTL,
      itemCount: _images.length,
      itemBuilder: (ctx, i) => Padding(
        padding: EdgeInsets.symmetric(horizontal: _sideMarginPx),
        child: MangaPageImage(
          url: _images[i],
          prefs: _prefs,
          zoomController: _zoomController,
          source: _source,
          rotationQuarterTurns: _pageRotations[i] ?? 0,
          cropEdge: _prefs.cropEdge,
        ),
      ),
    );
  }

  /// 双页并排：仅在 splitDoublePage 且横排单页模式（singleLTR/singleRTL）下使用。
  /// PageController 以「跨页(spread)」为单位，每屏展示两页；[_currentPage] 仍记录逻辑单页索引（取当前跨页的首页）。
  Widget _buildPagedSpread() {
    final pc = _pageController;
    if (pc == null) return const SizedBox.shrink();
    final rtl = _prefs.readingMode == ReadingMode.singleRTL;
    return PageView.builder(
      controller: pc,
      scrollDirection: Axis.horizontal,
      reverse: rtl,
      itemCount: _spreadCount,
      itemBuilder: (ctx, spreadIdx) {
        final a = spreadIdx * 2;
        final b = a + 1;
        final aImg = _images[a];
        final bImg = b < _images.length ? _images[b] : null;
        final List<Widget> rowChildren = <Widget>[
          Expanded(
            child: MangaPageImage(
              url: aImg,
              prefs: _prefs,
              zoomController: _zoomController,
              source: _source,
              rotationQuarterTurns: _pageRotations[a] ?? 0,
              cropEdge: _prefs.cropEdge,
            ),
          ),
        ];
        if (bImg != null) {
          rowChildren.add(
            Expanded(
              child: MangaPageImage(
                url: bImg,
                prefs: _prefs,
                zoomController: _zoomController,
                source: _source,
                rotationQuarterTurns: _pageRotations[b] ?? 0,
                cropEdge: _prefs.cropEdge,
              ),
            ),
          );
        }
        // RTL 阅读顺序为右→左：跨页内两页交换位置（单页奇数尾页不变）。
        if (rtl) rowChildren.insert(0, rowChildren.removeLast());
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: _sideMarginPx),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rowChildren,
          ),
        );
      },
    );
  }

  Widget _buildWebtoon() {
    final sc = _scrollController;
    if (sc == null) return const SizedBox.shrink();
    final gap = _prefs.readingMode == ReadingMode.webtoonWithGap
        ? AppTokens.spaceMd
        : 0.0;
    return ListView.separated(
      controller: sc,
      padding: EdgeInsets.zero,
      itemCount: _images.length,
      separatorBuilder: (_, __) => SizedBox(height: gap),
      itemBuilder: (ctx, i) => Padding(
        padding: EdgeInsets.symmetric(horizontal: _sideMarginPx),
        child: MangaPageImage(
          url: _images[i],
          prefs: _prefs,
          zoomController: _zoomController,
          source: _source,
          rotationQuarterTurns: _pageRotations[i] ?? 0,
          cropEdge: _prefs.cropEdge,
        ),
      ),
    );
  }

  Widget _buildTopBar(AppLocalizations l10n, Color bg) {
    final chapter = widget.chapters.isEmpty
        ? null
        : widget.chapters[_chapterIndex];
    final String? chapterUrl = chapter?.url;
    final String? absoluteChapterUrl = (chapterUrl != null &&
            chapterUrl.isNotEmpty)
        ? (_source != null && _source!.site.baseUrl.isNotEmpty
            ? _source!.site.baseUrl + chapterUrl
            : chapterUrl)
        : null;
    // 本地模式标题：文件名 · 本地文件（无章节概念）。
    final String titleText = _isLocalMode
        ? '${widget.title} · ${l10n.localFileLabel}'
        : '${widget.title} · ${l10n.chapterN(_chapterIndex + 1)}'
            '${chapter != null && chapter.title.isNotEmpty ? ' · ${chapter.title}' : ''}';
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[bg.withValues(alpha: 0.95), bg.withValues(alpha: 0)],
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: AppTokens.spaceSm,
        ),
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                titleText,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(_isFav ? Icons.favorite : Icons.favorite_border),
              tooltip: l10n.favorite,
              onPressed: _toggleFavorite,
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: l10n.readerSettings,
              onPressed: _showSettingsPanel,
            ),
            // 章节列表按钮：本地模式无章节概念，隐藏。
            if (!_isLocalMode)
              IconButton(
                icon: const Icon(Icons.toc),
                tooltip: l10n.chapterList,
                onPressed: () async {
                  final index = await showChapterList(
                    context,
                    widget.chapters,
                    _chapterIndex,
                  );
                  if (index != null && index != _chapterIndex && mounted) {
                    _chapterIndex = index;
                    _loadChapter(_chapterIndex);
                  }
                },
              ),
            // WebView / 浏览器 / 分享菜单：本地模式无在线 URL，隐藏。
            if (!_isLocalMode)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: l10n.moreActions,
                onSelected: (String value) {
                  if (absoluteChapterUrl == null) return;
                  switch (value) {
                    case 'webview':
                      openInAppBrowser(context, absoluteChapterUrl);
                    case 'browser':
                      openInExternalBrowser(context, absoluteChapterUrl);
                    case 'share':
                      shareContent(
                        context,
                        '${widget.title} - ${chapter?.title ?? ''}',
                        absoluteChapterUrl,
                      );
                  }
                },
                itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'webview',
                    enabled: absoluteChapterUrl != null,
                    child: ListTile(
                      leading: const Icon(Icons.public),
                      title: Text(l10n.openInAppBrowser),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'browser',
                    enabled: absoluteChapterUrl != null,
                    child: ListTile(
                      leading: const Icon(Icons.open_in_new),
                      title: Text(l10n.openInBrowser),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'share',
                    enabled: absoluteChapterUrl != null,
                    child: ListTile(
                      leading: const Icon(Icons.share_outlined),
                      title: Text(l10n.share),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    final Color barColor = _prefs.resolveBackgroundColor(
      Theme.of(context).brightness == Brightness.dark,
    );
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: <Color>[
              barColor.withValues(alpha: 0.95),
              barColor.withValues(alpha: 0),
            ],
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: AppTokens.spaceSm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 章内进度滑条（仅底横形态；右竖形态由 _buildRightProgressBar 单独覆盖）。
            _buildProgressBar(l10n),
            const SizedBox(height: AppTokens.spaceXs),
            _buildBottomToolbar(l10n),
          ],
        ),
      ),
    );
  }

  /// 底部横向进度滑条（progressBarOnRight=false 时渲染）。
  /// 左右翻页箭头 + 滑条 + 页码（受 showPageNumber 控制）。
  /// 双页模式下以「跨页」为单位，标签显示当前跨页包含的页码范围。
  Widget _buildProgressBar(AppLocalizations l10n) {
    if (_prefs.progressBarOnRight) return const SizedBox.shrink();
    final bool doubleMode = _isDoublePage;
    final int totalImages = _images.length;
    final int total = doubleMode ? _spreadCount : totalImages;
    final int currentIndex =
        doubleMode ? (_currentPage ~/ 2) : _currentPage;
    final double base = total > 1 ? currentIndex / (total - 1) : 0.0;
    final double value = (_progressDragValue ?? base).clamp(0.0, 1.0);
    return Semantics(
      label: l10n.readerProgress,
      child: Directionality(
        // RTL 模式下滑条方向反转（视觉与翻页方向一致）。
        textDirection: _prefs.readingMode == ReadingMode.singleRTL
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: l10n.prevPage,
              onPressed: _goPrevPage,
            ),
            Expanded(
              child: Slider(
                value: value,
                onChanged: total > 1
                    ? (v) => setState(() => _progressDragValue = v)
                    : null,
                onChangeEnd: total > 1
                    ? (v) {
                        setState(() => _progressDragValue = null);
                        if (doubleMode) {
                          final spread = (v * (total - 1)).round();
                          _jumpToPage(spread * 2);
                        } else {
                          final target = (v * (total - 1)).round();
                          _jumpToPage(target);
                        }
                      }
                    : null,
              ),
            ),
            if (_prefs.showPageNumber)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppTokens.spaceSm),
                child: Text(
                  doubleMode
                      ? _doublePageIndicatorText(l10n, currentIndex, totalImages)
                      : l10n.pageIndicator(
                          totalImages == 0 ? 0 : _currentPage + 1,
                          totalImages,
                        ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: l10n.nextPage,
              onPressed: _goNextPage,
            ),
          ],
        ),
      ),
    );
  }

  /// 双页跨页页码标签，例如 1-2 / 10。
  String _doublePageIndicatorText(
    AppLocalizations l10n,
    int spreadIndex,
    int totalImages,
  ) {
    final first = spreadIndex * 2 + 1;
    final last = ((spreadIndex + 1) * 2).clamp(1, totalImages);
    return l10n.readerDoublePageIndicator(first, last, totalImages);
  }

  /// 双页跨页范围文本（不含总数），例如 1-2。
  String _doublePageRangeText(int spreadIndex, int totalImages) {
    final first = spreadIndex * 2 + 1;
    final last = ((spreadIndex + 1) * 2).clamp(1, totalImages);
    return '$first-$last';
  }

  /// 右侧竖向进度滑条（progressBarOnRight=true 时渲染）。
  /// 靠右 Positioned：上/下翻页箭头 + 顶/底页码 + 旋转 90° 的 Slider。
  /// 双页模式下以「跨页」为单位。
  Widget _buildRightProgressBar(AppLocalizations l10n) {
    final bool doubleMode = _isDoublePage;
    final int totalImages = _images.length;
    final int total = doubleMode ? _spreadCount : totalImages;
    final int currentIndex =
        doubleMode ? (_currentPage ~/ 2) : _currentPage;
    final double base = total > 1 ? currentIndex / (total - 1) : 0.0;
    final double value = (_progressDragValue ?? base).clamp(0.0, 1.0);
    final bool showNum = _prefs.showPageNumber;
    return Positioned(
      right: AppTokens.spaceXs,
      top: 0,
      bottom: 0,
      child: SafeArea(
        child: Center(
          child: Semantics(
            label: l10n.readerProgress,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.expand_less),
                  tooltip: l10n.prevPage,
                  onPressed: _goPrevPage,
                ),
              if (showNum)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppTokens.spaceXs,
                  ),
                  child: Text(
                    doubleMode
                        ? _doublePageRangeText(currentIndex, totalImages)
                        : '${totalImages == 0 ? 0 : _currentPage + 1}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                SizedBox(
                  // 旋转 90° 后，Slider 的横向宽度变成竖向高度。
                  height: MediaQuery.of(context).size.height * 0.4,
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: Slider(
                      value: value,
                      onChanged: total > 1
                          ? (v) => setState(() => _progressDragValue = v)
                          : null,
                      onChangeEnd: total > 1
                          ? (v) {
                              setState(() => _progressDragValue = null);
                              if (doubleMode) {
                                final spread = (v * (total - 1)).round();
                                _jumpToPage(spread * 2);
                              } else {
                                final target = (v * (total - 1)).round();
                                _jumpToPage(target);
                              }
                            }
                          : null,
                    ),
                  ),
                ),
                if (showNum)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTokens.spaceXs,
                    ),
                    child: Text(
                      // 与单页模式保持一致：底部始终显示总页数。
                      '$totalImages',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.expand_more),
                  tooltip: l10n.nextPage,
                  onPressed: _goNextPage,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 底部快捷工具栏：阅读模式选择 / Spacer / 裁剪 / 旋转 / 设置。
  Widget _buildBottomToolbar(AppLocalizations l10n) {
    return Row(
      children: <Widget>[
        IconButton(
          icon: Icon(_readingModeIcon(_prefs.readingMode)),
          tooltip: l10n.readerMode,
          onPressed: () => _showReadingModePicker(l10n),
        ),
        const Spacer(),
        IconButton(
          icon: Icon(_prefs.cropEdge ? Icons.crop : Icons.crop_free),
          tooltip: l10n.readerCropEdge,
          onPressed: () => _onPrefsChanged(
            _prefs.copyWith(cropEdge: !_prefs.cropEdge),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.rotate_right),
          tooltip: l10n.readerRotatePage,
          onPressed: _rotateCurrentPage,
        ),
        IconButton(
          icon: const Icon(Icons.tune),
          tooltip: l10n.readerSettings,
          onPressed: _showSettingsPanel,
        ),
      ],
    );
  }

  IconData _readingModeIcon(ReadingMode mode) => switch (mode) {
        ReadingMode.singleLTR => Icons.arrow_forward,
        ReadingMode.singleRTL => Icons.arrow_back,
        ReadingMode.singleVertical => Icons.arrow_downward,
        ReadingMode.webtoon => Icons.view_stream,
        ReadingMode.webtoonWithGap => Icons.view_agenda,
      };

  /// 阅读模式选择：弹出白色底部面板，用 ChoiceChip 列出 5 种模式
  ///（用户决策：与小说阅读器一致的形式）。
  void _showReadingModePicker(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.readerMode,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppTokens.spaceMd),
              Wrap(
                spacing: AppTokens.spaceSm,
                runSpacing: AppTokens.spaceSm,
                children: ReadingMode.values.map((m) {
                  return ChoiceChip(
                    label: Text(_readingModeLabel(l10n, m)),
                    selected: _prefs.readingMode == m,
                    onSelected: (_) {
                      _onPrefsChanged(_prefs.copyWith(readingMode: m));
                      Navigator.of(ctx).pop();
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _readingModeLabel(AppLocalizations l10n, ReadingMode m) => switch (m) {
        ReadingMode.singleLTR => l10n.readerModeSingleLTR,
        ReadingMode.singleRTL => l10n.readerModeSingleRTL,
        ReadingMode.singleVertical => l10n.readerModeSingleVertical,
        ReadingMode.webtoon => l10n.readerModeWebtoon,
        ReadingMode.webtoonWithGap => l10n.readerModeWebtoonWithGap,
      };

  /// 右侧内联设置面板：承载 [ReaderSettingsBody]，自动保存模式。
  ///
  /// 宽度收窄并带左侧圆角，与小说阅读器设置面板形态保持一致，避免占据过大空间。
  /// 顶部仅保留「关闭」按钮（改动即时生效并落盘，无需确认）。
  Widget _buildSettingsPanel(AppLocalizations l10n) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      child: Container(
        width: screenWidth * 0.62 < 420 ? screenWidth * 0.62 : 420,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(AppTokens.spaceLg),
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black26,
              blurRadius: 16,
              offset: Offset(-2, 0),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              // 顶部条：标题 / 关闭
              Row(
                children: <Widget>[
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.only(left: AppTokens.spaceMd),
                      child: Text(
                        l10n.readerSettings,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                    onPressed: _hideSettingsPanel,
                  ),
                ],
              ),
              const Divider(height: 1),
              Expanded(
                child: ReaderSettingsBody(
                  initial: _prefs,
                  onChanged: _applySettingsAuto,
                  showConfirmButton: false,
                  showHeader: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 居中的提示信息（错误 / 空）。
class _CenterMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  const _CenterMessage({required this.icon, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: AppTokens.spaceMd),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppTokens.spaceMd),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(AppLocalizations.of(context).retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 单页漫画图：支持以指针为中心的双击/滚轮缩放（缩放由外部
/// [zoomController] 统一驱动，便于阅读器在点击区域覆盖层上响应双击缩放）。
///
/// 增强：[rotationQuarterTurns] 让用户对单页 90° 旋转（不影响其他页）；
/// [cropEdge] 为 true 时改用 [BoxFit.cover] / 居中裁切去四周留白（简单版）。
class MangaPageImage extends StatefulWidget {
  final String url;
  final ReaderPreferences prefs;
  final TransformationController? zoomController;
  final PluginConfig? source;

  /// 该页旋转的 quarterTurns（0/1/2/3 = 0°/90°/180°/270°）。
  final int rotationQuarterTurns;

  /// 是否裁边（true 时图片 fit 切换为 cover + 居中对齐，去除四周留白）。
  final bool cropEdge;

  const MangaPageImage({
    super.key,
    required this.url,
    required this.prefs,
    this.zoomController,
    this.source,
    this.rotationQuarterTurns = 0,
    this.cropEdge = false,
  });

  @override
  State<MangaPageImage> createState() => _MangaPageImageState();
}

class _MangaPageImageState extends State<MangaPageImage> {
  final TransformationController _local = TransformationController();
  TransformationController get _tc => widget.zoomController ?? _local;

  @override
  void dispose() {
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 初始缩放（initialZoom）+ 裁边（cropEdge）共同决定图片 fit 与尺寸约束。
    // cropEdge 优先：用 BoxFit.cover 居中裁切，去掉页面四周留白（按文档简单版实现）。
    // 非裁边时按 initialZoom 选择适配方式。
    final (BoxFit fit, double? width) = _resolveFit();
    final Widget raw = widget.cropEdge
        ? SizedBox.expand(
            child: SourceImage(
              url: widget.url,
              source: widget.source,
              fit: BoxFit.cover,
              placeholder: const Center(child: AppLoadingIndicator()),
            ),
          )
        : Align(
            alignment: Alignment.center,
            child: SourceImage(
              url: widget.url,
              source: widget.source,
              fit: fit,
              width: width,
              placeholder: const Center(child: AppLoadingIndicator()),
            ),
          );
    final img = ReaderImageFiltered(
      brightness: widget.prefs.filterBrightness,
      contrast: widget.prefs.filterContrast,
      colorTemp: widget.prefs.filterColorTemp,
      saturation: widget.prefs.filterSaturation,
      hue: widget.prefs.filterHue,
      inverted: widget.prefs.filterInverted,
      grayscale: widget.prefs.filterGrayscale,
      child: raw,
    );
    // 旋转包裹在 img 外：仅对该页生效，不影响其他页。
    final rotated = RotatedBox(
      quarterTurns: widget.rotationQuarterTurns,
      child: img,
    );
    // 桌面滚轮缩放始终可用（雷区 12），双击/捏合缩放由 doubleTapZoom 控制
    // （P8.3.1 §廿四 桌面滚轮缩放解耦 doubleTapZoom）。
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) _onWheel(e);
      },
      child: InteractiveViewer(
        transformationController: _tc,
        minScale: widget.prefs.minScale,
        maxScale: widget.prefs.maxScale,
        // doubleTapZoom 关闭时禁用触摸缩放/平移，但桌面滚轮仍可用
        panEnabled: widget.prefs.doubleTapZoom,
        scaleEnabled: widget.prefs.doubleTapZoom,
        child: rotated,
      ),
    );
  }

  /// 由 [ReaderPreferences.initialZoom] 推导非裁边状态下的图片 fit 与宽度约束。
  /// - fitWidth：按宽度适配（width=∞）。
  /// - fitHeight：按高度适配（width=∞，由父容器高度约束）。
  /// - original：原始像素大小（不加宽高约束，由 InteractiveViewer 裁剪/平移）。
  ///
  /// 裁边（cropEdge）在 [build] 中单独用 [SizedBox.expand] + [BoxFit.cover] 处理，
  /// 不再经过本方法。
  (BoxFit, double?) _resolveFit() {
    switch (widget.prefs.initialZoom) {
      case ReaderInitialZoom.fitWidth:
        return (BoxFit.fitWidth, double.infinity);
      case ReaderInitialZoom.fitHeight:
        return (BoxFit.fitHeight, double.infinity);
      case ReaderInitialZoom.original:
        return (BoxFit.none, null);
    }
  }

  void _onWheel(PointerScrollEvent e) {
    // scrollWheelInverted=true：反转滚轮方向（上滚缩小、下滚放大）。
    final double base = e.scrollDelta.dy < 0 ? 1.1 : 0.9;
    final double factor =
        widget.prefs.scrollWheelInverted ? (base == 1.1 ? 0.9 : 1.1) : base;
    _zoomAround(e.localPosition, factor);
  }

  void _zoomAround(Offset focal, double factor) {
    final m = _tc.value;
    final cur = m.getMaxScaleOnAxis();
    final newScale =
        (cur * factor).clamp(widget.prefs.minScale, widget.prefs.maxScale);
    final realFactor = newScale / cur;
    final dx = focal.dx * (1 - realFactor);
    final dy = focal.dy * (1 - realFactor);
    _tc.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(realFactor)
      ..multiply(m);
  }
}
