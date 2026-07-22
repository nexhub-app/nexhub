import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import 'danmaku_source.dart';

/// Bilibili 弹幕服务（fallback）。
///
/// 仅实现 [getComments]（通过 cid 拉取 XML 弹幕），
/// 不提供搜索/剧集接口。
class BilibiliDanmakuService implements DanmakuSource {
  BilibiliDanmakuService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              responseType: ResponseType.plain,
            ));

  final Dio _dio;

  @override
  DanmakuSourceType get type => DanmakuSourceType.bilibili;

  @override
  String get name => 'Bilibili';

  @override
  bool get isAvailable => true;

  @override
  Future<List<DanmakuSearchResult>> search(String keyword) {
    throw UnsupportedError('Bilibili danmaku source does not support search');
  }

  @override
  Future<List<DanmakuEpisode>> getEpisodes(String animeId) {
    throw UnsupportedError(
        'Bilibili danmaku source does not support getEpisodes');
  }

  /// 请求 `https://comment.bilibili.com/{cid}.xml`。
  ///
  /// 每个 `<d p="time,mode,color,uid">text</d>` 转为 [ParsedDanmakuItem]。
  @override
  Future<List<ParsedDanmakuItem>> getComments(String cid) async {
    final url = 'https://comment.bilibili.com/$cid.xml';
    final response = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final body = response.data;
    if (body == null || body.isEmpty) return const <ParsedDanmakuItem>[];
    return _parseXml(body);
  }

  List<ParsedDanmakuItem> _parseXml(String xml) {
    final document = XmlDocument.parse(xml);
    final out = <ParsedDanmakuItem>[];
    final nodes = document.findAllElements('d');
    for (final node in nodes) {
      final p = node.getAttribute('p');
      final text = node.innerText.trim();
      if (p == null || text.isEmpty) continue;
      final parts = p.split(',');
      if (parts.length < 3) continue;
      final time = double.tryParse(parts[0]);
      final modeRaw = int.tryParse(parts[1]);
      final colorRaw = int.tryParse(parts[2]);
      if (time == null || modeRaw == null || colorRaw == null) continue;
      out.add(ParsedDanmakuItem(
        text: text,
        time: time,
        color: _intToColor(colorRaw),
        mode: _parseMode(modeRaw),
      ));
    }
    return out;
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

  /// `R*65536+G*256+B` 整数转 Color（与弹弹play 编码一致）。
  static Color _intToColor(int value) {
    final r = (value >> 16) & 0xff;
    final g = (value >> 8) & 0xff;
    final b = value & 0xff;
    return Color.fromARGB(255, r, g, b);
  }
}
