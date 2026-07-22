/// 验证检测与异常定义。
///
/// 任一拦截路径（详情/播放/浏览/搜索/预加载/headless）命中验证特征时，
/// HttpFetcher 抛出 [VerificationRequiredException]；需要 WebView 过验证时
/// WebViewResolver 抛出 [WebViewRequiredException]。上层据此弹验证页并同步 Cookie 后重试。
library;

/// 需要网页验证（401/403/Cloudflare/CAPTCHA/滑块）。
class VerificationRequiredException implements Exception {
  final String url;
  final Map<String, String>? headers;
  final String? body;
  final int? statusCode;

  const VerificationRequiredException({
    required this.url,
    this.headers,
    this.body,
    this.statusCode,
  });

  @override
  String toString() =>
      'VerificationRequiredException(status=$statusCode, url=$url)';
}

/// 该源/路由需要走 WebView（headless 加载 + 过验证/取 HTML）。
class WebViewRequiredException implements Exception {
  final String url;
  final Map<String, String>? headers;

  const WebViewRequiredException(this.url, {this.headers});

  @override
  String toString() => 'WebViewRequiredException(url=$url)';
}

/// 单个源解析失败（错误隔离用，不影响其他源）。
class SourceResolveException implements Exception {
  final String sourceId;
  final String apiName;
  final String message;

  const SourceResolveException({
    required this.sourceId,
    required this.apiName,
    required this.message,
  });

  @override
  String toString() =>
      'SourceResolveException($sourceId/$apiName): $message';
}

/// HTTP 4xx/5xx 错误（非验证类）。
///
/// HttpFetcher 在通过验证检测后，若状态码仍 ≥ 400（如 404/500/502），
/// 抛出此异常以便上层显示明确错误 + 重试，而非把错误页 body 当成正常
/// 响应交给解析器，导致静默空列表。
class HttpStatusException implements Exception {
  final String url;
  final int statusCode;
  final String? body;

  const HttpStatusException({
    required this.url,
    required this.statusCode,
    this.body,
  });

  @override
  String toString() => 'HttpStatusException($statusCode, url=$url)';
}

class VerificationDetector {
  VerificationDetector._();

  /// 主动挑战标记：仅出现在真正的验证/反爬挑战页（5秒盾、滑块、CAPTCHA、
  /// Cloudflare 真实「Just a moment」页），正常内容页绝不会出现。命中即判为验证页。
  ///
  /// 注意：避免把整段域名（如 `fsdm02`）作为特征——源站正常页面里也会在
  /// URL/脚本/链接中出现自己的域名，会导致整站正常响应被误判为验证页，
  /// 进而触发验证循环（用户看到「需要验证」但验证完仍打不开）。fsdm02 的
  /// 滑块验证页已经通过 `/_guard/html.js` / `/_guard/slide.js` 精确识别。
  static const List<String> _activeChallengeMarkers = <String>[
    '__cf_chl',
    'g-recaptcha',
    'turnstile',
    'input[type=password]',
    '/_guard/html.js',
    '/_guard/slide.js',
    'slider_html',
    'challenge-form',
    'challenge-stage',
    'data-sitekey',
  ];

  /// 被动 CF 标记：Cloudflare 为「每一个」经它代理的页面注入（包括正常内容页，
  /// 例如 `/cdn-cgi/challenge-platform/scripts/jsd/main.js` 这段 bot 检测脚本）。
  /// goda 这类站点的正常 200 大页面（47–62KB）就包含它。单凭它命中会误伤 →
  /// 验证死循环。因此被动标记只在 body「极短（真实挑战页通常只有几 KB 的等待/
  /// 重定向壳）」时才结合判定，正常大内容页直接放行。
  static const List<String> _passiveCfMarkers = <String>[
    'cf-ray',
    'challenge-platform',
  ];

  /// WAF/反爬「拦截应答」的精确 body 特征：整段 body 去掉首尾空白后**全字匹配**
  /// （大小写不敏感）才算命中。
  ///
  /// 背景：cycani / girigirilove 等站点挂在「Edge WAF」后面（响应头 Server 形如
  /// `Edge/1.1.18`）。当它判定请求疑似机器人时，会返回 HTTP 200，但 body 只有一个
  /// 极短的拦截词——实测就是 `closed`。旧逻辑只认 Cloudflare/滑块特征，于是把
  /// `closed` 当成「正常内容」丢给解析器 → 解析出 0 条 → 用户只看到空白列表，
  /// 永远不会弹验证页。
  ///
  /// 为什么用「全字匹配」而不是 contains：正常网页/JSON 永远不会「整段只有一个
  /// closed」，全字匹配几乎不可能误伤真实内容；而 contains('closed') 会把任何正常
  /// 页面里出现的 closed 一词（如「已完结 closed」）误判为验证页，触发验证死循环。
  static const Set<String> _wafBlockBodies = <String>{
    'closed',
  };

