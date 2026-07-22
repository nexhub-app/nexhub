import 'package:flutter/material.dart';
import 'app_tokens.dart';
import 'app_theme.dart';

/// 运行时主题状态（亮 / 暗 / 跟随 + 自定义主色 + 莫奈开关）。
///
/// 使用方式（见 lib/app.dart）：
/// ```dart
/// ChangeNotifierProvider<ThemeController>.value(
///   value: ThemeController(),
///   child: const App(),
/// )
/// ```
///
/// 莫奈取色（Monet / Material You）：当 [useMonet] 为 true 且系统提供了动态
/// ColorScheme 时，优先使用系统动态色；否则回退到 [seed] 生成的浅蓝主题。
class ThemeController extends ChangeNotifier {
  ThemeController({
    ThemeMode mode = ThemeMode.system,
    Color seed = AppTokens.seedYouthfulPrimary,
    bool useMonet = true,
  })  : _mode = mode,
        _seed = seed,
        _useMonet = useMonet;

  ThemeMode _mode;
  Color _seed;
  bool _useMonet;

  ThemeMode get mode => _mode;

  /// 当前自定义主色（非莫奈时生效）。
  Color get seed => _seed;

  /// 是否优先使用系统莫奈动态色。
  bool get useMonet => _useMonet;

  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  /// 选择自定义主色（会自动关闭莫奈，因为指定了显式 seed）。
  void setSeed(Color seed) {
    _seed = seed;
    _useMonet = false;
    notifyListeners();
  }

  void setUseMonet(bool value) {
    if (_useMonet == value) return;
    _useMonet = value;
    notifyListeners();
  }

  ThemeData lightTheme([ColorScheme? systemScheme]) =>
      _useMonet && systemScheme != null
          ? AppTheme.light(scheme: systemScheme)
          : AppTheme.light(seed: _seed);

  ThemeData darkTheme([ColorScheme? systemScheme]) =>
      _useMonet && systemScheme != null
          ? AppTheme.dark(scheme: systemScheme)
          : AppTheme.dark(seed: _seed);
}
