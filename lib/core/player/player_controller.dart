import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'media_kit_backend.dart';
import 'video_player_backend.dart';

/// 播放线路（FR-3.4）：一条可播放 URL 与其展示名（线路 1 / 线路 2 …）。
class VideoLine {
  const VideoLine({required this.name, required this.url, this.headers});

  /// 展示名（如「线路 1」、「备线」等）。
  final String name;

  /// 该线路对应的可播放地址。
  final String url;

  /// 打开该线路所需 HTTP 请求头（反盗链 Referer / UA 等）。
  final Map<String, String>? headers;
}

/// 视频播放器控制器。
///
/// 封装 [MediaKitBackend]（持有底层 [Player]），对外暴露播放控制、状态流、
/// 锁定、倍速、解码 / 音频 / 比例切换与自动连播等能力，作为 Provider 层
/// ChangeNotifier 供 UI 绑定。
class PlayerController extends ChangeNotifier {
  PlayerController({Player? player})
      : _backend = MediaKitBackend(player ?? Player()) {
    _initStallDetection();
  }

  final MediaKitBackend _backend;

  /// 自动连播开关。
  bool autoPlayNext = true;

  /// 自动连播回调，由外部（剧集管理器）注入。
  VoidCallback? onAutoPlayNext;

  /// 解析进度：null 表示 indeterminate（不确定）。
  final ValueNotifier<double?> resolveProgress =
      ValueNotifier<double?>(null);

  /// 播放器锁定状态，锁定后禁用手势与控制栏交互。
  bool isLocked = false;

  /// 当前倍速。
  double playbackSpeed = 1.0;

  /// 当前音量（0–100，透传底层 [Player.setVolume]）。
  double volume = 50;

  /// 当前媒体可用的播放线路列表（FR-3.4）。
  /// 解析结果含多线路 URL 时由播放器入口填充；为空表示仅单线路或本地/直链模式。
  List<VideoLine> lines = const <VideoLine>[];

  /// 当前选中的播放线路索引（FR-3.4）。
  int currentLineIndex = 0;

  // ─────────────────────── 静音 / 全屏（P8.3.4 §廿四） ───────────────────────

  /// 是否静音。
  bool _isMuted = false;
  bool get isMuted => _isMuted;

  /// 静音前的音量（取消静音时恢复），默认 100。
  double _volumeBeforeMute = 100.0;

  /// 是否处于全屏模式（横屏锁定 + 沉浸式）。
  bool _isFullscreen = false;
  bool get isFullscreen => _isFullscreen;

  /// 切换静音：静音时缓存当前音量；取消静音时恢复。
  Future<void> toggleMute() async {
    if (_isMuted) {
      await _backend.player.setVolume(_volumeBeforeMute);
      _isMuted = false;
    } else {
      // 缓存当前音量（不低于 0），再静音。
      final cur = _backend.player.state.volume;
      if (cur > 0) _volumeBeforeMute = cur;
      await _backend.player.setVolume(0);
      _isMuted = true;
    }
    notifyListeners();
  }

