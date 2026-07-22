import 'package:canvas_danmaku/canvas_danmaku.dart' as cd;
import 'package:flutter/material.dart';

/// 单条弹幕（数据模型，与 canvas_danmaku 解耦）。
class DanmakuItem {
  DanmakuItem({
    required this.text,
    required this.time,
    Color? color,
    this.fontSize = 16,
  }) : color = color ?? Colors.white;

  final String text;

  /// 在视频时间轴上的出现时刻。
  final Duration time;
  final Color color;
  final double fontSize;
}

/// 弹幕控制器（基于 canvas_danmaku）。
///
/// 持有全部弹幕与已展示索引，按视频播放位置给出「此刻应出现」的弹幕。
/// 通过 [attach] 绑定 [cd.DanmakuController] 后，调用 [tick] 即可自动注入。
class DanmakuController {
  DanmakuController([List<DanmakuItem>? items]) {
    if (items != null) _items.addAll(items);
  }

  cd.DanmakuController? _controller;
  final List<DanmakuItem> _items = [];
  final Set<int> _shown = <int>{};

  /// 绑定 canvas_danmaku 控制器。
  void attach(cd.DanmakuController controller) => _controller = controller;

  /// 替换全部弹幕数据（清空旧的并重置展示索引）。
  void setItems(List<DanmakuItem> items) {
    _items
      ..clear()
      ..addAll(items);
    _shown.clear();
  }

  /// 更新弹幕选项（同步到 canvas_danmaku 控制器）。
  void setOption(cd.DanmakuOption option) {
    _controller?.updateOption(option);
  }

  /// 按视频位置注入弹幕到 canvas_danmaku 控制器。
  void tick(Duration position) {
    final pending = _pendingItems(position);
    for (final item in pending) {
      _controller?.addDanmaku(
        cd.DanmakuContentItem(
          item.text,
          color: item.color,
        ),
      );
    }
  }

  List<DanmakuItem> _pendingItems(Duration position) {
    final out = <DanmakuItem>[];
    for (var i = 0; i < _items.length; i++) {
      if (!_shown.contains(i) && _items[i].time <= position) {
        _shown.add(i);
        out.add(_items[i]);
      }
    }
    return out;
  }

  /// 返回播放位置 [position] 之前尚未展示的弹幕（向后兼容）。
  List<DanmakuItem> pending(Duration position) => _pendingItems(position);

  /// 清空屏幕上的弹幕。
  void clear() => _controller?.clear();

  /// 重置已展示索引（重新播放时调用）。
  void reset() => _shown.clear();

  /// 构造均匀分布的示例弹幕。
  static List<DanmakuItem> demo(int count,
      {Duration step = const Duration(seconds: 2)}) {
    const samples = <String>[
      'Exciting!',
      'Famous scene!',
      'Tears!',
      'Awesome frame!',
      'BGM plays!',
      'Spoiler alert!',
    ];
    return [
      for (var i = 0; i < count; i++)
        DanmakuItem(
          text: samples[i % samples.length],
          time: step * i,
        ),
    ];
  }
}
