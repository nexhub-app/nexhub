import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/comic/models/reader_preferences.dart';
import '../../../core/theme/app_tokens.dart';
import 'reader_image_filter.dart';
import 'reader_tap_zones.dart';

/// 弹出阅读设置面板（modal），返回用户确认后的新偏好（取消返回 null）。
///
/// 内部包 [showModalBottomSheet] 承载 [ReaderSettingsBody]，保持向后兼容。
/// 内联面板场景请直接使用 [ReaderSettingsBody]。
///
/// [onChanged]：草稿变化时实时回调（用于滤镜等需要即时预览的设置）。
/// 调用方在回调中更新阅读器当前偏好，使页面立即重建；取消时由调用方
/// 自行回滚到原偏好。
Future<ReaderPreferences?> showReaderSettings(
  BuildContext context,
  ReaderPreferences current, {
  void Function(ReaderPreferences)? onChanged,
}) =>
    showModalBottomSheet<ReaderPreferences>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      builder: (_) => ReaderSettingsBody(
        initial: current,
        onChanged: onChanged,
        // modal 模式：OK 按钮通过 Navigator.pop 返回草稿；不传 onConfirm 即走默认 pop。
        showConfirmButton: true,
      ),
    );

/// 可复用的阅读器设置内容（既可包在 modal 中，也可承载于内联滑出面板）。
///
/// - [onChanged]：草稿变化时实时回调（实时预览，不落盘）。
/// - [onConfirm]：用户点击 OK 按钮时回调；为 null 时点击 OK 调
///   `Navigator.pop(_draft)`（modal 模式兼容）。
/// - [showConfirmButton]：是否渲染底部 取消/确认 按钮；内联面板通常设为 false，
///   由面板自身提供确认 / 取消按钮。
/// - [showHeader]：是否渲染标题行（标题 + 关闭 + 分割线）；内联面板由父级
///   自带标题条，应设为 false 以避免重复。
class ReaderSettingsBody extends StatefulWidget {
  final ReaderPreferences initial;
  final void Function(ReaderPreferences)? onChanged;
  final void Function(ReaderPreferences)? onConfirm;
  final bool showConfirmButton;
  final bool showHeader;

  const ReaderSettingsBody({
    super.key,
    required this.initial,
    this.onChanged,
    this.onConfirm,
    this.showConfirmButton = true,
    this.showHeader = true,
  });

  @override
  State<ReaderSettingsBody> createState() => _ReaderSettingsBodyState();
}

/// 单个设置项（用于搜索过滤与「常用设置」复用）。
class _SettingItem {
  final List<String> keywords;
  final Widget Function() build;
  final bool Function(ReaderPreferences)? visible;
  _SettingItem(this.keywords, this.build, {this.visible});
}

/// 可折叠分组。
class _SettingsGroup {
  final String id;
  final String title;
  final IconData? icon;
  final List<_SettingItem> items;
  _SettingsGroup(this.id, this.title, this.items, {this.icon});
}

class _ReaderSettingsBodyState extends State<ReaderSettingsBody> {
  late ReaderPreferences _draft;
  String _query = '';
  bool _modelBuilt = false;
  late List<_SettingsGroup> _groups;
  late List<_SettingItem> _commonItems;
  final Map<String, bool> _expanded = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  void _update(ReaderPreferences next) {
    setState(() => _draft = next);
    widget.onChanged?.call(next);
  }

