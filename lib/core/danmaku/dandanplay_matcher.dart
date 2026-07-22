/// 弹弹play 弹幕自动匹配器。
///
/// 按番剧标题搜索弹弹play → 取最相关条目 → 拉取剧集列表 →
/// 按集数/标题匹配源剧集 → 返回 每个剧集索引 → dandanplayEpisodeId。
///
/// 全流程 best-effort：任何网络错误 / 解析失败均静默返回空 map，
/// 不影响主解析流程。
library;

import '../models/episode.dart';
import '../settings/danmaku_config.dart';
import 'dandanplay_service.dart';
import 'danmaku_source.dart';

class DandanplayMatcher {
  DandanplayMatcher({required DandanplayService dandanplay})
      : _dandanplay = dandanplay;

  final DandanplayService _dandanplay;

  static DandanplayMatcher? _default;

  /// 默认实例（懒加载，使用共享弹幕配置）。
  /// 供 [BuiltinResolver] 在未显式注入 matcher 时使用。
  static DandanplayMatcher get defaultInstance {
    return _default ??= DandanplayMatcher(
      dandanplay: DandanplayService(configStore: DanmakuConfigStore()),
    );
  }

  /// 仅供测试重置默认实例。
  static void resetDefault() => _default = null;

  /// 按标题搜索弹弹play 并匹配剧集。
  ///
  /// 返回 `{剧集索引: dandanplayEpisodeId}`。匹配失败返回空 map。
  Future<Map<int, int>> matchEpisodes(
    String title,
    List<Episode> episodes,
  ) async {
    if (title.isEmpty || episodes.isEmpty) return const <int, int>{};
    try {
      await _dandanplay.refreshAvailability();
      if (!_dandanplay.isAvailable) return const <int, int>{};

      final results = await _dandanplay.search(title);
      if (results.isEmpty) return const <int, int>{};

      // 取第一个（最相关）条目，拉取其剧集列表。
      final anime = results.first;
      final dandanEps = await _dandanplay.getEpisodes(anime.animeId);
      if (dandanEps.isEmpty) return const <int, int>{};

      return _buildMapping(episodes, dandanEps);
    } on Object {
      // 网络错误 / 解析失败：静默返回空 map。
      return const <int, int>{};
    }
  }

  /// 构建剧集索引 → dandanplayEpisodeId 映射。
  ///
  /// 优先按集数匹配（从源剧集标题提取集数 → 对应 dandanplay episodeNumber）；
  /// 若按集数未匹配到任何条目，则按顺序匹配（best-effort）。
  Map<int, int> _buildMapping(
    List<Episode> sourceEps,
    List<DanmakuEpisode> dandanEps,
  ) {
    // 建立集数 → dandanplayEpisodeId 索引。
    final byNumber = <int, int>{};
    for (final de in dandanEps) {
      if (de.episodeNumber == null) continue;
      final eid = int.tryParse(de.episodeId);
      if (eid != null) byNumber[de.episodeNumber!] = eid;
    }

    final map = <int, int>{};

    // 1. 按集数匹配。
    for (int i = 0; i < sourceEps.length; i++) {
      final epNum = _extractEpisodeNumber(sourceEps[i].title);
      if (epNum != null && byNumber.containsKey(epNum)) {
        map[i] = byNumber[epNum]!;
      }
    }
    if (map.isNotEmpty) return map;

    // 2. 按顺序匹配（仅当源剧集数 ≤ 弹弹play 剧集数时）。
    if (sourceEps.length <= dandanEps.length) {
      for (int i = 0; i < sourceEps.length; i++) {
        final eid = int.tryParse(dandanEps[i].episodeId);
        if (eid != null) map[i] = eid;
      }
    }
    return map;
  }

  /// 从剧集标题中提取集数。
  ///
  /// 支持格式：`第3集` / `第3话` / `第3回` / `EP12` / `E12` / `12`。
  static int? _extractEpisodeNumber(String title) {
    final patterns = <RegExp>[
      RegExp('\u7B2C\\s*(\\d+)\\s*[\u96C6\u8BDD\u56DE\u8A71]'),
      RegExp(r'[Ee][Pp]?\.?\s*(\d+)'),
      RegExp(r'^\s*(\d+)\s*$'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(title);
      if (m != null) return int.tryParse(m.group(1)!);
    }
    return null;
  }
}
