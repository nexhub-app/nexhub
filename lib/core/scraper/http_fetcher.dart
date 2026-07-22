/// 统一 HTTP 实例：Cookie 管理、强制隐身（随机延迟 + UA 轮换）、验证感知。
/// 全应用只应有一个 HttpFetcher 实例（spec：headless WebView 加载前把 Cookie 写入共享 CookieManager）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fast_gbk/fast_gbk.dart';
import '../services/config_loader.dart';
import 'verification_detector.dart';

/// 浏览器指纹档案：UA 与 `Sec-Ch-Ua` 品牌必须配套，否则会自爆（WAF 一秒识破）。
///
/// 每个档案都对应一个真实存在的 Chrome 版本，UA 字符串里的版本号与
/// `Sec-Ch-Ua` 里 `Chromium`/`Not.A.Brand` 的版本号一致。请求时按 host 固定选用
/// 其中一个，避免同一站点前后请求 UA 漂移。
class _BrowserProfile {
  const _BrowserProfile(this.ua, this.secChUa, this.secChUaMobile, this.secChUaPlatform);
  final String ua;
  final String secChUa;
  final String secChUaMobile;
  final String secChUaPlatform;
}

class HttpFetcher {
  HttpFetcher._() {
    _buildDio();
  }

  static final HttpFetcher instance = HttpFetcher._();

  /// 调试/特殊网络环境下强制直连（绕过系统代理）。默认 false，不影响正常行为。
  static bool forceDirect = false;

  late Dio _dio;
  final Map<String, String> _cookieJar = {};

  /// 每域名固定的浏览器指纹档案序号：保证同一站点每次请求用同一套 UA/指纹，
  /// 既轮换了不同站点之间的指纹，又不会在单次会话里自相矛盾。
  final Map<String, int> _hostProfile = {};

  static final List<_BrowserProfile> _profiles = const <_BrowserProfile>[
    _BrowserProfile(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
      '?0',
      '"Windows"',
    ),
    _BrowserProfile(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36 Edg/123.0.0.0',
      '"Chromium";v="123", "Not.A.Brand";v="99", "Microsoft Edge";v="123"',
      '?0',
      '"Windows"',
    ),
    _BrowserProfile(
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      '"Chromium";v="120", "Google Chrome";v="120", "Not-A.Brand";v="99"',
      '?0',
      '"macOS"',
    ),
  ];

  /// 为某 host 选定（或复用）指纹档案序号。
  int _profileIndexFor(String? host) {
    if (host == null || host.isEmpty) return 0;
    return _hostProfile.putIfAbsent(host, () => _random.nextInt(_profiles.length));
  }

  final Random _random = Random();

