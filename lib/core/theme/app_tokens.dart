import 'package:flutter/material.dart';

/// 统一设计 Token —— 应用中所有颜色、间距、圆角、阴影、时长的**唯一**来源。
///
/// 治理规则（见 docs/DESIGN_SYSTEM.md）：
/// - feature 代码**禁止**硬编码 `Color(0xFF…)`、`EdgeInsets.all(8)` 等魔法数字。
/// - 颜色统一取 `Theme.of(context).colorScheme`（由 seed 生成，深浅色自适应）。
/// - 间距 / 圆角 / 时长取本文件常量。
/// - 随深浅色变化的派生值（阴影、渐变）通过 [AppShadows] / [AppGradients] 取得。
class AppTokens {
  AppTokens._();

  // ─────────────────────── 语义色板（用于生成 ColorScheme / 强调色） ───────────────────────
  /// 保留预设：浅蓝（旧脚手架配色，可选；应用默认主色为 [seedYouthfulPrimary] #0EA5E9）。
  static const Color seedLightBlue = Color(0xFF5B9BD5);

  /// 文档「青春活力」预设主色：蓝青。
  static const Color seedYouthfulPrimary = Color(0xFF0EA5E9);

  /// 文档「青春活力」预设强调：珊瑚。
  static const Color seedYouthfulAccent = Color(0xFFF43F5E);

  /// 可选预设主色（设置页切换 / 自定义取色）。
  static const List<Color> presetSeeds = <Color>[
    seedLightBlue,
    seedYouthfulPrimary,
    Color(0xFF6750A4), // M3 默认紫
    Color(0xFF26A69A), // 青绿
    Color(0xFFEF6C00), // 橙
  ];

  // ─────────────────────── 间距（Spacing） ───────────────────────
  static const double spaceNone = 0;
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double space2xl = 32;
  static const double space3xl = 48;

  // ─────────────────────── 圆角（Radius） ───────────────────────
  static const double radiusNone = 0;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;
  static const double radiusFull = 999;

  // ─────────────────────── 时长（Durations） ───────────────────────
  static const Duration durFast = Duration(milliseconds: 150);
  static const Duration durBase = Duration(milliseconds: 250);
  /// 翻页动画统一 450ms（见文档附录 C）。
  static const Duration durPageTurn = Duration(milliseconds: 450);

  // ─────────────────────── 组件固定尺寸 ───────────────────────
  static const double coverAspectRatio = 0.7; // 封面宽高比（漫画/小说）
  static const double coverRadius = radiusMd;
  static const double iconButtonSize = 40;
  static const double tabBarHeight = 56;
  static const double bottomNavHeight = 80;

  // ─────────────────────── 响应式断点 ───────────────────────
  /// 桌面布局断点（≥ 此宽度使用 NavigationRail）。
  static const double desktopBreakpoint = 840;
}

/// 阴影 Token（随 ColorScheme 自适应，禁止写死颜色）。
class AppShadows {
  AppShadows._();

  /// 卡片阴影（轻）。
  static List<BoxShadow> card(ColorScheme scheme) => <BoxShadow>[
        BoxShadow(
          color: scheme.shadow.withValues(alpha: 0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// 封面阴影（中）。
  static List<BoxShadow> cover(ColorScheme scheme) => <BoxShadow>[
        BoxShadow(
          color: scheme.shadow.withValues(alpha: 0.18),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  /// 悬浮阴影（重）。
  static List<BoxShadow> elevated(ColorScheme scheme) => <BoxShadow>[
        BoxShadow(
          color: scheme.shadow.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];
}

/// 渐变 Token（随 ColorScheme 自适应）。
class AppGradients {
  AppGradients._();

  /// 表面渐变（顶部 surface → 底部 surfaceContainerHighest）。
  static LinearGradient surface(ColorScheme scheme) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          scheme.surface,
          scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        ],
      );

  /// Hero 渐变（primary → tertiary）。
  static LinearGradient hero(ColorScheme scheme) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[scheme.primary, scheme.tertiary],
      );
}
