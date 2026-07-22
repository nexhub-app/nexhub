/// 小说阅读器设置子页 —— 小说阅读默认（全局默认值，打开小说时兜底生效）。
///
/// 持久化到 SharedPreferences（key: `reader_default_settings_v1`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/comic/models/reader_preferences.dart';
import '../../../core/novel/novel_page_animation.dart';
import '../../../core/settings/reader_default_settings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/reader_tokens.dart';
import 'widgets/settings_widgets.dart';

/// 小说阅读器默认设置页面。
class SettingsNovelReaderScreen extends StatefulWidget {
  const SettingsNovelReaderScreen({super.key});

  @override
  State<SettingsNovelReaderScreen> createState() =>
      _SettingsNovelReaderScreenState();
}

class _SettingsNovelReaderScreenState extends State<SettingsNovelReaderScreen> {
  final ReaderDefaultSettingsStore _store = ReaderDefaultSettingsStore();
  late ReaderDefaultSettings _settings;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _settings = const ReaderDefaultSettings();
    _store.load().then((s) {
      if (mounted) {
        setState(() {
          _settings = s;
          _loaded = true;
        });
      }
    });
  }

  void _update(ReaderDefaultSettings next) {
    setState(() => _settings = next);
    _store.save(next);
  }

  String _readingModeLabel(AppLocalizations l10n, ReadingMode mode) {
    return switch (mode) {
      ReadingMode.singleLTR => l10n.readerModeSingleLTR,
      ReadingMode.singleRTL => l10n.readerModeSingleRTL,
      ReadingMode.singleVertical => l10n.readerModeSingleVertical,
      ReadingMode.webtoon => l10n.readerModeWebtoon,
      ReadingMode.webtoonWithGap => l10n.readerModeWebtoonWithGap,
    };
  }

  String _pageAnimLabel(AppLocalizations l10n, NovelPageAnimation anim) {
    return switch (anim) {
      NovelPageAnimation.none => l10n.novelAnimNone,
      NovelPageAnimation.slide => l10n.novelAnimSlide,
      NovelPageAnimation.scroll => l10n.novelAnimScroll,
      NovelPageAnimation.fade => l10n.novelAnimFade,
      NovelPageAnimation.cover => l10n.novelAnimCover,
      NovelPageAnimation.simulation => l10n.novelAnimSimulation,
    };
  }

  String _chineseConversionLabel(
      AppLocalizations l10n, NovelChineseConversion conv) {
    return switch (conv) {
      NovelChineseConversion.none => l10n.noConvert,
      NovelChineseConversion.traditionalToSimplified =>
        l10n.traditionalToSimplified,
      NovelChineseConversion.simplifiedToTraditional =>
        l10n.simplifiedToTraditional,
    };
  }

  String _tapZoneInvertLabel(AppLocalizations l10n, TapZoneInvert inv) {
    return switch (inv) {
      TapZoneInvert.none => l10n.readerTapInvertNone,
      TapZoneInvert.leftRight => l10n.readerTapInvertLeftRight,
      TapZoneInvert.upDown => l10n.readerTapInvertUpDown,
      TapZoneInvert.all => l10n.readerTapInvertAll,
    };
  }

  String _bgPresetLabel(AppLocalizations l10n, String key) {
    return switch (key) {
      'readerBgBlack' => l10n.readerBgBlack,
      'readerBgDarkGray' => l10n.readerBgDarkGray,
      'readerBgWhite' => l10n.readerBgWhite,
      'readerBgEyeCare' => l10n.readerBgEyeCare,
      'readerBgParchment' => l10n.readerBgParchment,
      'readerBgWarmLinen' => l10n.readerBgWarmLinen,
      'readerBgLightBrown' => l10n.readerBgLightBrown,
      'readerBgBeanGreen' => l10n.readerBgBeanGreen,
      'readerBgMint' => l10n.readerBgMint,
      'readerBgApricot' => l10n.readerBgApricot,
      'readerBgGrayBlue' => l10n.readerBgGrayBlue,
      _ => key,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.novelReaderSettingsTitle)),
      body: _loaded
          ? ListView(
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              children: <Widget>[
                // ── 通用阅读偏好 ──
                SettingsCard(
                  title: l10n.readerGeneralGroup,
                  children: <Widget>[
                    _labeled(
                      l10n.readerDefaultMode,
                      DropdownButton<ReadingMode>(
                        value: _settings.readingMode,
                        isExpanded: true,
                        items: ReadingMode.values.map((mode) {
                          return DropdownMenuItem<ReadingMode>(
                            value: mode,
                            child: Text(_readingModeLabel(l10n, mode)),
                          );
                        }).toList(),
                        onChanged: (mode) {
                          if (mode != null) {
                            _update(_settings.copyWith(readingMode: mode));
                          }
                        },
                      ),
                    ),
                    SettingsChoiceChips<int>(
                      title: l10n.novelBackgroundPreset,
                      selected: _settings.novelBgPresetIndex,
                      onSelected: (i) =>
                          _update(_settings.copyWith(novelBgPresetIndex: i)),
                      options: ReaderTokens.bgPresetL10nKeys
                          .asMap()
                          .entries
                          .map((e) => SettingsChoiceChipData<int>(
                                value: e.key,
                                label: _bgPresetLabel(l10n, e.value),
                              ))
                          .toList(),
                    ),
                    SettingsSegmentedTile<ReaderOrientation>(
                      title: l10n.readerDefaultOrientation,
                      selected: <ReaderOrientation>{_settings.orientation},
                      onSelectionChanged: (s) =>
                          _update(_settings.copyWith(orientation: s.first)),
                      segments: <ButtonSegment<ReaderOrientation>>[
                        ButtonSegment<ReaderOrientation>(
                            value: ReaderOrientation.horizontal,
                            label: Text(l10n.readerOrientationHorizontal)),
                        ButtonSegment<ReaderOrientation>(
                            value: ReaderOrientation.vertical,
                            label: Text(l10n.readerOrientationVertical)),
                      ],
                    ),
                    SettingsChoiceChips<TapZoneInvert>(
                      title: l10n.novelTapZoneInvert,
                      selected: _settings.novelTapZoneInvert,
                      onSelected: (v) =>
                          _update(_settings.copyWith(novelTapZoneInvert: v)),
                      options: TapZoneInvert.values
                          .map((v) => SettingsChoiceChipData<TapZoneInvert>(
                                value: v,
                                label: _tapZoneInvertLabel(l10n, v),
                              ))
                          .toList(),
                    ),
                    SettingsSwitchTile(
                      title: l10n.readerDoubleTapZoom,
                      value: _settings.doubleTapZoom,
                      onChanged: (v) =>
                          _update(_settings.copyWith(doubleTapZoom: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.readerOrientationLock,
                      value: _settings.orientationLock,
                      onChanged: (v) =>
                          _update(_settings.copyWith(orientationLock: v)),
                    ),
                  ],
                ),

                // ── 小说排版 ──
                SettingsCard(
                  title: l10n.novelTypographyGroup,
                  children: <Widget>[
                    _labeled(
                      l10n.novelDefaultPageTurnAnimation,
                      DropdownButton<NovelPageAnimation>(
                        value: _settings.novelPageAnimation,
                        isExpanded: true,
                        items: NovelPageAnimation.values.map((anim) {
                          return DropdownMenuItem<NovelPageAnimation>(
                            value: anim,
                            child: Text(_pageAnimLabel(l10n, anim)),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            _update(_settings.copyWith(novelPageAnimation: v));
                          }
                        },
                      ),
                    ),
                    SettingsSliderTile(
                      label: l10n.novelDefaultFontSize,
                      value: _settings.novelFontSize,
                      min: 12,
                      max: 32,
                      divisions: 20,
                      display: _settings.novelFontSize.toStringAsFixed(0),
                      onChanged: (v) =>
                          _update(_settings.copyWith(novelFontSize: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.novelDefaultLineHeight,
                      value: _settings.novelLineHeight,
                      min: 1.0,
                      max: 3.0,
                      divisions: 20,
                      display: _settings.novelLineHeight.toStringAsFixed(1),
                      onChanged: (v) =>
                          _update(_settings.copyWith(novelLineHeight: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.novelParagraphSpacing,
                      value: _settings.novelParagraphSpacing,
                      min: 4,
                      max: 48,
                      divisions: 22,
                      display:
                          _settings.novelParagraphSpacing.toStringAsFixed(0),
                      onChanged: (v) => _update(
                          _settings.copyWith(novelParagraphSpacing: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.novelMargin,
                      value: _settings.novelMargin,
                      min: 8,
                      max: 64,
                      divisions: 28,
                      display: _settings.novelMargin.toStringAsFixed(0),
                      onChanged: (v) =>
                          _update(_settings.copyWith(novelMargin: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.novelShadow,
                      value: _settings.novelShadow,
                      onChanged: (v) =>
                          _update(_settings.copyWith(novelShadow: v)),
                    ),
                    SettingsChoiceChips<NovelChineseConversion>(
                      title: l10n.novelDefaultChineseConversion,
                      selected: _settings.novelChineseConversion,
                      onSelected: (conv) => _update(
                          _settings.copyWith(novelChineseConversion: conv)),
                      options: NovelChineseConversion.values
                          .map((conv) =>
                              SettingsChoiceChipData<NovelChineseConversion>(
                                value: conv,
                                label:
                                    _chineseConversionLabel(l10n, conv),
                              ))
                          .toList(),
                    ),
                    SettingsSliderTile(
                      label: l10n.novelDefaultTtsRate,
                      value: _settings.novelTtsSpeechRate,
                      min: 0.5,
                      max: 2.0,
                      divisions: 15,
                      display:
                          '${_settings.novelTtsSpeechRate.toStringAsFixed(1)}x',
                      onChanged: (v) => _update(
                          _settings.copyWith(novelTtsSpeechRate: v)),
                    ),
                  ],
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _labeled(String label, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: AppTokens.spaceXs),
          child,
        ],
      ),
    );
  }
}
