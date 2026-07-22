/// EPUB 构建器（文档 §8.4 / §10.1）。
///
/// 构建最小合法 EPUB 2.0 结构：
/// - `mimetype`（不压缩，首条）
/// - `META-INF/container.xml`
/// - `OEBPS/content.opf`（元数据 + manifest + spine）
/// - `OEBPS/toc.ncx`（目录）
/// - `OEBPS/chapter-N.xhtml`（章节正文）
///
/// 使用 `archive` 纯 Dart 包，无平台依赖。
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

/// EPUB 章节数据。
class EpubChapter {
  final String title;
  final String content; // HTML 片段（段落列表）

  const EpubChapter({required this.title, required this.content});
}

/// EPUB 元数据。
class EpubMetadata {
  final String title;
  final String? author;
  final String? language;

  const EpubMetadata({
    required this.title,
    this.author,
    this.language = 'zh',
  });
}

/// EPUB 打包器。
class EpubBuilder {
  EpubBuilder();

  /// 构建 EPUB 字节流。
  static Uint8List build({
    required EpubMetadata metadata,
    required List<EpubChapter> chapters,
  }) {
    final archive = Archive();

    // 1. mimetype（不压缩，必须是第一条且无额外字段）
    final mimetypeData = Uint8List.fromList('application/epub+zip'.codeUnits);
    final mimetypeFile = ArchiveFile('mimetype', mimetypeData.length, mimetypeData);
    mimetypeFile.compress = false;
    archive.addFile(mimetypeFile);

    // 2. META-INF/container.xml
    final containerData = Uint8List.fromList(_containerXml().codeUnits);
    archive.addFile(ArchiveFile('META-INF/container.xml', containerData.length, containerData));

    // 3. OEBPS/content.opf
    final opfData = Uint8List.fromList(_contentOpf(metadata, chapters).codeUnits);
    archive.addFile(ArchiveFile('OEBPS/content.opf', opfData.length, opfData));

    // 4. OEBPS/toc.ncx
    final ncxData = Uint8List.fromList(_tocNcx(metadata, chapters).codeUnits);
    archive.addFile(ArchiveFile('OEBPS/toc.ncx', ncxData.length, ncxData));

    // 5. 章节正文
    for (var i = 0; i < chapters.length; i++) {
      final ch = chapters[i];
      final chData = Uint8List.fromList(_chapterXhtml(ch).codeUnits);
      archive.addFile(ArchiveFile('OEBPS/chapter-${i + 1}.xhtml', chData.length, chData));
    }

    final encoder = ZipEncoder();
    return encoder.encode(archive) as Uint8List;
  }

  /// 构建 TXT 字节流（简化格式：标题 + 段落）。
  static Uint8List buildTxt({
    required EpubMetadata metadata,
    required List<EpubChapter> chapters,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(metadata.title);
    buffer.writeln('=' * 40);
    if (metadata.author != null && metadata.author!.isNotEmpty) {
      buffer.writeln('Author: ${metadata.author}');
    }
    buffer.writeln();

    for (final ch in chapters) {
      buffer.writeln(ch.title);
      buffer.writeln('-' * 30);
      buffer.writeln(ch.content);
      buffer.writeln();
    }

    return Uint8List.fromList(buffer.toString().codeUnits);
  }

  static String _containerXml() => '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';

  static String _contentOpf(
      EpubMetadata metadata, List<EpubChapter> chapters) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
        '<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="2.0">');
    buf.writeln('  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"'
        ' xmlns:opf="http://www.idpf.org/2007/opf">');
    buf.writeln('    <dc:title>${_escape(metadata.title)}</dc:title>');
    if (metadata.author != null && metadata.author!.isNotEmpty) {
      buf.writeln(
          '    <dc:creator opf:role="aut">${_escape(metadata.author!)}</dc:creator>');
    }
    buf.writeln(
        '    <dc:language>${metadata.language ?? 'zh'}</dc:language>');
    buf.writeln('    <dc:identifier id="BookId" opf:scheme="UUID">'
        'nexhub-${DateTime.now().millisecondsSinceEpoch}</dc:identifier>');
    buf.writeln('  </metadata>');
    buf.writeln('  <manifest>');
    buf.writeln(
        '    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>');
    for (var i = 0; i < chapters.length; i++) {
      buf.writeln(
          '    <item id="ch${i + 1}" href="chapter-${i + 1}.xhtml" media-type="application/xhtml+xml"/>');
    }
    buf.writeln('  </manifest>');
    buf.writeln('  <spine toc="ncx">');
    for (var i = 0; i < chapters.length; i++) {
      buf.writeln('    <itemref idref="ch${i + 1}"/>');
    }
    buf.writeln('  </spine>');
    buf.writeln('</package>');
    return buf.toString();
  }

  static String _tocNcx(EpubMetadata metadata, List<EpubChapter> chapters) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">');
    buf.writeln('  <head>');
    buf.writeln('    <meta name="dtb:uid" content="nexhub"/>');
    buf.writeln('  </head>');
    buf.writeln('  <docTitle><text>${_escape(metadata.title)}</text></docTitle>');
    buf.writeln('  <navMap>');
    for (var i = 0; i < chapters.length; i++) {
      buf.writeln('    <navPoint id="nav${i + 1}" playOrder="${i + 1}">');
      buf.writeln(
          '      <navLabel><text>${_escape(chapters[i].title)}</text></navLabel>');
      buf.writeln('      <content src="chapter-${i + 1}.xhtml"/>');
      buf.writeln('    </navPoint>');
    }
    buf.writeln('  </navMap>');
    buf.writeln('</ncx>');
    return buf.toString();
  }

  static String _chapterXhtml(EpubChapter ch) {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>${_escape(ch.title)}</title></head>
<body>
<h1>${_escape(ch.title)}</h1>
${ch.content}
</body>
</html>''';
  }

  static String _escape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}
