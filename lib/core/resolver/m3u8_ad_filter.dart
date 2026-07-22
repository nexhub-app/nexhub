/// M3U8 广告分片过滤：基于 URL 关键词、分片时长、discontinuity 组短时长
/// 三种启发式规则识别并剔除广告分片。
///
/// 同时提供：
/// - 顶层函数 [filterAds]：对已解析的 [M3u8Segment] 列表过滤；
/// - [M3u8AdFilter] 类：对 playlist 原文字符串过滤（保留 header/标签）。
library;

import 'dart:convert';

import 'm3u8_parser.dart';

/// 广告过滤规则。
class AdFilterRules {
  /// 分片 URL 含这些关键词（不区分大小写）视为广告。
  final List<String> adKeywords;

  /// 分片时长低于此值（秒）视为广告；`0` 表示不启用时长规则。
  final double minSegmentDuration;

  /// 是否启用 discontinuity 组短时长过滤。
  final bool useDiscontinuity;

  /// discontinuity 组总时长比相邻组中位数短多少（秒）即视为广告组。
  final double discontinuityAdThreshold;

  /// 保底比例：过滤后分片数少于原数量的此比例时，回退为原始列表，
  /// 避免误杀大面积正常分片。
  final double preserveMinimumRatio;

  const AdFilterRules({
    this.adKeywords = const ['ad', 'advert', 'ads', 'advertisement', 'promo'],
    this.minSegmentDuration = 0.5,
    this.useDiscontinuity = true,
    this.discontinuityAdThreshold = 5.0,
    this.preserveMinimumRatio = 0.5,
  });

  /// 完全不过滤的规则（用于禁用广告过滤场景）。
  static const AdFilterRules disabled = AdFilterRules(
    adKeywords: [],
    minSegmentDuration: 0,
    useDiscontinuity: false,
  );
}

/// 对已解析的分片列表过滤广告。
///
/// 依次应用三条规则：
/// 1. URL 含 [AdFilterRules.adKeywords] 关键词；
/// 2. 分片时长 < [AdFilterRules.minSegmentDuration]；
/// 3. discontinuity 组总时长显著短于相邻组（[AdFilterRules.discontinuityAdThreshold]）。
///
/// 最后做保底检查：若过滤后分片数不足原始的
/// [AdFilterRules.preserveMinimumRatio]，返回原始列表以免误杀。
List<M3u8Segment> filterAds(
  List<M3u8Segment> segments, {
  AdFilterRules rules = const AdFilterRules(),
}) {
  if (segments.length <= 1) return List<M3u8Segment>.unmodifiable(segments);

  final isAd = List<bool>.filled(segments.length, false);

  // 1. URL 关键词匹配（不区分大小写）。
  if (rules.adKeywords.isNotEmpty) {
    final lowerKeywords =
        rules.adKeywords.map((k) => k.toLowerCase()).toList(growable: false);
    for (var i = 0; i < segments.length; i++) {
      final lowerUrl = segments[i].url.toLowerCase();
      if (lowerKeywords.any((k) => lowerUrl.contains(k))) {
        isAd[i] = true;
      }
    }
  }

  // 2. 分片时长过短。
  if (rules.minSegmentDuration > 0) {
    for (var i = 0; i < segments.length; i++) {
      if (segments[i].duration < rules.minSegmentDuration) {
        isAd[i] = true;
      }
    }
  }

  // 3. discontinuity 组短时长过滤。
  if (rules.useDiscontinuity) {
    _markDiscontinuityAdGroups(
      segments,
      isAd,
      rules.discontinuityAdThreshold,
    );
  }

  // 4. 收集保留分片并做保底比例检查。
  final kept = <M3u8Segment>[];
  for (var i = 0; i < segments.length; i++) {
    if (!isAd[i]) kept.add(segments[i]);
  }
  if (kept.isEmpty ||
      kept.length < segments.length * rules.preserveMinimumRatio) {
    return List<M3u8Segment>.unmodifiable(segments);
  }
  return List<M3u8Segment>.unmodifiable(kept);
}

