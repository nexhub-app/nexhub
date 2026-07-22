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
  Future<dynamic> resolve(
    PluginConfig source,
    String apiName, {
    Map<String, String> vars = const {},
  });
}
