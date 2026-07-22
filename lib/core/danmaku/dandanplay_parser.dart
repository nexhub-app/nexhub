import 'package:flutter/material.dart';

import 'danmaku_source.dart';

/// 弹弹play API 响应解析器。
class DandanplayParser {
  const DandanplayParser._();

  /// 解析 `/api/v2/search/anime` 的 `animes[]`。
  static List<DanmakuSearchResult> parseSearchResponse(
      Map<String, dynamic> json) {
    final animes = json['animes'];
    if (animes is! List) return const <DanmakuSearchResult>[];
    return animes
        .whereType<Map<String, dynamic>>()
        .map((a) => DanmakuSearchResult(
              animeId: _asString(a['animeId']),
              title: _asString(a['animeTitle']),
              subtitle: _asNullableString(a['typeDescription']),
              type: _asNullableString(a['type']),
              imageUrl: _asNullableString(a['imageUrl']),
            ))
        .toList(growable: false);
  }

  /// 解析 `/api/v2/search/episodes` 的 `animes[].episodes[]`。
  static List<DanmakuEpisode> parseEpisodesResponse(
      Map<String, dynamic> json) {
    final animes = json['animes'];
    if (animes is! List) return const <DanmakuEpisode>[];
    final out = <DanmakuEpisode>[];
    for (final anime in animes) {
      if (anime is! Map<String, dynamic>) continue;
      final episodes = anime['episodes'];
      if (episodes is! List) continue;
      for (final ep in episodes) {
        if (ep is! Map<String, dynamic>) continue;
        out.add(DanmakuEpisode(
          episodeId: _asString(ep['episodeId']),
          title: _asString(ep['episodeTitle']),
          episodeNumber: _asInt(ep['episodeNumber']),
        ));
      }
    }
    return out;
  }

  /// 解析 `/api/v2/comment/{episodeId}` 的 `comments[]`。
  ///
  /// `p` 字段格式：`时间,模式,颜色,用户ID`
  /// 模式：1=scroll, 4=bottom, 5=top
  /// 颜色：`R*65536+G*256+B` 整数转 Color
  static List<ParsedDanmakuItem> parseCommentResponse(
      Map<String, dynamic> json) {
    final comments = json['comments'];
    if (comments is! List) return const <ParsedDanmakuItem>[];
    return comments
        .whereType<Map<String, dynamic>>()
        .map(parseComment)
        .whereType<ParsedDanmakuItem>()
        .toList(growable: false);
  }

  /// 解析单条 comment。
  static ParsedDanmakuItem? parseComment(Map<String, dynamic> c) {
    final p = _asString(c['p']);
    final text = _asString(c['m']);
    final parts = p.split(',');
    if (parts.length < 3) return null;
    final time = double.tryParse(parts[0]);
    final modeRaw = int.tryParse(parts[1]);
    final colorRaw = int.tryParse(parts[2]);
    if (time == null || modeRaw == null || colorRaw == null) return null;
    return ParsedDanmakuItem(
      text: text,
      time: time,
      color: _intToColor(colorRaw),
      mode: _parseMode(modeRaw),
    );
  }

  static DanmakuMode _parseMode(int mode) {
    switch (mode) {
      case 4:
        return DanmakuMode.bottom;
      case 5:
        return DanmakuMode.top;
      default:
        return DanmakuMode.scroll;
    }
  }

  /// `R*65536+G*256+B` 整数转 Color。
  static Color _intToColor(int value) {
    final r = (value >> 16) & 0xff;
    final g = (value >> 8) & 0xff;
    final b = value & 0xff;
    return Color.fromARGB(255, r, g, b);
  }

  static String _asString(dynamic v) => v?.toString() ?? '';
  static String? _asNullableString(dynamic v) => v?.toString();
  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
