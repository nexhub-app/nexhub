/// 脚本解析器：执行源内嵌 JS（quickjs 沙箱）。
///
/// 安全约束：沙箱仅经 [JsHostBridge] 调用能力；单函数 >10s 自动终止抛超时；
/// 错误隔离——某源脚本崩溃仅该源返回 [SourceResolveException]，不影响其他源。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/episode.dart';
import '../models/media_item.dart';
import '../models/plugin_config.dart';
import '../scraper/http_fetcher.dart';
import '../scraper/verification_detector.dart';
import '../services/config_loader.dart';
import 'js_context.dart';
import 'parse_diagnostics.dart';
import 'source_resolver.dart';

class ScriptResolver implements SourceResolver {
  ScriptResolver({this.engineFactory});

  /// 可注入引擎工厂（测试用 FakeJsEngine）。
  final JsEngineFactory? engineFactory;

  @override
  Future<dynamic> resolve(
    PluginConfig source,
    String apiName, {
    Map<String, String> vars = const {},
    void Function(List<dynamic>)? onProgress,
  }) async {
    // 注意：不再对 `useWebview` 源无条件抛 [WebViewHtmlRequest]。
    //
    // 本解析器只会被「脚本型」源（parser.type=='script' 或 hybrid + override
    // 为 script）路由到；声明式 useWebview 源（builtin/xpath/jsonpath/css）由
    // [ResolverRegistry] 直接派发给 [WebViewResolver]，不会进到这里。
    //
    // 之前这里对 useWebview 源一律抛 WebViewHtmlRequest，导致脚本源（如
    // manga_goda / manga_baozimh）每次点源都强制打开内嵌 InAppWebView 渲染后
    // 抽页——而这些源脚本本身通过 `ctx.http.get/getJson` 自行抓取数据、并不
    // 消费回灌的渲染 HTML，于是 WebView 毫无意义，且 InAppWebView 在反爬站点
    // 上加载数秒后直接 native 崩溃（表现即「漫画点击源过几秒钟自动卡崩」）。
    //
    // 正确做法：脚本源直接运行脚本，由脚本内部的 `ctx.http` 自行抓取；若站点
    // 拦截，脚本自身 try/catch 返回空列表，优雅降级而非崩溃。需要渲染后 HTML
    // 的声明式源仍走 WebViewResolver，不在此受影响。
    final factory = engineFactory ?? defaultEngineFactory;
    ParseDiagnostics.clear();
    ParseDiagnostics.log(source.id, 'resolve() 开始: apiName=$apiName, vars=$vars');
    debugPrint('[ScriptResolver] resolve() 开始: source=${source.id}, apiName=$apiName, vars=$vars');
    final engine = factory(source);
    // 注入分页/分类/关键词等到 JS context，供脚本自拼 URL（如 goda 脚本依赖
    // ctx.page / ctx.category 翻页与分类）。无相关变量的源为空操作，无副作用。
    engine.injectContext(vars);
    try {
      final base = ConfigLoader.instance.getActiveMirror(source);
      final url =
          source.resolveRouteUrl(apiName, activeBaseUrl: base, vars: vars);
      final rt = source.responseTypeFor(apiName) ?? 'json';
      ParseDiagnostics.log(source.id, '路由URL=$url (responseType=$rt)');
      debugPrint('[ScriptResolver] 预取: url=$url, responseType=$rt');
      // 预取：多数脚本（如 goda 漫画）会自行 ctx.http.get 抓取，此处结果常被
      // 忽略；即便站点反爬导致预取抛 VerificationRequiredException，也不应直接
      // 上抛成 SourceResolveException 让列表报错——兜底为空串，交由脚本自抓取。
      dynamic raw;
      try {
        raw = rt == 'json'
            ? await engine.bridge.httpGetJson(url)
            : await engine.bridge.httpGet(url);
        final rawLen = raw is String ? raw.length : (raw is List ? raw.length : -1);
        ParseDiagnostics.log(source.id, '预取成功: 拿到 ${rawLen} 字符/项');
        debugPrint('[ScriptResolver] 预取成功: rawLength=${raw is String ? raw.length : (raw is List ? raw.length : "non-string/list")}');
      } on Object catch (e) {
        ParseDiagnostics.log(source.id, '预取失败(非致命): $e');
        debugPrint('[ScriptResolver] 预取失败(非致命): $e');
        raw = '';
      }
      ParseDiagnostics.log(source.id, '开始执行脚本(入口函数)...');
      debugPrint('[ScriptResolver] 开始执行脚本...');
      final result = await _runScriptWithRaw(source, apiName, raw, engine);
      final count = result is List ? result.length : 0;
      ParseDiagnostics.log(source.id, '脚本执行完成: 返回 ${count} 项 (类型=${result.runtimeType})');
      debugPrint('[ScriptResolver] 脚本执行完成: resultType=${result.runtimeType}, result=${result is List ? "List[${result.length}]" : result}');
      if (count == 0) {
        ParseDiagnostics.log(source.id, '⚠️ 脚本返回空列表！可能是：1) 桥接未通(ctx.http.get 拿不到数据) 2) 页面结构变化 3) 站点反爬');
      }
      // detail 路由兜底：脚本若未返回 detailUrl，或返回了无效占位符 `{}`，
      // 优先用 id 推导（id 是 URL/相对路径时），其次用实际请求 URL 填充，
      // 保证所有脚本源详情页都能显示正确的浏览器按钮（共创式，不针对单个源）。
      if (apiName == 'detail' && result is MediaItem) {
        final du = result.detailUrl;
        if (du == null || du.isEmpty || du.contains('{}')) {
          String? fallback;
          final id = result.id;
          if (id.startsWith('http://') || id.startsWith('https://')) {
            fallback = id;
          } else if (id.startsWith('/')) {
            final base = ConfigLoader.instance.getActiveMirror(source);
            final b =
                base.endsWith('/') ? base.substring(0, base.length - 1) : base;
            fallback = '$b$id';
          } else if (url.isNotEmpty && !url.contains('{}')) {
            fallback = url;
          }
          if (fallback != null && fallback.isNotEmpty) {
            return result.copyWith(detailUrl: fallback);
          }
        }
      }
      return result;
    } on SourceResolveException catch (e) {
      ParseDiagnostics.log(source.id, '❌ 解析异常: ${e.message}');
      rethrow;
    } catch (e) {
      ParseDiagnostics.log(source.id, '❌ 未知异常: $e');
      throw SourceResolveException(
        sourceId: source.id,
        apiName: apiName,
        message: e.toString(),
      );
    } finally {
      engine.dispose();
    }
  }

