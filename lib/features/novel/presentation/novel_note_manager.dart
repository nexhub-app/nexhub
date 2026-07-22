/// 小说笔记管理器。
///
/// 按书 + 章节保存笔记到 Hive box `novel_notes`。
/// 支持添加 / 删除 / 更新 / 按书或章节列出笔记，UI 通过 [ChangeNotifier] 驱动。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// 单条小说笔记。
class NovelNote {
  /// 笔记唯一 ID（自动生成的时间戳字符串）。
  final String id;

  /// 所属小说 ID。
  final String novelId;

  /// 章节在 chapters 列表中的索引。
  final int chapterIndex;

  /// 章节标题（展示用）。
  final String chapterTitle;

  /// 选中的文本。
  final String selectedText;

  /// 笔记内容。
  final String note;

  /// 创建时间（毫秒）。
  final int createdAt;

  const NovelNote({
    required this.id,
    required this.novelId,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.selectedText,
    required this.note,
    required this.createdAt,
  });

  /// 便捷构造：以当前时间戳自动生成 id 与 createdAt。
  factory NovelNote.create({
    required String novelId,
    required int chapterIndex,
    required String chapterTitle,
    required String selectedText,
    required String note,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return NovelNote(
      id: now.toString(),
      novelId: novelId,
      chapterIndex: chapterIndex,
      chapterTitle: chapterTitle,
      selectedText: selectedText,
      note: note,
      createdAt: now,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'novelId': novelId,
        'chapterIndex': chapterIndex,
        'chapterTitle': chapterTitle,
        'selectedText': selectedText,
        'note': note,
        'createdAt': createdAt,
      };

  factory NovelNote.fromJson(Map<String, dynamic> json) {
    return NovelNote(
      id: json['id'] as String? ?? '',
      novelId: json['novelId'] as String? ?? '',
      chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
      chapterTitle: json['chapterTitle'] as String? ?? '',
      selectedText: json['selectedText'] as String? ?? '',
      note: json['note'] as String? ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 小说笔记管理器——使用 Hive box `novel_notes`，通过 [ChangeNotifier] 驱动 UI。
class NovelNoteManager extends ChangeNotifier {
  NovelNoteManager({Box<dynamic>? box}) : _box = box;

  /// Hive box 名。
  static const String boxName = 'novel_notes';

  Box<dynamic>? _box;

  /// 打开 box（应在 splash 阶段或首次使用前调用）。
  Future<void> init() async {
    if (_box != null) return;
    if (Hive.isBoxOpen(boxName)) {
      _box = Hive.box(boxName);
      return;
    }
    _box = await Hive.openBox(boxName);
  }

  Future<Box<dynamic>> _ensureBox() async {
    if (_box != null) return _box!;
    await init();
    return _box!;
  }

  /// 添加一条笔记。
  Future<void> addNote(NovelNote note) async {
    final box = await _ensureBox();
    await box.put(note.id, jsonEncode(note.toJson()));
    notifyListeners();
  }

  /// 删除指定 ID 的笔记。
  Future<void> removeNote(String id) async {
    final box = await _ensureBox();
    await box.delete(id);
    notifyListeners();
  }

  /// 更新指定 ID 的笔记内容。
  Future<void> updateNote(String id, String newNote) async {
    final box = await _ensureBox();
    final raw = box.get(id);
    if (raw is! String || raw.isEmpty) return;
    try {
      final old = NovelNote.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      final updated = NovelNote(
        id: old.id,
        novelId: old.novelId,
        chapterIndex: old.chapterIndex,
        chapterTitle: old.chapterTitle,
        selectedText: old.selectedText,
        note: newNote,
        createdAt: old.createdAt,
      );
      await box.put(id, jsonEncode(updated.toJson()));
      notifyListeners();
    } on Object {
      // 损坏数据忽略
    }
  }

  /// 列出某本书的全部笔记（按创建时间倒序）。
  Future<List<NovelNote>> notesForNovel(String novelId) async {
    final box = await _ensureBox();
    final result = <NovelNote>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is! String || raw.isEmpty) continue;
      try {
        final n = NovelNote.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (n.novelId == novelId) result.add(n);
      } on Object {
        // 损坏数据忽略
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// 列出某本书指定章节的笔记（按创建时间倒序）。
  Future<List<NovelNote>> notesForChapter(
    String novelId,
    int chapterIndex,
  ) async {
    final all = await notesForNovel(novelId);
    return all.where((n) => n.chapterIndex == chapterIndex).toList();
  }
}
