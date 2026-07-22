/// 影视已看记录管理器（M16.2 剧集行操作）。
///
/// 按内容 ID 存储已看剧集索引集合，持久化到 Hive box `media_watched`。
/// 支持标记 / 取消标记 / 查询 / 列出某内容的全部已看集。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// 影视已看记录管理器——使用 Hive box `media_watched`。
///
/// key = contentId，value = JSON 编码的 `List<int>`（已看 episodeIndex 集合）。
/// 通过 [ChangeNotifier] 驱动 UI 刷新。
class MediaWatchedManager extends ChangeNotifier {
  MediaWatchedManager({Box<dynamic>? box}) : _box = box;

  /// Hive box 名。
  static const String boxName = 'media_watched';

  final Box<dynamic>? _box;

  /// 内存缓存：contentId → 已看索引集合。
  final Map<String, Set<int>> _cache = {};

  /// 懒加载打开 box 并加载全部数据到内存。
  Future<void> init() async {
    final box = await _openBox();
    for (final key in box.keys) {
      if (key is! String) continue;
      final raw = box.get(key);
      if (raw is! String || raw.isEmpty) continue;
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _cache[key] = list.map((e) => (e as num).toInt()).toSet();
      } on Object {
        // 损坏数据忽略
      }
    }
    notifyListeners();
  }

  Future<Box<dynamic>> _openBox() async {
    if (_box != null) return _box;
    if (Hive.isBoxOpen(boxName)) return Hive.box(boxName);
    return Hive.openBox(boxName);
  }

  /// 判断某集是否已看。
  bool isWatched(String contentId, int episodeIndex) {
    final set = _cache[contentId];
    return set?.contains(episodeIndex) ?? false;
  }

  /// 切换某集的已看状态。
  Future<void> toggleWatched(String contentId, int episodeIndex) async {
    final set = _cache.putIfAbsent(contentId, () => <int>{});
    if (set.contains(episodeIndex)) {
      set.remove(episodeIndex);
    } else {
      set.add(episodeIndex);
    }
    await _persist(contentId);
    notifyListeners();
  }

  /// 标记某集为已看。
  Future<void> markWatched(String contentId, int episodeIndex) async {
    final set = _cache.putIfAbsent(contentId, () => <int>{});
    if (set.contains(episodeIndex)) return;
    set.add(episodeIndex);
    await _persist(contentId);
    notifyListeners();
  }

  /// 获取某内容的全部已看集索引（按升序）。
  List<int> watchedList(String contentId) {
    final set = _cache[contentId];
    if (set == null || set.isEmpty) return const <int>[];
    return set.toList()..sort();
  }

  /// 已看集数。
  int watchedCount(String contentId) =>
      _cache[contentId]?.length ?? 0;

  /// 清除某内容的全部已看记录。
  Future<void> clear(String contentId) async {
    _cache.remove(contentId);
    final box = await _openBox();
    await box.delete(contentId);
    notifyListeners();
  }

  Future<void> _persist(String contentId) async {
    final box = await _openBox();
    final set = _cache[contentId];
    if (set == null || set.isEmpty) {
      await box.delete(contentId);
    } else {
      await box.put(contentId, jsonEncode(set.toList()));
    }
  }
}
