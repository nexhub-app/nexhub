/// 漫画章节书签管理器（M16.3 章节行操作）。
///
/// 镜像 [NovelBookmarkManager] 结构，按书 + 章节保存书签到 Hive box
/// `comic_bookmarks`。支持添加 / 删除 / 列出当前书的所有书签。
library;

import 'dart:convert';

import 'package:hive/hive.dart';

/// 单条漫画书签。
class ComicBookmark {
  /// 所属漫画 ID。
  final String comicId;

  /// 章节在 chapters 列表中的索引。
  final int chapterIndex;

  /// 章节 ID。
  final String chapterId;

  /// 章节标题（展示用）。
  final String chapterTitle;

  /// 创建时间（毫秒）。
  final int createdAt;

  /// 可选备注。
  final String? note;

  const ComicBookmark({
    required this.comicId,
    required this.chapterIndex,
    required this.chapterId,
    required this.chapterTitle,
    required this.createdAt,
    this.note,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'comicId': comicId,
        'chapterIndex': chapterIndex,
        'chapterId': chapterId,
        'chapterTitle': chapterTitle,
        'createdAt': createdAt,
        if (note != null) 'note': note,
      };

  factory ComicBookmark.fromJson(Map<String, dynamic> json) {
    return ComicBookmark(
      comicId: json['comicId'] as String? ?? '',
      chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
      chapterId: json['chapterId'] as String? ?? '',
      chapterTitle: json['chapterTitle'] as String? ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      note: json['note'] as String?,
    );
  }

  /// 复合 key：`comicId::chapterIndex::createdAt`，唯一标识一条书签。
  String get key => '$comicId::$chapterIndex::$createdAt';
}

/// 漫画书签管理器——使用 Hive box `comic_bookmarks`。
class ComicBookmarkManager {
  ComicBookmarkManager({Box<dynamic>? box}) : _box = box;

  /// Hive box 名。
  static const String boxName = 'comic_bookmarks';

  final Box<dynamic>? _box;

  /// 懒加载打开 box（如未在 splash 阶段预打开）。
  Future<Box<dynamic>> _openBox() async {
    if (_box != null) return _box;
    if (Hive.isBoxOpen(boxName)) return Hive.box(boxName);
    return Hive.openBox(boxName);
  }

  /// 添加一条书签，返回新建的书签。
  Future<ComicBookmark> add(ComicBookmark bookmark) async {
    final box = await _openBox();
    await box.put(bookmark.key, jsonEncode(bookmark.toJson()));
    return bookmark;
  }

  /// 删除指定书签。
  Future<void> remove(String key) async {
    final box = await _openBox();
    await box.delete(key);
  }

  /// 列出某本漫画的全部书签（按创建时间倒序）。
  Future<List<ComicBookmark>> listFor(String comicId) async {
    final box = await _openBox();
    final result = <ComicBookmark>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is! String || raw.isEmpty) continue;
      try {
        final bm = ComicBookmark.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (bm.comicId == comicId) result.add(bm);
      } on Object {
        // 损坏数据忽略
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// 判断指定章节是否有书签（按 comicId + chapterIndex）。
  Future<bool> hasBookmark(String comicId, int chapterIndex) async {
    final list = await listFor(comicId);
    return list.any((b) => b.chapterIndex == chapterIndex);
  }
}