  /// 渲染后 HTML 回灌入口：UI 层在内嵌 WebView 加载页面、JS 渲染完成后
  /// 取回整页 HTML，调用本方法把 [html] 作为 `raw` 参数喂给脚本入口（替代
  /// 脚本内 `ctx.http.get(url)` 抓未渲染 HTML 的旧路径）。
  ///
  /// 与 [resolve] 共享 [_runScriptWithRaw]（脚本/入口选取 + 执行 + `_toTyped`
  /// 转换），但跳过 `engine.bridge.httpGet/httpGetJson` 抓取步骤；不再触发
  /// [WebViewHtmlRequest]（已由调用方提供渲染后 HTML，避免回灌循环）。
  Future<dynamic> resolveFromHtml(
    PluginConfig source,
    String apiName,
    String html, {
    Map<String, String> vars = const {},
  }) async {
    final factory = engineFactory ?? defaultEngineFactory;
    final engine = factory(source);
    engine.injectContext(vars);
    try {
      return await _runScriptWithRaw(source, apiName, html, engine);
    } on SourceResolveException {
      rethrow;
    } catch (e) {
      throw SourceResolveException(
        sourceId: source.id,
        apiName: apiName,
        message: e.toString(),
      );
    } finally {
      engine.dispose();
    }
  }

