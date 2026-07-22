/// 浏览页文章订阅管理器（文档 §10.2，Task 29）。
///
/// 与全局 [RssManager] 数据完全隔离，仅管理浏览页文章订阅源。
/// 持久化 key 为 `'browse_article_feeds_v1'`（与全局 `'rss_feeds_v1'` 互不干扰）。
/// 复用 [RssFeed] / [RssItem] / [ParsedFeed] 模型与 [RssParser] 解析器，
/// 抓取通过 [HttpFetcher] 完成，UI 通过 [ChangeNotifier] 驱动。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../comic/models/reader_preferences.dart';
import '../scraper/http_fetcher.dart';
import 'rss_feed.dart';
import 'rss_parser.dart';

/// 浏览页文章订阅管理器——独立于全局 [RssManager]（Provider 注入）。
///
/// 仅承载浏览页 RSS 入口下的订阅源列表，不与 anime/manga/novel 模块绑定，
/// 也不复用全局 [RssManager] 的存储 key，确保数据隔离。
class BrowseArticleFeedManager extends ChangeNotifier {
  BrowseArticleFeedManager({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  final PrefsBackend _backend;

  /// 持久化 key（与全局 RssManager 隔离）。
  static const String _key = 'browse_article_feeds_v1';

  final List<RssFeed> _feeds = [];

  /// 所有浏览页订阅源（只读）。
  List<RssFeed> get feeds => List.unmodifiable(_feeds);

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
  /// [url] RSS/Atom 链接；[title] 自定义标题（可选，缺省时用 url）；
  /// [description] 自定义描述（可选）。
  /// moduleType 固定为 null（浏览页全局订阅）。
  Future<RssFeed> addFeed({
    required String url,
    String? title,
    String? description,
  }) async {
    final id = feedIdFromUrl(url);

    // 去重：已存在则直接返回原订阅源
    if (_feeds.any((f) => f.id == id)) {
      return _feeds.firstWhere((f) => f.id == id);
    }

    final feed = RssFeed(
      id: id,
      title: title ?? url,
      url: url,
      description: description,
      moduleType: null,
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

  Future<void> _persist() async {
    final list = _feeds.map((f) => f.toJson()).toList();
    await _backend.set(_key, jsonEncode(list));
  }
}
