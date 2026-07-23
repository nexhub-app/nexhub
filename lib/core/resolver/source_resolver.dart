/// 解析器抽象：所有解析能力（Builtin / Script / WebView）的统一契约。
library;

import '../models/plugin_config.dart';

/// 解析某 API（latest/explore/category/search/detail/episodes/video/chapters/images/...）。
///
/// 返回类型按 API 语义：
/// - list 类（latest/search/explore/category）：`List<MediaItem>`
/// - detail：`MediaItem`
/// - episodes/chapters：`List<Episode>`
/// - video：`VideoResult`
abstract class SourceResolver {
  /// [onProgress] 为可选渐进回调：部分 API（如小说章节目录）数据量大、需多页
  /// 串行抓取时，解析器可通过它分批回传中间结果（如 `List<Episode>`），让上层
  /// UI 先渲染首屏、后台续抓，避免整页被长列表阻塞。无此需求的 API 忽略即可。
  Future<dynamic> resolve(
    PluginConfig source,
    String apiName, {
    Map<String, String> vars = const {},
    void Function(List<dynamic>)? onProgress,
  });
}
