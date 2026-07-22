/// 布局设置数据模型（项 3：网格/列表布局类型 + 列数/间距/圆角/字号/显隐项）。
///
/// 持久化到 SharedPreferences（key: `layout_settings_v2`），
/// 复用 [PrefsBackend] 抽象以便测试注入。
///
/// 若旧 key `layout_settings_v1` 存在，则迁移为 v2（保留既有用户偏好）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../comic/models/reader_preferences.dart';

/// 网格布局尺寸（大/中/小）。
enum GridLayoutSize { large, medium, small }

/// 列表布局风格（舒适/紧凑）。
enum ListLayoutStyle { comfortable, compact }

/// 顶层布局模式（网格/列表）。
///
/// 项 3 的 5 选 1 SegmentedButton 需要区分「前 3 项归 GridLayoutSize」与
/// 「后 2 项归 ListLayoutStyle」，因此引入此模式字段以消除选中态歧义。
enum LayoutMode { grid, list }

/// 进度显示方式（布局设置 → 显示选项）。
///
/// 与 [LayoutSettings.showProgress] 配合：showProgress 为总开关，
/// progressDisplay 决定「已读/已看」进度以[进度条]还是[百分比文字徽标]呈现
/// （二选一，避免两者同时显示）。
enum ProgressDisplayMode { bar, text }

/// 布局设置（项 3 新增字段）。
///
/// 既有 [BookshelfLayoutPreferences]（书架网格/列表模式 + 密度）保持独立，
/// 本类承载浏览/已下载/书架页共用的细粒度布局参数。
class LayoutSettings {
  final LayoutMode layoutMode;
  final GridLayoutSize gridLayoutSize;
  final ListLayoutStyle listStyle;
  final int gridColumns;
  final double gridSpacing;
  final double coverRadius;
  final double titleFontSize;
  final bool showTitle;
  final int titleMaxLines;
  final bool showAuthor;
  final bool showProgress;
  final ProgressDisplayMode progressDisplay;

  const LayoutSettings({
    this.layoutMode = LayoutMode.grid,
    this.gridLayoutSize = GridLayoutSize.medium,
    this.listStyle = ListLayoutStyle.comfortable,
    this.gridColumns = 3,
    this.gridSpacing = 8,
    this.coverRadius = 6,
    this.titleFontSize = 14,
    this.showTitle = true,
    this.titleMaxLines = 2,
    this.showAuthor = true,
    this.showProgress = true,
    this.progressDisplay = ProgressDisplayMode.bar,
  });

  LayoutSettings copyWith({
    LayoutMode? layoutMode,
    GridLayoutSize? gridLayoutSize,
    ListLayoutStyle? listStyle,
    int? gridColumns,
    double? gridSpacing,
    double? coverRadius,
    double? titleFontSize,
    bool? showTitle,
    int? titleMaxLines,
    bool? showAuthor,
    bool? showProgress,
    ProgressDisplayMode? progressDisplay,
  }) =>
      LayoutSettings(
        layoutMode: layoutMode ?? this.layoutMode,
        gridLayoutSize: gridLayoutSize ?? this.gridLayoutSize,
        listStyle: listStyle ?? this.listStyle,
        gridColumns: gridColumns ?? this.gridColumns,
        gridSpacing: gridSpacing ?? this.gridSpacing,
        coverRadius: coverRadius ?? this.coverRadius,
        titleFontSize: titleFontSize ?? this.titleFontSize,
        showTitle: showTitle ?? this.showTitle,
        titleMaxLines: titleMaxLines ?? this.titleMaxLines,
        showAuthor: showAuthor ?? this.showAuthor,
        showProgress: showProgress ?? this.showProgress,
        progressDisplay: progressDisplay ?? this.progressDisplay,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'layoutMode': layoutMode.name,
        'gridLayoutSize': gridLayoutSize.name,
        'listStyle': listStyle.name,
        'gridColumns': gridColumns,
        'gridSpacing': gridSpacing,
        'coverRadius': coverRadius,
        'titleFontSize': titleFontSize,
        'showTitle': showTitle,
        'titleMaxLines': titleMaxLines,
        'showAuthor': showAuthor,
        'showProgress': showProgress,
        'progressDisplay': progressDisplay.name,
      };

