import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:nexhub/core/danmaku/bilibili_danmaku_service.dart';
import 'package:nexhub/core/danmaku/danmaku_repository.dart';
import 'package:nexhub/core/danmaku/danmaku_source.dart';
import 'package:nexhub/core/danmaku/dandanplay_matcher.dart';
import 'package:nexhub/core/danmaku/dandanplay_service.dart';
import 'package:nexhub/core/models/episode.dart';
import 'package:nexhub/core/models/media_item.dart';
import 'package:nexhub/core/settings/danmaku_config.dart';

// ---- Fakes ----

/// 可控的弹弹play 服务替身（绕过真实网络/配置）。
class _FakeDandanplay extends DandanplayService {
  _FakeDandanplay({
    this.available = true,
    this.searchResults = const <DanmakuSearchResult>[],
    this.episodes = const <DanmakuEpisode>[],
    this.comments = const <ParsedDanmakuItem>[],
    this.throwOnComments = false,
  }) : super(configStore: DanmakuConfigStore());

  final bool available;
  final List<DanmakuSearchResult> searchResults;
  final List<DanmakuEpisode> episodes;
  final List<ParsedDanmakuItem> comments;
  final bool throwOnComments;

  @override
  bool get isAvailable => available;

  @override
  Future<void> refreshAvailability() async {}

  @override
  Future<List<DanmakuSearchResult>> search(String keyword) async =>
      searchResults;

  @override
  Future<List<DanmakuEpisode>> getEpisodes(String animeId) async => episodes;

  @override
  Future<List<ParsedDanmakuItem>> getComments(String episodeId) async {
    if (throwOnComments) throw Exception('network error');
    return comments;
  }
}

/// 可控的 Bilibili 服务替身。
class _FakeBilibili extends BilibiliDanmakuService {
  _FakeBilibili({
    this.comments = const <ParsedDanmakuItem>[],
  }) : super();

  final List<ParsedDanmakuItem> comments;

  @override
  Future<List<ParsedDanmakuItem>> getComments(String cid) async {
    return comments;
  }
}

