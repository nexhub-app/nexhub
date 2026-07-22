/// 书源导入服务：解析书源 JSON / XML / 文本批量格式，
/// 输出 [ShuyuanSource] 列表，供 [ShuyuanAdapter] 转换为 [PluginConfig]。
///
/// 支持格式：
/// - JSON 数组（最常见）：`[{ "bookSourceUrl": ... }, ...]`
/// - JSON 单对象：`{ "bookSourceUrl": ... }`
/// - JSON 包装：`{ "bookSources": [...] }`
/// - XML：`<sources><source>...</source></sources>`
/// - NDJSON（每行一个对象）
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import 'model/book_source.dart';
import 'model/rule_book_info.dart';
import 'model/rule_content.dart';
import 'model/rule_explore.dart';
import 'model/rule_search.dart';
import 'model/rule_toc.dart';

/// 书源原始数据（与 XiaoshuoBookSource 区别：保持 Map 形态，
/// 便于在 adapter 阶段一并保存到 PluginConfig.selectors['xiaoshuo']
/// 实现完整规则回写）。
class ShuyuanSource {
  final String bookSourceName;
  final String bookSourceUrl;
  final int bookSourceType;
  final String? bookSourceGroup;
  final String? bookSourceComment;
  final bool enabled;
  final String? searchUrl;
  final String? exploreUrl;
  final String? header;
  final String? tocUrl;
  final Map<String, dynamic>? ruleSearch;
  final Map<String, dynamic>? ruleBookInfo;
  final Map<String, dynamic>? ruleToc;
  final Map<String, dynamic>? ruleContent;
  final Map<String, dynamic>? ruleExplore;

  const ShuyuanSource({
    required this.bookSourceName,
    required this.bookSourceUrl,
    this.bookSourceType = 0,
    this.bookSourceGroup,
    this.bookSourceComment,
    this.enabled = true,
    this.searchUrl,
    this.exploreUrl,
    this.header,
    this.tocUrl,
    this.ruleSearch,
    this.ruleBookInfo,
    this.ruleToc,
    this.ruleContent,
    this.ruleExplore,
  });

  bool get isValid =>
      bookSourceName.isNotEmpty &&
      bookSourceUrl.isNotEmpty &&
      (ruleSearch != null ||
          ruleToc != null ||
          ruleContent != null ||
          ruleExplore != null);

  /// 转换为 XiaoshuoBookSource（供 WebBook 直接消费）。
  XiaoshuoBookSource toBookSource() {
    return XiaoshuoBookSource(
      bookSourceUrl: bookSourceUrl,
      bookSourceName: bookSourceName,
      bookSourceGroup: bookSourceGroup,
      bookSourceType: bookSourceType,
      bookSourceComment: bookSourceComment,
      enabled: enabled,
      header: header,
      searchUrl: searchUrl,
      exploreUrl: exploreUrl,
      ruleSearch:
          ruleSearch != null ? SearchRule.fromJson(ruleSearch!) : null,
      ruleBookInfo: ruleBookInfo != null
          ? BookInfoRule.fromJson(ruleBookInfo!)
          : null,
      ruleToc: ruleToc != null ? TocRule.fromJson(ruleToc!) : null,
      ruleContent:
          ruleContent != null ? ContentRule.fromJson(ruleContent!) : null,
      ruleExplore:
          ruleExplore != null ? ExploreRule.fromJson(ruleExplore!) : null,
    );
  }

  factory ShuyuanSource.fromJson(Map<String, dynamic> json) {
    String? resolveTocUrl() {
      final topToc = json['tocUrl'];
      if (topToc is String && topToc.isNotEmpty) return topToc;
      if (topToc is Map) {
        for (final k in ['url', 'tocUrl', 'value', 'rule']) {
          final v = topToc[k];
          if (v is String && v.isNotEmpty) return v;
        }
      }
      final bookInfo = _parseRuleDynamic(json['ruleBookInfo']);
      if (bookInfo != null) {
        final tUrl = bookInfo['tocUrl'];
        if (tUrl is String && tUrl.isNotEmpty) return tUrl;
      }
      return null;
    }

    return ShuyuanSource(
      bookSourceName: json['bookSourceName'] as String? ?? '',
      bookSourceUrl: json['bookSourceUrl'] as String? ?? '',
      bookSourceType: json['bookSourceType'] as int? ?? 0,
      bookSourceGroup: json['bookSourceGroup'] as String?,
      bookSourceComment: json['bookSourceComment'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      searchUrl: json['searchUrl'] as String?,
      exploreUrl: json['exploreUrl'] as String?,
      header: json['header'] as String?,
      tocUrl: resolveTocUrl(),
      ruleSearch: _parseRuleDynamic(json['ruleSearch']),
      ruleBookInfo: _parseRuleDynamic(json['ruleBookInfo']),
      ruleToc: _parseRuleDynamic(json['ruleToc']),
      ruleContent: _parseRuleDynamic(json['ruleContent']),
      ruleExplore: _parseRuleDynamic(json['ruleExplore']),
    );
  }

  Map<String, dynamic> toJson() => {
        'bookSourceName': bookSourceName,
        'bookSourceUrl': bookSourceUrl,
        'bookSourceType': bookSourceType,
        if (bookSourceGroup != null) 'bookSourceGroup': bookSourceGroup,
        if (bookSourceComment != null) 'bookSourceComment': bookSourceComment,
        'enabled': enabled,
        if (searchUrl != null) 'searchUrl': searchUrl,
        if (exploreUrl != null) 'exploreUrl': exploreUrl,
        if (header != null) 'header': header,
        if (tocUrl != null) 'tocUrl': tocUrl,
        if (ruleSearch != null) 'ruleSearch': ruleSearch,
        if (ruleBookInfo != null) 'ruleBookInfo': ruleBookInfo,
        if (ruleToc != null) 'ruleToc': ruleToc,
        if (ruleContent != null) 'ruleContent': ruleContent,
        if (ruleExplore != null) 'ruleExplore': ruleExplore,
      };
}

Map<String, dynamic>? _parseRuleDynamic(dynamic val) {
  if (val == null) return null;
  if (val is Map<String, dynamic>) return val;
  if (val is Map) return Map<String, dynamic>.from(val.cast<String, dynamic>());
  if (val is String) {
    final s = val.trim();
    if (s.isEmpty) return null;
    try {
      final decoded = json.decode(s);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      }
    } catch (_) {
      // 不是 JSON 字符串
    }
  }
  if (val is List) {
    for (final item in val) {
      if (item is Map<String, dynamic>) return item;
      if (item is Map) {
        return Map<String, dynamic>.from(item.cast<String, dynamic>());
      }
      if (item is String) {
        try {
          final decoded = json.decode(item);
          if (decoded is Map<String, dynamic>) return decoded;
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
          }
        } catch (_) {}
      }
    }
  }
  return null;
}

