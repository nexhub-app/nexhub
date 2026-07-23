/// 漫画阅读器设置子页 —— 漫画阅读默认（全局默认值，打开漫画时兜底生效）。
///
/// 持久化到 SharedPreferences（key: `reader_default_settings_v1`）。
library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/comic/models/reader_preferences.dart';
import '../../../core/settings/reader_default_settings.dart';
import '../../../core/theme/app_tokens.dart';
import 'widgets/settings_widgets.dart';

/// 漫画阅读器默认设置页面。
class SettingsComicReaderScreen extends StatefulWidget {
  const SettingsComicReaderScreen({super.key});

  @override
  State<SettingsComicReaderScreen> createState() =>
      _SettingsComicReaderScreenState();
}

class _SettingsComicReaderScreenState extends State<SettingsComicReaderScreen> {
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

  String _directionLabel(AppLocalizations l10n, ComicReadingDirection dir) {
    return switch (dir) {
      ComicReadingDirection.ltr => l10n.comicDirLtr,
      ComicReadingDirection.rtl => l10n.comicDirRtl,
      ComicReadingDirection.vertical => l10n.comicDirVertical,
      ComicReadingDirection.webtoon => l10n.comicDirWebtoon,
      ComicReadingDirection.webtoonWithGap => l10n.comicDirWebtoonGap,
    };
  }

  String _tapZoneLayoutLabel(AppLocalizations l10n, ComicTapZoneLayout t) {
    return switch (t) {
      ComicTapZoneLayout.layout1 => l10n.comicTapLayout1,
      ComicTapZoneLayout.layout2 => l10n.comicTapLayout2,
      ComicTapZoneLayout.layout3 => l10n.comicTapLayout3,
      ComicTapZoneLayout.layout4 => l10n.comicTapLayout4,
      ComicTapZoneLayout.layout5 => l10n.comicTapLayout5,
    };
  }

