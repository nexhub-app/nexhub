import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/comic/models/reader_preferences.dart';

/// 点击区域动作。
enum _TapAction { prev, next, toggle }

/// 单个点击热区（坐标为相对于阅读区的比例 0..1）。
class _Region {
  final double left;
  final double top;
  final double width;
  final double height;
  final _TapAction action;
  const _Region(this.left, this.top, this.width, this.height, this.action);
}

/// 阅读器点击区域覆盖层（文档 7.3）。
///
/// 用一个铺满阅读区的 [Listener] 监听指针 down / up，按抬起坐标命中对应热区
/// 分发到 prev / next / toggle。之所以不用 [GestureDetector]：在 widget 测试中
/// 验证发现，[GestureDetector] 的识别器由 `RawGestureDetector` 内部的
/// `Listener`（deferToChild）在命中测试时喂入指针，而该内部 Listener 在以
/// `SizedBox.expand()` 之类「自身不可命中」的 child 作下层时不会进入命中路径，
/// 导致识别器拿不到指针、单击永远不触发（即便覆盖层几何与 behavior 都正确）。
/// 直接用 [Listener] 的 `onPointerDown` / `onPointerUp` 则稳定可靠。
///
/// 双击（仅切换热区）触发 `onZoom` 缩放，与单击导航互不冲突。支持 5 种布局。
///
/// 在布局之上叠加 [TapZoneInvert] 方向反转：leftRight 反转横向翻页（竖向
/// webtoon 模式下不生效），upDown 反转竖向滚动，all 两者都反转。
class ReaderTapZones extends StatefulWidget {
  final ReaderTapZoneLayout layout;
  final TapZoneInvert tapZoneInvert;
  final bool isVertical; // webtoon / 竖向：prev=上滚，next=下滚
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToggleUi;
  final VoidCallback? onZoom;

  /// 在指定位置缩放（桌面 Shift+左键 兜底双击缩放）。为 null 时由调用方回退到 [onZoom]。
  final void Function(Offset)? onZoomAt;

  /// 长按回调（用于弹出图片「保存 / 分享」菜单等）。为 null 时不检测长按。
  final VoidCallback? onLongPress;

  /// 是否渲染点击区域预览（彩色块 + 标签）。用于设置页预览，开启时不响应手势。
  final bool showPreview;

  /// 预览标签（key 为 'prev' / 'next' / 'toggle'）。
  final Map<String, String>? previewLabels;

  const ReaderTapZones({
    super.key,
    required this.layout,
    this.tapZoneInvert = TapZoneInvert.none,
    required this.isVertical,
    required this.onPrev,
    required this.onNext,
    required this.onToggleUi,
    this.onZoom,
    this.onZoomAt,
    this.onLongPress,
    this.showPreview = false,
    this.previewLabels,
  });

  @override
  State<ReaderTapZones> createState() => _ReaderTapZonesState();
}

class _ReaderTapZonesState extends State<ReaderTapZones> {
  int? _activePointer;
  Offset? _downPos;
  DateTime? _downTime;
  bool _downShift = false;

  // 双击检测：记录上一次「已分发的单击」时间与位置。
  DateTime? _lastTapTime;
  Offset? _lastTapPos;

  // 长按检测：按下后启动定时器，到阈值仍未抬起且未明显移动则触发。
  Timer? _longPressTimer;
  bool _longPressFired = false;

  static const double _tapSlop = 18.0; // 移动超过此值不算 tap
  static const Duration _tapTimeout = Duration(milliseconds: 400);
  static const Duration _doubleTapTimeout = Duration(milliseconds: 300);
  static const double _doubleTapSlop = 36.0;
  static const Duration _longPressThreshold = Duration(milliseconds: 500);

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  /// 启动长按定时器（仅在 [widget.onLongPress] 非空时）。
  void _startLongPressTimer(int pointer) {
    if (widget.onLongPress == null) return;
    _longPressTimer?.cancel();
    _longPressFired = false;
    _longPressTimer = Timer(_longPressThreshold, () {
      if (_activePointer == pointer) {
        _longPressFired = true;
        widget.onLongPress!();
      }
    });
  }

