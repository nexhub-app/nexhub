/// 小说翻页动画枚举（文档 8.1，6 种效果）。
///
/// - [none] — 无动画（jumpToPage）。
/// - [slide] — PageView 默认滑动（双页同步、无阴影）。
/// - [scroll] — 垂直 ListView 连续滚动。
/// - [fade] — 纯 Opacity 交叉淡入（450ms）。
/// - [cover] — 旧页滑出 + 新页 ClipRect 显露 + 40px 渐变阴影。
/// - [simulation] — 贝塞尔 ClipPath 卷页（跟手）。
library;

/// 翻页动画类型。
enum NovelPageAnimation {
  none,
  slide,
  scroll,
  fade,
  cover,
  simulation;

  /// 从字符串解析（容错，默认 [slide]）。
  static NovelPageAnimation fromString(String? raw) {
    return switch (raw) {
      'none' => none,
      'slide' => slide,
      'scroll' => scroll,
      'fade' => fade,
      'cover' => cover,
      'simulation' => simulation,
      _ => slide,
    };
  }

  /// 是否为连续滚动模式（不使用分页 PageView）。
  bool get isScroll => this == scroll;

  /// 是否使用 PageView（分页翻页）。
  bool get isPaged => this != scroll;

  /// l10n 键。
  String l10nKey() => switch (this) {
        NovelPageAnimation.none => 'novelAnimNone',
        NovelPageAnimation.slide => 'novelAnimSlide',
        NovelPageAnimation.scroll => 'novelAnimScroll',
        NovelPageAnimation.fade => 'novelAnimFade',
        NovelPageAnimation.cover => 'novelAnimCover',
        NovelPageAnimation.simulation => 'novelAnimSimulation',
      };
}