  String _initialZoomLabel(AppLocalizations l10n, ComicInitialZoom z) {
    return switch (z) {
      ComicInitialZoom.fitWidth => l10n.comicZoomFitWidth,
      ComicInitialZoom.fitHeight => l10n.comicZoomFitHeight,
      ComicInitialZoom.original => l10n.comicZoomOriginal,
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

  String _onOff(AppLocalizations l10n, bool v) => v ? l10n.on : l10n.off;

  String _flashColorLabel(AppLocalizations l10n, ReaderFlashColor c) {
    return switch (c) {
      ReaderFlashColor.black => l10n.readerFlashBlack,
      ReaderFlashColor.white => l10n.readerFlashWhite,
      ReaderFlashColor.blackWhite => l10n.readerFlashBlackWhite,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.comicReaderSettingsTitle),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: l10n.restoreDefault,
            onPressed: _confirmReset,
          ),
        ],
      ),
      body: _loaded
          ? ListView(
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              children: <Widget>[
                // ── 当前设置概览 ──
                SettingsCard(
                  title: l10n.comicSettingsOverview,
                  children: <Widget>[
                    Wrap(
                      spacing: AppTokens.spaceSm,
                      runSpacing: AppTokens.spaceXs,
                      children: <Widget>[
                        _overviewChip(
                          l10n.comicDefaultReadingDirection,
                          _directionLabel(l10n, _settings.comicReadingDirection),
                        ),
                        _overviewChip(
                          l10n.comicDefaultTapZoneLayout,
                          _tapZoneLayoutLabel(l10n, _settings.comicTapZoneLayout),
                        ),
                        _overviewChip(
                          l10n.comicDefaultInitialZoom,
                          _initialZoomLabel(l10n, _settings.comicInitialZoom),
                        ),
                        _overviewChip(
                          l10n.comicDefaultFullscreen,
                          _onOff(l10n, _settings.comicFullscreen),
                        ),
                        _overviewChip(
                          l10n.comicDefaultGrayscale,
                          _onOff(l10n, _settings.comicGrayscale),
                        ),
                        _overviewChip(
                          l10n.readerShowPageNumber,
                          _onOff(l10n, _settings.comicShowPageNumber),
                        ),
                        _overviewChip(
                          l10n.readerKeepScreenOn,
                          _onOff(l10n, _settings.comicKeepScreenOn),
                        ),
                      ],
                    ),
                  ],
                ),

                // ── 通用阅读偏好 ──
                SettingsCard(
                  title: l10n.readerGeneralGroup,
                  children: <Widget>[
                    _labeled(
                      l10n.comicDefaultReadingDirection,
                      DropdownButton<ComicReadingDirection>(
                        value: _settings.comicReadingDirection,
                        isExpanded: true,
                        items: ComicReadingDirection.values.map((dir) {
                          return DropdownMenuItem<ComicReadingDirection>(
                            value: dir,
                            child: Text(_directionLabel(l10n, dir)),
                          );
                        }).toList(),
                        onChanged: (dir) {
                          if (dir != null) {
                            _update(_settings.copyWith(comicReadingDirection: dir));
                          }
                        },
                      ),
                    ),
                    _labeled(
                      l10n.comicDefaultTapZoneLayout,
                      DropdownButton<ComicTapZoneLayout>(
                        value: _settings.comicTapZoneLayout,
                        isExpanded: true,
                        items: ComicTapZoneLayout.values.map((t) {
                          return DropdownMenuItem<ComicTapZoneLayout>(
                            value: t,
                            child: Text(_tapZoneLayoutLabel(l10n, t)),
                          );
                        }).toList(),
                        onChanged: (t) {
                          if (t != null) {
                            _update(_settings.copyWith(comicTapZoneLayout: t));
                          }
                        },
                      ),
                    ),
                    SettingsChoiceChips<TapZoneInvert>(
                      title: l10n.comicTapZoneInvert,
                      selected: _settings.comicTapZoneInvert,
                      onSelected: (v) =>
                          _update(_settings.copyWith(comicTapZoneInvert: v)),
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
                      title: l10n.comicDefaultFullscreen,
                      value: _settings.comicFullscreen,
                      onChanged: (v) =>
                          _update(_settings.copyWith(comicFullscreen: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.comicDefaultLongPressMenu,
                      value: _settings.comicShowLongPressMenu,
                      onChanged: (v) => _update(
                          _settings.copyWith(comicShowLongPressMenu: v)),
                    ),
                  ],
                ),

                // ── 页面与进度 ──
                SettingsCard(
                  title: l10n.comicPageProgressGroup,
                  children: <Widget>[
                    SettingsSwitchTile(
                      title: l10n.readerCropEdge,
                      value: _settings.comicCropEdge,
                      onChanged: (v) =>
                          _update(_settings.copyWith(comicCropEdge: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.readerShowPageNumber,
                      value: _settings.comicShowPageNumber,
                      onChanged: (v) =>
                          _update(_settings.copyWith(comicShowPageNumber: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.readerProgressBarOnRight,
                      value: _settings.comicProgressBarOnRight,
                      onChanged: (v) => _update(
                          _settings.copyWith(comicProgressBarOnRight: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.readerKeepScreenOn,
                      value: _settings.comicKeepScreenOn,
                      onChanged: (v) =>
                          _update(_settings.copyWith(comicKeepScreenOn: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.readerRotatePage,
                      value: _settings.comicRotateLandscape,
                      onChanged: (v) =>
                          _update(_settings.copyWith(comicRotateLandscape: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.readerSplitDoublePage,
                      value: _settings.comicSplitDoublePage,
                      onChanged: (v) => _update(
                          _settings.copyWith(comicSplitDoublePage: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.readerSideMargin,
                      value: _settings.comicSideMargin,
                      min: 0.0,
                      max: 0.5,
                      divisions: 50,
                      display:
                          '${(_settings.comicSideMargin * 100).round()}%',
                      onChanged: (v) =>
                          _update(_settings.copyWith(comicSideMargin: v)),
                    ),
                  ],
                ),

                // ── 画面与缩放 ──
                SettingsCard(
                  title: l10n.comicVisualZoomGroup,
                  children: <Widget>[
                    SettingsSliderTile(
                      label: l10n.comicFilterBrightness,
                      value: _settings.comicFilterBrightness,
                      min: -1.0,
                      max: 1.0,
                      divisions: 20,
                      display:
                          '${(_settings.comicFilterBrightness * 100).round()}%',
                      onChanged: (v) => _update(
                          _settings.copyWith(comicFilterBrightness: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.comicFilterContrast,
                      value: _settings.comicFilterContrast,
                      min: -1.0,
                      max: 1.0,
                      divisions: 20,
                      display:
                          '${(_settings.comicFilterContrast * 100).round()}%',
                      onChanged: (v) => _update(
                          _settings.copyWith(comicFilterContrast: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.comicFilterColorTemp,
                      value: _settings.comicFilterColorTemp,
                      min: -1.0,
                      max: 1.0,
                      divisions: 20,
                      display:
                          '${(_settings.comicFilterColorTemp * 100).round()}%',
                      onChanged: (v) => _update(
                          _settings.copyWith(comicFilterColorTemp: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.comicFilterInverted,
                      value: _settings.comicFilterInverted,
                      onChanged: (v) =>
                          _update(_settings.copyWith(comicFilterInverted: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.saturation,
                      value: _settings.comicFilterSaturation,
                      min: -1.0,
                      max: 1.0,
                      divisions: 20,
                      display:
                          '${(_settings.comicFilterSaturation * 100).round()}%',
                      onChanged: (v) => _update(
                          _settings.copyWith(comicFilterSaturation: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.hue,
                      value: _settings.comicFilterHue,
                      min: -1.0,
                      max: 1.0,
                      divisions: 20,
                      display:
                          '${(_settings.comicFilterHue * 100).round()}%',
                      onChanged: (v) =>
                          _update(_settings.copyWith(comicFilterHue: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.comicDefaultGrayscale,
                      value: _settings.comicGrayscale,
                      onChanged: (v) =>
                          _update(_settings.copyWith(comicGrayscale: v)),
                    ),
                    SettingsSegmentedTile<ComicInitialZoom>(
                      title: l10n.comicDefaultInitialZoom,
                      selected: <ComicInitialZoom>{_settings.comicInitialZoom},
                      onSelectionChanged: (s) => _update(
                          _settings.copyWith(comicInitialZoom: s.first)),
                      segments: <ButtonSegment<ComicInitialZoom>>[
                        ButtonSegment<ComicInitialZoom>(
                            value: ComicInitialZoom.fitWidth,
                            label: Text(l10n.comicZoomFitWidth)),
                        ButtonSegment<ComicInitialZoom>(
                            value: ComicInitialZoom.fitHeight,
                            label: Text(l10n.comicZoomFitHeight)),
                        ButtonSegment<ComicInitialZoom>(
                            value: ComicInitialZoom.original,
                            label: Text(l10n.comicZoomOriginal)),
                      ],
                    ),
                    SettingsSegmentedTile<ComicDoubleTapZoom>(
                      title: l10n.comicDefaultDoubleTapZoom,
                      selected: <ComicDoubleTapZoom>{
                        _settings.comicDoubleTapZoom
                      },
                      onSelectionChanged: (s) => _update(
                          _settings.copyWith(comicDoubleTapZoom: s.first)),
                      segments: <ButtonSegment<ComicDoubleTapZoom>>[
                        ButtonSegment<ComicDoubleTapZoom>(
                            value: ComicDoubleTapZoom.x2,
                            label: Text(l10n.comicZoom2x)),
                        ButtonSegment<ComicDoubleTapZoom>(
                            value: ComicDoubleTapZoom.x3,
                            label: Text(l10n.comicZoom3x)),
                      ],
                    ),
                    SettingsSegmentedTile<ComicScrollWheel>(
                      title: l10n.comicDefaultScrollWheel,
                      selected: <ComicScrollWheel>{_settings.comicScrollWheel},
                      onSelectionChanged: (s) => _update(
                          _settings.copyWith(comicScrollWheel: s.first)),
                      segments: <ButtonSegment<ComicScrollWheel>>[
                        ButtonSegment<ComicScrollWheel>(
                            value: ComicScrollWheel.natural,
                            label: Text(l10n.comicWheelNatural)),
                        ButtonSegment<ComicScrollWheel>(
                            value: ComicScrollWheel.inverted,
                            label: Text(l10n.comicWheelInverted)),
                      ],
                    ),
                    SettingsSwitchTile(
                      title: l10n.comicDefaultPreventShrink,
                      value: _settings.comicPreventShrink,
                      onChanged: (v) =>
                          _update(_settings.copyWith(comicPreventShrink: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.comicDefaultChapterTransition,
                      value: _settings.comicChapterTransition,
                      onChanged: (v) => _update(
                          _settings.copyWith(comicChapterTransition: v)),
                    ),
                  ],
                ),

                // ── 闪光效果 ──
                SettingsCard(
                  title: l10n.readerGroupFlash,
                  children: <Widget>[
                    SettingsSwitchTile(
                      title: l10n.readerFlashEnabled,
                      value: _settings.comicFlashEnabled,
                      onChanged: (v) =>
                          _update(_settings.copyWith(comicFlashEnabled: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.readerFlashTime,
                      value: _settings.comicFlashTime.toDouble(),
                      min: 50,
                      max: 600,
                      divisions: 55,
                      display: '${_settings.comicFlashTime} ms',
                      onChanged: (v) => _update(
                          _settings.copyWith(comicFlashTime: v.round())),
                    ),
                    SettingsSliderTile(
                      label: l10n.readerFlashInterval,
                      value: _settings.comicFlashInterval.toDouble(),
                      min: 0,
                      max: 600,
                      divisions: 60,
                      display: '${_settings.comicFlashInterval} ms',
                      onChanged: (v) => _update(
                          _settings.copyWith(comicFlashInterval: v.round())),
                    ),
                    SettingsChoiceChips<ReaderFlashColor>(
                      title: l10n.readerFlashColor,
                      selected: _settings.comicFlashColor,
                      onSelected: (c) =>
                          _update(_settings.copyWith(comicFlashColor: c)),
                      options: ReaderFlashColor.values
                          .map((c) => SettingsChoiceChipData<ReaderFlashColor>(
                                value: c,
                                label: _flashColorLabel(l10n, c),
                              ))
                          .toList(),
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
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          child,
        ],
      ),
    );
  }

  Widget _overviewChip(String label, String value) {
    final theme = Theme.of(context);
    return Chip(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      label: Text.rich(
        TextSpan(
          children: <TextSpan>[
            TextSpan(
              text: '$label：',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmReset() {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.restoreDefault),
        content: Text(l10n.comicResetConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _update(const ReaderDefaultSettings());
            },
            child: Text(l10n.restoreDefault),
          ),
        ],
      ),
    );
  }
}
