/// 视频地址提取器：从 HTML 的 `<video>` / `<iframe>` / `<source>` 标签中
/// 抽取视频直链或嵌入页 URL。
///
/// 同时提供顶层函数 [extractFromVideoTag] 作为简洁入口。
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// 从 HTML 提取出的单个视频信息。
class ExtractedVideo {
  /// 视频 URL（直链或嵌入页 URL），已基于 baseUrl 解析为绝对地址。
  final String url;

  /// 类型：`hls` / `video/mp4` / `embed` / `unknown` 等。
  final String type;

  /// `<video poster>` 海报图 URL（可选）。
  final String? poster;

  /// 嵌入来源标识（`youtube` / `bilibili` / ...），仅 type == `embed` 时有值。
  final String? source;

  const ExtractedVideo({
    required this.url,
    required this.type,
    this.poster,
    this.source,
  });

  @override
  String toString() {
    return 'ExtractedVideo(url: $url, type: $type, poster: $poster, '
        'source: $source)';
  }
}

/// 从 HTML 提取视频地址。
///
/// 依次扫描 `<video src>`、`<video><source>`、`<iframe src>`、独立 `<source>`
/// 标签，返回去重后的 [ExtractedVideo] 列表（保持出现顺序）。
class VideoExtractor {
  /// 从 [html] 提取视频地址列表。
  ///
  /// [baseUrl] 用于将相对 URL 解析为绝对 URL。
  static List<ExtractedVideo> extract(String html, {String? baseUrl}) {
    final document = html_parser.parse(html);
    final videos = <ExtractedVideo>[];
    final seen = <String>{};

    _extractFromVideoTags(document, baseUrl, videos, seen);
    _extractFromIframes(document, baseUrl, videos, seen);
    _extractFromSourceTags(document, baseUrl, videos, seen);

    return videos;
  }

  /// 提取 `<video src>` 与 `<video><source src>` 标签。
  static void _extractFromVideoTags(
    Document document,
    String? baseUrl,
    List<ExtractedVideo> videos,
    Set<String> seen,
  ) {
    final videoElements = document.querySelectorAll('video[src]');
    for (final el in videoElements) {
      final src = el.attributes['src'];
      if (src == null || src.isEmpty) continue;

      final resolved = _resolveUrl(src, baseUrl);
      if (seen.contains(resolved)) continue;
      seen.add(resolved);

      final poster = el.attributes['poster'];

      videos.add(ExtractedVideo(
        url: resolved,
        type: _guessType(src),
        poster: poster != null ? _resolveUrl(poster, baseUrl) : null,
      ));
    }

    final sourceElements = document.querySelectorAll('video source[src]');
    for (final el in sourceElements) {
      final src = el.attributes['src'];
      if (src == null || src.isEmpty) continue;

      final resolved = _resolveUrl(src, baseUrl);
      if (seen.contains(resolved)) continue;
      seen.add(resolved);

      final type = el.attributes['type'] ?? _guessType(src);

      videos.add(ExtractedVideo(url: resolved, type: type));
    }
  }

  /// 提取 `<iframe src>` 中的视频嵌入页 URL。
  static void _extractFromIframes(
    Document document,
    String? baseUrl,
    List<ExtractedVideo> videos,
    Set<String> seen,
  ) {
    final iframes = document.querySelectorAll('iframe[src]');
    for (final el in iframes) {
      final src = el.attributes['src'];
      if (src == null || src.isEmpty) continue;

      final resolved = _resolveUrl(src, baseUrl);
      if (seen.contains(resolved)) continue;
      seen.add(resolved);

      if (_isVideoEmbed(resolved)) {
        videos.add(ExtractedVideo(
          url: resolved,
          type: 'embed',
          source: _detectEmbedSource(resolved),
        ));
      }
    }
  }

  /// 提取独立 `<source src>` 标签（非 `<video>` 内的）。
  static void _extractFromSourceTags(
    Document document,
    String? baseUrl,
    List<ExtractedVideo> videos,
    Set<String> seen,
  ) {
    final sources = document.querySelectorAll('source[src]');
    for (final el in sources) {
      final src = el.attributes['src'];
      if (src == null || src.isEmpty) continue;

      final resolved = _resolveUrl(src, baseUrl);
      if (seen.contains(resolved)) continue;
      seen.add(resolved);

      videos.add(ExtractedVideo(
        url: resolved,
        type: el.attributes['type'] ?? _guessType(src),
      ));
    }
  }

  /// 根据 URL 后缀猜测视频类型。
  static String _guessType(String url) {
    if (url.contains('.m3u8') || url.contains('hls')) return 'hls';
    if (url.contains('.mp4')) return 'video/mp4';
    if (url.contains('.webm')) return 'video/webm';
    if (url.contains('.mkv')) return 'video/x-matroska';
    return 'unknown';
  }

  /// URL 是否为已知视频嵌入站。
  static bool _isVideoEmbed(String url) {
    const videoDomains = [
      'youtube.com',
      'youtu.be',
      'vimeo.com',
      'bilibili.com',
      'player.bilibili.com',
      'dailymotion.com',
      'twitch.tv',
    ];
    return videoDomains.any((d) => url.contains(d));
  }

  /// 识别嵌入站来源。
  static String _detectEmbedSource(String url) {
    if (url.contains('youtube.com') || url.contains('youtu.be')) return 'youtube';
    if (url.contains('vimeo.com')) return 'vimeo';
    if (url.contains('bilibili.com')) return 'bilibili';
    if (url.contains('dailymotion.com')) return 'dailymotion';
    if (url.contains('twitch.tv')) return 'twitch';
    return 'unknown';
  }

  /// 将相对 URL 基于 baseUrl 解析为绝对 URL。
  static String _resolveUrl(String url, String? baseUrl) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (baseUrl == null) return url;
    if (url.startsWith('//')) {
      final baseUri = Uri.parse(baseUrl);
      return '${baseUri.scheme}:$url';
    }
    if (url.startsWith('/')) {
      final baseUri = Uri.parse(baseUrl);
      return '${baseUri.scheme}://${baseUri.host}$url';
    }
    return '$baseUrl/$url';
  }
}

/// 从 HTML 的 `<video>` / `<iframe>` / `<source>` 标签提取视频 URL。
///
/// 等价于 [VideoExtractor.extract]，返回 [ExtractedVideo] 列表。
List<ExtractedVideo> extractFromVideoTag(String html, {String? baseUrl}) {
  return VideoExtractor.extract(html, baseUrl: baseUrl);
}
