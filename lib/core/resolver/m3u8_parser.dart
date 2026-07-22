/// HLS M3U8 解析器：支持 Master Playlist（清晰度列表）与 Media Playlist（分片列表）。
///
/// 同时提供顶层函数 [parseM3u8] 作为简洁入口，以及 [M3u8Parser] 类承载
/// 更完整的解析能力（递归、data URI、加密 Key 等），供广告过滤等模块复用。
library;

import 'dart:convert';

/// Master Playlist 中的一个清晰度变体（`#EXT-X-STREAM-INF`）。
class M3u8Variant {
  /// 声明带宽（bps）。
  final int bandwidth;

  /// 分辨率，例如 `1920x1080`，缺失为 `null`。
  final String? resolution;

  /// 编码字符串，例如 `avc1.42e00a,mp4a.40.2`，缺失为 `null`。
  final String? codecs;

  /// 该变体对应 Media Playlist 的 URL（绝对或相对）。
  final String url;

  const M3u8Variant({
    required this.bandwidth,
    required this.url,
    this.resolution,
    this.codecs,
  });

  @override
  String toString() {
    return 'M3u8Variant(bandwidth: $bandwidth, resolution: $resolution, '
        'codecs: $codecs, url: $url)';
  }
}

/// 单个 HLS 媒体分片（`#EXTINF` + URI）。
class M3u8Segment {
  /// 分片 URL（绝对或相对）。
  final String url;

  /// 分片时长（秒）。
  final double duration;

  /// `#EXTINF` 携带的可选标题。
  final String? title;

  /// 该分片所属的加密 Key 信息。
  final M3u8KeyInfo? keyInfo;

  /// 该分片所属的 `#EXT-X-DISCONTINUITY` 组索引（从 0 开始）。
  ///
  /// 用于广告过滤： discontinuity 标记之间的分片归为同一组，短时长组
  /// 通常是被插入的广告块。
  final int discontinuityGroup;

  const M3u8Segment({
    required this.url,
    required this.duration,
    this.title,
    this.keyInfo,
    this.discontinuityGroup = 0,
  });

  @override
  String toString() {
    return 'M3u8Segment(url: $url, duration: $duration, title: $title, '
        'keyInfo: $keyInfo, discontinuityGroup: $discontinuityGroup)';
  }
}

/// 加密 Key 信息（`#EXT-X-KEY`）。
class M3u8KeyInfo {
  /// 加密方式，例如 `AES-128` / `SAMPLE-AES`。
  final String method;

  /// Key 资源 URL（绝对或相对）。
  final String? uri;

  /// 初始化向量（十六进制字符串）。
  final String? iv;

  const M3u8KeyInfo({required this.method, this.uri, this.iv});

  @override
  String toString() {
    return 'M3u8KeyInfo(method: $method, uri: $uri, iv: $iv)';
  }
}

/// M3U8 解析结果。
///
/// 至少 [variants] 或 [segments] 之一会被填充。[isMaster] / [isMedia]
/// 标识原始文本的 playlist 类型。
class M3u8ParseResult {
  /// Master Playlist 的清晰度变体列表。
  final List<M3u8Variant> variants;

  /// Media Playlist 的分片列表。
  final List<M3u8Segment> segments;

  /// 是否为 Master Playlist。
  final bool isMaster;

  /// 是否为 Media Playlist。
  final bool isMedia;

  const M3u8ParseResult({
    this.variants = const [],
    this.segments = const [],
    this.isMaster = false,
    this.isMedia = false,
  });
}

/// 解析 M3U8 文本，自动识别 Master / Media Playlist。
///
/// [baseUrl] 用于将相对 URL 解析为绝对 URL。返回 [M3u8ParseResult]，
/// 包含清晰度列表（variants）与分片列表（segments）。
M3u8ParseResult parseM3u8(String text, {String? baseUrl}) {
  return M3u8Parser.parse(text, baseUrl: baseUrl);
}

/// HLS M3U8 解析器。
///
/// 支持 Master Playlist（`#EXT-X-STREAM-INF`）、Media Playlist
///（`#EXTINF` / `#EXT-X-KEY` / `#EXT-X-DISCONTINUITY`），并对嵌套 M3U8
/// 与 `data:` URI 做有限递归展开。
class M3u8Parser {
  static const String _masterTag = '#EXT-X-STREAM-INF';
  static const String _mediaTag = '#EXTINF';
  static const String _keyTag = '#EXT-X-KEY';
  static const String _endListTag = '#EXT-X-ENDLIST';
  static const String _discontinuityTag = '#EXT-X-DISCONTINUITY';

  static const int _defaultMaxRecursion = 3;

  /// 将相对 [url] 基于 [baseUrl] 解析为绝对 URL。
  ///
  /// 绝对 URL、`data:` URI 原样返回；相对 URL 按 RFC 3986 解析
  ///（[baseUrl] 末段会被视为文件名并去掉，例如
  /// `https://a.com/playlist/master.m3u8` + `low.m3u8` →
  /// `https://a.com/playlist/low.m3u8`）。
  static String resolveUrl(String url, String? baseUrl) {
    if (url.startsWith('data:')) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (baseUrl == null || baseUrl.isEmpty) return url;

    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null) return url;

