/// WebView 解析器：当请求被拦截（验证/Cloudflare/CAPTCHA/滑块）时，
/// 抛出 [WebViewRequiredException] 通知 UI 打开 WebViewVerificationScreen 过验证，
/// 取回 HTML + Cookie 后同步 HttpFetcher 重试。自身不内嵌 WebView 控件（UI 层职责）。
///
/// M2.4 增强：若源在 `parser.script` / `parser.overrides[apiName].script`
/// 声明了 `jsExtractor` 脚本，则改为抛 [WebViewExtractionRequest] 携带脚本回传，
/// UI 层在 [WebViewVerificationScreen] 内嵌 WebView 加载页面、完成验证后，
/// 用 `evaluateJavascript(jsExtractor)` 抽取真实地址回传给调用方。
library;

import '../models/plugin_config.dart';
import '../scraper/verification_detector.dart';
import '../services/config_loader.dart';
import 'builtin_resolver.dart';
import 'source_resolver.dart';

/// 本会话内「已捕获的渲染 HTML」缓存，按 `(sourceId, apiName)` 维度存储。
///
/// 用途：修复「多个页面需要验证多次」。声明式 `useWebview` 源（如 girigirilove
/// 次元城、pms_fsdm）每次 fetch 都会经 [WebViewResolver] 抛 [WebViewHtmlRequest]
/// 触发内嵌浏览器验证——若不做缓存，刷新列表 / 重新进入详情 / 切到选集都会再弹一次
/// 验证页，用户体验极差。
///
/// 流程：首次某 `(源, 路由)` 触发验证 → UI 捕获渲染 HTML 并回灌 → [MediaApiService]
/// 把该 HTML 写入本缓存；之后同 `(源, 路由)` 再次请求时，[WebViewResolver] 命中缓存
/// 直接复用既有 HTML 解析，**不再弹验证页**。每个路由每会话仅捕获一次。
///
/// 注意：缓存为内存态（进程生命周期内有效），进程重启即失效，避免长期陈旧内容。
class WebViewHtmlCache {
  WebViewHtmlCache._();

  static final Map<String, String> _store = <String, String>{};

  static String _key(String sourceId, String apiName) => '$sourceId::$apiName';

  /// 写入某 (源, 路由) 的渲染 HTML。
  static void set(String sourceId, String apiName, String html) {
    if (html.isEmpty) return;
    _store[_key(sourceId, apiName)] = html;
  }

  /// 读取缓存的渲染 HTML（无则 null）。
  static String? get(String sourceId, String apiName) =>
      _store[_key(sourceId, apiName)];

  /// 清除某源的全部缓存（切源 / 主动刷新本源时调用，避免陈旧内容）。
  static void invalidateSource(String sourceId) {
    _store.removeWhere((k, _) => k.startsWith('$sourceId::'));
  }

  /// 清空全部缓存（保留用于调试 / 强制重新验证）。
  static void clear() => _store.clear();
}

/// 声明式解析器类型集合：[ParserConfig.type] 命中即视为「无脚本、靠选择器解析」。
///
/// 与 `resolver_registry.dart` 中的 `_declarativeTypes` 同义；此处独立声明
/// 避免反向依赖（registry 内部使用，不对外导出）。
const Set<String> _declarativeTypes = <String>{
  'builtin',
  'xpath',
  'jsonpath',
  'css',
};

/// WebView 内嵌抽取请求：携带 [jsExtractor] 脚本由 UI 层在
/// `WebViewVerificationScreen` 内执行后回传真实地址。
///
/// 实现 `Exception` 以便上层 `catch` 与 [WebViewRequiredException] 统一处理；
/// 当 [jsExtractor] 为空时，[WebViewResolver] 仍回退到 [WebViewRequiredException]
/// 走纯手动验证流程（best-effort 抽取失败时同样回退）。
class WebViewExtractionRequest implements Exception {
  /// 触发抽取的源 ID（错误隔离与日志用）。
  final String sourceId;

  /// 调用的 API 名称（latest/detail/episodes/video/...）。
  final String apiName;

  /// 需要在 WebView 中加载并完成验证的 URL。
  final String url;

  /// 在 WebView 内执行的 JS 抽取脚本（应返回字符串地址或 JSON 字符串）。
  final String jsExtractor;

  /// 附加请求头（注入到 InAppWebView 的初始请求）。
  final Map<String, String>? headers;

  const WebViewExtractionRequest({
    required this.sourceId,
    required this.apiName,
    required this.url,
    required this.jsExtractor,
    this.headers,
  });

  @override
  String toString() =>
      'WebViewExtractionRequest(sourceId=$sourceId, apiName=$apiName, url=$url)';
}

/// WebView 渲染后抽取请求：不携带 JS 脚本，仅要求 UI 层在内嵌 WebView 中
/// 加载页面、等待 JS 渲染完成后，用 `controller.getHtml()` 取回完整渲染后
/// HTML，回传给调用方用既有 CSS/XPath 选择器解析。
///
/// 用于 xgcartoon / baozimh 等「列表 / 详情由 JS 动态渲染」的源：不再为每个
/// 源写抽取脚本，而是「渲染 → 取回整页 HTML → 复用既有选择器」一步到位。
class WebViewHtmlRequest implements Exception {
  final String sourceId;
  final String apiName;
  final String url;
  final Map<String, String>? headers;

  const WebViewHtmlRequest({
    required this.sourceId,
    required this.apiName,
    required this.url,
    this.headers,
  });

  @override
  String toString() =>
      'WebViewHtmlRequest(sourceId=$sourceId, apiName=$apiName, url=$url)';
}

class WebViewResolver implements SourceResolver {
  const WebViewResolver();

