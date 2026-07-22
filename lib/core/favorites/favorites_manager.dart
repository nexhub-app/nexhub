/// 收藏管理器（文档 §10.2）。
///
/// 三模块共用，按 [SourceType] 隔离收藏列表。
/// 持久化到 [PrefsBackend]，UI 通过 [ChangeNotifier] 驱动。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../comic/models/reader_preferences.dart';
import '../models/media_item.dart';
import '../models/plugin_config.dart';

/// 收藏条目——精简版 MediaItem，只保留书架展示所需字段。
class FavoriteEntry {
  final String id;
  final String title;
  final String? coverUrl;
  final String? sourceId;
  final SourceType sourceType;
  final String? author;
  final String? detailUrl;
  final int favoritedAt;

  /// 最后阅读时间（毫秒），0 表示未读过（P8.1.3 §廿一 收藏切换不丢 dateAdded/lastRead）。
  final int lastRead;

  /// 分类（取自 MediaItem.tags 首项），用于书架筛选。
  final String? category;

  /// 状态（连载中 / 已完结），用于书架筛选。
  final String? status;

  const FavoriteEntry({
    required this.id,
    required this.title,
    required this.sourceType,
    this.coverUrl,
    this.sourceId,
    this.author,
    this.detailUrl,
    required this.favoritedAt,
    this.lastRead = 0,
    this.category,
    this.status,
  });

  factory FavoriteEntry.fromMediaItem(MediaItem item, {int? favoritedAt}) =>
      FavoriteEntry(
        id: item.id,
        title: item.title,
        coverUrl: item.coverUrl,
        sourceId: item.sourceId,
        sourceType: item.sourceType ?? SourceType.animeSource,
        author: item.author,
        detailUrl: item.detailUrl,
        favoritedAt: favoritedAt ?? DateTime.now().millisecondsSinceEpoch,
        lastRead: 0,
        category: item.tags?.isNotEmpty == true ? item.tags!.first : null,
        status: item.status,
      );

  /// 返回一个更新了 lastRead 的副本。
  FavoriteEntry withLastRead(int timestamp) => FavoriteEntry(
        id: id,
        title: title,
        coverUrl: coverUrl,
        sourceId: sourceId,
        sourceType: sourceType,
        author: author,
        detailUrl: detailUrl,
        favoritedAt: favoritedAt,
        lastRead: timestamp,
        category: category,
        status: status,
      );

  /// 返回一个更新了 coverUrl 的副本（用于"设为书架封面"）。
  FavoriteEntry withCoverUrl(String? newCoverUrl) => FavoriteEntry(
        id: id,
        title: title,
        coverUrl: newCoverUrl,
        sourceId: sourceId,
        sourceType: sourceType,
        author: author,
        detailUrl: detailUrl,
        favoritedAt: favoritedAt,
        lastRead: lastRead,
        category: category,
        status: status,
      );

  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: title,
        coverUrl: coverUrl,
        sourceId: sourceId,
        sourceType: sourceType,
        author: author,
        detailUrl: detailUrl,
        tags: category != null ? <String>[category!] : null,
        status: status,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'coverUrl': coverUrl,
        'sourceId': sourceId,
        'sourceType': sourceType.apiName,
        'author': author,
        'detailUrl': detailUrl,
        'favoritedAt': favoritedAt,
        'lastRead': lastRead,
        'category': category,
        'status': status,
      };

  factory FavoriteEntry.fromJson(Map<String, dynamic> json) => FavoriteEntry(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        coverUrl: json['coverUrl'] as String?,
        sourceId: json['sourceId'] as String?,
        sourceType:
            SourceType.parse(json['sourceType'] as String?) ?? SourceType.animeSource,
        author: json['author'] as String?,
        detailUrl: json['detailUrl'] as String?,
        favoritedAt: json['favoritedAt'] as int? ?? 0,
        lastRead: json['lastRead'] as int? ?? 0,
        category: json['category'] as String?,
        status: json['status'] as String?,
      );
}

