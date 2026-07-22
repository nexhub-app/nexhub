import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/comic/models/reader_preferences.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/rss/rss_feed.dart';
import 'package:nexhub/core/rss/rss_manager.dart';
import 'package:nexhub/core/rss/rss_parser.dart';

void main() {
  group('RssParser', () {
    test('parses RSS 2.0 feed', () {
      const rssXml = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Test Feed</title>
    <description>A test RSS feed</description>
    <link>https://example.com</link>
    <item>
      <title>Article 1</title>
      <link>https://example.com/article-1</link>
      <description>&lt;p&gt;First article&lt;/p&gt;</description>
      <author>author@example.com</author>
      <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
    </item>
    <item>
      <title>Article 2</title>
      <link>https://example.com/article-2</link>
      <description>Second article description</description>
    </item>
  </channel>
</rss>''';

      final feed = RssParser.parse(rssXml);

      expect(feed.title, 'Test Feed');
      expect(feed.description, 'A test RSS feed');
      expect(feed.siteUrl, 'https://example.com');
      expect(feed.items.length, 2);
      expect(feed.items[0].title, 'Article 1');
      expect(feed.items[0].url, 'https://example.com/article-1');
      expect(feed.items[0].author, 'author@example.com');
      expect(feed.items[0].publishedAt, isNotNull);
      expect(feed.items[1].title, 'Article 2');
    });

    test('parses Atom 1.0 feed', () {
      const atomXml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Atom Test Feed</title>
  <subtitle>An atom test feed</subtitle>
  <link href="https://example.com" rel="alternate"/>
  <link href="https://example.com/feed.xml" rel="self"/>
  <entry>
    <title>Entry 1</title>
    <link href="https://example.com/entry-1" rel="alternate"/>
    <summary>Summary of entry 1</summary>
    <author><name>Test Author</name></author>
    <published>2024-01-15T10:30:00Z</published>
  </entry>
  <entry>
    <title>Entry 2</title>
    <link href="https://example.com/entry-2"/>
    <updated>2024-02-01T12:00:00Z</updated>
  </entry>
</feed>''';

      final feed = RssParser.parse(atomXml);

      expect(feed.title, 'Atom Test Feed');
      expect(feed.description, 'An atom test feed');
      expect(feed.siteUrl, 'https://example.com');
      expect(feed.items.length, 2);
      expect(feed.items[0].title, 'Entry 1');
      expect(feed.items[0].url, 'https://example.com/entry-1');
      expect(feed.items[0].author, 'Test Author');
      expect(feed.items[0].publishedAt, isNotNull);
      expect(feed.items[1].title, 'Entry 2');
    });

    test('extracts cover from HTML in description', () {
      const rssXml = '''<?xml version="1.0"?>
<rss version="2.0">
  <channel>
    <title>Image Feed</title>
    <item>
      <title>Image Article</title>
      <link>https://example.com/img</link>
      <description>&lt;img src="https://example.com/cover.jpg"/&gt;Some text</description>
    </item>
  </channel>
</rss>''';

      final feed = RssParser.parse(rssXml);
      expect(feed.items.length, 1);
      expect(feed.items[0].coverUrl, 'https://example.com/cover.jpg');
    });

    test('throws on unrecognized format', () {
      expect(
        () => RssParser.parse('<unknown><test>data</test></unknown>'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('RssManager', () {
    late InMemoryBackend backend;
    late RssManager manager;

    setUp(() {
      backend = InMemoryBackend();
      manager = RssManager(backend: backend);
    });

    test('addFeed adds feed', () async {
      final feed = await manager.addFeed(
        url: 'https://example.com/feed.xml',
        title: 'Test Feed',
        moduleType: SourceType.novelSource,
      );

      expect(manager.feeds.length, 1);
      expect(manager.feeds.first.title, 'Test Feed');
      expect(manager.feeds.first.url, 'https://example.com/feed.xml');
      expect(feed.id, isNotEmpty);
    });

    test('addFeed deduplicates by URL', () async {
      await manager.addFeed(url: 'https://example.com/feed.xml', title: 'Feed 1');
      await manager.addFeed(url: 'https://example.com/feed.xml', title: 'Feed 2');

      expect(manager.feeds.length, 1);
      expect(manager.feeds.first.title, 'Feed 1');
    });

    test('feedsFor filters by module type', () async {
      await manager.addFeed(
        url: 'https://example.com/novel.xml',
        title: 'Novel Feed',
        moduleType: SourceType.novelSource,
      );
      await manager.addFeed(
        url: 'https://example.com/comic.xml',
        title: 'Comic Feed',
        moduleType: SourceType.mangaSource,
      );
      await manager.addFeed(
        url: 'https://example.com/global.xml',
        title: 'Global Feed',
      );

      expect(manager.feedsFor(SourceType.novelSource).length, 1);
      expect(manager.feedsFor(SourceType.mangaSource).length, 1);
      expect(manager.globalFeeds.length, 1);
      expect(manager.feeds.length, 3);
    });

    test('removeFeed removes by id', () async {
      final feed = await manager.addFeed(
        url: 'https://example.com/feed.xml',
        title: 'Test',
      );
      await manager.removeFeed(feed.id);
      expect(manager.feeds, isEmpty);
    });

    test('updateFeed updates existing', () async {
      final feed = await manager.addFeed(
        url: 'https://example.com/feed.xml',
        title: 'Old Title',
      );
      await manager.updateFeed(feed.copyWith(title: 'New Title'));
      expect(manager.feeds.first.title, 'New Title');
    });

    test('persistence survives re-init', () async {
      await manager.addFeed(
        url: 'https://example.com/feed.xml',
        title: 'Persisted Feed',
        moduleType: SourceType.novelSource,
      );

      final manager2 = RssManager(backend: backend);
      await manager2.init();
      expect(manager2.feeds.length, 1);
      expect(manager2.feeds.first.title, 'Persisted Feed');
    });

    test('feedIdFromUrl generates consistent IDs', () {
      final id1 = feedIdFromUrl('https://example.com/feed.xml');
      final id2 = feedIdFromUrl('https://example.com/feed.xml');
      final id3 = feedIdFromUrl('https://other.com/feed.xml');

      expect(id1, id2);
      expect(id1, isNot(id3));
    });
  });

  group('RssFeed model', () {
    test('JSON round-trip', () {
      const feed = RssFeed(
        id: 'feed_123',
        title: 'Test',
        url: 'https://example.com/feed.xml',
        description: 'A test feed',
        siteUrl: 'https://example.com',
        moduleType: SourceType.novelSource,
        addedAt: 1700000000000,
      );

      final json = feed.toJson();
      final restored = RssFeed.fromJson(json);

      expect(restored.id, feed.id);
      expect(restored.title, feed.title);
      expect(restored.url, feed.url);
      expect(restored.description, feed.description);
      expect(restored.siteUrl, feed.siteUrl);
      expect(restored.moduleType, feed.moduleType);
      expect(restored.addedAt, feed.addedAt);
    });

    test('copyWith creates modified copy', () {
      const feed = RssFeed(
        id: 'feed_123',
        title: 'Original',
        url: 'https://example.com/feed.xml',
        addedAt: 0,
      );
      final modified = feed.copyWith(title: 'Modified');

      expect(modified.title, 'Modified');
      expect(modified.id, feed.id);
      expect(modified.url, feed.url);
    });
  });
}
