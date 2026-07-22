/// 书源到 PluginConfig 的适配器：保留原始规则在 `selectors['xiaoshuo']`
/// 中供 ShuyuanNovelResolver 回写为 XiaoshuoBookSource，同时声明 search/detail/
/// toc/content/explore 路由供 MediaApiService 调度。
///
/// 与旧版（xiaoshuo_adapter）差异：
/// - `PluginType.novelSource` → `SourceType.novelSource`
/// - `parser` 字段在新 PluginConfig 中为必填，默认 `ParserConfig(type: 'builtin')`
///   但被 ResolverRegistry 识别为 xiaoshuo 源时改走 ShuyuanNovelResolver
/// - 不再把书源规则强制降级为 CSS 选择器，而是原样保留完整规则
library;

import '../../core/models/plugin_config.dart';
import 'shuyuan_source_service.dart';

class ShuyuanAdapter {
  /// 将书源转换为 PluginConfig。
  static PluginConfig toPluginConfig(ShuyuanSource source) {
    final baseUrl = source.bookSourceUrl;
    final routes = <String, RouteConfig>{};

    // 路由声明：URL 留空，由 ShuyuanNovelResolver 通过 WebBook/AnalyzeUrl
    // 自行根据 XiaoshuoBookSource.searchUrl/exploreUrl 等字段解析。
    if (source.searchUrl != null && source.searchUrl!.isNotEmpty) {
      routes['search'] = const RouteConfig(url: '', method: 'GET');
    }
    if (source.ruleBookInfo != null) {
      routes['detail'] = const RouteConfig(url: '', method: 'GET');
    }
    if (source.ruleToc != null) {
      routes['toc'] = const RouteConfig(url: '', method: 'GET');
      routes['chapters'] = const RouteConfig(url: '', method: 'GET');
    }
    if (source.ruleContent != null) {
      routes['content'] = const RouteConfig(url: '', method: 'GET');
    }
    if (source.exploreUrl != null && source.exploreUrl!.isNotEmpty) {
      routes['explore'] = const RouteConfig(url: '', method: 'GET');
      // 没有 searchUrl 时，发现页可作为 latest 回退
      if (!routes.containsKey('search')) {
        routes['search'] = const RouteConfig(url: '', method: 'GET');
      }
    }

    // 'latest' 路由：发现页列表的默认入口（NovelOnlineListScreen 优先调用
    // 'latest'，若缺省则取 routes.keys.first，可能误调到 'search'）。
    // ShuyuanNovelResolver 在 'latest' 上回退到 exploreBook。
    if (routes.containsKey('explore') && !routes.containsKey('latest')) {
      routes['latest'] = const RouteConfig(url: '', method: 'GET');
    } else if (!routes.containsKey('latest') && routes.isNotEmpty) {
      routes['latest'] = routes.values.first;
    }

    // 选择器：保留完整书源规则在 'xiaoshuo' 键下，供 ShuyuanNovelResolver
    // 反序列化为 XiaoshuoBookSource 直接驱动 WebBook。
    final selectors = <String, dynamic>{
      'xiaoshuo': {
        'bookSourceName': source.bookSourceName,
        'bookSourceUrl': source.bookSourceUrl,
        'bookSourceType': source.bookSourceType,
        'bookSourceGroup': source.bookSourceGroup,
        'bookSourceComment': source.bookSourceComment,
        'enabled': source.enabled,
        'header': source.header,
        'searchUrl': source.searchUrl,
        'exploreUrl': source.exploreUrl,
        'tocUrl': source.tocUrl,
        'ruleSearch': source.ruleSearch,
        'ruleBookInfo': source.ruleBookInfo,
        'ruleToc': source.ruleToc,
        'ruleContent': source.ruleContent,
        'ruleExplore': source.ruleExplore,
      },
    };

    // 反盗链：用书源 baseUrl 作为默认 Referer（书源 header 字段也透传到
    // AnalyzeUrl 中由 getStrResponse 处理）。
    final antiHotlinking = AntiHotlinkingConfig(referer: baseUrl);

    return PluginConfig(
      id: 'xiaoshuo_${_urlToId(baseUrl)}',
      name: source.bookSourceName,
      type: SourceType.novelSource,
      responseType: 'html',
      site: SiteConfig(
        domain: Uri.tryParse(baseUrl)?.host ?? baseUrl,
        baseUrl: baseUrl,
      ),
      parser: const ParserConfig(type: 'builtin'),
      routes: routes,
      selectors: selectors,
      antiHotlinking: antiHotlinking,
      enabled: source.enabled,
      enabledExplore: source.enabled,
    );
  }

  /// 从 PluginConfig 反向恢复 XiaoshuoBookSource（供 ShuyuanNovelResolver 使用）。
  static ShuyuanSource? fromPluginConfig(PluginConfig config) {
    final xiaoshuo = config.selectors?['xiaoshuo'];
    if (xiaoshuo is! Map<String, dynamic>) return null;
    return ShuyuanSource.fromJson(xiaoshuo);
  }

  /// 判断 PluginConfig 是否为书源（ShuyuanNovelResolver 应处理）。
  static bool isShuyuanSource(PluginConfig config) {
    return config.selectors?['xiaoshuo'] is Map<String, dynamic>;
  }

  static String _urlToId(String url) {
    final id = url
        .replaceAll(RegExp(r'https?://'), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (id.isEmpty) return 'unknown';
    return id.substring(0, 60.clamp(0, id.length));
  }
}
