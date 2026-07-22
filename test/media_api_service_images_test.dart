import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/js_context.dart';
import 'package:nexhub/core/resolver/resolver_registry.dart';
import 'package:nexhub/core/resolver/script_resolver.dart';
import 'package:nexhub/core/scraper/media_api_service.dart';

Future<HttpServer> _startServer(Map<String, String> routes) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    final body = routes[req.uri.path];
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(body ?? '{}');
    req.response.close();
  });
  return server;
}

/// 测试用宿主桥（所有方法返回空桩，不依赖真实网络/IO）。
class _StubBridge implements JsHostBridge {
  const _StubBridge();
  @override
  Future<String> httpGet(String url, {Map<String, String>? headers}) async => '';
  @override
  Future<dynamic> httpGetJson(String url, {Map<String, String>? headers}) async =>
      <String, dynamic>{};
  @override
  Future<String> httpPost(String url, String body,
      {Map<String, String>? headers}) async => '';
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
  @override
  List<String> extractImagesFromHtml(String html, {String? selector}) => const [];
  @override
  List<String> extractLazyImagesFromHtml(String html, {String? selector}) =>
      const [];
  @override
  bool isValidImageUrl(String url) => false;
  @override
  String? guessFormat(String url, {List<int>? bytes}) => null;
  @override
  List<String> filterImages(List<String> urls,
      {Map<String, dynamic>? rules}) => const [];
  @override
  List<String> getPageUrls(String html, Map<String, dynamic> config) => const [];
  @override
  String? storageGet(String key) => null;
  @override
  void storageSet(String key, String value) {}
  @override
  void storageRemove(String key) {}
  @override
  Future<String> httpPut(String url, String body,
      {Map<String, String>? headers}) async => '';
  @override
  Future<String> httpDelete(String url, {Map<String, String>? headers}) async =>
      '';
  @override
  Future<Map<String, dynamic>> httpFetch(String url,
      {String method = 'GET',
      Map<String, String>? headers,
      String? body}) async => <String, dynamic>{};
  @override
  Future<void> utilsSetTimeout(int ms) async {}
}

/// 捕获 `engine.run(script, function, args)` 入参的假引擎，返回预设数据。
///
/// 用于验证 `ScriptResolver.resolveFromHtml` 是否把回灌的 HTML 作为 `raw`
/// （即 `args[0]`）传给脚本入口函数。
class _ArgsCapturingEngine implements JsEngine {
  _ArgsCapturingEngine(this._onRun, this._data);
  final void Function(String fn, List<dynamic> args) _onRun;
  final dynamic _data;

  @override
  JsHostBridge get bridge => const _StubBridge();

  @override
  Future<dynamic> run(String script, String function, List<dynamic> args) async {
    _onRun(function, args);
    return _data;
  }

  @override
  void injectContext(Map<String, String> vars) {}

  @override
  void dispose() {}
}

