/// 弹幕显示设置子页 —— 全局弹幕显示参数（独立于播放器内临时面板）。
///
/// 持久化到 SharedPreferences（key: `danmaku_display_settings_v1`），
/// 复用 [DanmakuSettings] 模型，作为播放器外全局默认值。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/comic/models/reader_preferences.dart';
import '../../../core/danmaku/danmaku_settings.dart';
import '../../../core/theme/app_tokens.dart';
import 'widgets/settings_widgets.dart';

/// 弹幕显示设置持久化存储（key: `danmaku_display_settings_v1`）。
///
/// 仿 [DanmakuConfigStore] 模式，复用 [PrefsBackend] 抽象以便测试注入。
class DanmakuDisplaySettingsStore {
  static const String _key = 'danmaku_display_settings_v1';

  final PrefsBackend _backend;

  DanmakuDisplaySettingsStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  Future<DanmakuSettings> load() async {
    final raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) return const DanmakuSettings();
    try {
      return DanmakuSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return const DanmakuSettings();
    }
  }

  Future<void> save(DanmakuSettings settings) async {
    await _backend.set(_key, jsonEncode(settings.toJson()));
  }
}

/// 弹幕显示设置页面（Scaffold 全页）。
class SettingsDanmakuDisplayScreen extends StatefulWidget {
  const SettingsDanmakuDisplayScreen({super.key});

  @override
  State<SettingsDanmakuDisplayScreen> createState() =>
      _SettingsDanmakuDisplayScreenState();
}

