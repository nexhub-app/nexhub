/// 浏览历史管理器（文档 §10.2 书架历史记录 Tab）。
///
/// 三模块共用，按 [SourceType] 隔离。
/// 每模块保留最近 [maxPerModule] 条，超出自动淘汰。
/// 持久化到 [PrefsBackend]，UI 通过 [ChangeNotifier] 驱动。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../comic/models/reader_preferences.dart';
import '../models/media_item.dart';
import '../models/plugin_config.dart';
import '../scraper/http_fetcher.dart';

/// 历史条目——记录最近浏览的内容。
class HistoryEntry {
  final String id;
  final String title;
  final String? coverUrl;
  final String? sourceId;
  final SourceType sourceType;
  final String? detailUrl;
  final int viewedAt;
  final String? lastChapter; // 最后阅读的章节/集标题

  /// 分类（取自 MediaItem.tags 首项），用于书架筛选。
  final String? category;

  /// 状态（连载中 / 已完结），用于书架筛选。
  final String? status;

  /// 封面本地缓存路径（离线可见）。写入历史时异步下载远程封面落盘，
  /// 优先于 [coverUrl] 使用；为空时回退远程 [coverUrl]。
  final String? localCoverPath;

  const HistoryEntry({
    required this.id,
    required this.title,
    required this.sourceType,
    this.coverUrl,
    this.sourceId,
    this.detailUrl,
    required this.viewedAt,
    this.lastChapter,
    this.category,
    this.status,
    this.localCoverPath,
  });

  factory HistoryEntry.fromMediaItem(
    MediaItem item, {
    String? lastChapter,
    SourceType? sourceType,
  }) =>
      HistoryEntry(
        id: item.id,
        title: item.title,
        coverUrl: item.coverUrl,
        sourceId: item.sourceId,
        sourceType: sourceType ?? item.sourceType ?? SourceType.animeSource,
        detailUrl: item.detailUrl,
        viewedAt: DateTime.now().millisecondsSinceEpoch,
        lastChapter: lastChapter,
        category: item.tags?.isNotEmpty == true ? item.tags!.first : null,
        status: item.status,
      );

  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: title,
        coverUrl: coverUrl,
        sourceId: sourceId,
        sourceType: sourceType,
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
        'detailUrl': detailUrl,
        'viewedAt': viewedAt,
        'lastChapter': lastChapter,
        'category': category,
        'status': status,
        'localCoverPath': localCoverPath,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        coverUrl: json['coverUrl'] as String?,
        sourceId: json['sourceId'] as String?,
        sourceType:
            SourceType.parse(json['sourceType'] as String?) ?? SourceType.animeSource,
        detailUrl: json['detailUrl'] as String?,
        viewedAt: json['viewedAt'] as int? ?? 0,
        lastChapter: json['lastChapter'] as String?,
        category: json['category'] as String?,
        status: json['status'] as String?,
        localCoverPath: json['localCoverPath'] as String?,
      );

  HistoryEntry copyWith({String? localCoverPath}) => HistoryEntry(
        id: id,
        title: title,
        coverUrl: coverUrl,
        sourceId: sourceId,
        sourceType: sourceType,
        detailUrl: detailUrl,
        viewedAt: viewedAt,
        lastChapter: lastChapter,
        category: category,
        status: status,
        localCoverPath: localCoverPath ?? this.localCoverPath,
      );
}

/// 历史管理器——全应用单例（Provider 注入）。
class HistoryManager extends ChangeNotifier {
  HistoryManager({
    PrefsBackend? backend,
    this.maxPerModule = 50,
  }) : _backend = backend ?? const SharedPrefsBackend();

  final PrefsBackend _backend;
  final int maxPerModule;
  static const String _key = 'history_v1';

  final Map<SourceType, List<HistoryEntry>> _cache = {};