  /// 构建分组模型（含中英文搜索关键词）。需在 l10n 可用时调用一次。
  void _buildModel(AppLocalizations l10n) {
    final pageTap = <_SettingItem>[
      _SettingItem([l10n.readerMode, '阅读模式', '模式', '单页', '从右到左', '竖排', '条漫'],
          _buildReadingMode),
      _SettingItem([l10n.readerBackground, '背景', '黑', '灰', '白', '自动'],
          _buildBackground),
      _SettingItem([l10n.readerOrientation, '屏幕方向', '横屏', '竖屏', '锁定', '旋转', '系统'],
          _buildOrientation),
      _SettingItem([l10n.readerTapZone, '点击区域', '布局', 'L型', '左右', 'kindle', '双边', '关闭'],
          _buildTapZone),
      _SettingItem([l10n.readerTapInvert, '点击反转', '上下', '左右', '全部'],
          _buildTapInvert),
      _SettingItem([l10n.readerSideMargin, '侧边距', '边距', '留白'],
          _buildSideMargin),
      _SettingItem([l10n.readerZoom, '双击缩放', '放大'], _buildDoubleTapZoom),
      _SettingItem([l10n.readerInitialZoom, '初始缩放', '适应宽度', '适应高度', '原始'],
          _buildInitialZoom),
    ];
    final viewFilter = <_SettingItem>[
      _SettingItem([
        l10n.imageFilter,
        l10n.brightness,
        l10n.contrast,
        l10n.colorTemperature,
        l10n.readerGrayscale,
        l10n.filterInverted,
        '画面',
        '滤镜',
        '亮度',
        '对比度',
        '色温',
        '反色',
        '灰度'
      ], _buildImageFilter),
    ];
    final progress = <_SettingItem>[
      _SettingItem([l10n.readerCropEdge, '裁边', '裁剪'], _buildCropEdge),
      _SettingItem([l10n.readerShowPageNumber, '页码', '页数'], _buildShowPageNumber),
      _SettingItem([l10n.readerProgressBarOnRight, '进度条右侧', '右侧'],
          _buildProgressBarOnRight),
      _SettingItem([l10n.readerKeepScreenOn, '常亮', '屏幕常亮', '休眠'], _buildKeepScreenOn),
      _SettingItem([l10n.readerRotatePage, '页面旋转', '横屏旋转', '旋转'],
          _buildRotatePage),
      _SettingItem([l10n.readerSplitDoublePage, '双页拆分', '双页', '拼页'],
          _buildSplitDoublePage),
      _SettingItem([l10n.readerFullscreen, '全屏'], _buildFullscreen),
      _SettingItem([l10n.readerLongPressMenu, '长按菜单', '菜单'], _buildLongPressMenu),
      _SettingItem([l10n.readerPreventShrink, '防缩', '缩小'], _buildPreventShrink),
      _SettingItem([l10n.readerChapterTransition, '章节过渡', '翻章', '过渡'],
          _buildChapterTransition),
    ];
    final flash = <_SettingItem>[
      _SettingItem([l10n.readerFlashEnabled, '闪屏', '闪光', '效果'], _buildFlashEnabled),
      _SettingItem([l10n.readerFlashTime, '闪屏时长', '时长', '时间'], _buildFlashTime,
          visible: (d) => d.flashEnabled),
      _SettingItem([l10n.readerFlashInterval, '闪屏间隔', '间隔'], _buildFlashInterval,
          visible: (d) => d.flashEnabled),
      _SettingItem([l10n.readerFlashColor, '闪屏颜色', '颜色'], _buildFlashColor,
          visible: (d) => d.flashEnabled),
    ];
    _groups = <_SettingsGroup>[
      _SettingsGroup('pageTap', l10n.readerGroupPageTap, pageTap,
          icon: Icons.touch_app),
      _SettingsGroup('viewFilter', l10n.readerGroupViewFilter, viewFilter,
          icon: Icons.tune),
      _SettingsGroup('progress', l10n.readerGroupProgress, progress,
          icon: Icons.display_settings),
      _SettingsGroup('flash', l10n.readerGroupFlash, flash,
          icon: Icons.flash_on),
    ];

    // 「常用设置」：阅读时最高频调整的几项快捷入口。
    _commonItems = <_SettingItem>[
      _SettingItem([l10n.readerMode, '阅读模式', '模式'], _buildReadingMode),
      _SettingItem([l10n.brightness, '亮度', '明度'], _buildBrightness),
      _SettingItem([l10n.readerZoom, '双击缩放', '放大'], _buildDoubleTapZoom),
      _SettingItem([l10n.readerInitialZoom, '初始缩放', '适应'], _buildInitialZoom),
      _SettingItem([l10n.readerFullscreen, '全屏'], _buildFullscreen),
    ];
  }

