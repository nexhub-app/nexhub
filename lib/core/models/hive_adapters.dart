library;

import 'package:hive/hive.dart';
import 'package:nexhub/core/models/episode.dart';
import 'package:nexhub/core/models/media_item.dart';
import 'package:nexhub/core/models/plugin_config.dart';

part 'hive_adapters.g.dart';

@HiveType(typeId: 0)
class HiveMediaItem {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  @HiveField(2)
  final String? coverUrl;
  @HiveField(3)
  final String? detailUrl;
  @HiveField(4)
  final String? sourceId;
  @HiveField(5)
  final String? sourceType;
  @HiveField(6)
  final String? description;
  @HiveField(7)
  final String? author;
  @HiveField(8)
  final String? director;
  @HiveField(9)
  final String? actors;
  @HiveField(10)
  final String? year;
  @HiveField(11)
  final List<String>? tags;
  @HiveField(12)
  final String? status;
  @HiveField(13)
  final int? updatedAt;
  @HiveField(14)
  final Map<String, dynamic>? extra;
  @HiveField(15)
  final String? wordCount;
  @HiveField(16)
  final String? authorUrl;
  @HiveField(17)
  final List<String>? tagUrls;

  HiveMediaItem({
    required this.id,
    required this.title,
    this.coverUrl,
    this.detailUrl,
    this.sourceId,
    this.sourceType,
    this.description,
    this.author,
    this.director,
    this.actors,
    this.year,
    this.tags,
    this.status,
    this.updatedAt,
    this.extra,
    this.wordCount,
    this.authorUrl,
    this.tagUrls,
  });

  factory HiveMediaItem.fromMediaItem(MediaItem item) => HiveMediaItem(
        id: item.id,
        title: item.title,
        coverUrl: item.coverUrl,
        detailUrl: item.detailUrl,
        sourceId: item.sourceId,
        sourceType: item.sourceType?.apiName,
        description: item.description,
        author: item.author,
        director: item.director,
        actors: item.actors,
        year: item.year,
        tags: item.tags,
        status: item.status,
        updatedAt: item.updatedAt?.millisecondsSinceEpoch,
        extra: item.extra,
        wordCount: item.wordCount,
        authorUrl: item.authorUrl,
        tagUrls: item.tagUrls,
      );

  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: title,
        coverUrl: coverUrl,
        detailUrl: detailUrl,
        sourceId: sourceId,
        sourceType: SourceType.parse(sourceType),
        description: description,
        author: author,
        director: director,
        actors: actors,
        year: year,
        tags: tags,
        status: status,
        updatedAt: updatedAt != null ? DateTime.fromMillisecondsSinceEpoch(updatedAt!) : null,
        extra: extra,
        wordCount: wordCount,
        authorUrl: authorUrl,
        tagUrls: tagUrls,
      );
}

@HiveType(typeId: 1)
class HiveEpisode {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  @HiveField(2)
  final String url;
  @HiveField(3)
  final String? lineName;

  HiveEpisode({
    required this.id,
    required this.title,
    required this.url,
    this.lineName,
  });

  factory HiveEpisode.fromEpisode(Episode episode) => HiveEpisode(
        id: episode.id,
        title: episode.title,
        url: episode.url,
        lineName: episode.lineName,
      );

  Episode toEpisode() => Episode(
        id: id,
        title: title,
        url: url,
        lineName: lineName,
      );
}

@HiveType(typeId: 2)
class HivePluginConfig {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final String type;
  @HiveField(3)
  final String? responseType;
  @HiveField(4)
  final bool useWebview;
  @HiveField(5)
  final Map<String, dynamic> site;
  @HiveField(6)
  final Map<String, dynamic> parser;
  @HiveField(7)
  final Map<String, dynamic> routes;
  @HiveField(8)
  final Map<String, dynamic>? selectors;
  @HiveField(9)
  final Map<String, dynamic>? category;
  @HiveField(10)
  final bool stealthMode;
  @HiveField(11)
  final Map<String, dynamic>? antiHotlinking;
  @HiveField(12)
  final Map<String, dynamic>? webviewConfig;
  @HiveField(13)
  final bool deprecated;
  @HiveField(14)
  final bool enabled;
  @HiveField(15)
  final bool enabledExplore;
  @HiveField(16)
  final String? migrationMessage;
  @HiveField(17)
  final String? engine;

  HivePluginConfig({
    required this.id,
    required this.name,
    required this.type,
    this.responseType,
    this.useWebview = false,
    required this.site,
    required this.parser,
    required this.routes,
    this.selectors,
    this.category,
    this.stealthMode = true,
    this.antiHotlinking,
    this.webviewConfig,
    this.deprecated = false,
    this.enabled = true,
    this.enabledExplore = true,
    this.migrationMessage,
    this.engine,
  });

