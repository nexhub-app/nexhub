import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/episode.dart';
import 'package:nexhub/core/models/media_item.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/js_context.dart';
import 'package:nexhub/core/resolver/script_resolver.dart';
import 'package:nexhub/core/resolver/webview_resolver.dart';
import 'package:nexhub/core/scraper/verification_detector.dart';

/// 测试用宿主桥（所有方法返回空桩，run 不依赖真实网络）。
class _StubBridge implements JsHostBridge {
  const _StubBridge();
  @override
  Future<String> httpGet(String url, {Map<String, String>? headers}) async => '';
  @override
  Future<dynamic> httpGetJson(String url, {Map<String, String>? headers}) async => <String, dynamic>{};
  @override
  Future<String> httpPost(String url, String body, {Map<String, String>? headers}) async => '';
  @override
  Future<String> httpPostForm(String url, Map<String, String> params,
      {Map<String, String>? headers}) async => '';
  @override
  String? query(String html, String selector) => null;
  @override
  List<String> queryAll(String html, String selector) => const [];
  @override
  String? queryAttr(String html, String selector, String attr) => null;
  @override
  String? queryXPath(String html, String xpath) => null;
  @override
  String? queryHtml(String html, String selector) => null;
  @override
  String contentClean(String html) => html;
  @override
  String md5(String s) => s;
  @override
  String base64Encode(String s) => s;
  @override
  String base64Decode(String s) => s;
  @override
  String rc4(String data, String key) => data;
  @override
  String aesDecrypt(String cipherBase64, String key, String iv) => '';
  @override
  String resolveUrl(String relative) => relative;
  @override
  void log(String msg) {}

  // ---- crypto extension stubs ----
  @override
  String sha1(String s) => '';
  @override
  String sha256(String s) => '';
  @override
  String sha512(String s) => '';
  @override
  String hmac(String key, String data, {String algorithm = 'sha256'}) => '';
  @override
  String hexEncode(List<int> bytes) => '';
  @override
  List<int> hexDecode(String hex) => const <int>[];
  @override
  String aesEcb(String key, String data,
      {bool encrypt = true, String encoding = 'base64'}) => '';
  @override
  String aesCbc(String key, String data, String iv,
      {bool encrypt = true, String encoding = 'base64'}) => '';
  @override
  String aesCfb(String key, String data, String iv,
      {bool encrypt = true, String encoding = 'base64'}) => '';
  @override
  String aesOfb(String key, String data, String iv,
      {bool encrypt = true, String encoding = 'base64'}) => '';

  // ---- image extension stubs ----
  @override
  List<String> extractImagesFromHtml(String html, {String? selector}) => const [];
  @override
  List<String> extractLazyImagesFromHtml(String html, {String? selector}) => const [];
  @override
  bool isValidImageUrl(String url) => false;
  @override
  String? guessFormat(String url, {List<int>? bytes}) => null;
  @override
  List<String> filterImages(List<String> urls,
      {Map<String, dynamic>? rules}) => const [];
  @override
  List<String> getPageUrls(String html, Map<String, dynamic> config) => const [];

  // ---- storage extension stubs ----
  @override
  String? storageGet(String key) => null;
  @override
  void storageSet(String key, String value) {}
  @override
  void storageRemove(String key) {}

  // ---- http extension stubs ----
  @override
  Future<String> httpPut(String url, String body,
      {Map<String, String>? headers}) async => '';
  @override
  Future<String> httpDelete(String url, {Map<String, String>? headers}) async => '';
  @override
  Future<Map<String, dynamic>> httpFetch(String url,
      {String method = 'GET',
      Map<String, String>? headers,
      String? body}) async => <String, dynamic>{};
  @override
  Future<void> utilsSetTimeout(int ms) async {}
}

/// 可注入的假引擎：直接返回预设数据（或抛错），无需真实 JS 运行时。
class FakeJsEngine implements JsEngine {
  FakeJsEngine(this._data, {this.throws = false});
  final dynamic _data;
  final bool throws;

  @override
  JsHostBridge get bridge => const _StubBridge();

  @override
  Future<dynamic> run(String script, String function, List<dynamic> args) async {
    if (throws) throw Exception('boom');
    return _data;
  }

  @override
  void injectContext(Map<String, String> vars) {}

  @override
  void dispose() {}
}

PluginConfig get _source => PluginConfig.fromJson(<String, dynamic>{
      'id': 'fake', 'name': 'fake', 'type': 'animeSource',
      'site': {'baseUrl': 'https://x.com'},
      'parser': {
        'type': 'script',
        'entrypoints': {'latest': 'parseLatest', 'detail': 'parseDetail'},
        'script': 'function parseLatest(html, context){ return []; }',
      },
      'routes': {'latest': {'url': '/l'}, 'detail': {'url': '/d'}},
    });