class ShuyuanSourceService {
  final Dio _dio;

  ShuyuanSourceService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (status) => status != null && status < 500,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Accept': '*/*',
          },
        ));

  /// 从 URL 抓取书源列表。
  Future<List<ShuyuanSource>> fetchSourcesFromUrl(String url) async {
    final resolvedUrl = _resolveUrl(url);
    final response = await _dio.get<String>(resolvedUrl);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final content = response.data ?? '';
    return _parseSourceContent(content);
  }

  /// 从本地文件读取书源列表。
  Future<List<ShuyuanSource>> fetchSourcesFromFile(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    return _parseSourceContent(content);
  }

  /// 解析书源内容字符串。
  List<ShuyuanSource> parseSources(String content) {
    return _parseSourceContent(content);
  }

  /// 处理 `xiaoshuo://import/bookSource?src=...` 形式的导入 URL。
  String _resolveUrl(String url) {
    if (url.startsWith('xiaoshuo://') || url.startsWith('shuyuan://')) {
      try {
        final uri = Uri.parse(url);
        final src = uri.queryParameters['src'];
        if (src != null && src.isNotEmpty) {
          return Uri.decodeFull(src);
        }
      } catch (_) {}

      final match = RegExp(r'src=([^&]+)').firstMatch(url);
      if (match != null) {
        return Uri.decodeFull(match.group(1)!);
      }
    }
    return url;
  }

  List<ShuyuanSource> _parseSourceContent(String content) {
    content = content.trim();

    if (content.startsWith('<')) {
      return _parseXml(content);
    }

    if (content.startsWith('[')) {
      return _parseJsonArray(content);
    }

    if (content.startsWith('{')) {
      final single = _parseSingleSource(content);
      return single != null ? [single] : <ShuyuanSource>[];
    }

    // 兜底：从内容中提取首个 JSON 数组
    final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(content);
    if (jsonMatch != null) {
      return _parseJsonArray(jsonMatch.group(0)!);
    }

    // 兜底：按行解析 NDJSON
    final sources = <ShuyuanSource>[];
    for (final line in LineSplitter.split(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('{')) {
        final s = _parseSingleSource(trimmed);
        if (s != null) sources.add(s);
      }
    }
    return sources;
  }

  List<ShuyuanSource> _parseJsonArray(String jsonStr) {
    try {
      final decoded = json.decode(jsonStr);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((e) => ShuyuanSource.fromJson(e))
            .toList();
      }

      if (decoded is Map<String, dynamic>) {
        // 常见包装键
        for (final key in ['bookSources', 'bookSource', 'data', 'sources', 'items']) {
          if (decoded.containsKey(key)) {
            final arr = decoded[key];
            if (arr is List) {
              return arr
                  .whereType<Map<String, dynamic>>()
                  .map((e) => ShuyuanSource.fromJson(e))
                  .toList();
            }
          }
        }
        // 视为单个书源对象
        return [ShuyuanSource.fromJson(decoded)];
      }
    } catch (_) {}
    return <ShuyuanSource>[];
  }

  ShuyuanSource? _parseSingleSource(String jsonStr) {
    try {
      final decoded = json.decode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return ShuyuanSource.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  List<ShuyuanSource> _parseXml(String xmlStr) {
    final sources = <ShuyuanSource>[];
    try {
      final document = XmlDocument.parse(xmlStr);
      final elements = document.findAllElements('source').toList()
        ..addAll(document.findAllElements('bookSource'));
      for (final el in elements) {
        final map = <String, dynamic>{};
        for (final child in el.childElements) {
          final tag = child.name.local;
          final val = child.innerText;
          if (val.isNotEmpty) map[tag] = val;
        }
        if (map.isNotEmpty) {
          sources.add(ShuyuanSource.fromJson(map));
        }
      }
    } catch (_) {}
    return sources;
  }

  void close() {
    _dio.close();
  }
}
