/// 设置子页公共组件。
///
/// 把散落在播放器 / 阅读器 / 布局 / 弹幕等设置页里重复的
/// “分组标题 + 滑块 + 开关 + 分段单选”代码收敛到一处，统一风格：
/// - [SettingsSection]：分组标题 + 可选说明；
/// - [SettingsCard]：带标题的卡片容器（圆角 + 阴影 + 统一内边距）；
/// - [SettingsSliderTile]：带当前值的滑块；
/// - [SettingsSwitchTile]：开关项；
/// - [SettingsSegmentedTile]：分段单选（SegmentedButton 包装）；
/// - [SettingsChoiceChips]：单选 Chip。
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// 分组标题（不含卡片背景）。用于卡片外部的独立小标题。
class SettingsSection extends StatelessWidget {
  final String title;
  final String? description;
  final EdgeInsetsGeometry? padding;

  const SettingsSection({
    super.key,
    required this.title,
    this.description,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ??
          const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceXs,
            vertical: AppTokens.spaceXs,
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (description != null) ...<Widget>[
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              description!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// 带标题的卡片容器。把所有同类设置项收进一个 [AppCard]，视觉分组更清晰。
class SettingsCard extends StatelessWidget {
  final String? title;
  final String? description;
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;

  const SettingsCard({
    super.key,
    this.title,
    this.description,
    required this.children,
    this.margin,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final List<Widget> body = <Widget>[];
    if (title != null) {
      body.add(
        Text(
          title!,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      if (description != null) {
        body.add(const SizedBox(height: AppTokens.spaceXs));
        body.add(
          Text(
            description!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        );
      }
      body.add(const SizedBox(height: AppTokens.spaceMd));
    }
    body.add(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _spaced(children, AppTokens.spaceMd),
      ),
    );

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: AppTokens.spaceMd),
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: body,
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> children, double gap) {
    if (children.isEmpty) return children;
    final List<Widget> out = <Widget>[children.first];
    for (var i = 1; i < children.length; i++) {
      out
        ..add(const SizedBox(height: AppTokens.spaceMd))
        ..add(children[i]);
    }
    return out;
  }
}

/// 带当前显示值的滑块。
class SettingsSliderTile extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  const SettingsSliderTile({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(
                display,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// 开关项。
class SettingsSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }
}

/// 分段单选（SegmentedButton 包装）。标题在上、选项在下。
class SettingsSegmentedTile<T extends Object> extends StatelessWidget {
  final String title;
  final String? description;
  final Set<T> selected;
  final void Function(Set<T>) onSelectionChanged;
  final List<ButtonSegment<T>> segments;
  final EdgeInsetsGeometry? margin;

  const SettingsSegmentedTile({
    super.key,
    required this.title,
    this.description,
    required this.selected,
    required this.onSelectionChanged,
    required this.segments,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: title,
      description: description,
      margin: margin,
      children: <Widget>[
        SegmentedButton<T>(
          selected: selected,
          onSelectionChanged: onSelectionChanged,
          segments: segments,
        ),
      ],
    );
  }
}

/// 单选 Chip 组。
class SettingsChoiceChips<T> extends StatelessWidget {
  final String title;
  final String? description;
  final T selected;
  final void Function(T) onSelected;
  final List<SettingsChoiceChipData<T>> options;
  final EdgeInsetsGeometry? margin;

  const SettingsChoiceChips({
    super.key,
    required this.title,
    this.description,
    required this.selected,
    required this.onSelected,
    required this.options,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      title: title,
      description: description,
      margin: margin,
      children: <Widget>[
        Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceXs,
          children: <Widget>[
            for (final opt in options)
              ChoiceChip(
                label: Text(opt.label),
                selected: opt.value == selected,
                onSelected: (_) => onSelected(opt.value),
              ),
          ],
        ),
      ],
    );
  }
}

/// [SettingsChoiceChips] 的单选项。
class SettingsChoiceChipData<T> {
  final T value;
  final String label;
  const SettingsChoiceChipData({required this.value, required this.label});
}
