/// 播放器设置子页 —— 默认解码/音频/比例/速度/字幕等全局默认值。
///
/// 持久化到 SharedPreferences（key: `player_settings_v1`）。
library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/settings/player_settings.dart';
import '../../../core/theme/app_tokens.dart';
import 'widgets/settings_widgets.dart';

/// 播放器设置页面。
class SettingsPlayerScreen extends StatefulWidget {
  const SettingsPlayerScreen({super.key});

  @override
  State<SettingsPlayerScreen> createState() => _SettingsPlayerScreenState();
}

class _SettingsPlayerScreenState extends State<SettingsPlayerScreen> {
  final PlayerSettingsStore _store = PlayerSettingsStore();
  late PlayerSettings _settings;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _settings = const PlayerSettings();
    _store.load().then((s) {
      if (mounted) {
        setState(() {
          _settings = s;
          _loaded = true;
        });
      }
    });
  }

  void _update(PlayerSettings next) {
    setState(() => _settings = next);
    _store.save(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.playerSettingsTitle)),
      body: _loaded
          ? ListView(
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              children: <Widget>[
                // ── 播放核心 ──
                SettingsCard(
                  title: l10n.playerCoreGroup,
                  children: <Widget>[
                    SettingsSegmentedTile<DecodeMode>(
                      title: l10n.playerDefaultDecodeMode,
                      selected: <DecodeMode>{_settings.decodeMode},
                      onSelectionChanged: (s) =>
                          _update(_settings.copyWith(decodeMode: s.first)),
                      segments: <ButtonSegment<DecodeMode>>[
                        ButtonSegment<DecodeMode>(
                            value: DecodeMode.auto,
                            label: Text(l10n.playerDecodeAuto)),
                        ButtonSegment<DecodeMode>(
                            value: DecodeMode.sw,
                            label: Text(l10n.playerDecodeSw)),
                        ButtonSegment<DecodeMode>(
                            value: DecodeMode.hw,
                            label: Text(l10n.playerDecodeHw)),
                        ButtonSegment<DecodeMode>(
                            value: DecodeMode.hwPlus,
                            label: Text(l10n.playerDecodeHwPlus)),
                      ],
                    ),
                    SettingsSegmentedTile<AudioChannel>(
                      title: l10n.playerDefaultAudioChannel,
                      selected: <AudioChannel>{_settings.audioChannel},
                      onSelectionChanged: (s) =>
                          _update(_settings.copyWith(audioChannel: s.first)),
                      segments: <ButtonSegment<AudioChannel>>[
                        ButtonSegment<AudioChannel>(
                            value: AudioChannel.auto,
                            label: Text(l10n.playerDecodeAuto)),
                        ButtonSegment<AudioChannel>(
                            value: AudioChannel.stereo,
                            label: Text(l10n.playerAudioStereo)),
                        ButtonSegment<AudioChannel>(
                            value: AudioChannel.mono,
                            label: Text(l10n.playerAudioMono)),
                      ],
                    ),
                    SettingsSegmentedTile<PlayerAspectRatio>(
                      title: l10n.playerDefaultAspectRatio,
                      selected: <PlayerAspectRatio>{_settings.aspectRatio},
                      onSelectionChanged: (s) =>
                          _update(_settings.copyWith(aspectRatio: s.first)),
                      segments: <ButtonSegment<PlayerAspectRatio>>[
                        ButtonSegment<PlayerAspectRatio>(
                            value: PlayerAspectRatio.defaultRatio,
                            label: Text(l10n.playerAspectDefault)),
                        ButtonSegment<PlayerAspectRatio>(
                            value: PlayerAspectRatio.ratio43,
                            label: Text(l10n.playerAspect43)),
                        ButtonSegment<PlayerAspectRatio>(
                            value: PlayerAspectRatio.ratio169,
                            label: Text(l10n.playerAspect169)),
                        ButtonSegment<PlayerAspectRatio>(
                            value: PlayerAspectRatio.fill,
                            label: Text(l10n.playerAspectFill)),
                      ],
                    ),
                    SettingsSliderTile(
                      label: l10n.playerDefaultSpeed,
                      value: _settings.playbackSpeed,
                      min: 0.5,
                      max: 2.0,
                      divisions: 15,
                      display: '${_settings.playbackSpeed.toStringAsFixed(1)}x',
                      onChanged: (v) =>
                          _update(_settings.copyWith(playbackSpeed: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.playerDefaultAutoPlay,
                      value: _settings.autoPlayNext,
                      onChanged: (v) =>
                          _update(_settings.copyWith(autoPlayNext: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.playerDefaultVolume,
                      value: _settings.defaultVolume,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      display: _settings.defaultVolume.toStringAsFixed(0),
                      onChanged: (v) =>
                          _update(_settings.copyWith(defaultVolume: v)),
                    ),
                  ],
                ),

                // ── 字幕 ──
                SettingsCard(
                  title: l10n.playerSubtitleGroup,
                  children: <Widget>[
                    SettingsSliderTile(
                      label: l10n.playerSubtitleFontSize,
                      value: _settings.subtitleFontSize,
                      min: 12,
                      max: 32,
                      divisions: 20,
                      display: _settings.subtitleFontSize.toStringAsFixed(0),
                      onChanged: (v) => _update(
                          _settings.copyWith(subtitleFontSize: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.playerSubtitleOutline,
                      value: _settings.subtitleOutline,
                      onChanged: (v) =>
                          _update(_settings.copyWith(subtitleOutline: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.playerSubtitleBottomMargin,
                      value: _settings.subtitleBottomMargin,
                      min: 0,
                      max: 120,
                      divisions: 12,
                      display: _settings.subtitleBottomMargin
                          .toStringAsFixed(0),
                      onChanged: (v) => _update(
                          _settings.copyWith(subtitleBottomMargin: v)),
                    ),
                  ],
                ),

                // ── 手势与控制 ──
                SettingsCard(
                  title: l10n.playerGestureGroup,
                  children: <Widget>[
                    SettingsSegmentedTile<PlayerLockOrientation>(
                      title: l10n.playerDefaultOrientation,
                      selected: <PlayerLockOrientation>{
                        _settings.lockOrientation
                      },
                      onSelectionChanged: (s) => _update(
                          _settings.copyWith(lockOrientation: s.first)),
                      segments: <ButtonSegment<PlayerLockOrientation>>[
                        ButtonSegment<PlayerLockOrientation>(
                            value: PlayerLockOrientation.auto,
                            label: Text(l10n.playerOrientationAuto)),
                        ButtonSegment<PlayerLockOrientation>(
                            value: PlayerLockOrientation.portrait,
                            label: Text(l10n.playerOrientationPortrait)),
                        ButtonSegment<PlayerLockOrientation>(
                            value: PlayerLockOrientation.landscape,
                            label: Text(l10n.playerOrientationLandscape)),
                      ],
                    ),
                    SettingsSegmentedTile<SeekMultiplier>(
                      title: l10n.playerGestureSeekMultiplier,
                      selected: <SeekMultiplier>{_settings.seekMultiplier},
                      onSelectionChanged: (s) =>
                          _update(_settings.copyWith(seekMultiplier: s.first)),
                      segments: <ButtonSegment<SeekMultiplier>>[
                        ButtonSegment<SeekMultiplier>(
                            value: SeekMultiplier.half,
                            label: Text(l10n.playerSeekHalf)),
                        ButtonSegment<SeekMultiplier>(
                            value: SeekMultiplier.normal,
                            label: Text(l10n.playerSeekNormal)),
                        ButtonSegment<SeekMultiplier>(
                            value: SeekMultiplier.double,
                            label: Text(l10n.playerSeekDouble)),
                      ],
                    ),
                    SettingsSwitchTile(
                      title: l10n.playerDoubleTapPlayPause,
                      value: _settings.doubleTapPlayPause,
                      onChanged: (v) =>
                          _update(_settings.copyWith(doubleTapPlayPause: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.playerLongPressSpeedUp,
                      value: _settings.longPressSpeedUp,
                      onChanged: (v) =>
                          _update(_settings.copyWith(longPressSpeedUp: v)),
                    ),
                  ],
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