/// 标记 discontinuity 组中显著短于相邻组的组为广告。
void _markDiscontinuityAdGroups(
  List<M3u8Segment> segments,
  List<bool> isAd,
  double threshold,
) {
  // 按出现顺序收集每个 discontinuity 组的分片索引。
  final groupOrder = <int>[];
  final groupSegments = <int, List<int>>{};
  for (var i = 0; i < segments.length; i++) {
    final g = segments[i].discontinuityGroup;
    final list = groupSegments[g];
    if (list == null) {
      groupSegments[g] = [i];
      groupOrder.add(g);
    } else {
      list.add(i);
    }
  }
  if (groupOrder.length <= 1) return;

  // 计算每组总时长。
  final groupDurations = <int, double>{};
  for (final g in groupOrder) {
    var total = 0.0;
    for (final idx in groupSegments[g]!) {
      total += segments[idx].duration;
    }
    groupDurations[g] = total;
  }

  // 比较每个组与其相邻组，短时长组标记为广告。
  for (var gi = 0; gi < groupOrder.length; gi++) {
    final g = groupOrder[gi];
    final prev = gi > 0 ? groupDurations[groupOrder[gi - 1]] : null;
    final next =
        gi < groupOrder.length - 1 ? groupDurations[groupOrder[gi + 1]] : null;
    final neighbors = <double>[
      if (prev != null) prev,
      if (next != null) next,
    ];
    if (neighbors.isEmpty) continue;
    neighbors.sort();
    final median = neighbors.length == 1
        ? neighbors.first
        : (neighbors.first + neighbors.last) / 2;
    if (median - groupDurations[g]! >= threshold) {
      for (final idx in groupSegments[g]!) {
        isAd[idx] = true;
      }
    }
  }
}

/// 对 M3U8 playlist 原文字符串进行广告过滤。
///
/// 与顶层 [filterAds] 不同，本类保留 playlist 的 header 标签与标签结构，
/// 输出仍为可被播放器直接消费的 playlist 字符串。
class M3u8AdFilter {
  static const String _discontinuityTag = '#EXT-X-DISCONTINUITY';
  static const String _extInfTag = '#EXTINF';
  static const String _endListTag = '#EXT-X-ENDLIST';
  static const String _targetDurationTag = '#EXT-X-TARGETDURATION';
  static const String _versionTag = '#EXT-X-VERSION';
  static const String _keyTag = '#EXT-X-KEY';
  static const String _mapTag = '#EXT-X-MAP';
  static const String _streamInfTag = '#EXT-X-STREAM-INF';

  /// 过滤 Media Playlist 字符串中的广告组。
  ///
  /// 按 `#EXT-X-DISCONTINUITY` 边界分组，移除总时长显著短于相邻组的分片组。
  /// [adDurationThreshold] 定义"显著短"的阈值；[preserveMinimumRatio] 为
  /// 保底保留比例，过滤后不足此比例则原样返回。
  static String filter(
    String playlistContent, {
    String? baseUrl,
    double adDurationThreshold = 5.0,
    double preserveMinimumRatio = 0.5,
  }) {
    final lines = LineSplitter.split(playlistContent).toList();
    final originalSegmentCount = _countSegments(lines);
    final groups = _groupByDiscontinuity(lines);

    if (groups.isEmpty) return playlistContent;

    final groupDurations = groups
        .map((group) => _sumGroupDuration(group))
        .toList(growable: false);
    final originalDuration = groupDurations.fold<double>(
      0,
      (sum, duration) => sum + duration,
    );

    final keepFlags = _identifyAdGroups(
      groupDurations,
      adDurationThreshold: adDurationThreshold,
    );

    var keptSegmentCount = 0;
    var keptDuration = 0.0;
    for (var i = 0; i < groups.length; i++) {
      if (!keepFlags[i]) continue;
      keptSegmentCount += _countSegments(groups[i]);
      keptDuration += groupDurations[i];
    }

    // 长 playlist 要求保留 95%，避免误杀；短 playlist 用传入比例。
    final effectiveMinimumRatio =
        originalSegmentCount > 100 ? 0.95 : preserveMinimumRatio;
    if (keptSegmentCount == 0 ||
        keptDuration == 0.0 ||
        keptSegmentCount < originalSegmentCount * effectiveMinimumRatio ||
        keptDuration < originalDuration * effectiveMinimumRatio) {
      return playlistContent;
    }

    final buffer = StringBuffer();
    _writeHeader(buffer, lines);

    var hasContent = false;
    for (var i = 0; i < groups.length; i++) {
      if (!keepFlags[i]) continue;
      _writeGroup(buffer, groups[i], includeLeadingDiscontinuity: hasContent);
      hasContent = true;
    }

    if (_hasEndList(lines)) {
      buffer.writeln(_endListTag);
    }

    return buffer.toString().trimRight();
  }

  /// 过滤广告并返回剩余分片的绝对 URL 列表。
  static List<String> filterToSegments(
    String playlistContent, {
    String? baseUrl,
    double adDurationThreshold = 5.0,
  }) {
    final result = M3u8Parser.parseMedia(
      filter(
        playlistContent,
        baseUrl: baseUrl,
        adDurationThreshold: adDurationThreshold,
      ),
      baseUrl: baseUrl,
    );
    return result.segments.map((s) => s.url).toList(growable: false);
  }

