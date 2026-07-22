/// 数据导入/导出配置（导出文件夹路径）。
///
/// 持久化到 shared_preferences，遵循 [PrefsBackend] 抽象。
library;

import 'dart:convert';

import '../../core/comic/models/reader_preferences.dart';

/// 数据导入/导出配置数据模型。
class DataExportConfig {
  /// 自定义导出文件夹路径（空 = 使用默认路径）。
  final String exportFolder;

  const DataExportConfig({
    this.exportFolder = '',
  });

  const DataExportConfig.defaults() : exportFolder = '';

  DataExportConfig copyWith({
    String? exportFolder,
  }) =>
      DataExportConfig(
        exportFolder: exportFolder ?? this.exportFolder,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'exportFolder': exportFolder,
      };

  factory DataExportConfig.fromJson(Map<String, dynamic> json) =>
      DataExportConfig(
        exportFolder: json['exportFolder'] as String? ?? '',
      );

  String toJsonString() => jsonEncode(toJson());

  static DataExportConfig fromJsonString(String raw) =>
      DataExportConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// 数据导出配置持久化存储（键 `data_export_config`）。
class DataExportConfigStore {
  static const String _key = 'data_export_config';

  final PrefsBackend _backend;

  DataExportConfigStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  Future<DataExportConfig> load() async {
    final raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) return const DataExportConfig.defaults();
    try {
      return DataExportConfig.fromJsonString(raw);
    } on Object {
      return const DataExportConfig.defaults();
    }
  }

  Future<void> save(DataExportConfig config) async {
    await _backend.set(_key, config.toJsonString());
  }
}
