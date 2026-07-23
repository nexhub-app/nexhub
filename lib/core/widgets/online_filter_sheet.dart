/// 在线列表筛选 Sheet（Phase 1.2 #7 A4-#7）。
///
/// 提供年份/地区/排序/状态四字段筛选 UI，应用后通过 [onApply] 回调
/// 透传到 `fetchApiResults` 的 `vars`。源不支持的字段会被 resolver 忽略，
/// 向后兼容。
library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../models/plugin_config.dart';
import '../theme/app_tokens.dart';

/// 筛选条件（所有字段可选，null 表示不限定）。
class OnlineFilter {
  const OnlineFilter({
    this.years = const <String>[],
    this.regions = const <String>[],
    this.sort,
    this.status,
  });

  /// 年份多选（如 ['2024', '2023']）。
  final List<String> years;

  /// 地区多选（如 ['中国大陆', '日本']）。
  final List<String> regions;

  /// 排序单选（如 'latest' / 'hottest' / 'rating'）。
  final String? sort;

  /// 状态单选（如 'ongoing' / 'completed'）。
  final String? status;

  /// 转为 `vars` Map 透传给 `fetchApiResults`。
  ///
  /// 多选字段用逗号拼接，单选字段直接透传。空列表/ null 不加入。
  Map<String, String> toVars() {
    final map = <String, String>{};
    if (years.isNotEmpty) map['year'] = years.join(',');
    if (regions.isNotEmpty) map['region'] = regions.join(',');
    if (sort != null && sort!.isNotEmpty) map['sort'] = sort!;
    if (status != null && status!.isNotEmpty) map['status'] = status!;
    return map;
  }

  /// 是否为空（无任何筛选条件）。
  bool get isEmpty =>
      years.isEmpty && regions.isEmpty && sort == null && status == null;

  OnlineFilter copyWith({
    List<String>? years,
    List<String>? regions,
    String? sort,
    String? status,
  }) =>
      OnlineFilter(
        years: years ?? this.years,
        regions: regions ?? this.regions,
        sort: sort ?? this.sort,
        status: status ?? this.status,
      );
}

/// 筛选 Sheet 配置（动态字段显示）。
class OnlineFilterConfig {
  const OnlineFilterConfig({
    this.showYear = true,
    this.showRegion = true,
    this.showSort = true,
    this.showStatus = true,
    this.yearOptions = const <String>[
      '2025', '2024', '2023', '2022', '2021',
      '2020', '2019', '2018', '2017', '2016',
      '2015', '2014', '2013', '2012', '2011',
      '2010', '2009', '2008', '2007', '2006',
      '2005', '2004', '2003', '2002', '2001',
      '2000',
    ],
    this.regionOptions = const <FilterRegionOption>[
      FilterRegionOption(value: '中国大陆', labelKey: 'china'),
      FilterRegionOption(value: '中国香港', labelKey: 'hongKong'),
      FilterRegionOption(value: '中国台湾', labelKey: 'taiwan'),
      FilterRegionOption(value: '日本', labelKey: 'japan'),
      FilterRegionOption(value: '韩国', labelKey: 'korea'),
      FilterRegionOption(value: '美国', labelKey: 'usa'),
      FilterRegionOption(value: '其他', labelKey: 'other'),
    ],
    this.sortOptions = const <FilterSortOption>[
      FilterSortOption(value: 'latest', labelKey: 'latest'),
      FilterSortOption(value: 'hottest', labelKey: 'hottest'),
      FilterSortOption(value: 'rating', labelKey: 'rating'),
    ],
    this.statusOptions = const <FilterStatusOption>[
      FilterStatusOption(value: 'ongoing', labelKey: 'ongoing'),
      FilterStatusOption(value: 'completed', labelKey: 'completed'),
    ],
  });

  /// 是否显示年份筛选（源不支持可关闭）。
  final bool showYear;

  /// 是否显示地区筛选。
  final bool showRegion;

  /// 是否显示排序筛选。
  final bool showSort;

  /// 是否显示状态筛选。
  final bool showStatus;

  /// 年份候选列表（多选）。
  final List<String> yearOptions;

  /// 地区候选列表（多选）。value 为透传给源 API 的原始字符串，labelKey 用于 l10n 显示。
  final List<FilterRegionOption> regionOptions;

  /// 排序候选列表（单选）。
  final List<FilterSortOption> sortOptions;

  /// 状态候选列表（单选）。
  final List<FilterStatusOption> statusOptions;
}

/// 地区候选项（value 透传给源 API，labelKey 用于 l10n 翻译）。
class FilterRegionOption {
  const FilterRegionOption({required this.value, required this.labelKey});
  final String value;
  final String labelKey;
}