/// 收藏管理器——全应用单例（Provider 注入）。
class FavoritesManager extends ChangeNotifier {
  FavoritesManager({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  final PrefsBackend _backend;
  static const String _key = 'favorites_v1';

  final Map<SourceType, List<FavoriteEntry>> _cache = {};

  /// 加载持久化数据。
  Future<void> init() async {
    final raw = await _backend.get(_key);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          final entry = FavoriteEntry.fromJson(item as Map<String, dynamic>);
          _cache.putIfAbsent(entry.sourceType, () => <FavoriteEntry>[]).add(entry);
        }
      } catch (_) {
        // 损坏数据忽略
      }
    }
    notifyListeners();
  }

  /// 获取某模块的收藏列表（按收藏时间倒序）。
  List<FavoriteEntry> favoritesFor(SourceType type) =>
      List.unmodifiable(_cache[type]?.reversed.toList() ?? const <FavoriteEntry>[]);

  /// 是否已收藏。
  bool isFavorite(String contentId, SourceType type) =>
      _cache[type]?.any((e) => e.id == contentId) ?? false;

  /// 切换收藏状态。重新收藏时保留原始 favoritedAt（P8.1.3 §廿一 不丢 dateAdded）。
  Future<void> toggleFavorite(MediaItem item) async {
    final type = item.sourceType ?? SourceType.animeSource;
    final list = _cache.putIfAbsent(type, () => <FavoriteEntry>[]);

    final idx = list.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      // 取消收藏：保留原 favoritedAt 和 lastRead，以便重新收藏时不丢
      final old = list[idx];
      _removedFavoriteCache[item.id] = old;
      list.removeAt(idx);
    } else {
      // 检查是否有刚被移除的缓存（保留原 favoritedAt + lastRead）
      final cached = _removedFavoriteCache.remove(item.id);
      if (cached != null) {
        // 重新收藏：保留原 favoritedAt 和 lastRead，但更新封面/作者等字段
        list.add(FavoriteEntry.fromMediaItem(item,
            favoritedAt: cached.favoritedAt));
        // 保留 lastRead（fromMediaItem 会重置为 0）
        final newIdx = list.length - 1;
        list[newIdx] = list[newIdx].withLastRead(cached.lastRead);
      } else {
        list.add(FavoriteEntry.fromMediaItem(item));
      }
    }
    await _persist();
    notifyListeners();
  }

  /// 更新某收藏条目的 lastRead 时间戳（阅读器内调用）。
  Future<void> updateLastRead(String contentId, SourceType type) async {
    final list = _cache[type];
    if (list == null) return;
    final idx = list.indexWhere((e) => e.id == contentId);
    if (idx < 0) return;
    list[idx] = list[idx].withLastRead(DateTime.now().millisecondsSinceEpoch);
    await _persist();
    notifyListeners();
  }

  /// 更新某收藏条目的封面 URL（"设为书架封面"调用）。
  Future<bool> updateCover(
    String contentId,
    SourceType type,
    String? newCoverUrl,
  ) async {
    final list = _cache[type];
    if (list == null) return false;
    final idx = list.indexWhere((e) => e.id == contentId);
    if (idx < 0) return false;
    list[idx] = list[idx].withCoverUrl(newCoverUrl);
    await _persist();
    notifyListeners();
    return true;
  }

  /// 已移除收藏的临时缓存（key=contentId），用于重新收藏时保留原 favoritedAt/lastRead。
  /// 仅内存态，应用重启后不保留。
  final Map<String, FavoriteEntry> _removedFavoriteCache = {};

  /// 移除收藏。
  Future<void> removeFavorite(String contentId, SourceType type) async {
    final list = _cache[type];
    if (list == null) return;
    list.removeWhere((e) => e.id == contentId);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final all = <Map<String, dynamic>>[];
    for (final list in _cache.values) {
      all.addAll(list.map((e) => e.toJson()));
    }
    await _backend.set(_key, jsonEncode(all));
  }

  /// Export all favorites as a JSON-serializable list.
  List<Map<String, dynamic>> exportToJson() {
    final all = <Map<String, dynamic>>[];
    for (final list in _cache.values) {
      all.addAll(list.map((e) => e.toJson()));
    }
    return all;
  }

  /// Import favorites from a parsed JSON list (merge, dedup by id).
  Future<void> importFromList(List<dynamic> items) async {
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final entry = FavoriteEntry.fromJson(item);
      final list =
          _cache.putIfAbsent(entry.sourceType, () => <FavoriteEntry>[]);
      if (list.any((e) => e.id == entry.id)) continue;
      list.add(entry);
    }
    await _persist();
    notifyListeners();
  }
}
