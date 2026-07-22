/// Tests for [RssUpdateChecker] (P5.2 / 16.13 RSS 更新通知).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/comic/models/reader_preferences.dart';
import 'package:nexhub/core/rss/rss_feed.dart';
import 'package:nexhub/core/rss/rss_manager.dart';
import 'package:nexhub/core/rss/rss_update_checker.dart';

/// Stub RssManager that returns a fixed list of parsed feeds.
class _StubRssManager extends RssManager {
  _StubRssManager({required PrefsBackend backend})
      : super(backend: backend);

  Map<String, ParsedFeed> feedResponses = <String, ParsedFeed>{};

  @override
  Future<ParsedFeed> fetchFeed(RssFeed feed) async {
    final parsed = feedResponses[feed.id];
    if (parsed != null) return parsed;
    throw Exception('No stub response for feed ${feed.id}');
  }
}

RssFeed _makeFeed(String url) => RssFeed(
      id: feedIdFromUrl(url),
      title: 'Feed $url',
      url: url,
      addedAt: 0,
    );

ParsedFeed _makeParsedFeed(List<String> titles) => ParsedFeed(
      title: 'Stub',
      items: titles
          .map((t) => RssItem(
                title: t,
                url: 'https://example.com/$t',
              ))
          .toList(),
    );

