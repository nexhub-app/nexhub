/// 下载格式偏好（文档 §10.1 自定义格式）。
///
/// 漫画可选 CBZ（打包）或散图文件夹；小说可选 EPUB 或 TXT。
/// 偏好持久化到 shared_preferences，可注入后端用于测试。
library;

import 'dart:convert';

import '../comic/models/reader_preferences.dart';
import 'download_task.dart';

/// 下载格式偏好。
class DownloadFormatPreferences {
  /// 漫画格式：cbz（默认）或 folder（散图）。
  final DownloadFormat comicFormat;

  /// 小说格式：epub（默认）或 txt。
  final DownloadFormat novelFormat;

  const DownloadFormatPreferences({
    this.comicFormat = DownloadFormat.cbz,
    this.novelFormat = DownloadFormat.epub,
  });

  const DownloadFormatPreferences.defaults()
      : comicFormat = DownloadFormat.cbz,
        novelFormat = DownloadFormat.epub;

  DownloadFormatPreferences copyWith({
    DownloadFormat? comicFormat,
    DownloadFormat? novelFormat,
  }) =>
      DownloadFormatPreferences(
        comicFormat: comicFormat ?? this.comicFormat,
        novelFormat: novelFormat ?? this.novelFormat,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'comicFormat': comicFormat.label,
        'novelFormat': novelFormat.label,
      };

  factory DownloadFormatPreferences.fromJson(Map<String, dynamic> json) =>
      DownloadFormatPreferences(
        comicFormat:
            DownloadFormat.fromString(json['comicFormat'] as String?) ??
                DownloadFormat.cbz,
        novelFormat:
            DownloadFormat.fromString(json['novelFormat'] as String?) ??
                DownloadFormat.epub,
      );

  String toJsonString() => jsonEncode(toJson());

  static DownloadFormatPreferences fromJsonString(String raw) =>
      DownloadFormatPreferences.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadFormatPreferences &&
          other.comicFormat == comicFormat &&
          other.novelFormat == novelFormat;

  @override
  int get hashCode => Object.hash(comicFormat, novelFormat);
}

/// 格式偏好持久化存储（键 `download_format_prefs`）。
class DownloadFormatPreferencesStore {
  static const String _key = 'download_format_prefs';

  final PrefsBackend _backend;

  DownloadFormatPreferencesStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  Future<DownloadFormatPreferences> load() async {
    final raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) return const DownloadFormatPreferences.defaults();
    try {
      return DownloadFormatPreferences.fromJsonString(raw);
    } catch (_) {
      return const DownloadFormatPreferences.defaults();
    }
  }

  Future<void> save(DownloadFormatPreferences prefs) async {
    await _backend.set(_key, prefs.toJsonString());
  }
}