void main() {
  group('ScriptResolver', () {
    test('maps list result to List<MediaItem>', () async {
      final resolver = ScriptResolver(
        engineFactory: (_) => FakeJsEngine(<dynamic>[
          {'id': '1', 'title': 'A', 'cover': 'c.png'},
          {'id': '2', 'title': 'B'},
        ]),
      );
      final items = await resolver.resolve(_source, 'latest')
          as List<MediaItem>;
      expect(items.length, 2);
      expect(items.first.title, 'A');
      expect(items.first.coverUrl, 'c.png');
    });

    test('maps detail result to MediaItem', () async {
      final resolver = ScriptResolver(
        engineFactory: (_) => FakeJsEngine(<String, dynamic>{
          'id': '1',
          'title': 'Detail',
          'detail': '/d/1',
        }),
      );
      final item = await resolver.resolve(_source, 'detail') as MediaItem;
      expect(item.title, 'Detail');
      expect(item.detailUrl, '/d/1');
    });

    test('error isolation: engine throws -> SourceResolveException (not crash)', () async {
      final resolver = ScriptResolver(
        engineFactory: (_) => FakeJsEngine(null, throws: true),
      );
      expect(
        () => resolver.resolve(_source, 'latest'),
        throwsA(isA<SourceResolveException>()),
      );
    });

    test('uses hybrid override entrypoint for video', () async {
      final hybridSource = PluginConfig.fromJson(<String, dynamic>{
        'id': 'h', 'name': 'h', 'type': 'animeSource',
        'site': {'baseUrl': 'https://x.com'},
        'parser': {
          'type': 'hybrid',
          'overrides': {
            'video': {'type': 'script', 'entrypoints': {'video': 'parseVideo'}},
          },
        },
        'routes': {'video': {'url': '/v'}},
      });
      var capturedEntry = '';
      final resolver = ScriptResolver(
        engineFactory: (source) => _CapturingEngine(
          (fn) => capturedEntry = fn,
          <String, dynamic>{'url': 'https://v/1', 'type': 'mp4'},
        ),
      );
      final video = await resolver.resolve(hybridSource, 'video') as VideoResult;
      expect(capturedEntry, 'parseVideo');
      expect(video.url, 'https://v/1');
    });

    test('injects route vars into engine context', () async {
      final captured = <String, String>{};
      final resolver = ScriptResolver(
        engineFactory: (_) => _InjectCaptureEngine(captured),
      );
      await resolver.resolve(_source, 'latest',
          vars: <String, String>{'page': '2', 'category': 'kr'});
      expect(captured['page'], '2');
      expect(captured['category'], 'kr');
    });

    test('useWebview short-circuit: resolve throws WebViewHtmlRequest without executing script', () async {
      final useWebviewSource = PluginConfig.fromJson(<String, dynamic>{
        'id': 'uwv', 'name': 'uwv', 'type': 'mangaSource',
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
      var factoryCalled = false;
      final resolver = ScriptResolver(
        engineFactory: (_) {
          factoryCalled = true;
          return FakeJsEngine(<dynamic>[]);
        },
      );
      await expectLater(
        resolver.resolve(useWebviewSource, 'latest'),
        throwsA(isA<WebViewHtmlRequest>()),
      );
      // Engine factory must NOT be called (script must NOT execute).
      expect(factoryCalled, isFalse);
    });

    test('resolveFromHtml passes rendered HTML as raw to script entry', () async {
      final capturedArgs = <dynamic>[];
      final resolver = ScriptResolver(
        engineFactory: (_) => _ArgsCaptureEngine(
          capturedArgs,
          <dynamic>[
            {'id': '1', 'title': 'A', 'cover': 'c.png'},
          ],
        ),
      );
      final items = await resolver.resolveFromHtml(
        _source,
        'latest',
        '<html>rendered</html>',
      ) as List<MediaItem>;
      expect(items.length, 1);
      expect(items.first.title, 'A');
      expect(items.first.coverUrl, 'c.png');
      // Verify HTML was passed as the raw argument (single-arg unwrapped).
      expect(capturedArgs.length, 1);
      expect(capturedArgs.first, '<html>rendered</html>');
    });

    test('resolveFromHtml does not trigger WebViewHtmlRequest for useWebview source', () async {
      // resolveFromHtml is the post-render reentry point: it MUST NOT re-throw
      // WebViewHtmlRequest (would cause infinite loop). Verifies that even when
      // source.useWebview==true, resolveFromHtml executes the script directly.
      final useWebviewSource = PluginConfig.fromJson(<String, dynamic>{
        'id': 'uwv2', 'name': 'uwv2', 'type': 'mangaSource',
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
      final resolver = ScriptResolver(
        engineFactory: (_) => FakeJsEngine(<dynamic>[
          {'id': '1', 'title': 'Rendered'},
        ]),
      );
      final items = await resolver.resolveFromHtml(
        useWebviewSource,
        'latest',
        '<html>rendered</html>',
      ) as List<MediaItem>;
      expect(items.length, 1);
      expect(items.first.title, 'Rendered');
    });
  });
}

/// 捕获被调用函数名的假引擎。
class _CapturingEngine implements JsEngine {
  _CapturingEngine(this._onRun, this._data);
  final void Function(String fn) _onRun;
  final dynamic _data;

  @override
  JsHostBridge get bridge => const _StubBridge();

  @override
  Future<dynamic> run(String script, String function, List<dynamic> args) async {
    _onRun(function);
    return _data;
  }

  @override
  void injectContext(Map<String, String> vars) {}

  @override
  void dispose() {}
}

/// 记录 injectContext 入参的假引擎（验证路由层 vars 已注入 JS context）。
class _InjectCaptureEngine implements JsEngine {
  _InjectCaptureEngine(this._captured);
  final Map<String, String> _captured;

  @override
  JsHostBridge get bridge => const _StubBridge();

  @override
  Future<dynamic> run(String script, String function, List<dynamic> args) async =>
      <dynamic>[];

  @override
  void injectContext(Map<String, String> vars) => _captured.addAll(vars);

  @override
  void dispose() {}
}

/// 捕获传给脚本入口的 raw 参数（验证 resolveFromHtml 透传 HTML）。
class _ArgsCaptureEngine implements JsEngine {
  _ArgsCaptureEngine(this._captured, this._data);
  final List<dynamic> _captured;
  final dynamic _data;

  @override
  JsHostBridge get bridge => const _StubBridge();

  @override
  Future<dynamic> run(String script, String function, List<dynamic> args) async {
    _captured.addAll(args);
    return _data;
  }

  @override
  void injectContext(Map<String, String> vars) {}

  @override
  void dispose() {}
}
