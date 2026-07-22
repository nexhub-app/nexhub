/// 视频嗅探器（Request ②）。
///
/// 在内置浏览器基础上增加「嗅探模式」：用 [InAppWebView] 打开视频页面，
/// 通过 [onLoadResource] 拦截所有网络资源，自动识别动态加载的
/// m3u8 / mp4 / ts / m4s 等视频串流（静态 <video> 解析漏掉的那些），
/// 列出后可一键复制或直接用内置播放器播放。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/models/episode.dart';
import '../../../core/theme/app_tokens.dart';
import '../../player/presentation/video_player_screen.dart';

/// 视频串流扩展名集合（用于资源拦截过滤）。
const Set<String> _videoExtensions = <String>{
  'm3u8',
  'mpd',
  'mp4',
  'ts',
  'm4s',
  'mov',
  'webm',
  'flv',
  'mkv',
  'avi',
  '3gp',
};

/// 视频嗅探页面。
///
/// [initialUrl] 为初始加载地址（可选）。返回值无意义（关闭即退出）。
class VideoSnifferScreen extends StatefulWidget {
  final String? initialUrl;

  const VideoSnifferScreen({super.key, this.initialUrl});

  @override
  State<VideoSnifferScreen> createState() => _VideoSnifferScreenState();
}

class _VideoSnifferScreenState extends State<VideoSnifferScreen> {
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocus = FocusNode();
  InAppWebViewController? _webViewController;
  bool _loading = false;
  bool _pageLoaded = false;

  /// 已嗅探到的视频 URL（去重，保持插入顺序）。
  final List<String> _sniffed = <String>[];

  @override
  void initState() {
    super.initState();
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

  /// 判断资源 URL 是否为视频串流。
  bool _isVideoUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final lower = url.toLowerCase();
    // 直接命中已知扩展名。
    for (final ext in _videoExtensions) {
      if (lower.contains('.$ext')) return true;
    }
    // 部分 m3u8 不带扩展名但路径含关键字。
    if (lower.contains('m3u8') || lower.contains('.mp4?') || lower.contains('manifest')) {
      return true;
    }
    return false;
  }

  /// 从 URL 推断视频类型标签（用于列表徽标）。
  String _videoType(String url) {
    final lower = url.toLowerCase();
    for (final ext in _videoExtensions) {
      if (lower.contains('.$ext')) return ext.toUpperCase();
    }
    if (lower.contains('m3u8')) return 'M3U8';
    if (lower.contains('manifest')) return 'DASH';
    return 'VIDEO';
  }

  void _onResourceLoaded(String? url) {
    if (!_isVideoUrl(url)) return;
    final u = url!;
    if (_sniffed.contains(u)) return;
    setState(() => _sniffed.add(u));
  }

  String _normalizeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
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

  void _copyUrl(String url) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.snifferCopy)),
    );
  }

  void _playUrl(String url) {
    final title = Uri.tryParse(url)?.pathSegments.isNotEmpty == true
        ? Uri.parse(url).pathSegments.last
        : url;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          title: title,
          episode: Episode(id: url, title: title, url: url),
          sourceId: '',
          itemId: url,
          directUrl: url,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.snifferTitle),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.snifferClear,
            onPressed: _sniffed.isEmpty
                ? null
                : () => setState(() => _sniffed.clear()),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 地址栏
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceSm,
              AppTokens.spaceSm,
              AppTokens.spaceSm,
              AppTokens.spaceXs,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    focusNode: _addressFocus,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    decoration: InputDecoration(
                      hintText: l10n.snifferAddressHint,
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusFull),
                      ),
                    ),
                    onSubmitted: _navigate,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: l10n.browserRefresh,
                  onPressed: () =>
                      _navigate(_addressController.text),
                ),
              ],
            ),
          ),
          // 浏览器主体
          Expanded(
            flex: 3,
            child: Stack(
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
                  },
                  onLoadStop: (controller, url) async {
                    if (mounted) {
                      setState(() {
                        _loading = false;
                        _pageLoaded = true;
                      });
                    }
                  },
                  // 核心：拦截所有网络资源，识别视频串流。
                  onLoadResource: (controller, resource) {
                    _onResourceLoaded(resource.url?.toString());
                  },
                ),
                if (_loading)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(),
                  ),
                if (widget.initialUrl != null && !_pageLoaded)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          // 嗅探结果
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceMd,
                    vertical: AppTokens.spaceSm,
                  ),
                  child: Text(
                    l10n.snifferHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
                Expanded(
                  child: _sniffed.isEmpty
                      ? Center(
                          child: Text(
                            l10n.snifferNoResult,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.spaceMd,
                          ),
                          itemCount: _sniffed.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final url = _sniffed[index];
                            final type = _videoType(url);
                            return ListTile(
                              dense: true,
                              leading: Chip(
                                label: Text(type),
                                visualDensity: VisualDensity.compact,
                              ),
                              title: Text(
                                url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 20),
                                    tooltip: l10n.snifferCopy,
                                    onPressed: () => _copyUrl(url),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.play_arrow, size: 20),
                                    tooltip: l10n.snifferPlay,
                                    onPressed: () => _playUrl(url),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