  bool _match(_SettingItem it, String q) =>
      q.isEmpty || it.keywords.any((k) => k.toLowerCase().contains(q));

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (!_modelBuilt) {
      _buildModel(l10n);
      _modelBuilt = true;
      _expanded[_groups.first.id] = true;
    }
    final String q = _query.trim().toLowerCase();
    final bool searching = q.isNotEmpty;

    final commonVisible = _commonItems
        .where((it) => (it.visible?.call(_draft) ?? true) && _match(it, q))
        .toList();

    final List<Widget> groupWidgets = <Widget>[];
    for (final g in _groups) {
      final kids = g.items
          .where((it) => (it.visible?.call(_draft) ?? true) && _match(it, q))
          .toList();
      if (searching && kids.isEmpty) continue;
      groupWidgets.add(_CollapsibleGroup(
        title: g.title,
        icon: g.icon,
        expanded: searching || (_expanded[g.id] ?? false),
        onToggle: searching
            ? null
            : () => setState(() => _expanded[g.id] = !(_expanded[g.id] ?? false)),
        children: kids.map((it) => it.build()).toList(),
      ));
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.spaceLg,
        AppTokens.spaceLg,
        AppTokens.spaceLg + MediaQuery.of(context).padding.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (widget.showHeader) ...<Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(l10n.readerSettings,
                      style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(_draft),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: AppTokens.spaceSm),
            ],
            _SearchBar(
              initial: _query,
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            if (commonVisible.isNotEmpty)
              _CommonCard(
                icon: Icons.star,
                items: commonVisible,
              ),
            ...groupWidgets,
            const SizedBox(height: AppTokens.spaceMd),
            if (widget.showConfirmButton)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  FilledButton(
                    onPressed: () {
                      final cb = widget.onConfirm;
                      if (cb != null) {
                        cb(_draft);
                      } else {
                        Navigator.of(context).pop(_draft);
                      }
                    },
                    child: Text(l10n.confirm),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ---- 各设置项控件构建 ----

  Widget _buildReadingMode() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: ReadingMode.values.map((m) {
        return ChoiceChip(
          label: Text(l10nKey(m.l10nKey())),
          selected: _draft.readingMode == m,
          onSelected: (_) {
            // 切到竖排 / 长条模式时，双页拆分不再生效，自动关闭避免「开着却没用」。
            final bool compatible =
                m == ReadingMode.singleLTR || m == ReadingMode.singleRTL;
            _update(_draft.copyWith(
              readingMode: m,
              splitDoublePage: compatible ? _draft.splitDoublePage : false,
            ));
          },
        );
      }).toList(),
    );
  }

