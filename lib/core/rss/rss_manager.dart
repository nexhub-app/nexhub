/// RSS 订阅管理器（文档 §10.2）。
///
/// 管理订阅源列表的 CRUD + 持久化，按 [SourceType] 隔离。
/// 抓取和解析通过 [RssParser] + [HttpFetcher] 完成。
/// UI 通过 [ChangeNotifier] 驱动。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../comic/models/reader_preferences.dart';
import '../models/plugin_config.dart';
import '../scraper/http_fetcher.dart';
import 'rss_feed.dart';
import 'rss_parser.dart';

/// RSS 订阅管理器——全应用单例（Provider 注入）。
class RssManager extends ChangeNotifier {
  RssManager({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  final PrefsBackend _backend;
  static const String _key = 'rss_feeds_v1';

  final List<RssFeed> _feeds = [];

  /// 所有订阅源（只读）。
  List<RssFeed> get feeds => List.unmodifiable(_feeds);

  /// 某模块的订阅源。
  List<RssFeed> feedsFor(SourceType? type) {
    if (type == null) return feeds;
    return List.unmodifiable(_feeds.where((f) => f.moduleType == type));
  }

  /// 未绑定模块的订阅源（浏览页全局 RSS）。
  List<RssFeed> get globalFeeds =>
      List.unmodifiable(_feeds.where((f) => f.moduleType == null));

  /// 初始化：加载持久化数据。
  Future<void> init() async {
    final raw = await _backend.get(_key);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _feeds.clear();
        _feeds.addAll(
          list.map((e) => RssFeed.fromJson(e as Map<String, dynamic>)),
        );
      } catch (_) {
        // 损坏数据忽略
      }
    }
    notifyListeners();
  }

  /// 添加订阅源。
  ///
  /// [url] RSS/Atom 链接；[title] 自定义标题（可选，缺省时从 feed 获取）；
  /// [moduleType] 绑定的模块类型（null = 全局浏览页）。
  Future<RssFeed> addFeed({
    required String url,
    String? title,
    String? description,
    SourceType? moduleType,
  }) async {
    final id = feedIdFromUrl(url);

    // 去重
    if (_feeds.any((f) => f.id == id)) return _feeds.firstWhere((f) => f.id == id);

    final feed = RssFeed(
      id: id,
      title: title ?? url,
      url: url,
      description: description,
      moduleType: moduleType,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );

    _feeds.add(feed);
    await _persist();
    notifyListeners();
    return feed;
  }

  /// 移除订阅源。
  Future<void> removeFeed(String id) async {
    _feeds.removeWhere((f) => f.id == id);
    await _persist();
    notifyListeners();
  }

  /// 更新订阅源。
  Future<void> updateFeed(RssFeed updated) async {
    final idx = _feeds.indexWhere((f) => f.id == updated.id);
    if (idx < 0) return;
    _feeds[idx] = updated;
    await _persist();
    notifyListeners();
  }

  /// 抓取并解析订阅源内容。
  Future<ParsedFeed> fetchFeed(RssFeed feed) async {
    final xmlText = await HttpFetcher.instance.getHtml(feed.url);
    return RssParser.parse(xmlText);
  }

  /// 抓取并尝试自动发现 feed 元信息（标题/描述/站点地址）。
  Future<ParsedFeed> discoverFeed(String url) async {
    final xmlText = await HttpFetcher.instance.getHtml(url);
    return RssParser.parse(xmlText);
  }

  /// 测速单个订阅源，返回延迟（毫秒）；失败返回 -1（P8.2.3 §廿二 RSS 一键测速）。
  Future<int> testFeedSpeed(RssFeed feed) async {
    final sw = Stopwatch()..start();
    try {
      await HttpFetcher.instance.getHtml(feed.url);
      sw.stop();
      return sw.elapsedMilliseconds;
    } on Object {
      sw.stop();
      return -1;
    }
  }

  /// 测速全部订阅源，返回 `feedId → 延迟毫秒`（-1 表示失败）。
  /// 每次测速完成后通过 [onProgress] 回调通知 UI 更新（P8.2.3 §廿二）。
  Future<Map<String, int>> testAllFeeds({
    void Function(String feedId, int latencyMs)? onProgress,
  }) async {
    final results = <String, int>{};
    for (final feed in _feeds) {
      final ms = await testFeedSpeed(feed);
      results[feed.id] = ms;
      onProgress?.call(feed.id, ms);
    }
    return results;
  }

  Future<void> _persist() async {
    final list = _feeds.map((f) => f.toJson()).toList();
    await _backend.set(_key, jsonEncode(list));
  }
}
