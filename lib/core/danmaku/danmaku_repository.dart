import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:xml/xml.dart';

import 'danmaku_source.dart';
import 'dandanplay_service.dart';
import 'bilibili_danmaku_service.dart';

/// Fetcher for a direct danmaku URL body (injectable for testing).
typedef DanmakuUrlFetcher = Future<String> Function(String url);

/// 弹幕仓库（多源 fallback + Hive 缓存）。
class DanmakuRepository {
  DanmakuRepository({
    required DandanplayService dandanplay,
    required BilibiliDanmakuService bilibili,
    required Box<dynamic> cacheBox,
    DanmakuUrlFetcher? urlFetcher,
  })  : _dandanplay = dandanplay,
        _bilibili = bilibili,
        _cacheBox = cacheBox,
        _urlFetcher = urlFetcher ?? _defaultUrlFetcher;

  final DandanplayService _dandanplay;
  final BilibiliDanmakuService _bilibili;
  final Box<dynamic> _cacheBox;
  final DanmakuUrlFetcher _urlFetcher;

  /// 搜索弹幕（仅弹弹play）。
  Future<List<DanmakuSearchResult>> search(String keyword) async {
    await _dandanplay.refreshAvailability();
    if (!_dandanplay.isAvailable) return const <DanmakuSearchResult>[];
    return _dandanplay.search(keyword);
  }

  /// 获取剧集列表（仅弹弹play）。
  Future<List<DanmakuEpisode>> getEpisodes(String animeId) async {
    await _dandanplay.refreshAvailability();
    if (!_dandanplay.isAvailable) return const <DanmakuEpisode>[];
    return _dandanplay.getEpisodes(animeId);
  }

  /// 获取弹幕，按优先级回退：danmakuUrl → 弹弹play → Bilibili → 缓存。
  ///
  /// cacheKey = `$sourceId:$episodeId`。
  /// [dandanplayEpisodeId] / [bilibiliCid] / [bangumiId] 均为可选，
  /// 由弹幕自动匹配（BuiltinResolver）填充到 Episode 后透传至此。
  /// [bangumiId] 当前预留（无 Bangumi 弹幕源），供未来集成使用。
  /// [danmakuUrl] 非空时作为最高优先级通道，直接 HTTP GET 拉取弹幕
  ///（兼容弹弹play/Bilibili XML 与自定义 JSON 格式），失败则按原三级回退。
  Future<List<ParsedDanmakuItem>> getDanmaku({
    required String sourceId,
    required String episodeId,
    int? dandanplayEpisodeId,
    int? bilibiliCid,
    int? bangumiId,
    String? danmakuUrl,
  }) async {
    final cacheKey = '$sourceId:$episodeId';

    List<ParsedDanmakuItem> result = const <ParsedDanmakuItem>[];

    // 0. danmakuUrl 直链（最高优先级）
    if (danmakuUrl != null && danmakuUrl.isNotEmpty) {
      try {
        final body = await _urlFetcher(danmakuUrl);
        result = _parseUrlBody(body);
      } on Object {
        result = const <ParsedDanmakuItem>[];
      }
    }

    await _dandanplay.refreshAvailability();

    // 1. 弹弹play
    if (result.isEmpty &&
        _dandanplay.isAvailable &&
        dandanplayEpisodeId != null) {
      try {
        result = await _dandanplay.getComments(dandanplayEpisodeId.toString());
      } on Object {
        result = const <ParsedDanmakuItem>[];
      }
    }

    // 2. Bilibili fallback
    if (result.isEmpty && bilibiliCid != null) {
      try {
        result = await _bilibili.getComments(bilibiliCid.toString());
      } on Object {
        result = const <ParsedDanmakuItem>[];
      }
    }

    // 3. 缓存 fallback（网络源均失败时尝试缓存）
    if (result.isEmpty) {
      final cached = _readCache(cacheKey);
      if (cached != null) return cached;
    } else {
      _writeCache(cacheKey, result);
    }
    return result;
  }

  List<ParsedDanmakuItem>? _readCache(String key) {
    final raw = _cacheBox.get(key);
    if (raw is! String || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(ParsedDanmakuItem.fromJson)
          .toList(growable: false);
    } on Object {
      return null;
    }
  }

  void _writeCache(String key, List<ParsedDanmakuItem> items) {
    final json = jsonEncode(items.map((e) => e.toJson()).toList());
    _cacheBox.put(key, json);
  }

  /// 解析 danmakuUrl 直链返回体（先尝试 XML，再尝试 JSON）。
  ///
  /// XML 兼容弹弹play / Bilibili 格式：
  /// `<i><d p="time,mode,fontSize,color,timestamp,pool,user,rowid">text</d></i>`
  /// JSON 格式：`{"danmaku":[{"text","time","color","mode"}]}`
  List<ParsedDanmakuItem> _parseUrlBody(String body) {
    if (body.isEmpty) return const <ParsedDanmakuItem>[];
    try {
      final document = XmlDocument.parse(body);
      final nodes = document.findAllElements('d');
      if (nodes.isEmpty) return _parseJsonBody(body);
      final out = <ParsedDanmakuItem>[];
      for (final node in nodes) {
        final p = node.getAttribute('p');
        final text = node.innerText.trim();
        if (p == null || text.isEmpty) continue;
        final parts = p.split(',');
        if (parts.length < 4) continue;
        final time = double.tryParse(parts[0]);
        final modeRaw = int.tryParse(parts[1]);
        final colorRaw = int.tryParse(parts[3]);
        if (time == null || modeRaw == null || colorRaw == null) continue;
        out.add(ParsedDanmakuItem(
          text: text,
          time: time,
          color: _intToColor(colorRaw),
          mode: _parseMode(modeRaw),
        ));
      }
      return out;
    } on Object {
      return _parseJsonBody(body);
    }
  }

  List<ParsedDanmakuItem> _parseJsonBody(String body) {
    try {
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) return const <ParsedDanmakuItem>[];
      final list = data['danmaku'];
      if (list is! List<dynamic>) return const <ParsedDanmakuItem>[];
      final out = <ParsedDanmakuItem>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final text = item['text'] as String?;
        final time = (item['time'] as num?)?.toDouble();
        if (text == null || text.isEmpty || time == null) continue;
        final colorRaw = (item['color'] as num?)?.toInt();
        final modeRaw = (item['mode'] as num?)?.toInt();
        out.add(ParsedDanmakuItem(
          text: text,
          time: time,
          color:
              colorRaw != null ? _intToColor(colorRaw) : const Color(0xFFFFFFFF),
          mode: modeRaw != null ? _parseMode(modeRaw) : DanmakuMode.scroll,
        ));
      }
      return out;
    } on Object {
      return const <ParsedDanmakuItem>[];
    }
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

  /// 默认 danmakuUrl 拉取器（best-effort，失败抛出由调用方捕获）。
  static Future<String> _defaultUrlFetcher(String url) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
    ));
    final response = await dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }
}
