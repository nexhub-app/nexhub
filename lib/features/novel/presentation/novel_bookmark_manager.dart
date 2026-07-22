/// 小说书签管理器（M3.5.4）。
///
/// 按书 + 章节保存书签到 Hive box `novel_bookmarks`。
/// 支持添加 / 删除 / 跳转 / 列出当前书的所有书签。
library;

import 'dart:convert';

import 'package:hive/hive.dart';

/// 单条书签。
class NovelBookmark {
  /// 所属小说 ID。
  final String novelId;

  /// 章节在 chapters 列表中的索引。
  final int chapterIndex;

  /// 章节 ID（便于跨页恢复时定位）。
  final String chapterId;

  /// 章节标题（展示用）。
  final String chapterTitle;

  /// 书签在章节内的页码。
  final int page;

  /// 创建时间（毫秒）。
  final int createdAt;

  /// 可选备注。
  final String? note;

  const NovelBookmark({
    required this.novelId,
    required this.chapterIndex,
    required this.chapterId,
    required this.chapterTitle,
    required this.page,
    required this.createdAt,
    this.note,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'novelId': novelId,
        'chapterIndex': chapterIndex,
        'chapterId': chapterId,
        'chapterTitle': chapterTitle,
        'page': page,
        'createdAt': createdAt,
        if (note != null) 'note': note,
      };

  factory NovelBookmark.fromJson(Map<String, dynamic> json) {
    return NovelBookmark(
      novelId: json['novelId'] as String? ?? '',
      chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
      chapterId: json['chapterId'] as String? ?? '',
      chapterTitle: json['chapterTitle'] as String? ?? '',
      page: (json['page'] as num?)?.toInt() ?? 0,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      note: json['note'] as String?,
    );
  }

  /// 复合 key：`novelId::chapterIndex::createdAt`，唯一标识一条书签。
  String get key => '$novelId::$chapterIndex::$createdAt';
}

/// 书签管理器——使用 Hive box `novel_bookmarks`。
class NovelBookmarkManager {
  NovelBookmarkManager({Box<dynamic>? box}) : _box = box;

  /// Hive box 名。
  static const String boxName = 'novel_bookmarks';

  final Box<dynamic>? _box;

  /// 懒加载打开 box（如未在 splash 阶段预打开）。
  Future<Box<dynamic>> _openBox() async {
    if (_box != null) return _box;
    if (Hive.isBoxOpen(boxName)) return Hive.box(boxName);
    return Hive.openBox(boxName);
  }

  /// 添加一条书签，返回新建的书签。
  Future<NovelBookmark> add(NovelBookmark bookmark) async {
    final box = await _openBox();
    await box.put(bookmark.key, jsonEncode(bookmark.toJson()));
    return bookmark;
  }

  /// 删除指定书签。
  Future<void> remove(String key) async {
    final box = await _openBox();
    await box.delete(key);
  }

  /// 列出某本书的全部书签（按创建时间倒序）。
  Future<List<NovelBookmark>> listFor(String novelId) async {
    final box = await _openBox();
    final result = <NovelBookmark>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is! String || raw.isEmpty) continue;
      try {
        final bm = NovelBookmark.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (bm.novelId == novelId) result.add(bm);
      } on Object {
        // 损坏数据忽略
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }
}