  Widget _buildBackground() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: ReaderBackgroundColor.values.map((b) {
        return ChoiceChip(
          label: Text(l10nKey(b.l10nKey())),
          selected: _draft.background == b,
          onSelected: (_) => _update(_draft.copyWith(background: b)),
        );
      }).toList(),
    );
  }

  Widget _buildOrientation() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: ScreenOrientation.values.map((o) {
        return ChoiceChip(
          label: Text(l10nKey(o.l10nKey())),
          selected: _draft.orientation == o,
          onSelected: (_) => _update(_draft.copyWith(orientation: o)),
        );
      }).toList(),
    );
  }

  Widget _buildTapZone() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceSm,
          children: <ReaderTapZoneLayout>[
            ReaderTapZoneLayout.lShape,
            ReaderTapZoneLayout.leftRight,
            ReaderTapZoneLayout.kindle,
            ReaderTapZoneLayout.bothSides,
            ReaderTapZoneLayout.off,
          ].map((t) {
            return ChoiceChip(
              label: Text(l10nKey(t.l10nKey())),
              selected: _draft.tapZoneLayout == t,
              onSelected: (_) => _update(_draft.copyWith(tapZoneLayout: t)),
            );
          }).toList(),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Text(l10n.readerTapPreviewHint,
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppTokens.spaceXs),
        SizedBox(
          height: 160,
          child: ReaderTapZones(
            showPreview: true,
            layout: _draft.tapZoneLayout,
            tapZoneInvert: _draft.tapZoneInvert,
            isVertical: false,
            previewLabels: <String, String>{
              'prev': l10n.tapPreviewPrev,
              'next': l10n.tapPreviewNext,
              'toggle': l10n.tapPreviewToggle,
            },
            onPrev: () {},
            onNext: () {},
            onToggleUi: () {},
          ),
        ),
      ],
    );
  }

  Widget _buildTapInvert() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: TapZoneInvert.values.map((t) {
        return ChoiceChip(
          label: Text(l10nKey(t.l10nKey())),
          selected: _draft.tapZoneInvert == t,
          onSelected: (_) => _update(_draft.copyWith(tapZoneInvert: t)),
        );
      }).toList(),
    );
  }

  Widget _buildSideMargin() {
    final l10n = AppLocalizations.of(context);
    return _SliderRow(
      label: l10n.readerSideMargin,
      value: _draft.sideMargin,
      min: 0.0,
      max: 0.5,
      divisions: 50,
      displayValue: '${(_draft.sideMargin * 100).round()}%',
      onChanged: (v) => _update(_draft.copyWith(sideMargin: v)),
    );
  }

  Widget _buildDoubleTapZoom() {
    final l10n = AppLocalizations.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(l10n.readerZoom),
      value: _draft.doubleTapZoom,
      onChanged: (v) => _update(_draft.copyWith(doubleTapZoom: v)),
    );
  }

  Widget _buildInitialZoom() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: ReaderInitialZoom.values.map((z) {
        return ChoiceChip(
          label: Text(l10nKey(z.l10nKey())),
          selected: _draft.initialZoom == z,
          onSelected: (_) => _update(_draft.copyWith(initialZoom: z)),
        );
      }).toList(),
    );
  }

  Widget _buildImageFilter() {
    return ReaderImageFilterPanel(
      brightness: _draft.filterBrightness,
      contrast: _draft.filterContrast,
      colorTemp: _draft.filterColorTemp,
      saturation: _draft.filterSaturation,
      hue: _draft.filterHue,
      inverted: _draft.filterInverted,
      grayscale: _draft.filterGrayscale,
      onChanged: (b, c, t, s, h) => _update(_draft.copyWith(
        filterBrightness: b,
        filterContrast: c,
        filterColorTemp: t,
        filterSaturation: s,
        filterHue: h,
      )),
      onInvertedChanged: (v) => _update(_draft.copyWith(filterInverted: v)),
      onGrayscaleChanged: (v) => _update(_draft.copyWith(filterGrayscale: v)),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: onChanged,
      );

  Widget _buildCropEdge() {
    final l10n = AppLocalizations.of(context);
    return _switch(l10n.readerCropEdge, _draft.cropEdge,
        (v) => _update(_draft.copyWith(cropEdge: v)));
  }

  Widget _buildShowPageNumber() {
    final l10n = AppLocalizations.of(context);
    return _switch(l10n.readerShowPageNumber, _draft.showPageNumber,
        (v) => _update(_draft.copyWith(showPageNumber: v)));
  }

  Widget _buildProgressBarOnRight() {
    final l10n = AppLocalizations.of(context);
    return _switch(l10n.readerProgressBarOnRight, _draft.progressBarOnRight,
        (v) => _update(_draft.copyWith(progressBarOnRight: v)));
  }

  Widget _buildKeepScreenOn() {
    final l10n = AppLocalizations.of(context);
    return _switch(l10n.readerKeepScreenOn, _draft.keepScreenOn,
        (v) => _update(_draft.copyWith(keepScreenOn: v)));
  }

  Widget _buildRotatePage() {
    final l10n = AppLocalizations.of(context);
    return _switch(l10n.readerRotatePage, _draft.rotateLandscape,
        (v) => _update(_draft.copyWith(rotateLandscape: v)));
  }

  Widget _buildSplitDoublePage() {
    final l10n = AppLocalizations.of(context);
    return _switch(l10n.readerSplitDoublePage, _draft.splitDoublePage, (v) {
      ReaderPreferences next = _draft.copyWith(splitDoublePage: v);
      // 双页拆分仅在横排单页（LTR/RTL）模式生效；若当前为竖排 / 长条模式，
      // 开启拆分时自动切到横排单页，确保开关「有作用」（修复「双页拆分没有作用」）。
      if (v &&
          _draft.readingMode != ReadingMode.singleLTR &&
          _draft.readingMode != ReadingMode.singleRTL) {
        next = next.copyWith(readingMode: ReadingMode.singleLTR);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.readerSplitDoublePageHint),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      _update(next);
    });
  }

  Widget _buildFullscreen() {
    final l10n = AppLocalizations.of(context);
    return _switch(l10n.readerFullscreen, _draft.fullscreen,
        (v) => _update(_draft.copyWith(fullscreen: v)));
  }

  Widget _buildLongPressMenu() {
    final l10n = AppLocalizations.of(context);
    return _switch(l10n.readerLongPressMenu, _draft.showLongPressMenu,
        (v) => _update(_draft.copyWith(showLongPressMenu: v)));
  }

  Widget _buildPreventShrink() {
    final l10n = AppLocalizations.of(context);
    return _switch(l10n.readerPreventShrink, _draft.preventShrink,
        (v) => _update(_draft.copyWith(preventShrink: v)));
  }

  Widget _buildChapterTransition() {
    final l10n = AppLocalizations.of(context);
    return _switch(l10n.readerChapterTransition, _draft.showChapterTransition,
        (v) => _update(_draft.copyWith(showChapterTransition: v)));
  }

  Widget _buildFlashEnabled() {
    final l10n = AppLocalizations.of(context);
    return _switch(l10n.readerFlashEnabled, _draft.flashEnabled,
        (v) => _update(_draft.copyWith(flashEnabled: v)));
  }

  Widget _buildFlashTime() {
    final l10n = AppLocalizations.of(context);
    return _SliderRow(
      label: l10n.readerFlashTime,
      value: _draft.flashTime.toDouble(),
      min: 50,
      max: 600,
      divisions: 55,
      displayValue: '${_draft.flashTime} ms',
      onChanged: (v) => _update(_draft.copyWith(flashTime: v.round())),
    );
  }

  Widget _buildFlashInterval() {
    final l10n = AppLocalizations.of(context);
    return _SliderRow(
      label: l10n.readerFlashInterval,
      value: _draft.flashInterval.toDouble(),
      min: 0,
      max: 600,
      divisions: 60,
      displayValue: '${_draft.flashInterval} ms',
      onChanged: (v) => _update(_draft.copyWith(flashInterval: v.round())),
    );
  }

  Widget _buildFlashColor() {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: ReaderFlashColor.values.map((c) {
        return ChoiceChip(
          label: Text(l10nKey(c.l10nKey())),
          selected: _draft.flashColor == c,
          onSelected: (_) => _update(_draft.copyWith(flashColor: c)),
        );
      }).toList(),
    );
  }

  Widget _buildBrightness() {
    final l10n = AppLocalizations.of(context);
    return _SliderRow(
      label: l10n.brightness,
      value: _draft.filterBrightness,
      min: -1.0,
      max: 1.0,
      divisions: 200,
      displayValue: _draft.filterBrightness.toStringAsFixed(2),
      onChanged: (v) => _update(_draft.copyWith(filterBrightness: v)),
    );
  }

  /// 通过 l10n key 名称取本地化字符串（避免在此硬编码）。
  String l10nKey(String key) {
    final l10n = AppLocalizations.of(context);
    switch (key) {
      case 'readerModeSingleLTR':
        return l10n.readerModeSingleLTR;
      case 'readerModeSingleRTL':
        return l10n.readerModeSingleRTL;
      case 'readerModeSingleVertical':
        return l10n.readerModeSingleVertical;
      case 'readerModeWebtoon':
        return l10n.readerModeWebtoon;
      case 'readerModeWebtoonWithGap':
        return l10n.readerModeWebtoonWithGap;
      case 'readerOrientationDefault':
        return l10n.readerOrientationDefault;
      case 'readerOrientationSystem':
        return l10n.readerOrientationSystem;
      case 'readerOrientationPortrait':
        return l10n.readerOrientationPortrait;
      case 'readerOrientationLandscape':
        return l10n.readerOrientationLandscape;
      case 'readerOrientationLockPortrait':
        return l10n.readerOrientationLockPortrait;
      case 'readerOrientationLockLandscape':
        return l10n.readerOrientationLockLandscape;
      case 'readerOrientationReversePortrait':
        return l10n.readerOrientationReversePortrait;
      case 'readerBgBlack':
        return l10n.readerBgBlack;
      case 'readerBgGray':
        return l10n.readerBgGray;
      case 'readerBgWhite':
        return l10n.readerBgWhite;
      case 'readerBgAuto':
        return l10n.readerBgAuto;
      case 'readerTapLShape':
        return l10n.readerTapLShape;
      case 'readerTapKindle':
        return l10n.readerTapKindle;
      case 'readerTapBothSides':
        return l10n.readerTapBothSides;
      case 'readerTapOff':
        return l10n.readerTapOff;
      case 'readerTapInvertNone':
        return l10n.readerTapInvertNone;
      case 'readerTapInvertLeftRight':
        return l10n.readerTapInvertLeftRight;
      case 'readerTapInvertUpDown':
        return l10n.readerTapInvertUpDown;
      case 'readerTapInvertAll':
        return l10n.readerTapInvertAll;
      case 'readerTapLeftRight':
        return l10n.readerTapLeftRight;
      case 'readerFlashBlack':
        return l10n.readerFlashBlack;
      case 'readerFlashWhite':
        return l10n.readerFlashWhite;
      case 'readerFlashBlackWhite':
        return l10n.readerFlashBlackWhite;
      case 'readerZoomFitWidth':
        return l10n.readerZoomFitWidth;
      case 'readerZoomFitHeight':
        return l10n.readerZoomFitHeight;
      case 'readerZoomOriginal':
        return l10n.readerZoomOriginal;
      default:
        return key;
    }
  }
}

