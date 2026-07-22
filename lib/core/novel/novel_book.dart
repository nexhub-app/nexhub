/// 小说书籍模型（文档 8.4）。
///
/// 标准字段：name / author / coverUrl / intro / kind / bookStatus /
/// recommendations / updateTime；章节列表由详情页加载后注入。
library;

import 'novel_chapter.dart';

class NovelBook {
  final String id;
  final String name;
  final String? author;
  final String? coverUrl;
  final String? intro;
  final String? bookStatus;
  final String? updateTime;

  /// 标签 / 分类。
  final List<String> kinds;

  /// 章节列表（详情页加载后填充）。
  final List<NovelChapter> chapters;

  /// 推荐书目（标题列表）。
  final List<String> recommendations;

  /// 来源 ID。
  final String? sourceId;

  const NovelBook({
    required this.id,
    required this.name,
    this.author,
    this.coverUrl,
    this.intro,
    this.bookStatus,
    this.updateTime,
    this.kinds = const <String>[],
    this.chapters = const <NovelChapter>[],
    this.recommendations = const <String>[],
    this.sourceId,
  });

  /// Whether the book is completed.
  bool get isCompleted =>
      bookStatus != null &&
      (bookStatus!.toLowerCase().contains('complete') ||
          bookStatus!.toLowerCase().contains('ended') ||
          bookStatus!.toLowerCase().contains('finished'));

  NovelBook copyWith({
    String? id,
    String? name,
    String? author,
    String? coverUrl,
    String? intro,
    String? bookStatus,
    String? updateTime,
    List<String>? kinds,
    List<NovelChapter>? chapters,
    List<String>? recommendations,
    String? sourceId,
  }) {
    return NovelBook(
      id: id ?? this.id,
      name: name ?? this.name,
      author: author ?? this.author,
      coverUrl: coverUrl ?? this.coverUrl,
      intro: intro ?? this.intro,
      bookStatus: bookStatus ?? this.bookStatus,
      updateTime: updateTime ?? this.updateTime,
      kinds: kinds ?? this.kinds,
      chapters: chapters ?? this.chapters,
      recommendations: recommendations ?? this.recommendations,
      sourceId: sourceId ?? this.sourceId,
    );
  }
}
