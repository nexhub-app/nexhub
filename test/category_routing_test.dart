import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/category_entry.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/resolver_registry.dart';
import 'package:nexhub/core/scraper/media_api_service.dart';

/// 路由选择 + 分类读取的单元验证（对应五大关键问题修复）。
///
/// 覆盖：
/// - [MediaApiService.routeForCategory] 的优先级逻辑；
/// - [MediaApiService.fetchCategories] 读取 `selectors.category.categories`
///   （goda 式静态分类）与书源 `selectors.xiaoshuo.exploreUrl`（biquge 式）
///   两条无网络路径；以及 `selectors.category.dynamicCategories` 在无采集
///   路由时安全回退为空列表（不触发网络）。
void main() {
  group('MediaApiService.routeForCategory', () {
    final withCategoryRoute = PluginConfig.fromJson(<String, dynamic>{
      'id': 'a',
      'name': 'a',
      'type': 'animeSource',
      'site': {'baseUrl': 'https://x.com'},
      'parser': {'type': 'hybrid'},
      'routes': {
        'latest': {'url': '/l'},
        'category': {'url': '/c/{category}'},
        'explore': {'url': '/e'},
      },
    });

    final withExploreOnly = PluginConfig.fromJson(<String, dynamic>{
      'id': 'n',
      'name': 'n',
      'type': 'novelSource',
      'site': {'baseUrl': 'https://x.com'},
      'parser': {'type': 'builtin'},
      'routes': {
        'latest': {'url': '/l'},
        'explore': {'url': '/e'},
      },
    });

    final latestOnly = PluginConfig.fromJson(<String, dynamic>{
      'id': 'l',
      'name': 'l',
      'type': 'animeSource',
      'site': {'baseUrl': 'https://x.com'},
      'parser': {'type': 'hybrid'},
      'routes': {'latest': {'url': '/l'}},
    });

    test('home (category=null) always uses latest', () {
      expect(MediaApiService.routeForCategory(withCategoryRoute, null), 'latest');
      expect(MediaApiService.routeForCategory(withExploreOnly, null), 'latest');
      expect(MediaApiService.routeForCategory(latestOnly, null), 'latest');
    });

    test('non-empty category prefers category route', () {
      expect(
        MediaApiService.routeForCategory(withCategoryRoute, '1'),
        'category',
      );
    });

    test('non-empty category falls back to explore when no category route', () {
      expect(
        MediaApiService.routeForCategory(withExploreOnly, 'https://x.com/c'),
        'explore',
      );
    });

    test('empty category string is treated as no category', () {
      expect(MediaApiService.routeForCategory(withCategoryRoute, ''), 'latest');
    });

    test('category with no category/explore route stays on latest', () {
      expect(MediaApiService.routeForCategory(latestOnly, 'x'), 'latest');
    });
  });

  group('MediaApiService.fetchCategories', () {
    final service = MediaApiService(ResolverRegistry.instance);

    test('reads selectors.category.categories (goda-style)', () async {
      final source = PluginConfig.fromJson(<String, dynamic>{
        'id': 'goda',
        'name': 'goda',
        'type': 'mangaSource',
        'site': {'baseUrl': 'https://godamh.com'},
        'parser': {'type': 'hybrid'},
        'routes': {
          'latest': {'url': '/'},
          'category': {'url': '{category}/page/{page}'},
        },
        'selectors': {
          'category': {
            'categories': [
              {'id': '', 'name': '全部'},
              {'id': 'kr', 'name': '韩漫'},
              {'id': 'cn', 'name': '国漫'},
            ],
          },
        },
      });
      final cats = await service.fetchCategories(source);
      expect(cats, hasLength(3));
      expect(cats[0].id, '');
      expect(cats[0].title, '全部');
      expect(cats[1].id, 'kr');
      expect(cats[1].title, '韩漫');
      expect(cats[2].id, 'cn');
      expect(cats[2].title, '国漫');
    });

    test('parses shuyuan exploreUrl (biquge-style)', () async {
      final source = PluginConfig.fromJson(<String, dynamic>{
        'id': 'xiaoshuo_bqg',
        'name': '笔趣阁',
        'type': 'novelSource',
        'site': {'baseUrl': 'https://m.biqubu3.com'},
        'parser': {'type': 'builtin'},
        'routes': {
          'latest': {'url': ''},
          'explore': {'url': ''},
        },
        'selectors': {
          'xiaoshuo': {
            'exploreUrl':
                '玄幻小说::https://m.biqubu3.com/xuanhuan/\n修真小说::https://m.biqubu3.com/xiuzhen/',
          },
        },
      });
      final cats = await service.fetchCategories(source);
      expect(cats, hasLength(2));
      expect(cats[0].id, 'https://m.biqubu3.com/xuanhuan/');
      expect(cats[0].title, '玄幻小说');
      expect(cats[1].id, 'https://m.biqubu3.com/xiuzhen/');
      expect(cats[1].title, '修真小说');
    });

    test('dynamicCategories with no collect route safely returns empty',
        () async {
      final source = PluginConfig.fromJson(<String, dynamic>{
        'id': 'dyn',
        'name': 'dyn',
        'type': 'animeSource',
        'site': {'baseUrl': 'https://x.com'},
        'parser': {'type': 'hybrid'},
        'routes': {
          'latest': {'url': '/l'}, // 非 ac=list 采集路由
        },
        'selectors': {
          'category': {'dynamicCategories': true},
        },
      });
      final cats = await service.fetchCategories(source);
      expect(cats, isEmpty);
    });

    test('falls back to top-level categoryEntries when selectors absent',
        () async {
      final source = PluginConfig.fromJson(<String, dynamic>{
        'id': 'top',
        'name': 'top',
        'type': 'animeSource',
        'site': {'baseUrl': 'https://x.com'},
        'parser': {'type': 'hybrid'},
        'routes': {'latest': {'url': '/l'}},
        'category': {
          'categoryEntries': [
            {'id': '1', 'title': '动作'},
          ],
        },
      });
      final cats = await service.fetchCategories(source);
      expect(cats, hasLength(1));
      expect(cats[0].id, '1');
      expect(cats[0].title, '动作');
    });
  });
}