  void _buildDio() {
    _dio = Dio();
    // 对齐旧版（AI 修改前可正常解析的版本）：补全浏览器标准请求头。
    // 缺少 Accept / Accept-Language 头时，大量国内站（小说/动漫/漫画）会直接返回 400 空响应。
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers.addAll({
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    });

    final adapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        // 允许自签证书（部分源使用非标准 SSL 配置）
        client.badCertificateCallback = (cert, host, port) => true;
        if (forceDirect) {
          client.findProxy = (_) => 'DIRECT';
        }
        return client;
      },
    );
    _dio.httpClientAdapter = adapter;
  }

  /// 运行时切换直连模式（会重建 Dio 实例）。
  static void setForceDirect(bool value) {
    forceDirect = value;
    instance._buildDio();
  }

  Future<void> _stealthDelay() async {
    // 强制隐身：请求前随机延迟 300~1100ms，降频 + 打散节拍，避免被识别为脚本。
    // 用 Random 而不是时间戳取模（后者可预测、固定间隔更可疑）。
    final ms = 300 + _random.nextInt(800);
    await Future.delayed(Duration(milliseconds: ms));
  }

  Map<String, String> _mergeHeaders(
    String? referer, [
    Map<String, String>? extra,
    String? url,
  ]) {
    // 每次请求实际发出的头。必须显式带上 Accept / Accept-Language：
    // 大量国内站（小说/动漫/漫画）会拒绝缺这些头的请求，直接回 400 空响应。
    // 注意：此处若不写全，会被请求级 Options(headers) 整体覆盖，基础配置的头不生效。
    final host = Uri.tryParse(url ?? '')?.host;
    final profile = _profiles[_profileIndexFor(host)];
    final merged = <String, String>{
      // 浏览器指纹：UA 与 Sec-Ch-Ua 品牌配套，避免自爆。
      'User-Agent': profile.ua,
      'Sec-Ch-Ua': profile.secChUa,
      'Sec-Ch-Ua-Mobile': profile.secChUaMobile,
      'Sec-Ch-Ua-Platform': profile.secChUaPlatform,
      // 现代浏览器标准头：WAF/Cloudflare 用这些判定是否真人。缺了极易被拦。
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Accept-Encoding': 'gzip, deflate',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'same-origin',
      'Sec-Fetch-User': '?1',
      'Upgrade-Insecure-Requests': '1',
      'Connection': 'keep-alive',
      if (referer != null) 'Referer': referer,
      ...?extra,
    };
    // 回带 Cookie（对齐旧版可解析版本）：站点下发的会话 Cookie 需在后续请求带回，
    // 否则部分 MacCMS/源会拒绝（400）或要求验证。匹配父域/子域。
    final cookie = _cookieHeaderFor(url);
    if (cookie != null) merged['Cookie'] = cookie;
    return merged;
  }

  /// 取与 [url] 同域（含父域/子域）的已存 Cookie，拼成 `Cookie` 头值。
  String? _cookieHeaderFor(String? url) {
    final host = Uri.tryParse(url ?? '')?.host;
    if (host == null || host.isEmpty) return null;
    final matched = <String>[];
    _cookieJar.forEach((storedHost, cookie) {
      if (cookie.isEmpty) return;
      if (host == storedHost || host.endsWith('.$storedHost')) {
        matched.add(cookie);
      }
    });
    if (matched.isEmpty) return null;
    return matched.join('; ');
  }

  /// 将响应字节按字符集解码为字符串。
  ///
  /// 对齐旧版可解析实现：国内大量漫画/小说/动漫源（如 goda、baozimh 部分镜像）
  /// 以 **GBK/GB2312/GB18030** 编码返回正文。若直接用 Dio 的 `ResponseType.plain`
  /// 走 UTF-8 解码，中文会变成乱码（烫疽 类字符），正则选择器匹配不到 → 列表空。
  /// 故统一取字节后：先按 Content-Type / <meta charset> 声明的字符集解码；
  /// 声明为 GBK 系列时直接用 [gbk]（fast_gbk，覆盖 GB2312/GB18030 绝大多数情况）
  /// 解码；未声明或声明 utf-8 时走 UTF-8，并对出现大量替换符（U+FFFD）的疑似
  /// 乱码结果再兜底尝试 GBK，避免漏掉未声明 charset 的站点。
  String _decodeBody(List<int> bytes, String? contentType) {
    if (bytes.isEmpty) return '';
    final charset = _detectCharset(bytes, contentType);
    if (charset != null && _isGbkFamily(charset)) {
      try {
        return gbk.decode(bytes);
      } on Object {
        // GBK 解码失败（极罕见非法序列）→ 退回 UTF-8。
      }
    }
    final utf8Str = utf8.decode(bytes, allowMalformed: true);
    if (_hasReplacementChars(utf8Str)) {
      try {
        final g = gbk.decode(bytes);
        if (!_hasReplacementChars(g)) return g;
      } on Object {
        // 忽略，保留 UTF-8 结果。
      }
    }
    return utf8Str;
  }

  /// 从 Content-Type 头与 <meta> 标签探测字符集声明。
  String? _detectCharset(List<int> bytes, String? contentType) {
    if (contentType != null) {
      final m = RegExp(r'charset=([^\s;]+)', caseSensitive: false)
          .firstMatch(contentType);
      if (m != null) return m.group(1)?.trim();
    }
    // 扫描 head 前若干字节内的 <meta charset=...> / <meta http-equiv=...charset=...>
    final headLen = bytes.length < 2048 ? bytes.length : 2048;
    final headAscii = String.fromCharCodes(
      bytes.sublist(0, headLen).map((b) => b < 128 ? b : 0x20),
    );
    final meta =
        RegExp(r'charset[^\w]*=[^\w]*([a-z0-9_-]+)', caseSensitive: false)
            .firstMatch(headAscii.toLowerCase());
    return meta?.group(1);
  }

  /// 是否为 GBK 系列字符集（GBK/GB2312/GB18030 等），统一用 [gbk] 解码。
  static bool _isGbkFamily(String charset) {
    final c = charset.toLowerCase().replaceAll('_', '-');
    return c == 'gbk' ||
        c == 'gb2312' ||
        c == 'gb-2312' ||
        c == 'gb18030' ||
        c == 'gb_2312' ||
        c == 'csgb2312' ||
        c == 'csiso58bgb231280';
  }

  /// 统计文本中 U+FFFD 替换符数量，超过阈值视为 UTF-8 乱码（疑似非 UTF-8 编码）。
  static bool _hasReplacementChars(String s) {
    var count = 0;
    final limit = s.length < 8000 ? s.length : 8000;
    for (var i = 0; i < limit; i++) {
      if (s.codeUnitAt(i) == 0xFFFD) count++;
      if (count > 5) return true;
    }
    return false;
  }

  /// 取 HTML 文本；命中验证特征抛 [VerificationRequiredException]。
  Future<String> getHtml(
    String url, {
    Map<String, String>? headers,
    String? referer,
    bool stealth = true,
  }) async {
    if (ConfigLoader.instance.getStealthMode() && stealth) {
      await _stealthDelay();
    }
    final merged = _mergeHeaders(referer, headers, url);
    final resp = await _dio.get<List<int>>(
      url,
      options: Options(
        headers: merged,
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
      ),
    );
    final bytes = resp.data ?? const <int>[];
    if (bytes.isEmpty) {
      if (VerificationDetector.isVerificationRequired(
        statusCode: resp.statusCode,
        body: '',
        headers: _responseHeaders(resp),
      )) {
        throw VerificationRequiredException(
          url: url,
          headers: merged,
          body: '',
          statusCode: resp.statusCode,
        );
      }
      _checkNonVerificationError(url, resp.statusCode, '');
      _storeCookies(url, resp);
      return '';
    }
    final body = _decodeBody(bytes, resp.headers.value('content-type'));
    if (VerificationDetector.isVerificationRequired(
      statusCode: resp.statusCode,
      body: body,
      headers: _responseHeaders(resp),
    )) {
      throw VerificationRequiredException(
        url: url,
        headers: merged,
        body: body,
        statusCode: resp.statusCode,
      );
    }
    _checkNonVerificationError(url, resp.statusCode, body);
    _storeCookies(url, resp);
    return body;
  }

  /// 取 JSON（自动解析）。
  Future<dynamic> getJson(
    String url, {
    Map<String, String>? headers,
    String? referer,
    bool stealth = true,
  }) async {
    final text =
        await getHtml(url, headers: headers, referer: referer, stealth: stealth);
    return _decodeJson(text);
  }

  /// POST 并返回解析后的 JSON（自动解析响应体）。
  /// 用于 meta 协议的 POST 预取分支（如 komiic 的 GraphQL 查询）。
  Future<dynamic> postJson(
    String url, {
    Map<String, String>? headers,
    Object? data,
    String? referer,
    bool stealth = true,
  }) async {
    final text = await post(
      url,
      headers: headers,
      data: data,
      referer: referer,
      stealth: stealth,
    );
    return _decodeJson(text);
  }

  /// POST 表单/JSON，返回 HTML 文本。
  Future<String> post(
    String url, {
    Map<String, String>? headers,
    Object? data,
    String? referer,
    bool stealth = true,
  }) async {
    if (ConfigLoader.instance.getStealthMode() && stealth) {
      await _stealthDelay();
    }
    final merged = _mergeHeaders(referer, headers, url);
    final resp = await _dio.post<List<int>>(
      url,
      data: data,
      options: Options(
        headers: merged,
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
      ),
    );
    final body = _decodeBody(resp.data ?? const <int>[], resp.headers.value('content-type'));
    if (VerificationDetector.isVerificationRequired(
      statusCode: resp.statusCode,
      body: body,
      headers: _responseHeaders(resp),
    )) {
      throw VerificationRequiredException(
        url: url,
        headers: merged,
        body: body,
        statusCode: resp.statusCode,
      );
    }
    _checkNonVerificationError(url, resp.statusCode, body);
    _storeCookies(url, resp);
    return body;
  }

  /// PUT 请求，返回 HTML 文本（与 [post] 同构，method=PUT）。
  Future<String> put(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? data,
    String? referer,
    bool stealth = true,
  }) async {
    _validateScheme(url);
    if (ConfigLoader.instance.getStealthMode() && stealth) {
      await _stealthDelay();
    }
    final merged = _mergeHeaders(referer, headers, url);
    final resp = await _dio.put<List<int>>(
      url,
      data: data,
      options: Options(
        headers: merged,
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
      ),
    );
    final body = _decodeBody(resp.data ?? const <int>[], resp.headers.value('content-type'));
    if (VerificationDetector.isVerificationRequired(
      statusCode: resp.statusCode,
      body: body,
      headers: _responseHeaders(resp),
    )) {
      throw VerificationRequiredException(
        url: url,
        headers: merged,
        body: body,
        statusCode: resp.statusCode,
      );
    }
    _checkNonVerificationError(url, resp.statusCode, body);
    _storeCookies(url, resp);
    return body;
  }

  /// DELETE 请求，返回 HTML 文本。
  Future<String> delete(
    String url, {
    Map<String, String>? headers,
    String? referer,
    bool stealth = true,
  }) async {
    _validateScheme(url);
    if (ConfigLoader.instance.getStealthMode() && stealth) {
      await _stealthDelay();
    }
    final merged = _mergeHeaders(referer, headers, url);
    final resp = await _dio.delete<List<int>>(
      url,
      options: Options(
        headers: merged,
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
      ),
    );
    final body = _decodeBody(resp.data ?? const <int>[], resp.headers.value('content-type'));
    if (VerificationDetector.isVerificationRequired(
      statusCode: resp.statusCode,
      body: body,
      headers: _responseHeaders(resp),
    )) {
      throw VerificationRequiredException(
        url: url,
        headers: merged,
        body: body,
        statusCode: resp.statusCode,
      );
    }
    _checkNonVerificationError(url, resp.statusCode, body);
    _storeCookies(url, resp);
    return body;
  }

  /// 表单（application/x-www-form-urlencoded）POST，返回 HTML 文本。
  /// 对应 JS 沙箱 `context.http.postForm(url, params)`：params 为键值对，
  /// 编码为 `k=v&...` 并以该 Content-Type 发送（golden 源 gugu3 视频解析用到）。
  Future<String> postForm(
    String url, {
    Map<String, String>? headers,
    Map<String, String>? data,
    String? referer,
    bool stealth = true,
  }) async {
    _validateScheme(url);
    if (ConfigLoader.instance.getStealthMode() && stealth) {
      await _stealthDelay();
    }
    final body = (data ?? const <String, String>{})
        .entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final merged = _mergeHeaders(referer, <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
      ...?headers,
    }, url);
    final resp = await _dio.post<List<int>>(
      url,
      data: body,
      options: Options(
        headers: merged,
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
      ),
    );
    final respBody = _decodeBody(resp.data ?? const <int>[], resp.headers.value('content-type'));
    if (VerificationDetector.isVerificationRequired(
      statusCode: resp.statusCode,
      body: respBody,
      headers: _responseHeaders(resp),
    )) {
      throw VerificationRequiredException(
        url: url,
        headers: merged,
        body: respBody,
        statusCode: resp.statusCode,
      );
    }
    _checkNonVerificationError(url, resp.statusCode, respBody);
    _storeCookies(url, resp);
    return respBody;
  }

  /// 通用 fetch：返回 `{status, headers, body}` 映射（JS 沙箱 http.fetch 桥）。
  Future<Map<String, dynamic>> fetch(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    String? body,
    String? referer,
    bool stealth = true,
  }) async {
    _validateScheme(url);
    if (ConfigLoader.instance.getStealthMode() && stealth) {
      await _stealthDelay();
    }
    final merged = _mergeHeaders(referer, headers, url);
    final resp = await _dio.request<List<int>>(
      url,
      data: body,
      options: Options(
        method: method,
        headers: merged,
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
      ),
    );
    final respBody = _decodeBody(resp.data ?? const <int>[], resp.headers.value('content-type'));
    if (VerificationDetector.isVerificationRequired(
      statusCode: resp.statusCode,
      body: respBody,
      headers: _responseHeaders(resp),
    )) {
      throw VerificationRequiredException(
        url: url,
        headers: merged,
        body: respBody,
        statusCode: resp.statusCode,
      );
    }
    _storeCookies(url, resp);
    final respHeaders = <String, String>{};
    resp.headers.map.forEach((k, v) {
      respHeaders[k] = v.join(', ');
    });
    return <String, dynamic>{
      'status': resp.statusCode ?? 0,
      'headers': respHeaders,
      'body': respBody,
    };
  }

  /// 校验 URL scheme 仅允许 http/https（沙箱安全约束）。
  void _validateScheme(String url) {
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      throw ArgumentError('URL scheme must be http or https: $url');
    }
  }

  /// 把 Dio 的响应头拍平成 `Map<String,String>`（同名多值用逗号拼接）。
  ///
  /// 验证检测需要**响应头**（如 `Server: Edge/1.1.18` 这类 WAF 签名）；旧代码误把
  /// 请求头传给检测器，导致基于响应头的判断永远失效，这里统一取真实响应头。
  static Map<String, String> _responseHeaders(Response<dynamic> resp) {
    final out = <String, String>{};
    resp.headers.map.forEach((k, v) {
      out[k] = v.join(', ');
    });
    return out;
  }

  /// 验证检测通过后，若状态码仍 ≥ 400（如 404/500/502），抛
  /// [HttpStatusException] 以便上层显示明确错误 + 重试，而非把错误页
  /// body 当成正常响应交给解析器导致静默空列表。
  void _checkNonVerificationError(String url, int? statusCode, String body) {
    final code = statusCode;
    if (code != null && code >= 400) {
      throw HttpStatusException(
        url: url,
        statusCode: code,
        body: body,
      );
    }
  }

  /// 取二进制（视频/图片）。
  Future<List<int>> getBytes(String url, {Map<String, String>? headers}) async {
    final resp = await _dio.get<List<int>>(
      url,
      options: Options(
        headers: _mergeHeaders(null, headers, url),
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
      ),
    );
    return resp.data ?? const [];
  }

  /// WebView 验证完成后把共享 Cookie 同步进 Fetcher（含父域子域匹配）。
  void syncCookies(String host, String cookieHeader) {
    _cookieJar[host] = cookieHeader;
  }

  String? getCookieHeader(String host) => _cookieJar[host];

  /// 清除所有 Cookie（缓存清除）。
  void clearCookies() {
    _cookieJar.clear();
  }

  void _storeCookies(String url, Response<dynamic> resp) {
    final setCookie = resp.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) return;
    final host = Uri.tryParse(url)?.host;
    if (host == null) return;
    _cookieJar[host] = setCookie.map((c) => c.split(';').first).join('; ');
  }

  dynamic _decodeJson(String text) {
    // 去除 BOM / 首尾空白；失败时退一步截取首个 { 到末个 }。
    final trimmed = text.trim();
    try {
      return jsonDecode(trimmed);
    } on Object {
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start >= 0 && end > start) {
        return jsonDecode(trimmed.substring(start, end + 1));
      }
      rethrow;
    }
  }
}