/// 排序候选项（value + labelKey 用于 l10n 翻译）。
class FilterSortOption {
  const FilterSortOption({required this.value, required this.labelKey});
  final String value;
  final String labelKey;
}

/// 状态候选项（value + labelKey 用于 l10n 翻译）。
class FilterStatusOption {
  const FilterStatusOption({required this.value, required this.labelKey});
  final String value;
  final String labelKey;
}

/// 以 modal bottom sheet 形式展示筛选 Sheet。
///
/// [config] 控制字段动态显示；[initial] 为初始筛选条件；[onApply] 为
/// 用户点击"应用"后的回调（透传 `vars` 给 fetchApiResults）。
Future<void> showOnlineFilterSheet(
  BuildContext context, {
  OnlineFilterConfig config = const OnlineFilterConfig(),
  OnlineFilter initial = const OnlineFilter(),
  required ValueChanged<OnlineFilter> onApply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTokens.radiusLg),
      ),
    ),
    builder: (ctx) => _OnlineFilterSheet(
      config: config,
      initial: initial,
      onApply: onApply,
    ),
  );
}

class _OnlineFilterSheet extends StatefulWidget {
  const _OnlineFilterSheet({
    required this.config,
    required this.initial,
    required this.onApply,
  });

  final OnlineFilterConfig config;
  final OnlineFilter initial;
  final ValueChanged<OnlineFilter> onApply;

  @override
  State<_OnlineFilterSheet> createState() => _OnlineFilterSheetState();
}

class _OnlineFilterSheetState extends State<_OnlineFilterSheet> {
  late List<String> _years;
  late List<String> _regions;
  late String? _sort;
  late String? _status;

  @override
  void initState() {
    super.initState();
    _years = List<String>.from(widget.initial.years);
    _regions = List<String>.from(widget.initial.regions);
    _sort = widget.initial.sort;
    _status = widget.initial.status;
  }

  void _toggleYear(String y) {
    setState(() {
      if (_years.contains(y)) {
        _years.remove(y);
      } else {
        _years.add(y);
      }
    });
  }

  void _toggleRegion(String r) {
    setState(() {
      if (_regions.contains(r)) {
        _regions.remove(r);
      } else {
        _regions.add(r);
      }
    });
  }

  void _reset() {
    setState(() {
      _years.clear();
      _regions.clear();
      _sort = null;
      _status = null;
    });
  }

  void _apply() {
    widget.onApply(OnlineFilter(
      years: _years,
      regions: _regions,
      sort: _sort,
      status: _status,
    ));
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTokens.spaceLg,
          right: AppTokens.spaceLg,
          top: AppTokens.spaceMd,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTokens.spaceMd,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 标题栏
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    l10n.filterTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const Divider(),

              // 年份（多选）
              if (widget.config.showYear) ...<Widget>[
                _sectionLabel(l10n.filterYear, theme),
                _wrapChips(
                  items: widget.config.yearOptions,
                  selected: _years,
                  onToggle: _toggleYear,
                ),
                const SizedBox(height: AppTokens.spaceMd),
              ],

              // 地区（多选）
              if (widget.config.showRegion) ...<Widget>[
                _sectionLabel(l10n.filterRegion, theme),
                _wrapLabeledChips(
                  items: widget.config.regionOptions
                      .map((e) => _LabeledValue(value: e.value, label: _regionLabel(l10n, e.labelKey)))
                      .toList(),
                  selected: _regions,
                  onToggle: _toggleRegion,
                ),
                const SizedBox(height: AppTokens.spaceMd),
              ],

              // 排序（单选）
              if (widget.config.showSort) ...<Widget>[
                _sectionLabel(l10n.filterSort, theme),
                _wrapRadioChips(
                  items: widget.config.sortOptions
                      .map((e) => _LabeledValue(value: e.value, label: _sortLabel(l10n, e.labelKey)))
                      .toList(),
                  selected: _sort,
                  onSelect: (v) => setState(() => _sort = v),
                ),
                const SizedBox(height: AppTokens.spaceMd),
              ],

              // 状态（单选）
              if (widget.config.showStatus) ...<Widget>[
                _sectionLabel(l10n.filterByStatus, theme),
                _wrapRadioChips(
                  items: widget.config.statusOptions
                      .map((e) => _LabeledValue(value: e.value, label: _statusLabel(l10n, e.labelKey)))
                      .toList(),
                  selected: _status,
                  onSelect: (v) => setState(() => _status = v),
                ),
                const SizedBox(height: AppTokens.spaceMd),
              ],

              // 底部按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  TextButton(
                    onPressed: _reset,
                    child: Text(l10n.filterReset),
                  ),
                  FilledButton(
                    onPressed: _apply,
                    child: Text(l10n.filterApply),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceXs),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _wrapChips({
    required List<String> items,
    required List<String> selected,
    required ValueChanged<String> onToggle,
  }) {
    return Wrap(
      spacing: AppTokens.spaceXs,
      runSpacing: AppTokens.spaceXs,
      children: items.map((it) {
        final isSel = selected.contains(it);
        return ChoiceChip(
          label: Text(it),
          selected: isSel,
          onSelected: (_) => onToggle(it),
        );
      }).toList(),
    );
  }

