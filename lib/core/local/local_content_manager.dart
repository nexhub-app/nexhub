/// 本地内容管理：导入历史的持久化与本地文件的类型识别。
///
/// 供 browse_local / content_import 复用，集中「本地媒体类型」单一真源，
/// 避免各 feature 自行散布扩展名判断逻辑。
library;

import 'dart:convert';
import 'dart:io' show Directory, File, FileSystemException;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地可播放/可读的媒体类型。
enum LocalMediaKind {
  video,
  images,
  text;

  String get apiName => name;

  static LocalMediaKind? parse(String? raw) {
    if (raw == null) return null;
    for (final k in LocalMediaKind.values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

/// 按扩展名识别本地文件媒体类型（目录交给 [classifyFolderByContent]）。
///
/// 白名单覆盖 spec F2.A 并扩展示例常见格式：漫画 cbz/cbr/cbt/zip/rar、
/// 小说 txt/epub/umd/mobi/fb2/md/azw3、视频 mp4/mkv/mov/webm/avi/flv/m4v/ts/
/// wmv/mpg/mpeg/rmvb、图片 jpg/jpeg/png/webp/gif/bmp。扩展名匹配大小写不敏感。
LocalMediaKind? classifyByPath(String path) {
  final ext = p.extension(path).toLowerCase();
  if (<String>['.txt', '.epub', '.umd', '.mobi', '.fb2', '.md', '.azw3']
      .contains(ext)) {
    return LocalMediaKind.text;
  }
  if (<String>[
    '.cbz',
    '.cbr',
    '.cbt',
    '.zip',
    '.rar',
  ].contains(ext)) {
    return LocalMediaKind.images;
  }
  if (<String>[
    '.mp4',
    '.mkv',
    '.mov',
    '.webm',
    '.avi',
    '.flv',
    '.m4v',
    '.ts',
    '.wmv',
    '.mpg',
    '.mpeg',
    '.rmvb',
  ].contains(ext)) {
    return LocalMediaKind.video;
  }
  if (<String>[
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
  ].contains(ext)) {
    return LocalMediaKind.images;
  }
  return null;
}

/// 判断路径是否为 Android SAF URI（content://）。
///
/// file_picker 的 `getDirectoryPath` 在 Android 返回 SAF tree URI
/// （`content://com.android.externalstorage.documents/tree/...`），这类 URI 无法
/// 用 dart:io 的 [Directory]/[File] 直接访问（`Directory.list` 会抛
/// [FileSystemException]），需通过 ContentResolver 或专门插件读取。调用方应据此
/// 给出明确提示而非静默失败——这是「选择目录却导入不了」的深层根因。
bool isAndroidSafUri(String path) => path.startsWith('content://');

/// 递归扫描目录，按里面真实文件的多数扩展名决定 [LocalMediaKind]。
///
/// 实现 spec F2.D：不再一刀切标 images。混合目录按多数决定；空目录或全未识别
/// 返回 null。目录不可读时抛 [FileSystemException]，由调用方走 l10n 提示。
/// 注意：Android SAF URI（content://）无法用 dart:io 列举，会抛
/// [FileSystemException]；调用方应先用 [isAndroidSafUri] 拦截并给出明确提示。
LocalMediaKind? classifyFolderByContent(String dirPath) {
  if (isAndroidSafUri(dirPath)) {
    throw FileSystemException(
      'Android SAF URI cannot be listed via dart:io Directory.list',
      dirPath,
    );
  }
  final dir = Directory(dirPath);
  final counts = <LocalMediaKind, int>{};
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final kind = classifyByPath(entity.path);
    if (kind == null) continue;
    counts[kind] = (counts[kind] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.first.key;
}

bool isImageFile(String path) =>
    classifyByPath(path) == LocalMediaKind.images;

/// 计算本地内容的封面路径：取「第一张图片」作为封面（用户建议）。
///
/// - 单图文件：直接返回其路径。
/// - 图片目录：返回按名排序后的第一张松散图片。
/// - 文件夹内的 .cbz/.zip：取目录内排序第一的压缩包，解压其首图作为封面。
/// - .cbz / .zip 文件：仅解压第一张图到应用私有目录 `local_covers/` 并引用，
///   避免每次进列表都全量解压（落盘缓存）。
/// - 视频 / 文本（非 images）：无封面，返回 null。
/// 任何异常均返回 null（封面回退占位图），不阻断导入流程。
Future<String?> computeLocalCover(String path, LocalMediaKind kind) async {
  if (kind != LocalMediaKind.images) return null;
  try {
    final lower = path.toLowerCase();
    if (lower.endsWith('.cbz') || lower.endsWith('.zip')) {
      return await _extractFirstImageFromArchive(path);
    }
    final f = File(path);
    if (await f.exists()) return path; // 单图文件
    final dir = Directory(path);
    if (await dir.exists()) {
      // 优先取目录内松散图片（按名排序第一张）。
      final loose = dir
          .listSync()
          .whereType<File>()
          .where((x) => isImageFile(x.path))
          .map((x) => x.path)
          .toList()
        ..sort();
      if (loose.isNotEmpty) return loose.first;
      // 否则取目录内第一个 cbz/zip，解压其首图作为封面。
      final archives = dir
          .listSync()
          .whereType<File>()
          .where((x) {
            final l = x.path.toLowerCase();
            return l.endsWith('.cbz') || l.endsWith('.zip');
          })
          .map((x) => x.path)
          .toList()
        ..sort();
      if (archives.isNotEmpty) {
        return await _extractFirstImageFromArchive(archives.first);
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// 仅解压压缩包内排序第一张图片到 `local_covers/` 缓存目录，返回其路径。
Future<String?> _extractFirstImageFromArchive(String path) async {
  final bytes = await File(path).readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);
  final images = archive
      .where((fl) => fl.isFile && isImageFile(fl.name))
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  if (images.isEmpty) return null;
  final first = images.first;
  final content = first.content;
  if (content == null) return null;
  final dir = await getApplicationDocumentsDirectory();
  final coverDir = Directory(p.join(dir.path, 'local_covers'));
  await coverDir.create(recursive: true);
  final ext = p.extension(first.name).isEmpty ? '.jpg' : p.extension(first.name);
  final target = File(p.join(coverDir.path, '${path.hashCode}_cover$ext'));
  await target.writeAsBytes(content as List<int>);
  return target.path;
}

/// 单条本地导入记录。
class LocalContentEntry {
  final String id;
  final String title;
  final String path;
  final LocalMediaKind kind;
  final int addedAt;

  /// 封面图路径（本地文件绝对路径）。导入时取「第一张图片」并落盘缓存；
  /// 无封面（视频/文本/无图）为 null，由 UI 回退占位图。
  final String? coverUrl;

  const LocalContentEntry({
    required this.id,
    required this.title,
    required this.path,
    required this.kind,
    required this.addedAt,
    this.coverUrl,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'path': path,
        'kind': kind.apiName,
        'addedAt': addedAt,
        'coverUrl': coverUrl,
      };

  factory LocalContentEntry.fromJson(Map<String, dynamic> json) => LocalContentEntry(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        path: json['path'] as String? ?? '',
        kind: LocalMediaKind.parse(json['kind'] as String?) ?? LocalMediaKind.text,
        addedAt: json['addedAt'] as int? ?? 0,
        coverUrl: json['coverUrl'] as String?,
      );
}

/// 本地导入历史管理（SharedPreferences 持久化）。
///
/// 继承 [ChangeNotifier] 以便书架等 UI 订阅导入列表变化（R3 修复）：
/// 之前的实现由各导入页本地实例化且未调用 [init]，导致 `add` 写入时
/// `_items` 为空 → `_persist` 覆盖旧记录，重启后导入历史丢失。
/// 现统一在 splash 创建单例、注册为 Provider，导入页通过 `context.read` 复用。
class LocalContentManager extends ChangeNotifier {
  static const String _key = 'local_imports_v1';

  final List<LocalContentEntry> _items = <LocalContentEntry>[];

  /// 倒序的导入历史（最新在前）。
  List<LocalContentEntry> get items => List.unmodifiable(_items);

  /// 加载持久化数据。
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _items
        ..clear()
        ..addAll(list.map((e) => LocalContentEntry.fromJson(e as Map<String, dynamic>)));
      notifyListeners();
      // 回填历史条目的封面：早于「取第一张图当封面」逻辑导入的漫画（images 类）
      // 持久化时 coverUrl 为 null，加载后从不补算 → 书架一直显示空白/占位。
      // 这里对缺封面的图片类条目补算首图并写回，UI 端（Image.file）随即显示。
      await _backfillMissingCovers();
    } catch (_) {
      // 损坏数据忽略
    }
  }

  /// 为缺封面的图片类历史条目补算「第一张图」作为封面并持久化。
  ///
  /// 只处理 [LocalMediaKind.images] 且 `coverUrl == null` 的条目（视频/文本本就
  /// 无封面）。补算失败（如 .cbr/损坏包）静默跳过，保持 null 由 UI 回退占位。
  Future<void> _backfillMissingCovers() async {
    var dirty = false;
    for (var i = 0; i < _items.length; i++) {
      final e = _items[i];
      if (e.coverUrl != null || e.kind != LocalMediaKind.images) continue;
      final cover = await computeLocalCover(e.path, e.kind);
      if (cover == null) continue;
      _items[i] = LocalContentEntry(
        id: e.id,
        title: e.title,
        path: e.path,
        kind: e.kind,
        addedAt: e.addedAt,
        coverUrl: cover,
      );
      dirty = true;
    }
    if (dirty) {
      await _persist();
      notifyListeners();
    }
  }

  /// 新增一条导入记录（去重：相同 path 不重复添加）。
  ///
  /// 若条目未带封面，自动计算并落盘缓存封面（取第一张图片），见
  /// [computeLocalCover]。旧版本持久化记录无 `coverUrl` 字段时同样在
  /// 重新导入时补全。
  Future<void> add(LocalContentEntry entry) async {
    final existingIndex = _items.indexWhere((e) => e.path == entry.path);
    if (existingIndex >= 0) {
      // 已存在同路径：不重复添加，但若旧记录缺封面则借这次重新导入补全，
      // 兑现「重新导入时补全封面」的承诺（否则用户再导一次也修不好封面）。
      final existing = _items[existingIndex];
      if (existing.coverUrl == null &&
          existing.kind == LocalMediaKind.images) {
        final cover = await computeLocalCover(existing.path, existing.kind);
        if (cover != null) {
          _items[existingIndex] = LocalContentEntry(
            id: existing.id,
            title: existing.title,
            path: existing.path,
            kind: existing.kind,
            addedAt: existing.addedAt,
            coverUrl: cover,
          );
          await _persist();
          notifyListeners();
        }
      }
      return;
    }
    String? coverUrl = entry.coverUrl;
    if (coverUrl == null) {
      coverUrl = await computeLocalCover(entry.path, entry.kind);
    }
    final covered = LocalContentEntry(
      id: entry.id,
      title: entry.title,
      path: entry.path,
      kind: entry.kind,
      addedAt: entry.addedAt,
      coverUrl: coverUrl,
    );
    _items.insert(0, covered);
    await _persist();
    notifyListeners();
  }

  /// 移除一条记录。
  Future<void> remove(String id) async {
    _items.removeWhere((e) => e.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _items.map((e) => e.toJson()).toList();
    await prefs.setString(_key, jsonEncode(list));
  }
}
