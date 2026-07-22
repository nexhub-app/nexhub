/// CBZ 构建器（文档 §7.5 / §10.1）。
///
/// CBZ 本质上是 ZIP 归档，内含按顺序命名的图片（0001.jpg, 0002.jpg, …）。
/// 使用 `archive` 纯 Dart 包，无平台依赖，可在测试中直接调用。
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 单页图片数据（文件名 + 字节内容）。
class CbzPage {
  final String filename;
  final Uint8List bytes;

  const CbzPage({required this.filename, required this.bytes});
}

/// CBZ 打包器。
class CbzBuilder {
  CbzBuilder();

  /// 将图片列表打包为 CBZ (ZIP) 字节流。
  ///
  /// 图片按列表顺序写入，文件名统一补零为 4 位（0001.jpg, 0002.jpg, …）。
  /// 如果 [pages] 中的 filename 已提供则直接使用。
  static Uint8List build({
    required List<CbzPage> pages,
    String fileExtension = 'jpg',
  }) {
    final archive = Archive();

    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final name = page.filename.isNotEmpty
          ? page.filename
          : '${_pad(i + 1)}.$fileExtension';
      archive.addFile(
        ArchiveFile(name, page.bytes.length, page.bytes),
      );
    }

    final encoder = ZipEncoder();
    return encoder.encode(archive) as Uint8List;
  }

  static String _pad(int n, [int width = 4]) =>
      n.toString().padLeft(width, '0');
}
