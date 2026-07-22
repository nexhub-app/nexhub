/// 下载设置（最大同时下载数 / 线程数 / 路径 / 下载器类型）。
///
/// 持久化到 shared_preferences，遵循 [PrefsBackend] 抽象（可注入内存后端测试）。
library;

import 'dart:convert';

import '../../core/comic/models/reader_preferences.dart';

/// 下载器类型：内置 / 外置。
enum DownloaderType { internal, external }

/// 下载设置数据模型。
class DownloadSettings {
  /// 最大同时下载数（1-10）。
  final int maxConcurrent;

  /// 下载线程数（1-16）。
  final int threadCount;

  /// 下载路径。
  final String downloadPath;

  /// 下载器类型。
  final DownloaderType downloaderType;

  /// 仅 WiFi 下载：开启后未连接 WiFi 时不启动下载，挂起等待。
  final bool wifiOnly;

  const DownloadSettings({
    this.maxConcurrent = 3,
    this.threadCount = 4,
    this.downloadPath = 'D:/Downloads',
    this.downloaderType = DownloaderType.internal,
    this.wifiOnly = false,
  });

  const DownloadSettings.defaults()
      : maxConcurrent = 3,
        threadCount = 4,
        downloadPath = 'D:/Downloads',
        downloaderType = DownloaderType.internal,
        wifiOnly = false;

  DownloadSettings copyWith({
    int? maxConcurrent,
    int? threadCount,
    String? downloadPath,
    DownloaderType? downloaderType,
    bool? wifiOnly,
  }) =>
      DownloadSettings(
        maxConcurrent: maxConcurrent ?? this.maxConcurrent,
        threadCount: threadCount ?? this.threadCount,
        downloadPath: downloadPath ?? this.downloadPath,
        downloaderType: downloaderType ?? this.downloaderType,
        wifiOnly: wifiOnly ?? this.wifiOnly,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'maxConcurrent': maxConcurrent,
        'threadCount': threadCount,
        'downloadPath': downloadPath,
        'downloaderType': downloaderType.name,
        'wifiOnly': wifiOnly,
      };

  factory DownloadSettings.fromJson(Map<String, dynamic> json) =>
      DownloadSettings(
        maxConcurrent: json['maxConcurrent'] as int? ?? 3,
        threadCount: json['threadCount'] as int? ?? 4,
        downloadPath: json['downloadPath'] as String? ?? 'D:/Downloads',
        wifiOnly: json['wifiOnly'] as bool? ?? false,
        downloaderType: DownloaderType.values.firstWhere(
          (e) => e.name == json['downloaderType'],
          orElse: () => DownloaderType.internal,
        ),
      );

  String toJsonString() => jsonEncode(toJson());

  static DownloadSettings fromJsonString(String raw) =>
      DownloadSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// 下载设置持久化存储（键 `download_settings`）。
class DownloadSettingsStore {
  static const String _key = 'download_settings';

  final PrefsBackend _backend;

  DownloadSettingsStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  Future<DownloadSettings> load() async {
    final raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) return const DownloadSettings.defaults();
    try {
      return DownloadSettings.fromJsonString(raw);
    } on Object {
      return const DownloadSettings.defaults();
    }
  }

  Future<void> save(DownloadSettings settings) async {
    await _backend.set(_key, settings.toJsonString());
  }
}
