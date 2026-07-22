/// 源配置加载器（运行时态）。
///
/// 关键硬约束（enable-stealth-mode-all-active-sources）：
/// - [getStealthMode] 始终返回 true；[setStealthMode] 为空操作。
/// - 每个源可记录「当前激活镜像」，parser/route/baseUrl/referer 统一指向它。
///
/// 镜像选择持久化到 Hive box `source_mirrors`（P8.2.2 §廿二）。
library;

import 'package:hive/hive.dart';

import '../models/plugin_config.dart';

class ConfigLoader {
  ConfigLoader._();

  static final ConfigLoader instance = ConfigLoader._();

  final Map<String, String> _activeMirror = {};
  final Map<String, String> _cookies = {};
  bool _loaded = false;
  Box<dynamic>? _box;

  /// Hive box 名。
  static const String boxName = 'source_mirrors';

  /// 从 Hive 加载持久化的镜像选择（P8.2.2 §廿二）。
  Future<void> init() async {
    if (_loaded) return;
    _box = await Hive.openBox(boxName);
    for (final key in _box!.keys) {
      if (key is! String) continue;
      final val = _box!.get(key);
      if (val is String && val.isNotEmpty) {
        _activeMirror[key] = val;
      }
    }
    _loaded = true;
  }

  /// 强制隐身：恒 true（不可关闭）。
  bool getStealthMode() => true;

  /// 空操作：UI 不应再提供开关。
  void setStealthMode(bool value) {
    // 强制锁定，忽略调用。
  }

  /// 获取某源当前激活镜像基址（缺省回退 site.baseUrl）。
  String getActiveMirror(PluginConfig source) {
    final mirror = _activeMirror[source.id];
    if (mirror != null) return mirror;
    return source.site.baseUrl;
  }

  /// 设置镜像并持久化到 Hive（P8.2.2 §廿二）。
  void setActiveMirror(String sourceId, String baseUrl) {
    _activeMirror[sourceId] = baseUrl;
    // fire-and-forget 持久化
    _box?.put(sourceId, baseUrl);
  }

  void setCookies(String host, String cookieHeader) {
    _cookies[host] = cookieHeader;
  }

  String? getCookies(String host) => _cookies[host];
}
