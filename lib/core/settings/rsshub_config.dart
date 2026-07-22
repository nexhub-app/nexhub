/// RSSHub 配置（实例地址）。
///
/// 持久化到 shared_preferences，遵循 [PrefsBackend] 抽象。
library;

import 'dart:convert';

import '../../core/comic/models/reader_preferences.dart';

/// RSSHub 配置数据模型。
class RssHubConfig {
  /// 当前使用的实例地址（空 = 使用官方默认实例）。
  final String instanceUrl;

  /// 是否使用自定义实例（而非预置实例）。
  final bool useCustom;

  /// 用户自定义实例列表（支持多条管理）。
  final List<String> customInstances;

  const RssHubConfig({
    this.instanceUrl = '',
    this.useCustom = false,
    this.customInstances = const <String>[],
  });

  const RssHubConfig.defaults()
      : instanceUrl = '',
        useCustom = false,
        customInstances = const <String>[];

  /// 解析为实际可用的实例 URL（默认回退官方实例）。
  String get effectiveUrl =>
      instanceUrl.isNotEmpty ? instanceUrl : 'https://rsshub.app';

  RssHubConfig copyWith({
    String? instanceUrl,
    bool? useCustom,
    List<String>? customInstances,
  }) =>
      RssHubConfig(
        instanceUrl: instanceUrl ?? this.instanceUrl,
        useCustom: useCustom ?? this.useCustom,
        customInstances: customInstances ?? this.customInstances,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'instanceUrl': instanceUrl,
        'useCustom': useCustom,
        'customInstances': customInstances,
      };

  factory RssHubConfig.fromJson(Map<String, dynamic> json) => RssHubConfig(
        instanceUrl: json['instanceUrl'] as String? ?? '',
        useCustom: json['useCustom'] as bool? ?? false,
        customInstances: (json['customInstances'] as List<dynamic>?)
                ?.map((dynamic e) => e as String)
                .toList() ??
            <String>[],
      );

  String toJsonString() => jsonEncode(toJson());

  static RssHubConfig fromJsonString(String raw) =>
      RssHubConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// RSSHub 配置持久化存储（键 `rsshub_config`）。
class RssHubConfigStore {
  static const String _key = 'rsshub_config';

  final PrefsBackend _backend;

  RssHubConfigStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  Future<RssHubConfig> load() async {
    final raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) return const RssHubConfig.defaults();
    try {
      return RssHubConfig.fromJsonString(raw);
    } on Object {
      return const RssHubConfig.defaults();
    }
  }

  Future<void> save(RssHubConfig config) async {
    await _backend.set(_key, config.toJsonString());
  }
}
