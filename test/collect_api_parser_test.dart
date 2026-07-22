import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/scraper/collect_api_parser.dart';

void main() {
  final source = PluginConfig.fromJson({
    'id': 'test_collect',
    'name': 'Test Collect',
    'type': 'animeSource',
    'site': {'domain': 'https://example.com', 'baseUrl': 'https://example.com'},
    'parser': {'type': 'builtin'},
    'routes': {
      'latest': {'url': '/api.php/provide/vod/?ac=list&pg={page}'},
    },
  });

  group('CollectApiParser', () {
    test('looksLikeCollectApi identifies ac endpoints', () {
      expect(CollectApiParser.looksLikeCollectApi('/?ac=list'), isTrue);
      expect(CollectApiParser.looksLikeCollectApi('/?ac=videolist'), isTrue);
      expect(CollectApiParser.looksLikeCollectApi('/?ac=detail'), isTrue);
      expect(CollectApiParser.looksLikeCollectApi('/search'), isFalse);
    });

    test('parseList extracts MediaItem list', () {
      final json = {
        'list': [
          {
            'vod_id': '1',
            'vod_name': 'Test Anime',
            'vod_pic': 'https://example.com/cover.jpg',
            'vod_content': 'A test anime.',
            'vod_director': 'Director',
            'vod_actor': 'Actor A,Actor B',
            'vod_remarks': '连载中',
            'vod_year': '2026',
            'vod_tag': '动作,科幻',
            'vod_time': '2026-07-12 10:00:00',
          },
        ],
      };
      final items = CollectApiParser.parseList(json, source);
      expect(items, hasLength(1));
      final item = items.first;
      expect(item.id, '1');
      expect(item.title, 'Test Anime');
      expect(item.coverUrl, 'https://example.com/cover.jpg');
      expect(item.tags, containsAll(<String>['动作', '科幻']));
      expect(item.director, 'Director');
      expect(item.status, '连载中');
    });

    test('splitPlayLines splits vod_play_from and vod_play_url', () {
      const from = '线路一\$\$\$线路二';
      const url = '第1集\$https://a.com/1.m3u8#第2集\$https://a.com/2.m3u8'
          '\$\$\$'
          '第1集\$https://b.com/1.mp4';
      final episodes = CollectApiParser.splitPlayLines(from, url);
      expect(episodes, hasLength(3));
      expect(episodes.where((e) => e.lineName == '线路一'), hasLength(2));
      expect(episodes.where((e) => e.lineName == '线路二'), hasLength(1));
      expect(episodes.first.url, 'https://a.com/1.m3u8');
    });

    test('parseCategories extracts class entries', () {
      final json = {
        'class': [
          {'type_id': '1', 'type_name': '电影'},
          {'type_id': '2', 'type_name': '电视剧'},
        ],
      };
      final cats = CollectApiParser.parseCategories(json);
      expect(cats, hasLength(2));
      expect(cats.first.id, '1');
      expect(cats.first.title, '电影');
    });
  });
}
