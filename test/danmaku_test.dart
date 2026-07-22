import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/widgets/danmaku.dart';

void main() {
  group('DanmakuController', () {
    test('pending returns items at or before position, once', () {
      final items = <DanmakuItem>[
        DanmakuItem(text: 'a', time: const Duration(seconds: 1)),
        DanmakuItem(text: 'b', time: const Duration(seconds: 3)),
        DanmakuItem(text: 'c', time: const Duration(seconds: 5)),
      ];
      final ctrl = DanmakuController(items);

      expect(ctrl.pending(const Duration(seconds: 2)), hasLength(1));
      // 同一位置再次调用不会重复给出已展示的弹幕
      expect(ctrl.pending(const Duration(seconds: 2)), isEmpty);
      // 推进时间后给出剩余弹幕
      expect(ctrl.pending(const Duration(seconds: 6)), hasLength(2));
      expect(ctrl.pending(const Duration(seconds: 6)), isEmpty);
    });

    test('reset clears shown state', () {
      final items = <DanmakuItem>[
        DanmakuItem(text: 'a', time: const Duration(seconds: 1)),
      ];
      final ctrl = DanmakuController(items);
      expect(ctrl.pending(const Duration(seconds: 2)), hasLength(1));
      ctrl.reset();
      expect(ctrl.pending(const Duration(seconds: 2)), hasLength(1));
    });

    test('demo produces requested count', () {
      final demo = DanmakuController.demo(10);
      expect(demo, hasLength(10));
      expect(demo.first.time, const Duration(seconds: 0));
      expect(demo[1].time, const Duration(seconds: 2));
    });
  });
}
