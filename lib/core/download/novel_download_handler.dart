/// 小说下载处理器（文档 §8.4 / §10.1）。
///
/// 按章节拉取正文段落 → 打包 EPUB（或 TXT）。
library;

import 'dart:typed_data';

import '../models/episode.dart';
import '../models/plugin_config.dart';
import '../scraper/media_api_service.dart';
import 'download_file_system.dart';
import 'download_handler.dart';
import 'download_task.dart';
import 'epub_builder.dart';

/// 小说下载处理器。
class NovelDownloadHandler implements DownloadHandler {
  NovelDownloadHandler({
    required this.service,
    required this.fs,
    required this.source,
    required this.novelId,
    required this.chapters,
    this.format = DownloadFormat.epub,
    this.bookTitle = '',
    this.author,
    this.concurrency = 1,
  });

  final MediaApiService service;
  final DownloadFileSystem fs;
  final PluginConfig source;
  final String novelId;
  final List<Episode> chapters;
  final DownloadFormat format;
  final String bookTitle;
  final String? author;

  /// 章节并行拉取数（来自下载设置「线程数」），<=1 退化为顺序下载。
  final int concurrency;

  @override
  Future<String> download(
    DownloadTask task, {
    DownloadProgressCallback? onProgress,
  }) async {
    final epubChapters = List<EpubChapter?>.filled(chapters.length, null);
    final idxList = [for (var i = 0; i < chapters.length; i++) i];
    await runPool(concurrency, idxList, (i) async {
      final ch = chapters[i];
      final paragraphs = await service.fetchNovelContent(
        source,
        novelId: novelId,
        chapterUrl: ch.url,
      );
      final content = paragraphs
          .map((p) => '<p>${_escape(p)}</p>')
          .join('\n');
      epubChapters[i] = EpubChapter(title: ch.title, content: content);
    });

    final finalChapters = epubChapters.whereType<EpubChapter>().toList();
    onProgress?.call(chapters.length, chapters.length);

    final metadata = EpubMetadata(
      title: bookTitle.isNotEmpty ? bookTitle : task.title,
      author: author,
    );

    final String filePath;
    final Uint8List bytes;

    if (format == DownloadFormat.txt) {
      bytes = EpubBuilder.buildTxt(
        metadata: metadata,
        chapters: finalChapters,
      );
      filePath = fs.join(fs.basePath, '${task.id}.txt');
    } else {
      bytes = EpubBuilder.build(
        metadata: metadata,
        chapters: finalChapters,
      );
      filePath = fs.join(fs.basePath, '${task.id}.epub');
    }

    await fs.writeBytes(filePath, bytes);
    return filePath;
  }

  String _escape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}