void main() {
  group('RssFeedState', () {
    test('default constructor has null fields and zero newCount', () {
      const state = RssFeedState();
      expect(state.lastItemTitle, isNull);
      expect(state.lastCheckedAt, isNull);
      expect(state.newCount, 0);
    });

    test('copyWith updates only specified fields', () {
      const state = RssFeedState(lastItemTitle: 'old');
      final updated = state.copyWith(newCount: 5);
      expect(updated.lastItemTitle, 'old');
      expect(updated.newCount, 5);
    });

    test('toJson/fromJson round-trip preserves all fields', () {
      const original = RssFeedState(
        lastItemTitle: 'title',
        lastCheckedAt: 12345,
        newCount: 3,
      );
      final roundTrip = RssFeedState.fromJson(original.toJson());
      expect(roundTrip.lastItemTitle, 'title');
      expect(roundTrip.lastCheckedAt, 12345);
      expect(roundTrip.newCount, 3);
    });

    test('fromJson backward compat: missing newCount defaults to 0', () {
      final state = RssFeedState.fromJson(const <String, dynamic>{
        'lastItemTitle': 'title',
      });
      expect(state.newCount, 0);
    });
  });

  group('RssUpdateInterval', () {
    test('duration returns correct Duration for each value', () {
      expect(RssUpdateInterval.minutes15.duration.inMinutes, 15);
      expect(RssUpdateInterval.minutes30.duration.inMinutes, 30);
      expect(RssUpdateInterval.hour1.duration.inHours, 1);
      expect(RssUpdateInterval.hours2.duration.inHours, 2);
      expect(RssUpdateInterval.hours4.duration.inHours, 4);
    });

    test('l10nKey returns stable key for each value', () {
      expect(RssUpdateInterval.minutes15.l10nKey, 'interval15m');
      expect(RssUpdateInterval.hour1.l10nKey, 'interval1h');
      expect(RssUpdateInterval.hours4.l10nKey, 'interval4h');
    });
  });

  group('RssUpdateChecker', () {
    late InMemoryBackend backend;
    late _StubRssManager rssManager;

    setUp(() {
      backend = InMemoryBackend();
      rssManager = _StubRssManager(backend: backend);
    });

    test('init with no data yields disabled + default interval', () async {
      final checker = RssUpdateChecker(rssManager: rssManager, backend: backend);
      await checker.init();
      expect(checker.enabled, isFalse);
      expect(checker.interval, RssUpdateInterval.hour1);
      expect(checker.totalNewCount, 0);
    });

    test('first check records latest title without reporting new items',
        () async {
      const url = 'https://example.com/feed1';
      final feed = _makeFeed(url);
      await rssManager.addFeed(url: feed.url, title: feed.title);
      final feedId = feedIdFromUrl(url);
      rssManager.feedResponses[feedId] =
          _makeParsedFeed(<String>['item1', 'item2', 'item3']);

      final checker = RssUpdateChecker(rssManager: rssManager, backend: backend);
      await checker.init();
      await checker.checkAllFeeds();

      expect(checker.newCountFor(feedId), 0);
      expect(checker.states[feedId]?.lastItemTitle, 'item1');
    });

    test('second check with same latest title reports zero new', () async {
      const url = 'https://example.com/feed1';
      final feed = _makeFeed(url);
      await rssManager.addFeed(url: feed.url, title: feed.title);
      final feedId = feedIdFromUrl(url);
      rssManager.feedResponses[feedId] =
          _makeParsedFeed(<String>['item1', 'item2', 'item3']);

      final checker = RssUpdateChecker(rssManager: rssManager, backend: backend);
      await checker.init();
      await checker.checkAllFeeds();
      await checker.checkAllFeeds();

      expect(checker.newCountFor(feedId), 0);
    });

    test('new items detected when latest title changes', () async {
      const url = 'https://example.com/feed1';
      final feed = _makeFeed(url);
      await rssManager.addFeed(url: feed.url, title: feed.title);
      final feedId = feedIdFromUrl(url);
      rssManager.feedResponses[feedId] =
          _makeParsedFeed(<String>['item1', 'item2', 'item3']);

      final checker = RssUpdateChecker(rssManager: rssManager, backend: backend);
      await checker.init();
      await checker.checkAllFeeds();

      // New items added at top
      rssManager.feedResponses[feedId] =
          _makeParsedFeed(<String>['item5', 'item4', 'item1', 'item2', 'item3']);
      await checker.checkAllFeeds();

      expect(checker.newCountFor(feedId), 2);
    });

    test('newCount accumulates across checks', () async {
      const url = 'https://example.com/feed1';
      final feed = _makeFeed(url);
      await rssManager.addFeed(url: feed.url, title: feed.title);
      final feedId = feedIdFromUrl(url);
      rssManager.feedResponses[feedId] =
          _makeParsedFeed(<String>['item1', 'item2', 'item3']);

      final checker = RssUpdateChecker(rssManager: rssManager, backend: backend);
      await checker.init();
      await checker.checkAllFeeds();

      rssManager.feedResponses[feedId] =
          _makeParsedFeed(<String>['item5', 'item4', 'item1', 'item2', 'item3']);
      await checker.checkAllFeeds();
      expect(checker.newCountFor(feedId), 2);

      rssManager.feedResponses[feedId] =
          _makeParsedFeed(<String>['item6', 'item5', 'item4', 'item1', 'item2']);
      await checker.checkAllFeeds();
      expect(checker.newCountFor(feedId), 3); // 2 + 1
    });

    test('markRead clears newCount for a feed', () async {
      const url = 'https://example.com/feed1';
      final feed = _makeFeed(url);
      await rssManager.addFeed(url: feed.url, title: feed.title);
      final feedId = feedIdFromUrl(url);
      rssManager.feedResponses[feedId] =
          _makeParsedFeed(<String>['item1', 'item2']);

      final checker = RssUpdateChecker(rssManager: rssManager, backend: backend);
      await checker.init();
      await checker.checkAllFeeds();

      rssManager.feedResponses[feedId] =
          _makeParsedFeed(<String>['item3', 'item1', 'item2']);
      await checker.checkAllFeeds();
      expect(checker.newCountFor(feedId), 1);

      await checker.markRead(feedId);
      expect(checker.newCountFor(feedId), 0);
    });

    test('totalNewCount sums across all feeds', () async {
      const url1 = 'https://example.com/f1';
      const url2 = 'https://example.com/f2';
      final feed1 = _makeFeed(url1);
      final feed2 = _makeFeed(url2);
      await rssManager.addFeed(url: feed1.url, title: feed1.title);
      await rssManager.addFeed(url: feed2.url, title: feed2.title);
      final id1 = feedIdFromUrl(url1);
      final id2 = feedIdFromUrl(url2);
      rssManager.feedResponses[id1] = _makeParsedFeed(<String>['a1', 'a2']);
      rssManager.feedResponses[id2] = _makeParsedFeed(<String>['b1', 'b2']);

      final checker = RssUpdateChecker(rssManager: rssManager, backend: backend);
      await checker.init();
      await checker.checkAllFeeds();

      // Both first checks → 0 new
      expect(checker.totalNewCount, 0);

      // Add new items to both
      rssManager.feedResponses[id1] =
          _makeParsedFeed(<String>['a3', 'a1', 'a2']);
      rssManager.feedResponses[id2] =
          _makeParsedFeed(<String>['b3', 'b4', 'b1', 'b2']);
      await checker.checkAllFeeds();
      expect(checker.totalNewCount, 3); // 1 + 2
    });

    test('setEnabled persists and toggles timer', () async {
      final checker = RssUpdateChecker(rssManager: rssManager, backend: backend);
      await checker.init();
      expect(checker.enabled, isFalse);

      await checker.setEnabled(true);
      expect(checker.enabled, isTrue);

      await checker.setEnabled(false);
      expect(checker.enabled, isFalse);
    });

    test('setInterval persists and updates interval', () async {
      final checker = RssUpdateChecker(rssManager: rssManager, backend: backend);
      await checker.init();
      expect(checker.interval, RssUpdateInterval.hour1);

      await checker.setInterval(RssUpdateInterval.minutes15);
      expect(checker.interval, RssUpdateInterval.minutes15);
    });

    test('settings persist across instances', () async {
      final checker1 = RssUpdateChecker(rssManager: rssManager, backend: backend);
      await checker1.init();
      await checker1.setEnabled(true);
      await checker1.setInterval(RssUpdateInterval.hours4);

      final rssManager2 = _StubRssManager(backend: backend);
      await rssManager2.init();
      final checker2 =
          RssUpdateChecker(rssManager: rssManager2, backend: backend);
      await checker2.init();

      expect(checker2.enabled, isTrue);
      expect(checker2.interval, RssUpdateInterval.hours4);
    });

    test('feed states persist across instances', () async {
      const url = 'https://example.com/feed1';
      final feed = _makeFeed(url);
      await rssManager.addFeed(url: feed.url, title: feed.title);
      final feedId = feedIdFromUrl(url);
      rssManager.feedResponses[feedId] =
          _makeParsedFeed(<String>['item1', 'item2']);

      final checker1 =
          RssUpdateChecker(rssManager: rssManager, backend: backend);
      await checker1.init();
      await checker1.checkAllFeeds();
      expect(checker1.states[feedId]?.lastItemTitle, 'item1');

      final rssManager2 = _StubRssManager(backend: backend);
      await rssManager2.init();
      // Re-add feed (same URL → same id)
      await rssManager2.addFeed(url: feed.url, title: feed.title);
      rssManager2.feedResponses[feedId] =
          _makeParsedFeed(<String>['item3', 'item1', 'item2']);

      final checker2 =
          RssUpdateChecker(rssManager: rssManager2, backend: backend);
      await checker2.init();
      // After init, state should be loaded from backend
      expect(checker2.states[feedId]?.lastItemTitle, 'item1');

      await checker2.checkAllFeeds();
      // New item 'item3' detected
      expect(checker2.newCountFor(feedId), 1);
    });

    test('onNewItemsDetected callback fires when new items found', () async {
      const url = 'https://example.com/feed1';
      final feed = _makeFeed(url);
      await rssManager.addFeed(url: feed.url, title: feed.title);
      final feedId = feedIdFromUrl(url);
      rssManager.feedResponses[feedId] =
          _makeParsedFeed(<String>['item1', 'item2']);

      var callbackCount = 0;
      final checker = RssUpdateChecker(rssManager: rssManager, backend: backend);
      checker.onNewItemsDetected = () => callbackCount++;
      await checker.init();

      // First check: no callback (first record)
      await checker.checkAllFeeds();
      expect(callbackCount, 0);

      // Second check with new items: callback fires
      rssManager.feedResponses[feedId] =
          _makeParsedFeed(<String>['item3', 'item1', 'item2']);
      await checker.checkAllFeeds();
      expect(callbackCount, 1);
    });

    test('network error does not crash and does not report new items',
        () async {
      const url = 'https://example.com/feed1';
      final feed = _makeFeed(url);
      await rssManager.addFeed(url: feed.url, title: feed.title);
      final feedId = feedIdFromUrl(url);
      // No stub response → fetchFeed throws

      final checker = RssUpdateChecker(rssManager: rssManager, backend: backend);
      await checker.init();
      await checker.checkAllFeeds(); // should not throw

      expect(checker.newCountFor(feedId), 0);
    });

    test('when lastKnown not in current list, all items counted as new',
        () async {
      const url = 'https://example.com/feed1';
      final feed = _makeFeed(url);
      await rssManager.addFeed(url: feed.url, title: feed.title);
      final feedId = feedIdFromUrl(url);
      rssManager.feedResponses[feedId] =
          _makeParsedFeed(<String>['item1', 'item2']);

      final checker = RssUpdateChecker(rssManager: rssManager, backend: backend);
      await checker.init();
      await checker.checkAllFeeds();

      // Source completely replaced items (old title gone)
      rssManager.feedResponses[feedId] =
          _makeParsedFeed(<String>['itemA', 'itemB', 'itemC']);
      await checker.checkAllFeeds();

      expect(checker.newCountFor(feedId), 3);
    });
  });
}
