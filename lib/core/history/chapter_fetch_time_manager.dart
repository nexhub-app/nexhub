/// 章节本地首次获取时间管理器（需求：源未提供更新时间时记录本地时间，且不再变动）。
///
/// 背景：部分源（如漫画 girigirilove / baozimh 等）不返回每章的更新时间。
/// 此时在详情页首次加载章节列表时，把"本地此刻"记为该章的获取时间并持久化，
/// 之后再次打开详情页不再刷新该时间，从而避免每次打开都变成"刚刚"。
///
/// 存储：Hive box `chapter_fetch_times`，value 为毫秒时间戳（int）。
/// key 格式：`{contentId}::{chapterId}`，跨内容互不影响。
library;

import 'package:hive/hive.dart';

class ChapterFetchTimeManager {
  ChapterFetchTimeManager({Box<dynamic>? box}) : _box = box;

  /// Hive box 名。
  static const String boxName = 'chapter_fetch_times';

  final Box<dynamic>? _box;

  Future<Box<dynamic>> _openBox() async {
    if (_box != null) return _box;
    if (Hive.isBoxOpen(boxName)) return Hive.box(boxName);
    return Hive.openBox(boxName);
  }

  static String _key(String contentId, String chapterId) =>
      '$contentId::$chapterId';

  /// 返回指定章节的本地首次获取时间（毫秒）；无记录返回 null。
  Future<int?> get(String contentId, String chapterId) async {
    final box = await _openBox();
    final v = box.get(_key(contentId, chapterId));
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// 仅当尚无记录时写入"此刻"时间戳。返回最终应显示的时间（毫秒）。
  ///
  /// 若已存在记录，直接返回旧值——保证"下次打开详情页不再更新该章时间"。
  Future<int> recordIfAbsent(
    String contentId,
    String chapterId,
    int nowMillis,
  ) async {
    final box = await _openBox();
    final key = _key(contentId, chapterId);
    final existing = box.get(key);
    if (existing is int) return existing;
    final existingStr = existing is String ? int.tryParse(existing) : null;
    if (existingStr != null) return existingStr;
    await box.put(key, nowMillis);
    return nowMillis;
  }
}
