// Unit tests for BuiltinResolver HTML path with nested (per-apiName) selectors.
//
// Mirrors the pms_fsdm-style selectors shape: each API (latest / detail /
// episodes / ...) is a sub-map under `selectors.<apiName>` with its own
// `list` / `id` / `title` / `cover` / `url` fields expressed as XPath or
// `css@attr` selectors. The flat legacy shape (`{episodes: "div.chapter a"}`)
// must continue to work for backward compatibility.
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/media_item.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/builtin_resolver.dart';

PluginConfig _source(Map<String, dynamic> selectors) {
  return PluginConfig.fromJson(<String, dynamic>{
    'id': 'pms_fsdm_test',
    'name': 'pms_fsdm_test',
    'type': 'animeSource',
    'responseType': 'html',
    'site': {
      'domain': 'www.example.com',
      'baseUrl': 'https://www.example.com/',
    },
    'parser': {'type': 'xpath'},
    'routes': {
      'latest': '/latest.html',
      'detail': '/detail/{id}.html',
      'episodes': '/detail/{id}.html',
    },
    'selectors': selectors,
  });
}

void main() {
  group('BuiltinResolver HTML - nested selectors (pms_fsdm-style)', () {
    test('latest list: extracts id/title/cover via per-apiName sub-map',
        () async {
      final source = _source(<String, dynamic>{
        'latest': <String, dynamic>{
          'list': "div[@class='item']",
          'id':
              "substring-before(substring-after(./a/@href, '/voddetail/'), '.html')",
          'title': './a/@title',
          'cover': ".//img/@data-src",
        },
      });
      const html = '''
<html><body>
<div class="list">
  <div class="item">
    <a href="/voddetail/123.html" title="某番剧">
      <img data-src="http://x/cover.jpg"/>
    </a>
  </div>
  <div class="item">
    <a href="/voddetail/456.html" title="另一番">
      <img data-src="http://x/cover2.jpg"/>
    </a>
  </div>
</div>
</body></html>
''';
      final r = await const BuiltinResolver().resolveFromHtml(
        source,
        'latest',
        html,
      );
      expect(r, isA<List>());
      final items = r as List;
      expect(items.length, 2);
      expect(items[0].id, '123');
      expect(items[0].title, '某番剧');
      expect(items[0].coverUrl, 'http://x/cover.jpg');
      expect(items[1].id, '456');
      expect(items[1].title, '另一番');
      expect(items[1].coverUrl, 'http://x/cover2.jpg');
    });

    test('episodes: extracts id/title via XPath, url falls back to <a> href',
        () async {
      final source = _source(<String, dynamic>{
        'episodes': <String, dynamic>{
          'list': "//div[@class='playlist']//li/a",
          'id':
              "substring-before(substring-after(./@href, '/vodplay/'), '.html')",
          'title': './text()',
        },
      });
      const html = '''
<html><body>
<div class="playlist">
  <ul>
    <li><a href="/vodplay/123-1.html">第1集</a></li>
    <li><a href="/vodplay/123-2.html">第2集</a></li>
  </ul>
</div>
</body></html>
''';
      final r = await const BuiltinResolver().resolveFromHtml(
        source,
        'episodes',
        html,
      );
      expect(r, isA<List>());
      final eps = r as List;
      expect(eps.length, 2);
      expect(eps[0].id, '123-1');
      expect(eps[0].title, '第1集');
      // `url` selector is not declared -> falls back to <a> href.
      expect(eps[0].url, '/vodplay/123-1.html');
      expect(eps[1].id, '123-2');
      expect(eps[1].title, '第2集');
      expect(eps[1].url, '/vodplay/123-2.html');
    });

    test('flat legacy shape `{episodes: "div.chapter a"}` still works',
        () async {
      final source = _source(<String, dynamic>{
        'episodes': 'div.chapter a',
      });
      const html = '''
<html><body>
<div class="chapter"><a href="/c1">第1话</a></div>
<div class="chapter"><a href="/c2">第2话</a></div>
</body></html>
''';
      final r = await const BuiltinResolver().resolveFromHtml(
        source,
        'episodes',
        html,
      );
      expect(r, isA<List>());
      final eps = r as List;
      expect(eps.length, 2);
      expect(eps[0].title, '第1话');
      expect(eps[0].url, '/c1');
      expect(eps[1].title, '第2话');
      expect(eps[1].url, '/c2');
    });

    test('detail: extracts title/cover/description via per-apiName sub-map',
        () async {
      final source = _source(<String, dynamic>{
        'detail': <String, dynamic>{
          'title': '//h1/text()',
          'cover': "//div[@class='detail-pic']//img/@src",
          'description': "//div[@class='detail-content']",
        },
      });
      const html = '''
<html><body>
<h1>某番剧</h1>
<div class="detail-pic"><img src="http://x/cover.jpg"/></div>
<div class="detail-content">这是某番剧的简介，内容非空。</div>
</body></html>
''';
      final r = await const BuiltinResolver().resolveFromHtml(
        source,
        'detail',
        html,
      );
      expect(r, isA<MediaItem>());
      final item = r as MediaItem;
      expect(item.title, '某番剧');
      expect(item.coverUrl, 'http://x/cover.jpg');
      expect(item.description, isNotEmpty);
    });
  });
}
