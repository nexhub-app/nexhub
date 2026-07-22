/// 小说章节模型。
///
/// 承载章节标题、URL 及解析后的正文内容（段落列表）。
library;

class NovelChapter {
  /// 章节标识（通常为 URL 中的路径段或 ID）。
  final String id;

  /// 章节标题。
  final String title;

  /// 章节页面 URL（用于解析正文）。
  final String url;

  /// 章节正文（按段落分割的文本列表；加载前为空）。
  final List<String> paragraphs;

  /// 章节更新时间（可选）。
  final String? updateTime;

  const NovelChapter({
    required this.id,
    required this.title,
    required this.url,
    this.paragraphs = const <String>[],
    this.updateTime,
  });

  /// 从 [Episode] 结构转换（章节列表共用 Episode 承载 id/title/url）。
  factory NovelChapter.fromEpisode({
    required String id,
    required String title,
    required String url,
    List<String>? paragraphs,
    String? updateTime,
  }) {
    return NovelChapter(
      id: id,
      title: title,
      url: url,
      paragraphs: paragraphs ?? const <String>[],
      updateTime: updateTime,
    );
  }

  NovelChapter copyWith({
    String? id,
    String? title,
    String? url,
    List<String>? paragraphs,
    String? updateTime,
  }) {
    return NovelChapter(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      paragraphs: paragraphs ?? this.paragraphs,
      updateTime: updateTime ?? this.updateTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NovelChapter && other.id == id && other.url == url;

  @override
  int get hashCode => Object.hash(id, url);
}
