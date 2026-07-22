/// 漫画下载处理器（文档 §7.5 / §10.1）。
///
/// 按章节拉取图片 URL → 下载图片字节 → 打包 CBZ（或散图文件夹）。
library;

import 'dart:typed_data';

import '../models/episode.dart';
import '../models/plugin_config.dart';
import '../scraper/http_fetcher.dart';
import '../scraper/media_api_service.dart';
import 'cbz_builder.dart';
import 'download_file_system.dart';
import 'download_handler.dart';
import 'download_task.dart';

/// 漫画下载处理器。
class ComicDownloadHandler implements DownloadHandler {
  ComicDownloadHandler({
    required this.service,
    required this.fs,
    required this.source,
    required this.comicId,
    required this.chapters,
    this.format = DownloadFormat.cbz,
    this.concurrency = 1,
  });

  final MediaApiService service;
  final DownloadFileSystem fs;
  final PluginConfig source;
  final String comicId;
  final List<Episode> chapters;
  final DownloadFormat format;

  /// 章内图片并行下载数（来自下载设置「线程数」），<=1 退化为顺序下载。
  final int concurrency;

  @override
  Future<String> download(
    DownloadTask task, {
    DownloadProgressCallback? onProgress,
  }) async {
    final basePath = fs.join(fs.basePath, task.id);
    await fs.createDir(basePath);

    // 单页散图模式（folder / jpg / png）：每章一个子文件夹，章内图片按线程数并行下载。
    if (format == DownloadFormat.folder ||
        format == DownloadFormat.jpg ||
        format == DownloadFormat.png) {
      final ext = format == DownloadFormat.png ? 'png' : 'jpg';
      for (var i = 0; i < chapters.length; i++) {
        final ch = chapters[i];
        final chDir = fs.join(basePath, _sanitize(ch.title, i));
        await fs.createDir(chDir);
        final images = await service.fetchImages(
          source,
          comicId: comicId,
          chapterId: ch.id,
        );
        final idxList = [for (var j = 0; j < images.length; j++) j];
        await runPool(concurrency, idxList, (j) async {
          final bytes = await _fetchImageBytes(images[j]);
          if (bytes != null) {
            await fs.writeBytes(
              fs.join(chDir, '${_pad(j + 1)}.$ext'),
              bytes,
            );
          }
        });
        onProgress?.call(i + 1, chapters.length);
      }
      return basePath;
    }

    // CBZ 模式：所有章节图片打包为单个 .cbz，章内图片按线程数并行下载。
    final allPages = <CbzPage>[];
    for (var i = 0; i < chapters.length; i++) {
      final ch = chapters[i];
      final images = await service.fetchImages(
        source,
        comicId: comicId,
        chapterId: ch.id,
      );
      final pageBytes = List<Uint8List?>.filled(images.length, null);
      final idxList = [for (var j = 0; j < images.length; j++) j];
      await runPool(concurrency, idxList, (j) async {
        pageBytes[j] = await _fetchImageBytes(images[j]);
      });
      for (var j = 0; j < pageBytes.length; j++) {
        final bytes = pageBytes[j];
        if (bytes != null) {
          allPages.add(CbzPage(
            filename: '${_pad(allPages.length + 1)}.jpg',
            bytes: bytes,
          ));
        }
      }
      onProgress?.call(i + 1, chapters.length);
    }

    final cbzBytes = CbzBuilder.build(pages: allPages);
    final cbzPath = fs.join(fs.basePath, '${task.id}.cbz');
    await fs.writeBytes(cbzPath, cbzBytes);

    // 清理临时目录
    await fs.delete(basePath);

    return cbzPath;
  }

  Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      final bytes = await HttpFetcher.instance.getBytes(url);
      return bytes.isEmpty ? null : Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  static String _sanitize(String s, int fallback) {
    final clean = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return clean.isEmpty ? 'chapter_${fallback + 1}' : clean;
  }

  static String _pad(int n, [int width = 4]) =>
      n.toString().padLeft(width, '0');
}
