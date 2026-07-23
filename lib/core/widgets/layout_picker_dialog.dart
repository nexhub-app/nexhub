/// 富布局弹窗（项 4/11）—— 底部弹窗，单一「布局类型」选择器 + 细项同屏即时生效。
///
/// 全局唯一的布局设置入口（书架/已下载/浏览/搜索/设置页均通过 [LayoutPickerButton]
/// 或直接调用本函数弹出），与 [showOnlineFilterSheet] 风格一致。
///
/// 设计要点（修复「书架布局按钮无效 / 布局类型重复 / 预览不对应」）：
/// - 全弹窗只维护**一个**布局 store：[LayoutSettingsStore]，渲染层（浏览页/结果页/
///   已下载页/书架页）都读它，故任何改动即时生效、预览与真实列表一致。
/// - 「布局类型」用单一 grid/list 分段按钮驱动 [LayoutSettings.layoutMode]；
///   不再保留写往一个「从未被渲染读取」的 [BookshelfLayoutPreferences] 的死控件。
/// - 网格/列表**条件显示**：选网格→列数+间距；选列表→列表风格。
/// - 网格与封面（圆角/标题字号）、显示选项（标题/作者/进度）两种模式下共用。
library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../settings/layout_settings.dart';
import '../theme/app_tokens.dart';
import 'app_card.dart';

/// 以 modal bottom sheet 形式展示富布局弹窗。
///
/// 所有改动即时写入 [LayoutSettingsStore.instance]，订阅方（浏览页/结果页/
/// 已下载页/书架页/设置页）同步刷新。
Future<void> showLayoutPickerDialog(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => const _LayoutPickerSheet(),
  );
}

class _LayoutPickerSheet extends StatefulWidget {
  const _LayoutPickerSheet();

  @override
  State<_LayoutPickerSheet> createState() => _LayoutPickerSheetState();
}

class _LayoutPickerSheetState extends State<_LayoutPickerSheet> {
  final LayoutSettingsStore _store = LayoutSettingsStore.instance;
  late LayoutSettings _current;

  @override
  void initState() {
    super.initState();
    _current = _store.settings;
  }

