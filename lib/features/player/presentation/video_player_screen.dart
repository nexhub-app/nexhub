import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart' as cd;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:hive/hive.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/danmaku/bilibili_danmaku_service.dart';
import '../../../core/danmaku/danmaku_repository.dart';
import '../../../core/danmaku/danmaku_settings.dart';
import '../../../core/danmaku/danmaku_source.dart';
import '../../../core/danmaku/dandanplay_service.dart';
import '../../../core/favorites/favorites_manager.dart';
import '../../../core/history/media_playback_position_manager.dart';
import '../../../core/models/episode.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/player/player_controller.dart';
import '../../../core/player/widgets/seek_bar.dart';
import '../../../core/resolver/webview_resolver.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/services/source_repository.dart';
import '../../verification/presentation/webview_verification_screen.dart';
import '../../../core/settings/danmaku_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_error_state.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:cast/cast.dart';
import 'package:floating/floating.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/widgets/danmaku.dart';
import '../../../core/widgets/danmaku_overlay.dart';
import '../cast/cast_service.dart';
import 'danmaku_settings_sheet.dart';
import 'danmaku_source_sheet.dart';
import 'subtitle_panel.dart';

/// 视频手势坐标轴状态机：避免横滑（seek）与竖滑（亮度 / 音量）冲突。
///
/// 一旦 [onVerticalDragStart] / [onHorizontalDragStart] 判定方向，即锁定该轴
/// 直到对应 `onEnd` 重置回 [none]，update 期间不切换轴。
enum _GestureAxis { none, horizontal, verticalLeft, verticalRight }

/// 视频播放页（Phase 5）。
///
/// - 从源解析真实可播放地址（[MediaApiService.fetchVideoUrl]）
/// - [PlayerController] + [MediaKitBackend] 提供播放内核
/// - 自定义控件：播放/暂停/进度/锁定/连播/解码模式/音频通道/画面比例
/// - 弹幕覆盖层按视频进度注入（[DanmakuController] + [DanmakuOverlay]）
/// - 弹幕来源：弹弹play（签名 + 搜索匹配）→ Bilibili fallback
///
/// 本地模式（Task O4.B.2）：传入 [localUri] 时进入本地模式，跳过在线源解析，
/// 直接用 [Player] + [VideoController] 打开本地文件。本地模式下隐藏切换线路 /
/// 下一集等在线专属按钮，保留弹幕（可选）、进度记忆（用 [itemId] =
/// `'local_${file.path.hashCode}'`）、播放器设置。调用方需将 [itemId] 设为
/// `'local_${file.path.hashCode}'`，[episode] 可用文件名构造占位 Episode。
class VideoPlayerScreen extends StatefulWidget {
  final String title;
  final Episode episode;
  final String sourceId;
  final String itemId;

  /// 可选：全集列表（用于自动连播与上下集切换）。
  final List<Episode>? episodes;

  /// 可选：初始剧集索引（在 [episodes] 中的位置）。
  final int? initialEpisodeIndex;

  /// 可选：切集回调（外部刷新详情页状态时使用）。
  final ValueChanged<Episode>? onEpisodeChange;

  /// 可选：收藏类型（用于播放器内收藏按钮）。若提供则顶栏显示收藏按钮。
  final SourceType? favoriteType;

  /// 本地模式：本地视频文件路径（跳过在线源解析，直接打开）。
  final String? localUri;

  /// 直链播放地址（视频嗅探器等场景）：非空时跳过在线源解析，直接播放该 URL。
  final String? directUrl;

  /// 详情页 URL（用于收藏时透传，避免历史/收藏详情灰屏）。
  final String? detailUrl;

  /// 封面 URL（用于收藏时透传，避免收藏书架缺封面）。
  final String? coverUrl;

