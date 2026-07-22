import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';

PluginConfig build(Map<String, dynamic> json) => PluginConfig.fromJson(json);

void main() {
  group('PluginConfig', () {
    test('parses animeSource MacCMS config', () {
      final source = build(<String, dynamic>{
        'id': 'pms_example',
        'name': '示例影视源',
        'type': 'animeSource',
        'responseType': 'json',
        'site': {
          'domain': 'https://example.com',
          'baseUrl': 'https://example.com',
        },
        'parser': {'type': 'builtin'},
        'routes': {
          'latest': {'url': '/api.php/provide/vod/?ac=list&pg={page}'},
          'search': {'url': '/api.php/provide/vod/?ac=list&wd={keyword}'},
        },
      });
      expect(source.id, 'pms_example');
      expect(source.type, SourceType.animeSource);
      expect(source.validate(), isEmpty);
    });

    test('detects source type for mangaSource / novelSource', () {
      expect(
        build(<String, dynamic>{
          'id': 'm', 'name': 'm', 'type': 'mangaSource',
          'site': {'baseUrl': 'https://x.com'}, 'parser': {'type': 'builtin'},
        }).type,
        SourceType.mangaSource,
      );
      expect(
        build(<String, dynamic>{
          'id': 'n', 'name': 'n', 'type': 'novelSource',
          'site': {'baseUrl': 'https://x.com'}, 'parser': {'type': 'builtin'},
        }).type,
        SourceType.novelSource,
      );
    });

    test('validate flags missing id and baseUrl', () {
      final source = build(<String, dynamic>{
        'name': 'bad',
        'type': 'animeSource',
        'site': {'baseUrl': ''},
        'parser': {'type': 'builtin'},
      });
      final errors = source.validate();
      expect(errors, contains('missing: id'));
      expect(errors, contains('missing: site.baseUrl'));
    });

    test('resolveRouteUrl fills baseUrl and vars', () {
      final source = build(<String, dynamic>{
        'id': 'pms_example',
        'name': '示例',
        'type': 'animeSource',
        'site': {'baseUrl': 'https://example.com'},
        'parser': {'type': 'builtin'},
        'routes': {
          'search': {'url': '/api.php/provide/vod/?ac=list&wd={keyword}&pg={page}'},
        },
      });
      final url = source.resolveRouteUrl(
        'search',
        activeBaseUrl: 'https://example.com',
        vars: <String, String>{'keyword': 'naruto', 'page': '2'},
      );
      expect(
        url,
        'https://example.com/api.php/provide/vod/?ac=list&wd=naruto&pg=2',
      );
    });

    test('responseTypeFor falls back to top-level', () {
      final source = build(<String, dynamic>{
        'id': 'p', 'name': 'p', 'type': 'animeSource',
        'responseType': 'json',
        'site': {'baseUrl': 'https://x.com'},
        'parser': {'type': 'builtin'},
        'routes': {'latest': {'url': '/l'}},
      });
      expect(source.responseTypeFor('latest'), 'json');
    });
  });
}
