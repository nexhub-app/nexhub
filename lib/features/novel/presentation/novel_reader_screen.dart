import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../../core/comic/models/reader_preferences.dart'
    show ReaderTapZoneLayout, TapZoneInvert;
import '../../../core/favorites/favorites_manager.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/download/download_manager.dart';
import '../../../core/novel/novel_page_animation.dart';
import '../../../core/novel/novel_progress_manager.dart';
import '../../../core/novel/novel_reader_preferences.dart';
import '../../../core/reader/tap_zone_resolver.dart';
import '../../../core/settings/reader_default_settings.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/scraper/verification_detector.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/reader_tokens.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../core/widgets/chapter_list_sheet.dart';
import '../../../core/widgets/detail_action_utils.dart';
import 'novel_animated_page_view.dart';
import 'novel_bookmark_manager.dart';
import 'novel_chinese_converter.dart';
import 'novel_in_book_search_sheet.dart';
import 'novel_note_manager.dart';
import 'novel_paginator.dart';
import 'novel_tts_controller.dart';

/// 小说阅读器（Phase 4 — Task 19/20）。
///
/// 支持文本分页、6 种翻页动画（none/slide/scroll/fade/cover/simulation）、
/// 点击区域翻页（左 1/3 = 上一页 / 中 1/3 = 切换 UI / 右 1/3 = 下一页）、
/// 左侧 1/3 竖向拖拽亮度调节、内联设置面板（桌面右侧 ~360px / 移动底部 ~55%）、
/// 章节导航、进度自动保存。
///
/// 本地模式（Task O4.B.3）：传入 [localTextPath] 时进入本地模式，跳过在线源解析，
/// 直接读取本地文本文件（兼容 UTF-8 BOM / UTF-8 / latin1）。本地模式下隐藏切换章节 /
/// 切换源 / WebView / 书内搜索等在线专属 UI，保留翻页动画、TTS、书签笔记（用
/// [novelId] = `'local_${file.path.hashCode}'`）。调用方需将 [novelId] 设为
/// `'local_${file.path.hashCode}'`，[chapters] 传空列表。
class NovelReaderScreen extends StatefulWidget {
  final String novelId;
  final String title;
  final String sourceId;
  final List<Episode> chapters;
  final int initialChapterIndex;

  /// 本地模式：本地文本文件路径（跳过在线源解析，直接读取）。
  final String? localTextPath;

  /// 详情页 URL（用于收藏时透传，避免历史/收藏详情灰屏）。
  final String? detailUrl;

  /// 封面 URL（用于收藏时透传，避免收藏书架缺封面）。
  final String? coverUrl;

  const NovelReaderScreen({
    super.key,
    required this.novelId,
    required this.title,
    required this.sourceId,
    required this.chapters,
    this.initialChapterIndex = 0,
    this.localTextPath,
    this.detailUrl,
    this.coverUrl,
  });

  @override
  State<NovelReaderScreen> createState() => _NovelReaderScreenState();
}

/// 朗读睡眠定时选择（分钟；0 = 关闭）。
/// 预设 0/15/30/45/60/90 分钟，并提供「自定义」可输入任意分钟数
/// （满足「自定义朗读时间」需求）。返回选中的分钟数（null = 取消）。
/// 库级私有函数：既被 [_NovelReaderScreenState] 的朗读栏调用，
/// 也被 [_NovelInlineSettings] 设置面板调用（二者不在同一类层级）。
Future<int?> _pickSleepMinutes({
  required BuildContext context,
  required AppLocalizations l10n,
  required int current,
}) async {
  const List<int> presets = <int>[0, 15, 30, 45, 60, 90];
  bool customActive = current > 0 && !presets.contains(current);
  int? customValue = customActive ? current : null;
  final int? result = await showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setDialogState) => AlertDialog(
        title: Text(l10n.ttsSleepTimer),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final m in presets)
                RadioListTile<int>(
                  title: Text(
                      m == 0 ? l10n.ttsSleepOff : l10n.minuteUnit(m)),
                  value: m,
                  groupValue: customActive ? -1 : current,
                  onChanged: (v) => Navigator.of(ctx).pop(v),
                ),
              RadioListTile<int>(
                title: Text(l10n.ttsSleepCustom),
                value: -1,
                groupValue: customActive ? -1 : current,
                onChanged: (_) => setDialogState(() => customActive = true),
              ),
              if (customActive)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 12, right: 12),
                  child: TextField(
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.ttsSleepCustomMinutes,
                      suffixText: l10n.minuteUnit(1),
                    ),
                    onChanged: (v) =>
                        setDialogState(() => customValue = int.tryParse(v.trim())),
                  ),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              customActive ? (customValue ?? 0) : current,
            ),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    ),
  );
  return result;
}