  /// 加载持久化数据。
  Future<void> init() async {
    final raw = await _backend.get(_key);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final item in list) {
          final entry = HistoryEntry.fromJson(item as Map<String, dynamic>);
          _cache.putIfAbsent(entry.sourceType, () => <HistoryEntry>[]).add(entry);
        }
      } catch (_) {
        // 损坏数据忽略
      }
    }
    notifyListeners();
  }

  /// 获取某模块的历史列表（按浏览时间倒序）。
  List<HistoryEntry> historyFor(SourceType type) =>
      List.unmodifiable(_cache[type]?.reversed.toList() ?? const <HistoryEntry>[]);

  /// 查找指定 id 的历史条目（按内容 sourceType + id 唯一定位）。
  ///
  /// 找不到时返回 null。详情页用来取最近一次的浏览时间（[HistoryEntry.viewedAt]），
  /// 作为"上次阅读"提示的相对时间锚点。
  HistoryEntry? findById(String contentId, {SourceType? sourceType}) {
    if (sourceType != null) {
      final list = _cache[sourceType];
      if (list == null) return null;
      for (final e in list) {
        if (e.id == contentId) return e;
      }
      return null;
    }
    for (final list in _cache.values) {
      for (final e in list) {
        if (e.id == contentId) return e;
      }
    }
    return null;
  }

  /// 添加/更新浏览记录。
  ///
  /// [sourceType] 显式指定所属模块，优先于 [MediaItem.sourceType]（后者为可空，
  /// 缺失时会错误回退到 [SourceType.animeSource]，把记录混进影视历史桶）。
  /// 各模块详情页应传入自身的固定类型，确保历史严格按模块隔离。
  Future<void> addHistory(
    MediaItem item, {
    String? lastChapter,
    SourceType? sourceType,
  }) async {
    final type = sourceType ?? item.sourceType ?? SourceType.animeSource;
    final list = _cache.putIfAbsent(type, () => <HistoryEntry>[]);

    // 移除旧记录（去重）
    list.removeWhere((e) => e.id == item.id);
    // 添加到末尾（最新的在后面，读取时 reversed）
    final entry = HistoryEntry.fromMediaItem(
      item,
      lastChapter: lastChapter,
      sourceType: type,
    );
    list.add(entry);

    // 超出上限淘汰
    while (list.length > maxPerModule) {
      list.removeAt(0);
    }

    await _persist();
    notifyListeners();
    // 离线封面缓存（best-effort，不阻塞 UI）。
    unawaited(_cacheCoverFor(entry));
  }

  /// 异步将远程封面下载到本地缓存目录 `history_covers/`，并回写
  /// [HistoryEntry.localCoverPath]（离线可见）。任何失败均静默忽略，
  /// 不影响历史功能。
  Future<void> _cacheCoverFor(HistoryEntry entry) async {
    final url = entry.coverUrl;
    if (url == null || url.isEmpty || !url.startsWith('http')) return;
    if (entry.localCoverPath != null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final coverDir = Directory(p.join(dir.path, 'history_covers'));
      await coverDir.create(recursive: true);
      final ext = _extFromUrl(url);
      final target =
          File(p.join(coverDir.path, '${entry.id.hashCode}_cover$ext'));
      if (await target.exists()) {
        // 已缓存：直接回写路径，避免重复下载。
        _replaceEntryInCache(entry.copyWith(localCoverPath: target.path));
        await _persist();
        notifyListeners();
        return;
      }
      final bytes = await HttpFetcher.instance.getBytes(url);
      if (bytes.isEmpty) return;
      await target.writeAsBytes(bytes);
      _replaceEntryInCache(entry.copyWith(localCoverPath: target.path));
      await _persist();
      notifyListeners();
    } on Object {
      // 封面缓存失败不影响历史功能。
    }
  }

  void _replaceEntryInCache(HistoryEntry updated) {
    final list = _cache[updated.sourceType];
    if (list == null) return;
    final idx = list.indexWhere((e) => e.id == updated.id);
    if (idx >= 0) list[idx] = updated;
  }

  String _extFromUrl(String url) {
    final withoutQuery = url.split('?').first;
    final ext = p.extension(withoutQuery);
    if (ext.isEmpty) return '.jpg';
    return ext.length <= 5 ? ext : '.jpg';
  }

  /// 清除某模块的历史。
  Future<void> clearHistory(SourceType type) async {
    _cache[type]?.clear();
    await _persist();
    notifyListeners();
  }

  /// 清除全部历史。
  Future<void> clearAll() async {
    _cache.clear();
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

  /// Export all history as a JSON-serializable list.
  List<Map<String, dynamic>> exportToJson() {
    final all = <Map<String, dynamic>>[];
    for (final list in _cache.values) {
      all.addAll(list.map((e) => e.toJson()));
    }
    return all;
  }

  /// Import history from a parsed JSON list (merge, dedup by id).
  Future<void> importFromList(List<dynamic> items) async {
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final entry = HistoryEntry.fromJson(item);
      final list =
          _cache.putIfAbsent(entry.sourceType, () => <HistoryEntry>[]);
      if (list.any((e) => e.id == entry.id)) continue;
      list.add(entry);
    }
    await _persist();
    notifyListeners();
  }
}
