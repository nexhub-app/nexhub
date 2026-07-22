/// 播放器默认设置模型（全局默认值，播放时可临时覆盖）。
///
/// 持久化到 SharedPreferences（key: `player_settings_v1`），
/// 复用 [PrefsBackend] 抽象以便测试注入。
library;

import 'dart:convert';

import '../comic/models/reader_preferences.dart';

/// 解码模式。
enum DecodeMode { auto, sw, hw, hwPlus }

/// 音频通道。
enum AudioChannel { auto, stereo, mono }

/// 画面比例。
enum PlayerAspectRatio { defaultRatio, ratio43, ratio169, fill }

/// 播放器锁定方向（项 1：合并旧 playerDefaultOrientation + 锁方向）。
enum PlayerLockOrientation { auto, portrait, landscape }

/// 播放器左右拖动 Seek 区间倍率。
enum SeekMultiplier { half, normal, double }

/// 播放器默认设置。
class PlayerSettings {
  final DecodeMode decodeMode;
  final AudioChannel audioChannel;
  final PlayerAspectRatio aspectRatio;
  final double playbackSpeed;
  final bool autoPlayNext;
  final double subtitleFontSize;
  final bool subtitleOutline;
  final PlayerLockOrientation lockOrientation;
  final SeekMultiplier seekMultiplier;
  final bool doubleTapPlayPause;
  final bool longPressSpeedUp;
  final double subtitleBottomMargin;
  final double defaultVolume;

  const PlayerSettings({
    this.decodeMode = DecodeMode.auto,
    this.audioChannel = AudioChannel.auto,
    this.aspectRatio = PlayerAspectRatio.defaultRatio,
    this.playbackSpeed = 1.0,
    this.autoPlayNext = true,
    this.subtitleFontSize = 16.0,
    this.subtitleOutline = true,
    this.lockOrientation = PlayerLockOrientation.auto,
    this.seekMultiplier = SeekMultiplier.normal,
    this.doubleTapPlayPause = true,
    this.longPressSpeedUp = true,
    this.subtitleBottomMargin = 0.0,
    this.defaultVolume = 100.0,
  });

  PlayerSettings copyWith({
    DecodeMode? decodeMode,
    AudioChannel? audioChannel,
    PlayerAspectRatio? aspectRatio,
    double? playbackSpeed,
    bool? autoPlayNext,
    double? subtitleFontSize,
    bool? subtitleOutline,
    PlayerLockOrientation? lockOrientation,
    SeekMultiplier? seekMultiplier,
    bool? doubleTapPlayPause,
    bool? longPressSpeedUp,
    double? subtitleBottomMargin,
    double? defaultVolume,
  }) =>
      PlayerSettings(
        decodeMode: decodeMode ?? this.decodeMode,
        audioChannel: audioChannel ?? this.audioChannel,
        aspectRatio: aspectRatio ?? this.aspectRatio,
        playbackSpeed: playbackSpeed ?? this.playbackSpeed,
        autoPlayNext: autoPlayNext ?? this.autoPlayNext,
        subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
        subtitleOutline: subtitleOutline ?? this.subtitleOutline,
        lockOrientation: lockOrientation ?? this.lockOrientation,
        seekMultiplier: seekMultiplier ?? this.seekMultiplier,
        doubleTapPlayPause: doubleTapPlayPause ?? this.doubleTapPlayPause,
        longPressSpeedUp: longPressSpeedUp ?? this.longPressSpeedUp,
        subtitleBottomMargin:
            subtitleBottomMargin ?? this.subtitleBottomMargin,
        defaultVolume: defaultVolume ?? this.defaultVolume,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'decodeMode': decodeMode.name,
        'audioChannel': audioChannel.name,
        'aspectRatio': aspectRatio.name,
        'playbackSpeed': playbackSpeed,
        'autoPlayNext': autoPlayNext,
        'subtitleFontSize': subtitleFontSize,
        'subtitleOutline': subtitleOutline,
        'lockOrientation': lockOrientation.name,
        'seekMultiplier': seekMultiplier.name,
        'doubleTapPlayPause': doubleTapPlayPause,
        'longPressSpeedUp': longPressSpeedUp,
        'subtitleBottomMargin': subtitleBottomMargin,
        'defaultVolume': defaultVolume,
      };

  factory PlayerSettings.fromJson(Map<String, dynamic> json) {
    DecodeMode decodeMode = DecodeMode.auto;
    if (json['decodeMode'] is String) {
      decodeMode = DecodeMode.values.firstWhere(
        (e) => e.name == json['decodeMode'],
        orElse: () => DecodeMode.auto,
      );
    }
    AudioChannel audioChannel = AudioChannel.auto;
    if (json['audioChannel'] is String) {
      audioChannel = AudioChannel.values.firstWhere(
        (e) => e.name == json['audioChannel'],
        orElse: () => AudioChannel.auto,
      );
    }
    PlayerAspectRatio aspectRatio = PlayerAspectRatio.defaultRatio;
    if (json['aspectRatio'] is String) {
      aspectRatio = PlayerAspectRatio.values.firstWhere(
        (e) => e.name == json['aspectRatio'],
        orElse: () => PlayerAspectRatio.defaultRatio,
      );
    }
    PlayerLockOrientation lockOrientation = PlayerLockOrientation.auto;
    if (json['lockOrientation'] is String) {
      lockOrientation = PlayerLockOrientation.values.firstWhere(
        (e) => e.name == json['lockOrientation'],
        orElse: () => PlayerLockOrientation.auto,
      );
    }
    SeekMultiplier seekMultiplier = SeekMultiplier.normal;
    if (json['seekMultiplier'] is String) {
      seekMultiplier = SeekMultiplier.values.firstWhere(
        (e) => e.name == json['seekMultiplier'],
        orElse: () => SeekMultiplier.normal,
      );
    }
    return PlayerSettings(
      decodeMode: decodeMode,
      audioChannel: audioChannel,
      aspectRatio: aspectRatio,
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      autoPlayNext: json['autoPlayNext'] as bool? ?? true,
      subtitleFontSize:
          (json['subtitleFontSize'] as num?)?.toDouble() ?? 16.0,
      subtitleOutline: json['subtitleOutline'] as bool? ?? true,
      lockOrientation: lockOrientation,
      seekMultiplier: seekMultiplier,
      doubleTapPlayPause:
          json['doubleTapPlayPause'] as bool? ?? true,
      longPressSpeedUp: json['longPressSpeedUp'] as bool? ?? true,
      subtitleBottomMargin:
          (json['subtitleBottomMargin'] as num?)?.toDouble() ?? 0.0,
      defaultVolume:
          (json['defaultVolume'] as num?)?.toDouble() ?? 100.0,
    );
  }
}

/// 播放器设置持久化存储（key: `player_settings_v1`）。
class PlayerSettingsStore {
  static const String _key = 'player_settings_v1';

  final PrefsBackend _backend;

  PlayerSettingsStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  Future<PlayerSettings> load() async {
    final raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) return const PlayerSettings();
    try {
      return PlayerSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return const PlayerSettings();
    }
  }

  Future<void> save(PlayerSettings settings) async {
    await _backend.set(_key, jsonEncode(settings.toJson()));
  }
}
