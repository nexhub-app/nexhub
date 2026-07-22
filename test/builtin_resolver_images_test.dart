import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/builtin_resolver.dart';

/// 启动一个本地 loopback 服务器，按 path 返回预设响应（无需真实网络）。
Future<HttpServer> _startServer(Map<String, String> routes) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    final path = req.uri.path;
    final body = routes[path];
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(body ?? '{}');
    req.response.close();
  });
  return server;
}

void main() {
  late HttpServer server;
  late String base;

  setUp(() async {
    server = await _startServer(<String, String>{
      '/images.json': '{"images":["https://x/1.jpg","https://x/2.jpg","https://x/3.jpg"]}',
      '/images.map': '{"list":[{"url":"https://y/a.png"},{"url":"https://y/b.png"}]}',
      '/images.html':
          '<div><img src="skip.png" data-src="d1.png"></div><img data-src="d2.png"><img src="s3.png">',
      '/chapters.html':
          '<div class="chapter"><a href="/c1">第1话</a></div><div class="chapter"><a href="/c2">第2话</a></div>',
      '/chapters.json':
          '{"list":[{"id":"1","title":"Ch1","url":"/r1"},{"id":"2","title":"Ch2","url":"/r2"}]}',
    });
    base = 'http://${server.address.host}:${server.port}';
  });

  tearDown(() => server.close(force: true));

  test('images from JSONPath selector', () async {
    final source = PluginConfig.fromJson(<String, dynamic>{
      'id': 's', 'name': 'S', 'type': 'mangaSource', 'responseType': 'json',
      'site': {'domain': base, 'baseUrl': base},
      'parser': {'type': 'builtin'},
      'routes': {'images': '/images.json'},
      'selectors': {'images': '\$.images'},
    });
    final r = await const BuiltinResolver().resolve(source, 'images');
    expect(r, isA<List<String>>());
    expect(r, <String>['https://x/1.jpg', 'https://x/2.jpg', 'https://x/3.jpg']);
  });

  test('images from JSON map selector', () async {
    final source = PluginConfig.fromJson(<String, dynamic>{
      'id': 's', 'name': 'S', 'type': 'mangaSource', 'responseType': 'json',
      'site': {'domain': base, 'baseUrl': base},
      'parser': {'type': 'builtin'},
      'routes': {'images': '/images.map'},
      'selectors': {
        'images': {'list': '\$.list', 'url': 'url'}
      },
    });
    final r = await const BuiltinResolver().resolve(source, 'images');
    expect(r, <String>['https://y/a.png', 'https://y/b.png']);
  });

  test('images from HTML @attr selector', () async {
    final source = PluginConfig.fromJson(<String, dynamic>{
      'id': 's', 'name': 'S', 'type': 'mangaSource', 'responseType': 'html',
      'site': {'domain': base, 'baseUrl': base},
      'parser': {'type': 'builtin'},
      'routes': {'images': '/images.html'},
      'selectors': {'images': 'img@data-src'},
    });
    final r = await const BuiltinResolver().resolve(source, 'images');
    // Relative `d1.png` / `d2.png` are now completed against the active
    // mirror base URL by the ImageExtractor cleaning chain.
    expect(r, <String>['$base/d1.png', '$base/d2.png']);
  });

  test('chapters from HTML (inner <a>)', () async {
    final source = PluginConfig.fromJson(<String, dynamic>{
      'id': 's', 'name': 'S', 'type': 'mangaSource', 'responseType': 'html',
      'site': {'domain': base, 'baseUrl': base},
      'parser': {'type': 'builtin'},
      'routes': {'chapters': '/chapters.html'},
      'selectors': {'chapters': 'div.chapter'},
    });
    final r = await const BuiltinResolver().resolve(source, 'chapters');
    expect(r, isA<List<Object>>());
    final eps = r as List;
    expect(eps.length, 2);
    expect(eps[0].title, '第1话');
    expect(eps[0].url, '/c1');
  });

  test('chapters from JSON map selector', () async {
    final source = PluginConfig.fromJson(<String, dynamic>{
      'id': 's', 'name': 'S', 'type': 'mangaSource', 'responseType': 'json',
      'site': {'domain': base, 'baseUrl': base},
      'parser': {'type': 'builtin'},
      'routes': {'chapters': '/chapters.json'},
      'selectors': {
        'chapters': {'list': '\$.list', 'id': 'id', 'title': 'title', 'url': 'url'}
      },
    });
    final r = await const BuiltinResolver().resolve(source, 'chapters');
    final eps = r as List;
    expect(eps.length, 2);
    expect(eps[1].title, 'Ch2');
    expect(eps[1].id, '2');
  });
}
