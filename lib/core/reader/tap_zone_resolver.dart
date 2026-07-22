import 'package:flutter/material.dart';

import '../comic/models/reader_preferences.dart';

/// 点击热区触发的动作。
enum TapZoneAction { prev, next, toggle }

/// 点击分区解析器（文档 7.3 / FR-4.2）。
///
/// 纯函数：给定布局 [ReaderTapZoneLayout]、方向反转 [TapZoneInvert]、
/// 是否竖向滚动 [isVertical]，以及抬起坐标 [pos]（相对于阅读区）与阅读区
/// 尺寸 [size]，返回命中的动作。小说 / 漫画共用，避免在两处各写一份
/// 区域表。
///
/// 区域定义与漫画 [ReaderTapZones] 私有实现完全一致（lShape / leftRight /
/// kindle / bothSides / off 见文档；历史上 defaultLayout 的几何已并入 leftRight，
/// lShape 成为默认布局）。方向反转规则：
/// - 横向模式 + leftRight / all → 反转 prev / next
/// - 竖向模式 + upDown / all → 反转 prev / next（上下滚动方向反转）
/// - none → 不反转
class TapZoneResolver {
  TapZoneResolver._();

  /// 解析单次抬起的命中动作。
  static TapZoneAction resolve({
    required ReaderTapZoneLayout layout,
    required TapZoneInvert invert,
    required bool isVertical,
    required Offset pos,
    required Size size,
  }) {
    final action = _actionAt(layout, pos, size);
    if (action == TapZoneAction.toggle) return TapZoneAction.toggle;
    final bool shouldInvert = switch (invert) {
      TapZoneInvert.none => false,
      TapZoneInvert.leftRight => !isVertical,
      TapZoneInvert.upDown => isVertical,
      TapZoneInvert.all => true,
    };
    final bool isPrev = action == TapZoneAction.prev;
    final bool effectiveIsPrev = shouldInvert ? !isPrev : isPrev;
    return effectiveIsPrev ? TapZoneAction.prev : TapZoneAction.next;
  }

  static TapZoneAction _actionAt(
    ReaderTapZoneLayout layout,
    Offset p,
    Size s,
  ) {
    for (final r in _regions(layout)) {
      final rect = Rect.fromLTWH(
        r.left * s.width,
        r.top * s.height,
        r.width * s.width,
        r.height * s.height,
      );
      if (rect.contains(p)) return r.action;
    }
    return TapZoneAction.toggle;
  }

  static List<_Region> _regions(ReaderTapZoneLayout layout) {
    switch (layout) {
      case ReaderTapZoneLayout.leftRight:
        // 左右：左 45% prev / 右 45% next / 中间 10% toggle。
        return const <_Region>[
          _Region(0, 0, 0.45, 1, TapZoneAction.prev),
          _Region(0.45, 0, 0.1, 1, TapZoneAction.toggle),
          _Region(0.55, 0, 0.45, 1, TapZoneAction.next),
        ];
      case ReaderTapZoneLayout.lShape:
        // 两个 L 形 + 中心 toggle（与漫画 reader_tap_zones.dart 保持一致）：
        // prev = 左列 + 下中条；next = 右列 + 上中条；toggle = 中心方块。
        return const <_Region>[
          _Region(0, 0, 0.33, 1, TapZoneAction.prev), // 左列（全高）
          _Region(0.67, 0, 0.33, 1, TapZoneAction.next), // 右列（全高）
          _Region(0.33, 0, 0.34, 0.33, TapZoneAction.next), // 上中条
          _Region(0.33, 0.67, 0.34, 0.33, TapZoneAction.prev), // 下中条
          _Region(0.33, 0.33, 0.34, 0.34, TapZoneAction.toggle), // 中心
        ];
      case ReaderTapZoneLayout.kindle:
        return const <_Region>[
          _Region(0, 0, 1, 0.15, TapZoneAction.toggle),
          _Region(0, 0.15, 0.35, 0.85, TapZoneAction.prev),
          _Region(0.35, 0.15, 0.65, 0.85, TapZoneAction.next),
        ];
      case ReaderTapZoneLayout.bothSides:
        return const <_Region>[
          _Region(0, 0.15, 0.33, 0.7, TapZoneAction.next),
          _Region(0.67, 0.15, 0.33, 0.7, TapZoneAction.next),
          _Region(0.33, 0.7, 0.34, 0.3, TapZoneAction.prev),
          _Region(0.33, 0, 0.34, 0.15, TapZoneAction.toggle),
        ];
      case ReaderTapZoneLayout.off:
        return const <_Region>[_Region(0, 0, 1, 1, TapZoneAction.toggle)];
    }
  }
}

/// 单个点击热区（坐标为相对于阅读区的比例 0..1）。
class _Region {
  final double left;
  final double top;
  final double width;
  final double height;
  final TapZoneAction action;
  const _Region(this.left, this.top, this.width, this.height, this.action);
}
