/// 调试用「单源探针」——仅打印日志，不改任何功能。
///
/// 目的：在 Windows 上定位 Bug②（普通源解析不到 / 采集api源详情页空）。
/// 运行：
///   flutter test test/debug_source_probe_test.dart
/// 只跑某个源（按 id，逗号分隔）：
///   PROBE_ONLY_ID=pms_fsdm,pms_aowu flutter test test/debug_source_probe_test.dart
/// 直接喂一个源 JSON 文件（例如「采集api生成」导出的真实源，它存在
/// SharedPreferences 里、flutter test 加载不到）：
///   PROBE_SOURCE_FILE=C:/Users/xxx/my_source.json flutter test test/debug_source_probe_test.dart
///
/// 输出是一段带分隔符的报告，请整段贴回给开发者，便于定位。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/builtin_resolver.dart';
import 'package:nexhub/core/resolver/resolver_registry.dart';
import 'package:nexhub/core/scraper/http_fetcher.dart';
import 'package:nexhub/core/scraper/verification_detector.dart';
import 'package:nexhub/core/services/source_repository.dart';

/// 列表类路由默认补的翻页/分类变量。App 真实翻页会传这些值；若不补，
/// resolveRouteUrl 会把 {pg}/{page}/{category} 占位清空成 "...&pg=" 导致 400。
const Map<String, String> _defaultListVars = {
  'pg': '1',
  'page': '1',
  'category': '1',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'debug source probe',
    () async {
      await runProbe();
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<void> runProbe() async {
  final out = StringBuffer();
  void log(Object o) => out.writeln(o);

  // ★关键★ flutter test 的 TestWidgetsFlutterBinding 会安装一个「假 HttpClient」，
  // 对所有请求一律返回 HTTP 400（空头空体），用来阻止单测真实联网。
  // 之前探针报告里「所有源都是 400、响应头={}」正是这个假客户端造成的，
  // 与你的网络/代理/解析器完全无关。这里清空它，让探针发起真实请求。
  HttpOverrides.global = null;

  log('');
  log('══════════════════════════════════════════════════════════════');
  log('  NEXHUB 单源探针 (debug single-source probe)');
  log('  时间: ${DateTime.now().toIso8601String()}   平台: ${Platform.operatingSystem}');
  log('  [已恢复真实网络: HttpOverrides.global=null]');
  log('══════════════════════════════════════════════════════════════');

  // 0) 网络模式：默认沿用系统代理（与正式 App 一致）。你的浏览器能正常访问，
  // 说明系统代理/网络可用，因此探针也走系统代理最能反映 App 真实行为。
  // 若想测试「直连」是否更好，可设 PROBE_FORCE_DIRECT=1。
  final forceDirectEnv = Platform.environment['PROBE_FORCE_DIRECT'] ?? '0';
  if (forceDirectEnv == '1') {
    HttpFetcher.setForceDirect(true);
    log('[网络] 已强制直连（绕过系统代理）');
  } else {
    log('[网络] 沿用系统代理设置（与 App 一致）');
  }

  // 1) 加载真实源（内置 + 用户导入，含「采集api生成」产出的源）。
  final repo = await SourceRepository.loadBuiltins();
  try {
    await repo.loadImported();
  } on Object catch (e) {
    log('[warn] 加载导入源失败（SharedPreferences 不可用？）: $e');
  }

  // 单源文件模式：用于探针「采集api生成」产出的真实源。
  // 这类源存在 SharedPreferences，flutter test 下加载不到；可把它导出成
  // JSON 文件，用 PROBE_SOURCE_FILE=路径 直接喂给探针。
  final fileSrc = Platform.environment['PROBE_SOURCE_FILE'];
  final List<PluginConfig> sources;
  if (fileSrc != null && fileSrc.isNotEmpty) {
    try {
      final raw = File(fileSrc).readAsStringSync();
      final s = PluginConfig.fromJsonString(raw);
      sources = [s];
      log('[模式] 从文件加载单源: $fileSrc');
      log('        id=${s.id}  name=${s.name}  baseUrl=${s.site.baseUrl}');
    } on Object catch (e) {
      log('[错误] 无法从文件加载源 ($fileSrc): $e');
      log('══════════════════════════════════════════════════════════════');
      // ignore: avoid_print
      print(out.toString());
      return;
    }
  } else {
    final onlyIds = (Platform.environment['PROBE_ONLY_ID'] ?? '')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    sources = repo.all.where((s) {
      if (onlyIds.isNotEmpty) return onlyIds.contains(s.id);
      // 默认跳过示例源（多半是占位不可用），除非显式指定。
      return !s.id.toLowerCase().contains('example');
    }).toList();

    log('发现源总数: ${repo.all.length}   本次探针覆盖: ${sources.length}');
  }
  log('');

  try {
    for (final source in sources) {
      await probeSource(source, log);
      log('');
    }
  } on Object catch (e, st) {
    log('[fatal] 探针主循环异常（已尽量完成其余源）: $e');
    log('$st');
  }

  log('══════════════════════════════════════════════════════════════');
  log('  探针结束。如仍有疑问，把以上报告整段贴回给开发者。');
  log('══════════════════════════════════════════════════════════════');

  // 一次性打印，避免与测试框架日志交错。
  // ignore: avoid_print
  print(out.toString());
}

bool _isShuyuan(PluginConfig s) =>
    s.selectors?['xiaoshuo'] is Map<String, dynamic>;

bool _isCollectLike(PluginConfig s) {
  for (final r in s.routes.values) {
    final u = r.url.toLowerCase();
    if (u.contains('ac=list') ||
        u.contains('ac=videolist') ||
        u.contains('ac=detail')) {
      return true;
    }
  }
  return false;
}

Future<void> probeSource(PluginConfig source, void Function(Object) log) async {
  log('────────────────────────────────────────────────────────────');
  log('源: ${source.id}  |  ${source.name}');
  log('  类型=${sourceTypeLabel(source.type)}  启用=${source.isEnabled}  '
      'useWebview=${source.useWebview}  parser.type=${source.parser.type}');
  log('  baseUrl=${source.site.baseUrl}');
  log('  路由 keys=${source.routes.keys.join(', ')}');

  if (_isShuyuan(source)) {
    log('  [跳过] 书源（ShuyuanNovelResolver），探针不覆盖。');
    return;
  }

  // 路由决策快照。
  final routeApis = ['latest', 'search', 'explore', 'category', 'detail', 'episodes'];
  final present = routeApis.where(source.routes.containsKey).toList();
  for (final api in present) {
    final t = ResolverRegistry.instance.effectiveResolverType(source, api);
    log('  路由决策 [$api] -> $t');
  }

  try {
    if (_isCollectLike(source)) {
      await _probeCollectChain(source, log);
    } else {
      await _probeNormalSource(source, log);
    }
  } on Object catch (e, st) {
    log('  [fatal] 该源探针异常: $e');
    log('  $st');
  }
}

/// 在 [names] 中返回 [source] 第一个存在的路由 key（无则 null）。
String? _pickRoute(PluginConfig source, List<String> names) {
  for (final n in names) {
    if (source.routes.containsKey(n)) return n;
  }
  return null;
}

/// 普通源：报告解析类型 + 真实 HTTP 状态，验证 M1a（useWebview 路由）是否生效。
Future<void> _probeNormalSource(PluginConfig source, void Function(Object) log) async {
  log('  [模式] 普通源（非采集api）');
  final listApi = _pickRoute(source, ['latest', 'search', 'explore']);
  if (listApi == null) {
    log('  [跳过] 无 latest/search/explore 路由，无法取列。');
    return;
  }
  final type = ResolverRegistry.instance.effectiveResolverType(source, listApi);
  if (type == 'webview' || type == 'script') {
    log('  [路由=$type] 该源需走 WebView/脚本渲染（过反爬），无头环境无法解析，'
        '请确认 App 内弹出的验证页能正常同步 Cookie 后重试。');
    // 仍然打一次原始请求，看是否返回验证挑战页，帮助判断是不是反爬。
    final url = _safeUrl(source, listApi, _defaultListVars);
    if (url != null) {
      final dual = await _rawFetchDual(url, source.site.baseUrl);
      _logDualRaw(log, '原始请求', url, dual.a, dual.b, dual.bDirect);
    }
    return;
  }
  // builtin：直接解析列，看是否空。
  final url = _safeUrl(source, listApi, _defaultListVars);
  log('  列请求 URL: ${url ?? '(无法构造)'}');
  if (url == null) return;
  final dual = await _rawFetchDual(url, source.site.baseUrl);
  _logDualRaw(log, '原始请求', url, dual.a, dual.b, dual.bDirect);
  if (dual.a.verification || dual.b.verification) {
    log('  ⚠️ 命中验证/反爬挑战页——BuiltinResolver 解析到 0 条是正常的，'
        '根因是 Cookie 未过验证。请确认 App 内验证流程。');
    return;
  }
  try {
    final items = await const BuiltinResolver().resolve(
      source,
      listApi,
      vars: _defaultListVars,
    ) as List<dynamic>;
    log('  解析列结果: ${items.length} 条');
    if (items.isEmpty) {
      log('  ⚠️ 列表为空但 HTTP 200 且非验证页——多为「选择器失效（站点改版）」或'
          '「返回结构非预期」。请把 body 前 200 字贴回分析。');
    } else {
      log('  ✅ 列解析正常，首条标题: ${(items.first as dynamic).title}');
    }
  } on VerificationRequiredException catch (e) {
    log('  ⚠️ 解析时命中验证: status=${e.statusCode}');
  } on Object catch (e) {
    log('  [解析异常] $e');
  }
}

/// 采集api源：跑 latest→detail→episodes 全链路，复现「详情页空」。
Future<void> _probeCollectChain(PluginConfig source, void Function(Object) log) async {
  log('  [模式] 采集api源（MacCMS ac=list/detail）');

  if (!source.routes.containsKey('latest')) {
    log('  [跳过] 无 latest 路由，无法取列。');
    return;
  }
  final listType =
      ResolverRegistry.instance.effectiveResolverType(source, 'latest');
  if (listType == 'webview' || listType == 'script') {
    log('  ⚠️ latest 被路由到 $listType（useWebview 导致），无头无法解析。'
        '若本源是纯 MacCMS api，请确认其 useWebview 应为 false。');
  }

  final listUrl = _safeUrl(source, 'latest', _defaultListVars);
  log('  latest URL: ${listUrl ?? '(无法构造)'}');
  if (listUrl == null) return;

  // 原始请求快照（看 400 来自站点还是中间代理，以及响应头；双模式对比）。
  final dual = await _rawFetchDual(listUrl, source.site.baseUrl);
  _logDualRaw(log, '原始请求', listUrl, dual.a, dual.b, dual.bDirect);

  List<dynamic> items = [];
  try {
    final r = await const BuiltinResolver().resolve(
      source,
      'latest',
      vars: _defaultListVars,
    );
    items = r is List ? r : <dynamic>[];
  } on VerificationRequiredException catch (e) {
    log('  ⚠️ latest 命中验证: ${e.statusCode}');
  } on Object catch (e) {
    log('  [latest 解析异常] $e');
  }
  log('  latest 解析: ${items.length} 条');

  if (items.isEmpty) {
    log('  ⚠️ 列表就为空 → 详情页必然空。问题在列表层（路由/反爬/选择器）。');
    return;
  }

  final first = items.first as dynamic;
  final id = '${first.id ?? ''}';
  final title = '${first.title ?? ''}';
  log('  首条: id=$id  title=$title');
  if (id.isEmpty) {
    log('  ⚠️ 列表项缺少 id → 后续 detail/episodes 无法构造 URL。');
    return;
  }

  // detail
  if (source.routes.containsKey('detail')) {
    final dUrl = _safeUrl(source, 'detail', {'id': id});
    log('  detail URL: ${dUrl ?? '(无法构造)'}');
    if (dUrl != null) {
      try {
        final detail = await const BuiltinResolver().resolve(
          source,
          'detail',
          vars: {'id': id},
        ) as dynamic;
        final ok = detail != null &&
            '${detail.title ?? ''}'.isNotEmpty;
        log('  detail 解析: title=${detail?.title}  descLen='
            '${'${detail?.description ?? ''}'.length}  '
            'cover=${detail?.coverUrl != null && '${detail.coverUrl}'.isNotEmpty}');
        log(ok ? '  ✅ detail 有内容' : '  ⚠️ detail 解析为空（复现「详情页空」）');
      } on PluginConfigException catch (e) {
        log('  ⚠️ detail 路由缺失: $e');
      } on VerificationRequiredException catch (e) {
        log('  ⚠️ detail 命中验证: ${e.statusCode}');
      } on Object catch (e) {
        log('  [detail 解析异常] $e');
      }
    }
  } else {
    log('  [提示] 该源无 detail 路由（详情页可能只靠列表项的字段）。');
  }

  // episodes
  if (source.routes.containsKey('episodes')) {
    final eUrl = _safeUrl(source, 'episodes', {'id': id});
    log('  episodes URL: ${eUrl ?? '(无法构造)'}');
    if (eUrl != null) {
      try {
        final eps = await const BuiltinResolver().resolve(
          source,
          'episodes',
          vars: {'id': id},
        ) as List<dynamic>;
        log('  episodes 解析: ${eps.length} 条');
        if (eps.isEmpty) {
          log('  ⚠️ episodes 为空（复现「选集/播放线路空」）——'
              '多为 vod_play_from/vod_play_url 字段名不符或为空。');
        } else {
          final ep = eps.first as dynamic;
          log('  ✅ 首集: ${ep.title}  line=${ep.lineName}  url非空='
              '${'${ep.url ?? ''}'.isNotEmpty}');
        }
      } on PluginConfigException catch (e) {
        log('  ⚠️ episodes 路由缺失: $e');
      } on VerificationRequiredException catch (e) {
        log('  ⚠️ episodes 命中验证: ${e.statusCode}');
      } on Object catch (e) {
        log('  [episodes 解析异常] $e');
      }
    }
  } else {
    log('  [提示] 该源无 episodes 路由。');
  }
}

String? _safeUrl(PluginConfig source, String api, [Map<String, String> vars = const {}]) {
  try {
    final base = source.site.baseUrl;
    return source.resolveRouteUrl(api, activeBaseUrl: base, vars: vars);
  } on Object {
    return null;
  }
}

Future<_RawResult> _rawFetch(
  String url,
  String referer, {
  bool? forceDirectOverride,
}) async {
  final restore = HttpFetcher.forceDirect;
  if (forceDirectOverride != null) HttpFetcher.setForceDirect(forceDirectOverride);
  try {
    final resp = await HttpFetcher.instance.fetch(url, referer: referer);
    final respHeaders = resp['headers'] as Map<String, dynamic>? ?? {};
    return _RawResult(
      status: resp['status'] as int? ?? 0,
      body: resp['body'] as String? ?? '',
      verification: false,
      error: null,
      respHeaders: respHeaders,
    );
  } on VerificationRequiredException catch (e) {
    return _RawResult(
      status: e.statusCode ?? 0,
      body: e.body ?? '',
      verification: true,
      error: null,
    );
  } on HttpStatusException catch (e) {
    return _RawResult(status: 0, body: '', verification: false, error: 'HTTP $e');
  } on Object catch (e) {
    return _RawResult(status: 0, body: '', verification: false, error: '$e');
  } finally {
    if (forceDirectOverride != null) HttpFetcher.setForceDirect(restore);
  }
}

/// 同一 URL 在「当前模式」与「另一模式」各取一次，便于判断究竟是
/// 代理/VPN 在拦截（两模式都 400 且无响应头）还是站点本身拒绝（有站点响应头）。
Future<({_RawResult a, _RawResult b, bool bDirect})> _rawFetchDual(
  String url,
  String referer,
) async {
  final a = await _rawFetch(url, referer);
  final bDirect = !HttpFetcher.forceDirect;
  final b = await _rawFetch(url, referer, forceDirectOverride: bDirect);
  return (a: a, b: b, bDirect: bDirect);
}

void _logDualRaw(
  void Function(Object) log,
  String label,
  String url,
  _RawResult a,
  _RawResult b,
  bool bDirect,
) {
  log('  $label: $url');
  log('    [模式A 当前] status=${a.status} verification=${a.verification} '
      'bodyLen=${a.body.length} 响应头=${a.respHeaders}');
  log('    [模式B ${bDirect ? "直连" : "代理"}] status=${b.status} '
      'verification=${b.verification} bodyLen=${b.body.length} '
      '响应头=${b.respHeaders}');
  log('    body前200: ${_preview(a.body.isNotEmpty ? a.body : b.body)}');
}

class _RawResult {
  const _RawResult({
    required this.status,
    required this.body,
    required this.verification,
    required this.error,
    this.respHeaders = const {},
  });
  final int status;
  final String body;
  final bool verification;
  final String? error;
  final Map<String, dynamic> respHeaders;
}

String _preview(String body) {
  final cleaned = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.length > 200 ? '${cleaned.substring(0, 200)}…' : cleaned;
}

String sourceTypeLabel(SourceType t) {
  switch (t) {
    case SourceType.animeSource:
      return '动漫';
    case SourceType.mangaSource:
      return '漫画';
    case SourceType.novelSource:
      return '小说';
  }
}
