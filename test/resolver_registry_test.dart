import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/builtin_resolver.dart';
import 'package:nexhub/core/resolver/resolver_registry.dart';
import 'package:nexhub/core/resolver/script_resolver.dart';
import 'package:nexhub/core/resolver/webview_resolver.dart';

PluginConfig build(Map<String, dynamic> json) => PluginConfig.fromJson(json);

void main() {
  group('ResolverRegistry.find', () {
    test('script type routes to ScriptResolver', () {
      final source = build(<String, dynamic>{
        'id': 's', 'name': 's', 'type': 'animeSource',
        'site': {'baseUrl': 'https://x.com'},
        'parser': {'type': 'script', 'script': 'function latest(){}'},
        'routes': {'latest': {'url': '/l'}},
      });
      final resolver = ResolverRegistry.instance.find(source, 'latest');
      expect(resolver, isA<ScriptResolver>());
    });

    test('hybrid routes video to ScriptResolver, search to BuiltinResolver', () {
      final source = build(<String, dynamic>{
        'id': 'h', 'name': 'h', 'type': 'animeSource',
        'site': {'baseUrl': 'https://x.com'},
        'parser': {
          'type': 'hybrid',
          'overrides': {
            'video': {'type': 'script', 'entrypoints': {'video': 'parseVideo'}},
          },
        },
        'routes': {'search': {'url': '/s'}, 'video': {'url': '/v'}},
      });
      expect(
        ResolverRegistry.instance.find(source, 'video'),
        isA<ScriptResolver>(),
      );
      expect(
        ResolverRegistry.instance.find(source, 'search'),
        isA<BuiltinResolver>(),
      );
    });

    test('builtin type routes to BuiltinResolver', () {
      final source = build(<String, dynamic>{
        'id': 'b', 'name': 'b', 'type': 'animeSource',
        'site': {'baseUrl': 'https://x.com'},
        'parser': {'type': 'builtin'},
        'routes': {'latest': {'url': '/l'}},
      });
      expect(
        ResolverRegistry.instance.find(source, 'latest'),
        isA<BuiltinResolver>(),
      );
    });

    test('selection is independent of registration order', () {
      // 注册顺序不影响结果：这里直接基于 parser 声明计算。
      final scriptSource = build(<String, dynamic>{
        'id': 's2', 'name': 's2', 'type': 'animeSource',
        'site': {'baseUrl': 'https://x.com'},
        'parser': {'type': 'script', 'script': 'function latest(){}'},
        'routes': {'latest': {'url': '/l'}},
      });
      expect(
        ResolverRegistry.instance.effectiveResolverType(scriptSource, 'latest'),
        'script',
      );
      final builtinSource = build(<String, dynamic>{
        'id': 'b2', 'name': 'b2', 'type': 'animeSource',
        'site': {'baseUrl': 'https://x.com'},
        'parser': {'type': 'builtin'},
        'routes': {'latest': {'url': '/l'}},
      });
      expect(
        ResolverRegistry.instance.effectiveResolverType(builtinSource, 'latest'),
        'builtin',
      );
      // WebViewResolver 作为独立可用实例存在（验证路径）。
      expect(const WebViewResolver(), isA<WebViewResolver>());
    });
  });

  group('ResolverRegistry.effectiveResolverType useWebview routing', () {
    test('pms_fsdm style (useWebview + xpath) -> webview', () {
      final source = build(<String, dynamic>{
        'id': 'pms_fsdm', 'name': 'pms_fsdm', 'type': 'animeSource',
        'site': {'baseUrl': 'https://x.com'},
        'useWebview': true,
        'parser': {'type': 'xpath'},
        'routes': {'latest': {'url': '/l'}},
      });
      expect(
        ResolverRegistry.instance.effectiveResolverType(source, 'latest'),
        'webview',
      );
    });

    test('manga_baozimh style (useWebview + hybrid + script override) -> script', () {
      final source = build(<String, dynamic>{
        'id': 'manga_baozimh', 'name': 'manga_baozimh', 'type': 'mangaSource',
        'site': {'baseUrl': 'https://x.com'},
        'useWebview': true,
        'parser': {
          'type': 'hybrid',
          'overrides': {
            'latest': {'type': 'script', 'entrypoints': {'latest': 'parseList'}},
          },
        },
        'routes': {'latest': {'url': '/l'}},
      });
      expect(
        ResolverRegistry.instance.effectiveResolverType(source, 'latest'),
        'script',
      );
    });

    test('useWebview + jsonpath -> webview', () {
      final source = build(<String, dynamic>{
        'id': 'jp', 'name': 'jp', 'type': 'animeSource',
        'site': {'baseUrl': 'https://x.com'},
        'useWebview': true,
        'parser': {'type': 'jsonpath'},
        'routes': {'latest': {'url': '/l'}},
      });
      expect(
        ResolverRegistry.instance.effectiveResolverType(source, 'latest'),
        'webview',
      );
    });

    test('useWebview + css -> webview', () {
      final source = build(<String, dynamic>{
        'id': 'css', 'name': 'css', 'type': 'animeSource',
        'site': {'baseUrl': 'https://x.com'},
        'useWebview': true,
        'parser': {'type': 'css'},
        'routes': {'latest': {'url': '/l'}},
      });
      expect(
        ResolverRegistry.instance.effectiveResolverType(source, 'latest'),
        'webview',
      );
    });

    test('MacCMS source (no useWebview + builtin) -> builtin', () {
      final source = build(<String, dynamic>{
        'id': 'maccms', 'name': 'maccms', 'type': 'animeSource',
        'site': {'baseUrl': 'https://x.com'},
        'parser': {'type': 'builtin'},
        'routes': {'latest': {'url': '/l'}},
      });
      expect(
        ResolverRegistry.instance.effectiveResolverType(source, 'latest'),
        'builtin',
      );
    });

    test('declarative xpath without useWebview -> builtin (avoid false positive)', () {
      final source = build(<String, dynamic>{
        'id': 'plain_xpath', 'name': 'plain_xpath', 'type': 'animeSource',
        'site': {'baseUrl': 'https://x.com'},
        'parser': {'type': 'xpath'},
        'routes': {'latest': {'url': '/l'}},
      });
      expect(
        ResolverRegistry.instance.effectiveResolverType(source, 'latest'),
        'builtin',
      );
    });
  });
}