/// 内存 Box 替身（仅实现 get/put，其余走 noSuchMethod）。
class _FakeBox implements Box<dynamic> {
  final Map<String, dynamic> _data = <String, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) {
    final k = key?.toString() ?? '';
    return _data.containsKey(k) ? _data[k] : defaultValue;
  }

  @override
  Future<void> put(dynamic key, dynamic value) async {
    _data[key.toString()] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const Color _white = Color(0xFFFFFFFF);

List<ParsedDanmakuItem> _items(String prefix, int count) => [
      for (int i = 0; i < count; i++)
        ParsedDanmakuItem(text: '$prefix-$i', time: i.toDouble(), color: _white),
    ];

void main() {
  // ===== Episode 模型序列化 =====
  group('Episode serialization', () {
    test('toJson / fromJson round-trip with danmaku fields', () {
      const ep = Episode(
        id: 'e1',
        title: '第1集',
        url: '/play/e1',
        lineName: '线路一',
        dandanplayEpisodeId: 12345,
        bilibiliCid: 67890,
        bangumiId: 111,
      );
      final json = ep.toJson();
      expect(json['dandanplayEpisodeId'], 12345);
      expect(json['bilibiliCid'], 67890);
      expect(json['bangumiId'], 111);

      final restored = Episode.fromJson(json);
      expect(restored.dandanplayEpisodeId, 12345);
      expect(restored.bilibiliCid, 67890);
      expect(restored.bangumiId, 111);
      expect(restored.id, 'e1');
      expect(restored.title, '第1集');
      expect(restored.lineName, '线路一');
    });

    test('toJson omits null danmaku fields', () {
      const ep = Episode(id: 'e1', title: 't', url: 'u');
      final json = ep.toJson();
      expect(json.containsKey('dandanplayEpisodeId'), isFalse);
      expect(json.containsKey('bilibiliCid'), isFalse);
      expect(json.containsKey('bangumiId'), isFalse);
    });

    test('fromJson tolerates missing danmaku fields', () {
      final ep = Episode.fromJson(<String, dynamic>{
        'id': 'e2',
        'title': 't',
        'url': 'u',
      });
      expect(ep.dandanplayEpisodeId, isNull);
      expect(ep.bilibiliCid, isNull);
      expect(ep.bangumiId, isNull);
    });

    test('copyWith fills dandanplayEpisodeId', () {
      const ep = Episode(id: 'e1', title: 't', url: 'u');
      final updated = ep.copyWith(dandanplayEpisodeId: 999);
      expect(updated.dandanplayEpisodeId, 999);
      expect(updated.id, 'e1');
      // 原实例不变
      expect(ep.dandanplayEpisodeId, isNull);
    });

    test('constructor backward compatible (no danmaku args)', () {
      const ep = Episode(id: 'e1', title: 't', url: 'u', lineName: 'L');
      expect(ep.dandanplayEpisodeId, isNull);
      expect(ep.bilibiliCid, isNull);
      expect(ep.bangumiId, isNull);
      expect(ep.id, 'e1');
    });

    test('toJson omits danmakuUrl when null', () {
      const ep = Episode(id: 'e1', title: 't', url: 'u');
      final json = ep.toJson();
      expect(json.containsKey('danmakuUrl'), isFalse);
    });

    test('toJson/fromJson round-trip with danmakuUrl', () {
      const ep = Episode(
        id: 'e1',
        title: 't',
        url: 'u',
        danmakuUrl: 'https://example.com/d.xml',
      );
      final json = ep.toJson();
      expect(json['danmakuUrl'], 'https://example.com/d.xml');
      final restored = Episode.fromJson(json);
      expect(restored.danmakuUrl, 'https://example.com/d.xml');
    });

    test('fromJson tolerates missing danmakuUrl', () {
      final ep = Episode.fromJson(<String, dynamic>{
        'id': 'e2',
        'title': 't',
        'url': 'u',
      });
      expect(ep.danmakuUrl, isNull);
    });

    test('copyWith fills danmakuUrl', () {
      const ep = Episode(id: 'e1', title: 't', url: 'u');
      final updated = ep.copyWith(danmakuUrl: 'https://example.com/d.xml');
      expect(updated.danmakuUrl, 'https://example.com/d.xml');
      expect(ep.danmakuUrl, isNull);
    });
  });

  // ===== MediaItem bangumiId =====
  group('MediaItem bangumiId', () {
    test('copyWith fills bangumiId', () {
      const item = MediaItem(id: 'm1', title: 'T');
      final updated = item.copyWith(bangumiId: 42);
      expect(updated.bangumiId, 42);
      expect(updated.id, 'm1');
    });

    test('constructor accepts bangumiId', () {
      const item = MediaItem(id: 'm1', title: 'T', bangumiId: 7);
      expect(item.bangumiId, 7);
    });
  });

  // ===== DanmakuRepository 优先级回退 =====
  group('DanmakuRepository fallback', () {
    late _FakeDandanplay dandan;
    late _FakeBilibili bilibili;
    late _FakeBox cacheBox;
    late DanmakuRepository repo;

    setUp(() {
      dandan = _FakeDandanplay();
      bilibili = _FakeBilibili();
      cacheBox = _FakeBox();
      repo = DanmakuRepository(
        dandanplay: dandan,
        bilibili: bilibili,
        cacheBox: cacheBox,
      );
    });

    test('dandanplay success returns its comments and writes cache', () async {
      dandan = _FakeDandanplay(
        available: true,
        comments: _items('dd', 3),
      );
      repo = DanmakuRepository(
          dandanplay: dandan, bilibili: bilibili, cacheBox: cacheBox);

      final result = await repo.getDanmaku(
        sourceId: 's1',
        episodeId: 'e1',
        dandanplayEpisodeId: 123,
      );
      expect(result.length, 3);
      expect(result.first.text, 'dd-0');

      // 缓存已写入
      final cached = cacheBox.get('s1:e1');
      expect(cached, isNotNull);
    });

    test('falls back to bilibili when dandanplay empty', () async {
      dandan = _FakeDandanplay(available: true, comments: const []);
      bilibili = _FakeBilibili(comments: _items('bili', 2));
      repo = DanmakuRepository(
          dandanplay: dandan, bilibili: bilibili, cacheBox: cacheBox);

      final result = await repo.getDanmaku(
        sourceId: 's1',
        episodeId: 'e1',
        dandanplayEpisodeId: 123,
        bilibiliCid: 456,
      );
      expect(result.length, 2);
      expect(result.first.text, 'bili-0');
    });

    test('falls back to bilibili when dandanplay throws', () async {
      dandan = _FakeDandanplay(
        available: true,
        throwOnComments: true,
        comments: _items('dd', 5),
      );
      bilibili = _FakeBilibili(comments: _items('bili', 2));
      repo = DanmakuRepository(
          dandanplay: dandan, bilibili: bilibili, cacheBox: cacheBox);

      final result = await repo.getDanmaku(
        sourceId: 's1',
        episodeId: 'e1',
        dandanplayEpisodeId: 123,
        bilibiliCid: 456,
      );
      expect(result.length, 2);
      expect(result.first.text, 'bili-0');
    });

    test('falls back to cache when both sources empty', () async {
      // 先写入缓存
      cacheBox.put('s1:e1',
          '[{"text":"cached-0","time":0.0,"color":4294967295,"mode":0,"fontSize":16.0}]');

      dandan = _FakeDandanplay(available: false);
      bilibili = _FakeBilibili(comments: const []);
      repo = DanmakuRepository(
          dandanplay: dandan, bilibili: bilibili, cacheBox: cacheBox);

      final result = await repo.getDanmaku(
        sourceId: 's1',
        episodeId: 'e1',
      );
      expect(result.length, 1);
      expect(result.first.text, 'cached-0');
    });

    test('returns empty when all sources fail and no cache', () async {
      dandan = _FakeDandanplay(available: false);
      repo = DanmakuRepository(
          dandanplay: dandan, bilibili: bilibili, cacheBox: cacheBox);

      final result = await repo.getDanmaku(
        sourceId: 's1',
        episodeId: 'e1',
      );
      expect(result, isEmpty);
    });

    test('dandanplay unavailable skips dandanplay, uses bilibili', () async {
      dandan = _FakeDandanplay(available: false, comments: _items('dd', 10));
      bilibili = _FakeBilibili(comments: _items('bili', 1));
      repo = DanmakuRepository(
          dandanplay: dandan, bilibili: bilibili, cacheBox: cacheBox);

      final result = await repo.getDanmaku(
        sourceId: 's1',
        episodeId: 'e1',
        dandanplayEpisodeId: 123,
        bilibiliCid: 456,
      );
      expect(result.length, 1);
      expect(result.first.text, 'bili-0');
    });
  });

  // ===== DanmakuRepository danmakuUrl 直链通道 =====
  group('DanmakuRepository danmakuUrl', () {
    late _FakeDandanplay dandan;
    late _FakeBilibili bilibili;
    late _FakeBox cacheBox;

    setUp(() {
      dandan = _FakeDandanplay();
      bilibili = _FakeBilibili();
      cacheBox = _FakeBox();
    });

    test('danmakuUrl takes priority over dandanplay/bilibili (XML)', () async {
      dandan = _FakeDandanplay(available: true, comments: _items('dd', 3));
      bilibili = _FakeBilibili(comments: _items('bili', 2));
      final repo = DanmakuRepository(
        dandanplay: dandan,
        bilibili: bilibili,
        cacheBox: cacheBox,
        urlFetcher: (_) async => '<i>'
            '<d p="1.5,1,25,16777215,0,0,user,1">hello</d>'
            '<d p="2.0,4,25,16711680,0,0,user,2">world</d>'
            '</i>',
      );
      final result = await repo.getDanmaku(
        sourceId: 's1',
        episodeId: 'e1',
        dandanplayEpisodeId: 123,
        bilibiliCid: 456,
        danmakuUrl: 'https://example.com/d.xml',
      );
      expect(result.length, 2);
      expect(result[0].text, 'hello');
      expect(result[0].time, 1.5);
      expect(result[1].text, 'world');
      expect(result[1].mode, DanmakuMode.bottom); // mode 4 = bottom
    });

    test('danmakuUrl fetch throws -> falls back to dandanplay', () async {
      dandan = _FakeDandanplay(available: true, comments: _items('dd', 2));
      bilibili = _FakeBilibili(comments: _items('bili', 5));
      final repo = DanmakuRepository(
        dandanplay: dandan,
        bilibili: bilibili,
        cacheBox: cacheBox,
        urlFetcher: (_) async => throw Exception('network error'),
      );
      final result = await repo.getDanmaku(
        sourceId: 's1',
        episodeId: 'e1',
        dandanplayEpisodeId: 123,
        bilibiliCid: 456,
        danmakuUrl: 'https://example.com/d.xml',
      );
      expect(result.length, 2);
      expect(result.first.text, 'dd-0');
    });

    test('danmakuUrl empty body -> falls back to bilibili', () async {
      dandan = _FakeDandanplay(available: true, comments: const []);
      bilibili = _FakeBilibili(comments: _items('bili', 3));
      final repo = DanmakuRepository(
        dandanplay: dandan,
        bilibili: bilibili,
        cacheBox: cacheBox,
        urlFetcher: (_) async => '',
      );
      final result = await repo.getDanmaku(
        sourceId: 's1',
        episodeId: 'e1',
        dandanplayEpisodeId: 123,
        bilibiliCid: 456,
        danmakuUrl: 'https://example.com/d.xml',
      );
      expect(result.length, 3);
      expect(result.first.text, 'bili-0');
    });

    test('danmakuUrl null keeps original dandanplay behavior', () async {
      dandan = _FakeDandanplay(available: true, comments: _items('dd', 2));
      bilibili = _FakeBilibili(comments: _items('bili', 5));
      final repo = DanmakuRepository(
        dandanplay: dandan,
        bilibili: bilibili,
        cacheBox: cacheBox,
        urlFetcher: (_) async =>
            '<i><d p="0,1,25,16777215,0,0,u,1">should-not-use</d></i>',
      );
      final result = await repo.getDanmaku(
        sourceId: 's1',
        episodeId: 'e1',
        dandanplayEpisodeId: 123,
      );
      expect(result.length, 2);
      expect(result.first.text, 'dd-0');
    });

    test('danmakuUrl parses JSON format', () async {
      final repo = DanmakuRepository(
        dandanplay: dandan,
        bilibili: bilibili,
        cacheBox: cacheBox,
        urlFetcher: (_) async => '{"danmaku":['
            '{"text":"a","time":0.5,"color":16777215,"mode":1},'
            '{"text":"b","time":1.0,"color":16711680,"mode":5}'
            ']}',
      );
      final result = await repo.getDanmaku(
        sourceId: 's1',
        episodeId: 'e1',
        danmakuUrl: 'https://example.com/d.json',
      );
      expect(result.length, 2);
      expect(result[0].text, 'a');
      expect(result[0].time, 0.5);
      expect(result[1].text, 'b');
      expect(result[1].mode, DanmakuMode.top); // mode 5 = top
    });

    test('danmakuUrl success writes cache', () async {
      final repo = DanmakuRepository(
        dandanplay: dandan,
        bilibili: bilibili,
        cacheBox: cacheBox,
        urlFetcher: (_) async =>
            '<i><d p="0,1,25,16777215,0,0,u,1">cached</d></i>',
      );
      await repo.getDanmaku(
        sourceId: 's1',
        episodeId: 'e1',
        danmakuUrl: 'https://example.com/d.xml',
      );
      expect(cacheBox.get('s1:e1'), isNotNull);
    });
  });

  // ===== DandanplayMatcher =====
  group('DandanplayMatcher', () {
    test('matches by episode number extracted from title', () async {
      final dandan = _FakeDandanplay(
        available: true,
        searchResults: const [
          DanmakuSearchResult(animeId: '1', title: 'Test Anime'),
        ],
        episodes: const [
          DanmakuEpisode(episodeId: '101', title: '第1话', episodeNumber: 1),
          DanmakuEpisode(episodeId: '102', title: '第2话', episodeNumber: 2),
          DanmakuEpisode(episodeId: '103', title: '第3话', episodeNumber: 3),
        ],
      );
      final matcher = DandanplayMatcher(dandanplay: dandan);

      final eps = <Episode>[
        const Episode(id: 'a', title: '第1集', url: 'u1'),
        const Episode(id: 'b', title: '第2集', url: 'u2'),
        const Episode(id: 'c', title: '第3集', url: 'u3'),
      ];
      final map = await matcher.matchEpisodes('Test Anime', eps);
      expect(map.length, 3);
      expect(map[0], 101);
      expect(map[1], 102);
      expect(map[2], 103);
    });

    test('returns empty when dandanplay unavailable', () async {
      final dandan = _FakeDandanplay(available: false);
      final matcher = DandanplayMatcher(dandanplay: dandan);
      final map = await matcher.matchEpisodes('X', [
        const Episode(id: 'a', title: '第1集', url: 'u'),
      ]);
      expect(map, isEmpty);
    });

    test('returns empty when search yields no results', () async {
      final dandan = _FakeDandanplay(
        available: true,
        searchResults: const [],
      );
      final matcher = DandanplayMatcher(dandanplay: dandan);
      final map = await matcher.matchEpisodes('Unknown', [
        const Episode(id: 'a', title: '第1集', url: 'u'),
      ]);
      expect(map, isEmpty);
    });

    test('returns empty on network error (silent)', () async {
      // search 抛异常，模拟网络错误
      final broken = _ThrowingDandanplay();
      final matcher = DandanplayMatcher(dandanplay: broken);
      final map = await matcher.matchEpisodes('X', [
        const Episode(id: 'a', title: '第1集', url: 'u'),
      ]);
      expect(map, isEmpty);
    });

    test('falls back to sequential match when no episode numbers', () async {
      final dandan = _FakeDandanplay(
        available: true,
        searchResults: const [
          DanmakuSearchResult(animeId: '1', title: 'Test'),
        ],
        episodes: const [
          DanmakuEpisode(episodeId: '201', title: 'Ep1'),
          DanmakuEpisode(episodeId: '202', title: 'Ep2'),
        ],
      );
      final matcher = DandanplayMatcher(dandanplay: dandan);
      final eps = <Episode>[
        const Episode(id: 'a', title: '第一话', url: 'u1'),
        const Episode(id: 'b', title: '第二话', url: 'u2'),
      ];
      final map = await matcher.matchEpisodes('Test', eps);
      expect(map.length, 2);
      expect(map[0], 201);
      expect(map[1], 202);
    });
  });
}

/// 搜索时抛异常的弹弹play 替身（模拟网络错误）。
class _ThrowingDandanplay extends DandanplayService {
  _ThrowingDandanplay() : super(configStore: DanmakuConfigStore());

  @override
  bool get isAvailable => true;

  @override
  Future<void> refreshAvailability() async {}

  @override
  Future<List<DanmakuSearchResult>> search(String keyword) async {
    throw Exception('network error');
  }
}