  factory LayoutSettings.fromJson(Map<String, dynamic> json) {
    LayoutMode layoutMode = LayoutMode.grid;
    if (json['layoutMode'] is String) {
      layoutMode = LayoutMode.values.firstWhere(
        (e) => e.name == json['layoutMode'],
        orElse: () => LayoutMode.grid,
      );
    }
    GridLayoutSize gridLayoutSize = GridLayoutSize.medium;
    if (json['gridLayoutSize'] is String) {
      gridLayoutSize = GridLayoutSize.values.firstWhere(
        (e) => e.name == json['gridLayoutSize'],
        orElse: () => GridLayoutSize.medium,
      );
    }
    ListLayoutStyle listStyle = ListLayoutStyle.comfortable;
    if (json['listStyle'] is String) {
      listStyle = ListLayoutStyle.values.firstWhere(
        (e) => e.name == json['listStyle'],
        orElse: () => ListLayoutStyle.comfortable,
      );
    }
    ProgressDisplayMode progressDisplay = ProgressDisplayMode.bar;
    if (json['progressDisplay'] is String) {
      progressDisplay = ProgressDisplayMode.values.firstWhere(
        (e) => e.name == json['progressDisplay'],
        orElse: () => ProgressDisplayMode.bar,
      );
    }
    return LayoutSettings(
      layoutMode: layoutMode,
      gridLayoutSize: gridLayoutSize,
      listStyle: listStyle,
      gridColumns: (json['gridColumns'] as num?)?.toInt() ?? 3,
      gridSpacing: (json['gridSpacing'] as num?)?.toDouble() ?? 8,
      coverRadius: (json['coverRadius'] as num?)?.toDouble() ?? 6,
      titleFontSize: (json['titleFontSize'] as num?)?.toDouble() ?? 14,
      showTitle: json['showTitle'] as bool? ?? true,
      titleMaxLines: (json['titleMaxLines'] as num?)?.toInt() ?? 2,
      showAuthor: json['showAuthor'] as bool? ?? true,
      showProgress: json['showProgress'] as bool? ?? true,
      progressDisplay: progressDisplay,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutSettings &&
          runtimeType == other.runtimeType &&
          layoutMode == other.layoutMode &&
          gridLayoutSize == other.gridLayoutSize &&
          listStyle == other.listStyle &&
          gridColumns == other.gridColumns &&
          gridSpacing == other.gridSpacing &&
          coverRadius == other.coverRadius &&
          titleFontSize == other.titleFontSize &&
          showTitle == other.showTitle &&
          titleMaxLines == other.titleMaxLines &&
          showAuthor == other.showAuthor &&
          showProgress == other.showProgress &&
          progressDisplay == other.progressDisplay;

  @override
  int get hashCode => Object.hash(
        layoutMode,
        gridLayoutSize,
        listStyle,
        gridColumns,
        gridSpacing,
        coverRadius,
        titleFontSize,
        showTitle,
        titleMaxLines,
        showAuthor,
        showProgress,
        progressDisplay,
      );
}

/// 布局设置持久化存储 + 变更广播（key: `layout_settings_v2`）。
///
/// 继承 [ChangeNotifier] 以便设置页与布局快选按钮（项 4/11）共享同一实例，
/// 任何入口写入后调用 [notifyListeners]，订阅方即时重建。
class LayoutSettingsStore extends ChangeNotifier {
  static const String _key = 'layout_settings_v2';
  static const String _legacyKey = 'layout_settings_v1';

  final PrefsBackend _backend;
  LayoutSettings _settings = const LayoutSettings();
  bool _loaded = false;

  LayoutSettingsStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  /// 全局共享单例 —— 供设置页与布局快选按钮共用，保证状态同步。
  static LayoutSettingsStore? _instance;
  static LayoutSettingsStore get instance {
    _instance ??= LayoutSettingsStore();
    if (!_instance!._loaded) {
      _instance!.load();
    }
    return _instance!;
  }

  LayoutSettings get settings => _settings;
  bool get loaded => _loaded;

  Future<LayoutSettings> load() async {
    String? raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) {
      // 尝试从旧 key 迁移（保留既有用户偏好）。
      final String? legacy = await _backend.get(_legacyKey);
      if (legacy != null && legacy.isNotEmpty) {
        try {
          final migrated = LayoutSettings.fromJson(
            jsonDecode(legacy) as Map<String, dynamic>,
          );
          _settings = migrated;
          await _backend.set(_key, jsonEncode(migrated.toJson()));
        } on Object {
          _settings = const LayoutSettings();
        }
      } else {
        _settings = const LayoutSettings();
      }
    } else {
      try {
        _settings = LayoutSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } on Object {
        _settings = const LayoutSettings();
      }
    }
    _loaded = true;
    notifyListeners();
    return _settings;
  }

  Future<void> save(LayoutSettings settings) async {
    _settings = settings;
    await _backend.set(_key, jsonEncode(settings.toJson()));
    notifyListeners();
  }
}
