/// RSS 订阅源与条目模型（文档 §10.2）。
///
/// 支持 RSS 2.0 和 Atom 两种主流格式。
library;

import 'dart:convert';

import '../models/plugin_config.dart';

/// RSS 订阅源配置。
class RssFeed {
  final String id;
  final String title;
  final String url;
  final String? description;
  final String? siteUrl;
  final String? iconUrl;
  final SourceType? moduleType;
  final int addedAt;

  const RssFeed({
    required this.id,
    required this.title,
    required this.url,
    this.description,
    this.siteUrl,
    this.iconUrl,
    this.moduleType,
    required this.addedAt,
  });

  RssFeed copyWith({
    String? title,
    String? url,
    String? description,
    String? siteUrl,
    String? iconUrl,
    SourceType? moduleType,
  }) =>
      RssFeed(
        id: id,
        title: title ?? this.title,
        url: url ?? this.url,
        description: description ?? this.description,
        siteUrl: siteUrl ?? this.siteUrl,
        iconUrl: iconUrl ?? this.iconUrl,
        moduleType: moduleType ?? this.moduleType,
        addedAt: addedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'url': url,
        'description': description,
        'siteUrl': siteUrl,
        'iconUrl': iconUrl,
        'moduleType': moduleType?.apiName,
        'addedAt': addedAt,
      };

  factory RssFeed.fromJson(Map<String, dynamic> json) => RssFeed(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
        description: json['description'] as String?,
        siteUrl: json['siteUrl'] as String?,
        iconUrl: json['iconUrl'] as String?,
        moduleType: SourceType.parse(json['moduleType'] as String?),
        addedAt: json['addedAt'] as int? ?? 0,
      );
}

/// RSS 条目（单篇文章 / 更新通知）。
class RssItem {
  final String title;
  final String url;
  final String? description;
  final String? author;
  final DateTime? publishedAt;
  final String? coverUrl;
  final String? content;

  const RssItem({
    required this.title,
    required this.url,
    this.description,
    this.author,
    this.publishedAt,
    this.coverUrl,
    this.content,
  });

  /// 从 RSS 2.0 <item> 解析。
  factory RssItem.fromXml(Map<String, String> fields) {
    DateTime? published;
    final dateStr = fields['pubDate'];
    if (dateStr != null) {
      published = _parseDate(dateStr);
    }

    return RssItem(
      title: fields['title'] ?? '',
      url: fields['link'] ?? '',
      description: fields['description'],
      author: fields['author'] ?? fields['dc:creator'],
      publishedAt: published,
      content: fields['content:encoded'] ?? fields['encoded'],
      coverUrl: extractCoverFromHtml(fields['content:encoded'] ??
          fields['encoded'] ??
          fields['description'] ??
          ''),
    );
  }

  /// 解析 RFC 822（RSS 2.0）和 ISO 8601（Atom）日期。
  static DateTime? _parseDate(String raw) {
    // 尝试 ISO 8601（Atom 格式）
    try {
      return DateTime.parse(raw);
    } catch (_) {
      // 继续尝试 RFC 822
    }

    // RFC 822: "Sat, 07 Sep 2002 09:42:31 GMT"
    try {
      final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
      // 移除星期前缀 "Sat, "
      final withoutDay = cleaned.contains(',')
          ? cleaned.substring(cleaned.indexOf(',') + 2)
          : cleaned;
      final parts = withoutDay.split(' ');
      if (parts.length >= 5) {
        final day = parts[0].padLeft(2, '0');
        final month = _monthToInt(parts[1]);
        final year = parts[2].length == 2 ? '20${parts[2]}' : parts[2];
        final time = parts[3];
        final tz = parts[4];
        final iso = '$year-$month-${day}T$time${_tzToIso(tz)}';
        return DateTime.parse(iso);
      }
    } catch (_) {
      // 忽略
    }
    return null;
  }

  static String _monthToInt(String month) {
    const months = <String, String>{
      'Jan': '01', 'Feb': '02', 'Mar': '03', 'Apr': '04',
      'May': '05', 'Jun': '06', 'Jul': '07', 'Aug': '08',
      'Sep': '09', 'Oct': '10', 'Nov': '11', 'Dec': '12',
    };
    return months[month] ?? '01';
  }

  static String _tzToIso(String tz) {
    if (tz == 'GMT' || tz == 'UTC') return 'Z';
    if (tz.startsWith('+') || tz.startsWith('-')) {
      final sign = tz.substring(0, 1);
      final rest = tz.substring(1);
      if (rest.length == 4) {
        return '$sign${rest.substring(0, 2)}:${rest.substring(2)}';
      }
    }
    return 'Z'; // 默认 UTC
  }

  /// 从 description 中提取第一张图片作为封面。
  static String? extractCoverFromHtml(String html) {
    final imgMatch = RegExp(
            r"""<img[^>]+src=["']([^"']+)["']""",
            caseSensitive: false)
        .firstMatch(html);
    return imgMatch?.group(1);
  }
}

/// RSS 解析后的结果。
class ParsedFeed {
  final String title;
  final String? description;
  final String? siteUrl;
  final String? iconUrl;
  final List<RssItem> items;

  const ParsedFeed({
    required this.title,
    this.description,
    this.siteUrl,
    this.iconUrl,
    required this.items,
  });
}

/// 从 [ParsedFeed] 生成 feed ID（URL 的简单哈希）。
String feedIdFromUrl(String url) {
  final bytes = utf8.encode(url);
  final digest = bytes.fold<int>(0, (prev, b) => (prev * 31 + b) & 0x7FFFFFFF);
  return 'feed_$digest';
}
