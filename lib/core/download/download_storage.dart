/// 下载任务持久化存储（文档 §10.1 / §10.3）。
///
/// 将任务列表序列化为 JSON 存入 PrefsBackend（替代 Hive）。
/// `clear()` 仅清空存储中的任务记录，不删除磁盘文件——
/// 与 `DownloadManager.clearAll(false)` 配合使用后，
/// 管理器立即从 `.meta.json` 恢复孤立记录。
library;

import 'dart:convert';

import '../comic/models/reader_preferences.dart';
import 'download_task.dart';

/// 下载任务存储（可注入后端，测试用 InMemoryBackend）。
class DownloadStorage {
  static const String _key = 'download_tasks';

  final PrefsBackend _backend;

  DownloadStorage({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  /// 读取全部任务。
  Future<List<DownloadTask>> loadAll() async {
    final raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) return <DownloadTask>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => DownloadTask.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <DownloadTask>[];
    }
  }

  /// 保存全部任务（全量覆盖）。
  Future<void> saveAll(List<DownloadTask> tasks) async {
    final raw = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await _backend.set(_key, raw);
  }

  /// 清空存储中的全部任务记录（不删磁盘文件）。
  Future<void> clear() async {
    await _backend.set(_key, '');
  }
}
