import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nexhub/core/comic/models/reader_preferences.dart';
import 'package:nexhub/core/reader/tap_zone_resolver.dart';

/// 测试辅助：以相对坐标 (fx, fy) 0..1 命中 1000x1000 阅读区。
TapZoneAction resolveAt({
  required ReaderTapZoneLayout layout,
  required TapZoneInvert invert,
  required bool isVertical,
  required double fx,
  required double fy,
  Size size = const Size(1000, 1000),
}) {
  return TapZoneResolver.resolve(
    layout: layout,
    invert: invert,
    isVertical: isVertical,
    pos: Offset(fx * size.width, fy * size.height),
    size: size,
  );
}

void main() {
  group('leftRight', () {
    // 左 45% prev / 中 10% toggle / 右 45% next（原 defaultLayout 几何）
    test('left third -> prev', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.1,
          fy: 0.5,
        ),
        TapZoneAction.prev,
      );
    });

    test('middle third -> toggle', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.5,
          fy: 0.5,
        ),
        TapZoneAction.toggle,
      );
    });

    test('right third -> next', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.9,
          fy: 0.5,
        ),
        TapZoneAction.next,
      );
    });

    test('leftRight + horizontal swaps prev/next', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.leftRight,
          isVertical: false,
          fx: 0.1,
          fy: 0.5,
        ),
        TapZoneAction.next,
      );
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.leftRight,
          isVertical: false,
          fx: 0.9,
          fy: 0.5,
        ),
        TapZoneAction.prev,
      );
    });

    test('leftRight + horizontal keeps toggle at center', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.leftRight,
          isVertical: false,
          fx: 0.5,
          fy: 0.5,
        ),
        TapZoneAction.toggle,
      );
    });

    test('all invert swaps prev/next', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.all,
          isVertical: false,
          fx: 0.1,
          fy: 0.5,
        ),
        TapZoneAction.next,
      );
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.all,
          isVertical: false,
          fx: 0.9,
          fy: 0.5,
        ),
        TapZoneAction.prev,
      );
    });
  });

  group('lShape', () {
    // 左列 + 下中条 = prev（L 形）；右列 + 上中条 = next（镜像 L）；
    // 中心方块 = toggle。
    test('left-top -> prev', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.lShape,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.25,
          fy: 0.25,
        ),
        TapZoneAction.prev,
      );
    });

    test('right-bottom -> next', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.lShape,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.75,
          fy: 0.75,
        ),
        TapZoneAction.next,
      );
    });

    // 上中条属于 next（镜像 L 的上臂）。
    test('right-top -> next', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.lShape,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.75,
          fy: 0.25,
        ),
        TapZoneAction.next,
      );
    });

    // 下中条属于 prev（L 的下臂）。
    test('left-bottom -> prev', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.lShape,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.25,
          fy: 0.75,
        ),
        TapZoneAction.prev,
      );
    });

    test('center -> toggle', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.lShape,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.5,
          fy: 0.5,
        ),
        TapZoneAction.toggle,
      );
    });

    test('top-center strip -> next', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.lShape,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.5,
          fy: 0.1,
        ),
        TapZoneAction.next,
      );
    });

    test('bottom-center strip -> prev', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.lShape,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.5,
          fy: 0.9,
        ),
        TapZoneAction.prev,
      );
    });
  });

  group('kindle', () {
    // 上 15% toggle / 左 35% prev / 右 65% next
    test('top 15% -> toggle', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.kindle,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.5,
          fy: 0.05,
        ),
        TapZoneAction.toggle,
      );
    });

    test('left 35% -> prev', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.kindle,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.1,
          fy: 0.5,
        ),
        TapZoneAction.prev,
      );
    });

    test('right 65% -> next', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.kindle,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.5,
          fy: 0.5,
        ),
        TapZoneAction.next,
      );
    });
  });

  group('bothSides', () {
    // 左中 next / 右中 next / 下 prev / 上 toggle
    test('left-middle -> next', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.bothSides,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.1,
          fy: 0.5,
        ),
        TapZoneAction.next,
      );
    });

    test('right-middle -> next', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.bothSides,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.9,
          fy: 0.5,
        ),
        TapZoneAction.next,
      );
    });

    test('bottom -> prev', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.bothSides,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.5,
          fy: 0.9,
        ),
        TapZoneAction.prev,
      );
    });

    test('top -> toggle', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.bothSides,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.5,
          fy: 0.05,
        ),
        TapZoneAction.toggle,
      );
    });
  });

  group('off', () {
    // 整屏 toggle
    test('any tap -> toggle', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.off,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.5,
          fy: 0.5,
        ),
        TapZoneAction.toggle,
      );
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.off,
          invert: TapZoneInvert.all,
          isVertical: true,
          fx: 0.01,
          fy: 0.99,
        ),
        TapZoneAction.toggle,
      );
    });
  });

  group('invert rules', () {
    // 使用 leftRight 验证反转规则：左 45% = prev，右 45% = next。
    test('none + horizontal: no inversion', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.1,
          fy: 0.5,
        ),
        TapZoneAction.prev,
      );
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.none,
          isVertical: false,
          fx: 0.9,
          fy: 0.5,
        ),
        TapZoneAction.next,
      );
    });

    test('leftRight + horizontal: inverted', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.leftRight,
          isVertical: false,
          fx: 0.1,
          fy: 0.5,
        ),
        TapZoneAction.next,
      );
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.leftRight,
          isVertical: false,
          fx: 0.9,
          fy: 0.5,
        ),
        TapZoneAction.prev,
      );
    });

    test('leftRight + vertical: no inversion', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.leftRight,
          isVertical: true,
          fx: 0.1,
          fy: 0.5,
        ),
        TapZoneAction.prev,
      );
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.leftRight,
          isVertical: true,
          fx: 0.9,
          fy: 0.5,
        ),
        TapZoneAction.next,
      );
    });

    test('upDown + horizontal: no inversion', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.upDown,
          isVertical: false,
          fx: 0.1,
          fy: 0.5,
        ),
        TapZoneAction.prev,
      );
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.upDown,
          isVertical: false,
          fx: 0.9,
          fy: 0.5,
        ),
        TapZoneAction.next,
      );
    });

    test('upDown + vertical: inverted', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.upDown,
          isVertical: true,
          fx: 0.1,
          fy: 0.5,
        ),
        TapZoneAction.next,
      );
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.upDown,
          isVertical: true,
          fx: 0.9,
          fy: 0.5,
        ),
        TapZoneAction.prev,
      );
    });

    test('all: always inverted (horizontal)', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.all,
          isVertical: false,
          fx: 0.1,
          fy: 0.5,
        ),
        TapZoneAction.next,
      );
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.all,
          isVertical: false,
          fx: 0.9,
          fy: 0.5,
        ),
        TapZoneAction.prev,
      );
    });

    test('all: always inverted (vertical)', () {
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.all,
          isVertical: true,
          fx: 0.1,
          fy: 0.5,
        ),
        TapZoneAction.next,
      );
      expect(
        resolveAt(
          layout: ReaderTapZoneLayout.leftRight,
          invert: TapZoneInvert.all,
          isVertical: true,
          fx: 0.9,
          fy: 0.5,
        ),
        TapZoneAction.prev,
      );
    });

    test('toggle is never inverted', () {
      // 中 1/3 在任何反转设置下都返回 toggle。
      for (final invert in TapZoneInvert.values) {
        for (final isVertical in [false, true]) {
          expect(
            resolveAt(
              layout: ReaderTapZoneLayout.leftRight,
              invert: invert,
              isVertical: isVertical,
              fx: 0.5,
              fy: 0.5,
            ),
            TapZoneAction.toggle,
            reason: 'invert=$invert, isVertical=$isVertical',
          );
        }
      }
    });
  });
}
