/// WebView 验证页面（文档 §6 验证流程）。
///
/// 当 [VerificationRequiredException] 被捕获时，UI 层导航到此页面。
/// 用户在浏览器中完成验证（Cloudflare / CAPTCHA / 滑块），返回后点击
/// 「已完成验证，重试」按钮，由调用方重试原始请求。
///
/// 在支持 WebView 的移动平台上可后续扩展为内嵌 WebView + Cookie 同步；
/// 当前实现使用 [url_launcher] 打开系统浏览器作为通用回退方案。
///
/// M2.4 增强：当传入 [WebViewExtractionRequest] 时切换为内嵌 [InAppWebView]
/// 模式，加载页面让用户完成验证，再点击「用此页抽取」按钮执行 [jsExtractor]
/// 脚本抽取真实地址回传给调用方；抽取失败时回退到 [url_launcher] 手动流程。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/resolver/webview_resolver.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../../../core/scraper/verification_detector.dart';
import '../../../core/theme/app_tokens.dart';
import '../../browser/presentation/http_browser_screen.dart';

/// 验证结果。
enum VerificationResult {
  /// 用户表示已完成验证，需要重试。
  done,
  /// 用户取消。
  cancelled,
}

/// WebView 抽取/验证流程的最终结果。
///
/// 调用方优先判断 [extractedUrl] 是否非空：非空则直接用作解析结果，
/// 否则按 [result] 决定是否重试原始请求。
class WebViewExtractionOutcome {
  final VerificationResult result;
  final String? extractedUrl;
  final String? renderedHtml;

  const WebViewExtractionOutcome({
    required this.result,
    this.extractedUrl,
    this.renderedHtml,
  });

  /// 用户已完成验证并希望重试。
  bool get shouldRetry => result == VerificationResult.done;

  /// 是否成功抽取到地址。
  bool get hasExtractedUrl =>
      extractedUrl != null && extractedUrl!.isNotEmpty;

  /// 是否成功取回渲染后 HTML。
  bool get hasRenderedHtml =>
      renderedHtml != null && renderedHtml!.isNotEmpty;
}

/// WebView 验证页面。
///
/// [verificationUrl] 是触发验证的 URL；[onRetry] 是验证完成后回调。
/// [extractionRequest] 非空时启用 M2.4 内嵌抽取流程。
/// [htmlRequest] 非空时启用「渲染后抽取」流程（取回整页渲染 HTML）。
class WebViewVerificationScreen extends StatefulWidget {
  final String verificationUrl;
  final VerificationRequiredException? exception;
  final WebViewExtractionRequest? extractionRequest;
  final WebViewHtmlRequest? htmlRequest;

  const WebViewVerificationScreen({
    super.key,
    required this.verificationUrl,
    this.exception,
    this.extractionRequest,
    this.htmlRequest,
  });

  @override
  State<WebViewVerificationScreen> createState() =>
      _WebViewVerificationScreenState();
}

class _WebViewVerificationScreenState extends State<WebViewVerificationScreen> {
  bool _browserOpened = false;
  InAppWebViewController? _webViewController;
  bool _pageLoaded = false;
  bool _extracting = false;
  String? _extractionError;

  /// 是否启用 M2.4 内嵌抽取流程。
  bool get _hasExtractionRequest => widget.extractionRequest != null;

