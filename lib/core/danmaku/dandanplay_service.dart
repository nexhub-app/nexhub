import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../settings/danmaku_config.dart';
import 'dandanplay_parser.dart';
import 'danmaku_source.dart';

/// 弹弹play 弹幕服务。
///
/// 签名算法：`base64(sha256(AppId+Timestamp+Path+AppSecret))`
/// 请求头：`X-AppId`、`X-Timestamp`、`X-Signature`
class DandanplayService implements DanmakuSource {
  DandanplayService({
    required DanmakuConfigStore configStore,
    Dio? dio,
  })  : _configStore = configStore,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              followRedirects: true,
            ));

  static const String _baseUrl = 'https://api.dandanplay.net';

  final DanmakuConfigStore _configStore;
  final Dio _dio;

  DanmakuConfig? _cachedConfig;

  @override
  DanmakuSourceType get type => DanmakuSourceType.dandanplay;

  @override
  String get name => 'DanDanPlay';

  /// 加载最新凭据。
  Future<DanmakuConfig> _loadConfig() async {
    final cfg = await _configStore.load();
    _cachedConfig = cfg;
    return cfg;
  }

  @override
  bool get isAvailable {
    final cfg = _cachedConfig;
    if (cfg == null) return false;
    return cfg.isConfigured && cfg.enabled;
  }

  /// 刷新可用性状态（在使用前调用）。
  Future<void> refreshAvailability() async {
    await _loadConfig();
  }

  @override
  Future<List<DanmakuSearchResult>> search(String keyword) async {
    const path = '/api/v2/search/anime';
    final query = <String, dynamic>{'anime': keyword};
    final json = await _get(path, query);
    return DandanplayParser.parseSearchResponse(json);
  }

  @override
  Future<List<DanmakuEpisode>> getEpisodes(String animeId) async {
    const path = '/api/v2/search/episodes';
    final query = <String, dynamic>{'anime': animeId};
    final json = await _get(path, query);
    return DandanplayParser.parseEpisodesResponse(json);
  }

  @override
  Future<List<ParsedDanmakuItem>> getComments(String episodeId) async {
    final path = '/api/v2/comment/$episodeId';
    final query = <String, dynamic>{'withRelated': 'true'};
    final json = await _get(path, query);
    return DandanplayParser.parseCommentResponse(json);
  }

  /// 发送带签名的 GET 请求。
  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, dynamic> query,
  ) async {
    final cfg = await _loadConfig();
    if (!cfg.isConfigured) {
      throw StateError('DanDanPlay credentials not configured');
    }
    final timestamp = _timestamp();
    final signature = _sign(cfg.appId, cfg.appSecret, timestamp, path);

    final response = await _dio.get<Map<String, dynamic>>(
      path,
      queryParameters: query,
      options: Options(
        headers: <String, String>{
          'X-AppId': cfg.appId,
          'X-Timestamp': timestamp,
          'X-Signature': signature,
          'User-Agent': 'NexHub/1.0',
          'Accept': 'application/json',
        },
        responseType: ResponseType.json,
      ),
    );

    final data = response.data;
    if (data == null) {
      throw StateError('DanDanPlay empty response');
    }
    return data;
  }

  /// Unix 时间戳（秒）。
  static String _timestamp() =>
      (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000).toString();

  /// 签名：`base64(sha256(AppId+Timestamp+Path+AppSecret))`。
  static String _sign(
      String appId, String appSecret, String timestamp, String path) {
    final raw = '$appId$timestamp$path$appSecret';
    final digest = sha256.convert(utf8.encode(raw));
    return base64Encode(digest.bytes);
  }
}