class _NovelReaderScreenState extends State<NovelReaderScreen>
    with WidgetsBindingObserver {
  final NovelReaderPreferencesStore _store = NovelReaderPreferencesStore();
  final NovelProgressManager _progress = NovelProgressManager();
  final NovelBookmarkManager _bookmarks = NovelBookmarkManager();
  final ScreenBrightness _brightnessPlugin = ScreenBrightness();
  final GlobalKey<NovelAnimatedPageViewState> _pageKey =
      GlobalKey<NovelAnimatedPageViewState>();

  late NovelReaderPreferences _prefs;
  int _chapterIndex = 0;
  int _savedPage = 0;

  /// 网络拉取的原始段落（未做繁简转换）。
  List<String> _rawParagraphs = const <String>[];
  /// 实际渲染的段落（应用繁简转换后）。
  List<String> _paragraphs = const <String>[];
  NovelPaginationResult? _pagination;
  /// 当前 [_pagination] 对应的章节下标。用于检测「跨章后分页是否需刷新」：
  /// 相邻两章页数可能相同，仅比较页数长度无法触发刷新（会残留上一章的分页）。
  int _paginationChapterIndex = -1;
  /// 分页缓存签名：仅当影响分页的输入（正文版本 / 偏好版本 / 章节下标 / 可用
  /// 尺寸 / 系统字号缩放 / 文字方向 / 章节标题 / 书名）真正变化时才重新分页。
  /// 否则直接在 build（含翻页动画每帧触发的父层重建、_onPageChanged 触发的重建）
  /// 中复用缓存，避免整章重新分页造成的卡顿，也避免翻页动画被重型计算抢占而
  /// 看起来「无动画」。
  String? _paginationSig;
  /// 偏好版本号：任何阅读设置（字号/行距/段距/边距/字体/标题样式…）变化都自增，
  /// 作为分页缓存签名的一部分，确保改设置后分页立即刷新。
  int _prefsVersion = 0;
  bool _loading = true;
  String? _error;
  bool _isResolveError = false;

  /// 是否为本地文件模式（Task O4.B.3）。
  bool get _isLocalMode => widget.localTextPath != null;

  ScrollController? _scrollController;
  int _currentPage = 0;
  bool _uiVisible = false;
  int _contentVersion = 0;

  /// scroll 模式下当前滚动比例（0..1），用于同步底部进度滑条。
  double _scrollFraction = 0;

  // ─────────────────────── 亮度手势 ───────────────────────
  double _brightness = 0.5;
  double? _brightnessDragStart;
  double _brightnessDragDelta = 0;
  bool _showBrightnessIndicator = false;
  StreamSubscription<double>? _brightnessSub;
  bool _brightnessChangedByUs = false;

  // ─────────────────────── 页眉/页脚 time/battery ───────────────────────
  String _currentTime = '';
  int _batteryLevel = -1; // -1 = unknown
  late final Timer _timeTimer;
  StreamSubscription<BatteryState>? _batterySubscription;

  // ─────────────────────── 内联设置面板 ───────────────────────
  bool _showInlineSettings = false;

  // ─────────────────────── 设置搜索（常用置顶 + 过滤） ───────────────────────
  final TextEditingController _settingsSearchController = TextEditingController();

  // ─────────────────────── 自动翻页（M3.5.2） ───────────────────────
  Timer? _autoPageTimer;
  bool _autoPagePaused = false;

  /// 章节加载锁：防止快速连续按上一页/下一页触发并发章节切换
  /// （导致 _currentPage 被多次设为哨兵值 -1，累加后显示为 -2/-3 等负数）。
  bool _chapterLoading = false;

  // ─────────────────────── 收藏状态（P3.1） ───────────────────────
  bool _isFav = false;

  // ─────────────────────── TTS 朗读（P3.1） ───────────────────────
  final NovelTtsController _tts = NovelTtsController();

  // ─────────────────────── 笔记（P3.1） ───────────────────────
  final NovelNoteManager _notes = NovelNoteManager();

  MediaApiService get _service => context.read<MediaApiService>();
  SourceRepository get _repo => context.read<SourceRepository>();
  PluginConfig? get _source => _repo.getById(widget.sourceId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chapterIndex = widget.initialChapterIndex;
    _prefs = const NovelReaderPreferences();
    _initBrightness();
    _initTimeAndBattery();
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // TTS 后台朗读开关：关闭时应用进入后台即暂停朗读；
    // 开启时保持朗读（wakelock_plus 已持有唤醒锁）。
    if (state == AppLifecycleState.paused &&
        !_tts.backgroundMode &&
        _tts.isPlaying) {
      _tts.pause();
      if (mounted) setState(() {});
    }
  }

  void _initTimeAndBattery() {
    _updateTime();
    _timeTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _updateTime(),
    );
    _fetchBatteryLevel();
    _batterySubscription = Battery().onBatteryStateChanged.listen(
      (_) => _fetchBatteryLevel(),
    );
  }

  void _updateTime() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    if (mounted) setState(() => _currentTime = '$hour:$minute');
  }

  // battery_plus 6.x: BatteryState is an enum without a level field, so we
  // refetch the level via [Battery.batteryLevel] whenever the state changes.
  Future<void> _fetchBatteryLevel() async {
    try {
      final level = await Battery().batteryLevel;
      if (mounted) setState(() => _batteryLevel = level);
    } on Object {
      // Some platforms may not support battery level; leave as -1.
    }
  }

  Future<void> _initBrightness() async {
    try {
      _brightness = await _brightnessPlugin.current;
    } on Object {
      _brightness = 0.5;
    }
    _brightnessSub = _brightnessPlugin.onCurrentBrightnessChanged.listen(
      (double value) {
        if (!_brightnessChangedByUs && mounted) {
          setState(() => _brightness = value);
        }
        _brightnessChangedByUs = false;
      },
      onError: (Object _) {},
    );
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    final defaults = await ReaderDefaultSettingsStore().load();
    _prefs = (await _store.get(widget.novelId))
        .mergedWith(defaults.toNovelReaderPreferences());
    // 迁移：自动翻页不应在进入阅读器时默认启动。
    // 之前误将默认值改为 30 导致已持久化数据残留非零值；
    // 无论具体数值是多少，一律重置为 0（关闭），由用户手动开启。
    if (_prefs.autoPageInterval > 0) {
      _prefs = _prefs.copyWith(autoPageInterval: 0);
      await _store.save(widget.novelId, _prefs);
    }
    // 重新注册自定义字体文件（正文 / 标题），否则重启后字体不生效。
    await _loadCustomFontsIfNeeded();
    final saved = await _progress.get(widget.novelId);
    // 本地模式只有单「章」（整个文件），saved.chapterIndex 恒为 0；
    // 在线模式需校验 chapterIndex 落在 chapters 范围内。
    if (saved != null &&
        (_isLocalMode || saved.chapterIndex < widget.chapters.length)) {
      _chapterIndex = saved.chapterIndex;
      _savedPage = saved.currentPage;
    }
    _refreshFavorite();
    await _notes.init();
    if (mounted) setState(() {});
    if (_isLocalMode) {
      await _loadLocalText(restorePage: _savedPage);
    } else {
      await _loadChapter(_chapterIndex, restorePage: _savedPage);
    }
  }

  /// 若用户选择了自定义字体文件（正文 / 标题），在启动与翻章前重新注册字族，
  /// 否则重启后字体不生效。已加载过的字族会被 [NovelReaderPreferences] 跳过。
  Future<void> _loadCustomFontsIfNeeded() async {
    if (_prefs.customFontPath != null) {
      await NovelReaderPreferences.loadCustomFont(
        NovelReaderPreferences.customLoadedFontFamily,
        _prefs.customFontPath!,
      );
    }
    if (_prefs.titleCustomFontPath != null) {
      await NovelReaderPreferences.loadCustomFont(
        NovelReaderPreferences.customLoadedTitleFontFamily,
        _prefs.titleCustomFontPath!,
      );
    }
  }

  /// 本地模式读取文本文件并分页（参考 local_media_viewer._readTextFile）。
  Future<void> _loadLocalText({int restorePage = 0}) async {
    if (mounted) setState(() => _loading = true);
    _stopAutoPage();
    try {
      final text = await _readTextFile(widget.localTextPath!);
      if (!mounted) return;
      // 按换行分Paragraphs，过滤纯空行（保留含空格的段落）。
      final paragraphs = text
          .split(RegExp(r'\r?\n'))
          .where((s) => s.trim().isNotEmpty)
          .toList(growable: false);
      if (paragraphs.isEmpty) {
        setState(() {
          _rawParagraphs = const <String>[];
          _paragraphs = const <String>[];
          _loading = false;
          _error = AppLocalizations.of(context).localFileLoadFailed;
        });
        return;
      }
      setState(() {
        _rawParagraphs = paragraphs;
        _paragraphs = _applyConvert(paragraphs);
        _loading = false;
        _error = null;
        _contentVersion++;
      });
      _setupControllers(restorePage: restorePage);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _isResolveError = false;
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// 读取文本文件，兼容 UTF-8 BOM / UTF-8 / latin1（GBK 等双字节可能为乱码）。
  Future<String> _readTextFile(String path) async {
    final bytes = await File(path).readAsBytes();
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  /// 刷新收藏状态。
  void _refreshFavorite() {
    final fav = context.read<FavoritesManager>();
    _isFav = fav.isFavorite(widget.novelId, SourceType.novelSource);
  }

  /// 切换收藏。
  Future<void> _toggleFavorite() async {
    final l10n = AppLocalizations.of(context);
    final fav = context.read<FavoritesManager>();
    final wasFavorite = _isFav;
    final item = MediaItem(
      id: widget.novelId,
      title: widget.title,
      sourceId: widget.sourceId,
      sourceType: SourceType.novelSource,
      detailUrl: widget.detailUrl,
      coverUrl: widget.coverUrl,
    );
    await fav.toggleFavorite(item);
    if (mounted) {
      setState(() => _isFav = !wasFavorite);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(wasFavorite ? l10n.favoriteRemoved : l10n.favoriteAdded),
        ),
      );
    }
  }

  /// 清除当前小说的阅读进度（三点菜单入口）。
  Future<void> _clearReadingProgress() async {
    final l10n = AppLocalizations.of(context);
    await _progress.clear(widget.novelId);
    if (mounted) {
      setState(() {
        _chapterIndex = 0;
        _currentPage = 0;
        _savedPage = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.readingProgressCleared)),
      );
      if (_isLocalMode) {
        await _loadLocalText();
      } else {
        await _loadChapter(_chapterIndex);
      }
    }
  }

  /// 重载当前章节（三点菜单入口）。
  Future<void> _reloadChapter() async {
    await _loadChapter(_chapterIndex);
  }

  /// 切换 TTS 朗读（三点菜单入口）。
  Future<void> _toggleTts() async {
    if (_tts.isPlaying) {
      await _tts.stop();
    } else if (_tts.isPaused) {
      await _tts.resume();
    } else {
      _tts.setBackground(_prefs.ttsBackground);
      await _tts.setRate(_prefs.ttsSpeechRate);
      await _tts.speak(_paragraphs, sleepTimer: _prefs.ttsSleepTimer);
    }
    if (mounted) setState(() {});
  }

  /// 显示笔记列表（三点菜单入口）。
  Future<void> _showNoteList() async {
    final notes = await _notes.notesForNovel(widget.novelId);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return SafeArea(
          child: notes.isEmpty
              ? Center(child: Text(l10n.noNotes))
              : ListView.builder(
                  itemCount: notes.length,
                  itemBuilder: (_, i) {
                    final n = notes[i];
                    return ListTile(
                      title: Text(
                        '${l10n.chapterN(n.chapterIndex + 1)} · ${n.chapterTitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        n.selectedText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          _notes.removeNote(n.id);
                          Navigator.of(ctx).pop();
                          _showNoteList();
                        },
                      ),
                      onTap: () {
                        if (n.chapterIndex != _chapterIndex) {
                          _chapterIndex = n.chapterIndex;
                          _loadChapter(_chapterIndex);
                        }
                        Navigator.of(ctx).pop();
                      },
                    );
                  },
                ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeTimer.cancel();
    _batterySubscription?.cancel();
    _autoPageTimer?.cancel();
    _scrollController?.dispose();
    _brightnessSub?.cancel();
    _brightnessPlugin.resetScreenBrightness();
    _tts.dispose();
    _settingsSearchController.dispose();
    super.dispose();
  }

  // ─────────────────────── 自动翻页（M3.5.2） ───────────────────────

  /// 是否启用了自动翻页（间隔 > 0 即视为启用）。
  bool get _autoPageEnabled => _prefs.autoPageInterval > 0;

  /// 根据当前偏好与暂停状态启停定时器。
  void _applyAutoPage() {
    _autoPageTimer?.cancel();
    _autoPageTimer = null;
    if (!_autoPageEnabled || _autoPagePaused) return;
    if (_paragraphs.isEmpty) return;
    final interval = _prefs.autoPageInterval;
    _autoPageTimer = Timer.periodic(
      Duration(seconds: interval),
      (_) => _goNextPage(),
    );
  }

  /// 完全停止自动翻页（切章 / dispose 时调用）。
  void _stopAutoPage() {
    _autoPageTimer?.cancel();
    _autoPageTimer = null;
  }

  /// 暂停 / 恢复自动翻页（运行时切换，不影响偏好）。
  void _toggleAutoPagePause() {
    setState(() => _autoPagePaused = !_autoPagePaused);
    _applyAutoPage();
  }

  // ─────────────────────── 书签（M3.5.4） ───────────────────────

  /// 在当前章节+页添加书签（可附带备注，P1-5）。
  Future<void> _addBookmark() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    // 本地模式无 chapters，用占位 chapterId/title 保存书签。
    final String chapterId;
    final String chapterTitle;
    final String chapterLabel;
    if (_isLocalMode) {
      chapterId = 'local';
      chapterTitle = '';
      chapterLabel = l10n.localFileLabel;
    } else {
      if (widget.chapters.isEmpty) return;
      final chapter = widget.chapters[_chapterIndex];
      chapterId = chapter.id;
      chapterTitle = chapter.title;
      chapterLabel = l10n.novelChapterProgress(
        chapter.number ?? (_chapterIndex + 1),
        widget.chapters.length,
      );
    }
    final TextEditingController noteCtl = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(l10n.addBookmark),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                chapterLabel,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: AppTokens.spaceSm),
              TextField(
                controller: noteCtl,
                decoration: InputDecoration(
                  labelText: l10n.bookmarkNoteHint,
                  hintText: l10n.bookmarkNoteHint,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.confirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      noteCtl.dispose();
      return;
    }
    final String note = noteCtl.text.trim();
    noteCtl.dispose();
    final bm = NovelBookmark(
      novelId: widget.novelId,
      chapterIndex: _chapterIndex,
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      page: _currentPage,
      note: note.isEmpty ? null : note,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _bookmarks.add(bm);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.bookmarkAdded)),
    );
  }

  /// 打开书签列表 sheet；选中后跳转，长按删除。
  Future<void> _showBookmarkList() async {
    final list = await _bookmarks.listFor(widget.novelId);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.noBookmarks)),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceMd,
                    vertical: AppTokens.spaceSm,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.bookmarkList,
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (BuildContext c, int i) {
                      final bm = list[i];
                      final String pageSub = l10n.pageIndicator(
                          bm.page + 1, _pagination?.pages.length ?? 1);
                      final List<String> subParts = <String>[pageSub];
                      if (bm.note != null && bm.note!.isNotEmpty) {
                        subParts.add(bm.note!);
                      }
                      return ListTile(
                        leading: const Icon(Icons.bookmark),
                        title: Text(bm.chapterTitle.isEmpty
                            ? l10n.novelChapterN(bm.chapterIndex + 1)
                            : bm.chapterTitle),
                        subtitle: Text(
                          subParts.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: l10n.deleteBookmark,
                          onPressed: () async {
                            await _bookmarks.remove(bm.key);
                            if (!ctx.mounted) return;
                            Navigator.of(ctx).pop();
                            _showBookmarkList();
                          },
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _jumpToBookmark(bm);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 跳转到指定书签。
  void _jumpToBookmark(NovelBookmark bm) {
    // 本地模式只有单「章」，chapterIndex 恒为 0；仅校验非负即可。
    if (_isLocalMode) {
      if (bm.chapterIndex < 0) return;
      if (_prefs.pageAnimation.isScroll) {
        final sc = _scrollController;
        if (sc != null && sc.hasClients) {
          final h = sc.position.viewportDimension;
          sc.jumpTo((bm.page * h).clamp(0.0, sc.position.maxScrollExtent));
        }
      } else {
        _pageKey.currentState?.jumpToPage(bm.page);
      }
      setState(() => _currentPage = bm.page);
      return;
    }
    if (bm.chapterIndex < 0 || bm.chapterIndex >= widget.chapters.length) {
      return;
    }
    if (bm.chapterIndex == _chapterIndex) {
      // 同章节：仅切页。
      if (_prefs.pageAnimation.isScroll) {
        final sc = _scrollController;
        if (sc != null && sc.hasClients) {
          final h = sc.position.viewportDimension;
          sc.jumpTo((bm.page * h).clamp(0.0, sc.position.maxScrollExtent));
        }
      } else {
        _pageKey.currentState?.jumpToPage(bm.page);
      }
      setState(() => _currentPage = bm.page);
      return;
    }
    _chapterIndex = bm.chapterIndex;
    _loadChapter(_chapterIndex, restorePage: bm.page);
  }

  // ─────────────────────── 数据加载 ───────────────────────

  Future<void> _loadChapter(int index, {int restorePage = 0}) async {
    // 防并发：章节加载期间忽略新的切章请求（快速连按上一页/下一页时）。
    if (_chapterLoading) return;
    _chapterLoading = true;
    if (mounted) setState(() => _loading = true);
    // 切换章节时必须取消自动翻页定时器（项目约束）。
    _stopAutoPage();
    try {
      final source = _repo.getById(widget.sourceId);
      if (source == null) throw Exception('source not found: ${widget.sourceId}');
      final chapter = widget.chapters[index];
      final paragraphs = await _service.fetchNovelContent(
        source,
        novelId: widget.novelId,
        chapterUrl: chapter.url,
      );
      if (!mounted) { _chapterLoading = false; return; }
      setState(() {
        _rawParagraphs = paragraphs;
        _paragraphs = _applyConvert(paragraphs);
        _loading = false;
        _error = null;
        _contentVersion++;
      });
      _setupControllers(restorePage: restorePage);
      // 不在此处对哨兵值 -1 调用 _saveProgress（会存入非法页码）。
      // 合法的页码会在 _buildReader 哨兵校正后，由后续翻页/渲染自动保存；
      // 若 restorePage ≥ 0 则正常记录进度。
      if (restorePage >= 0) _saveProgress(restorePage);
    } on SourceResolveException catch (e) {
      if (mounted) {
        setState(() {
          _isResolveError = true;
          _error = e.message;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _isResolveError = false;
          _error = e.toString();
          _loading = false;
        });
      }
    }
    _chapterLoading = false;
  }

  /// 按当前繁简转换模式转换段落列表。
  List<String> _applyConvert(List<String> input) {
    final mode = ChineseConvertMode.fromString(_prefs.chineseConvert);
    return convertChineseList(input, mode);
  }

  /// 重新应用繁简转换（在 [NovelReaderPreferences.chineseConvert] 变更后调用）。
  void _refreshConvert() {
    final next = _applyConvert(_rawParagraphs);
    if (next.length == _paragraphs.length) {
      bool same = true;
      for (int i = 0; i < next.length; i++) {
        if (next[i] != _paragraphs[i]) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    setState(() {
      _paragraphs = next;
      _contentVersion++;
    });
    _setupControllers(restorePage: _currentPage);
  }

  void _setupControllers({int restorePage = 0}) {
    _scrollController?.dispose();
    _scrollController = null;
    _currentPage = restorePage;
    _scrollFraction = 0;

    if (_prefs.pageAnimation.isScroll) {
      _scrollController = ScrollController();
      _scrollController!.addListener(_onScrollChanged);
    }
    // paged 模式由 NovelAnimatedPageView 内部管理页状态；
    // _contentVersion 变更会触发 widget 重建并使用 initialPage。
    if (mounted) setState(() {});
  }

  /// scroll 模式滚动监听：更新 [_scrollFraction] 以同步底部进度滑条。
  /// 仅在 UI 可见时刷新（隐藏时无需重绘）。
  void _onScrollChanged() {
    final sc = _scrollController;
    if (sc == null || !sc.hasClients) return;
    final max = sc.position.maxScrollExtent;
    final frac = max > 0 ? (sc.offset / max).clamp(0.0, 1.0) : 0.0;
    if ((frac - _scrollFraction).abs() < 0.005) return;
    _scrollFraction = frac;
    if (mounted && _uiVisible) setState(() {});
  }

  void _onPageChanged(int idx) {
    // 防御：page view 在极端时序下可能回调负数（如拖拽越界），
    // 直接丢弃非法值，避免 _currentPage 被污染为 -1/-2/-3。
    if (idx < 0) return;
    if (idx == _currentPage) return;
    _currentPage = idx;
    _saveProgress(idx);
    // 翻页后刷新底部进度条 / 页码（底部栏位于 ListenableBuilder(_tts) 内，
    // 翻页不经由 _tts 通知，必须主动 setState 才能实时更新进度。
    if (mounted) setState(() {});
  }

  void _saveProgress(int page) {
    // 本地模式无 chapters，用占位 chapterId 保存进度。
    final String chapterId;
    if (_isLocalMode) {
      chapterId = 'local';
    } else {
      if (widget.chapters.isEmpty) return;
      chapterId = widget.chapters[_chapterIndex].id;
    }
    _progress.save(
      widget.novelId,
      chapterId,
      page,
      _chapterIndex,
      totalChapters: _isLocalMode ? null : widget.chapters.length,
    );
    // 更新收藏条目的 lastRead 时间戳（P8.1.3 §廿一 收藏切换不丢 lastRead）
    try {
      context.read<FavoritesManager>().updateLastRead(
            widget.novelId,
            SourceType.novelSource,
          );
    } catch (_) {
      // FavoritesManager 不可用时静默忽略。
    }
  }

  // ─────────────────────── 导航 ───────────────────────

  void _goNextPage() {
    if (_loading || _chapterLoading) return;
    if (_prefs.pageAnimation.isScroll) {
      _scrollByPage(1);
      return;
    }
    _pageKey.currentState?.nextPage();
  }

  void _goPrevPage() {
    if (_loading || _chapterLoading) return;
    if (_prefs.pageAnimation.isScroll) {
      _scrollByPage(-1);
      return;
    }
    _pageKey.currentState?.previousPage();
  }

  void _scrollByPage(int dir) {
    final sc = _scrollController;
    if (sc == null || !sc.hasClients) return;
    final h = sc.position.viewportDimension;
    final target =
        (sc.offset + dir * h).clamp(0.0, sc.position.maxScrollExtent).toDouble();
    sc.animateTo(target, duration: AppTokens.durFast, curve: Curves.easeInOut);
  }

  void _goNextChapter() {
    if (_chapterIndex < widget.chapters.length - 1) {
      _chapterIndex++;
      _loadChapter(_chapterIndex);
    }
  }

  void _goPrevChapter({bool toLastPage = false}) {
    if (_chapterIndex > 0) {
      _chapterIndex--;
      _loadChapter(_chapterIndex, restorePage: toLastPage ? -1 : 0);
    }
  }

  /// TTS 模式下点击某一段落：跳转到该段落开始朗读。
  void _onParagraphTapped(int globalParagraphIndex) {
    if (_paragraphs.isEmpty) return;
    final clamped = globalParagraphIndex.clamp(0, _paragraphs.length - 1);
    // 找到该段落属于哪一页（通过分页数据）。
    final pages = _pagination?.pages;
    if (pages != null) {
      for (int i = 0; i < pages.length; i++) {
        if (pages[i].any((NovelLine l) => l.paragraphIndex == clamped)) {
          if (i != _currentPage) {
            _pageKey.currentState?.jumpToPage(i);
          }
          break;
        }
      }
    }
    // 从点击的段落重新开始 TTS 朗读。
    if (_tts.isPlaying || _tts.isPaused) {
      _tts.speak(_paragraphs, startIndex: clamped,
          sleepTimer: _prefs.ttsSleepTimer);
    } else {
      // TTS 未启动时，直接从该段开始朗读。
      _tts.setBackground(_prefs.ttsBackground);
      _tts.setRate(_prefs.ttsSpeechRate);
      _tts.speak(_paragraphs, startIndex: clamped,
          sleepTimer: _prefs.ttsSleepTimer);
    }
    setState(() {});
  }

  void _toggleUi() {
    setState(() {
      _uiVisible = !_uiVisible;
      if (!_uiVisible) _showInlineSettings = false;
    });
  }

  void _toggleInlineSettings() {
    setState(() => _showInlineSettings = !_showInlineSettings);
  }

  Future<void> _onPrefsChanged(NovelReaderPreferences next) async {
    final animationChanged = next.pageAnimation != _prefs.pageAnimation;
    final convertChanged =
        next.chineseConvert != _prefs.chineseConvert;
    final autoPageChanged =
        next.autoPageInterval != _prefs.autoPageInterval;
    _prefs = next;
    // 任何阅读设置变化都使分页缓存失效（字号/行距/段距/边距/字体等不会 bump
    // _contentVersion，但会影响分页高度，必须靠 _prefsVersion 触发重新分页）。
    _prefsVersion++;
    await _store.save(widget.novelId, next);
    if (convertChanged && _rawParagraphs.isNotEmpty) {
      _refreshConvert();
    } else if (animationChanged && _paragraphs.isNotEmpty) {
      _contentVersion++;
      _setupControllers(restorePage: _currentPage);
    } else {
      if (mounted) setState(() {});
    }
    if (autoPageChanged) {
      // 间隔变更后若之前已暂停，保持暂停；否则按新间隔重启。
      _applyAutoPage();
    }
  }

  // ─────────────────────── 点击区域（FR-4.2 五布局） ───────────────────────

  void _onTapUp(TapUpDetails details, Size size) {
    if (_showInlineSettings) {
      _toggleInlineSettings();
      return;
    }
    final action = TapZoneResolver.resolve(
      layout: _prefs.tapZoneLayout,
      invert: _prefs.tapZoneInvert,
      isVertical: _prefs.pageAnimation.isScroll,
      pos: details.localPosition,
      size: size,
    );
    switch (action) {
      case TapZoneAction.toggle:
        _toggleUi();
      case TapZoneAction.prev:
        _goPrevPage();
      case TapZoneAction.next:
        _goNextPage();
    }
  }

  /// 显示点按区域预览弹窗：半透明展示当前布局的各区域及对应操作。
  void _showTapZonePreview(AppLocalizations l10n) {
    final layout = _prefs.tapZoneLayout;
    final invert = _prefs.tapZoneInvert;
    final isVertical = _prefs.pageAnimation.isScroll;

    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx2, Function(void Function()) setDialogState) {
            return AlertDialog(
              title: Text(l10n.tapZonePreview),
              content: SizedBox(
                width: 280,
                height: 420,
                child: _TapZonePreviewOverlay(
                  layout: layout,
                  invert: invert,
                  isVertical: isVertical,
                  l10n: l10n,
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─────────────────────── 亮度手势 ───────────────────────

  void _onBrightnessDragStart(DragStartDetails d) {
    final w = context.size?.width ?? MediaQuery.sizeOf(context).width;
    if (d.globalPosition.dx >= w / 3) return;
    _brightnessDragStart = _brightness;
    _brightnessDragDelta = 0;
    setState(() => _showBrightnessIndicator = true);
  }

  void _onBrightnessDragUpdate(DragUpdateDetails d) {
    if (_brightnessDragStart == null) return;
    _brightnessDragDelta += d.delta.dy;
    final h = MediaQuery.sizeOf(context).height;
    final next =
        (_brightnessDragStart! + (-_brightnessDragDelta / h)).clamp(0.0, 1.0);
    _setBrightness(next);
  }

  void _onBrightnessDragEnd(DragEndDetails d) {
    _brightnessDragStart = null;
    _brightnessDragDelta = 0;
    if (mounted) setState(() => _showBrightnessIndicator = false);
  }

  Future<void> _setBrightness(double value) async {
    _brightness = value;
    _brightnessChangedByUs = true;
    if (mounted) setState(() {});
    try {
      await _brightnessPlugin.setScreenBrightness(value);
    } on Object {
      // 部分平台可能不支持亮度调节，静默忽略。
    }
  }

  // ─────────────────────── 构建 ───────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _prefs.resolveBackgroundColor(isDark);
    final textColor = _prefs.resolveTextColor(bg);
    final l10n = AppLocalizations.of(context);

    // TTS 状态变化时重建 Stack：TTS 激活时底部栏内嵌朗读控件（避免重叠）。
    return Scaffold(
      backgroundColor: bg,
      body: ListenableBuilder(
        listenable: _tts,
        builder: (BuildContext context, Widget? _) {
          final ttsActive = _tts.state != NovelTtsState.stopped;
          return Stack(
            children: <Widget>[
              _buildContent(l10n, bg, textColor),
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
                  child: _buildBottomBar(l10n, bg, ttsActive: ttsActive),
                ),
              if (_showBrightnessIndicator) _buildBrightnessIndicator(l10n),
              if (_showInlineSettings)
                _buildInlineSettings(l10n, bg, textColor),
            ],
          );
        },
      ),
    );
  }

  /// TTS 内联控件（嵌入底部栏第二行，替代独立 TTS 栏，避免重叠）。
  /// 包含：上一句/暂停-停止/下一句/睡眠/后台 + 语速滑块。
  Widget _buildTtsControlsInline(AppLocalizations l10n, Color bg) {
    final remaining = _tts.sleepRemaining;
    final rate = _tts.rate;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.skip_previous, size: 20),
              tooltip: l10n.ttsPrevSentence,
              visualDensity: VisualDensity.compact,
              onPressed: () => _tts.prev(),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: Icon(_tts.isPlaying ? Icons.pause : Icons.play_arrow, size: 20),
              tooltip: l10n.ttsPauseOrResume,
              visualDensity: VisualDensity.compact,
              onPressed: () {
                if (_tts.isPlaying) {
                  _tts.pause();
                } else {
                  _tts.resume();
                }
              },
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: const Icon(Icons.stop, size: 20),
              tooltip: l10n.ttsExit,
              visualDensity: VisualDensity.compact,
              onPressed: () => _tts.stop(),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next, size: 20),
              tooltip: l10n.ttsNextSentence,
              visualDensity: VisualDensity.compact,
              onPressed: () => _tts.next(),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: const Icon(Icons.timer_outlined, size: 18),
              tooltip: l10n.ttsSleepTimer,
              visualDensity: VisualDensity.compact,
              onPressed: _showSleepTimerPicker,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: Icon(_tts.backgroundMode ? Icons.headset : Icons.headset_off, size: 18),
              tooltip: l10n.novelTtsBackground,
              visualDensity: VisualDensity.compact,
              onPressed: () {
                final next = !_tts.backgroundMode;
                _tts.setBackground(next);
                _onPrefsChanged(_prefs.copyWith(ttsBackground: next));
              },
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            const Icon(Icons.speed, size: 16),
            const SizedBox(width: AppTokens.spaceXs),
            Expanded(
              child: Slider(
                value: rate,
                min: 0.5,
                max: 2.0,
                divisions: 30,
                onChanged: (v) => _tts.setRate(v),
              ),
            ),
            SizedBox(
              width: 38,
              child: Text(
                '${rate.toStringAsFixed(1)}x',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
        if (remaining != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l10n.ttsSleepRemaining(
                remaining.inMinutes,
                remaining.inSeconds % 60,
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  /// 睡眠定时选择（#5）：0 关闭 / 预设 / 自定义分钟。朗读控制栏入口。
  Future<void> _showSleepTimerPicker() async {
    final l10n = AppLocalizations.of(context);
    final picked = await _pickSleepMinutes(
      context: context,
      l10n: l10n,
      current: _tts.sleepRemaining?.inMinutes ?? 0,
    );
    if (picked != null && mounted) {
      _tts.startSleepTimer(picked);
      // 与设置面板一致：写回 _prefs（持久化），避免重启后丢失。
      _onPrefsChanged(_prefs.copyWith(ttsSleepTimer: picked));
    }
  }

  Widget _buildContent(AppLocalizations l10n, Color bg, Color textColor) {
    if (_loading) {
      return const Center(child: AppLoadingIndicator());
    }
    if (_error != null) {
      return _CenterMessage(
        icon: Icons.error_outline,
        message: _isLocalMode
            ? l10n.localFileLoadFailed
            : (_isResolveError ? l10n.resolveFailed(_error!) : l10n.loadFailed),
        onRetry: _isLocalMode
            ? () => _loadLocalText(restorePage: _currentPage)
            : () => _loadChapter(_chapterIndex, restorePage: _currentPage),
      );
    }
    if (_paragraphs.isEmpty) {
      return _CenterMessage(icon: Icons.article_outlined, message: l10n.noContent);
    }
    return _buildReader(bg, textColor);
  }

  Widget _buildReader(Color bg, Color textColor) {
    final String chapterTitleForBody = widget.chapters.isEmpty
        ? ''
        : widget.chapters[_chapterIndex].title;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // 分页缓存签名：仅在这些输入真正变化时重新分页，否则复用上一次结果。
        // 关键：翻页动画每帧只触发 NovelAnimatedPageView 自身重建（其 State 内的
        // setState），不会重建到这里；但 _onPageChanged → setState 与
        // FavoritesManager 通知都会触发本 reader 重建 → 若每次都重新分页整章，
        // 会在翻页瞬间产生明显卡顿，并使翻页动画被重型计算抢占、看起来「无动画」。
        final scaler = MediaQuery.textScalerOf(context);
        final dir = Directionality.of(context);
        final sig =
            '$_contentVersion|$_prefsVersion|$_chapterIndex|${w.round()}x${h.round()}|$scaler|$dir|$chapterTitleForBody|${widget.title}';
        final bool sigChanged = _paginationSig != sig;
        final int prevChapterIndex = _paginationChapterIndex;
        if (_pagination == null || sigChanged) {
          _pagination = NovelPaginator.paginate(
            paragraphs: _paragraphs,
            constraints: constraints,
            prefs: _prefs,
            context: context,
            chapterTitle: chapterTitleForBody,
            bookName: widget.title,
          );
          _paginationSig = sig;
          _paginationChapterIndex = _chapterIndex;
        }

        // 检测分页结果是否变化（跨章/改偏好/旋转屏幕时变化）。
        // _pagination 可能在本帧的 layout 阶段才被 LayoutBuilder 赋值，
        // 而 _buildProgressSlider 已在 build 阶段读取了旧值。需要 schedule 一帧
        // 让进度条重建以获取最新分页数据（详见 _loadChapter 时序注释）。
        // 注意：相邻两章页数可能相同，仅比较页数长度不够，必须同时检测章节下标变化，
        // 否则会残留上一章的分页（总页数/当前页显示正确但内容错位）。
        // 这里用「缓存前的旧章节下标」判断跨章，并用 sigChanged 覆盖「同章但
        // 改了字号/边距等导致分页变化」的情况，确保进度条/分页始终与最新输入一致。
        final chapterChanged = prevChapterIndex != _chapterIndex;
        final paginationChanged = chapterChanged || sigChanged;

        if (_pagination!.isEmpty) {
          return _CenterMessage(
            icon: Icons.article_outlined,
            message: AppLocalizations.of(context).noContent,
          );
        }

        final pages = _pagination!.pages;
        // 哨兵值：restorePage=-1 表示「恢复到本章最后一页」（上一页越界时）。
        if (_currentPage < 0 && pages.isNotEmpty) {
          _currentPage = pages.length - 1;
        }
        // 同步校正：如果当前页超出范围（比如跨章后 page view 通过
        // didUpdateWidget 重置了 internal index 但未回调 onPageChanged），
        // 强制对齐到合法范围。
        if (_currentPage >= pages.length && pages.isNotEmpty) {
          _currentPage = pages.length - 1;
        }
        final chapterTitle = widget.chapters.isEmpty
            ? ''
            : widget.chapters[_chapterIndex].title;

        // 分页数据变化时 schedule 一帧刷新，让底部进度条获取最新的
        // total/pages/currentPage（LayoutBuilder 的 builder 在 layout 阶段执行，
        // 晚于 _buildProgressSlider 的 build 阶段读取）。
        if (paginationChanged && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }

        return NovelAnimatedPageView(
          key: _pageKey,
          contentVersion: _contentVersion,
          animation: _prefs.pageAnimation,
          pageCount: pages.length,
          initialPage: _currentPage,
          background: bg,
          pageBuilder: (BuildContext ctx, int pageIndex) {
            final page = pages[pageIndex];
            return _NovelPageWidget(
              lines: page,
              prefs: _prefs,
              bg: bg,
              textColor: textColor,
              animation: _prefs.pageAnimation,
              chapterTitle: chapterTitle,
              bookName: widget.title,
              pageIndex: pageIndex,
              totalPages: pages.length,
              time: _currentTime,
              batteryLevel: _batteryLevel,
              headerCenter: _prefs.headerCenter,
              footerCenter: _prefs.footerCenter,
              headerFooterColor: _prefs.headerFooterColor,
              headerFooterMargin: _prefs.headerFooterMargin,
              ttsCurrentIndex: _tts.currentIndex,
              ttsActive: _tts.state != NovelTtsState.stopped,
              onParagraphTap: _onParagraphTapped,
            );
          },
          scrollBuilder: _prefs.pageAnimation.isScroll
              ? (BuildContext ctx) => _buildScrollContent(bg, textColor)
              : null,
          onPageChanged: _onPageChanged,
          onRequestNextChapter: _goNextChapter,
          onRequestPrevChapter: () => _goPrevChapter(toLastPage: true),
          onTapUp: _onTapUp,
          onVerticalDragStart: _onBrightnessDragStart,
          onVerticalDragUpdate: _onBrightnessDragUpdate,
          onVerticalDragEnd: _onBrightnessDragEnd,
        );
      },
    );
  }

  Widget _buildScrollContent(Color bg, Color textColor) {
    final sc = _scrollController;
    if (sc == null) return const SizedBox.shrink();

    final String scrollChapterTitle = widget.chapters.isEmpty
        ? ''
        : widget.chapters[_chapterIndex].title;
    final bool showTitle = _prefs.showChapterTitleInBody &&
        scrollChapterTitle.isNotEmpty;
    // 显示标题时列表首项为标题，其后为正文段落。
    final int itemCount = _paragraphs.length + (showTitle ? 1 : 0);

    return ListView.builder(
      controller: sc,
      padding: EdgeInsets.symmetric(
        horizontal: _prefs.margin,
        vertical: _prefs.margin,
      ),
      itemCount: itemCount,
      itemBuilder: (BuildContext ctx, int i) {
        if (showTitle && i == 0) {
          return _buildChapterTitleWidget(
            _prefs,
            scrollChapterTitle,
            widget.title,
          );
        }
        final int paraIdx = showTitle ? i - 1 : i;
        return Padding(
          padding: EdgeInsets.only(bottom: _prefs.paragraphSpacing),
          child: Text(
            _paragraphs[paraIdx],
            style: _prefs.resolveBodyTextStyle(textColor),
          ),
        );
      },
    );
  }

  /// 顶栏标题（P1-6）：两行——书名 + 「第N章/共M章 · 章名」。
  /// 本地模式无章节列表，第二行显示「本地文件」。
  Widget _buildTopBarTitle(AppLocalizations l10n, Episode? chapter) {
    const TextStyle titleStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 15,
    );
    final TextStyle subStyle = TextStyle(
      fontSize: 11.5,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    if (_isLocalMode) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
          Text(
            l10n.localFileLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: subStyle,
          ),
        ],
      );
    }
    final int total = widget.chapters.length;
    final int current = chapter?.number ?? (_chapterIndex + 1);
    final String chapterName = chapter?.title ?? '';
    final String sub = total > 0
        ? '${l10n.novelChapterProgress(current, total)}'
            '${chapterName.isNotEmpty ? ' · $chapterName' : ''}'
        : chapterName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        if (sub.isNotEmpty)
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: subStyle,
          ),
      ],
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
              child: _buildTopBarTitle(l10n, chapter),
            ),
            // 收藏按钮（P3.1）
            IconButton(
              icon: Icon(_isFav ? Icons.favorite : Icons.favorite_border),
              tooltip: l10n.favorite,
              onPressed: _toggleFavorite,
            ),
            // 重载本章（在线重载当前章节；本地重新读取文本）
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.reloadChapter,
              onPressed: () {
                if (_isLocalMode) {
                  _loadLocalText();
                } else {
                  _reloadChapter();
                }
              },
            ),
            // 清除阅读记录（回到本书开头）
            IconButton(
              icon: const Icon(Icons.cleaning_services_outlined),
              tooltip: l10n.clearReadingProgress,
              onPressed: _clearReadingProgress,
            ),
            // 其余工具（目录 / 自动翻页 / 设置 / 书签 / 夜间 / 搜索）已移至底部工具栏，
            // 可在「配置底部按钮」中自定义；顶栏仅保留返回 / 标题 / 收藏 / 更多。
            // 三点菜单（P3.1）：WebView 打开章节 / 浏览器打开 / 分享 / 书签列表 /
            // 配置底部工具栏 / 笔记 / 翻页动画
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: l10n.moreActions,
              onSelected: (String value) {
                switch (value) {
                  case 'webview':
                    if (absoluteChapterUrl != null) {
                      openInAppBrowser(context, absoluteChapterUrl);
                    }
                  case 'browser':
                    if (absoluteChapterUrl != null) {
                      openInExternalBrowser(context, absoluteChapterUrl);
                    }
                  case 'share':
                    if (absoluteChapterUrl != null) {
                      shareContent(
                        context,
                        '${widget.title} - ${chapter?.title ?? ''}',
                        absoluteChapterUrl,
                      );
                    }
                  case 'bookmarkList':
                    _showBookmarkList();
                  case 'configureBottomToolbar':
                    _showBottomToolbarConfig();
                  case 'notes':
                    _showNoteList();
                  case 'pageAnimation':
                    _showPageAnimationPicker();
                }
              },
              itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                // WebView / 浏览器 / 分享：本地模式无在线 URL，隐藏。
                if (!_isLocalMode) ...<PopupMenuEntry<String>>[
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
                  const PopupMenuDivider(),
                ],
                // 书签列表
                PopupMenuItem<String>(
                  value: 'bookmarkList',
                  child: ListTile(
                    leading: const Icon(Icons.bookmark_border),
                    title: Text(l10n.novelMenuBookmarkList),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                // 配置底部工具栏
                PopupMenuItem<String>(
                  value: 'configureBottomToolbar',
                  child: ListTile(
                    leading: const Icon(Icons.tune),
                    title: Text(l10n.novelMenuConfigureToolbar),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuDivider(),
                // 笔记列表（P3.1）
                PopupMenuItem<String>(
                  value: 'notes',
                  child: ListTile(
                    leading: const Icon(Icons.edit_note),
                    title: Text(l10n.noteList),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                // 翻页动画快捷（P3）：弹出 6 种动画选择。
                PopupMenuItem<String>(
                  value: 'pageAnimation',
                  child: ListTile(
                    leading: const Icon(Icons.auto_stories_outlined),
                    title: Text(l10n.novelPageAnimation),
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

  Widget _buildBottomBar(AppLocalizations l10n, Color bg, {bool ttsActive = false}) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: <Color>[bg.withValues(alpha: 0.95), bg.withValues(alpha: 0)],
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: AppTokens.spaceSm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildProgressSlider(l10n),
            const SizedBox(height: AppTokens.spaceXs),
            if (ttsActive)
              _buildTtsControlsInline(l10n, bg)
            else
              _buildBottomToolbar(l10n),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── 章内进度滑条 ───────────────────────

  Widget _buildProgressSlider(AppLocalizations l10n) {
    final total = _pagination?.pages.length ?? 0;
    final isScroll = _prefs.pageAnimation.isScroll;
    // 翻页按钮可用性：章内有可翻页 OR 存在相邻章。
    // 用户需求：即使本章只有一页，上一页/下一页仍应可用——分别去往
    // 上一章最后一页 / 下一章第一页（由 page view 边界回调处理，连贯翻页）。
    // 本地模式（单文件无章间导航）或加载中则禁用按钮避免竞态。
    final bool hasPrev = !_loading &&
        (_currentPage > 0 || (!_isLocalMode && _chapterIndex > 0));
    final bool hasNext = !_loading &&
        (_currentPage < total - 1 ||
            (!_isLocalMode && _chapterIndex < widget.chapters.length - 1));
    // 滑块仅在多页时允许拖动跳页；单页时禁用（无跳页意义）但保留布局。
    final bool sliderInteractive = isScroll || total > 1;
    final int divisions = total > 1 ? total - 1 : 1;
    double value;
    String leftLabel;
    String rightLabel;
    if (isScroll) {
      value = _scrollFraction.clamp(0.0, 1.0);
      leftLabel = '${(value * 100).round()}%';
      rightLabel = '';
    } else {
      value = total > 1 ? _currentPage / (total - 1) : 0.0;
      // 防护：_currentPage 可能在章节切换瞬间为哨兵值 -1（toLastPage），
      // clamp 到合法范围避免闪现 "0"。
      final displayPage = _currentPage.clamp(0, total > 0 ? total - 1 : 0);
      leftLabel = '${displayPage + 1}';
      rightLabel = total > 0 ? '$total' : '';
    }
    return Row(
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: l10n.prevPage,
          visualDensity: VisualDensity.compact,
          onPressed: hasPrev ? _goPrevPage : null,
        ),
        SizedBox(
          width: 32,
          child: Text(
            leftLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 1.0),
            divisions: divisions,
            onChanged: sliderInteractive
                ? (v) {
                    if (isScroll) {
                      setState(() => _scrollFraction = v);
                    } else {
                      // paged 模式拖动即跳页（实时）。
                      final target =
                          (v * (total - 1)).round().clamp(0, total - 1);
                      if (target != _currentPage) {
                        _pageKey.currentState?.jumpToPage(target);
                      }
                    }
                  }
                : null,
            onChangeEnd: isScroll ? (v) => _onSeekScroll(v) : null,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            rightLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: l10n.nextPage,
          visualDensity: VisualDensity.compact,
          onPressed: hasNext ? _goNextPage : null,
        ),
      ],
    );
  }

  /// scroll 模式：按拖动比例跳转到对应滚动位置。
  void _onSeekScroll(double fraction) {
    final sc = _scrollController;
    if (sc == null || !sc.hasClients) return;
    final max = sc.position.maxScrollExtent;
    sc.animateTo(
      (fraction * max).clamp(0.0, max),
      duration: AppTokens.durFast,
      curve: Curves.easeInOut,
    );
  }

  // ─────────────────────── 底部工具栏 ───────────────────────

  Widget _buildBottomToolbar(AppLocalizations l10n) {
    // #3：书签列表与「配置底部工具栏」齿轮已从底部工具栏移除，仅保留用户
    // 可配置的槽位。配置入口移至内联设置面板（见 _NovelInlineSettings）。
    final slots = _prefs.bottomToolbarSlots.take(6).where((tool) {
      if (tool == NovelBottomTool.bookmarkList) return false;
      // 本地模式无章节导航，隐藏 toc / prevChapter / nextChapter。
      if (_isLocalMode) {
        return tool != NovelBottomTool.toc &&
            tool != NovelBottomTool.prevChapter &&
            tool != NovelBottomTool.nextChapter;
      }
      return true;
    }).toList();
    // 注意：无需在此包裹 ListenableBuilder(_tts)，因为父级 build() 已经用
    // ListenableBuilder(_tts) 包裹了整个 Stack（含本栏），_tts 状态变更时
    // 整个底部栏都会自动重建，TTS 图标（record_voice_over / stop）随之刷新。
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        for (final tool in slots)
          _buildToolButton(l10n, tool),
      ],
    );
  }

  Widget _buildToolButton(AppLocalizations l10n, NovelBottomTool tool) {
    return IconButton(
      icon: Icon(_toolIcon(tool)),
      tooltip: _toolLabel(l10n, tool),
      visualDensity: VisualDensity.compact,
      onPressed: () => _onToolTap(tool),
    );
  }

  IconData _toolIcon(NovelBottomTool tool) {
    final isNight = _prefs.nightMode;
    switch (tool) {
      case NovelBottomTool.toc:
        return Icons.toc;
      case NovelBottomTool.prevChapter:
        return Icons.skip_previous;
      case NovelBottomTool.nextChapter:
        return Icons.skip_next;
      case NovelBottomTool.nightMode:
        // 夜间开启时用实心月，关闭时用描边。
        return isNight ? Icons.dark_mode : Icons.light_mode_outlined;
      case NovelBottomTool.autoPage:
        return _autoPageEnabled
            ? (_autoPagePaused ? Icons.play_arrow : Icons.pause)
            : Icons.play_circle_outline;
      case NovelBottomTool.settings:
        return Icons.tune;
      case NovelBottomTool.bookmark:
        return Icons.bookmark_add_outlined;
      case NovelBottomTool.bookmarkList:
        return Icons.bookmarks_outlined;
      case NovelBottomTool.search:
        return Icons.search;
      case NovelBottomTool.tts:
        return _tts.isPlaying ? Icons.stop : Icons.record_voice_over;
    }
  }

  String _toolLabel(AppLocalizations l10n, NovelBottomTool tool) {
    switch (tool) {
      case NovelBottomTool.toc:
        return l10n.toolToc;
      case NovelBottomTool.prevChapter:
        return l10n.toolPrevChapter;
      case NovelBottomTool.nextChapter:
        return l10n.toolNextChapter;
      case NovelBottomTool.nightMode:
        return l10n.toolNightMode;
      case NovelBottomTool.autoPage:
        return l10n.toolAutoPage;
      case NovelBottomTool.settings:
        return l10n.toolSettings;
      case NovelBottomTool.bookmark:
        return l10n.toolBookmark;
      case NovelBottomTool.bookmarkList:
        return l10n.toolBookmarkList;
      case NovelBottomTool.search:
        return l10n.toolSearch;
      case NovelBottomTool.tts:
        return _tts.isPlaying ? l10n.stopReading : l10n.toolTts;
    }
  }

  void _onToolTap(NovelBottomTool tool) {
    switch (tool) {
      case NovelBottomTool.toc:
        _showChapterList();
      case NovelBottomTool.prevChapter:
        _goPrevChapter();
      case NovelBottomTool.nextChapter:
        _goNextChapter();
      case NovelBottomTool.nightMode:
        _toggleNightMode();
      case NovelBottomTool.autoPage:
        if (_autoPageEnabled) {
          _toggleAutoPagePause();
        } else {
          // 未启用自动翻页时，打开设置面板让用户设定间隔。
          _toggleInlineSettings();
        }
      case NovelBottomTool.settings:
        _toggleInlineSettings();
      case NovelBottomTool.bookmark:
        _addBookmark();
      case NovelBottomTool.bookmarkList:
        _showBookmarkList();
      case NovelBottomTool.search:
        _showInBookSearch();
      case NovelBottomTool.tts:
        _toggleTts();
    }
  }

  /// 夜间快捷切换：写回 [NovelReaderPreferences.nightMode]，背景预设不变。
  void _toggleNightMode() {
    _onPrefsChanged(_prefs.copyWith(nightMode: !_prefs.nightMode));
  }

  /// 缓存本书到本地（离线阅读）：复用全局 [DownloadManager] 提交整本下载任务。
  /// 本地模式（localTextPath）无在线源，入口已禁用；章节为空则提示。
  Future<void> _startNovelDownload() async {
    final l10n = AppLocalizations.of(context);
    if (widget.chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.emptyContent)),
      );
      return;
    }
    final dl = context.read<DownloadManager>();
    if (dl.isItemDownloaded(widget.novelId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.alreadyDownloaded)),
      );
      return;
    }
    final item = MediaItem(
      id: widget.novelId,
      title: widget.title,
      sourceId: widget.sourceId,
      sourceType: SourceType.novelSource,
      coverUrl: widget.coverUrl,
      detailUrl: widget.detailUrl,
    );
    final indices = <int>[
      for (int i = 0; i < widget.chapters.length; i++) i
    ];
    await dl.addTask(
      item: item,
      chapters: widget.chapters,
      chapterIndices: indices,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.downloadStarted)),
      );
    }
  }

  /// 恢复本书默认设置：清除按书覆盖，写回全局默认（下次读取会继承全局默认）。
  Future<void> _resetBookPrefs() async {
    final l10n = AppLocalizations.of(context);
    await _store.save(widget.novelId, const NovelReaderPreferences());
    setState(() => _prefs = const NovelReaderPreferences());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.novelResetBookDone)),
      );
    }
  }

  /// 翻页动画快捷选择（更多菜单入口）：弹窗列出 6 种动画，选中即应用。
  Future<void> _showPageAnimationPicker() async {
    final l10n = AppLocalizations.of(context);
    final current = _prefs.pageAnimation;
    final picked = await showDialog<NovelPageAnimation>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.novelPageAnimation),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: AppTokens.spaceSm,
            runSpacing: AppTokens.spaceSm,
            children: <Widget>[
              for (final anim in NovelPageAnimation.values)
                ChoiceChip(
                  label: Text(_animLabel(anim, l10n)),
                  selected: anim == current,
                  onSelected: (_) => Navigator.of(ctx).pop(anim),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      _onPrefsChanged(_prefs.copyWith(pageAnimation: picked));
    }
  }

  /// 打开章节列表（顶栏与底部工具栏共用）。传入本书书签章节，供目录内书签标记与筛选。
  Future<void> _showChapterList() async {
    final bookmarks = await _bookmarks.listFor(widget.novelId);
    final bookmarkedChapters = bookmarks.map((b) => b.chapterIndex).toSet();
    final index = await showChapterList(
      context,
      widget.chapters,
      _chapterIndex,
      bookmarkedIndices: bookmarkedChapters,
    );
    if (index != null && index != _chapterIndex && mounted) {
      _chapterIndex = index;
      _loadChapter(_chapterIndex);
    }
  }

  /// 打开书内搜索（顶栏与底部工具栏共用；本地模式不可用）。
  Future<void> _showInBookSearch() async {
    if (_isLocalMode) return;
    final result = await showNovelInBookSearchSheet(
      context: context,
      chapters: widget.chapters,
      currentChapterIndex: _chapterIndex,
      service: _service,
      source: _source,
      novelId: widget.novelId,
    );
    if (result != null &&
        result.chapterIndex != _chapterIndex &&
        mounted) {
      _chapterIndex = result.chapterIndex;
      _loadChapter(_chapterIndex);
    }
  }

  /// 底部工具栏配置 sheet：勾选 / 排序槽位（最多 6 个）。
  Future<void> _showBottomToolbarConfig() async {
    final l10n = AppLocalizations.of(context);
    // 书签列表为固定按钮，不进入可配置列表。
    List<NovelBottomTool> working = List<NovelBottomTool>.of(
        _prefs.bottomToolbarSlots)
      ..removeWhere((NovelBottomTool t) => t == NovelBottomTool.bookmarkList);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetCtx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSheetState) {
            final hidden = NovelBottomTool.values
                .where((NovelBottomTool t) =>
                    t != NovelBottomTool.bookmarkList &&
                    !working.contains(t))
                .toList();
            return SafeArea(
              child: Container(
                height: MediaQuery.sizeOf(ctx).height * 0.6,
                padding: const EdgeInsets.all(AppTokens.spaceMd),
                child: Column(
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          l10n.bottomToolbarConfigTitle,
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                        Row(
                          children: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: Text(
                                  MaterialLocalizations.of(ctx)
                                      .cancelButtonLabel),
                            ),
                            FilledButton(
                              onPressed: () {
                                _onPrefsChanged(_prefs.copyWith(
                                    bottomToolbarSlots: working));
                                Navigator.of(ctx).pop();
                              },
                              child: Text(
                                  MaterialLocalizations.of(ctx)
                                      .okButtonLabel),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(l10n.slotsShown,
                          style: Theme.of(ctx).textTheme.bodySmall),
                    ),
                    Expanded(
                      child: working.isEmpty
                          ? Center(child: Text(l10n.slotsHidden))
                          : ReorderableListView(
                              buildDefaultDragHandles: false,
                              onReorder: (int oldI, int newI) {
                                setSheetState(() {
                                  if (newI > oldI) newI -= 1;
                                  final item = working.removeAt(oldI);
                                  working.insert(newI, item);
                                });
                              },
                              children: <Widget>[
                                for (int i = 0; i < working.length; i++)
                                  ListTile(
                                    key: ValueKey<String>(working[i].name),
                                    leading: Icon(_toolIcon(working[i])),
                                    title: Text(_toolLabel(l10n, working[i])),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        IconButton(
                                          icon: const Icon(Icons.close),
                                          tooltip:
                                              MaterialLocalizations.of(ctx)
                                                  .deleteButtonTooltip,
                                          onPressed: () => setSheetState(
                                              () => working.removeAt(i)),
                                        ),
                                        ReorderableDragStartListener(
                                          index: i,
                                          child: const Icon(Icons.drag_handle),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    if (hidden.isNotEmpty) ...<Widget>[
                      const Divider(),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(l10n.slotsHidden,
                            style: Theme.of(ctx).textTheme.bodySmall),
                      ),
                      const SizedBox(height: AppTokens.spaceXs),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: <Widget>[
                          for (final t in hidden)
                            ActionChip(
                              label: Text(_toolLabel(l10n, t)),
                              avatar: Icon(_toolIcon(t), size: 18),
                              onPressed: working.length >= 6
                                  ? null
                                  : () => setSheetState(
                                      () => working.add(t)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─────────────────────── 亮度指示器 ───────────────────────

  Widget _buildBrightnessIndicator(AppLocalizations l10n) {
    final percent = (_brightness * 100).round();
    return Center(
      child: Container(
        padding: const EdgeInsets.all(AppTokens.spaceXl),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.brightness_6,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              '$percent%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              l10n.novelBrightness,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── 内联设置面板 ───────────────────────

  Widget _buildInlineSettings(
      AppLocalizations l10n, Color bg, Color textColor) {
    final isDesktop =
        MediaQuery.sizeOf(context).width >= AppTokens.desktopBreakpoint;

    final panel = Container(
      color: bg,
      child: _NovelInlineSettings(
        prefs: _prefs,
        brightness: _brightness,
        onChanged: _onPrefsChanged,
        onBrightnessChanged: _setBrightness,
        onClose: _toggleInlineSettings,
        onCache: _isLocalMode ? null : _startNovelDownload,
        onResetBook: _resetBookPrefs,
        onConfigureToolbar: _showBottomToolbarConfig,
        tts: _tts,
        searchController: _settingsSearchController,
        onSearchChanged: (_) => setState(() {}),
        onShowTapZonePreview: () => _showTapZonePreview(l10n),
      ),
    );

    if (isDesktop) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: panel,
        ),
      );
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        heightFactor: 0.55,
        child: panel,
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

/// 章节大标题渲染（#7）：支持左 / 中 / 右对齐与「隐藏」；分段模式下主行(章名) +
/// 次行(书名) 两行。paged 与 scroll 两种模式共用，保证排版一致。
Widget _buildChapterTitleWidget(
  NovelReaderPreferences prefs,
  String chapterTitle,
  String bookName,
) {
  if (!prefs.showChapterTitleInBody ||
      prefs.titleAlign == NovelTitleAlign.hidden ||
      chapterTitle.isEmpty) {
    return const SizedBox.shrink();
  }
  final mainStyle = prefs.resolveTitleTextStyle();
  final cross = switch (prefs.titleAlign) {
    NovelTitleAlign.left => CrossAxisAlignment.start,
    NovelTitleAlign.center => CrossAxisAlignment.center,
    NovelTitleAlign.right => CrossAxisAlignment.end,
    NovelTitleAlign.hidden => CrossAxisAlignment.start,
  };
  final textAlign = switch (prefs.titleAlign) {
    NovelTitleAlign.left => TextAlign.left,
    NovelTitleAlign.center => TextAlign.center,
    NovelTitleAlign.right => TextAlign.right,
    NovelTitleAlign.hidden => TextAlign.left,
  };
  Widget titleBlock;
  if (prefs.titleSegmentMode) {
    final subStyle = mainStyle.copyWith(
      fontSize: (mainStyle.fontSize ?? 18) * prefs.titleSubScale,
      height: prefs.titleSubLineSpacing,
    );
    titleBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: cross,
      children: <Widget>[
        Text(chapterTitle, style: mainStyle, textAlign: textAlign),
        SizedBox(height: prefs.titleSegmentSpacing),
        Text(
          bookName,
          style: subStyle,
          textAlign: textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  } else {
    titleBlock = Text(
      chapterTitle,
      style: mainStyle,
      textAlign: textAlign,
    );
  }
  // SizedBox(width: double.infinity) 让 titleBlock 占满父宽度，
  // 确保 titleAlign = center / right 时 Column / Text 真正居中 / 右对齐
  // （父级 Column 是 crossAxisAlignment.start，不占满宽度会导致对齐失效）。
  return Padding(
    padding: EdgeInsets.only(
      top: prefs.titleTopMargin,
      bottom: prefs.titleBottomMargin,
    ),
    child: SizedBox(
      width: double.infinity,
      child: titleBlock,
    ),
  );
}

/// 页眉 / 页脚槽位内容的本地化标签（#8）。
String _hfContentLabel(NovelHeaderFooterContent c, AppLocalizations l10n) {
  switch (c) {
    case NovelHeaderFooterContent.none:
      return l10n.novelHfNone;
    case NovelHeaderFooterContent.time:
      return l10n.novelHfTime;
    case NovelHeaderFooterContent.battery:
      return l10n.novelHfBattery;
    case NovelHeaderFooterContent.chapterTitle:
      return l10n.novelHfChapterTitle;
    case NovelHeaderFooterContent.bookName:
      return l10n.novelHfBookName;
    case NovelHeaderFooterContent.pageNumber:
      return l10n.novelHfPageNumber;
    case NovelHeaderFooterContent.progressPercent:
      return l10n.novelHfProgressPercent;
    case NovelHeaderFooterContent.pageAndProgress:
      return l10n.novelHfPageAndProgress;
    case NovelHeaderFooterContent.timeAndBattery:
      return l10n.novelHfTimeAndBattery;
  }
}

/// 自定义虚线下划线文字：当 [NovelReaderPreferences.underlineDashed]
/// 开启时，用 [CustomPaint] 在每行文字基线下方按 `dashLength` / `dashGap`
/// 绘制虚线，弥补原生 `TextDecorationStyle.dashed` 不支持自定义段长/间隙
/// 的不足。
class _DashedUnderlineText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double dashLength;
  final double dashGap;
  final double thickness;
  final Color? color;

  const _DashedUnderlineText({
    required this.text,
    required this.style,
    required this.dashLength,
    required this.dashGap,
    required this.thickness,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints constraints) {
        final TextPainter painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
          textScaler: MediaQuery.textScalerOf(ctx),
        )..layout(maxWidth: constraints.maxWidth);
        final List<LineMetrics> lines = painter.computeLineMetrics();
        final Size painterSize = Size(painter.width, painter.height);
        return Stack(
          children: <Widget>[
            Text(text, style: style),
            Positioned(
              left: 0,
              top: 0,
              child: CustomPaint(
                size: painterSize,
                painter: _DashedUnderlinePainter(
                  lines: lines,
                  dashLength: dashLength <= 0 ? 1.0 : dashLength,
                  dashGap: dashGap <= 0 ? 0.0 : dashGap,
                  thickness: thickness <= 0 ? 1.0 : thickness,
                  color: color ?? style.color ?? const Color(0xFF000000),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashedUnderlinePainter extends CustomPainter {
  final List<LineMetrics> lines;
  final double dashLength;
  final double dashGap;
  final double thickness;
  final Color color;

  _DashedUnderlinePainter({
    required this.lines,
    required this.dashLength,
    required this.dashGap,
    required this.thickness,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    // 基线下方偏移：约字号 × 0.18，与 Flutter 原生下划线位置接近。
    final double underlineOffset =
        lines.isNotEmpty ? (lines.first.height * 0.18).clamp(1.0, 4.0) : 2.0;
    final double step = dashLength + dashGap;
    for (final LineMetrics line in lines) {
      final double y = line.baseline + underlineOffset;
      final double lineEnd = line.left + line.width;
      double x = line.left;
      while (x < lineEnd) {
        final double segEnd = (x + dashLength).clamp(line.left, lineEnd);
        canvas.drawLine(Offset(x, y), Offset(segEnd, y), paint);
        x += step;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedUnderlinePainter old) {
    return old.dashLength != dashLength ||
        old.dashGap != dashGap ||
        old.thickness != thickness ||
        old.color != color ||
        old.lines.length != lines.length;
  }
}

/// 单页小说内容（含页眉页脚）。
class _NovelPageWidget extends StatelessWidget {
  final List<NovelLine> lines;
  final NovelReaderPreferences prefs;
  final Color bg;
  final Color textColor;
  final NovelPageAnimation animation;
  final String chapterTitle;
  final String bookName;
  final int pageIndex;
  final int totalPages;
  final String time;
  final int batteryLevel;
  final NovelHeaderFooterContent headerCenter;
  final NovelHeaderFooterContent footerCenter;
  final int? headerFooterColor;
  final double headerFooterMargin;
  /// TTS 当前朗读段落索引（-1 表示未朗读 / TTS 未启动）。
  final int ttsCurrentIndex;
  /// TTS 是否处于激活状态（playing 或 paused）。
  final bool ttsActive;
  /// 点击段落回调：传入段落在 paragraphs 中的全局索引。
  /// TTS 模式下点击某行时回调：返回该行所属段落下标。
  /// （TextColumn 精确字符坐标保留在 NovelLine.charLefts 中，
  /// 供未来长按选区等场景使用；tap 时默认命中段落首字符即可。）
  final void Function(int paragraphIndex)? onParagraphTap;

  const _NovelPageWidget({
    required this.lines,
    required this.prefs,
    required this.bg,
    required this.textColor,
    required this.animation,
    required this.chapterTitle,
    required this.bookName,
    required this.pageIndex,
    required this.totalPages,
    required this.time,
    required this.batteryLevel,
    required this.headerCenter,
    required this.footerCenter,
    required this.headerFooterColor,
    required this.headerFooterMargin,
    this.ttsCurrentIndex = -1,
    this.ttsActive = false,
    this.onParagraphTap,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = prefs.resolveBodyTextStyle(textColor);

    // 页眉页脚颜色：自定义优先，否则跟随正文色半透明。
    final hfColor = headerFooterColor != null
        ? Color(headerFooterColor!)
        : textColor.withValues(alpha: 0.5);
    final headerFooterStyle = TextStyle(
      fontSize: 12,
      color: hfColor,
      fontFamily: prefs.customFontPath != null
          ? NovelReaderPreferences.customLoadedFontFamily
          : prefs.fontFamily,
    );

    final progress = totalPages > 0 ? (pageIndex + 1) / totalPages : 0.0;

    return Container(
      color: bg,
      // 仅纵向用正文边距；页眉页脚用各自的 [headerFooterMargin]，正文用
      // [prefs.margin]，互不干扰（#8）。
      padding: EdgeInsets.symmetric(vertical: prefs.margin),
      child: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: headerFooterMargin),
            child: _buildHeaderFooter(
              prefs.headerLeft,
              headerCenter,
              prefs.headerRight,
              headerFooterStyle,
              chapterTitle,
              bookName,
              pageIndex,
              totalPages,
              progress,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              clipBehavior: Clip.hardEdge,
              padding: EdgeInsets.symmetric(horizontal: prefs.margin),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 章节大标题仅在第一页顶部渲染（#7，含对齐 / 分段模式）。
                  if (pageIndex == 0) _buildChapterTitleWidget(
                    prefs,
                    chapterTitle,
                    bookName,
                  ),
                  for (final line in lines) ...<Widget>[
                    _buildLine(context, line, textStyle),
                    // 段落间距（仅段末行后加）
                    if (line.isLastLine)
                      SizedBox(height: prefs.paragraphSpacing),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: headerFooterMargin),
            child: _buildHeaderFooter(
              prefs.footerLeft,
              footerCenter,
              prefs.footerRight,
              headerFooterStyle,
              chapterTitle,
              bookName,
              pageIndex,
              totalPages,
              progress,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单行文本（legado 式按行渲染）：TTS 高亮 + 点击跳转。
  ///
  /// 每行已是适配宽度的视觉行，首行自带 `　　` 缩进；段距由上层在
  /// [isLastLine] 后统一添加，这里只负责单行的文字与高亮。
  Widget _buildLine(BuildContext context, NovelLine line, TextStyle textStyle) {
    final isCurrent = ttsActive && line.paragraphIndex == ttsCurrentIndex;
    // TTS 当前朗读段落：浅色高亮背景（类似电子书阅读器的跟读效果）。
    final Widget textWidget = prefs.fontUnderline && prefs.underlineDashed
        ? _DashedUnderlineText(
            text: line.text,
            style: textStyle,
            dashLength: prefs.underlineDashLength,
            dashGap: prefs.underlineDashGap,
            thickness: prefs.underlineThickness,
            color: prefs.resolveUnderlineColor(textColor),
          )
        : Text(
            line.text,
            style: textStyle,
            // 每行已是按宽度精确测量出的单行文本，禁止再次折行/省略，
            // 保证渲染与分页器测量一致（legado 式按行排版）。
            softWrap: false,
            maxLines: 1,
            overflow: TextOverflow.clip,
          );

    final content = isCurrent
        ? Container(
            decoration: BoxDecoration(
              color: prefs.resolveTextColor(bg).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 4, vertical: 2),
            child: textWidget,
          )
        : textWidget;

    // TTS 激活时允许点按任意行跳转朗读位置（按所属段落）；否则不拦截点击
    // （让外层 GestureDetector 处理翻页/切换 UI）。
    //
    // ⚠️ 内层段落交互必须用 onLongPress（长按），绝不能用 onTap/onTapUp。
    // 原因：外层 _wrapGestures 用 onTapUp 接收翻页/切换 UI 指令，而 Flutter 中
    // onTap 与 onTapUp 同属 TapGestureRecognizer（是同一类手势）。若内层用 onTap，
    // 嵌套竞技场里内层会赢、外层 onTapUp 被吞→点文本时翻页指令丢失，页面变成「瞬跳
    // 无动画」或「误触发 TTS 跳转」，即用户反馈的「翻页动画消失」。
    //
    // onLongPress 属于 LongPressGestureRecognizer（与 Tap 是不同的识别器家族），
    // 不会抢占单击手势：轻点文本→外层 onTapUp 正常翻页并播放动画；长按文本→
    // 内层跳转到该段落朗读。两种交互互不干扰，翻页动画始终可见。
    // TextColumn 精确字符坐标（charLefts / hitTestCharOffset）保留在模型中，
    // 供未来长按选区等需要精确坐标的场景使用。
    if (ttsActive && onParagraphTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () => onParagraphTap!.call(line.paragraphIndex),
        child: content,
      );
    }
    return content;
  }

  Widget _buildHeaderFooter(
    NovelHeaderFooterContent left,
    NovelHeaderFooterContent center,
    NovelHeaderFooterContent right,
    TextStyle style,
    String chapter,
    String book,
    int page,
    int total,
    double progress,
  ) {
    String resolve(NovelHeaderFooterContent c) {
      return switch (c) {
        NovelHeaderFooterContent.none => '',
        NovelHeaderFooterContent.time => time,
        NovelHeaderFooterContent.battery =>
          batteryLevel >= 0 ? '$batteryLevel%' : '',
        NovelHeaderFooterContent.chapterTitle => chapter,
        NovelHeaderFooterContent.bookName => book,
        NovelHeaderFooterContent.pageNumber => '${page + 1}/$total',
        NovelHeaderFooterContent.progressPercent =>
          '${(progress * 100).round()}%',
        NovelHeaderFooterContent.pageAndProgress =>
          '${page + 1}/$total  ${(progress * 100).round()}%',
        NovelHeaderFooterContent.timeAndBattery =>
          '${time}${batteryLevel >= 0 ? '  $batteryLevel%' : ''}',
      };
    }

    final leftText = resolve(left);
    final centerText = resolve(center);
    final rightText = resolve(right);

    // 中间槽位为空（none 或空串）时退化为左右两槽，保持 spaceBetween。
    if (center == NovelHeaderFooterContent.none || centerText.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            child: Text(leftText, style: style, overflow: TextOverflow.ellipsis),
          ),
          Flexible(
            child:
                Text(rightText, style: style, overflow: TextOverflow.ellipsis),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Expanded(
          child: Text(leftText, style: style, overflow: TextOverflow.ellipsis),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceSm),
          child: Text(centerText,
              style: style, textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          child: Text(rightText,
              style: style,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// 内联设置面板（桌面右侧 ~360px / 移动底部 ~55%）。
///
/// 包含字号 / 行距 / 段距 / 边距滑块、翻页动画选择、背景预设、文字阴影开关、
/// 亮度滑块。所有变更即时生效并持久化。

/// 点按区域预览覆盖层：在对话框内半透明展示当前布局的各点击分区，
/// 用不同颜色区分 prev / next / toggle 操作区域，并标注中文标签。
class _TapZonePreviewOverlay extends StatelessWidget {
  final ReaderTapZoneLayout layout;
  final TapZoneInvert invert;
  final bool isVertical;
  final AppLocalizations l10n;

  const _TapZonePreviewOverlay({
    required this.layout,
    required this.invert,
    required this.isVertical,
    required this.l10n,
  });

  // 各操作对应的颜色（半透明）。
  static const Color _prevColor = Color(0x332196F3);   // 蓝
  static const Color _nextColor = Color(0x334CAF50);   // 绿
  static const Color _toggleColor = Color(0x33FF9800); // 橙

  String _labelFor(TapZoneAction action) {
    switch (action) {
      case TapZoneAction.prev: return l10n.tapZonePrev;
      case TapZoneAction.next: return l10n.tapZoneNext;
      case TapZoneAction.toggle: return l10n.tapZoneToggle;
    }
  }

  Color _colorFor(TapZoneAction action) {
    switch (action) {
      case TapZoneAction.prev: return _prevColor;
      case TapZoneAction.next: return _nextColor;
      case TapZoneAction.toggle: return _toggleColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用与 TapZoneResolver 相同的区域定义。
    final regions = _resolvedRegions();
    return ClipRect(
      child: Stack(
        children: <Widget>[
          // 背景网格（模拟阅读页面）
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          // 各区域色块 + 标签
          for (final entry in regions)
            Positioned.fromRect(
              rect: entry.key,
              child: Container(
                decoration: BoxDecoration(
                  color: _colorFor(entry.value),
                  border: Border.all(
                    color: _colorFor(entry.value).withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  _labelFor(entry.value),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _colorFor(entry.value).withValues(alpha: 1.0),
                    shadows: <Shadow>[
                      Shadow(
                        color: Colors.white.withValues(alpha: 0.8),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 解析当前设置下的有效区域（考虑反转），返回 [Rect → Action] 映射。
  List<MapEntry<Rect, TapZoneAction>> _resolvedRegions() {
    // 原始区域定义（来自 TapZoneResolver._regions 的逻辑副本）。
    final raw = _rawRegions(layout);
    final result = <MapEntry<Rect, TapZoneAction>>[];
    for (final r in raw) {
      final action = TapZoneResolver.resolve(
        layout: layout,
        invert: invert,
        isVertical: isVertical,
        pos: Offset(r.left + r.width / 2, r.top + r.height / 2),
        size: const Size(1, 1),
      );
      result.add(MapEntry(
        Rect.fromLTWH(r.left * 280, r.top * 420, r.width * 280, r.height * 420),
        action,
      ));
    }
    return result;
  }

  /// 返回原始区域列表（比例坐标 0..1），同 TapZoneResolver._regions。
  static List<_RawRegion> _rawRegions(ReaderTapZoneLayout layout) {
    switch (layout) {
      case ReaderTapZoneLayout.leftRight:
        return const <_RawRegion>[
          _RawRegion(0, 0, 0.45, 1),   // prev
          _RawRegion(0.45, 0, 0.1, 1), // toggle
          _RawRegion(0.55, 0, 0.45, 1), // next
        ];
      case ReaderTapZoneLayout.lShape:
        // 两个 L 形 + 中心 toggle（与 TapZoneResolver 保持一致）。
        return const <_RawRegion>[
          _RawRegion(0, 0, 0.33, 1),       // prev 左列（全高）
          _RawRegion(0.67, 0, 0.33, 1),     // next 右列（全高）
          _RawRegion(0.33, 0, 0.34, 0.33),  // next 上中条
          _RawRegion(0.33, 0.67, 0.34, 0.33), // prev 下中条
          _RawRegion(0.33, 0.33, 0.34, 0.34), // toggle 中心
        ];
      case ReaderTapZoneLayout.kindle:
        return const <_RawRegion>[
          _RawRegion(0, 0, 1, 0.15),    // toggle (顶部)
          _RawRegion(0, 0.15, 0.35, 0.85),// prev (左侧)
          _RawRegion(0.35, 0.15, 0.65, 0.85),// next (右侧)
        ];
      case ReaderTapZoneLayout.bothSides:
        return const <_RawRegion>[
          _RawRegion(0, 0.15, 0.33, 0.7), // next (左上)
          _RawRegion(0.67, 0.15, 0.33, 0.7),// next (右上)
          _RawRegion(0.33, 0.7, 0.34, 0.3), // prev (底部中间)
          _RawRegion(0.33, 0, 0.34, 0.15),   // toggle (顶部)
        ];
      case ReaderTapZoneLayout.off:
        return const <_RawRegion>[_RawRegion(0, 0, 1, 1)]; // 全 toggle
    }
  }
}

/// 原始区域（比例坐标 0..1），仅用于预览渲染。
class _RawRegion {
  final double left, top, width, height;
  const _RawRegion(this.left, this.top, this.width, this.height);
}

class _NovelInlineSettings extends StatelessWidget {
  final NovelReaderPreferences prefs;
  final double brightness;
  final ValueChanged<NovelReaderPreferences> onChanged;
  final ValueChanged<double> onBrightnessChanged;
  final VoidCallback onClose;
  final VoidCallback? onCache;
  final VoidCallback? onResetBook;
  final VoidCallback? onConfigureToolbar;
  final NovelTtsController tts;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onShowTapZonePreview;

  const _NovelInlineSettings({
    required this.prefs,
    required this.brightness,
    required this.onChanged,
    required this.onBrightnessChanged,
    required this.onClose,
    this.onCache,
    this.onResetBook,
    this.onConfigureToolbar,
    required this.tts,
    required this.searchController,
    required this.onSearchChanged,
    this.onShowTapZonePreview,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final q = searchController.text.trim().toLowerCase();
    bool groupMatches(String title, List<String> terms) {
      if (q.isEmpty) return true;
      final hay = <String>[title, ...terms].join(' ').toLowerCase();
      return hay.contains(q);
    }
    final bool hasSearchMatch = groupMatches(l10n.novelSectionColor,
            const <String>['颜色', '背景', '亮度', '夜间', '文字色', '强调色', '背景色'])
        || groupMatches(l10n.novelSectionText,
            const <String>['字号', '行距', '段距', '边距', '字距', '字体大小', '行高', '段落'])
        || groupMatches(l10n.novelSectionFont,
            const <String>['粗体', '斜体', '下划线', '字体', '字体文件', '字族'])
        || groupMatches(l10n.novelSectionTitle,
            const <String>['章节标题', '标题', '位置', '字体', '分段', '字号'])
        || groupMatches(l10n.novelSectionHeaderFooter,
            const <String>['页眉', '页脚', '时间', '电量', '页数', '进度'])
        || groupMatches(l10n.novelSectionShadowUnderline,
            const <String>['阴影', '下划线', '颜色', '虚线', '阴影色'])
        || groupMatches(l10n.novelSectionPage,
            const <String>['翻页', '动画', '点击', '自动翻页', '手势', '分区'])
        || groupMatches(l10n.novelSectionTts,
            const <String>['朗读', '语速', '睡眠', '后台', '语音'])
        || groupMatches(l10n.novelSectionMisc,
            const <String>['简繁', '缓存', '恢复', '配置', '工具栏', '转换']);
    return Material(
      elevation: 4,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          ),
        ),
        child: Column(
          children: <Widget>[
            // 标题行
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceLg,
                vertical: AppTokens.spaceMd,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    l10n.readerSettings,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // #3：底部工具栏「配置」入口从工具栏齿轮移至此处，保持可配置能力。
            if (onConfigureToolbar != null)
              ListTile(
                leading: const Icon(Icons.view_module_outlined),
                title: Text(l10n.configureBottomToolbar),
                onTap: onConfigureToolbar,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
              ),
            // 搜索框（固定，不随滚动消失）
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceLg,
                vertical: AppTokens.spaceSm,
              ),
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  hintText: l10n.novelSettingsSearch,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ),
            // 可滚动内容
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTokens.spaceLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 常用置顶：最常改的快捷项（搜索时隐藏，避免与过滤重叠）
                    if (searchController.text.trim().isEmpty)
                      _buildCommonCard(context, l10n),

                    // ── 颜色与背景组 ──
                    _buildSettingsGroup(
                      context,
                      l10n.novelSectionColor,
                      searchQuery: searchController.text,
                      leading: Icons.palette,
                      searchTerms: const <String>[
                        '颜色',
                        '背景',
                        '亮度',
                        '夜间',
                        '文字色',
                        '强调色',
                        '背景色',
                      ],
                      children: <Widget>[
                    // 亮度（从「翻页与交互」组上移，最常调）
                    _SliderRow(
                      label: l10n.novelBrightness,
                      value: brightness,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      onChanged: onBrightnessChanged,
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    // 夜间快捷开关
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.nightMode),
                      value: prefs.nightMode,
                      onChanged: (v) =>
                          onChanged(prefs.copyWith(nightMode: v)),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    // 背景预设
                    Text(l10n.readerBackground,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: AppTokens.spaceXs),
                    Wrap(
                      spacing: AppTokens.spaceSm,
                      runSpacing: AppTokens.spaceSm,
                      children: <Widget>[
                        for (int i = 0; i < ReaderTokens.bgPresets.length; i++)
                          ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: _swatchColor(ReaderTokens.bgPresets[i]),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline
                                          .withValues(alpha: 0.6),
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(_bgLabel(i, l10n)),
                              ],
                            ),
                            selected: prefs.bgPresetIndex == i &&
                                prefs.customBgColor == null,
                            onSelected: (_) => onChanged(prefs.copyWith(
                              bgPresetIndex: i,
                              customBgColor: null,
                            )),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
                    // 自定义背景色
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.customBgColor),
                      trailing: GestureDetector(
                        onTap: () async {
                          // #6 修复：确认式取色（OK/Cancel），仅用户点确定时写回，避免非手势 pop 崩溃。
                          Color? pickedColor;
                          final Color initial = prefs.customBgColor != null
                              ? Color(prefs.customBgColor!)
                              : ReaderTokens.bgPresets[prefs.bgPresetIndex
                                  .clamp(0, ReaderTokens.bgPresets.length - 1)];
                          final color = await showDialog<Color>(
                            context: context,
                            builder: (ctx) => StatefulBuilder(
                              builder: (ctx2, setDialogState) => AlertDialog(
                                title: Text(l10n.customBgColor),
                                content: SingleChildScrollView(
                                  child: ColorPicker(
                                    pickerColor: pickedColor ?? initial,
                                    onColorChanged: (c) => setDialogState(() => pickedColor = c),
                                  ),
                                ),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(),
                                    child: Text(
                                      MaterialLocalizations.of(ctx)
                                          .cancelButtonLabel,
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(
                                            pickedColor ?? initial),
                                    child: Text(
                                      MaterialLocalizations.of(ctx)
                                          .okButtonLabel,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                          if (color != null) {
                            onChanged(prefs.copyWith(
                                customBgColor: color.toARGB32()));
                          }
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _swatchColor(prefs.customBgColor != null
                                ? Color(prefs.customBgColor!)
                                : ReaderTokens.bgPresets[
                                    prefs.bgPresetIndex.clamp(
                                        0, ReaderTokens.bgPresets.length - 1)]),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
                    // 正文颜色（自定义；可清除为跟随背景）
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.novelTextColor),
                      subtitle: prefs.customTextColor == null
                          ? Text(l10n.novelTextColorFollowBg)
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (prefs.customTextColor != null)
                            IconButton(
                              icon: const Icon(Icons.backspace_outlined),
                              tooltip: l10n.novelTextColorFollowBg,
                              onPressed: () => onChanged(
                                  prefs.copyWith(customTextColor: null)),
                            ),
                          GestureDetector(
                            onTap: () async {
                              // #6 修复：确认式取色（OK/Cancel），仅用户点确定时写回，避免非手势 pop 崩溃。
                              Color? pickedColor;
                              final Color initial =
                                  prefs.customTextColor != null
                                      ? Color(prefs.customTextColor!)
                                      : const Color(0xFF1A1A1A);
                              final color = await showDialog<Color>(
                                context: context,
                                builder: (ctx) => StatefulBuilder(
                                  builder: (ctx2, setDialogState) =>
                                      AlertDialog(
                                    title: Text(l10n.novelTextColor),
                                    content: SingleChildScrollView(
                                      child: ColorPicker(
                                        pickerColor: pickedColor ?? initial,
                                        onColorChanged: (c) => setDialogState(() => pickedColor = c),
                                      ),
                                    ),
                                    actions: <Widget>[
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(),
                                        child: Text(
                                          MaterialLocalizations.of(ctx)
                                              .cancelButtonLabel,
                                        ),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.of(ctx).pop(
                                            pickedColor ?? initial),
                                        child: Text(
                                          MaterialLocalizations.of(ctx)
                                              .okButtonLabel,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                              if (color != null) {
                                onChanged(prefs.copyWith(
                                    customTextColor: color.toARGB32()));
                              }
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: prefs.customTextColor != null
                                    ? Color(prefs.customTextColor!)
                                    : const Color(0xFF1A1A1A),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
                    // 强调色（从「字体文件」组移入；可清除为默认）
                    _colorTile(
                      context: context,
                      l10n: l10n,
                      title: l10n.novelEmphasisColor,
                      subtitle: prefs.emphasisColor == null
                          ? l10n.novelEmphasisColorAuto
                          : null,
                      current: prefs.emphasisColor,
                      fallback: ReaderTokens.emphasisDefault,
                      onPicked: (c) =>
                          onChanged(prefs.copyWith(emphasisColor: c)),
                      onClear: () =>
                          onChanged(prefs.copyWith(emphasisColor: null)),
                      clearTooltip: l10n.novelEmphasisColorAuto,
                    ),
                      ],
                    ),
                    // ── 文字组 ──
                    _buildSettingsGroup(
                      context,
                      l10n.novelSectionText,
                      initiallyExpanded: true,
                      searchQuery: searchController.text,
                      leading: Icons.text_fields,
                      searchTerms: const <String>[
                        '字号',
                        '行距',
                        '段距',
                        '边距',
                        '字距',
                        '字体大小',
                        '行高',
                        '段落',
                      ],
                      children: <Widget>[
                    _SliderRow(
                      label: l10n.novelFontSize,
                      value: prefs.fontSize,
                      min: 12,
                      max: 32,
                      divisions: 20,
                      unit: 'sp',
                      onChanged: (v) =>
                          onChanged(prefs.copyWith(fontSize: v)),
                    ),
                    _SliderRow(
                      label: l10n.novelLineHeight,
                      value: prefs.lineHeight,
                      min: 1.2,
                      max: 3.0,
                      divisions: 18,
                      onChanged: (v) =>
                          onChanged(prefs.copyWith(lineHeight: v)),
                    ),
                    _SliderRow(
                      label: l10n.novelParagraphSpacing,
                      value: prefs.paragraphSpacing,
                      min: 4,
                      max: 48,
                      divisions: 22,
                      unit: 'px',
                      onChanged: (v) =>
                          onChanged(prefs.copyWith(paragraphSpacing: v)),
                    ),
                    _SliderRow(
                      label: l10n.novelMargin,
                      value: prefs.margin,
                      min: 8,
                      max: 64,
                      divisions: 14,
                      unit: 'px',
                      onChanged: (v) => onChanged(prefs.copyWith(margin: v)),
                    ),
                    _SliderRow(
                      label: l10n.novelLetterSpacing,
                      value: prefs.letterSpacing,
                      min: 0,
                      max: 8,
                      divisions: 16,
                      unit: 'px',
                      onChanged: (v) =>
                          onChanged(prefs.copyWith(letterSpacing: v)),
                    ),
                      ],
                    ),
                    // ── 字体样式组 ──
                    _buildSettingsGroup(
                      context,
                      l10n.novelSectionFont,
                      searchQuery: searchController.text,
                      leading: Icons.font_download_outlined,
                      searchTerms: const <String>[
                        '粗体',
                        '斜体',
                        '下划线',
                        '字体',
                        '字体文件',
                        '字族',
                      ],
                      children: <Widget>[
                    // 字体样式（加粗 / 斜体 / 下划线，可共存）
                    Text(l10n.novelFontStyle,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: AppTokens.spaceXs),
                    Wrap(
                      spacing: AppTokens.spaceSm,
                      runSpacing: AppTokens.spaceSm,
                      children: <Widget>[
                        FilterChip(
                          label: Text(l10n.fontBold),
                          selected: prefs.fontBold,
                          onSelected: (v) =>
                              onChanged(prefs.copyWith(fontBold: v)),
                        ),
                        FilterChip(
                          label: Text(l10n.fontItalic),
                          selected: prefs.fontItalic,
                          onSelected: (v) =>
                              onChanged(prefs.copyWith(fontItalic: v)),
                        ),
                        FilterChip(
                          label: Text(l10n.fontUnderline),
                          selected: prefs.fontUnderline,
                          onSelected: (v) =>
                              onChanged(prefs.copyWith(fontUnderline: v)),
                        ),
                      ],
                    ),
                    // 自定义字体（M3.5.3）
                    const SizedBox(height: AppTokens.spaceMd),
                    Text(l10n.customFont,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: AppTokens.spaceXs),
                    Wrap(
                      spacing: AppTokens.spaceSm,
                      runSpacing: AppTokens.spaceSm,
                      children: <Widget>[
                        ChoiceChip(
                          label: Text(l10n.fontSystem),
                          selected: prefs.fontFamily == null,
                          onSelected: (_) =>
                              onChanged(prefs.copyWith(fontFamily: null)),
                        ),
                        ChoiceChip(
                          label: Text(l10n.fontSerif),
                          selected: prefs.fontFamily == 'serif',
                          onSelected: (_) =>
                              onChanged(prefs.copyWith(fontFamily: 'serif')),
                        ),
                        ChoiceChip(
                          label: Text(l10n.fontMonospace),
                          selected: prefs.fontFamily == 'monospace',
                          onSelected: (_) => onChanged(
                              prefs.copyWith(fontFamily: 'monospace')),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    _fontFileTile(
                      context: context,
                      l10n: l10n,
                      title: false,
                    ),
                      ],
                    ),
                    // ── 章节标题组 ──
                    _buildSettingsGroup(
                      context,
                      l10n.novelSectionTitle,
                      searchQuery: searchController.text,
                      leading: Icons.title,
                      searchTerms: const <String>[
                        '章节标题',
                        '标题',
                        '位置',
                        '字体',
                        '分段',
                        '字号',
                      ],
                      children: <Widget>[
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.novelShowChapterTitle),
                          value: prefs.showChapterTitleInBody,
                          onChanged: (v) => onChanged(
                              prefs.copyWith(showChapterTitleInBody: v)),
                        ),
                        if (prefs.showChapterTitleInBody) ...<Widget>[
                          Text(
                            l10n.novelTitlePosition,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: AppTokens.spaceXs),
                          Wrap(
                            spacing: AppTokens.spaceSm,
                            runSpacing: AppTokens.spaceSm,
                            children: <Widget>[
                              for (final a in NovelTitleAlign.values)
                                ChoiceChip(
                                  label: Text(_titleAlignLabel(a, l10n)),
                                  selected: prefs.titleAlign == a,
                                  onSelected: (_) => onChanged(
                                      prefs.copyWith(titleAlign: a)),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppTokens.spaceMd),
                          _SliderRow(
                            label: l10n.novelTitleFontScale,
                            value: prefs.titleFontScale,
                            min: 1.0,
                            max: 2.5,
                            divisions: 15,
                            onChanged: (v) => onChanged(
                                prefs.copyWith(titleFontScale: v)),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.novelTitleBold),
                            value: prefs.titleBold,
                            onChanged: (v) =>
                                onChanged(prefs.copyWith(titleBold: v)),
                          ),
                          _fontFileTile(
                            context: context,
                            l10n: l10n,
                            title: true,
                          ),
                          const Divider(height: 1),
                          const SizedBox(height: AppTokens.spaceSm),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.novelTitleSegmentMode),
                            value: prefs.titleSegmentMode,
                            onChanged: (v) => onChanged(
                                prefs.copyWith(titleSegmentMode: v)),
                          ),
                          if (prefs.titleSegmentMode) ...<Widget>[
                            _SliderRow(
                              label: l10n.novelTitleSubScale,
                              value: prefs.titleSubScale,
                              min: 0.4,
                              max: 1.5,
                              divisions: 22,
                              onChanged: (v) => onChanged(
                                  prefs.copyWith(titleSubScale: v)),
                            ),
                            _SliderRow(
                              label: l10n.novelTitleSegmentSpacing,
                              value: prefs.titleSegmentSpacing,
                              min: 0,
                              max: 32,
                              divisions: 32,
                              unit: 'px',
                              onChanged: (v) => onChanged(
                                  prefs.copyWith(titleSegmentSpacing: v)),
                            ),
                            _SliderRow(
                              label: l10n.novelTitleSubLineSpacing,
                              value: prefs.titleSubLineSpacing,
                              min: 1.0,
                              max: 2.5,
                              divisions: 30,
                              onChanged: (v) => onChanged(
                                  prefs.copyWith(titleSubLineSpacing: v)),
                            ),
                            _SliderRow(
                              label: l10n.novelTitleTopMargin,
                              value: prefs.titleTopMargin,
                              min: 0,
                              max: 48,
                              divisions: 48,
                              unit: 'px',
                              onChanged: (v) => onChanged(
                                  prefs.copyWith(titleTopMargin: v)),
                            ),
                            _SliderRow(
                              label: l10n.novelTitleBottomMargin,
                              value: prefs.titleBottomMargin,
                              min: 0,
                              max: 48,
                              divisions: 48,
                              unit: 'px',
                              onChanged: (v) => onChanged(
                                  prefs.copyWith(titleBottomMargin: v)),
                            ),
                          ],
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.novelTitleColor),
                            subtitle: prefs.titleColor == null
                                ? Text(l10n.novelTitleColorAuto)
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (prefs.titleColor != null)
                                  IconButton(
                                    icon: const Icon(Icons.backspace_outlined),
                                    tooltip: l10n.novelTitleColorAuto,
                                    onPressed: () => onChanged(
                                        prefs.copyWith(titleColor: null)),
                                  ),
                                GestureDetector(
                                  onTap: () async {
                                    // #6 修复：确认式取色（OK/Cancel），仅用户点确定时写回，避免非手势 pop 崩溃。
                                    Color? pickedColor;
                                    final Color initial =
                                        prefs.titleColor != null
                                            ? Color(prefs.titleColor!)
                                            : ReaderTokens.emphasisDefault;
                                    final color = await showDialog<Color>(
                                      context: context,
                                      builder: (ctx) => StatefulBuilder(
                                        builder: (ctx2, setDialogState) =>
                                            AlertDialog(
                                          title: Text(l10n.novelTitleColor),
                                          content: SingleChildScrollView(
                                            child: ColorPicker(
                                              pickerColor: pickedColor ?? initial,
                                              onColorChanged: (c) => setDialogState(() => pickedColor = c),
                                            ),
                                          ),
                                          actions: <Widget>[
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(),
                                              child: Text(
                                                MaterialLocalizations.of(ctx)
                                                    .cancelButtonLabel,
                                              ),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(
                                                      pickedColor ?? initial),
                                              child: Text(
                                                MaterialLocalizations.of(ctx)
                                                    .okButtonLabel,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                    if (color != null) {
                                      onChanged(prefs.copyWith(
                                          titleColor: color.toARGB32()));
                                    }
                                  },
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: prefs.titleColor != null
                                          ? Color(prefs.titleColor!)
                                          : ReaderTokens.emphasisDefault,
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    // ── 页眉页脚组 ──
                    _buildSettingsGroup(
                      context,
                      l10n.novelSectionHeaderFooter,
                      searchQuery: searchController.text,
                      leading: Icons.view_headline,
                      searchTerms: const <String>[
                        '页眉',
                        '页脚',
                        '时间',
                        '电量',
                        '页数',
                        '进度',
                      ],
                      children: <Widget>[
                        _buildHfSlotPicker(
                          context: context,
                          l10n: l10n,
                          l10n.novelHeaderLeft,
                          prefs.headerLeft,
                          (v) => onChanged(prefs.copyWith(headerLeft: v)),
                        ),
                        _buildHfSlotPicker(
                          context: context,
                          l10n: l10n,
                          l10n.novelHeaderCenter,
                          prefs.headerCenter,
                          (v) => onChanged(prefs.copyWith(headerCenter: v)),
                        ),
                        _buildHfSlotPicker(
                          context: context,
                          l10n: l10n,
                          l10n.novelHeaderRight,
                          prefs.headerRight,
                          (v) => onChanged(prefs.copyWith(headerRight: v)),
                        ),
                        const Divider(height: 1),
                        const SizedBox(height: AppTokens.spaceSm),
                        _buildHfSlotPicker(
                          context: context,
                          l10n: l10n,
                          l10n.novelFooterLeft,
                          prefs.footerLeft,
                          (v) => onChanged(prefs.copyWith(footerLeft: v)),
                        ),
                        _buildHfSlotPicker(
                          context: context,
                          l10n: l10n,
                          l10n.novelFooterCenter,
                          prefs.footerCenter,
                          (v) => onChanged(prefs.copyWith(footerCenter: v)),
                        ),
                        _buildHfSlotPicker(
                          context: context,
                          l10n: l10n,
                          l10n.novelFooterRight,
                          prefs.footerRight,
                          (v) => onChanged(prefs.copyWith(footerRight: v)),
                        ),
                        const Divider(height: 1),
                        const SizedBox(height: AppTokens.spaceSm),
                        _colorTile(
                          context: context,
                          l10n: l10n,
                          title: l10n.novelHeaderFooterColor,
                          subtitle: prefs.headerFooterColor == null
                              ? l10n.novelTextColorFollowBg
                              : null,
                          current: prefs.headerFooterColor,
                          fallback: const Color(0xFF1A1A1A),
                          onPicked: (c) => onChanged(
                              prefs.copyWith(headerFooterColor: c)),
                          onClear: () =>
                              onChanged(prefs.copyWith(headerFooterColor: null)),
                          clearTooltip: l10n.novelTextColorFollowBg,
                        ),
                        _SliderRow(
                          label: l10n.novelHeaderFooterMargin,
                          value: prefs.headerFooterMargin,
                          min: 0,
                          max: 48,
                          divisions: 48,
                          unit: 'px',
                          onChanged: (v) => onChanged(
                              prefs.copyWith(headerFooterMargin: v)),
                        ),
                      ],
                    ),
                    // ── 阴影与下划线组 ──
                    _buildSettingsGroup(
                      context,
                      l10n.novelSectionShadowUnderline,
                      searchQuery: searchController.text,
                      leading: Icons.format_color_text,
                      searchTerms: const <String>[
                        '阴影',
                        '下划线',
                        '颜色',
                        '虚线',
                        '阴影色',
                      ],
                      children: <Widget>[
                        // 文字阴影开关（从「颜色与背景」组移入）
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.novelTextShadow),
                          value: prefs.shadow,
                          onChanged: (v) =>
                              onChanged(prefs.copyWith(shadow: v)),
                        ),
                        // 阴影颜色（仅在开启阴影时可调；可清除为跟随正文色）
                        if (prefs.shadow)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.novelShadowColor),
                            subtitle: prefs.shadowColor == null
                                ? Text(l10n.novelShadowColorAuto)
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (prefs.shadowColor != null)
                                  IconButton(
                                    icon: const Icon(Icons.backspace_outlined),
                                    tooltip: l10n.novelShadowColorAuto,
                                    onPressed: () => onChanged(
                                        prefs.copyWith(shadowColor: null)),
                                  ),
                                GestureDetector(
                                  onTap: () async {
                                    // #6 修复：确认式取色（OK/Cancel），仅用户点确定时写回，避免非手势 pop 崩溃。
                                    Color? pickedColor;
                                    final Color initial = prefs.shadowColor !=
                                            null
                                        ? Color(prefs.shadowColor!)
                                        : const Color(0x4D000000);
                                    final color = await showDialog<Color>(
                                      context: context,
                                      builder: (ctx) => StatefulBuilder(
                                        builder: (ctx2, setDialogState) =>
                                            AlertDialog(
                                          title: Text(l10n.novelShadowColor),
                                          content: SingleChildScrollView(
                                            child: ColorPicker(
                                              pickerColor: pickedColor ?? initial,
                                              onColorChanged: (c) => setDialogState(() => pickedColor = c),
                                            ),
                                          ),
                                          actions: <Widget>[
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(),
                                              child: Text(
                                                MaterialLocalizations.of(ctx)
                                                    .cancelButtonLabel,
                                              ),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(
                                                      pickedColor ?? initial),
                                              child: Text(
                                                MaterialLocalizations.of(ctx)
                                                    .okButtonLabel,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                    if (color != null) {
                                      onChanged(prefs.copyWith(
                                          shadowColor: color.toARGB32()));
                                    }
                                  },
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: prefs.shadowColor != null
                                          ? Color(prefs.shadowColor!)
                                          : const Color(0x4D000000),
                                      border: Border.all(
                                        color:
                                            Theme.of(context).colorScheme.outline,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (prefs.shadow) ...<Widget>[
                          _SliderRow(
                            label: l10n.novelShadowBlur,
                            value: prefs.shadowBlur,
                            min: 0,
                            max: 8,
                            divisions: 32,
                            unit: 'px',
                            onChanged: (v) =>
                                onChanged(prefs.copyWith(shadowBlur: v)),
                          ),
                          _SliderRow(
                            label: l10n.novelShadowOffsetX,
                            value: prefs.shadowOffsetX,
                            min: -8,
                            max: 8,
                            divisions: 32,
                            unit: 'px',
                            onChanged: (v) =>
                                onChanged(prefs.copyWith(shadowOffsetX: v)),
                          ),
                          _SliderRow(
                            label: l10n.novelShadowOffsetY,
                            value: prefs.shadowOffsetY,
                            min: -8,
                            max: 8,
                            divisions: 32,
                            unit: 'px',
                            onChanged: (v) =>
                                onChanged(prefs.copyWith(shadowOffsetY: v)),
                          ),
                        ],
                        const Divider(height: 1),
                        const SizedBox(height: AppTokens.spaceSm),
                        // fontUnderline 开关已移至「字体样式」组，
                        // 这里保留下划线颜色 / 虚线 / 线宽 / 段长 / 间隙。
                        if (prefs.fontUnderline) ...<Widget>[
                          _colorTile(
                            context: context,
                            l10n: l10n,
                            title: l10n.novelUnderlineColor,
                            subtitle: prefs.underlineColor == null
                                ? l10n.novelUnderlineColorAuto
                                : null,
                            current: prefs.underlineColor,
                            fallback: const Color(0xFF1A1A1A),
                            onPicked: (c) =>
                                onChanged(prefs.copyWith(underlineColor: c)),
                            onClear: () =>
                                onChanged(prefs.copyWith(underlineColor: null)),
                            clearTooltip: l10n.novelUnderlineColorAuto,
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.novelUnderlineDashed),
                            value: prefs.underlineDashed,
                            onChanged: (v) =>
                                onChanged(prefs.copyWith(underlineDashed: v)),
                          ),
                          _SliderRow(
                            label: l10n.novelUnderlineThickness,
                            value: prefs.underlineThickness,
                            min: 0.5,
                            max: 6,
                            divisions: 22,
                            unit: 'px',
                            onChanged: (v) => onChanged(
                                prefs.copyWith(underlineThickness: v)),
                          ),
                          if (prefs.underlineDashed) ...<Widget>[
                            _SliderRow(
                              label: l10n.novelUnderlineDashLength,
                              value: prefs.underlineDashLength,
                              min: 1,
                              max: 16,
                              divisions: 30,
                              unit: 'px',
                              onChanged: (v) => onChanged(
                                  prefs.copyWith(underlineDashLength: v)),
                            ),
                            _SliderRow(
                              label: l10n.novelUnderlineDashGap,
                              value: prefs.underlineDashGap,
                              min: 0,
                              max: 16,
                              divisions: 32,
                              unit: 'px',
                              onChanged: (v) => onChanged(
                                  prefs.copyWith(underlineDashGap: v)),
                            ),
                          ],
                        ],
                      ],
                    ),
                    // ── 翻页与交互组 ──
                    _buildSettingsGroup(
                      context,
                      l10n.novelSectionPage,
                      searchQuery: searchController.text,
                      leading: Icons.gesture,
                      searchTerms: const <String>[
                        '翻页',
                        '动画',
                        '点击',
                        '自动翻页',
                        '手势',
                        '分区',
                      ],
                      children: <Widget>[
                    // 翻页动画
                    Text(l10n.novelPageAnimation,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: AppTokens.spaceXs),
                    Wrap(
                      spacing: AppTokens.spaceSm,
                      runSpacing: AppTokens.spaceSm,
                      children: <Widget>[
                        for (final anim in NovelPageAnimation.values)
                          ChoiceChip(
                            label: Text(_animLabel(anim, l10n)),
                            selected: prefs.pageAnimation == anim,
                            onSelected: (_) =>
                                onChanged(prefs.copyWith(pageAnimation: anim)),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    // 点击分区布局（FR-4.2，5 布局）
                    Row(
                      children: <Widget>[
                        Text(l10n.readerTapZone,
                            style: Theme.of(context).textTheme.bodyMedium),
                        const Spacer(),
                        TextButton(
                          onPressed: onShowTapZonePreview,
                          child: Text(l10n.tapZonePreview),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.spaceXs),
                    Wrap(
                      spacing: AppTokens.spaceSm,
                      runSpacing: AppTokens.spaceSm,
                      children: <Widget>[
                        for (final layout in ReaderTapZoneLayout.values)
                          ChoiceChip(
                            label: Text(_tapLayoutLabel(l10n, layout)),
                            selected: prefs.tapZoneLayout == layout,
                            onSelected: (_) => onChanged(
                                prefs.copyWith(tapZoneLayout: layout)),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    // 点击分区方向反转（FR-4.2）
                    Text(l10n.readerTapInvert,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: AppTokens.spaceXs),
                    Wrap(
                      spacing: AppTokens.spaceSm,
                      runSpacing: AppTokens.spaceSm,
                      children: <Widget>[
                        for (final invert in TapZoneInvert.values)
                          ChoiceChip(
                            label: Text(_tapInvertLabel(l10n, invert)),
                            selected: prefs.tapZoneInvert == invert,
                            onSelected: (_) => onChanged(
                                prefs.copyWith(tapZoneInvert: invert)),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    // 自动翻页间隔（M3.5.2）
                    Text(l10n.autoPageInterval,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: AppTokens.spaceXs),
                    Wrap(
                      spacing: AppTokens.spaceSm,
                      runSpacing: AppTokens.spaceSm,
                      children: <Widget>[
                        for (final v in const <int>[0, 3, 5, 10, 15])
                          ChoiceChip(
                            label: Text(v == 0 ? l10n.autoPageOff : '${v}s'),
                            selected: prefs.autoPageInterval == v,
                            onSelected: (_) => onChanged(
                                prefs.copyWith(autoPageInterval: v)),
                          ),
                      ],
                    ),
                      ],
                    ),
                    // ── 朗读组 ──
                    _buildSettingsGroup(
                      context,
                      l10n.novelSectionTts,
                      searchQuery: searchController.text,
                      leading: Icons.record_voice_over,
                      searchTerms: const <String>[
                        '朗读',
                        '语速',
                        '睡眠',
                        '后台',
                        '语音',
                      ],
                      children: <Widget>[
                        ListenableBuilder(
                          listenable: tts,
                          builder: (BuildContext ctx, Widget? _) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              _SliderRow(
                                label: l10n.ttsRate,
                                value: tts.rate,
                                min: 0.5,
                                max: 2.0,
                                divisions: 30,
                                onChanged: (v) {
                                  tts.setRate(v);
                                  onChanged(
                                      prefs.copyWith(ttsSpeechRate: v));
                                },
                              ),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.timer_outlined),
                                title: Text(l10n.ttsSleepTimer),
                                subtitle: tts.sleepRemaining != null
                                    ? Text(l10n.ttsSleepRemaining(
                                        tts.sleepRemaining!.inMinutes,
                                        tts.sleepRemaining!.inSeconds % 60))
                                    : null,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _pickSleepTimer(
                                  context: context,
                                  l10n: l10n,
                                ),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(l10n.novelTtsBackground),
                                value: prefs.ttsBackground,
                                onChanged: (v) => onChanged(
                                    prefs.copyWith(ttsBackground: v)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // ── 高级组 ──
                    _buildSettingsGroup(
                      context,
                      l10n.novelSectionMisc,
                      searchQuery: searchController.text,
                      leading: Icons.tune,
                      searchTerms: const <String>[
                        '简繁',
                        '缓存',
                        '恢复',
                        '配置',
                        '工具栏',
                        '转换',
                      ],
                      children: <Widget>[
                    // 繁简转换（M3.5.1）
                    Text(l10n.chineseConverter,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: AppTokens.spaceXs),
                    Wrap(
                      spacing: AppTokens.spaceSm,
                      runSpacing: AppTokens.spaceSm,
                      children: <Widget>[
                        ChoiceChip(
                          label: Text(l10n.noConvert),
                          selected: prefs.chineseConvert == 'none',
                          onSelected: (_) => onChanged(
                              prefs.copyWith(chineseConvert: 'none')),
                        ),
                        ChoiceChip(
                          label: Text(l10n.traditionalToSimplified),
                          selected: prefs.chineseConvert ==
                              'traditionalToSimplified',
                          onSelected: (_) => onChanged(prefs.copyWith(
                              chineseConvert: 'traditionalToSimplified')),
                        ),
                        ChoiceChip(
                          label: Text(l10n.simplifiedToTraditional),
                          selected: prefs.chineseConvert ==
                              'simplifiedToTraditional',
                          onSelected: (_) => onChanged(prefs.copyWith(
                              chineseConvert: 'simplifiedToTraditional')),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    const Divider(height: 1),
                    const SizedBox(height: AppTokens.spaceMd),
                    // 缓存本书到本地（离线阅读）
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.download_outlined),
                      title: Text(l10n.novelCacheBook),
                      onTap: onCache,
                    ),
                    // 恢复本书默认设置（清除按书覆盖，回到全局默认）
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.restart_alt),
                      title: Text(l10n.novelResetBookPrefs),
                      onTap: onResetBook,
                    ),
                      ],
                    ),
                    if (searchController.text.trim().isNotEmpty &&
                        !hasSearchMatch)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppTokens.spaceLg),
                        child: Center(
                          child: Column(
                            children: <Widget>[
                              Icon(Icons.search_off,
                                  size: 40,
                                  color: Theme.of(context).hintColor),
                              const SizedBox(height: AppTokens.spaceSm),
                              Text(
                                l10n.novelSettingsNoResult,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 常用置顶卡片：字号 / 亮度 / 背景 / 夜间 / 翻页动画 快捷入口。
  Widget _buildCommonCard(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.22),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.star_outline,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    l10n.novelSettingsCommon,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceSm),
              _SliderRow(
                label: l10n.novelFontSize,
                value: prefs.fontSize,
                min: 12,
                max: 32,
                divisions: 20,
                unit: 'sp',
                onChanged: (v) => onChanged(prefs.copyWith(fontSize: v)),
              ),
              _SliderRow(
                label: l10n.novelBrightness,
                value: brightness,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: onBrightnessChanged,
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(l10n.readerBackground, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppTokens.spaceXs),
              Wrap(
                spacing: AppTokens.spaceSm,
                runSpacing: AppTokens.spaceSm,
                children: <Widget>[
                  for (int i = 0; i < ReaderTokens.bgPresets.length; i++)
                    ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: ReaderTokens.bgPresets[i],
                              border: Border.all(
                                color: theme.colorScheme.outline
                                    .withValues(alpha: 0.6),
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(_bgLabel(i, l10n)),
                        ],
                      ),
                      selected: prefs.bgPresetIndex == i &&
                          prefs.customBgColor == null,
                      onSelected: (_) => onChanged(prefs.copyWith(
                        bgPresetIndex: i,
                        customBgColor: null,
                      )),
                    ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceSm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.nightMode),
                value: prefs.nightMode,
                onChanged: (v) =>
                    onChanged(prefs.copyWith(nightMode: v)),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(l10n.novelPageAnimation, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppTokens.spaceXs),
              Wrap(
                spacing: AppTokens.spaceSm,
                runSpacing: AppTokens.spaceSm,
                children: <Widget>[
                  for (final anim in NovelPageAnimation.values)
                    ChoiceChip(
                      label: Text(_animLabel(anim, l10n)),
                      selected: prefs.pageAnimation == anim,
                      onSelected: (_) => onChanged(
                          prefs.copyWith(pageAnimation: anim)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 颜色选择瓦片：点击色块弹出取色器，右侧有「清除（恢复默认）」按钮。
  /// 预览色块：夜间模式下在原始色基础上压暗，与 [NovelReaderPreferences
  /// .resolveBackgroundColor] 的夜间处理保持一致，做到「所见即所得」。
  Color _swatchColor(Color c) {
    if (!prefs.nightMode) return c;
    return Color.lerp(c, Colors.black, ReaderTokens.nightDarkenFactor) ?? c;
  }

  Widget _colorTile({
    required BuildContext context,
    required AppLocalizations l10n,
    required String title,
    String? subtitle,
    required int? current,
    required Color fallback,
    required ValueChanged<int> onPicked,
    required VoidCallback onClear,
    required String clearTooltip,
  }) {
    final displayed = Color(current ?? fallback.value);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          GestureDetector(
            onTap: () async {
            // #6 修复：确认式取色（OK/Cancel），仅用户点确定时写回；
            // onColorChanged 同步写入局部变量，避免滑块回弹。
            Color? pickedColor;
              final Color initial = displayed;
              final result = await showDialog<Color>(
                context: context,
                builder: (ctx) => StatefulBuilder(
                  builder: (BuildContext ctx2, StateSetter setDialogState) {
                    return AlertDialog(
                      title: Text(title),
                      content: SingleChildScrollView(
                        child: ColorPicker(
                          pickerColor: pickedColor ?? initial,
                          onColorChanged: (c) => setDialogState(() => pickedColor = c),
                        ),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(
                            MaterialLocalizations.of(ctx).cancelButtonLabel,
                          ),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(ctx).pop(pickedColor ?? initial),
                          child: Text(
                            MaterialLocalizations.of(ctx).okButtonLabel,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
              if (result != null) onPicked(result.value);
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: displayed,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: clearTooltip,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }

  /// 字体文件选择瓦片：从本机选取 .ttf/.otf 字体并加载（[title]=true 时作用于标题字体）。
  Widget _fontFileTile({
    required BuildContext context,
    required AppLocalizations l10n,
    required bool title,
  }) {
    final currentPath =
        title ? prefs.titleCustomFontPath : prefs.customFontPath;
    final label = title ? l10n.novelTitleFontFile : l10n.novelChooseFontFile;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.font_download_outlined),
      title: Text(label),
      subtitle: currentPath != null
          ? Text(l10n.novelFontFileCurrent(
              currentPath.split(RegExp(r'[/\\]')).last))
          : null,
      trailing: currentPath != null
          ? IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.novelClearFontFile,
              onPressed: () => onChanged(
                title
                    ? prefs.copyWith(titleCustomFontPath: null)
                    : prefs.copyWith(customFontPath: null),
              ),
            )
          : null,
      onTap: () async {
        String? path;
        try {
          if (Platform.isAndroid) {
            // 读外部字体文件可能需要存储权限；被拒也继续尝试（部分设备用系统选择器即可）。
            try {
              await Permission.storage.request();
            } on Object {
              // 忽略权限请求异常
            }
          }
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: <String>['ttf', 'otf'],
          );
          path = result?.files.single.path;
        } on Object {
          path = null;
        }
        if (path == null || !context.mounted) return;
        try {
          await NovelReaderPreferences.loadCustomFont(
            title
                ? NovelReaderPreferences.customLoadedTitleFontFamily
                : NovelReaderPreferences.customLoadedFontFamily,
            path!,
          );
          onChanged(
            title
                ? prefs.copyWith(titleCustomFontPath: path)
                : prefs.copyWith(customFontPath: path),
          );
        } on Object {
          // 加载失败静默忽略
        }
      },
    );
  }

  /// 页眉/页脚单槽内容选择器：点按弹出单选菜单（无/书名/标题/时间/电量/页数/进度…）。
  Widget _buildHfSlotPicker(
    String label,
    NovelHeaderFooterContent value,
    ValueChanged<NovelHeaderFooterContent> onChanged, {
    required BuildContext context,
    required AppLocalizations l10n,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(_hfContentLabel(value, l10n)),
      onTap: () async {
        final picked = await showDialog<NovelHeaderFooterContent>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(label),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final c in NovelHeaderFooterContent.values)
                    RadioListTile<NovelHeaderFooterContent>(
                      title: Text(_hfContentLabel(c, l10n)),
                      value: c,
                      groupValue: value,
                      onChanged: (v) => Navigator.of(ctx).pop(v),
                    ),
                ],
              ),
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }

  /// 标题对齐方式标签（左/中/右/隐藏）。
  String _titleAlignLabel(NovelTitleAlign a, AppLocalizations l10n) {
    return switch (a) {
      NovelTitleAlign.left => l10n.novelTitleAlignLeft,
      NovelTitleAlign.center => l10n.novelTitleAlignCenter,
      NovelTitleAlign.right => l10n.novelTitleAlignRight,
      NovelTitleAlign.hidden => l10n.novelTitleAlignHidden,
    };
  }

  /// 朗读睡眠定时选择（分钟；0 = 关闭）。
  /// 预设 0/15/30/45/60/90 分钟，并提供「自定义」可输入任意分钟数
  /// （满足「自定义朗读时间」需求）。返回选中的分钟数（null = 取消）。
  /// 朗读睡眠定时选择（分钟；0 = 关闭）。设置面板入口。
  Future<void> _pickSleepTimer({
    required BuildContext context,
    required AppLocalizations l10n,
  }) async {
    final picked = await _pickSleepMinutes(
      context: context,
      l10n: l10n,
      current: tts.sleepRemaining?.inMinutes ?? 0,
    );
    if (picked == null) return;
    // 同时写回 prefs（持久化）并启动 controller 定时器，
    // 修复 Bug-3：选了不写回 prefs 导致重启后丢失。
    tts.startSleepTimer(picked);
    onChanged(prefs.copyWith(ttsSleepTimer: picked));
  }

  String _bgLabel(int index, AppLocalizations l10n) {
    return switch (index) {
      0 => l10n.readerBgBlack,
      1 => l10n.readerBgDarkGray,
      2 => l10n.readerBgWhite,
      3 => l10n.readerBgEyeCare,
      4 => l10n.readerBgParchment,
      5 => l10n.readerBgWarmLinen,
      6 => l10n.readerBgLightBrown,
      7 => l10n.readerBgBeanGreen,
      8 => l10n.readerBgMint,
      9 => l10n.readerBgApricot,
      10 => l10n.readerBgGrayBlue,
      _ => l10n.readerBgWhite,
    };
  }
}

/// 翻页动画标签（与漫画共用 l10n key）。
String _animLabel(NovelPageAnimation anim, AppLocalizations l10n) {
  return switch (anim) {
    NovelPageAnimation.none => l10n.novelAnimNone,
    NovelPageAnimation.slide => l10n.novelAnimSlide,
    NovelPageAnimation.scroll => l10n.novelAnimScroll,
    NovelPageAnimation.fade => l10n.novelAnimFade,
    NovelPageAnimation.cover => l10n.novelAnimCover,
    NovelPageAnimation.simulation => l10n.novelAnimSimulation,
  };
}

/// 点击分区布局的本地化标签（与漫画共用 l10n key）。
String _tapLayoutLabel(AppLocalizations l10n, ReaderTapZoneLayout layout) {
  switch (layout) {
    case ReaderTapZoneLayout.lShape:
      return l10n.readerTapLShape;
    case ReaderTapZoneLayout.leftRight:
      return l10n.readerTapLeftRight;
    case ReaderTapZoneLayout.kindle:
      return l10n.readerTapKindle;
    case ReaderTapZoneLayout.bothSides:
      return l10n.readerTapBothSides;
    case ReaderTapZoneLayout.off:
      return l10n.readerTapOff;
  }
}

/// 点击分区方向反转的本地化标签（与漫画共用 l10n key）。
String _tapInvertLabel(AppLocalizations l10n, TapZoneInvert invert) {
  switch (invert) {
    case TapZoneInvert.none:
      return l10n.readerTapInvertNone;
    case TapZoneInvert.leftRight:
      return l10n.readerTapInvertLeftRight;
    case TapZoneInvert.upDown:
      return l10n.readerTapInvertUpDown;
    case TapZoneInvert.all:
      return l10n.readerTapInvertAll;
  }
}

/// 设置面板可折叠分组（P1-C）：标题一行 + 可展开内容，内置箭头动画。
/// 去掉 ExpansionTile 默认的上下分割线，样式与设置面板统一。
Widget _buildSettingsGroup(
  BuildContext context,
  String title, {
  bool initiallyExpanded = false,
  IconData? leading,
  List<String> searchTerms = const <String>[],
  String searchQuery = '',
  required List<Widget> children,
}) {
  // 搜索过滤：query 非空时，仅当组标题或别名命中才显示本组。
  final q = searchQuery.trim().toLowerCase();
  if (q.isNotEmpty) {
    final hay = <String>[title, ...searchTerms].join(' ').toLowerCase();
    if (!hay.contains(q)) return const SizedBox.shrink();
  }
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
    child: Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.18),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMd,
            vertical: AppTokens.spaceXs,
          ),
          leading: leading == null
              ? null
              : Icon(leading, size: 20, color: theme.colorScheme.primary),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppTokens.spaceMd,
            0,
            AppTokens.spaceMd,
            AppTokens.spaceMd,
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          initiallyExpanded: initiallyExpanded,
          title: Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          children: children,
        ),
      ),
    ),
  );
}

/// 通用滑块行。
class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String? unit;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              unit != null
                  ? '${value.toStringAsFixed(value < 10 ? 1 : 0)}$unit'
                  : value.toStringAsFixed(1),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
