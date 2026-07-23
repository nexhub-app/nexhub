import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/theme/app_tokens.dart';

/// 漫画阅读器图片滤镜：亮度 / 对比度 / 色温。
///
/// 使用 [ColorFiltered] + 4x5 颜色矩阵实现实时滤镜，无需引入额外依赖。
/// 矩阵按「亮度 -> 对比度 -> 色温」顺序合成（色温放最后，避免被对比度
/// 压回中性）。三轴范围均为 -1.0~1.0，0.0 表示不调整。
class ReaderImageFilter {
  ReaderImageFilter._();

  /// 构造 4x5 颜色矩阵（行主序，长度 20，供 [ColorFilter.matrix] 使用）。
  ///
  /// [brightness] -1.0~1.0，正值提亮、负值变暗。
  /// [contrast]   -1.0~1.0，正值增强、负值减弱（-1 退化为中灰）。
  /// [colorTemp]  -1.0~1.0，正值偏暖（R↑B↓）、负值偏冷（R↓B↑）。
  static List<double> matrix({
    double brightness = 0.0,
    double contrast = 0.0,
    double colorTemp = 0.0,
  }) {
    // 亮度偏移：映射到 -0.5~0.5（Flutter 颜色通道为 0~1 浮点）。
    final double b = brightness * 0.5;
    // 对比度系数：1+contrast，围绕 0.5 灰点缩放。
    final double c = 1.0 + contrast;
    // 对比度偏移：保持灰中点不变。
    final double co = -0.5 * contrast;
    // 亮度 + 对比度合成后的偏移量。
    final double off = c * b + co;
    // 色温：暖色 R 通道增益、B 通道衰减；冷色反之。0.3 控制最大偏移幅度。
    final double wr = 1.0 + colorTemp * 0.3;
    final double wb = 1.0 - colorTemp * 0.3;
    return <double>[
      wr * c, 0, 0, 0, wr * off, // R
      0, c, 0, 0, off, // G
      0, 0, wb * c, 0, wb * off, // B
      0, 0, 0, 1, 0, // A
    ];
  }

  /// 灰度矩阵（去色）：按 Rec.601 亮度系数把 RGB 压成单色（彩色漫画转黑白）。
  static List<double> grayscaleMatrix() => const <double>[
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ];