  Widget _wrapLabeledChips({
    required List<_LabeledValue> items,
    required List<String> selected,
    required ValueChanged<String> onToggle,
  }) {
    return Wrap(
      spacing: AppTokens.spaceXs,
      runSpacing: AppTokens.spaceXs,
      children: items.map((it) {
        final isSel = selected.contains(it.value);
        return ChoiceChip(
          label: Text(it.label),
          selected: isSel,
          onSelected: (_) => onToggle(it.value),
        );
      }).toList(),
    );
  }

  Widget _wrapRadioChips({
    required List<_LabeledValue> items,
    required String? selected,
    required ValueChanged<String> onSelect,
  }) {
    return Wrap(
      spacing: AppTokens.spaceXs,
      runSpacing: AppTokens.spaceXs,
      children: items.map((it) {
        final isSel = selected == it.value;
        return ChoiceChip(
          label: Text(it.label),
          selected: isSel,
          onSelected: (_) => onSelect(it.value),
        );
      }).toList(),
    );
  }

  String _sortLabel(AppLocalizations l10n, String key) {
    return switch (key) {
      'latest' => l10n.sortRecent,
      'hottest' => l10n.sortHottest,
      'rating' => l10n.sortRating,
      _ => key,
    };
  }

  String _regionLabel(AppLocalizations l10n, String key) {
    return switch (key) {
      'china' => l10n.regionChina,
      'hongKong' => l10n.regionHongKong,
      'taiwan' => l10n.regionTaiwan,
      'japan' => l10n.regionJapan,
      'korea' => l10n.regionKorea,
      'usa' => l10n.regionUSA,
      'other' => l10n.regionOther,
      _ => key,
    };
  }

  String _statusLabel(AppLocalizations l10n, String key) {
    return switch (key) {
      'ongoing' => l10n.statusOngoing,
      'completed' => l10n.statusCompleted,
      _ => key,
    };
  }
}

class _LabeledValue {
  const _LabeledValue({required this.value, required this.label});
  final String value;
  final String label;
}

// ============================================================================
// 动态筛选（共创式：筛选维度完全由源 [FilterGroupConfig] 声明或兜底生成）
//
// 修复旧版「筛选按钮写死年份/地区/排序/状态」：改为按源提供的分组动态渲染。
// 旧的 [OnlineFilter] / [showOnlineFilterSheet] 保留向后兼容，新代码用下列 API。
// ============================================================================

/// 单个已选筛选项（携带其所属分组 id、路由占位符 param 与选项值）。
class DynamicFilterSelection {
  const DynamicFilterSelection({
    required this.groupId,
    required this.param,
    required this.value,
  });

  /// 所属分组 [FilterGroupConfig.id]（用于 UI 回显选中态）。
  final String groupId;

  /// 该值代入的路由占位符名（如 `category` / `keyword`）。
  final String param;

  /// 选项值（透传给源路由 URL 占位符）。
  final String value;
}

/// 动态筛选条件。
///
/// [route] 为筛选触发的路由覆盖（如 baozimh 的 `tagSearch`）；为 null 表示
/// 沿用分类 Tab 默认路由。[selections] 为已选项集合（跨路由互斥，故同一时刻
/// 所有已选项共享同一 [route]）。
class DynamicOnlineFilter {
  const DynamicOnlineFilter({
    this.route,
    this.selections = const <DynamicFilterSelection>[],
  });

  final String? route;
  final List<DynamicFilterSelection> selections;

  bool get isEmpty => selections.isEmpty;

  /// 转为 `vars` 透传给 `fetchApiResults`。
  ///
  /// 同 param 的多个值用逗号拼接；[route] 非空时写入特殊键 `__route`
  /// 触发 [MediaApiService.fetchApiResults] 的路由覆盖钩子。
  Map<String, String> toVars() {
    final map = <String, String>{};
    for (final s in selections) {
      final existing = map[s.param];
      map[s.param] = existing == null ? s.value : '$existing,${s.value}';
    }
    if (route != null && route!.isNotEmpty) map['__route'] = route!;
    return map;
  }
}

