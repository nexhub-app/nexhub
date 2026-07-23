/// 内置网页浏览器（M3.1）。
///
/// 顶部地址栏 + 前进/后退/刷新；主体 [InAppWebView]；右上菜单：复制链接 / 分享 /
/// 用此页完成验证。验证完成后回写 Cookie 到 [HttpFetcher]，支持作为验证兜底。
///
/// 在不支持 [InAppWebView] 的平台（如 Web）显示提示并回退到外部浏览器。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/platform/platform_service.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../../../core/theme/app_tokens.dart';
import 'video_sniffer_screen.dart';

/// 内置浏览器页面。
///
/// [initialUrl] 为初始加载地址（可选；为空时显示空白页等待用户输入）。
///
/// 返回值：`true` 表示用户点击了「用此页完成验证」（此时 Cookie 已同步到
/// [HttpFetcher]）；`false` / `null` 表示用户直接关闭。
class HttpBrowserScreen extends StatefulWidget {
  final String? initialUrl;

  const HttpBrowserScreen({super.key, this.initialUrl});

  @override
  State<HttpBrowserScreen> createState() => _HttpBrowserScreenState();
}

class _HttpBrowserScreenState extends State<HttpBrowserScreen> {
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocus = FocusNode();
  InAppWebViewController? _webViewController;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _loading = false;
  bool _pageLoaded = false;
  String? _currentUrl;

  /// 当前平台是否支持内置浏览器（[InAppWebView] 在 Web 不可用）。
  bool get _isAvailable => !PlatformService.instance.isWeb;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl;
    if (widget.initialUrl != null) {
      _addressController.text = widget.initialUrl!;
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  /// 规范化用户输入：无 scheme 时补 https://；无明显域名时当作搜索词。
  String _normalizeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    // 含空格或无点号时视为搜索词，回退到搜索引擎。
    if (!trimmed.contains('.') || trimmed.contains(' ')) {
      return 'https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}';
    }
    return 'https://$trimmed';
  }