  /// 切换全屏：进入时锁定横屏 + 隐藏系统 UI；退出时还原。
  Future<void> toggleFullscreen() async {
    _isFullscreen = !_isFullscreen;
    try {
      if (_isFullscreen) {
        await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
        );
      } else {
        await SystemChrome.setPreferredOrientations(<DeviceOrientation>[]);
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
        );
      }
    } on Object {
      // 测试环境或当前平台不支持，忽略。
    }
    notifyListeners();
  }

  /// Seek 宽限期：seek 后该时长内不触发 stall（卡顿）检测。
  final Duration _seekGracePeriod = const Duration(seconds: 5);

  /// Stall 超时：播放中位置超过该时长未推进则判定为卡顿。
  final Duration _stallTimeout = const Duration(seconds: 10);

  // ─────────────────────── Stall 检测（P4.1.4） ───────────────────────
  StreamSubscription<Duration>? _stallPositionSub;
  StreamSubscription<bool>? _stallPlayingSub;
  Timer? _stallCheckTimer;
  Duration _lastStallPosition = Duration.zero;
  DateTime _lastPositionAdvancedAt = DateTime.now();
  DateTime _lastSeekAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isPlayingForStall = false;
  final StreamController<void> _stallController =
      StreamController<void>.broadcast();

  /// Stall（卡顿）事件流：播放中位置超时未推进（超过 [_stallTimeout]）
  /// 且已过 seek 宽限期（[_seekGracePeriod]）时触发一次，UI 可据此提示
  /// 并自动重连。
  Stream<void> get stallStream => _stallController.stream;

  void _initStallDetection() {
    _stallPositionSub = _backend.player.stream.position.listen((pos) {
      if (pos != _lastStallPosition) {
        _lastStallPosition = pos;
        _lastPositionAdvancedAt = DateTime.now();
      }
    });
    _stallPlayingSub = _backend.player.stream.playing.listen((playing) {
      _isPlayingForStall = playing;
      if (playing) {
        _lastPositionAdvancedAt = DateTime.now();
      }
    });
    _stallCheckTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkStall(),
    );
  }

  void _checkStall() {
    if (!_isPlayingForStall || _stallController.isClosed) return;
    final now = DateTime.now();
    // seek 宽限期内不检测
    if (now.difference(_lastSeekAt) < _seekGracePeriod) return;
    // 位置未推进超过 stallTimeout → 触发 stall
    if (now.difference(_lastPositionAdvancedAt) >= _stallTimeout) {
      _stallController.add(null);
      // 重置基准，避免连续重复触发；待位置再次推进后重新计时
      _lastPositionAdvancedAt = now;
    }
  }

  /// 暴露底层后端（供 Video 控件获取 [Player]）。
  VideoPlayerBackend get backend => _backend;

  /// 暴露底层 [Player] 实例。
  Player get player => _backend.player;

  // ─────────────────────── 播放控制 ───────────────────────

  /// 打开媒体地址。
  ///
  /// [headers] 透传给 mpv 的 HTTP 请求头（反盗链 Referer / UA 等），
  /// 必须与抓取 m3u8 文本时一致，否则 CDN 返回 403、解不出帧。
  Future<void> open(String url, {Map<String, String>? headers}) async {
    await _backend.player.open(Media(url, httpHeaders: headers));
  }

  /// 继续播放。
  Future<void> play() async {
    await _backend.player.play();
  }

  /// 暂停播放。
  Future<void> pause() async {
    await _backend.player.pause();
  }

  /// 跳转到指定位置。
  Future<void> seek(Duration position) async {
    _lastSeekAt = DateTime.now();
    await _backend.player.seek(position);
  }

  /// 设置音量（0–100，自动 clamp），透传底层 [Player.setVolume]。
  Future<void> setVolume(double v) async {
    final clamped = v.clamp(0.0, 100.0);
    volume = clamped;
    await _backend.player.setVolume(clamped);
    notifyListeners();
  }

  // ─────────────────────── 播放线路（FR-3.4） ───────────────────────

  /// 切换到指定播放线路。
  ///
  /// 更新 [currentLineIndex] 并通过 [_openCurrentLine] 重新打开对应 URL；
  /// 越界索引静默忽略。本地 / 直链模式 [lines] 为空，调用方不应触发。
  Future<void> selectLine(int index) async {
    if (index < 0 || index >= lines.length) return;
    if (index == currentLineIndex) return;
    currentLineIndex = index;
    notifyListeners();
    await _openCurrentLine();
  }

  /// 重新打开当前选中线路的 URL（复用现有 `_player.open(Media(url))` 入口）。
  Future<void> _openCurrentLine() async {
    if (lines.isEmpty) return;
    final line = lines[currentLineIndex];
    if (line.url.isEmpty) return;
    await _backend.player.open(Media(line.url, httpHeaders: line.headers));
  }

  // ─────────────────────── 状态流 ───────────────────────

  /// 播放位置流。
  Stream<Duration> get positionStream => _backend.player.stream.position;

  /// 媒体时长流。
  Stream<Duration> get durationStream => _backend.player.stream.duration;

  /// 播放状态流。
  Stream<bool> get playingStream => _backend.player.stream.playing;

  /// 播放完成流。
  Stream<bool> get completedStream => _backend.player.stream.completed;

  // ─────────────────────── 瞬时状态 ───────────────────────

  /// 当前播放位置。
  Duration get position => _backend.player.state.position;

  /// 媒体总时长。
  Duration get duration => _backend.player.state.duration;

  /// 是否正在播放。
  bool get isPlaying => _backend.player.state.playing;

  /// 是否播放完成。
  bool get isCompleted => _backend.player.state.completed;

  // ─────────────────────── 锁定 ───────────────────────

  /// 切换播放器锁定状态。
  void toggleLock() {
    isLocked = !isLocked;
    notifyListeners();
  }

  // ─────────────────────── 倍速 ───────────────────────

  /// 设置播放倍速。
  Future<void> setPlaybackSpeed(double speed) async {
    playbackSpeed = speed;
    await _backend.player.setRate(speed);
    notifyListeners();
  }

  // ─────────────────────── 字幕 ───────────────────────

  /// 可用字幕轨道列表（实时快照，来自底层 [Player.state.tracks]）。
  List<SubtitleTrack> get subtitleTracks =>
      _backend.player.state.tracks.subtitle;

  /// 用户选中的字幕轨道（偏好，关闭显示时仍保留以便恢复）。
  SubtitleTrack? _currentSubtitleTrack;
  SubtitleTrack? get currentSubtitleTrack => _currentSubtitleTrack;

  /// 字幕偏移（限制在 ±5s）。
  Duration _subtitleDelay = Duration.zero;
  Duration get subtitleDelay => _subtitleDelay;

  /// 字幕显示开关。
  bool _subtitleVisible = false;
  bool get subtitleVisible => _subtitleVisible;

  /// 可用轨道变更流（含音频 / 视频 / 字幕）。
  Stream<Tracks> get tracksStream => _backend.player.stream.tracks;

  /// 当前选中轨道变更流。
  Stream<Track> get trackStream => _backend.player.stream.track;

  /// 设置字幕轨道。传 null 关闭字幕并清除偏好。
  Future<void> setSubtitleTrack(SubtitleTrack? track) async {
    if (track == null) {
      await _backend.player.setSubtitleTrack(SubtitleTrack.no());
      _currentSubtitleTrack = null;
      _subtitleVisible = false;
    } else {
      await _backend.player.setSubtitleTrack(track);
      _currentSubtitleTrack = track;
      _subtitleVisible = true;
    }
    notifyListeners();
  }

  /// 设置字幕偏移，自动限制在 -5s~+5s（通过 mpv `sub-delay` 属性生效）。
  Future<void> setSubtitleDelay(Duration delay) async {
    final ms = delay.inMilliseconds.clamp(-5000, 5000);
    _subtitleDelay = Duration(milliseconds: ms);
    try {
      final platform = _backend.player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty(
          'sub-delay',
          (ms / 1000.0).toStringAsFixed(3),
        );
      }
    } catch (_) {
      // 当前平台不支持 mpv 属性设置（如 Web），忽略。
    }
    notifyListeners();
  }

  /// 切换字幕显示开关。关闭时记住当前轨道，开启时恢复。
  Future<void> setSubtitleVisible(bool visible) async {
    if (visible == _subtitleVisible) return;
    if (visible) {
      final track = _currentSubtitleTrack;
      if (track != null) {
        await _backend.player.setSubtitleTrack(track);
      }
      _subtitleVisible = true;
    } else {
      await _backend.player.setSubtitleTrack(SubtitleTrack.no());
      _subtitleVisible = false;
    }
    notifyListeners();
  }

  // ─────────────────────── 字幕样式（mpv sub-* 属性） ───────────────────────

  /// 设置字幕属性（透传 mpv sub-* 键值对）。
  ///
  /// 平台不支持时（如 Web）静默忽略。
  Future<void> _setSubProperty(String name, String value) async {
    try {
      final platform = _backend.player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty(name, value);
      }
    } catch (_) {
      // 当前平台不支持 mpv 属性设置，忽略。
    }
  }

  /// 字幕字体名称（如 "Sans", "Serif"）。
  Future<void> setSubtitleFont(String font) async {
    await _setSubProperty('sub-font', font);
    notifyListeners();
  }

  /// 字号（像素值，如 "28", "36"）。
  Future<void> setSubtitleFontSize(double size) async {
    await _setSubProperty('sub-font-size', size.toStringAsFixed(1));
    notifyListeners();
  }

  /// 字幕颜色（BGR 十六进制，如 "FFFFFF"=白, "00FFFF"=黄）。
  Future<void> setSubtitleColor(String color) async {
    await _setSubProperty('sub-color', color);
    notifyListeners();
  }

  /// 字幕边框颜色（BGR 十六进制）。
  Future<void> setSubtitleBorderColor(String color) async {
    await _setSubProperty('sub-border-color', color);
    notifyListeners();
  }

  /// 字幕边框宽度（像素值）。
  Future<void> setSubtitleBorderSize(double size) async {
    await _setSubProperty('sub-border-size', size.toStringAsFixed(1));
    notifyListeners();
  }

  /// 字幕阴影颜色（BGR 十六进制）。
  Future<void> setSubtitleShadowColor(String color) async {
    await _setSubProperty('sub-shadow-color', color);
    notifyListeners();
  }

  /// 字幕阴影偏移（像素值）。
  Future<void> setSubtitleShadowOffset(double offset) async {
    await _setSubProperty('sub-shadow-offset', offset.toStringAsFixed(1));
    notifyListeners();
  }

  /// 字幕缩放比例（如 "1.5" 放大 50%）。
  Future<void> setSubtitleScale(double scale) async {
    await _setSubProperty('sub-scale', scale.toStringAsFixed(2));
    notifyListeners();
  }

  /// 字幕垂直位置（"top", "center", "bottom" 或 0-100 百分比）。
  Future<void> setSubtitlePosition(String pos) async {
    await _setSubProperty('sub-pos', pos);
    notifyListeners();
  }

  /// 是否覆盖 ASS/SSA 样式（"yes"/"no"/"strip"/"force"）。
  Future<void> setSubtitleAssOverride(String mode) async {
    await _setSubProperty('sub-ass-override', mode);
    notifyListeners();
  }

  // ─────────────────────── 后端能力委托 ───────────────────────

  /// 设置硬件解码模式（委托后端）。
  Future<void> setHwdec(String mode) async {
    await _backend.setHwdec(mode);
    notifyListeners();
  }

  /// 设置音频通道（委托后端）。
  Future<void> setAudioChannel(String channel) async {
    await _backend.setAudioChannel(channel);
    notifyListeners();
  }

  /// 设置画面比例（委托后端）。
  Future<void> setAspectRatio(String ratio) async {
    await _backend.setAspectRatio(ratio);
    notifyListeners();
  }

  /// 当前解码模式。
  String get currentHwdec => _backend.currentHwdec;

  /// 当前音频通道。
  String get currentAudioChannel => _backend.currentAudioChannel;

  /// 当前画面比例。
  String get currentAspectRatio => _backend.currentAspectRatio;

  @override
  void dispose() {
    _stallCheckTimer?.cancel();
    _stallPositionSub?.cancel();
    _stallPlayingSub?.cancel();
    _stallController.close();
    resolveProgress.dispose();
    _backend.player.dispose();
    // 退出时若仍处于全屏，还原方向与系统 UI（P8.3.4 §廿四）
    if (_isFullscreen) {
      try {
        SystemChrome.setPreferredOrientations(<DeviceOrientation>[]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } on Object {
        // 测试环境忽略。
      }
    }
    super.dispose();
  }
}