  /// 共用脚本执行 helper：选取脚本/入口、运行（10s 超时）、按 apiName 转换
  /// 类型化结果。供 [resolve]（[raw] 为抓回的 HTML/JSON）与 [resolveFromHtml]
  /// （[raw] 为回灌的 HTML）复用，避免重复实现。
  Future<dynamic> _runScriptWithRaw(
    PluginConfig source,
    String apiName,
    dynamic raw,
    JsEngine engine,
  ) async {
    // 选取脚本与入口函数（考虑 hybrid overrides + golden 覆盖写法）。
    // 入口名优先级：override.function（golden 写法）> override.entrypoints[api]
    // > parser.entrypoints[api] > apiName（直接以 api 名作函数名）。
    final override = source.parser.overrides?[apiName];
    final String script;
    final String entry;
    if (source.parser.type == 'hybrid' && override != null) {
      script = override.script ?? source.parser.script ?? '';
      entry = override.function ??
          override.entrypoints?[apiName] ??
          apiName;
    } else {
      script = source.parser.script ?? '';
      entry = override?.function ??
          source.parser.entrypoints?[apiName] ??
          apiName;
    }
    debugPrint('[ScriptResolver] _runScriptWithRaw: entry=$entry, scriptLength=${script.length}, rawLength=${raw is String ? (raw as String).length : "non-string"}');
    try {
      final rawResult = await engine
          .run(script, entry, <dynamic>[raw])
          .timeout(const Duration(seconds: 10));

      // JS 引擎（flutter_js / QuickJS）的 stringResult 常返回非严格 JSON 的
      // JS 字面量字符串（如 [{id: foo, title: bar}] 键名无引号），导致
      // JsContext 内部 jsonDecode 失败后回退为原始 String。
      // 此处做防御性解码：若结果为 String 且形似 JSON（以 [ 或 { 开头），
      // 尝试 jsonDecode；失败则保持原值交由 _toTyped 处理。
      var result = _decodeEngineResult(rawResult);

      // ══════════════════════════════════════════════════════════
      // Meta→预取→处理 协议（flutter_js 真机无法执行 async function 的解决方案）
      // ══════════════════════════════════════════════════════════
      //
      // 背景：flutter_js 在真机上 evaluateAsync 对任何 Promise/async 均返回
      //   "Instance of 'Future<dynamic>'" 字符串，handlePromise/isPromise 全部失效。
      //   唯一能工作的异步通道是桥接自身的 __resolveBridge（解单个 HTTP 请求），
      //   但不传播到脚本级 Promise 返回值。
      //
      // 解决方案：需要异步数据的脚本改为两步同步模式：
      //   Step 1 (sync): 脚本提取参数 + 返回 meta 描述符 {__meta:true, __fetchUrl, __processor}
      //   Step 2 (Dart): ScriptResolver 检测到 meta → 用源配置(防盗链/UA)在 Dart 侧 HTTP 预取
      //   Step 3 (sync): 用预取数据调用处理器函数(__processChapters 等) → 返回最终结果
      //
      // 对已有同步脚本的影响：零。result 不是 Map 或不含 __meta 键时完全跳过。
      if (result is Map) {
        final meta = result as Map<dynamic, dynamic>;
        if (meta['__meta'] == true && meta['__fetchUrl'] is String) {
          final fetchUrl = meta['__fetchUrl'] as String;
          final processor = meta['__processor'] as String? ?? '';
          // meta 协议扩展字段（通用，仍不写死任何站点逻辑）：
          //   __fetchMethod  : 'get'(默认) | 'post'
          //   __fetchBody    : POST body 字符串（通常为 JSON.stringify(query)）
          //   __fetchHeaders : 请求头 Map（如 {'Content-Type':'application/json'}）
          // 用于需要 POST 的源（如 komiic 的 GraphQL）。GET 源（goda/bun）不受影响。
          final fetchMethod =
              (meta['__fetchMethod'] as String? ?? 'get').toLowerCase();
          final fetchBody = meta['__fetchBody'] as String?;
          final fetchHeaders = <String, String>{};
          final rawHeaders = meta['__fetchHeaders'];
          if (rawHeaders is Map) {
            rawHeaders.forEach((k, v) => fetchHeaders[k.toString()] = v.toString());
          }
          debugPrint(
              '[ScriptResolver] 检测到 meta 协议: method=$fetchMethod, fetch=$fetchUrl, processor=$processor');
          ParseDiagnostics.log(
              source.id, '📡 meta协议($fetchMethod): $apiName → 预取 $fetchUrl');

          if (processor.isNotEmpty) {
            try {
              // Step 2: Dart 侧预取（使用源的防盗链/UA 配置）
              final referer =
                  source.antiHotlinking.referer ??
                      ConfigLoader.instance.getActiveMirror(source);
              final apiJson = fetchMethod == 'post'
                  ? await HttpFetcher.instance.postJson(
                      fetchUrl,
                      data: fetchBody,
                      headers: fetchHeaders.isNotEmpty ? fetchHeaders : null,
                      referer: referer,
                    )
                  : await HttpFetcher.instance.getJson(
                      fetchUrl,
                      referer: referer,
                    );
              debugPrint(
                  '[ScriptResolver] 预取成功: ${fetchUrl}, dataKeys=${(apiJson as Map?)?.keys}');
              ParseDiagnostics.log(source.id, '✅ 预取成功: $fetchUrl');

              // Step 3: 调用 JS 处理函数（纯同步，传入预取数据）
              final processResult = await engine
                  .run(script, processor, <dynamic>[apiJson])
                  .timeout(const Duration(seconds: 10));
              result = _decodeEngineResult(processResult);
              debugPrint(
                  '[ScriptResolver] 处理器 $processor 完成: ${result is List ? "List[${(result as List).length}]" : result.runtimeType}');
              ParseDiagnostics.log(
                  source.id,
                  '✅ 处理器$processor完成: ${result is List ? "List[${(result as List).length}]" : result.runtimeType}');
            } on Object catch (e) {
              debugPrint('[ScriptResolver] meta 预取/处理失败: $e');
              ParseDiagnostics.log(source.id, '❌ meta协议失败: $e');
              result = []; // 优雅降级为空列表
            }
          }
        }
      }

      debugPrint('[ScriptResolver] _runScriptWithRaw ✅ 完成: ${result is List ? "List[${(result as List).length}]" : result.runtimeType}');
      return _toTyped(apiName, result, sourceId: source.id);
    } on TimeoutException {
      throw SourceResolveException(
        sourceId: source.id,
        apiName: apiName,
        message: 'script timeout (>10s)',
      );
    }
  }

