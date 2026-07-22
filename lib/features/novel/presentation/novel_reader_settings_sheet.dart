import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/novel/novel_page_animation.dart';
import '../../../core/novel/novel_reader_preferences.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/reader_tokens.dart';

/// 显示小说阅读器设置面板（ModalBottomSheet）。
///
/// 返回更新后的 [NovelReaderPreferences]；用户取消返回 null。
Future<NovelReaderPreferences?> showNovelReaderSettings(
  BuildContext context,
  NovelReaderPreferences current,
) {
  return showModalBottomSheet<NovelReaderPreferences>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NovelSettingsSheet(initial: current),
  );
}

class _NovelSettingsSheet extends StatefulWidget {
  final NovelReaderPreferences initial;
  const _NovelSettingsSheet({required this.initial});

  @override
  State<_NovelSettingsSheet> createState() => _NovelSettingsSheetState();
}

class _NovelSettingsSheetState extends State<_NovelSettingsSheet> {
  late NovelReaderPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _prefs = widget.initial;
  }

  void _update(NovelReaderPreferences next) {
    setState(() => _prefs = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 标题行
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  l10n.readerSettings,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(_prefs),
                ),
              ],
            ),
            const Divider(),

            // 字体大小
            _SliderRow(
              label: l10n.novelFontSize,
              value: _prefs.fontSize,
              min: 12,
              max: 32,
              divisions: 20,
              unit: 'sp',
              onChanged: (v) =>
                  _update(_prefs.copyWith(fontSize: v)),
            ),

            // 行距
            _SliderRow(
              label: l10n.novelLineHeight,
              value: _prefs.lineHeight,
              min: 1.2,
              max: 3.0,
              divisions: 18,
              onChanged: (v) =>
                  _update(_prefs.copyWith(lineHeight: v)),
            ),

            // 段距
            _SliderRow(
              label: l10n.novelParagraphSpacing,
              value: _prefs.paragraphSpacing,
              min: 4,
              max: 48,
              divisions: 22,
              unit: 'px',
              onChanged: (v) =>
                  _update(_prefs.copyWith(paragraphSpacing: v)),
            ),

            // 边距
            _SliderRow(
              label: l10n.novelMargin,
              value: _prefs.margin,
              min: 8,
              max: 64,
              divisions: 14,
              unit: 'px',
              onChanged: (v) =>
                  _update(_prefs.copyWith(margin: v)),
            ),

            const SizedBox(height: AppTokens.spaceMd),

            // 翻页动画
            Text(l10n.novelPageAnimation,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              children: <Widget>[
                for (final anim in NovelPageAnimation.values)
                  ChoiceChip(
                    label: Text(_animLabel(anim, l10n)),
                    selected: _prefs.pageAnimation == anim,
                    onSelected: (_) =>
                        _update(_prefs.copyWith(pageAnimation: anim)),
                  ),
              ],
            ),

            const SizedBox(height: AppTokens.spaceMd),

            // 背景预设
            Text(l10n.readerBackground,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              children: <Widget>[
                for (int i = 0; i < ReaderTokens.bgPresets.length; i++)
                  ChoiceChip(
                    label: Text(_bgLabel(i, l10n)),
                    selected: _prefs.bgPresetIndex == i &&
                        _prefs.customBgColor == null,
                    onSelected: (_) => _update(_prefs.copyWith(
                      bgPresetIndex: i,
                      customBgColor: null,
                    )),
                  ),
              ],
            ),

            const SizedBox(height: AppTokens.spaceMd),

            // 文字阴影
            SwitchListTile(
              title: Text(l10n.novelTextShadow),
              value: _prefs.shadow,
              onChanged: (v) => _update(_prefs.copyWith(shadow: v)),
            ),

            const SizedBox(height: AppTokens.spaceMd),

            // 底部按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: AppTokens.spaceSm),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_prefs),
                  child: Text(l10n.confirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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

  String _bgLabel(int index, AppLocalizations l10n) {
    return switch (index) {
      0 => l10n.readerBgBlack,
      1 => l10n.readerBgGray,
      _ => l10n.readerBgWhite,
    };
  }
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
