/// 剧集 / 章节统一模型（媒体叫「集」，漫画/小说叫「章」）。
/// 同一结构承载播放地址与所属播放线路。
library;

class Episode {
  final String id;
  final String title;
  final String url;
  final String? lineName; // 网站播放线路名（线路一/二/三…）

  /// 弹弹play 剧集 ID（由弹幕自动匹配填充，best-effort）。
  final int? dandanplayEpisodeId;

  /// Bilibili 弹幕 cid（由弹幕自动匹配填充，best-effort）。
  final int? bilibiliCid;

  /// Bangumi 番剧 ID（预留，供未来 Bangumi 集成使用）。
  final int? bangumiId;

  /// Direct danmaku URL (filled at detail route stage, best-effort).
  /// Takes highest priority in DanmakuRepository fallback chain.
  final String? danmakuUrl;

  /// 章节/剧集上传时间（用于排序"按更新时间"）。
  final DateTime? updatedAt;

  /// 章节/剧集序号（用于"显示序号"和"按序号排序"）。
  final int? number;

  const Episode({
    required this.id,
    required this.title,
    required this.url,
    this.lineName,
    this.dandanplayEpisodeId,
    this.bilibiliCid,
    this.bangumiId,
    this.danmakuUrl,
    this.updatedAt,
    this.number,
  });

  /// 复制并覆盖部分字段（弹幕自动匹配时用于生成带 ID 的新实例）。
  Episode copyWith({
    String? id,
    String? title,
    String? url,
    String? lineName,
    int? dandanplayEpisodeId,
    int? bilibiliCid,
    int? bangumiId,
    String? danmakuUrl,
    DateTime? updatedAt,
    int? number,
  }) =>
      Episode(
        id: id ?? this.id,
        title: title ?? this.title,
        url: url ?? this.url,
        lineName: lineName ?? this.lineName,
        dandanplayEpisodeId: dandanplayEpisodeId ?? this.dandanplayEpisodeId,
        bilibiliCid: bilibiliCid ?? this.bilibiliCid,
        bangumiId: bangumiId ?? this.bangumiId,
        danmakuUrl: danmakuUrl ?? this.danmakuUrl,
        updatedAt: updatedAt ?? this.updatedAt,
        number: number ?? this.number,
      );

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
        lineName: json['lineName'] as String?,
        dandanplayEpisodeId: (json['dandanplayEpisodeId'] as num?)?.toInt(),
        bilibiliCid: (json['bilibiliCid'] as num?)?.toInt(),
        bangumiId: (json['bangumiId'] as num?)?.toInt(),
        danmakuUrl: json['danmakuUrl'] as String?,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
        number: (json['number'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'url': url,
        if (lineName != null) 'lineName': lineName,
        if (dandanplayEpisodeId != null) 'dandanplayEpisodeId': dandanplayEpisodeId,
        if (bilibiliCid != null) 'bilibiliCid': bilibiliCid,
        if (bangumiId != null) 'bangumiId': bangumiId,
        if (danmakuUrl != null) 'danmakuUrl': danmakuUrl,
        if (updatedAt != null)
          'updatedAt': updatedAt!.toIso8601String(),
        if (number != null) 'number': number,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Episode &&
          other.id == id &&
          other.url == url &&
          other.lineName == lineName;

  @override
  int get hashCode => Object.hash(id, url, lineName);
}

/// 视频解析结果（直链 MP4/M3U8 / DASH 等）。
class VideoResult {
  final String url;
  final String? type; // mp4 | m3u8 | dash | ...

  /// 播放该地址所需的 HTTP 请求头（反盗链 Referer / UA 等）。
  /// 抓取 m3u8 文本时需要带，播放器真正打开地址（mpv 拉分片）时
  /// 同样必须带上，否则 CDN（如 v5.lbv*.com）返回 403，解不出任何帧 → 黑屏。
  final Map<String, String>? headers;

  const VideoResult({required this.url, this.type, this.headers});

  factory VideoResult.fromJson(Map<String, dynamic> json) => VideoResult(
        url: json['url'] as String,
        type: json['type'] as String?,
        headers: (json['headers'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        if (type != null) 'type': type,
        if (headers != null) 'headers': headers,
      };
}