  /// JS 引擎返回值的防御性解码。
  ///
  /// flutter_js / QuickJS 的 stringResult 可能是：
  /// - 严格 JSON → JsContext 内部已 jsonDecode，直接得到 List/Map
  /// - 非 JSON 的 JS 字面量 String（键名无引号）→ 内部 jsonDecode 失败回退为 String
  /// - 空值 / 基本类型
  ///
  /// 本方法处理第二种情况：String 且形似 JSON 时再尝试一次解码（含容错）。
  static dynamic _decodeEngineResult(dynamic raw) {
    if (raw is List || raw is Map) return raw;
    if (raw is! String || raw.isEmpty) return raw;
    final trimmed = raw.trim();
    if (!trimmed.startsWith('[') && !trimmed.startsWith('{')) return raw;
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      // 严格 JSON 解析失败，尝试修正常见非 JSON 模式后重试
      try {
        return _lenientJsonDecode(trimmed);
      } on Object {
        debugPrint('[ScriptResolver] ⚠️ 引擎结果无法解码为JSON, 长度=${raw.length}, 前100字符: ${raw.length > 100 ? raw.substring(0, 100) : raw}');
        return raw;
      }
    }
  }

  /// 宽松 JSON 解码：尝试修复 JS 字面量中常见的非严格格式问题。
  ///
  /// 仅处理脚本返回的最常见模式：[{id: val, title: "str", ...}]
  /// 即键名无双引号 / 单引号包裹的值等。不做完整 JS 表达式解析。
  static dynamic _lenientJsonDecode(String input) {
    // 给无引号的键名加双引号: {id: → {"id":
    var fixed = input.replaceAllMapped(
      RegExp(r'(?<=[{\s,])([a-zA-Z_][a-zA-Z0-9_]*)\s*:'),
      (m) => '"${m[1]}":',
    );
    // 给单引号字符串值换成双引号: 'value' → "value"
    fixed = fixed.replaceAllMapped(
      RegExp(r"'([^']*)'"),
      (m) => '"${m[1]}"',
    );
    return jsonDecode(fixed);
  }

  dynamic _toTyped(String apiName, dynamic result, {String? sourceId}) {
    if (result == null) {
      return apiName == 'detail' ? null : <MediaItem>[];
    }
    switch (apiName) {
      case 'detail':
        return _toItem(result, fallbackSourceId: sourceId);
      case 'episodes':
      case 'chapters':
        return _toEpisodes(result);
      case 'images':
        return _toImages(result);
      case 'video':
        return _toVideo(result);
      default:
        return _toItems(result, sourceId: sourceId);
    }
  }

  List<MediaItem> _toItems(dynamic result, {String? sourceId}) {
    if (result is! List) return const [];
    return [for (final e in result) if (e is Map) _toItem(e, fallbackSourceId: sourceId)];
  }

  MediaItem _toItem(dynamic m, {String? fallbackSourceId}) {
    final map = m as Map<dynamic, dynamic>;
    final detailUrl = _str(map['detailUrl']).isNotEmpty
        ? _str(map['detailUrl'])
        : _str(map['detail']);
    // 脚本返回值通常不含 sourceId（由 ScriptResolver 从当前源自动注入）；
    // 若脚本显式返回了 sourceId 则优先使用，否则用调用方传入的 fallback。
    final sid = _str(map['sourceId']).isNotEmpty
        ? _str(map['sourceId'])
        : (fallbackSourceId ?? '');
    return MediaItem(
      id: _str(map['id']),
      title: _str(map['title']),
      coverUrl: _str(map['cover']),
      detailUrl: detailUrl,
      sourceId: sid,
      description: _str(map['description']),
      author: _str(map['author']),
      // 解析导演/主演，供「按导演/主演检索」客户端过滤使用（小说/漫画源通常为空，无害）。
      director: _str(map['director']).isNotEmpty ? _str(map['director']) : null,
      actors: _str(map['actors']).isNotEmpty ? _str(map['actors']) : null,
      status: _str(map['status']),
      tags: _tags(map['tags']),
      updatedAt: _parseDateTime(map['updatedAt']),
      wordCount: _str(map['wordCount']).isNotEmpty ? _str(map['wordCount']) : null,
      // 详情页解析出的作者/标签落地页链接，供"点作者/标签即检索"使用（源侧提供）。
      authorUrl: _str(map['authorUrl']).isNotEmpty ? _str(map['authorUrl']) : null,
      tagUrls: _tagUrls(map['tagUrls']),
    );
  }

  List<Episode> _toEpisodes(dynamic result) {
    if (result is! List) return const [];
    return [
      for (final e in result)
        if (e is Map)
          Episode(
            id: _str(e['id']),
            title: _str(e['title']),
            url: _str(e['url']),
            updatedAt: _parseDateTime(e['updatedAt']),
            number: _parseInt(e['number']),
          ),
    ];
  }

  VideoResult _toVideo(dynamic result) {
    if (result is Map) {
      return VideoResult(url: _str(result['url']), type: _strOrNull(result['type']));
    }
    return VideoResult(url: _str(result));
  }

  /// 漫画图片列表（脚本可返回 `['url', ...]` 或 `[{ url }, ...]`）。
  List<String> _toImages(dynamic result) {
    if (result is! List) return const [];
    return <String>[
      for (final e in result)
        if (e is Map) _str(e['url']) else _str(e),
    ].where((s) => s.isNotEmpty).toList();
  }

  String _str(dynamic v) => v?.toString() ?? '';
  String? _strOrNull(dynamic v) => v?.toString();

  /// 把脚本返回的日期/时间戳解析成 [DateTime]。支持 ISO 字符串、毫秒/秒级时间戳。
  DateTime? _parseDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) {
      // 毫秒级时间戳通常 > 1e12；秒级则乘 1000
      if (v > 9999999999) return DateTime.fromMillisecondsSinceEpoch(v);
      return DateTime.fromMillisecondsSinceEpoch(v * 1000);
    }
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  /// 把脚本返回的数字解析成 [int]。
  int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  List<String>? _tags(dynamic v) {
    if (v == null) return null;
    if (v is List) {
      return v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    final s = v.toString();
    if (s.isEmpty) return null;
    return s.split(RegExp(r'[,，/、|\s]+')).where((t) => t.isNotEmpty).toList();
  }

  /// 与 [_tags] 类似，但专用于详情页解析出的"标签落地页链接"列表（不拆分、原样保留 URL）。
  List<String>? _tagUrls(dynamic v) {
    if (v == null) return null;
    if (v is! List) return null;
    final list = v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    return list.isEmpty ? null : list;
  }
}