  /// 是否启用「渲染后抽取」流程（取回整页渲染 HTML）。
  bool get _hasHtmlRequest => widget.htmlRequest != null;

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.verificationUrl);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) {
        setState(() => _browserOpened = true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).webViewNotAvailable),
          ),
        );
      }
    }
  }

  /// 打开内置浏览器完成验证（M3.1）。
  ///
  /// 内置浏览器在「用此页完成验证」时会将最新 Cookie 同步到 [HttpFetcher]；
  /// 返回 `true` 时直接以 [VerificationResult.done] 结束，触发上层重试。
  Future<void> _openInternalBrowser() async {
    final used = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => HttpBrowserScreen(initialUrl: widget.verificationUrl),
      ),
    );
    if (used == true && mounted) {
      // HttpBrowserScreen 已同步最新 Cookie，直接返回 done 触发重试。
      Navigator.of(context).pop(VerificationResult.done);
    }
  }

  void _finish() {
    // 同步 Cookie（best-effort：外部浏览器 Cookie 无法直接读取，
    // 但如果验证基于 IP/服务端 session，重试时 HttpFetcher 自带 Cookie 可能已够用）。
    final host = Uri.tryParse(widget.verificationUrl)?.host;
    if (host != null && widget.exception?.headers != null) {
      // 将已有 Cookie 头写回 HttpFetcher 以保留已有会话。
      final cookieHeader =
          widget.exception!.headers?['Cookie'] ?? widget.exception!.headers?['cookie'];
      if (cookieHeader != null) {
        HttpFetcher.instance.syncCookies(host, cookieHeader);
      }
    }
    Navigator.of(context).pop(VerificationResult.done);
  }

  /// 同步内嵌 WebView 的 Cookie 到 HttpFetcher（best-effort，跨域父域匹配）。
  Future<void> _syncWebviewCookies() async {
    try {
      final uri = Uri.tryParse(widget.verificationUrl);
      if (uri == null) return;
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri('${uri.scheme}://${uri.host}'),
      );
      if (cookies.isEmpty) return;
      final cookieHeader = cookies
          .where((c) => c.value.isNotEmpty)
          .map((c) => '${c.name}=${c.value}')
          .join('; ');
      if (cookieHeader.isNotEmpty) {
        HttpFetcher.instance.syncCookies(uri.host, cookieHeader);
      }
    } catch (_) {
      // Cookie 读取失败不影响主流程。
    }
  }

  /// 执行 jsExtractor 脚本并解析回传地址。
  ///
  /// 兼容三种返回格式：原始 URL 字符串、JSON 对象（含 url/src/video 字段）、
  /// JSON 数组（取第一个有效 URL）。失败时返回 null 并设置 [_extractionError]。
  Future<void> _runExtraction() async {
    final controller = _webViewController;
    final request = widget.extractionRequest;
    if (controller == null || request == null) return;
    setState(() {
      _extracting = true;
      _extractionError = null;
    });
    try {
      // 先同步 Cookie，让重试时 HttpFetcher 带上验证后的会话。
      await _syncWebviewCookies();
      final raw = await controller.evaluateJavascript(
        source: request.jsExtractor,
      );
      final extracted = _parseExtractedResult(raw);
      if (extracted != null && extracted.isNotEmpty) {
        if (mounted) {
          Navigator.of(context).pop(
            WebViewExtractionOutcome(
              result: VerificationResult.done,
              extractedUrl: extracted,
            ),
          );
        }
        return;
      }
      // 抽取脚本返回空值或无法识别的格式。
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractionError =
              AppLocalizations.of(context).extractNoResult;
        });
      }
    } catch (e) {
      // best-effort：抽取失败时回退到手动验证流程。
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractionError =
              '${AppLocalizations.of(context).extractFailed}: $e';
        });
      }
    }
  }

  /// 解析 jsExtractor 返回值，兼容字符串/JSON 对象/JSON 数组三种格式。
  String? _parseExtractedResult(dynamic result) {
    if (result == null) return null;
    // 1. 字符串：直接当作 URL，或尝试 JSON 解码。
    if (result is String) {
      final trimmed = result.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return trimmed;
      }
      try {
        final decoded = jsonDecode(trimmed);
        return _parseExtractedResult(decoded);
      } catch (_) {
        return null;
      }
    }
    // 2. List：递归取第一个有效 URL。
    if (result is List) {
      for (final item in result) {
        final parsed = _parseExtractedResult(item);
        if (parsed != null && parsed.isNotEmpty) return parsed;
      }
      return null;
    }
    // 3. Map：按常见字段优先级取值。
    if (result is Map) {
      const keys = <String>['url', 'src', 'video', 'file', 'source', 'link'];
      for (final key in keys) {
        final value = result[key];
        if (value is String && value.startsWith('http')) return value;
        if (value is List || value is Map) {
          final parsed = _parseExtractedResult(value);
          if (parsed != null && parsed.isNotEmpty) return parsed;
        }
      }
      return null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // 渲染后抽取：优先于 JS 抽取（二者不会同时出现）。
    if (_hasHtmlRequest) {
      return _buildHtmlCaptureScaffold(context, l10n);
    }
    // M2.4：有抽取请求时切换为内嵌 WebView 抽取视图。
    if (_hasExtractionRequest) {
      return _buildExtractionScaffold(context, l10n);
    }
    return _buildLegacyScaffold(context, l10n);
  }

  /// M2.4 内嵌抽取视图：InAppWebView 加载页面 + 底部「用此页抽取」操作栏。
  Widget _buildExtractionScaffold(BuildContext context, AppLocalizations l10n) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.verificationRequired),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(
              const WebViewExtractionOutcome(
                result: VerificationResult.cancelled,
              ),
            ),
          ),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: l10n.openInBrowser,
              onPressed: _openInBrowser,
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                children: <Widget>[
                  InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(widget.verificationUrl),
                      headers: widget.extractionRequest?.headers,
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      mediaPlaybackRequiresUserGesture: false,
                      useShouldOverrideUrlLoading: true,
                    ),
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                    },
                    shouldOverrideUrlLoading: (controller, navigationAction) async {
                      return NavigationActionPolicy.ALLOW;
                    },
                    onLoadStop: (controller, url) async {
                      if (!_pageLoaded && mounted) {
                        setState(() => _pageLoaded = true);
                      }
                      // 页面加载完成后立即同步 Cookie，确保后续抽取与会话一致。
                      await _syncWebviewCookies();
                    },
                  ),
                  if (!_pageLoaded)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
            // 底部操作栏：状态提示 + 抽取按钮 + 手动回退按钮。
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceMd,
                AppTokens.spaceSm,
                AppTokens.spaceMd,
                AppTokens.spaceMd,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                border: Border(
                  top: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_extractionError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                      child: Text(
                        _extractionError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                      ),
                    ),
                  if (_extracting)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: AppTokens.spaceSm),
                          Text(l10n.extracting),
                        ],
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _pageLoaded ? _runExtraction : null,
                      icon: const Icon(Icons.auto_fix_high),
                      label: Text(l10n.extractFromPage),
                    ),
                  const SizedBox(height: AppTokens.spaceSm),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          l10n.extractHint,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      const WebViewExtractionOutcome(
                        result: VerificationResult.done,
                      ),
                    ),
                    child: Text(l10n.verificationDone),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 渲染后抽取视图：InAppWebView 加载页面 + 底部「抓取本页渲染内容」操作栏。
  ///
  /// 与 JS 抽取不同，这里不执行脚本，而是等页面 JS 渲染完成后调用
  /// `controller.getHtml()` 取回完整 HTML，交回调用方用既有选择器解析。
  Widget _buildHtmlCaptureScaffold(
      BuildContext context, AppLocalizations l10n) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.verificationRequired),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(
              const WebViewExtractionOutcome(
                result: VerificationResult.cancelled,
              ),
            ),
          ),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: l10n.openInBrowser,
              onPressed: _openInBrowser,
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: Stack(
                children: <Widget>[
                  InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(widget.verificationUrl),
                      headers: widget.htmlRequest?.headers,
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      mediaPlaybackRequiresUserGesture: false,
                      useShouldOverrideUrlLoading: true,
                    ),
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                    },
                    shouldOverrideUrlLoading: (controller, navigationAction) async {
                      return NavigationActionPolicy.ALLOW;
                    },
                    onLoadStop: (controller, url) async {
                      if (!_pageLoaded && mounted) {
                        setState(() => _pageLoaded = true);
                      }
                      // 页面加载完成后立即同步 Cookie，确保后续解析与会话一致。
                      await _syncWebviewCookies();
                    },
                  ),
                  if (!_pageLoaded)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceMd,
                AppTokens.spaceSm,
                AppTokens.spaceMd,
                AppTokens.spaceMd,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                border: Border(
                  top: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_extractionError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                      child: Text(
                        _extractionError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                      ),
                    ),
                  if (_extracting)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: AppTokens.spaceSm),
                          Text(l10n.capturing),
                        ],
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _pageLoaded ? _captureHtml : null,
                      icon: const Icon(Icons.auto_fix_high),
                      label: Text(l10n.captureFromPage),
                    ),
                  const SizedBox(height: AppTokens.spaceSm),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          l10n.captureHint,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      const WebViewExtractionOutcome(
                        result: VerificationResult.done,
                      ),
                    ),
                    child: Text(l10n.verificationDone),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 取回渲染后的整页 HTML 并回传。
  ///
  /// 先同步 Cookie，再调用 `controller.getHtml()` 拿到 JS 渲染完成后的完整
  /// HTML，交由调用方用既有选择器解析（修复「列表由 JS 动态渲染、静态抓取为空」）。
  Future<void> _captureHtml() async {
    final controller = _webViewController;
    if (controller == null) return;
    setState(() {
      _extracting = true;
      _extractionError = null;
    });
    try {
      await _syncWebviewCookies();
      final html = await controller.getHtml();
      if (html != null && html.isNotEmpty) {
        if (mounted) {
          Navigator.of(context).pop(
            WebViewExtractionOutcome(
              result: VerificationResult.done,
              renderedHtml: html,
            ),
          );
        }
        return;
      }
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractionError = AppLocalizations.of(context).extractNoResult;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _extracting = false;
          _extractionError =
              '${AppLocalizations.of(context).extractFailed}: $e';
        });
      }
    }
  }

  /// 原有 url_launcher 手动验证视图（保留不动）。
  Widget _buildLegacyScaffold(BuildContext context, AppLocalizations l10n) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
        // 返回 cancelled
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.verificationRequired),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () =>
                Navigator.of(context).pop(VerificationResult.cancelled),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.verified_user_outlined,
                  size: 72,
                  color: scheme.primary.withValues(alpha: 0.7),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                Text(
                  l10n.verificationRequired,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppTokens.spaceMd),
                Text(
                  l10n.verificationHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                // 显示需要验证的 URL（截断显示）
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceMd,
                    vertical: AppTokens.spaceSm,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  ),
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Text(
                    widget.verificationUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceXl),
                FilledButton.icon(
                  onPressed: _openInBrowser,
                  icon: const Icon(Icons.open_in_browser),
                  label: Text(l10n.openInBrowser),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                FilledButton.tonalIcon(
                  onPressed: _openInternalBrowser,
                  icon: const Icon(Icons.travel_explore),
                  label: Text(l10n.openInternalBrowser),
                ),
                if (_browserOpened) ...<Widget>[
                  const SizedBox(height: AppTokens.spaceMd),
                  FilledButton.tonalIcon(
                    onPressed: _finish,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(l10n.verificationDone),
                  ),
                ],
                const SizedBox(height: AppTokens.spaceLg),
                TextButton(
                  onPressed: () => Navigator.of(context)
                      .pop(VerificationResult.cancelled),
                  child: Text(l10n.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 便捷方法：导航到验证页面并等待结果。
///
/// 返回 `true` 表示用户已完成验证并希望重试。
Future<bool> navigateToVerification(
  BuildContext context, {
  required String url,
  VerificationRequiredException? exception,
}) async {
  final result = await Navigator.of(context).push<VerificationResult>(
    MaterialPageRoute<VerificationResult>(
      builder: (_) => WebViewVerificationScreen(
        verificationUrl: url,
        exception: exception,
      ),
    ),
  );
  return result == VerificationResult.done;
}

/// M2.4 便捷方法：导航到抽取页面并等待结果。
///
/// 调用方优先判断 [WebViewExtractionOutcome.hasExtractedUrl]：
/// - 命中则直接使用 [WebViewExtractionOutcome.extractedUrl] 作为解析结果。
/// - 未命中且 [WebViewExtractionOutcome.shouldRetry] 时，回退到重试原始请求。
/// - 返回 null 表示用户取消。
Future<WebViewExtractionOutcome?> navigateToExtraction(
  BuildContext context, {
  required WebViewExtractionRequest request,
}) async {
  return Navigator.of(context).push<WebViewExtractionOutcome>(
    MaterialPageRoute<WebViewExtractionOutcome>(
      builder: (_) => WebViewVerificationScreen(
        verificationUrl: request.url,
        exception: null,
        extractionRequest: request,
      ),
    ),
  );
}

/// 渲染后抽取便捷方法：导航到 WebView 渲染页面，取回整页渲染 HTML 并等待结果。
///
/// 调用方优先判断 [WebViewExtractionOutcome.hasRenderedHtml]：
/// - 命中则直接用 [WebViewExtractionOutcome.renderedHtml] 复用源选择器解析。
/// - 返回 null 表示用户取消。
Future<WebViewExtractionOutcome?> navigateToHtmlCapture(
  BuildContext context, {
  required WebViewHtmlRequest request,
}) async {
  return Navigator.of(context).push<WebViewExtractionOutcome>(
    MaterialPageRoute<WebViewExtractionOutcome>(
      builder: (_) => WebViewVerificationScreen(
        verificationUrl: request.url,
        exception: null,
        htmlRequest: request,
      ),
    ),
  );
}