  void _commit(LayoutSettings next) {
    _current = next;
    _store.save(next);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTokens.spaceLg,
          right: AppTokens.spaceLg,
          top: AppTokens.spaceLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTokens.spaceLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ── 标题栏 ──
              Row(
                children: <Widget>[
                  Icon(Icons.tune, size: 22, color: scheme.primary),
                  const SizedBox(width: AppTokens.spaceSm),
                  Text(
                    l10n.layoutSettings,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: l10n.close ?? 'Close',
                  ),
                ],
              ),

              // ── 实时预览区（与真实列表一致）──
              const SizedBox(height: AppTokens.spaceMd),
              _PreviewCard(settings: _current),

              // ── 布局类型（唯一 grid/list 选择器）──
              _buildSection(
                title: l10n.layoutTypeLabel,
                children: <Widget>[
                  _segmentedRow<LayoutMode>(
                    label: l10n.layoutModeLabel,
                    selected: <LayoutMode>{_current.layoutMode},
                    onSelectionChanged: (s) =>
                        _commit(_current.copyWith(layoutMode: s.first)),
                    segments: <ButtonSegment<LayoutMode>>[
                      ButtonSegment<LayoutMode>(
                        value: LayoutMode.grid,
                        label: Text(l10n.bookshelfLayoutGrid),
                        icon: const Icon(Icons.grid_view, size: 18),
                      ),
                      ButtonSegment<LayoutMode>(
                        value: LayoutMode.list,
                        label: Text(l10n.bookshelfLayoutList),
                        icon: const Icon(Icons.view_list, size: 18),
                      ),
                    ],
                  ),
                ],
              ),

              // ── 布局细节（按模式条件显示）──
              _buildSection(
                title: l10n.layoutDetailGroup,
                children: <Widget>[
                  if (_current.layoutMode == LayoutMode.grid) ...<Widget>[
                    _SliderTile(
                      icon: Icons.view_column,
                      label: l10n.layoutGridColumns,
                      value: _current.gridColumns.toDouble(),
                      min: 1,
                      max: 8,
                      divisions: 7,
                      onChanged: (v) =>
                          _commit(_current.copyWith(gridColumns: v.toInt())),
                    ),
                    _SliderTile(
                      icon: Icons.horizontal_distribute,
                      label: l10n.layoutGridSpacing,
                      value: _current.gridSpacing.clamp(4, 24),
                      min: 4,
                      max: 24,
                      divisions: 20,
                      onChanged: (v) =>
                          _commit(_current.copyWith(gridSpacing: v)),
                    ),
                  ] else ...<Widget>[
                    _segmentedRow<ListLayoutStyle>(
                      label: l10n.layoutListStyle,
                      selected: <ListLayoutStyle>{_current.listStyle},
                      onSelectionChanged: (s) =>
                          _commit(_current.copyWith(listStyle: s.first)),
                      segments: <ButtonSegment<ListLayoutStyle>>[
                        ButtonSegment<ListLayoutStyle>(
                          value: ListLayoutStyle.comfortable,
                          label: Text(l10n.layoutListComfortable),
                        ),
                        ButtonSegment<ListLayoutStyle>(
                          value: ListLayoutStyle.compact,
                          label: Text(l10n.layoutListCompact),
                        ),
                      ],
                    ),
                  ],
                ],
              ),

              // ── 网格与封面（两种模式共用）──
              _buildSection(
                title: l10n.layoutGridCoverGroup,
                children: <Widget>[
                  _SliderTile(
                    icon: Icons.rounded_corner,
                    label: l10n.layoutCoverRadius,
                    value: _current.coverRadius.clamp(0, 24),
                    min: 0,
                    max: 24,
                    divisions: 24,
                    onChanged: (v) =>
                        _commit(_current.copyWith(coverRadius: v)),
                  ),
                  _SliderTile(
                    icon: Icons.text_fields,
                    label: l10n.layoutTitleFontSize,
                    value: _current.titleFontSize.clamp(12, 18),
                    min: 12,
                    max: 18,
                    divisions: 6,
                    onChanged: (v) =>
                        _commit(_current.copyWith(titleFontSize: v)),
                  ),
                ],
              ),

              // ── 显示选项 ──
              _buildSection(
                title: l10n.layoutDisplayGroup,
                children: <Widget>[
                  _SwitchTile(
                    icon: Icons.title,
                    label: l10n.layoutShowTitle,
                    value: _current.showTitle,
                    onChanged: (v) => _commit(_current.copyWith(showTitle: v)),
                  ),
                  if (_current.showTitle)
                    Padding(
                      padding: EdgeInsets.only(left: AppTokens.spaceXl),
                      child: _StepperInline(
                        label: l10n.layoutTitleMaxLines,
                        value: _current.titleMaxLines,
                        minValue: 1,
                        maxValue: 3,
                        onChanged: (v) =>
                            _commit(_current.copyWith(titleMaxLines: v)),
                      ),
                    ),
                  _SwitchTile(
                    icon: Icons.person_outline,
                    label: l10n.layoutShowAuthor,
                    value: _current.showAuthor,
                    onChanged: (v) =>
                        _commit(_current.copyWith(showAuthor: v)),
                  ),
                  _SwitchTile(
                    icon: Icons.pie_chart_outline,
                    label: l10n.layoutShowProgress,
                    value: _current.showProgress,
                    onChanged: (v) =>
                        _commit(_current.copyWith(showProgress: v)),
                  ),
                  if (_current.showProgress)
                    _segmentedRow<ProgressDisplayMode>(
                      label: l10n.layoutProgressDisplay,
                      selected: <ProgressDisplayMode>{_current.progressDisplay},
                      onSelectionChanged: (s) => _commit(
                          _current.copyWith(progressDisplay: s.first)),
                      segments: <ButtonSegment<ProgressDisplayMode>>[
                        ButtonSegment<ProgressDisplayMode>(
                          value: ProgressDisplayMode.bar,
                          label: Text(l10n.progressBar),
                        ),
                        ButtonSegment<ProgressDisplayMode>(
                          value: ProgressDisplayMode.text,
                          label: Text(l10n.progressText),
                        ),
                      ],
                    ),
                ],
              ),

            ],
          ),
        ),
      ),
    );
  }

  /// 分区卡片（与详情页筛选弹窗同风格：AppCard 包裹 + 标题）。
  Widget _buildSection({
    required String title,
    bool show = true,
    required List<Widget> children,
  }) {
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppTokens.spaceMd),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceSm,
            vertical: AppTokens.spaceSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceSm,
                  AppTokens.spaceSm,
                  AppTokens.spaceSm,
                  AppTokens.spaceXs,
                ),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  /// 分段按钮行。
  Widget _segmentedRow<T>({
    required String label,
    required Set<T> selected,
    required List<ButtonSegment<T>> segments,
    required void Function(Set<T>) onSelectionChanged,
  }) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          SegmentedButton<T>(
            selected: selected,
            onSelectionChanged: onSelectionChanged,
            showSelectedIcon: false,
            segments: segments,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 子组件 —— 视觉增强版
// ═══════════════════════════════════════════════════════════════════════════

/// 布局预览卡 —— 直接反映 [LayoutSettings] 的真实数值，与列表页渲染一致。
class _PreviewCard extends StatelessWidget {
  final LayoutSettings settings;
  const _PreviewCard({required this.settings});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool isList = settings.layoutMode == LayoutMode.list;
    // 预览最多显示 4 列，避免列数过多时每个色块太小看不清
    final int cross = isList ? 1 : settings.gridColumns.clamp(1, 4);
    final double radius = settings.coverRadius.clamp(0, 16);
    // 预览区间距按比例缩小，避免过大或过小
    final double spacing = (settings.gridSpacing.clamp(4, 24) * 0.5).clamp(2, 12);

    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.preview, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppTokens.spaceXs),
              Text(
                isList
                    ? 'List · ${settings.listStyle.name}'
                    : 'Grid · ${settings.gridColumns} col · spacing ${settings.gridSpacing.toInt()}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              // 实时反映圆角和字号
              Text(
                'r:${settings.coverRadius.toInt()} fs:${settings.titleFontSize.toInt()}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          // 缩略预览网格（使用真实间距/圆角，与列表一致）
          SizedBox(
            height: isList ? 52 : 60,
            child: GridView.builder(
              scrollDirection: Axis.horizontal,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cross,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                // 网格模式用接近真实封面比例；列表模式用宽扁比例
                childAspectRatio: isList ? 3.5 : 0.72,
              ),
              itemCount: cross * (isList ? 1 : 2),
              itemBuilder: (_, i) => _PreviewItem(
                scheme: scheme,
                radius: radius,
                showTitle: settings.showTitle,
                showAuthor: settings.showAuthor,
                showProgress: settings.showProgress,
                progressAsBar: settings.progressDisplay == ProgressDisplayMode.bar,
                isList: isList,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个预览项（模拟 ContentCard / ListItem 的视觉效果）。
class _PreviewItem extends StatelessWidget {
  final ColorScheme scheme;
  final double radius;
  final bool showTitle;
  final bool showAuthor;
  final bool showProgress;
  final bool progressAsBar;
  final bool isList;

  const _PreviewItem({
    required this.scheme,
    required this.radius,
    required this.showTitle,
    required this.showAuthor,
    required this.showProgress,
    required this.progressAsBar,
    required this.isList,
  });

  @override
  Widget build(BuildContext context) {
    final cover = Container(
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    if (isList) {
      // 列表模式预览：左侧缩略图 + 右侧文本行
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(width: 32, height: 44, child: cover),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (showTitle)
                  Container(
                    width: 48,
                    height: 6,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                if (showTitle && showAuthor)
                  const SizedBox(height: 4),
                if (showAuthor)
                  Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
          if (showProgress)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: progressAsBar
                  ? SizedBox(
                      width: 28,
                      height: 3,
                      child: LinearProgressIndicator(
                        value: 0.6,
                        backgroundColor: scheme.surfaceContainerHighest,
                        color: scheme.primary,
                      ),
                    )
                  : Text('60%',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      )),
            ),
        ],
      );
    }

    // 网格模式预览：封面在上 + 标题/作者/进度在下
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Expanded(
          flex: 3,
          child: cover,
        ),
        if (showTitle) ...<Widget>[
          const SizedBox(height: 3),
          Container(
            width: 28,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
        if (showAuthor && showTitle) const SizedBox(height: 2),
        if (showAuthor && !showTitle)
          const SizedBox(height: 3),
        if (showAuthor)
          Container(
            width: 20,
            height: 3,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        if (showProgress && progressAsBar) ...<Widget>[
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: LinearProgressIndicator(
              value: 0.6,
              minHeight: 2,
              backgroundColor: scheme.surfaceContainerHighest,
              color: scheme.primary,
            ),
          ),
        ],
      ],
    );
  }
}

/// 带图标的滑块行（icon + label + slider + 数值）。
class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              value.toStringAsFixed(0),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 带图标的开关行。
class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      title: Text(label),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }
}

/// 内联 Stepper 行（紧凑型，用于子选项）。
class _StepperInline extends StatelessWidget {
  final String label;
  final int value;
  final int minValue;
  final int maxValue;
  final ValueChanged<int> onChanged;

  const _StepperInline({
    required this.label,
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          iconSize: 18,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: const Icon(Icons.remove, size: 16),
          onPressed: value > minValue ? () => onChanged(value - 1) : null,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('$value',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
        ),
        IconButton(
          iconSize: 18,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: const Icon(Icons.add, size: 16),
          onPressed: value < maxValue ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}
