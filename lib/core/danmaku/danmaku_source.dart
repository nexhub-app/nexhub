import 'package:flutter/material.dart';

import '../widgets/danmaku.dart';

/// 弹幕源类型。
///
/// `off` 表示用户主动关闭弹幕加载（不发起任何网络请求）。
enum DanmakuSourceType { dandanplay, bilibili, customUrl, off }

/// 弹幕显示模式。
enum DanmakuMode { scroll, top, bottom }

/// 弹幕搜索结果（动漫条目）。
class DanmakuSearchResult {
  const DanmakuSearchResult({
    required this.animeId,
    required this.title,
    this.subtitle,
    this.type,
    this.imageUrl,
  });

  /// 弹弹play animeId。
  final String animeId;
  final String title;
  final String? subtitle;
  final String? type;
  final String? imageUrl;
}

/// 弹幕剧集。
class DanmakuEpisode {
  const DanmakuEpisode({
    required this.episodeId,
    required this.title,
    this.episodeNumber,
  });

  final String episodeId;
  final String title;
  final int? episodeNumber;
}

/// 从弹幕源解析出的单条弹幕。
///
/// 相比 [DanmakuItem]，此模型携带 [mode] 与浮点 [time]（秒），
/// 便于从弹弹play / Bilibili 原始数据直接转换。
class ParsedDanmakuItem {
  const ParsedDanmakuItem({
    required this.text,
    required this.time,
    required this.color,
    this.mode = DanmakuMode.scroll,
    this.fontSize = 16,
  });

  final String text;

  /// 出现时间（秒）。
  final double time;
  final Color color;
  final DanmakuMode mode;
  final double fontSize;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        'time': time,
        'color': color.toARGB32(),
        'mode': mode.index,
        'fontSize': fontSize,
      };

  static ParsedDanmakuItem fromJson(Map<String, dynamic> json) =>
      ParsedDanmakuItem(
        text: json['text'] as String,
        time: (json['time'] as num).toDouble(),
        color: Color(json['color'] as int),
        mode: DanmakuMode.values[json['mode'] as int? ?? 0],
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16,
      );

  /// 转换为 [DanmakuItem]（canvas_danmaku 数据模型）。
  DanmakuItem toDanmakuItem() => DanmakuItem(
        text: text,
        time: Duration(milliseconds: (time * 1000).round()),
        color: color,
        fontSize: fontSize,
      );
}

/// 弹幕源抽象。
abstract class DanmakuSource {
  DanmakuSourceType get type;
  String get name;
  bool get isAvailable;
  Future<List<DanmakuSearchResult>> search(String keyword);
  Future<List<DanmakuEpisode>> getEpisodes(String animeId);
  Future<List<ParsedDanmakuItem>> getComments(String episodeId);
}