/// 顶部搜索框。
class _SearchBar extends StatefulWidget {
  final String initial;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.initial, required this.onChanged});

  static const double _radius = 24;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: l10n.readerSearchSettings,
        suffixIcon: widget.initial.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                },
              )
            : null,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_SearchBar._radius),
          borderSide: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_SearchBar._radius),
          borderSide: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_SearchBar._radius),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }
}

/// 「常用设置」快捷卡。
class _CommonCard extends StatelessWidget {
  final IconData? icon;
  final List<_SettingItem> items;
  const _CommonCard({this.icon, required this.items});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppTokens.spaceMd),
      ),
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: AppTokens.spaceSm),
              ],
              Text(l10n.readerCommonSettings,
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          ...items.expand((it) => [it.build(), const SizedBox(height: AppTokens.spaceSm)]),
        ],
      ),
    );
  }
}

/// 可折叠分组（搜索时强制展开并过滤子项）。
class _CollapsibleGroup extends StatelessWidget {
  final String title;
  final IconData? icon;
  final bool expanded;
  final VoidCallback? onToggle;
  final List<Widget> children;
  const _CollapsibleGroup({
    required this.title,
    this.icon,
    required this.expanded,
    this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
            child: Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 20, color: colorScheme.primary),
                  const SizedBox(width: AppTokens.spaceSm),
                ],
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (onToggle != null)
                  Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        if (expanded)
          ...children.expand((c) => [c, const SizedBox(height: AppTokens.spaceSm)]),
        const SizedBox(height: AppTokens.spaceMd),
      ],
    );
  }
}

/// 通用滑块行（标签 + 滑块 + 数值）。
class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
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
            width: 64,
            child: Text(
              displayValue,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