void main() {
  late HttpServer server;
  late String base;
  late MediaApiService service;

  setUp(() async {
    server = await _startServer(<String, String>{
      '/chapters': '{"list":[{"id":"c1","title":"第1话","url":"/c1"},{"id":"c2","title":"第2话","url":"/c2"}]}',
      '/images': '{"images":["https://x/p1.jpg","https://x/p2.jpg"]}',
    });
    base = 'http://${server.address.host}:${server.port}';
    service = MediaApiService(ResolverRegistry.instance);
  });

  tearDown(() => server.close(force: true));

  test('fetchChapters delegates to builtin', () async {
    final source = PluginConfig.fromJson(<String, dynamic>{
      'id': 's', 'name': 'S', 'type': 'mangaSource', 'responseType': 'json',
      'site': {'domain': base, 'baseUrl': base},
      'parser': {'type': 'builtin'},
      'routes': {'chapters': '/chapters', 'images': '/images?cid={cid}'},
      'selectors': {
        'chapters': {'list': '\$.list', 'id': 'id', 'title': 'title', 'url': 'url'},
        'images': '\$.images',
      },
    });
    final chapters = await service.fetchChapters(source, 'm1');
    expect(chapters.length, 2);
    expect(chapters.first.title, '第1话');
    expect(chapters.first.id, 'c1');
  });

  test('fetchImages delegates to builtin', () async {
    final source = PluginConfig.fromJson(<String, dynamic>{
      'id': 's', 'name': 'S', 'type': 'mangaSource', 'responseType': 'json',
      'site': {'domain': base, 'baseUrl': base},
      'parser': {'type': 'builtin'},
      'routes': {'chapters': '/chapters', 'images': '/images?cid={cid}'},
      'selectors': {
        'chapters': {'list': '\$.list', 'id': 'id', 'title': 'title', 'url': 'url'},
        'images': '\$.images',
      },
    });
    final images = await service.fetchImages(source, comicId: 'm1', chapterId: 'c1');
    expect(images, <String>['https://x/p1.jpg', 'https://x/p2.jpg']);
  });

  group('renderedHtml dispatch (Task 4.4)', () {
    test('hybrid+script+useWebview source routes renderedHtml to ScriptResolver with HTML as raw', () async {
      // 参考 manga_baozimh 配置：parser.type=hybrid + overrides[latest].type=script + useWebview=true。
      final capturedFn = <String>[];
      final capturedArgs = <List<dynamic>>[];
      final resolver = ScriptResolver(
        engineFactory: (_) => _ArgsCapturingEngine(
          (fn, args) {
            capturedFn.add(fn);
            capturedArgs.add(List<dynamic>.from(args));
          },
          <dynamic>[
            <String, dynamic>{
              'id': '/manga/abc',
              'title': 'Test Manga',
              'cover': 'https://x/cover.png',
              'detailUrl': 'https://m.baozimh.one/manga/abc',
            },
          ],
        ),
      );
      final localService = MediaApiService(
        ResolverRegistry.instance,
        scriptResolver: resolver,
      );
      final source = PluginConfig.fromJson(<String, dynamic>{
        'id': 'manga_baozimh_test',
        'name': 'Bun Manga Test',
        'type': 'mangaSource',
        'responseType': 'html',
        'useWebview': true,
        'site': {'baseUrl': 'https://m.baozimh.one'},
        'parser': {
          'type': 'hybrid',
          'overrides': {
            'latest': {
              'type': 'script',
              'function': 'parseList',
              'script': 'function parseList(html, context){ return []; }',
            },
          },
        },
        'routes': {'latest': {'url': '/'}},
      });
      const html =
          '<html><body><a href="/manga/abc"><h3>Test Manga</h3>'
          '<img src="https://x/cover.png"/></a></body></html>';
      final items = await localService.fetchApiResults(
        source,
        'latest',
        renderedHtml: html,
      );
      // 验证脚本入口被调用，且回灌的 HTML 作为 raw 参数（args[0]）传入。
      expect(capturedFn, <String>['parseList']);
      expect(capturedArgs.length, 1);
      expect(capturedArgs.first.length, 1);
      expect(capturedArgs.first.first, html);
      // 验证脚本返回值经 _toTyped 转换为 List<MediaItem>。
      expect(items.length, 1);
      expect(items.first.title, 'Test Manga');
      expect(items.first.id, '/manga/abc');
      expect(items.first.coverUrl, 'https://x/cover.png');
      expect(items.first.detailUrl, 'https://m.baozimh.one/manga/abc');
    });

    test('xpath+useWebview source routes renderedHtml to BuiltinResolver (non-empty results)', () async {
      // 参考 pms_fsdm 配置：parser.type=xpath + useWebview=true。
      // 回灌渲染后 HTML，验证 BuiltinResolver 按 XPath selectors 解析出非空结果。
      // 注：BuiltinResolver HTML 路径按扁平 selectors 读取（sel['list']/sel['id']/...），
      // 测试用扁平结构验证分流逻辑与 BuiltinResolver 解析能力。
      final localService = MediaApiService(ResolverRegistry.instance);
      final source = PluginConfig.fromJson(<String, dynamic>{
        'id': 'pms_fsdm_test',
        'name': 'Fsdm Test',
        'type': 'animeSource',
        'responseType': 'html',
        'useWebview': true,
        'site': {'baseUrl': 'https://www.fsdm02.com'},
        'parser': {'type': 'xpath'},
        'routes': {'latest': {'url': '/vodshow/1--------{page}---.html'}},
        'selectors': {
          'list': "div[@class='item']",
          'id': "substring-before(substring-after(./a/@href, '/voddetail/'), '.html')",
          'title': './a/@title',
          'cover': './/img/@data-src',
        },
      });
      const html =
          '<html><body>'
          '<div class="item">'
          '<a href="/voddetail/123.html" title="Test Anime">Test Anime</a>'
          '<img data-src="https://x/cover.jpg"/>'
          '</div>'
          '<div class="item">'
          '<a href="/voddetail/456.html" title="Another Anime">Another Anime</a>'
          '<img data-src="https://x/cover2.jpg"/>'
          '</div>'
          '</body></html>';
      final items = await localService.fetchApiResults(
        source,
        'latest',
        renderedHtml: html,
      );
      // 验证 BuiltinResolver 按 XPath selectors 解析出非空 List<MediaItem>。
      expect(items.length, 2);
      expect(items.first.id, '123');
      expect(items.first.title, 'Test Anime');
      expect(items.first.coverUrl, 'https://x/cover.jpg');
      expect(items[1].id, '456');
      expect(items[1].title, 'Another Anime');
      expect(items[1].coverUrl, 'https://x/cover2.jpg');
    });
  });
}
