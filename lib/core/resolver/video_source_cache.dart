/// 已解析视频 URL 的 TTL 缓存，避免对同一视频地址重复解析。
///
/// 缓存项在 [ttl] 时间后自动失效；命中过期项时返回 `null` 并移除。
library;

import '../models/episode.dart';

/// 单条缓存项：值 + 过期时间。
class _CacheEntry {
  final VideoResult value;
  final DateTime expiresAt;

  const _CacheEntry(this.value, this.expiresAt);
}

/// [VideoResult] 的 TTL 缓存。
///
/// 默认 TTL 5 分钟。典型 key 形如 `sourceId:episodeId` 或原始视频页 URL。
class VideoSourceCache {
  /// 缓存有效期。
  final Duration ttl;

  final Map<String, _CacheEntry> _entries = {};

  VideoSourceCache({this.ttl = const Duration(minutes: 5)});

  /// 读取缓存的 [VideoResult]；不存在或已过期返回 `null`（过期项会被移除）。
  VideoResult? get(String key) {
    final entry = _entries[key];
    if (entry == null) return null;

    if (DateTime.now().isAfter(entry.expiresAt)) {
      _entries.remove(key);
      return null;
    }

    return entry.value;
  }

  /// 写入缓存项，过期时间为当前时间 + [ttl]。
  void set(String key, VideoResult value) {
    _entries[key] = _CacheEntry(value, DateTime.now().add(ttl));
  }

  /// 清空所有缓存项。
  void clear() => _entries.clear();

  /// 移除指定 key 的缓存项。
  void remove(String key) => _entries.remove(key);

  /// 批量清理所有已过期项，返回移除条数。
  ///
  /// 在重解析前调用，防止过期项堆积。
  int clearExpired() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    _entries.forEach((key, entry) {
      if (now.isAfter(entry.expiresAt)) expiredKeys.add(key);
    });
    for (final key in expiredKeys) {
      _entries.remove(key);
    }
    return expiredKeys.length;
  }

  /// 当前缓存项数量（含可能已过期但未访问触发的项）。
  int get length => _entries.length;
}