  /// 按 `#EXT-X-DISCONTINUITY` 将 playlist 行分组。
  ///
  /// 首个 `#EXTINF` 起为第一组；后续每个 `#EXT-X-DISCONTINUITY` 开新组。
  /// 首个 `#EXTINF` 之前的加密/元数据标签附加到第一组以保留。
  static List<List<String>> _groupByDiscontinuity(List<String> lines) {
    final groups = <List<String>>[];
    List<String>? currentGroup;
    final leadingMetadata = <String>[];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (_isHeaderTag(line) || line.startsWith(_streamInfTag)) continue;
      if (line == _endListTag) continue;

      if (line.startsWith(_extInfTag)) {
        currentGroup ??= <String>[];
        if (leadingMetadata.isNotEmpty) {
          currentGroup.addAll(leadingMetadata);
          leadingMetadata.clear();
        }
        currentGroup.add(rawLine);
      } else if (line.startsWith(_discontinuityTag)) {
        if (currentGroup != null && currentGroup.isNotEmpty) {
          groups.add(currentGroup);
        }
        currentGroup = <String>[];
      } else if (_isSegmentMetadataTag(line)) {
        if (currentGroup == null) {
          leadingMetadata.add(rawLine);
        } else {
          currentGroup.add(rawLine);
        }
      } else if (currentGroup != null) {
        currentGroup.add(rawLine);
      }
    }

    if (currentGroup != null && currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }

    return groups;
  }

  /// 求一组内所有 `#EXTINF` 时长之和。
  static double _sumGroupDuration(List<String> group) {
    var total = 0.0;
    for (final rawLine in group) {
      final line = rawLine.trim();
      if (line.startsWith(_extInfTag)) {
        final parsed = M3u8Parser.parseMedia(
          '#EXTM3U\n$line\nplaceholder.ts',
        );
        if (parsed.segments.isNotEmpty) {
          total += parsed.segments.first.duration;
        }
      }
    }
    return total;
  }

  /// 统计行中的 `#EXTINF` 数量。
  static int _countSegments(Iterable<String> lines) {
    var count = 0;
    for (final rawLine in lines) {
      if (rawLine.trim().startsWith(_extInfTag)) {
        count++;
      }
    }
    return count;
  }

  /// 识别应保留的组：总时长比相邻组中位数短 [adDurationThreshold] 的组移除。
  static List<bool> _identifyAdGroups(
    List<double> durations, {
    required double adDurationThreshold,
  }) {
    if (durations.length <= 1) {
      return List<bool>.filled(durations.length, true);
    }

    final keep = List<bool>.filled(durations.length, true);
    for (var i = 0; i < durations.length; i++) {
      final previous = i > 0 ? durations[i - 1] : null;
      final next = i < durations.length - 1 ? durations[i + 1] : null;

      final neighbors = <double>[
        if (previous != null) previous,
        if (next != null) next,
      ];
      if (neighbors.isEmpty) continue;

      neighbors.sort();
      final median = neighbors.length == 1
          ? neighbors.first
          : (neighbors.first + neighbors.last) / 2;

      if (median - durations[i] >= adDurationThreshold) {
        keep[i] = false;
      }
    }

    return keep;
  }

  /// 将 header 标签写入 buffer，保留 `#EXT-X-STREAM-INF` 及其变体 URI。
  static void _writeHeader(StringBuffer buffer, List<String> lines) {
    buffer.writeln('#EXTM3U');
    String? pendingStreamInf;
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line == '#EXTM3U') continue;
      if (line.isEmpty) {
        pendingStreamInf = null;
        continue;
      }
      if (_isHeaderTag(line)) {
        buffer.writeln(rawLine);
        continue;
      }
      if (line.startsWith(_streamInfTag)) {
        pendingStreamInf = rawLine;
        continue;
      }
      if (pendingStreamInf != null && !line.startsWith('#')) {
        buffer.writeln(pendingStreamInf);
        buffer.writeln(rawLine);
        pendingStreamInf = null;
        continue;
      }
      // 其他标签取消挂起的 STREAM-INF。
      if (line.startsWith('#')) {
        pendingStreamInf = null;
      }
    }
  }

  /// 将一个分片组写入 buffer。
  static void _writeGroup(
    StringBuffer buffer,
    List<String> group, {
    required bool includeLeadingDiscontinuity,
  }) {
    if (includeLeadingDiscontinuity) {
      buffer.writeln(_discontinuityTag);
    }
    for (final line in group) {
      buffer.writeln(line);
    }
  }

  /// 是否为 playlist header 标签。
  static bool _isHeaderTag(String line) {
    return line.startsWith(_targetDurationTag) ||
        line.startsWith(_versionTag) ||
        line.startsWith('#EXT-X-MEDIA-SEQUENCE') ||
        line.startsWith('#EXT-X-PLAYLIST-TYPE');
  }

  /// 是否为加密/分片元数据标签（需随分片组保留）。
  static bool _isSegmentMetadataTag(String line) {
    return line.startsWith(_keyTag) || line.startsWith(_mapTag);
  }

  /// playlist 是否含 `#EXT-X-ENDLIST`。
  static bool _hasEndList(List<String> lines) {
    return lines.any((l) => l.trim() == _endListTag);
  }
}