  /// 选取某 API 的 jsExtractor 脚本：优先 hybrid overrides，再回退顶层 script。
  ///
  /// 仅当 `parser.type` 为 `webview` 或 `hybrid + override.type=webview` 时
  /// 才视为有效的抽取脚本；其他情况返回 null（走 [WebViewRequiredException] 兜底）。
  String? _pickJsExtractor(PluginConfig source, String apiName) {    final parser = source.parser;
    // hybrid 模式下仅当该 API 显式声明 webview override 才走抽取。
    if (parser.type == 'hybrid') {
      final override = parser.overrides?[apiName];
      if (override?.type != 'webview') return null;
      return override?.script?.isNotEmpty == true
          ? override!.script
          : parser.script;
    }
    if (parser.type == 'webview') {
      // 顶层 webview：优先 override 脚本，再回退 parser.script。
      final override = parser.overrides?[apiName];
      if (override?.script?.isNotEmpty == true) return override!.script;
      return parser.script;
    }
    return null;
  }

  /// 是否以「渲染后抽取」(webview-html) 模式处理该 API。
  ///
  /// 满足以下任一条件即为 html 模式：
  /// - 顶层 `parser.type == 'webview-html'`；
  /// - hybrid / 其它模式下的路由级 override `type == 'webview-html'`；
  /// - `source.useWebview==true` 且 `parser.type ∈ {builtin, xpath, jsonpath,
  ///   css, script, hybrid}` **且为视频路由**：对齐旧应用模型——useWebview
  ///   仅对视频启用 WebView 渲染/嗅探，列表/详情/选集等非视频路由不强制
  ///   WebView（否则反爬页上内嵌浏览器崩溃、反复弹验证、列表为空）。
  bool _isHtmlMode(PluginConfig source, String apiName) {
    // 视频路由判定：对齐旧应用 WebViewResolver.canResolve。
    final lower = apiName.toLowerCase();
    final isVideoRoute =
        lower == 'video' || lower == 'episode' || lower.contains('video');

    // 声明式源 + useWebview + 视频路由：走 WebViewHtmlRequest（渲染后整页
    // HTML 回灌给 BuiltinResolver 用既有选择器解析视频）。非视频路由不进此
    // 分支（列表/详情/选集走直连 HTTP，不触发内嵌浏览器）。
    if (source.useWebview &&
        _declarativeTypes.contains(source.parser.type) &&
        isVideoRoute) {
      return true;
    }
    // useWebview + 顶层 script 源 + 视频路由：走「渲染后抽取」。把 WebView
    // 取回的渲染 HTML 作为 raw 喂给 QuickJS 沙箱脚本（ScriptResolver
    // .resolveFromHtml），而非在 WebView 上下文 evaluateJavascript 跑脚本
    // （后者脚本拿不到 ctx.http，函数声明式脚本不会被调用，永远返回空）。
    // 非视频路由不进此分支（脚本源自抓取 ctx.http.get，无需 WebView）。
    if (source.useWebview && source.parser.type == 'script' && isVideoRoute) {
      return true;
    }
    // useWebview + hybrid + 视频路由：走「渲染后抽取」。声明式路由（latest/
    // detail/episodes）由 BuiltinResolver 按 selectors 解析；script override
    // 路由（如 cycani 的 video）由 _resolveFromRenderedHtml 路由到
    // ScriptResolver 用渲染 HTML 当 raw 跑脚本。非视频路由不进此分支。
    if (source.useWebview && source.parser.type == 'hybrid' && isVideoRoute) {
      return true;
    }
    if (source.parser.type == 'webview-html') {
      // 顶层 webview-html：若某路由显式 override 为 webview 且带脚本，
      // 则走 JS 抽取流程（更精确），否则统一渲染后抽取。
      final override = source.parser.overrides?[apiName];
      if (override?.type == 'webview' &&
          override?.script?.isNotEmpty == true) {
        return false;
      }
      return true;
    }
    final override = source.parser.overrides?[apiName];
    return override?.type == 'webview-html';
  }

  @override
  Future<dynamic> resolve(
    PluginConfig source,
    String apiName, {
    Map<String, String> vars = const {},
    void Function(List<dynamic>)? onProgress,
  }) async {
    final base = ConfigLoader.instance.getActiveMirror(source);
    final url =
        source.resolveRouteUrl(apiName, activeBaseUrl: base, vars: vars);
    // webview-html 模式：不执行 JS 抽取脚本，而是渲染后取回整页 HTML，
    // 复用既有 CSS/XPath 选择器解析（见 [WebViewHtmlRequest]）。
    if (_isHtmlMode(source, apiName)) {
      // 本会话已为该 (源, 路由) 捕获过渲染 HTML → 直接复用，避免反复弹验证页
      // （修复「多个页面需要验证多次」）。首次捕获由验证回灌流程写入缓存。
      final cached = WebViewHtmlCache.get(source.id, apiName);
      if (cached != null && cached.isNotEmpty) {
        return BuiltinResolver().resolveFromHtml(
          source,
          apiName,
          cached,
          vars: vars,
        );
      }
      throw WebViewHtmlRequest(
        sourceId: source.id,
        apiName: apiName,
        url: url,
        headers: source.site.headers,
      );
    }
    final jsExtractor = _pickJsExtractor(source, apiName);
    if (jsExtractor != null && jsExtractor.isNotEmpty) {
      // M2.4：携带 jsExtractor 回传，UI 层在内嵌 WebView 中执行抽取。
      throw WebViewExtractionRequest(
        sourceId: source.id,
        apiName: apiName,
        url: url,
        jsExtractor: jsExtractor,
        headers: source.site.headers,
      );
    }
    // 兜底：无 jsExtractor 脚本时走纯验证流程。
    throw WebViewRequiredException(url, headers: source.site.headers);
  }
}