  const VideoPlayerScreen({
    super.key,
    required this.title,
    required this.episode,
    required this.sourceId,
    required this.itemId,
    this.episodes,
    this.initialEpisodeIndex,
    this.onEpisodeChange,
    this.favoriteType,
    this.localUri,
    this.directUrl,
    this.detailUrl,
    this.coverUrl,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final PlayerController _controller;
  VideoController? _videoController;

  final DanmakuController _danmakuController = DanmakuController();
  final GlobalKey<DanmakuOverlayState> _danmakuKey =
      GlobalKey<DanmakuOverlayState>();
  DanmakuSettings _danmakuSettings = const DanmakuSettings();
  DanmakuRepository? _danmakuRepo;
  bool _danmakuOn = true;

  /// 是否为本地文件 / 直链模式（跳过在线源解析，直接打开给定地址）。
  bool get _isDirectMode => widget.localUri != null || widget.directUrl != null;

  /// 当前弹幕源（持久化到 SharedPreferences，键 `danmaku_source`）。
  DanmakuSourceType _danmakuSource = DanmakuSourceType.dandanplay;

  /// SharedPreferences 中保存弹幕源选择的键。
  static const String _kDanmakuSourceKey = 'danmaku_source';

  /// #6 A4-#6: 自定义弹幕 URL（持久化键 `danmaku_custom_url`）。
  String _customDanmakuUrl = '';

  /// #6 A4-#6: SharedPreferences 中保存自定义 URL 的键。
  static const String _kDanmakuCustomUrlKey = 'danmaku_custom_url';

  /// Current playable URL (used for sharing).
  String? _playUrl;

  /// 自定义截图保存目录（空 = 默认 Documents/screenshots）。
  String? _customScreenshotDir;

  /// 当前播放地址所需的 HTTP 请求头（反盗链 Referer / UA 等），
  /// 与解析抓取 m3u8 文本时一致；打开地址（mpv 拉分片）必须带上，
  /// 否则 CDN 返回 403、解不出帧、画面全黑。
  Map<String, String>? _playHeaders;

  /// Sleep timer for auto-pausing playback.
  Timer? _sleepTimer;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<void>? _stallSub;

  /// 下一集是否已预解析（进度>80% 时后台拉取地址写入 VideoSourceCache）。
  /// 切集时重置为 false。
  bool _nextEpisodePreloaded = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _uiVisible = true;
  bool _isFav = false;

  // ─────────────────────── 手势 / 亮度 / 音量（P8.3.4 §廿四 + 视频还原） ───────────────────────

  /// 当前手势轴（横滑 / 左竖滑 / 右竖滑），锁定后直到 onEnd 才重置。
  _GestureAxis _dragAxis = _GestureAxis.none;

  /// 手势起点系统亮度（0..1），用于左竖滑按 delta 计算新亮度。
  double _dragStartBrightness = 0;

  /// 手势起点播放器音量（0..100），用于右竖滑按 delta 计算新音量。
  double _dragStartVolume = 50;

  /// 横滑 seek 预览目标时间，松手后跳转。
  Duration _seekPreview = Duration.zero;

  /// 当前系统亮度缓存（init 时从 [ScreenBrightness.instance.application] 读取）。
  double _brightness = 0.5;

  /// 手势指示器当前展示的内容（任一非 null 即显示对应数值）。
  String? _gestureIndicatorText;

  /// 手势指示器可见性（[AnimatedOpacity] 驱动）。
  bool _gestureIndicatorVisible = false;

  /// 手势指示器自动淡出计时器（约 800ms）。
  Timer? _gestureIndicatorTimer;

  /// 上次自动保存播放位置的时间（节流，每 5 秒存一次）。
  DateTime _lastPositionSaveAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 当前剧集索引（若有全集列表）。
  late int _episodeIndex;

  late Future<void> _initFuture;

  final CastService _castService = CastService();
  bool _isCasting = false;

  /// 键盘焦点节点（P8.3.4 §廿四 键盘快捷键）。
  final FocusNode _focusNode = FocusNode();

  /// 屏幕亮度插件实例（手势调节系统亮度）。
  final ScreenBrightness _brightnessPlugin = ScreenBrightness();

  @override
  void initState() {
    super.initState();
    _controller = PlayerController();
    _controller.addListener(_onControllerChanged);
    _episodeIndex = widget.initialEpisodeIndex ?? 0;
    _initFuture = _init();
  }

  /// PlayerController 状态变更（字幕显隐 / 全屏 / 音量 / 线路）触发 UI 重建。
  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// 解析视频地址，自动处理 webview-html 渲染后抽取（xgcartoon 等源）。
  ///
  /// 若源声明 webview-html，[fetchVideoUrl] 会抛出 [WebViewHtmlRequest]，
  /// 这里弹出内嵌 WebView 取回渲染 HTML 并回填重试，直至拿到真实可播放地址。
  Future<VideoResult> _resolveVideoWithCapture(
    MediaApiService service,
    PluginConfig source,
    String episodeUrl, {
    String? renderedHtml,
  }) async {
    try {
      return await service.fetchVideoUrl(source, episodeUrl,
          renderedHtml: renderedHtml);
    } on WebViewHtmlRequest catch (e) {
      if (!mounted) rethrow;
      final outcome = await navigateToHtmlCapture(context, request: e);
      if (outcome?.hasRenderedHtml == true) {
        return _resolveVideoWithCapture(
          service,
          source,
          episodeUrl,
          renderedHtml: outcome!.renderedHtml,
        );
      }
      throw Exception('video capture cancelled');
    }
  }

  Future<void> _init() async {
    // 创建 VideoController 并打开媒体
    _videoController = VideoController(_controller.player);

    // 同步当前系统亮度（手势起点基准）与播放器音量（PlayerController.volume）。
    try {
      _brightness = await _brightnessPlugin.current;
    } on Object {
      _brightness = 0.5;
    }
    try {
      _controller.volume = _controller.player.state.volume;
      _dragStartVolume = _controller.volume;
    } on Object {
      // 取底层音量失败，沿用默认 50。
    }

    if (_isDirectMode) {
      // 本地 / 直链模式：跳过在线源解析，直接打开给定地址。
      final direct = widget.directUrl ?? widget.localUri!;
      _playUrl = direct;
      await _controller.open(direct);
    } else {
      final repo = context.read<SourceRepository>();
      final service = context.read<MediaApiService>();
      final source = repo.getById(widget.sourceId);
      if (source == null) {
        throw Exception('source not found: ${widget.sourceId}');
      }

      // 解析视频地址（自动处理渲染后抽取）
      final video =
          await _resolveVideoWithCapture(service, source, widget.episode.url);
      _playUrl = video.url;
      _playHeaders = video.headers;

      // 当前沿解析管线仅返回单线路 URL；将其填充为唯一线路，供线路面板展示。
      // 后续若解析器扩展为返回多线路，可在 VideoResult 增加 lines 字段并在此合并。
      if (video.url.isNotEmpty) {
        _controller.lines = <VideoLine>[
          VideoLine(name: _lineName(0), url: video.url, headers: video.headers),
        ];
        _controller.currentLineIndex = 0;
      }

      await _controller.open(video.url, headers: video.headers);
      // 解析成功后自动开始播放
      _controller.play();
    }

    // 恢复上次播放位置（P8.1.2 §廿一 续读进度跨章节恢复）
    await _restoreSavedPosition();

    // 监听播放状态
    _positionSub = _controller.positionStream.listen(_onPositionChanged);
    _completedSub = _controller.completedStream.listen(_onCompleted);
    // 监听 stall（卡顿）事件：提示并自动重连
    _stallSub = _controller.stallStream.listen((_) => _onStall());

    // 初始化弹幕仓库
    _initDanmakuRepository();

    // 读取用户上次选择的弹幕源
    await _loadDanmakuSourcePref();

    // 读取自定义截图保存目录
    try {
      final prefs = await SharedPreferences.getInstance();
      _customScreenshotDir = prefs.getString('screenshot_custom_dir');
    } on Object {
      // 读取失败，使用默认路径
    }

    // 尝试加载弹幕（本地 / 直链模式无剧集元数据，跳过自动匹配；
    // 用户仍可通过弹幕源面板切换到自定义 URL 手动加载）。
    if (!_isDirectMode) {
      _loadDanmaku();
    }

    // 刷新收藏状态（P9.1.7 §16.1 顶栏收藏按钮）
    _refreshFavorite();

    if (mounted) setState(() {});
  }

  /// 从 SharedPreferences 读取弹幕源选择。
  Future<void> _loadDanmakuSourcePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_kDanmakuSourceKey);
      if (name != null) {
        _danmakuSource = DanmakuSourceType.values.firstWhere(
          (e) => e.name == name,
          orElse: () => DanmakuSourceType.dandanplay,
        );
      }
      // #6 A4-#6: 同步加载自定义 URL。
      _customDanmakuUrl = prefs.getString(_kDanmakuCustomUrlKey) ?? '';
    } on Object {
      // 读取失败，沿用默认值。
    }
  }

  void _initDanmakuRepository() {
    try {
      final cacheBox = Hive.box<dynamic>('danmaku_cache');
      final configStore = DanmakuConfigStore();
      _danmakuRepo = DanmakuRepository(
        dandanplay: DandanplayService(configStore: configStore),
        bilibili: BilibiliDanmakuService(),
        cacheBox: cacheBox,
      );
    } on Object {
      // Hive box 未打开或服务不可用，静默降级（无弹幕）。
      _danmakuRepo = null;
    }
  }

  Future<void> _loadDanmaku() async {
    if (_danmakuRepo == null) return;
    // 关闭弹幕源：清空并跳过加载。
    if (_danmakuSource == DanmakuSourceType.off) {
      _danmakuController.clear();
      return;
    }
    // #6 A4-#6: 自定义 URL 源且 URL 为空时，提示并跳过。
    if (_danmakuSource == DanmakuSourceType.customUrl &&
        _customDanmakuUrl.isEmpty) {
      _danmakuController.clear();
      return;
    }
    try {
      final items = await _danmakuRepo!.getDanmaku(
        sourceId: widget.sourceId,
        episodeId: widget.episode.id,
        dandanplayEpisodeId: _danmakuSource == DanmakuSourceType.bilibili
            ? null
            : widget.episode.dandanplayEpisodeId,
        bilibiliCid: _danmakuSource == DanmakuSourceType.dandanplay
            ? null
            : widget.episode.bilibiliCid,
        bangumiId: widget.episode.bangumiId,
        danmakuUrl: _danmakuSource == DanmakuSourceType.customUrl
            ? _customDanmakuUrl
            : widget.episode.danmakuUrl,
      );
      // 过滤并转换为 DanmakuItem
      final filtered = items
          .where((i) => !_danmakuSettings.shouldFilter(i.text))
          .map((i) => i.toDanmakuItem())
          .toList();
      _danmakuController.setItems(filtered);
    } on Object {
      // 弹幕加载失败，静默忽略。
    }
  }

  void _onPositionChanged(Duration position) {
    _position = position;
    if (_duration == Duration.zero) {
      _duration = _controller.duration;
    }
    // 注入弹幕
    if (_danmakuOn) {
      final adjusted = position +
          Duration(
              milliseconds:
                  (_danmakuSettings.timeOffset * 1000).round());
      _danmakuController.tick(adjusted);
    }
    // 预解析下一集（进度>80% 触发，后台拉地址写入 VideoSourceCache）
    _maybePreloadNextEpisode();
    // 节流保存播放位置（每 5 秒）
    _maybeSavePosition();
    if (mounted) setState(() {});
  }

  /// 节流保存播放位置：每 5 秒写一次到 MediaPlaybackPositionManager。
  void _maybeSavePosition() {
    final now = DateTime.now();
    if (now.difference(_lastPositionSaveAt) < const Duration(seconds: 5)) return;
    _lastPositionSaveAt = now;
    try {
      final mgr = context.read<MediaPlaybackPositionManager>();
      unawaited(mgr.savePosition(
          widget.itemId, _episodeIndex, _position.inMilliseconds));
    } on Object {
      // Manager 不可用时静默忽略。
    }
  }

  /// 恢复上次播放位置：从 MediaPlaybackPositionManager 读取并 seek。
  Future<void> _restoreSavedPosition() async {
    try {
      final mgr = context.read<MediaPlaybackPositionManager>();
      final savedMs = mgr.getPosition(widget.itemId, _episodeIndex);
      if (savedMs > 5000) {
        // 超过 5 秒才恢复，避免片头闪现
        await _controller.seek(Duration(milliseconds: savedMs));
      }
    } on Object {
      // Manager 不可用时静默忽略。
    }
  }

  void _onCompleted(bool completed) {
    if (!completed) return;
    // 播完清除该集播放位置，避免下次续播已看完的集
    try {
      final mgr = context.read<MediaPlaybackPositionManager>();
      unawaited(mgr.clearPosition(widget.itemId, _episodeIndex));
    } on Object {
      // Manager 不可用时静默忽略。
    }
    // 自动连播
    if (_controller.autoPlayNext &&
        widget.episodes != null &&
        _episodeIndex < widget.episodes!.length - 1) {
      _goNextEpisode();
    }
  }

  void _goNextEpisode() {
    if (widget.episodes == null || _episodeIndex >= widget.episodes!.length - 1) {
      return;
    }
    _changeEpisode(_episodeIndex + 1);
  }

  /// 预解析下一集：当前集播放进度>80% 时后台拉取下一集地址，
  /// 命中 [VideoSourceCache] 后 `_changeEpisode` 切集时秒切。
  /// 每集只触发一次，切集时重置。
  void _maybePreloadNextEpisode() {
    if (_nextEpisodePreloaded) return;
    if (widget.episodes == null || _duration == Duration.zero) return;
    if (_episodeIndex >= widget.episodes!.length - 1) return;
    // 进度 > 80% 触发
    if (_position.inMilliseconds <= _duration.inMilliseconds * 0.8) return;
    _nextEpisodePreloaded = true;
    final repo = context.read<SourceRepository>();
    final service = context.read<MediaApiService>();
    final source = repo.getById(widget.sourceId);
    if (source == null) return;
    final nextEp = widget.episodes![_episodeIndex + 1];
    // 后台拉取，结果由 BuiltinResolver 写入 VideoSourceCache；不 await、不阻塞 UI。
    unawaited(
      service.fetchVideoUrl(source, nextEp.url).catchError((_) =>
          const VideoResult(url: '', type: 'unknown')),
    );
  }

  /// Stall（卡顿）处理：弹 SnackBar 提示并自动重新 open 当前地址恢复播放。
  void _onStall() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.playerStallDetected),
        duration: const Duration(seconds: 2),
      ),
    );
    unawaited(_reconnect());
  }

  /// 重新 open 当前播放地址恢复播放。
  Future<void> _reconnect() async {
    final url = _playUrl;
    if (url == null || url.isEmpty) return;
    try {
      await _controller.open(url, headers: _playHeaders);
      await _controller.play();
    } on Object {
      // 重连失败，静默忽略。
    }
  }

  void _goPrevEpisode() {
    if (_episodeIndex <= 0) return;
    _changeEpisode(_episodeIndex - 1);
  }

  Future<void> _changeEpisode(int index) async {
    if (widget.episodes == null || index < 0 || index >= widget.episodes!.length) {
      return;
    }
    _sleepTimer?.cancel();
    _sleepTimer = null;
    // 保存当前集播放位置（P8.1.2）
    _saveCurrentPosition();
    setState(() {
      _episodeIndex = index;
      _position = Duration.zero;
      _nextEpisodePreloaded = false;
      _lastPositionSaveAt = DateTime.fromMillisecondsSinceEpoch(0);
    });

    final ep = widget.episodes![index];
    widget.onEpisodeChange?.call(ep);

    final repo = context.read<SourceRepository>();
    final service = context.read<MediaApiService>();
    final source = repo.getById(widget.sourceId);
    if (source == null) return;

    try {
      final video =
          await _resolveVideoWithCapture(service, source, ep.url);
      _playUrl = video.url;
      _playHeaders = video.headers;
      // 切集后刷新线路列表（当前仅单线路）。
      if (video.url.isNotEmpty) {
        _controller.lines = <VideoLine>[
          VideoLine(name: _lineName(0), url: video.url, headers: video.headers),
        ];
        _controller.currentLineIndex = 0;
      }
      await _controller.open(video.url, headers: video.headers);
      // 切集后自动播放
      _controller.play();
      _danmakuController.clear();
      _danmakuController.reset();
      // 重新加载弹幕（使用新剧集 ID）
      _loadDanmakuForEpisode(ep);
      // 恢复新剧集的上次播放位置
      await _restoreSavedPosition();
    } on Object {
      // 切集失败，静默忽略。
    }
  }

  /// 保存当前集播放位置到 MediaPlaybackPositionManager。
  void _saveCurrentPosition() {
    try {
      final mgr = context.read<MediaPlaybackPositionManager>();
      unawaited(mgr.savePosition(
          widget.itemId, _episodeIndex, _position.inMilliseconds));
    } on Object {
      // Manager 不可用时静默忽略。
    }
  }

  Future<void> _loadDanmakuForEpisode(Episode ep) async {
    if (_danmakuRepo == null) return;
    // 关闭弹幕源：清空并跳过加载。
    if (_danmakuSource == DanmakuSourceType.off) {
      _danmakuController.clear();
      return;
    }
    try {
      final items = await _danmakuRepo!.getDanmaku(
        sourceId: widget.sourceId,
        episodeId: ep.id,
        dandanplayEpisodeId: _danmakuSource == DanmakuSourceType.bilibili
            ? null
            : ep.dandanplayEpisodeId,
        bilibiliCid: _danmakuSource == DanmakuSourceType.dandanplay
            ? null
            : ep.bilibiliCid,
        bangumiId: ep.bangumiId,
        danmakuUrl: ep.danmakuUrl,
      );
      final filtered = items
          .where((i) => !_danmakuSettings.shouldFilter(i.text))
          .map((i) => i.toDanmakuItem())
          .toList();
      _danmakuController.setItems(filtered);
    } on Object {
      // 静默忽略。
    }
  }

  void _toggleDanmaku() {
    setState(() => _danmakuOn = !_danmakuOn);
    if (!_danmakuOn) {
      _danmakuKey.currentState?.clear();
    }
  }

  void _toggleUi() {
    setState(() => _uiVisible = !_uiVisible);
  }

  void _toggleLock() {
    _controller.toggleLock();
    // 延迟 setState 到当前事件帧结束后，避免在手势回调栈中
    // 销毁控制层子 widget（如 TextField / FocusNode）导致异常。
    if (mounted) {
      Future<void>.microtask(() {
        if (mounted) setState(() {});
      });
    }
  }

  // ─────────────────────── 手势 / 亮度 / 音量（视频还原） ───────────────────────

  /// 生成线路展示名（线路 1 / 线路 2 …），按 1 起编号。
  String _lineName(int index) {
    final l10n = AppLocalizations.of(context);
    return '${l10n.playerLine} ${index + 1}';
  }

  /// 相对当前播放位置 seek 指定偏移（负值快退，正值快进），自动 clamp 到 [0, _duration]。
  Future<void> _seekBy(Duration offset) async {
    if (_duration == Duration.zero) return;
    final target = _position + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    await _onSeek(clamped);
  }

  /// 设置系统亮度（0..1）并刷新手势指示器。
  Future<void> _setBrightness(double v) async {
    final clamped = v.clamp(0.0, 1.0);
    final l10n = AppLocalizations.of(context);
    _brightness = clamped;
    try {
      await _brightnessPlugin.setScreenBrightness(clamped);
    } on Object {
      // 平台不支持时静默忽略。
    }
    _showGestureIndicator('${l10n.playerBrightness}: ${(clamped * 100).round()}%');
  }

  /// 设置播放器音量（0..100，经 PlayerController 透传）并刷新手势指示器。
  Future<void> _setVolume(double v) async {
    final l10n = AppLocalizations.of(context);
    await _controller.setVolume(v);
    _showGestureIndicator(
        '${l10n.playerVolume}: ${_controller.volume.round()}%');
  }

  /// 显示手势指示器约 800ms 后自动淡出。
  ///
  /// 多次连续触发会重置计时器，指示器保持显示直到最后一次触发后 800ms。
  void _showGestureIndicator(String text) {
    _gestureIndicatorTimer?.cancel();
    setState(() {
      _gestureIndicatorText = text;
      _gestureIndicatorVisible = true;
    });
    _gestureIndicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() => _gestureIndicatorVisible = false);
      }
    });
  }

  /// 中央手势指示器浮层：显示双击 ±10s / 亮度 % / 音量 % / 横滑 seek 目标时间。
  Widget _buildGestureIndicator() {
    return IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          opacity: _gestureIndicatorVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
              vertical: AppTokens.spaceSm,
            ),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(AppTokens.spaceSm),
            ),
            child: Text(
              _gestureIndicatorText ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────── 截图（边缘按钮 + 菜单共用） ───────────────────────

  /// 抽出 [_takeScreenshot] 的核心实现，供边缘常驻按钮与「更多」菜单共用。
  ///
  /// 使用 media_kit 的 [Player.screenshot] 截取当前帧，
  /// 保存为 PNG 到截图目录（默认 Documents/screenshots 或用户自定义）。
  Future<void> _captureAndSaveScreenshot(AppLocalizations l10n) async {
    try {
      final Uint8List? bytes = await _controller.player.screenshot();
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.screenshotFailed)),
          );
        }
        return;
      }
      Directory baseDir;
      if (_customScreenshotDir != null && _customScreenshotDir!.isNotEmpty) {
        baseDir = Directory(_customScreenshotDir!);
        if (!await baseDir.exists()) {
          await baseDir.create(recursive: true);
        }
      } else {
        final docDir = await getApplicationDocumentsDirectory();
        baseDir = Directory(p.join(docDir.path, 'screenshots'));
        if (!await baseDir.exists()) {
          await baseDir.create(recursive: true);
        }
      }
      final String fileName =
          'nexhub_${DateTime.now().millisecondsSinceEpoch}.png';
      final File file = File(p.join(baseDir.path, fileName));
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.screenshotSaved)),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.screenshotFailed}: $e')),
        );
      }
    }
  }

  /// 选择自定义截图保存目录。
  Future<void> _pickScreenshotDirectory(AppLocalizations l10n) async {
    try {
      final String? selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: l10n.playerScreenshot,
      );
      if (selected == null || selected.isEmpty) return;
      setState(() => _customScreenshotDir = selected);
      // 持久化到 SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('screenshot_custom_dir', selected);
      } on Object {
        // 写入失败不影响功能
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(selected)),
        );
      }
    } on Object {
      // 用户取消或平台不支持，静默忽略
    }
  }

  /// 刷新收藏状态（P9.1.7 §16.1 顶栏收藏按钮）。
  void _refreshFavorite() {
    final type = widget.favoriteType;
    if (type == null) return;
    try {
      final fav = context.read<FavoritesManager>();
      _isFav = fav.isFavorite(widget.itemId, type);
    } on Object {
      // FavoritesManager 不可用时静默忽略。
    }
  }

  /// 切换收藏状态（P9.1.7 §16.1 顶栏收藏按钮）。
  Future<void> _toggleFavorite() async {
    final type = widget.favoriteType;
    if (type == null) return;
    final l10n = AppLocalizations.of(context);
    final fav = context.read<FavoritesManager>();
    final wasFavorite = _isFav;
    final item = MediaItem(
      id: widget.itemId,
      title: widget.title,
      sourceId: widget.sourceId,
      sourceType: type,
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

  // ─────────────────────── 键盘快捷键（P8.3.4 §廿四） ───────────────────────

  /// 处理键盘事件：空格=播放/暂停，左右=seek ±10s，F=全屏，M=静音。
  /// 返回 `KeyEventResult.handled` 表示已处理，否则 `ignored`。
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // 仅响应 key down（避免重复触发），且锁定时不响应（除解锁外）。
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      if (_controller.isLocked) return KeyEventResult.handled;
      if (_isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
      setState(() => _isPlaying = !_isPlaying);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_controller.isLocked) return KeyEventResult.handled;
      final target = (_position - const Duration(seconds: 10));
      final clamped = target < Duration.zero ? Duration.zero : target;
      unawaited(_onSeek(clamped));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (_controller.isLocked) return KeyEventResult.handled;
      final target = (_position + const Duration(seconds: 10));
      final clamped = target > _duration ? _duration : target;
      unawaited(_onSeek(clamped));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      // 全屏切换即使在锁定状态也允许（与播放器 UI 解耦）。
      unawaited(_controller.toggleFullscreen());
      setState(() {});
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      if (_controller.isLocked) return KeyEventResult.handled;
      unawaited(_controller.toggleMute());
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _onSeek(Duration position) async {
    await _controller.seek(position);
    _danmakuController.clear();
    _danmakuController.reset();
    setState(() => _position = position);
  }

  Future<void> _openDanmakuSettings() async {
    await DanmakuSettingsSheet.show(
      context,
      settings: _danmakuSettings,
      onChanged: (next) {
        setState(() => _danmakuSettings = next);
        _applyDanmakuOption();
      },
    );
  }

  void _openDanmakuSource() async {
    await DanmakuSourceSheet.show(
      context,
      currentSource: _danmakuSource,
      currentCustomUrl: _customDanmakuUrl,
      onChanged: (next) async {
        if (next == _danmakuSource) return;
        setState(() => _danmakuSource = next);
        // 持久化用户选择。
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kDanmakuSourceKey, next.name);
        } on Object {
          // 写入失败静默忽略。
        }
        // 清空并重新加载弹幕。
        _danmakuController.clear();
        _danmakuController.reset();
        _loadDanmaku();
      },
      onCustomUrl: (url) async {
        setState(() {
          _customDanmakuUrl = url;
          _danmakuSource = DanmakuSourceType.customUrl;
        });
        // 持久化 URL 和源选择。
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_kDanmakuCustomUrlKey, url);
          await prefs.setString(_kDanmakuSourceKey, DanmakuSourceType.customUrl.name);
        } on Object {
          // 写入失败静默忽略。
        }
        _danmakuController.clear();
        _danmakuController.reset();
        _loadDanmaku();
      },
    );
  }

  /// 倍速选择面板（底部弹出，点击即生效）。
  void _showSpeedPicker(AppLocalizations l10n) {
    const speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    final current = _controller.playbackSpeed;

    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.playerPlaybackSpeed,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${current}x',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ...speeds.map((s) => ListTile(
              dense: true,
              title: Center(child: Text('${s}x')),
              tileColor: (s == current)
                  ? Theme.of(ctx).colorScheme.primaryContainer
                  : null,
              onTap: () {
                unawaited(_controller.setPlaybackSpeed(s));
                _applyDanmakuOption();
                Navigator.pop(ctx);
              },
            )),
            const SizedBox(height: AppTokens.spaceSm),
          ],
        ),
      ),
    );
  }

  void _applyDanmakuOption() {
    final effectiveDuration =
        _danmakuSettings.effectiveDuration(_controller.playbackSpeed);
    final option = cd.DanmakuOption(
      duration: effectiveDuration.round(),
      fontSize: 16,
      area: _danmakuSettings.area,
      hideTop: _danmakuSettings.hideTop,
      hideBottom: _danmakuSettings.hideBottom,
      hideScroll: _danmakuSettings.hideScroll,
    );
    _danmakuKey.currentState?.updateOption(option);
  }

  /// 显示弹幕输入框（底部轻量对话框）。
  void _showDanmakuInput() {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l10n.danmakuSend ?? '发送弹幕'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.danmakuSendHint ?? '输入弹幕内容',
            border: const OutlineInputBorder(),
          ),
          maxLength: 50,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                // 通过 DanmakuOverlay 注入一条本地弹幕（立即显示）
                final item = DanmakuItem(
                  text: text,
                  time: _position +
                      Duration(
                          milliseconds:
                              (_danmakuSettings.timeOffset * 1000).round()),
                );
                _danmakuKey.currentState?.addSingle(item);
              }
              Navigator.pop(ctx);
            },
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _menuHeader(l10n),
            // 自动连播（本地 / 直链模式无下一集，隐藏）
            if (!_isDirectMode)
              ListTile(
                leading: Icon(
                  _controller.autoPlayNext
                      ? Icons.play_circle
                      : Icons.play_circle_outline,
                ),
                title: Text(l10n.playerAutoPlayNext),
                trailing: Switch(
                  value: _controller.autoPlayNext,
                  onChanged: (v) {
                    setState(() => _controller.autoPlayNext = v);
                    Navigator.pop(ctx);
                  },
                  activeColor: Theme.of(ctx).colorScheme.primary,
                ),
              ),
            // 画中画（从顶栏移入更多菜单）
            ListTile(
              leading: const Icon(Icons.picture_in_picture),
              title: Text(l10n.playerPip),
              onTap: () {
                Navigator.pop(ctx);
                _togglePip(l10n);
              },
            ),
            ListTile(
              leading: const Icon(Icons.memory),
              title: Text(l10n.playerDecodeMode),
              trailing: DropdownButton<String>(
                value: _controller.currentHwdec,
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                      value: 'auto', child: Text(l10n.playerDecodeAuto)),
                  DropdownMenuItem<String>(
                      value: 'sw', child: Text(l10n.playerDecodeSw)),
                  DropdownMenuItem<String>(
                      value: 'hw', child: Text(l10n.playerDecodeHw)),
                  DropdownMenuItem<String>(
                      value: 'hw+', child: Text(l10n.playerDecodeHwPlus)),
                ],
                onChanged: (String? v) {
                  if (v != null) _controller.setHwdec(v);
                  Navigator.pop(ctx);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: Text(l10n.playerAudioChannel),
              trailing: DropdownButton<String>(
                value: _controller.currentAudioChannel,
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                      value: 'auto', child: Text(l10n.playerDecodeAuto)),
                  DropdownMenuItem<String>(
                      value: 'auto-safe', child: Text(l10n.playerAudioAutoProtect)),
                  DropdownMenuItem<String>(
                      value: 'stereo', child: Text(l10n.playerAudioStereo)),
                  DropdownMenuItem<String>(
                      value: 'mono', child: Text(l10n.playerAudioMono)),
                  DropdownMenuItem<String>(
                      value: 'reverse-stereo', child: Text(l10n.playerAudioReverseStereo)),
                ],
                onChanged: (String? v) {
                  if (v != null) _controller.setAudioChannel(v);
                  Navigator.pop(ctx);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.bedtime),
              title: Text(l10n.playerTimer),
              onTap: () {
                Navigator.pop(ctx);
                _showSleepTimerPicker(l10n);
              },
            ),
            // #4 A4-#4: 媒体信息
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.mediaInfo),
              onTap: () {
                Navigator.pop(ctx);
                _showMediaInfo(l10n);
              },
            ),
            // #4 A4-#4: 外部播放
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(l10n.playExternal),
              onTap: () {
                Navigator.pop(ctx);
                _playInExternal(l10n);
              },
            ),
            // #4 A4-#4: 分享（复用 _share）
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(l10n.share),
              onTap: () {
                Navigator.pop(ctx);
                _share(l10n);
              },
            ),
            // 截图保存路径设置
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text(l10n.screenshotPathSetting),
              subtitle: _customScreenshotDir != null
                  ? Text(_customScreenshotDir!,
                      maxLines: 1, overflow: TextOverflow.ellipsis)
                  : Text(l10n.screenshotPathDefault),
              onTap: () {
                Navigator.pop(ctx);
                _pickScreenshotDirectory(l10n);
              },
            ),
            const SizedBox(height: AppTokens.spaceSm),
          ],
          ),
        ),
      ),
    );
  }

  void _showCastSheet(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: FutureBuilder<List<CastDevice>>(
          future: _castService.discover(),
          builder: (BuildContext _, AsyncSnapshot<List<CastDevice>> snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final List<CastDevice> devices = snap.data ?? <CastDevice>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: Text(
                    l10n.castToDevice,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_isCasting)
                  ListTile(
                    leading: const Icon(Icons.cast_connected),
                    title: Text(l10n.castingTo(_castService.deviceName ?? '')),
                    trailing: TextButton(
                      onPressed: () {
              Navigator.pop(context);
                        _disconnectCast(l10n);
                      },
                      child: Text(l10n.castDisconnect),
                    ),
                  ),
                if (!_isCasting && snap.hasError)
                  Padding(
                    padding: const EdgeInsets.all(AppTokens.spaceMd),
                    child: Text(l10n.castNotSupportedOnDevice),
                  ),
                if (!_isCasting && !snap.hasError && devices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppTokens.spaceMd),
                    child: Text(l10n.castNoDevices),
                  ),
                for (final CastDevice d in devices)
                  ListTile(
                    leading: const Icon(Icons.tv),
                    title: Text(d.name),
                    onTap: () {
                      Navigator.pop(ctx);
                      _connectCast(d, l10n);
                    },
                  ),
                const SizedBox(height: AppTokens.spaceSm),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _connectCast(CastDevice device, AppLocalizations l10n) async {
    final String url = _playUrl ?? widget.episode.url;
    try {
      await _castService.connectAndPlay(device, url, title: _episodeTitle);
      await _controller.pause();
      if (mounted) {
        setState(() => _isCasting = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.castingTo(device.name))),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.castNotSupportedOnDevice)),
        );
      }
    }
  }

  Future<void> _disconnectCast(AppLocalizations l10n) async {
    await _castService.disconnect();
    if (mounted) {
      setState(() => _isCasting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.castDisconnect)),
      );
    }
  }

  Future<void> _togglePip(AppLocalizations l10n) async {
    final floating = Floating();
    try {
      final bool available = await floating.isPipAvailable;
      if (!available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.pipNotSupportedOnDevice)),
          );
        }
        return;
      }
      await floating.enable(ImmediatePiP());
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pipNotSupportedOnDevice)),
        );
      }
    }
  }

  Widget _menuHeader(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.spaceMd,
        AppTokens.spaceSm,
        AppTokens.spaceSm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              l10n.playerPlayInfo,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          // 投屏入口（打开设备选择面板）。
          IconButton(
            icon: Icon(Icons.cast, color: _isCasting ? Colors.amber : null),
            tooltip: l10n.cast,
            onPressed: () {
              Navigator.pop(context);
              _showCastSheet(l10n);
            },
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // 退出时保存最后播放位置
    _saveCurrentPosition();
    _sleepTimer?.cancel();
    _gestureIndicatorTimer?.cancel();
    _positionSub?.cancel();
    _completedSub?.cancel();
    _stallSub?.cancel();
    unawaited(_castService.disconnect());
    _focusNode.dispose();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    // 还原系统亮度（避免退出后保留手势调节值）。
    try {
      _brightnessPlugin.resetScreenBrightness();
    } on Object {
      // 平台不支持时静默忽略。
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (BuildContext c, AsyncSnapshot<void> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || _videoController == null) {
            return AppErrorState(
              message: l10n.playerVideoExpired,
              // 注意：setState 的回调必须是 void，不能写 `() => _initFuture = _init()`
              // （赋值表达式会返回 _init() 这个 Future，触发「setState callback returned a Future」崩溃）。
              onRetry: () {
                setState(() {
                  _initFuture = _init();
                });
              },
            );
          }
          return _buildPlayer(l10n);
        },
      ),
    );
  }

  Widget _buildPlayer(AppLocalizations l10n) {
    // 包裹 Focus 以响应键盘快捷键（P8.3.4 §廿四）。
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Stack(
        children: <Widget>[
          // 视频画面 + 手势系统（双击 ±10s / 左竖滑亮度 / 右竖滑音量 / 横滑 seek 预览）
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleUi,
            onDoubleTapDown: (TapDownDetails d) {
              if (_controller.isLocked) return;
              final width = context.size?.width ?? 0;
              final half = width / 2;
              if (d.localPosition.dx < half) {
                // 左半屏双击：快退 10s
                unawaited(_seekBy(const Duration(seconds: -10)));
                _showGestureIndicator(l10n.seekBackward10);
              } else {
                // 右半屏双击：快进 10s
                unawaited(_seekBy(const Duration(seconds: 10)));
                _showGestureIndicator(l10n.seekForward10);
              }
            },
            onVerticalDragStart: (DragStartDetails d) {
              if (_controller.isLocked) return;
              final width = context.size?.width ?? 1;
              _dragAxis = d.localPosition.dx < width / 2
                  ? _GestureAxis.verticalLeft
                  : _GestureAxis.verticalRight;
              _dragStartBrightness = _brightness;
              _dragStartVolume = _controller.volume;
            },
            onVerticalDragUpdate: (DragUpdateDetails d) {
              if (_controller.isLocked) return;
              if (_dragAxis == _GestureAxis.none) return;
              final height = context.size?.height ?? 1;
              // 上滑为正（增量），下滑为负
              final delta = -d.delta.dy / height;
              if (_dragAxis == _GestureAxis.verticalLeft) {
                unawaited(
                    _setBrightness(_dragStartBrightness + delta));
              } else if (_dragAxis == _GestureAxis.verticalRight) {
                unawaited(_setVolume(_dragStartVolume + delta * 100));
              }
            },
            onVerticalDragEnd: (_) {
              _dragAxis = _GestureAxis.none;
            },
            onHorizontalDragStart: (_) {
              if (_controller.isLocked) return;
              _dragAxis = _GestureAxis.horizontal;
              _seekPreview = _position;
            },
            onHorizontalDragUpdate: (DragUpdateDetails d) {
              if (_controller.isLocked) return;
              if (_dragAxis != _GestureAxis.horizontal) return;
              final width = context.size?.width ?? 1;
              final delta = -d.delta.dx / width;
              final next = _seekPreview +
                  Duration(
                      seconds: (delta * _duration.inSeconds).round());
              _seekPreview = next < Duration.zero
                  ? Duration.zero
                  : (next > _duration ? _duration : next);
              _showGestureIndicator(
                  '${_formatDuration(_seekPreview)} / ${_formatDuration(_duration)}');
            },
            onHorizontalDragEnd: (_) {
              if (_controller.isLocked) {
                _dragAxis = _GestureAxis.none;
                return;
              }
              if (_dragAxis == _GestureAxis.horizontal) {
                unawaited(_controller.seek(_seekPreview));
              }
              _dragAxis = _GestureAxis.none;
            },
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Video(
                  controller: _videoController!,
                  controls: NoVideoControls,
                ),
              ),
            ),
          ),

          // 弹幕覆盖层
          Positioned.fill(
            child: IgnorePointer(
              child: DanmakuOverlay(
                key: _danmakuKey,
                enabled: _danmakuOn,
              ),
            ),
          ),

          // 中央手势指示器（锁定态不显示）
          if (!_controller.isLocked) _buildGestureIndicator(),

          // 左边缘常驻锁定按钮（垂直居中；锁定时仍可见，作解锁入口）
          Positioned(
            left: AppTokens.spaceLg,
            top: 0,
            bottom: 0,
            child: Center(
              child: _ControlButton(
                key: const Key('player_lock_edge'),
                icon: _controller.isLocked ? Icons.lock : Icons.lock_open,
                tooltip: _controller.isLocked
                    ? l10n.playerUnlock
                    : l10n.playerLock,
                onTap: _toggleLock,
              ),
            ),
          ),

          // 右边缘常驻截图按钮（垂直居中；锁定态隐藏，避免误触）
          if (!_controller.isLocked)
            Positioned(
              right: AppTokens.spaceLg,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ControlButton(
                  key: const Key('player_screenshot_edge'),
                  icon: Icons.camera_alt,
                  tooltip: l10n.playerScreenshot,
                  onTap: () => unawaited(_captureAndSaveScreenshot(l10n)),
                ),
              ),
            ),

          // 控制层（未锁定时显示）
          if (!_controller.isLocked) ...<Widget>[
            // 顶栏
            if (_uiVisible)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopBar(l10n),
              ),

            // 底栏
            if (_uiVisible)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomBar(l10n),
              ),

            // 中央播放/暂停按钮（仅暂停态显示）
            if (_uiVisible && !_isPlaying)
              Center(
                child: IconButton.filled(
                  key: const Key('player_play_pause'),
                  iconSize: 48,
                  icon: const Icon(Icons.play_arrow),
                  onPressed: () {
                    _controller.play();
                    setState(() => _isPlaying = true);
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopBar(AppLocalizations l10n) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Colors.black54, Colors.transparent],
          ),
        ),
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top,
          left: AppTokens.spaceSm,
          right: AppTokens.spaceSm,
        ),
        child: Row(
          children: <Widget>[
            IconButton(
              key: const Key('player_back'),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            // 滚动媒体名 + 集数（长标题自动横向滚动）
            Expanded(
              child: _MarqueeText(
                text: _episodeTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // 投屏
            IconButton(
              key: const Key('player_cast'),
              icon: Icon(Icons.cast,
                  color: _isCasting ? Colors.amber : Colors.white),
              tooltip: l10n.playerCast,
              onPressed: () => _showCastSheet(l10n),
            ),
            // 字幕
            IconButton(
              key: const Key('player_subtitle'),
              icon: Icon(
                _controller.subtitleVisible
                    ? Icons.subtitles
                    : Icons.subtitles_outlined,
                color: Colors.white,
              ),
              tooltip: l10n.playerSubtitle,
              onPressed: () => SubtitlePanel.show(context, controller: _controller),
            ),
            // 收藏按钮（P9.1.7 §16.1 顶栏收藏，仅 favoriteType 提供时显示）
            if (widget.favoriteType != null)
              IconButton(
                key: const Key('player_favorite'),
                icon: Icon(
                  _isFav ? Icons.favorite : Icons.favorite_border,
                  color: _isFav ? Colors.redAccent : Colors.white,
                ),
                tooltip: l10n.favorite,
                onPressed: _toggleFavorite,
              ),
            // 更多（已瘦身：解码 / 音频 / 媒体信息 / 外部播放 / 定时关闭 / 分享 / PiP / 连播）
            IconButton(
              key: const Key('player_more'),
              icon: const Icon(Icons.more_vert, color: Colors.white),
              tooltip: l10n.playerMore,
              onPressed: () => _showMoreMenu(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(AppLocalizations l10n) {
    final hasPrev = widget.episodes != null && _episodeIndex > 0;
    final hasNext =
        widget.episodes != null && _episodeIndex < widget.episodes!.length - 1;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: <Color>[Colors.black54, Colors.transparent],
          ),
        ),
        padding: EdgeInsets.only(
          left: AppTokens.spaceMd,
          right: AppTokens.spaceMd,
          bottom: MediaQuery.of(context).padding.bottom + AppTokens.spaceSm,
          top: AppTokens.spaceSm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 解析二级进度（加载态可见，复用 PlayerController.resolveProgress）
            ValueListenableBuilder<double?>(
              valueListenable: _controller.resolveProgress,
              builder: (BuildContext _, double? v, Widget? __) {
                if (v == null) return const SizedBox.shrink();
                return Padding(
                  padding:
                      const EdgeInsets.only(bottom: AppTokens.spaceXs),
                  child: LinearProgressIndicator(
                    value: v >= 0 ? v : null,
                    minHeight: 2,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                );
              },
            ),
            // 进度行：SeekBar + 时间 + 内联控件
            SeekBar(
              position: _position,
              duration: _duration,
              onSeek: _onSeek,
            ),
            // 单行控件：时间 | 上一集 | 播放/暂停 | 下一集 | 弹幕 | 弹幕设置 ‖ 倍速 | 比例 | 选集 | 全屏
            // （原两行合并：删去与快捷行完全重复的主控行按钮，弹幕设置紧邻弹幕开关）
            Row(
              children: <Widget>[
                // 时间
                Text(
                  _formatDuration(_position),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                const Text(
                  ' / ',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(width: AppTokens.spaceSm),
                // 上一集
                if (hasPrev)
                  _ControlButton(
                    key: const Key('player_prev_ep'),
                    icon: Icons.skip_previous,
                    tooltip: l10n.playerPreviousEpisode,
                    onTap: _goPrevEpisode,
                  ),
                // 播放 / 暂停
                _ControlButton(
                  key: const Key('player_play_pause_bottom'),
                  icon: _isPlaying ? Icons.pause : Icons.play_arrow,
                  tooltip: _isPlaying ? l10n.pause : l10n.play,
                  onTap: () {
                    if (_isPlaying) {
                      _controller.pause();
                    } else {
                      _controller.play();
                    }
                    setState(() => _isPlaying = !_isPlaying);
                  },
                ),
                // 下一集
                if (hasNext)
                  _ControlButton(
                    key: const Key('player_next_ep'),
                    icon: Icons.skip_next,
                    tooltip: l10n.playerNextEpisode,
                    onTap: _goNextEpisode,
                  ),
                // 弹幕区域（开关 + 发送[开时] + 设置[开时]）
                _DanmakuToggle(
                  key: const Key('player_danmaku_area'),
                  isOn: _danmakuOn,
                  l10n: l10n,
                  onToggle: _toggleDanmaku,
                  onSend: _showDanmakuInput,
                  onSettings: _openDanmakuSettings,
                  onLongPressSettings: _openDanmakuSource,
                ),
                const Spacer(),
                // 倍速（弹出选择面板）
                _ControlButton(
                  key: const Key('player_quick_speed'),
                  icon: Icons.speed,
                  tooltip: '${l10n.playerPlaybackSpeed} ${_controller.playbackSpeed}x',
                  onTap: () => _showSpeedPicker(l10n),
                ),
                // 比例（循环 default / 4:3 / 16:9 / fill）
                _ControlButton(
                  key: const Key('player_quick_aspect'),
                  icon: Icons.aspect_ratio,
                  tooltip: l10n.playerAspectRatio,
                  onTap: () {
                    const ratios = <String>['default', '4:3', '16:9', 'fill'];
                    final cur = _controller.currentAspectRatio;
                    final idx = ratios.indexOf(cur);
                    final next = ratios[(idx + 1) % ratios.length];
                    unawaited(_controller.setAspectRatio(next));
                  },
                ),
                // 选集（本地 / 直链模式隐藏）
                if (!_isDirectMode)
                  _ControlButton(
                    key: const Key('player_quick_episodes'),
                    icon: Icons.video_library,
                    tooltip: l10n.playerEpisodes,
                    onTap: () => _showLineSheet(l10n),
                  ),
                // 全屏
                _ControlButton(
                  key: const Key('player_quick_fullscreen'),
                  icon: _controller.isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  tooltip: _controller.isFullscreen
                      ? l10n.playerExitFullscreen
                      : l10n.playerFullscreen,
                  onTap: () =>
                      unawaited(_controller.toggleFullscreen()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _episodeTitle {
    final ep = widget.episodes != null && widget.episodes!.isNotEmpty
        ? widget.episodes![_episodeIndex.clamp(0, widget.episodes!.length - 1)]
        : widget.episode;
    return '${widget.title} · ${ep.title}';
  }

  // ─────────────────────── 选集 / 线路面板（FR-3.4） ───────────────────────

  /// 弹出选集 + 线路 sheet：上半剧集列表（点击跳集），下半线路切换（点击 selectLine）。
  ///
  /// 本地 / 直链模式 [_isDirectMode] 不应触发（调用方已隐藏入口）；
  /// 若 [_controller.lines] 为空（解析失败），线路分组仍渲染但提示无可用线路。
  void _showLineSheet(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        final episodes = widget.episodes ?? <Episode>[];
        final lines = _controller.lines;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.6,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: Text(
                    l10n.playerEpisodes,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                const Divider(height: 1),
                // 上半：剧集列表
                Expanded(
                  flex: 3,
                  child: ListView.builder(
                    itemCount: episodes.length,
                    itemBuilder: (BuildContext _, int i) {
                      final ep = episodes[i];
                      final selected = i == _episodeIndex;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: selected
                              ? Theme.of(ctx).colorScheme.primary
                              : null,
                          child: Text('${i + 1}'),
                        ),
                        title: Text(
                          ep.title,
                          style: selected
                              ? TextStyle(
                                  color: Theme.of(ctx).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                )
                              : null,
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          if (i != _episodeIndex) _changeEpisode(i);
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                // 下半：播放线路分组
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTokens.spaceMd, AppTokens.spaceSm, AppTokens.spaceMd, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.playerLine,
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: lines.isEmpty
                      ? Center(child: Text(l10n.playerSelectLine))
                      : ListView.builder(
                          itemCount: lines.length,
                          itemBuilder: (BuildContext _, int i) {
                            final line = lines[i];
                            final selected = i == _controller.currentLineIndex;
                            return ListTile(
                              leading: Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                color: selected
                                    ? Theme.of(ctx).colorScheme.primary
                                    : null,
                              ),
                              title: Text(line.name),
                              onTap: () {
                                Navigator.pop(ctx);
                                if (i != _controller.currentLineIndex) {
                                  unawaited(_controller.selectLine(i));
                                }
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

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:$mm:$ss';
    return '$mm:$ss';
  }

  void _showSleepTimerPicker(AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.timer_off),
              title: Text(l10n.playerTimerOff),
              onTap: () {
                Navigator.pop(ctx);
                _sleepTimer?.cancel();
                _sleepTimer = null;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.playerTimerCanceled)),
                );
              },
            ),
            for (final m in <int>[15, 30, 45, 60, 90])
              ListTile(
                leading: const Icon(Icons.timer),
                title: Text(l10n.playerTimerMinutes(m)),
                onTap: () {
                  Navigator.pop(ctx);
                  _setSleepTimer(m, l10n);
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(l10n.playerTimerCustom),
              onTap: () {
                Navigator.pop(ctx);
                _showCustomSleepTimerDialog(l10n);
              },
            ),
            const SizedBox(height: AppTokens.spaceSm),
          ],
        ),
      ),
    );
  }

  void _setSleepTimer(int minutes, AppLocalizations l10n) {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      _controller.pause();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.playerTimerFired)),
        );
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.playerTimerMinutes(minutes))),
    );
  }

  void _showCustomSleepTimerDialog(AppLocalizations l10n) {
    final TextEditingController controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l10n.playerTimer),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: l10n.playerTimerCustom),
          autofocus: true,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              final m = int.tryParse(controller.text.trim());
              if (m != null && m > 0) {
                Navigator.pop(ctx);
                _setSleepTimer(m, l10n);
              }
            },
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  void _share(AppLocalizations l10n) {
    final text = '$_episodeTitle\n${_playUrl ?? widget.episode.url}';
    Share.share(text);
  }

  /// #4 A4-#4: 显示媒体信息（标题/源/剧集/当前 URL/播放进度）。
  void _showMediaInfo(AppLocalizations l10n) {
    final url = _playUrl ?? widget.episode.url;
    final pos = _position.inSeconds;
    final dur = _duration.inSeconds;
    final posStr =
        '${pos ~/ 60}:${(pos % 60).toString().padLeft(2, '0')}';
    final durStr =
        '${dur ~/ 60}:${(dur % 60).toString().padLeft(2, '0')}';
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.mediaInfo,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppTokens.spaceSm),
              Text('${l10n.browseLocalFileTypeVideo}: ${widget.title}'),
              Text(_episodeTitle),
              if (_isDirectMode)
                Text('${l10n.localFileLabel}: ${widget.directUrl ?? widget.localUri}')
              else
                Text('${l10n.videoSourceLine}: ${widget.sourceId}'),
              Text('URL: $url'),
              Text('${l10n.novelHfProgressPercent}: $posStr / $durStr'),
              const SizedBox(height: AppTokens.spaceMd),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// #4 A4-#4: 使用外部播放器打开当前 URL。
  Future<void> _playInExternal(AppLocalizations l10n) async {
    final url = _playUrl ?? widget.episode.url;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.errorParse)));
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.browseNetworkConnect)));
      }
    } on Object {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.errorNetwork)));
      }
    }
  }
}

