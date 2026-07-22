/// RSS / Atom XML 解析器（文档 §10.2）。
///
/// 支持 RSS 2.0 和 Atom 1.0 两种主流格式。
/// 使用 `xml` 包解析 XML，提取 feed 元信息和条目列表。
library;

import 'package:xml/xml.dart';

import 'rss_feed.dart';

/// 解析 RSS/Atom XML 文本为 [ParsedFeed]。
class RssParser {
  /// 解析 XML 文本。
  ///
  /// 自动检测 RSS 2.0（根 <rss>）或 Atom（根 <feed>）。
  static ParsedFeed parse(String xmlText) {
    final doc = XmlDocument.parse(xmlText);
    final root = doc.rootElement;

    if (root.name.local == 'rss') {
      return _parseRss2(root);
    } else if (root.name.local == 'feed') {
      return _parseAtom(root);
    }

    // 尝试 RSS 2.0 降级
    final channel = root.findElements('channel').firstOrNull;
    if (channel != null) return _parseRss2(channel);

    throw FormatException('Unrecognized feed format: root <${root.name}>');
  }

  // ── RSS 2.0 ──────────────────────────────────────────

  static ParsedFeed _parseRss2(XmlElement rss) {
    final channel = rss.findElements('channel').firstOrNull ?? rss;

    final title = _text(channel, 'title') ?? 'Untitled Feed';
    final description = _text(channel, 'description');
    final siteUrl = _text(channel, 'link');
    final iconUrl = _text(channel, 'image', child: 'url');

    final items = <RssItem>[];
    for (final item in channel.findElements('item')) {
      items.add(RssItem.fromXml(_itemFields(item)));
    }

    return ParsedFeed(
      title: title,
      description: description,
      siteUrl: siteUrl,
      iconUrl: iconUrl,
      items: items,
    );
  }

  static Map<String, String> _itemFields(XmlElement item) {
    final fields = <String, String>{};
    for (final child in item.children.whereType<XmlElement>()) {
      final tag = child.name.local;
      // 处理带命名空间的标签如 dc:creator
      final fullTag = child.name.qualified;
      if (!fields.containsKey(tag)) {
        fields[tag] = child.innerText.trim();
      }
      if (fullTag != tag && !fields.containsKey(fullTag)) {
        fields[fullTag] = child.innerText.trim();
      }
    }
    return fields;
  }

  // ── Atom 1.0 ─────────────────────────────────────────

  static ParsedFeed _parseAtom(XmlElement feed) {
    final title = _text(feed, 'title') ?? 'Untitled Feed';
    final subtitle = _text(feed, 'subtitle');

    // Atom link 有 rel 属性，alternate 为站点地址
    String? siteUrl;
    for (final link in feed.findElements('link')) {
      final rel = link.getAttribute('rel');
      if (rel == null || rel == 'alternate') {
        siteUrl = link.getAttribute('href');
        break;
      }
    }

    final iconUrl = _text(feed, 'icon') ?? _text(feed, 'logo');

    final items = <RssItem>[];
    for (final entry in feed.findElements('entry')) {
      items.add(_atomEntryToItem(entry));
    }

    return ParsedFeed(
      title: title,
      description: subtitle,
      siteUrl: siteUrl,
      iconUrl: iconUrl,
      items: items,
    );
  }

  static RssItem _atomEntryToItem(XmlElement entry) {
    final title = _text(entry, 'title') ?? '';
    String? link;
    for (final l in entry.findElements('link')) {
      final rel = l.getAttribute('rel');
      if (rel == null || rel == 'alternate') {
        link = l.getAttribute('href');
        break;
      }
    }
    final summary = _text(entry, 'summary') ?? _text(entry, 'content');
    final author = _text(entry, 'author', child: 'name') ?? _text(entry, 'author');
    final published = _text(entry, 'published') ?? _text(entry, 'updated');

    return RssItem(
      title: title,
      url: link ?? '',
      description: summary,
      author: author,
      publishedAt: published != null ? _tryParseDate(published) : null,
      coverUrl: RssItem.extractCoverFromHtml(summary ?? ''),
    );
  }

  // ── 辅助方法 ──────────────────────────────────────────

  static String? _text(XmlElement parent, String tag, {String? child}) {
    final el = parent.findElements(tag).firstOrNull;
    if (el == null) return null;
    if (child != null) {
      final childEl = el.findElements(child).firstOrNull;
      return childEl?.innerText.trim();
    }
    return el.innerText.trim();
  }

  static DateTime? _tryParseDate(String raw) {
    try {
      return DateTime.parse(raw.trim());
    } catch (_) {
      return null;
    }
  }
}