class _SettingsDanmakuDisplayScreenState
    extends State<SettingsDanmakuDisplayScreen> {
  final TextEditingController _keywordController = TextEditingController();
  final TextEditingController _blockedKeywordsController =
      TextEditingController();
  final DanmakuDisplaySettingsStore _store = DanmakuDisplaySettingsStore();
  late DanmakuSettings _settings;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _settings = const DanmakuSettings();
    _store.load().then((s) {
      if (mounted) {
        setState(() {
          _settings = s;
          _loaded = true;
          _blockedKeywordsController.text = s.blockedKeywords;
        });
      }
    });
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _blockedKeywordsController.dispose();
    super.dispose();
  }

  void _update(DanmakuSettings next) {
    setState(() => _settings = next);
    _store.save(next);
  }

  void _addKeyword() {
    final text = _keywordController.text.trim();
    if (text.isEmpty) return;
    if (_settings.filterKeywords.contains(text)) {
      _keywordController.clear();
      return;
    }
    _update(_settings.copyWith(
      filterKeywords: <String>[..._settings.filterKeywords, text],
    ));
    _keywordController.clear();
  }

  void _removeKeyword(String keyword) {
    _update(_settings.copyWith(
      filterKeywords:
          _settings.filterKeywords.where((k) => k != keyword).toList(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.danmakuDisplaySettingsTitle)),
      body: _loaded
          ? ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceLg,
                vertical: AppTokens.spaceSm,
              ),
              children: <Widget>[
                // ── 过滤与屏蔽 ──
                SettingsCard(
                  title: l10n.danmakuDisplayGroupFilter,
                  children: <Widget>[
                    _keywordSection(l10n),
                    SettingsSliderTile(
                      label: l10n.danmakuTimeOffset,
                      value: _settings.timeOffset,
                      min: -10,
                      max: 10,
                      divisions: 20,
                      display: _settings.timeOffset.toStringAsFixed(1),
                      onChanged: (v) =>
                          _update(_settings.copyWith(timeOffset: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.danmakuHideTop,
                      value: _settings.hideTop,
                      onChanged: (v) =>
                          _update(_settings.copyWith(hideTop: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.danmakuHideBottom,
                      value: _settings.hideBottom,
                      onChanged: (v) =>
                          _update(_settings.copyWith(hideBottom: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.danmakuHideScroll,
                      value: _settings.hideScroll,
                      onChanged: (v) =>
                          _update(_settings.copyWith(hideScroll: v)),
                    ),
                    _labeled(l10n.danmakuDisplayBlockedKeywords,
                        TextField(
                      controller: _blockedKeywordsController,
                      decoration: InputDecoration(
                        hintText: l10n.danmakuDisplayBlockedKeywordsHint,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 4,
                      onChanged: (v) =>
                          _update(_settings.copyWith(blockedKeywords: v)),
                    )),
                  ],
                ),

                // ── 外观 ──
                SettingsCard(
                  title: l10n.danmakuDisplayGroupAppearance,
                  children: <Widget>[
                    SettingsSliderTile(
                      label: l10n.danmakuFontSize,
                      value: _settings.fontSize,
                      min: 12,
                      max: 28,
                      divisions: 16,
                      display: _settings.fontSize.toStringAsFixed(0),
                      onChanged: (v) =>
                          _update(_settings.copyWith(fontSize: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.danmakuOpacity,
                      value: _settings.opacity,
                      min: 0.1,
                      max: 1.0,
                      divisions: 9,
                      display: '${(_settings.opacity * 100).round()}%',
                      onChanged: (v) =>
                          _update(_settings.copyWith(opacity: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.danmakuArea,
                      value: _settings.area,
                      min: 0.1,
                      max: 1.0,
                      divisions: 9,
                      display: _settings.area.toStringAsFixed(1),
                      onChanged: (v) => _update(_settings.copyWith(area: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.danmakuDuration,
                      value: _settings.duration,
                      min: 4,
                      max: 20,
                      divisions: 16,
                      display: _settings.duration.toStringAsFixed(0),
                      onChanged: (v) => _update(_settings.copyWith(duration: v)),
                    ),
                    SettingsSliderTile(
                      label: l10n.danmakuLineHeight,
                      value: _settings.lineHeight,
                      min: 1.0,
                      max: 3.0,
                      divisions: 20,
                      display: _settings.lineHeight.toStringAsFixed(1),
                      onChanged: (v) => _update(_settings.copyWith(lineHeight: v)),
                    ),
                  ],
                ),

                // ── 显示范围 ──
                SettingsCard(
                  title: l10n.danmakuDisplayGroupDisplayRange,
                  children: <Widget>[
                    SettingsSwitchTile(
                      title: l10n.danmakuDisplayShowTop,
                      value: _settings.showOnTop,
                      onChanged: (v) =>
                          _update(_settings.copyWith(showOnTop: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.danmakuDisplayShowBottom,
                      value: _settings.showOnBottom,
                      onChanged: (v) =>
                          _update(_settings.copyWith(showOnBottom: v)),
                    ),
                    SettingsSwitchTile(
                      title: l10n.danmakuDisplayShowFull,
                      value: _settings.showFull,
                      onChanged: (v) =>
                          _update(_settings.copyWith(showFull: v)),
                    ),
                  ],
                ),

                // ── 速度 ──
                SettingsCard(
                  title: l10n.danmakuDisplayGroupSpeed,
                  children: <Widget>[
                    SettingsSegmentedTile<DanmakuFontSize>(
                      title: l10n.danmakuDisplayFontSize,
                      selected: <DanmakuFontSize>{
                        _settings.fontSizePreset
                      },
                      onSelectionChanged: (Set<DanmakuFontSize> s) => _update(
                          _settings.copyWith(fontSizePreset: s.first)),
                      segments: <ButtonSegment<DanmakuFontSize>>[
                        ButtonSegment<DanmakuFontSize>(
                            value: DanmakuFontSize.small,
                            label: Text(l10n.danmakuSizeSmall)),
                        ButtonSegment<DanmakuFontSize>(
                            value: DanmakuFontSize.medium,
                            label: Text(l10n.danmakuSizeMedium)),
                        ButtonSegment<DanmakuFontSize>(
                            value: DanmakuFontSize.large,
                            label: Text(l10n.danmakuSizeLarge)),
                      ],
                    ),
                    SettingsSegmentedTile<DanmakuScrollSpeed>(
                      title: l10n.danmakuDisplayScrollSpeed,
                      selected: <DanmakuScrollSpeed>{_settings.scrollSpeed},
                      onSelectionChanged: (Set<DanmakuScrollSpeed> s) =>
                          _update(_settings.copyWith(scrollSpeed: s.first)),
                      segments: <ButtonSegment<DanmakuScrollSpeed>>[
                        ButtonSegment<DanmakuScrollSpeed>(
                            value: DanmakuScrollSpeed.slow,
                            label: Text(l10n.danmakuSpeedSlow)),
                        ButtonSegment<DanmakuScrollSpeed>(
                            value: DanmakuScrollSpeed.medium,
                            label: Text(l10n.danmakuSpeedMedium)),
                        ButtonSegment<DanmakuScrollSpeed>(
                            value: DanmakuScrollSpeed.fast,
                            label: Text(l10n.danmakuSpeedFast)),
                      ],
                    ),
                    SettingsSegmentedTile<DanmakuDisplayArea>(
                      title: l10n.danmakuDisplayArea,
                      selected: <DanmakuDisplayArea>{_settings.displayArea},
                      onSelectionChanged: (Set<DanmakuDisplayArea> s) =>
                          _update(_settings.copyWith(displayArea: s.first)),
                      segments: <ButtonSegment<DanmakuDisplayArea>>[
                        ButtonSegment<DanmakuDisplayArea>(
                            value: DanmakuDisplayArea.quarter,
                            label: Text(l10n.danmakuAreaQuarter)),
                        ButtonSegment<DanmakuDisplayArea>(
                            value: DanmakuDisplayArea.half,
                            label: Text(l10n.danmakuAreaHalf)),
                        ButtonSegment<DanmakuDisplayArea>(
                            value: DanmakuDisplayArea.full,
                            label: Text(l10n.danmakuAreaFull)),
                      ],
                    ),
                    SettingsSegmentedTile<DanmakuMaxOnScreen>(
                      title: l10n.danmakuDisplayMaxOnScreen,
                      selected: <DanmakuMaxOnScreen>{_settings.maxOnScreen},
                      onSelectionChanged: (Set<DanmakuMaxOnScreen> s) =>
                          _update(_settings.copyWith(maxOnScreen: s.first)),
                      segments: <ButtonSegment<DanmakuMaxOnScreen>>[
                        ButtonSegment<DanmakuMaxOnScreen>(
                            value: DanmakuMaxOnScreen.ten,
                            label: Text(l10n.danmakuMaxTen)),
                        ButtonSegment<DanmakuMaxOnScreen>(
                            value: DanmakuMaxOnScreen.twenty,
                            label: Text(l10n.danmakuMaxTwenty)),
                        ButtonSegment<DanmakuMaxOnScreen>(
                            value: DanmakuMaxOnScreen.fifty,
                            label: Text(l10n.danmakuMaxFifty)),
                        ButtonSegment<DanmakuMaxOnScreen>(
                            value: DanmakuMaxOnScreen.hundred,
                            label: Text(l10n.danmakuMaxHundred)),
                      ],
                    ),
                    SettingsSwitchTile(
                      title: l10n.danmakuFollowSpeed,
                      value: _settings.followPlaybackSpeed,
                      onChanged: (v) => _update(
                          _settings.copyWith(followPlaybackSpeed: v)),
                    ),
                  ],
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _keywordSection(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.danmakuFilterKeywords,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppTokens.spaceSm),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _keywordController,
                  decoration: InputDecoration(
                    hintText: l10n.danmakuKeywordHint,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _addKeyword(),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              IconButton.filled(
                icon: const Icon(Icons.add),
                onPressed: _addKeyword,
                tooltip: l10n.danmakuAddKeyword,
              ),
            ],
          ),
          if (_settings.filterKeywords.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              spacing: AppTokens.spaceXs,
              runSpacing: AppTokens.spaceXs,
              children: <Widget>[
                for (final keyword in _settings.filterKeywords)
                  Chip(
                    label: Text(keyword),
                    onDeleted: () => _removeKeyword(keyword),
                  ),
              ],
            ),
          ],
        ],
      ),
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