    return baseUri.resolve(url).toString();
  }

  /// 解析 [content]，自动识别 Master / Media Playlist。
  ///
  /// 当 [baseUrl] 提供时，所有相对 URL 转为绝对 URL。若某变体或分片指向
  /// 另一个 `.m3u8` 且 [maxRecursion] 未耗尽，则递归解析并扁平化入结果。
  static M3u8ParseResult parse(
    String content, {
    String? baseUrl,
    int maxRecursion = _defaultMaxRecursion,
  }) {
    final isMaster = _containsMasterPlaylist(content);
    final isMedia = _containsMediaPlaylist(content);

    if (isMaster && isMedia) {
      // 退化情形：同时含 master 与 media 标记，两部分都解析。
      final variants = parseMaster(content, baseUrl: baseUrl).variants;
      final segments = _parseMediaInternal(
        content,
        baseUrl: baseUrl,
        maxRecursion: maxRecursion,
      );
      return M3u8ParseResult(
        variants: variants,
        segments: segments,
        isMaster: true,
        isMedia: true,
      );
    }

    if (isMaster) {
      final variants = parseMaster(content, baseUrl: baseUrl).variants;
      final flattened = <M3u8Segment>[];
      if (maxRecursion > 0) {
        for (final variant in variants) {
          if (_isM3u8Url(variant.url)) {
            final nested = parse(
              variant.url,
              baseUrl: baseUrl,
              maxRecursion: maxRecursion - 1,
            );
            flattened.addAll(nested.segments);
          }
        }
      }
      return M3u8ParseResult(
        variants: variants,
        segments: flattened,
        isMaster: true,
        isMedia: flattened.isNotEmpty,
      );
    }

    final segments = _parseMediaInternal(
      content,
      baseUrl: baseUrl,
      maxRecursion: maxRecursion,
    );
    return M3u8ParseResult(
      variants: const [],
      segments: segments,
      isMaster: false,
      isMedia: segments.isNotEmpty || _containsMediaPlaylist(content),
    );
  }

  /// 解析 Master Playlist，返回其清晰度变体列表。
  static M3u8ParseResult parseMaster(
    String content, {
    String? baseUrl,
  }) {
    final variants = <M3u8Variant>[];
    final lines = LineSplitter.split(content).toList();

    M3u8StreamInfAttributes? pendingAttributes;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        if (line.startsWith(_masterTag)) {
          pendingAttributes = _parseStreamInf(line);
        }
        continue;
      }

      if (pendingAttributes != null) {
        final resolvedUrl = resolveUrl(line, baseUrl);
        variants.add(
          M3u8Variant(
            bandwidth: pendingAttributes.bandwidth ?? 0,
            resolution: pendingAttributes.resolution,
            codecs: pendingAttributes.codecs,
            url: resolvedUrl,
          ),
        );
        pendingAttributes = null;
      }
    }

    return M3u8ParseResult(variants: variants, isMaster: true, isMedia: false);
  }

  /// 解析 Media Playlist，返回其分片列表。
  ///
  /// 嵌套 M3U8 递归展开至 [maxRecursion] 层。
  static M3u8ParseResult parseMedia(
    String content, {
    String? baseUrl,
    int maxRecursion = _defaultMaxRecursion,
  }) {
    final segments = _parseMediaInternal(
      content,
      baseUrl: baseUrl,
      maxRecursion: maxRecursion,
    );
    return M3u8ParseResult(
      variants: const [],
      segments: segments,
      isMaster: false,
      isMedia: true,
    );
  }

  /// 将 Media Playlist 字符串解析为 [M3u8Segment] 列表。
  static List<M3u8Segment> _parseMediaInternal(
    String content, {
    String? baseUrl,
    required int maxRecursion,
  }) {
    final segments = <M3u8Segment>[];
    final lines = LineSplitter.split(content).toList();

    M3u8KeyInfo? currentKey;
    double? pendingDuration;
    String? pendingTitle;
    var discontinuityGroup = 0;

    for (var i = 0; i < lines.length; i++) {
      final rawLine = lines[i];
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#EXTM3U')) continue;

      if (line.startsWith(_discontinuityTag)) {
        // 遇到 discontinuity 标记，后续分片归入下一组。
        if (segments.isNotEmpty) {
          discontinuityGroup++;
        }
        continue;
      }

      if (line.startsWith(_keyTag)) {
        currentKey = _parseKey(line, baseUrl);
        continue;
      }

      if (line.startsWith(_mediaTag)) {
        final parsed = _parseExtInf(line);
        pendingDuration = parsed.duration;
        pendingTitle = parsed.title;
        continue;
      }

      if (line.startsWith('#')) {
        // 其他标签（byte-range 等）不影响分片收集。
        continue;
      }

      if (pendingDuration != null) {
        final resolvedUrl = resolveUrl(line, baseUrl);
        if (_shouldExpandNested(resolvedUrl) && maxRecursion > 0) {
          final nested = _resolveNestedMedia(
            resolvedUrl,
            baseUrl: baseUrl,
            maxRecursion: maxRecursion - 1,
          );
          segments.addAll(nested);
        } else {
          segments.add(
            M3u8Segment(
              url: resolvedUrl,
              duration: pendingDuration,
              title: pendingTitle,
              keyInfo: currentKey,
              discontinuityGroup: discontinuityGroup,
            ),
          );
        }
        pendingDuration = null;
        pendingTitle = null;
      }
    }

    return segments;
  }

  /// 解析 `#EXT-X-STREAM-INF` 行的属性。
  static M3u8StreamInfAttributes _parseStreamInf(String line) {
    final attrs = M3u8StreamInfAttributes();
    final attributeRegex = RegExp(r'([A-Z0-9\-]+)=("[^"]*"|[^,\s]+)');
    for (final match in attributeRegex.allMatches(line)) {
      final key = match.group(1);
      var value = match.group(2) ?? '';
      if (value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      switch (key) {
        case 'BANDWIDTH':
          attrs.bandwidth = int.tryParse(value);
        case 'RESOLUTION':
          attrs.resolution = value;
        case 'CODECS':
          attrs.codecs = value;
      }
    }
    return attrs;
  }

  /// 解析 `#EXT-X-KEY` 行为 [M3u8KeyInfo]。
  static M3u8KeyInfo _parseKey(String line, String? baseUrl) {
    String? method;
    String? uri;
    String? iv;

    final attributeRegex = RegExp(r'([A-Z0-9\-]+)=("[^"]*"|[^,\s]+)');
    for (final match in attributeRegex.allMatches(line)) {
      final key = match.group(1);
      var value = match.group(2) ?? '';
      if (value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      switch (key) {
        case 'METHOD':
          method = value;
        case 'URI':
          uri = resolveUrl(value, baseUrl);
        case 'IV':
          iv = value;
      }
    }

    return M3u8KeyInfo(method: method ?? 'UNKNOWN', uri: uri, iv: iv);
  }

  /// 解析 `#EXTINF` 为时长与可选标题。
  static _ExtInfParseResult _parseExtInf(String line) {
    final match = RegExp(r'#EXTINF:([0-9]+\.?[0-9]*),?(.*)').firstMatch(line);
    if (match == null) {
      return const _ExtInfParseResult(duration: 0.0);
    }
    final duration = double.tryParse(match.group(1) ?? '0') ?? 0.0;
    final title = match.group(2)?.trim();
    return _ExtInfParseResult(
      duration: duration,
      title: title?.isNotEmpty == true ? title : null,
    );
  }

  /// 内容是否含 Master Playlist 标记。
  static bool _containsMasterPlaylist(String content) {
    return content.contains(_masterTag);
  }

  /// 内容是否含 Media Playlist 标记。
  static bool _containsMediaPlaylist(String content) {
    return content.contains(_mediaTag) ||
        content.contains(_endListTag) ||
        content.contains(_discontinuityTag);
  }

  /// URL 是否指向 M3U8 资源。
  static bool _isM3u8Url(String url) {
    return url.toLowerCase().endsWith('.m3u8') || url.contains('.m3u8?');
  }

  /// URL 是否应作为嵌套 playlist 展开。
  static bool _shouldExpandNested(String url) {
    return _isM3u8Url(url) || url.startsWith('data:');
  }

  /// 解析嵌套 M3U8 URL。
  ///
  /// 仅处理 `data:` URI；远程嵌套 playlist 需调用方先抓取内容再传入 [parse]，
  /// 此处返回占位分片以保证 URL 不丢失。
  static List<M3u8Segment> _resolveNestedMedia(
    String url, {
    String? baseUrl,
    required int maxRecursion,
  }) {
    final dataUriContent = _tryParseDataUri(url);
    if (dataUriContent != null) {
      return _parseMediaInternal(
        dataUriContent,
        baseUrl: baseUrl,
        maxRecursion: maxRecursion,
      );
    }
    // 无外部抓取器时无法展开远程嵌套 playlist，返回占位分片保留 URL。
    return [
      M3u8Segment(
        url: url,
        duration: 0.0,
        title: 'nested-m3u8',
      ),
    ];
  }

  /// 解码 `data:...;base64,...` URI 为纯文本。
  static String? _tryParseDataUri(String url) {
    if (!url.startsWith('data:')) return null;
    final commaIndex = url.indexOf(',');
    if (commaIndex == -1) return null;
    final meta = url.substring(5, commaIndex).toLowerCase();
    final data = url.substring(commaIndex + 1);
    if (meta.contains('base64')) {
      try {
        return utf8.decode(base64Decode(data));
      } catch (_) {
        return null;
      }
    }
    return Uri.decodeComponent(data.replaceAll('+', ' '));
  }
}

/// `#EXT-X-STREAM-INF` 属性临时容器。
class M3u8StreamInfAttributes {
  int? bandwidth;
  String? resolution;
  String? codecs;
}

/// `#EXTINF` 解析临时结果。
class _ExtInfParseResult {
  final double duration;
  final String? title;

  const _ExtInfParseResult({required this.duration, this.title});
}
