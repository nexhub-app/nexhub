import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../models/plugin_config.dart';
import '../theme/app_tokens.dart';

/// 统一源图片 widget：按源配置注入防盗链 headers，带缓存、失败重试、圆角、Hero。
///
/// 替代裸 `Image.network`：漫画源 / 影视源封面常因防盗链返回 403，必须携带
/// `Referer` / `User-Agent` / `Cookie` 等头才能正常加载（见 PluginConfig.antiHotlinking
/// 与 PluginConfig.site）。本地文件路径走 [Image.file]。
class SourceImage extends StatelessWidget {
  final String? url;
  final PluginConfig? source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String? heroTag;
  final double? radius;
  final Widget? placeholder;
  final bool enableRetry;

  const SourceImage({
    super.key,
    required this.url,
    this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.heroTag,
    this.radius,
    this.placeholder,
    this.enableRetry = true,
  });

  bool get _isHttp =>
      url != null &&
      (url!.startsWith('http://') || url!.startsWith('https://'));

  /// 合并防盗链 headers：antiHotlinking.headers 起手 → site.headers →
  /// Referer / User-Agent / Cookie 字段（后者优先覆盖同名键）。
  Map<String, String>? _buildHeaders() {
    final ah = source?.antiHotlinking;
    final site = source?.site;
    final ahHeaders = ah?.headers;
    final siteHeaders = site?.headers;
    final referer = ah?.referer;
    final ua = site?.userAgent;
    final cookies = site?.cookies;
    final hasFields = (siteHeaders != null && siteHeaders.isNotEmpty) ||
        (ahHeaders != null && ahHeaders.isNotEmpty) ||
        (referer != null && referer.isNotEmpty) ||
        (ua != null && ua.isNotEmpty) ||
        (cookies != null && cookies.isNotEmpty);
    if (!hasFields) return null;
    final Map<String, String> m = <String, String>{};
    if (ahHeaders != null) m.addAll(ahHeaders);
    if (siteHeaders != null) m.addAll(siteHeaders);
    if (referer != null && referer.isNotEmpty) {
      m['Referer'] = referer;
    }
    if (ua != null && ua.isNotEmpty) {
      m['User-Agent'] = ua;
    }
    if (cookies != null && cookies.isNotEmpty) {
      m['Cookie'] = cookies;
    }
    return m;
  }

  Widget _defaultPlaceholder(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_outlined,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? u = url;
    final Widget core;
    if (u == null || u.isEmpty) {
      core = placeholder ?? _defaultPlaceholder(context);
    } else if (_isHttp) {
      core = _RetryableNetworkImage(
        url: u,
        headers: _buildHeaders(),
        width: width,
        height: height,
        fit: fit,
        placeholder: placeholder ?? _defaultPlaceholder(context),
        enableRetry: enableRetry,
      );
    } else {
      core = Image.file(
        File(u),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (c, e, s) => placeholder ?? _defaultPlaceholder(context),
      );
    }

    final double? r = radius;
    final Widget clipped =
        r == null ? core : ClipRRect(borderRadius: BorderRadius.circular(r), child: core);
    return heroTag == null ? clipped : Hero(tag: heroTag!, child: clipped);
  }
}

/// 带指数退避重试的网络图片（最多 3 次：1s / 2s / 4s）。
class _RetryableNetworkImage extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget placeholder;
  final bool enableRetry;

  const _RetryableNetworkImage({
    required this.url,
    this.headers,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    required this.placeholder,
    this.enableRetry = true,
  });

  @override
  State<_RetryableNetworkImage> createState() => _RetryableNetworkImageState();
}

class _RetryableNetworkImageState extends State<_RetryableNetworkImage> {
  static const int _maxRetries = 3;
  static const List<Duration> _backoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  int _retryKey = 0;
  int _retryCount = 0;
  bool _retrying = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _retry() {
    if (!widget.enableRetry || _retrying || _retryCount >= _maxRetries) return;
    setState(() => _retrying = true);
    _timer = Timer(_backoff[_retryCount], () {
      if (!mounted) return;
      setState(() {
        _retrying = false;
        _retryCount += 1;
        _retryKey += 1;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      key: ValueKey<String>('${widget.url}-$_retryKey'),
      imageUrl: widget.url,
      httpHeaders: widget.headers,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      placeholder: (c, u) => widget.placeholder,
      errorWidget: (c, u, e) => _buildError(context),
    );
  }

  Widget _buildError(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool exhausted = _retryCount >= _maxRetries;
    return Semantics(
      label: l10n.imageLoadFailed,
      child: Container(
        width: widget.width,
        height: widget.height,
        color: scheme.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.broken_image, color: scheme.onSurfaceVariant),
            if (widget.enableRetry) ...<Widget>[
              const SizedBox(height: AppTokens.spaceXs),
              if (_retrying)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                )
              else if (!exhausted)
                TextButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.retry),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