  /// 已知 WAF 的 Server 响应头签名（小写子串匹配）。
  ///
  /// 仅作为「辅助信号」：单看 Server 头不足以判定验证（同一个 WAF 放行后也用这个
  /// Server 头发正常内容）。只有当 body 同时「短且不像正常内容」时才结合它判定，
  /// 覆盖「拦截词有变化 / body 为空」等 `_wafBlockBodies` 没枚举到的变体。
  static const List<String> _wafServerSignatures = <String>[
    'edge/1.1',
  ];

  /// 检查顺序：403/401 先于「无 body」；503 解码 body 后看挑战特征；
  /// 200 + 主动挑战标记 / (被动CF标记 + 极短壳) / WAF 拦截应答 也判。
  static bool isVerificationRequired({
    required int? statusCode,
    required String? body,
    Map<String, String>? headers,
  }) {
    final code = statusCode;
    if (code == 401 || code == 403) return true;
    if (code == 503) {
      // 503 本身已是强挑战信号：CF 的 503 挑战页含被动标记且体积极小，
      // 不做长度闸门，避免漏判。
      return _hasActiveChallenge(body ?? '') ||
          _hasPassiveCf(body ?? '') ||
          _isWafBlock(body, headers);
    }
    if (code == 200) {
      // 主动挑战标记（仅真实挑战页有）→ 直接判。
      if (body != null && _hasActiveChallenge(body)) return true;
      // 被动 CF 标记（正常页也有）→ 仅当 body 极短（挑战壳）时才判，
      // 放行 goda 这类 47–62KB 的正常大页面。
      if (body != null &&
          _hasPassiveCf(body) &&
          _isLikelyChallengeShell(body)) {
        return true;
      }
      if (_isWafBlock(body, headers)) return true;
    }
    return false;
  }

  static bool _hasActiveChallenge(String body) {
    final lower = body.toLowerCase();
    return _activeChallengeMarkers
        .any((f) => lower.contains(f.toLowerCase()));
  }

  static bool _hasPassiveCf(String body) {
    final lower = body.toLowerCase();
    return _passiveCfMarkers.any((f) => lower.contains(f.toLowerCase()));
  }

  /// 真实 CF 挑战页特征：体积极小（仅为「等待 5 秒 / 重定向」壳，通常 < 8KB），
  /// 不像正常大内容（goda 正常页 47–62KB，远超过阈值，不会误伤）。
  ///
  /// 仅作为「被动 CF 标记」的辅助闸门：body 既含被动标记又极短 → 才判为挑战。
  static bool _isLikelyChallengeShell(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;
    return trimmed.length <= 8192;
  }

  /// 判断是否为 WAF/反爬「拦截应答」（应走内置浏览器过验证，而非当空内容）。
  ///
  /// 两条命中路径：
  /// 1) body 去空白后全字命中 [_wafBlockBodies]（如整段就是 `closed`）；
  /// 2) 响应头 Server 命中已知 WAF 签名，且 body「短且不像正常内容」
  ///    （极短、且不是以 `{`/`[`/`<` 开头的 JSON/HTML）——覆盖拦截词变体或空 body。
  static bool _isWafBlock(String? body, Map<String, String>? headers) {
    final trimmed = (body ?? '').trim();
    final lower = trimmed.toLowerCase();
    if (_wafBlockBodies.contains(lower)) return true;

    final server = _serverHeader(headers);
    if (server != null &&
        _wafServerSignatures.any((s) => server.contains(s))) {
      // Server 头是已知 WAF：仅当 body 短且不像正常 JSON/HTML 才判为拦截，
      // 避免把「同一 WAF 放行后返回的正常大响应」误伤。
      if (trimmed.length <= 32 &&
          !trimmed.startsWith('{') &&
          !trimmed.startsWith('[') &&
          !trimmed.startsWith('<')) {
        return true;
      }
    }
    return false;
  }

  /// 大小写不敏感地取 Server 响应头（Dio 的 header key 可能是任意大小写）。
  static String? _serverHeader(Map<String, String>? headers) {
    if (headers == null) return null;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'server') {
        return entry.value.toLowerCase();
      }
    }
    return null;
  }
}