  /// 指针移动超过 slop 则取消长按（避免拖拽误触发）。
  void _maybeCancelLongPress(Offset pos) {
    final Offset? down = _downPos;
    if (down == null) return;
    if ((pos - down).distance > _tapSlop) {
      _longPressTimer?.cancel();
    }
  }

  List<_Region> _buildRegions() {
    switch (widget.layout) {
      case ReaderTapZoneLayout.leftRight:
        return const <_Region>[
          _Region(0, 0, 0.45, 1, _TapAction.prev),
          _Region(0.45, 0, 0.1, 1, _TapAction.toggle),
          _Region(0.55, 0, 0.45, 1, _TapAction.next),
        ];
      case ReaderTapZoneLayout.lShape:
        // 两个 L 形 + 中心 toggle（与小说 tap_zone_resolver.dart 保持一致）：
        // prev = 左列 + 下中条；next = 右列 + 上中条；toggle = 中心方块。
        return const <_Region>[
          _Region(0, 0, 0.33, 1, _TapAction.prev), // 左列（全高）
          _Region(0.67, 0, 0.33, 1, _TapAction.next), // 右列（全高）
          _Region(0.33, 0, 0.34, 0.33, _TapAction.next), // 上中条
          _Region(0.33, 0.67, 0.34, 0.33, _TapAction.prev), // 下中条
          _Region(0.33, 0.33, 0.34, 0.34, _TapAction.toggle), // 中心
        ];
      case ReaderTapZoneLayout.kindle:
        return const <_Region>[
          _Region(0, 0, 1, 0.15, _TapAction.toggle),
          _Region(0, 0.15, 0.35, 0.85, _TapAction.prev),
          _Region(0.35, 0.15, 0.65, 0.85, _TapAction.next),
        ];
      case ReaderTapZoneLayout.bothSides:
        return const <_Region>[
          _Region(0, 0.15, 0.33, 0.7, _TapAction.next),
          _Region(0.67, 0.15, 0.33, 0.7, _TapAction.next),
          _Region(0.33, 0.7, 0.34, 0.3, _TapAction.prev),
          _Region(0.33, 0, 0.34, 0.15, _TapAction.toggle),
        ];
      case ReaderTapZoneLayout.off:
        return const <_Region>[_Region(0, 0, 1, 1, _TapAction.toggle)];
    }
  }

  Rect _rect(_Region r, double w, double h) =>
      Rect.fromLTWH(r.left * w, r.top * h, r.width * w, r.height * h);

  _TapAction? _actionAt(Offset p, double w, double h) {
    for (final r in _buildRegions()) {
      if (_rect(r, w, h).contains(p)) return r.action;
    }
    return null;
  }

  void _onPointerDown(PointerDownEvent e) {
    _activePointer = e.pointer;
    _downPos = e.localPosition;
    _downTime = DateTime.now();
    _downShift = HardwareKeyboard.instance.isShiftPressed;
    _startLongPressTimer(e.pointer);
  }

  void _onPointerMove(PointerMoveEvent e) {
    _maybeCancelLongPress(e.localPosition);
  }

