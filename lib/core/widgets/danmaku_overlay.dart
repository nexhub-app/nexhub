import 'package:canvas_danmaku/canvas_danmaku.dart' as cd;
import 'package:flutter/material.dart';

import 'danmaku.dart';

/// 弹幕覆盖层（基于 canvas_danmaku 的 [cd.DanmakuScreen]）。
///
/// 由播放器按视频进度调用 [show] 注入新弹幕；渲染、动画与轨道管理
/// 全部委托给 canvas_danmaku。[enabled] 控制整体开关。
class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({super.key, this.enabled = true});

  final bool enabled;

  @override
  State<DanmakuOverlay> createState() => DanmakuOverlayState();
}

class DanmakuOverlayState extends State<DanmakuOverlay> {
  cd.DanmakuController? _cdController;
  cd.DanmakuOption _option = cd.DanmakuOption();

  /// 注入一条弹幕（被播放器在合适进度调用）。
  void show(DanmakuItem item) {
    if (!widget.enabled || !mounted) return;
    _cdController?.addDanmaku(
      cd.DanmakuContentItem(
        item.text,
        color: item.color,
      ),
    );
  }

  /// 注入一条用户发送的弹幕（从弹幕输入框调用，使用当前播放位置作为时间基准）。
  void addSingle(DanmakuItem item) {
    if (!widget.enabled || !mounted) return;
    _cdController?.addDanmaku(
      cd.DanmakuContentItem(
        item.text,
        color: item.color,
      ),
    );
  }

  /// 清空屏幕上的弹幕。
  void clear() => _cdController?.clear();

  /// 暂停弹幕动画。
  void pause() => _cdController?.pause();

  /// 恢复弹幕动画。
  void resume() => _cdController?.resume();

  /// 更新弹幕选项。
  void updateOption(cd.DanmakuOption option) {
    _option = option;
    _cdController?.updateOption(option);
  }

  @override
  Widget build(BuildContext context) {
    return cd.DanmakuScreen(
      option: _option,
      createdController: (cd.DanmakuController controller) {
        _cdController = controller;
      },
    );
  }
}