/// 弹幕开关区域组件：根据开关状态显示不同 UI。
///
/// **开启时**：高亮背景 + 实心图标 + 发送按钮 + 设置按钮
/// **关闭时**：透明背景 + 空心图标（仅开关）
class _DanmakuToggle extends StatelessWidget {
  const _DanmakuToggle({
    super.key,
    required this.isOn,
    required this.l10n,
    required this.onToggle,
    this.onSend,
    this.onSettings,
    this.onLongPressSettings,
  });

  final bool isOn;
  final AppLocalizations l10n;
  final VoidCallback onToggle;
  final VoidCallback? onSend;
  final VoidCallback? onSettings;
  final VoidCallback? onLongPressSettings;

  @override
  Widget build(BuildContext context) {
    if (!isOn) {
      // 关闭态：仅显示空心开关按钮，紧凑尺寸
      return IconButton(
        icon: const Icon(Icons.comment_outlined, color: Colors.white54),
        iconSize: 22,
        tooltip: l10n.danmaku,
        onPressed: onToggle,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: const EdgeInsets.all(4),
      );
    }

    // 开启态：高亮背景 + 实心图标 + 发送 + 设置
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.cyan.withOpacity(0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyan.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 弹幕开关（开启态，实心图标）
          IconButton(
            icon: const Icon(Icons.comment, color: Colors.cyan, size: 20),
            tooltip: l10n.danmaku,
            onPressed: onToggle,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
          ),
          // 发送弹幕按钮（仅开启时显示）
          if (onSend != null)
            IconButton(
              icon: const Icon(Icons.send, color: Colors.white70, size: 18),
              tooltip: l10n.danmakuSend ?? 'Send danmaku',
              onPressed: onSend,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
          // 弹幕设置（长按=弹幕源选择）
          if (onSettings != null)
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white70, size: 18),
              tooltip: l10n.danmakuSettings,
              onPressed: onSettings,
              onLongPress: onLongPressSettings,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

/// 控制按钮（透明背景圆形）。
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.onLongPress,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white),
      tooltip: tooltip,
      onPressed: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// 横向滚动文字（Marquee）：当文本超出可用宽度时自动循环滚动；
/// 文本能完整显示时静止不动（无动画开销）。
///
/// 用 [SingleChildScrollView] 承载文本，由 [AnimationController] 驱动
/// [_scrollController] 手动滚动；避免 ListView.builder(itemCount:null) 在
/// 顶栏 Row 内触发无限高度布局崩溃。
class _MarqueeText extends StatefulWidget {
  const _MarqueeText({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _animController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..addListener(_onAnimTick);

  /// 文本是否需要滚动（测量后确定）。
  bool _scrollable = false;

  @override
  void initState() {
    super.initState();
    // 延迟一帧测量文本宽度，决定是否需要滚动。
    WidgetsBinding.instance.addPostFrameCallback(_measure);
  }

  void _measure(_) {
    final renderer = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    // 容器可用宽度估算（减去返回键 + 右侧图标的大致占用）。
    final maxWidth = MediaQuery.of(context).size.width - 160;
    if (mounted && renderer.width > maxWidth) {
      // 标记需要滚动并启动动画（setState 异步，故动画启动不依赖刚刚写入的 _scrollable）。
      if (mounted) setState(() => _scrollable = true);
      if (!_animController.isAnimating) {
        _animController.repeat();
      }
    }
  }

  void _onAnimTick() {
    if (!_scrollable || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    // 滚到末尾（留 40px 间隙）后回环到起点，形成循环滚动。
    final span = max + 40;
    final v = (_animController.value * span) % span;
    _scrollController.jumpTo(v);
  }

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _scrollable = false;
      _animController.stop();
      WidgetsBinding.instance.addPostFrameCallback(_measure);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _scrollController,
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(widget.text, style: widget.style),
      ),
    );
  }
}