  /// 饱和度矩阵：[s] 范围 -1.0~1.0；0 为不变，-1 退化为灰度，>0 增艳。
  /// 围绕 Rec.601 灰度点旋转（标准饱和度矩阵）。
  static List<double> saturationMatrix(double s) {
    final double inv = 1.0 - s;
    final double r = 0.2126 * inv;
    final double g = 0.7152 * inv;
    final double b = 0.0722 * inv;
    return <double>[
      r + s, g, b, 0, 0,
      r, g + s, b, 0, 0,
      r, g, b + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  /// 色相旋转矩阵：围绕灰度轴旋转 [angle] 弧度（标准 hue-rotation 矩阵）。
  static List<double> hueMatrix(double angle) {
    final double c = math.cos(angle);
    final double sn = math.sin(angle);
    return <double>[
      0.213 + c * 0.787 - sn * 0.213, 0.715 - c * 0.715 - sn * 0.715,
      0.072 - c * 0.072 + sn * 0.928, 0, 0,
      0.213 - c * 0.213 + sn * 0.143, 0.715 + c * 0.285 + sn * 0.140,
      0.072 - c * 0.072 - sn * 0.283, 0, 0,
      0.213 - c * 0.213 - sn * 0.787, 0.715 - c * 0.715 + sn * 0.715,
      0.072 + c * 0.928 + sn * 0.072, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  /// 三轴是否均为默认值（无任何滤镜）。
  static bool isIdentity(
    double brightness,
    double contrast,
    double colorTemp, [
    double saturation = 0.0,
    double hue = 0.0,
  ]) =>
      brightness == 0.0 &&
      contrast == 0.0 &&
      colorTemp == 0.0 &&
      saturation == 0.0 &&
      hue == 0.0;
}

/// 用滤镜包裹子节点；三轴为 0 且不反色时直接返回原节点，避免无谓的图层开销。
///
/// 反色按雷区 11 用 `ColorFilter.mode(Colors.white, BlendMode.difference)`
/// 实现，避免 matrix 方案在桌面端变全黑的 bug。反色层叠加在 matrix 之上
/// （先做亮度/对比度/色温调整，再做反色）。
class ReaderImageFiltered extends StatelessWidget {
  final double brightness;
  final double contrast;
  final double colorTemp;
  final double saturation;
  final double hue;
  final bool inverted;
  final bool grayscale;
  final Widget child;

  const ReaderImageFiltered({
    super.key,
    required this.brightness,
    required this.contrast,
    required this.colorTemp,
    this.saturation = 0.0,
    this.hue = 0.0,
    this.inverted = false,
    this.grayscale = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bool matrixIdentity = ReaderImageFilter.isIdentity(
      brightness,
      contrast,
      colorTemp,
      saturation,
      hue,
    );
    if (matrixIdentity && !inverted && !grayscale) return child;
    Widget result = child;
    if (grayscale) {
      result = ColorFiltered(
        colorFilter:
            ColorFilter.matrix(ReaderImageFilter.grayscaleMatrix()),
        child: result,
      );
    }
    if (!matrixIdentity) {
      final m = ReaderImageFilter.matrix(
        brightness: brightness,
        contrast: contrast,
        colorTemp: colorTemp,
      );
      result = ColorFiltered(colorFilter: ColorFilter.matrix(m), child: result);
      if (saturation != 0.0) {
        result = ColorFiltered(
          colorFilter:
              ColorFilter.matrix(ReaderImageFilter.saturationMatrix(saturation)),
          child: result,
        );
      }
      if (hue != 0.0) {
        result = ColorFiltered(
          colorFilter: ColorFilter.matrix(
            ReaderImageFilter.hueMatrix(hue * math.pi),
          ),
          child: result,
        );
      }
    }
    if (inverted) {
      result = ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.difference),
        child: result,
      );
    }
    return result;
  }
}

/// 滤镜调节面板（反色开关 + 三轴滑块 + 重置按钮）。
///
/// 嵌入阅读设置抽屉的「图片滤镜」段。通过 [onChanged] 实时回传三轴新值，
/// 通过 [onInvertedChanged] 回传反色开关新值，阅读器据此重建当前页，
/// 实现「所见即所得」的实时预览。
class ReaderImageFilterPanel extends StatefulWidget {
  final double brightness;
  final double contrast;
  final double colorTemp;
  final double saturation;
  final double hue;
  final bool inverted;
  final bool grayscale;

  /// 五轴中任意一轴变化时回调，参数顺序固定为 (亮度, 对比度, 色温, 饱和度, 色相)。
  final void Function(double brightness, double contrast, double colorTemp,
      double saturation, double hue) onChanged;

  /// 反色开关变化时回调。
  final ValueChanged<bool> onInvertedChanged;

  /// 灰度开关变化时回调。
  final ValueChanged<bool> onGrayscaleChanged;

  const ReaderImageFilterPanel({
    super.key,
    required this.brightness,
    required this.contrast,
    required this.colorTemp,
    this.saturation = 0.0,
    this.hue = 0.0,
    this.inverted = false,
    this.grayscale = false,
    required this.onChanged,
    required this.onInvertedChanged,
    required this.onGrayscaleChanged,
  });

  @override
  State<ReaderImageFilterPanel> createState() => _ReaderImageFilterPanelState();
}

class _ReaderImageFilterPanelState extends State<ReaderImageFilterPanel> {
  late double _brightness;
  late double _contrast;
  late double _colorTemp;
  late double _saturation;
  late double _hue;
  late bool _inverted;
  late bool _grayscale;

  @override
  void initState() {
    super.initState();
    _brightness = widget.brightness;
    _contrast = widget.contrast;
    _colorTemp = widget.colorTemp;
    _saturation = widget.saturation;
    _hue = widget.hue;
    _inverted = widget.inverted;
    _grayscale = widget.grayscale;
  }

  void _emit() => widget.onChanged(
        _brightness,
        _contrast,
        _colorTemp,
        _saturation,
        _hue,
      );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.readerGrayscale),
          value: _grayscale,
          onChanged: (bool v) {
            setState(() => _grayscale = v);
            widget.onGrayscaleChanged(v);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.filterInverted),
          value: _inverted,
          onChanged: (bool v) {
            setState(() => _inverted = v);
            widget.onInvertedChanged(v);
          },
        ),
        const SizedBox(height: AppTokens.spaceSm),
        _SliderRow(
          label: l10n.brightness,
          value: _brightness,
          onChanged: (double v) {
            setState(() => _brightness = v);
            _emit();
          },
        ),
        const SizedBox(height: AppTokens.spaceSm),
        _SliderRow(
          label: l10n.contrast,
          value: _contrast,
          onChanged: (double v) {
            setState(() => _contrast = v);
            _emit();
          },
        ),
        const SizedBox(height: AppTokens.spaceSm),
        _SliderRow(
          label: l10n.colorTemperature,
          value: _colorTemp,
          onChanged: (double v) {
            setState(() => _colorTemp = v);
            _emit();
          },
        ),
        const SizedBox(height: AppTokens.spaceSm),
        _SliderRow(
          label: l10n.saturation,
          value: _saturation,
          onChanged: (double v) {
            setState(() => _saturation = v);
            _emit();
          },
        ),
        const SizedBox(height: AppTokens.spaceSm),
        _SliderRow(
          label: l10n.hue,
          value: _hue,
          onChanged: (double v) {
            setState(() => _hue = v);
            _emit();
          },
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _brightness = 0.0;
                _contrast = 0.0;
                _colorTemp = 0.0;
                _saturation = 0.0;
                _hue = 0.0;
                _inverted = false;
                _grayscale = false;
              });
              _emit();
              widget.onInvertedChanged(false);
              widget.onGrayscaleChanged(false);
            },
            icon: const Icon(Icons.restart_alt, size: 18),
            label: Text(l10n.resetFilter),
          ),
        ),
      ],
    );
  }
}

/// 单行滑块：标签 + 滑块 + 数值。
class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(width: 96, child: Text(label)),
        Expanded(
          child: Slider(
            min: -1.0,
            max: 1.0,
            divisions: 200, // 0.01 步进
            value: value.clamp(-1.0, 1.0),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
