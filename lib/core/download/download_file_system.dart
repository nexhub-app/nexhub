/// 下载文件系统抽象（文档 §10.1 / §10.3）。
///
/// 将平台文件操作抽象为接口，便于测试注入内存实现。
/// 生产环境使用 [PathProviderFileSystem]；测试使用 [InMemoryFileSystem]。
library;

import 'dart:io';
import 'dart:typed_data';

/// 文件系统后端接口。
abstract class DownloadFileSystem {
  /// 获取下载基路径。
  String get basePath;

  /// 写入文件（字节），自动创建父目录。
  Future<void> writeBytes(String path, Uint8List bytes);

  /// 写入文件（文本），自动创建父目录。
  Future<void> writeString(String path, String content);

  /// 读取文件字节。
  Future<Uint8List> readBytes(String path);

  /// 读取文件文本。
  Future<String> readString(String path);

  /// 文件是否存在。
  Future<bool> exists(String path);

  /// 删除文件或目录（递归）。
  Future<void> delete(String path);

  /// 列出目录下的文件名（不含路径前缀）。
  Future<List<String>> listFiles(String dirPath);

  /// 创建目录（递归）。
  Future<void> createDir(String path);

  /// 拼接路径。
  String join(String a, String b);
}

/// 基于 path_provider + dart:io 的生产实现。
class PathProviderFileSystem implements DownloadFileSystem {
  PathProviderFileSystem(this._basePath);

  final String _basePath;

  @override
  String get basePath => _basePath;

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> writeString(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<Uint8List> readBytes(String path) async =>
      await File(path).readAsBytes();

  @override
  Future<String> readString(String path) async =>
      await File(path).readAsString();

  @override
  Future<bool> exists(String path) async => File(path).existsSync();

  @override
  Future<void> delete(String path) async {
    final f = File(path);
    if (await f.exists()) {
      await f.delete();
      return;
    }
    final d = Directory(path);
    if (d.existsSync()) {
      await d.delete(recursive: true);
    }
  }

  @override
  Future<List<String>> listFiles(String dirPath) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return <String>[];
    final entries = <String>[];
    await for (final e in dir.list()) {
      entries.add(e.uri.pathSegments.last);
    }
    return entries;
  }

  @override
  Future<void> createDir(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  String join(String a, String b) => '$a${Platform.pathSeparator}$b';
}

/// 内存文件系统（测试用）。
class InMemoryFileSystem implements DownloadFileSystem {
  InMemoryFileSystem({this.basePath = '/tmp/downloads'});

  @override
  final String basePath;

  final Map<String, Uint8List> _files = {};

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    _files[path] = bytes;
  }

  @override
  Future<void> writeString(String path, String content) async {
    _files[path] = Uint8List.fromList(content.codeUnits);
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    final f = _files[path];
    if (f == null) throw FileSystemException('Not found', path);
    return f;
  }

  @override
  Future<String> readString(String path) async {
    final f = _files[path];
    if (f == null) throw FileSystemException('Not found', path);
    return String.fromCharCodes(f);
  }

  @override
  Future<bool> exists(String path) async => _files.containsKey(path);

  @override
  Future<void> delete(String path) async {
    _files.remove(path);
    // Also remove any files under this path prefix (directory simulation)
    final prefix = '$path/';
    _files.removeWhere((key, _) => key.startsWith(prefix));
  }

  @override
  Future<List<String>> listFiles(String dirPath) async {
    final prefix = dirPath.endsWith('/') ? dirPath : '$dirPath/';
    final result = <String>[];
    for (final key in _files.keys) {
      if (key.startsWith(prefix)) {
        final rel = key.substring(prefix.length);
        // Only direct children (no further separators)
        if (!rel.contains('/')) {
          result.add(rel);
        }
      }
    }
    return result;
  }

  @override
  Future<void> createDir(String path) async {
    // No-op for in-memory
  }

  @override
  String join(String a, String b) => '$a/$b';

  /// 直接检查文件是否存在（同步，测试辅助）。
  bool hasFile(String path) => _files.containsKey(path);

  /// 获取文件内容（同步，测试辅助）。
  Uint8List? getFile(String path) => _files[path];
}