  factory HivePluginConfig.fromPluginConfig(PluginConfig config) => HivePluginConfig(
        id: config.id,
        name: config.name,
        type: config.type.apiName,
        responseType: config.responseType,
        useWebview: config.useWebview,
        site: config.site.toJson(),
        parser: config.parser.toJson(),
        routes: config.routes.map((k, v) => MapEntry(k, v.toJson())),
        selectors: config.selectors,
        category: config.category.toJson(),
        stealthMode: config.stealthMode,
        antiHotlinking: config.antiHotlinking.referer != null ? {'referer': config.antiHotlinking.referer} : null,
        webviewConfig: {
          'adblock': config.webviewConfig.adblock,
          'timeoutSeconds': config.webviewConfig.timeoutSeconds,
        },
        deprecated: config.deprecated,
        enabled: config.enabled,
        enabledExplore: config.enabledExplore,
        migrationMessage: config.migrationMessage,
        engine: config.engine,
      );

  PluginConfig toPluginConfig() => PluginConfig.fromJson({
        'id': id,
        'name': name,
        'type': type,
        'responseType': responseType,
        'useWebview': useWebview,
        'site': site,
        'parser': parser,
        'routes': routes,
        'selectors': selectors,
        'category': category,
        'stealthMode': stealthMode,
        'antiHotlinking': antiHotlinking,
        'webviewConfig': webviewConfig,
        'deprecated': deprecated,
        'enabled': enabled,
        'enabledExplore': enabledExplore,
        'migrationMessage': migrationMessage,
        'engine': engine,
      });
}

@HiveType(typeId: 3)
class HiveReadingProgress {
  @HiveField(0)
  final String itemId;
  @HiveField(1)
  final String? chapterId;
  @HiveField(2)
  final int currentPage;
  @HiveField(3)
  final int? lastReadChapterIndex;
  @HiveField(4)
  final int? totalChapters;
  @HiveField(5)
  final int updatedAt;

  HiveReadingProgress({
    required this.itemId,
    this.chapterId,
    required this.currentPage,
    this.lastReadChapterIndex,
    this.totalChapters,
    required this.updatedAt,
  });
}

@HiveType(typeId: 4)
class HiveFavorite {
  @HiveField(0)
  final String itemId;
  @HiveField(1)
  final String type;
  @HiveField(2)
  final String title;
  @HiveField(3)
  final String? coverUrl;
  @HiveField(4)
  final String? sourceId;
  @HiveField(5)
  final int dateAdded;
  @HiveField(6)
  final int? lastReadAt;
  @HiveField(7)
  final Map<String, dynamic>? extra;

  HiveFavorite({
    required this.itemId,
    required this.type,
    required this.title,
    this.coverUrl,
    this.sourceId,
    required this.dateAdded,
    this.lastReadAt,
    this.extra,
  });
}

@HiveType(typeId: 5)
class HiveDownloadTask {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String type;
  @HiveField(2)
  final String itemId;
  @HiveField(3)
  final String title;
  @HiveField(4)
  final String? coverUrl;
  @HiveField(5)
  final String? sourceId;
  @HiveField(6)
  final String? localPath;
  @HiveField(7)
  final int status;
  @HiveField(8)
  final int progress;
  @HiveField(9)
  final int totalSize;
  @HiveField(10)
  final int downloadedSize;
  @HiveField(11)
  final List<String> chapters;
  @HiveField(12)
  final int dateAdded;
  @HiveField(13)
  final int? completedAt;
  @HiveField(14)
  final Map<String, dynamic>? extra;

  HiveDownloadTask({
    required this.id,
    required this.type,
    required this.itemId,
    required this.title,
    this.coverUrl,
    this.sourceId,
    this.localPath,
    required this.status,
    required this.progress,
    required this.totalSize,
    required this.downloadedSize,
    required this.chapters,
    required this.dateAdded,
    this.completedAt,
    this.extra,
  });
}

@HiveType(typeId: 6)
class HiveDanmakuCache {
  @HiveField(0)
  final String key;
  @HiveField(1)
  final String content;
  @HiveField(2)
  final int cachedAt;
  @HiveField(3)
  final int ttl;

  HiveDanmakuCache({
    required this.key,
    required this.content,
    required this.cachedAt,
    required this.ttl,
  });
}

@HiveType(typeId: 7)
class HiveRssFeed {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  @HiveField(2)
  final String url;
  @HiveField(3)
  final String? iconUrl;
  @HiveField(4)
  final bool enabled;
  @HiveField(5)
  final int dateAdded;
  @HiveField(6)
  final int? lastUpdated;
  @HiveField(7)
  final int? unreadCount;
  @HiveField(8)
  final Map<String, dynamic>? extra;

  HiveRssFeed({
    required this.id,
    required this.title,
    required this.url,
    this.iconUrl,
    this.enabled = true,
    required this.dateAdded,
    this.lastUpdated,
    this.unreadCount,
    this.extra,
  });
}

@HiveType(typeId: 8)
class HiveSettings {
  @HiveField(0)
  final String key;
  @HiveField(1)
  final dynamic value;
  @HiveField(2)
  final int updatedAt;

  HiveSettings({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
}