/// 以 modal bottom sheet 形式展示「动态筛选」Sheet。
///
/// [groups] 为源声明或兜底生成的筛选分组；[initial] 为初始条件；
/// [onApply] 为用户点击「应用」后的回调。当 [groups] 为空时不应调用本函数
/// （调用方应改为不显示筛选按钮）。
Future<void> showDynamicFilterSheet(
  BuildContext context, {
  required List<FilterGroupConfig> groups,
  DynamicOnlineFilter initial = const DynamicOnlineFilter(),
  required ValueChanged<DynamicOnlineFilter> onApply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTokens.radiusLg),
      ),
    ),
    builder: (ctx) => _DynamicFilterSheet(
      groups: groups,
      initial: initial,
      onApply: onApply,
    ),
  );
}

class _DynamicFilterSheet extends StatefulWidget {
  const _DynamicFilterSheet({
    required this.groups,
    required this.initial,
    required this.onApply,
  });

  final List<FilterGroupConfig> groups;
  final DynamicOnlineFilter initial;
  final ValueChanged<DynamicOnlineFilter> onApply;

  @override
  State<_DynamicFilterSheet> createState() => _DynamicFilterSheetState();
}

class _DynamicFilterSheetState extends State<_DynamicFilterSheet> {
  late List<DynamicFilterSelection> _selected;
  String? _activeRoute;

  @override
  void initState() {
    super.initState();
    _selected = List<DynamicFilterSelection>.from(widget.initial.selections);
    _activeRoute = widget.initial.route;
  }

  /// 分组的有效路由（分组自声明优先，缺省回退 `category`）。
  String _routeOf(FilterGroupConfig g) =>
      (g.route != null && g.route!.isNotEmpty) ? g.route! : 'category';

  bool _isSelected(FilterGroupConfig g, String value) =>
      _selected.any((s) => s.groupId == g.id && s.value == value);

  void _toggle(FilterGroupConfig g, String value) {
    final route = _routeOf(g);
    setState(() {
      // 跨路由互斥：切到不同路由的分组时，清空原路由下的所有已选项。
      if (_activeRoute != null && _activeRoute != route) {
        _selected.clear();
      }
      _activeRoute = route;

      final existingIdx =
          _selected.indexWhere((s) => s.groupId == g.id && s.value == value);
      if (existingIdx >= 0) {
        _selected.removeAt(existingIdx);
        if (_selected.isEmpty) _activeRoute = null;
        return;
      }
      // 单选分组：先移除同组其他已选项，再加入新值。
      if (!g.multiSelect) {
        _selected.removeWhere((s) => s.groupId == g.id);
      }
      _selected.add(DynamicFilterSelection(
        groupId: g.id,
        param: g.param,
        value: value,
      ));
    });
  }

  void _reset() {
    setState(() {
      _selected.clear();
      _activeRoute = null;
    });
  }

  void _apply() {
    widget.onApply(DynamicOnlineFilter(
      route: _activeRoute,
      selections: List<DynamicFilterSelection>.from(_selected),
    ));
    Navigator.of(context).maybePop();
  }

  /// 分组标题：源声明的 title 优先；缺省按 id 映射到 l10n（避免 Dart 硬编码中文）。
  String _groupTitle(AppLocalizations l10n, FilterGroupConfig g) {
    if (g.title.isNotEmpty) return g.title;
    return switch (g.id) {
      'category' => l10n.filterCategory,
      'tag' => l10n.filterTag,
      'region' => l10n.filterRegion,
      'year' => l10n.filterYear,
      'sort' => l10n.filterSort,
      'status' => l10n.filterByStatus,
      _ => g.id,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTokens.spaceLg,
          right: AppTokens.spaceLg,
          top: AppTokens.spaceMd,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppTokens.spaceMd,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 标题栏
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(l10n.filterTitle, style: theme.textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const Divider(),

              // 动态分组
              for (final g in widget.groups)
                if (g.options.isNotEmpty) ...<Widget>[
                  _sectionLabel(_groupTitle(l10n, g), theme),
                  Wrap(
                    spacing: AppTokens.spaceXs,
                    runSpacing: AppTokens.spaceXs,
                    children: g.options.map((opt) {
                      return ChoiceChip(
                        label: Text(opt.label),
                        selected: _isSelected(g, opt.value),
                        onSelected: (_) => _toggle(g, opt.value),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                ],

              // 底部按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  TextButton(
                    onPressed: _reset,
                    child: Text(l10n.filterReset),
                  ),
                  FilledButton(
                    onPressed: _apply,
                    child: Text(l10n.filterApply),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceXs),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
