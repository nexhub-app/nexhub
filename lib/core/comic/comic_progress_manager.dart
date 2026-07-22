/// 漫画阅读进度管理（按 comicId 持久化）。
///
/// 记录当前章节与页码；切章节时同步 [lastReadChapterIndex]，供书架「续读」使用。
library;

import 'dart:convert';

import 'models/reader_preferences.dart';

/// 单部作品的阅读进度。
class ReadingProgress {
  final String chapterId;
  final int currentPage;
  final int chapterIndex;
  final int? totalChapters;

  const ReadingProgress({
    required this.chapterId,
    required this.currentPage,
    required this.chapterIndex,
    this.totalChapters,
  });

  factory ReadingProgress.fromJson(Map<String, dynamic> json) => ReadingProgress(
        chapterId: json['chapterId'] as String? ?? '',
        currentPage: json['currentPage'] as int? ?? 0,
        chapterIndex: json['chapterIndex'] as int? ?? 0,
        totalChapters: json['totalChapters'] as int?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'chapterId': chapterId,
        'currentPage': currentPage,
        'chapterIndex': chapterIndex,
        'totalChapters': totalChapters,
      };
}

/// 进度存储（可注入后端：默认 shared_preferences，测试用内存后端）。
class ComicProgressManager {
  ComicProgressManager({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  final PrefsBackend _backend;
  final Map<String, ReadingProgress> _cache = {};

  static const String _prefix = 'comic_progress_';

  /// 读取进度（无记录返回 null）。
  Future<ReadingProgress?> get(String comicId) async {
    final cached = _cache[comicId];
    if (cached != null) return cached;
    final raw = await _backend.get('$_prefix$comicId');
    if (raw == null) return null;
    try {
      return ReadingProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  /// 保存进度（同步 lastReadChapterIndex）。
  Future<void> save(
    String comicId,
    String chapterId,
    int currentPage,
    int chapterIndex, {
    int? totalChapters,
  }) async {
    final p = ReadingProgress(
      chapterId: chapterId,
      currentPage: currentPage,
      chapterIndex: chapterIndex,
      totalChapters: totalChapters ?? _cache[comicId]?.totalChapters,
    );
    _cache[comicId] = p;
    await _backend.set(_prefix + comicId, jsonEncode(p.toJson()));
  }

  /// 清除进度（如移除书架）。
  Future<void> clear(String comicId) async {
    _cache.remove(comicId);
    await _backend.set('$_prefix$comicId', '');
  }
}