  Future<void> _navigate(String input) async {
    final url = _normalizeUrl(input);
    if (url.isEmpty) return;
    _addressController.text = url;
    _addressFocus.unfocus();
    final controller = _webViewController;
    if (controller == null) return;
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _goBack() async {
    final controller = _webViewController;
    if (controller == null) return;
    if (await controller.canGoBack()) {
      await controller.goBack();
    }
  }

  Future<void> _goForward() async {
    final controller = _webViewController;
    if (controller == null) return;
    if (await controller.canGoForward()) {
      await controller.goForward();
    }
  }

  Future<void> _refresh() async {
    final controller = _webViewController;
    if (controller == null) return;
    await controller.reload();
  }

  /// 仅在地址栏未获得焦点时回填地址，避免覆盖用户正在输入的内容。
  void _syncAddress(String? url) {
    if (url == null || url.isEmpty) return;
    _currentUrl = url;
    if (!_addressFocus.hasFocus) {
      _addressController.text = url;
    }
  }

  /// 复制当前链接到剪贴板。
  void _copyLink() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final url = _currentUrl;
    if (url == null || url.isEmpty) return;
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.browserLinkCopied)),
    );
  }

  /// 分享当前链接（复制到剪贴板 + 提示，与项目现有 share 行为一致）。
  void _shareLink() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final url = _currentUrl;
    if (url == null || url.isEmpty) return;
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.shareCopied)),
    );
  }

  /// 将当前页 Cookie 同步到 [HttpFetcher] 并返回，作为验证兜底。
  Future<void> _useAsVerification() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final url = _currentUrl;
    if (url == null || url.isEmpty) return;
    await _syncCookiesToFetcher(url);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.browserUseAsVerificationDone)),
    );
    Navigator.of(context).pop(true);
  }

  /// 打开「视频嗅探模式」：在当前页基础上拦截动态加载的串流。
  ///
  /// 若用户已在内置浏览器打开了一个视频页，则把当前地址带入嗅探器作为初始
  /// 地址，省去再次输入。
  void _openSniffer() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoSnifferScreen(initialUrl: _currentUrl),
      ),
    );
  }

  /// 读取 [InAppWebView] 的 [CookieManager] Cookie 写回 [HttpFetcher]（best-effort）。
  Future<void> _syncCookiesToFetcher(String url) async {
    try {
      final uri = Uri.tryParse(url);
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

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (!_isAvailable) {
      return _buildUnavailableScaffold(context, l10n);
    }
    return _buildBrowserScaffold(context, l10n);
  }

  /// 平台不支持 [InAppWebView] 时的回退视图。
  Widget _buildUnavailableScaffold(BuildContext context, AppLocalizations l10n) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.browserTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.browse_gallery_outlined,
                size: 72,
                color: scheme.primary.withValues(alpha: 0.7),
              ),
              const SizedBox(height: AppTokens.spaceLg),
              Text(
                l10n.browserNotAvailable,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppTokens.spaceLg),
              if (widget.initialUrl != null)
                FilledButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(widget.initialUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_browser),
                  label: Text(l10n.openInBrowser),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrowserScaffold(BuildContext context, AppLocalizations l10n) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppTokens.spaceSm,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: _buildAddressField(context, l10n),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: l10n.browserBack,
            onPressed: _canGoBack ? _goBack : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            tooltip: l10n.browserForward,
            onPressed: _canGoForward ? _goForward : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.browserRefresh,
            onPressed: _refresh,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: l10n.browserTitle,
            onSelected: (String value) {
              switch (value) {
                case 'copy':
                  _copyLink();
                  break;
                case 'share':
                  _shareLink();
                  break;
                case 'verify':
                  _useAsVerification();
                  break;
                case 'sniffer':
                  _openSniffer();
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'copy',
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.link_outlined, size: 20),
                    const SizedBox(width: AppTokens.spaceMd),
                    Text(l10n.browserCopyLink),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'share',
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.share_outlined, size: 20),
                    const SizedBox(width: AppTokens.spaceMd),
                    Text(l10n.browserShare),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'verify',
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.verified_user_outlined, size: 20),
                    const SizedBox(width: AppTokens.spaceMd),
                    Text(l10n.browserUseAsVerification),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'sniffer',
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.cable_outlined, size: 20),
                    const SizedBox(width: AppTokens.spaceMd),
                    Text(l10n.browserOpenSniffer),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          InAppWebView(
            initialUrlRequest: widget.initialUrl != null
                ? URLRequest(url: WebUri(widget.initialUrl!))
                : null,
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
            onLoadStart: (controller, url) {
              if (mounted) setState(() => _loading = true);
              _syncAddress(url?.toString());
            },
            onLoadStop: (controller, url) async {
              _canGoBack = await controller.canGoBack();
              _canGoForward = await controller.canGoForward();
              _syncAddress(url?.toString());
              if (mounted) {
                setState(() {
                  _loading = false;
                  _pageLoaded = true;
                });
              }
            },
            onUpdateVisitedHistory:
                (controller, url, androidIsReload) async {
              _canGoBack = await controller.canGoBack();
              _canGoForward = await controller.canGoForward();
              _syncAddress(url?.toString());
              if (mounted) setState(() {});
            },
          ),
          // 加载进度条：吸附顶部。
          if (_loading)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            ),
          // 首次加载前的占位指示。
          if (widget.initialUrl != null && !_pageLoaded)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  /// 顶部地址输入框。
  Widget _buildAddressField(BuildContext context, AppLocalizations l10n) {
    return TextField(
      controller: _addressController,
      focusNode: _addressFocus,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.go,
      decoration: InputDecoration(
        hintText: l10n.browserAddressHint,
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusFull),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: AppTokens.spaceSm,
        ),
      ),
      onSubmitted: _navigate,
    );
  }
}
