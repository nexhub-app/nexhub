/// 弹弹 play 弹幕配置（AppId / AppSecret）。
///
/// 持久化到 shared_preferences，遵循 [PrefsBackend] 抽象。
library;

import 'dart:convert';

import '../../core/comic/models/reader_preferences.dart';

/// 弹弹 play 弹幕配置数据模型。
class DanmakuConfig {
  final String appId;
  final String appSecret;
  final bool enabled;

  const DanmakuConfig({
    this.appId = '',
    this.appSecret = '',
    this.enabled = false,
  });

  const DanmakuConfig.defaults()
      : appId = '',
        appSecret = '',
        enabled = false;

  bool get isConfigured => appId.isNotEmpty && appSecret.isNotEmpty;

  DanmakuConfig copyWith({
    String? appId,
    String? appSecret,
    bool? enabled,
  }) =>
      DanmakuConfig(
        appId: appId ?? this.appId,
        appSecret: appSecret ?? this.appSecret,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'appId': appId,
        'appSecret': appSecret,
        'enabled': enabled,
      };

  factory DanmakuConfig.fromJson(Map<String, dynamic> json) => DanmakuConfig(
        appId: json['appId'] as String? ?? '',
        appSecret: json['appSecret'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? false,
      );

  String toJsonString() => jsonEncode(toJson());

  static DanmakuConfig fromJsonString(String raw) =>
      DanmakuConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// 弹幕配置持久化存储（键 `danmaku_config`）。
class DanmakuConfigStore {
  static const String _key = 'danmaku_config';

  final PrefsBackend _backend;

  DanmakuConfigStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  Future<DanmakuConfig> load() async {
    final raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) return const DanmakuConfig.defaults();
    try {
      return DanmakuConfig.fromJsonString(raw);
    } on Object {
      return const DanmakuConfig.defaults();
    }
  }

  Future<void> save(DanmakuConfig config) async {
    await _backend.set(_key, config.toJsonString());
  }
}
