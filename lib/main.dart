import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'features/splash/splash_screen.dart';

/// Entry point: defers all initialization to [SplashScreen] so the user sees
/// a branded splash while Hive boxes, sources, and managers come online.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 必须在创建任何 media_kit [Player] 之前初始化原生内核（libmpv / fvp 桥接）。
  // 该调用幂等，所有平台均可安全调用；缺失会导致 "MediaKit.ensureInitialized
  // must be called before using any API" 异常。
  MediaKit.ensureInitialized();
  runApp(const SplashScreen());
}