  void _onPointerUp(PointerUpEvent e) {
    _longPressTimer?.cancel();
    if (_activePointer != e.pointer || _downPos == null || _downTime == null) {
      return;
    }
    final move = (e.localPosition - _downPos!).distance;
    final dt = DateTime.now().difference(_downTime!);
    final fired = _longPressFired;
    _activePointer = null;
    _downPos = null;
    _downTime = null;
    _longPressFired = false;
    final bool shifted = _downShift;
    _downShift = false;
    // 长按已触发则不再分发单击 / 双击。
    if (fired) return;
    // 移动过大或按住过久视为拖拽 / 长按，不处理。
    if (move > _tapSlop || dt > _tapTimeout) return;

    // 桌面 Shift+左键：在点击处缩放（兜底双击缩放），不触发导航 / 双击。
    // 此分支优先于区域命中，任意位置按下 Shift 均可定点缩放。
    if (shifted) {
      final at = widget.onZoomAt;
      if (at != null) {
        at(e.localPosition);
      } else {
        widget.onZoom?.call();
      }
      return;
    }

    final size = MediaQuery.sizeOf(context);
    final action = _actionAt(e.localPosition, size.width, size.height);
    if (action == null) return;

    final now = DateTime.now();
    final isDouble = _lastTapTime != null &&
        now.difference(_lastTapTime!) <= _doubleTapTimeout &&
        _lastTapPos != null &&
        (_lastTapPos! - e.localPosition).distance <= _doubleTapSlop;
    if (isDouble) {
      // 双击：仅切换热区触发缩放。注意：不再抑制本次单击的导航/切换，
      // 否则两次快速单击会被误判为双击而丢失一次切换（widget 测试中的两次
      // 单击间隔仅约 80ms）。双击时 UI 会闪一下，但缩放功能正确。
      _lastTapTime = null;
      _lastTapPos = null;
      if (action == _TapAction.toggle) widget.onZoom?.call();
    } else {
      _lastTapTime = now;
      _lastTapPos = e.localPosition;
    }
    _dispatch(action);
  }

  void _dispatch(_TapAction a) {
    switch (_effectiveAction(a)) {
      case _TapAction.prev:
        widget.onPrev();
      case _TapAction.next:
        widget.onNext();
      case _TapAction.toggle:
        widget.onToggleUi();
    }
  }

  /// 按 [widget.tapZoneInvert] 与 [widget.isVertical] 决定实际触发的动作。
  ///
  /// - 横向模式 + leftRight/all → 反转 prev/next
  /// - 竖向模式 + upDown/all → 反转 prev/next（上下滚动方向反转）
  /// - none → 不反转
  ///
  /// 预览也复用此方法，让彩色块与标签实时反映反转后的真实热区。
  _TapAction _effectiveAction(_TapAction action) {
    if (action == _TapAction.toggle) return action;
    final invert = widget.tapZoneInvert;
    bool shouldInvert = false;
    switch (invert) {
      case TapZoneInvert.none:
        shouldInvert = false;
      case TapZoneInvert.leftRight:
        shouldInvert = !widget.isVertical;
      case TapZoneInvert.upDown:
        shouldInvert = widget.isVertical;
      case TapZoneInvert.all:
        shouldInvert = true;
    }
    if (!shouldInvert) return action;
    return action == _TapAction.prev ? _TapAction.next : _TapAction.prev;
  }

  /// 点击区域预览：彩色块 + 标签，不响应手势。用于设置页。
  Widget _buildPreview() {
    final regions = _buildRegions();
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          children: <Widget>[
            for (final r in regions)
              Positioned(
                left: r.left * w,
                top: r.top * h,
                width: r.width * w,
                height: r.height * h,
                child: Container(
                  color: _previewColor(_effectiveAction(r.action))
                      .withValues(alpha: 0.22),
                  child: Center(
                    child: Text(
                      _previewLabel(_effectiveAction(r.action)),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Color _previewColor(_TapAction a) => switch (a) {
        _TapAction.prev => Colors.blue,
        _TapAction.next => Colors.green,
        _TapAction.toggle => Colors.orange,
      };

  String _previewLabel(_TapAction a) {
    final key = switch (a) {
      _TapAction.prev => 'prev',
      _TapAction.next => 'next',
      _TapAction.toggle => 'toggle',
    };
    return widget.previewLabels?[key] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showPreview) return _buildPreview();
    // 覆盖层铺满父级 Stack；Listener(behavior: opaque) 保证其自身可被命中，
    // 且 SizedBox.expand() 填满几何，单击 / 双击坐标按尺寸比例映射到热区。
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      child: const SizedBox.expand(),
    );
  }
}
