/// 媒体（视频）下载处理器（文档 §9 / §10.1）。
///
/// 按剧集拉取视频直链 → 下载字节 → 保存为按集命名的 .mp4 文件。
/// 仅支持直链视频（mp4/mkv 等），HLS(m3u8)/DASH(mpd) 流跳过该集。
library;

import 'dart:typed_data';

import '../models/episode.dart';
import '../models/plugin_config.dart';
import '../scraper/http_fetcher.dart';
import '../scraper/media_api_service.dart';
import 'download_file_system.dart';
import 'download_handler.dart';
import 'download_task.dart';

/// 媒体（视频）下载处理器。
class MediaDownloadHandler implements DownloadHandler {
  MediaDownloadHandler({
    required this.service,
    required this.fs,
    required this.source,
    required this.contentId,
    required this.chapters,
    this.concurrency = 1,
  });

  final MediaApiService service;
  final DownloadFileSystem fs;
  final PluginConfig source;
  final String contentId;
  final List<Episode> chapters;

  /// 章节并行拉取数（来自下载设置「线程数」），<=1 退化为顺序下载。
  final int concurrency;

  @override
  Future<String> download(
    DownloadTask task, {
    DownloadProgressCallback? onProgress,
  }) async {
    final taskDir = fs.join(fs.basePath, task.id);
    await fs.createDir(taskDir);

    var completed = 0;
    final idxList = [for (var i = 0; i < chapters.length; i++) i];
    await runPool(concurrency, idxList, (i) async {
      final ch = chapters[i];
      final video = await service.fetchVideoUrl(source, ch.url);

      // HLS / DASH 流无法作为单文件下载，跳过该集（不报错，继续下一集）。
      if (_isHlsOrDash(video.url, video.type)) {
        completed++;
        onProgress?.call(completed, chapters.length);
        return;
      }

      // 非直链视频无法直接下载，跳过该集。
      if (!_isDirectVideo(video.url, video.type)) {
        completed++;
        onProgress?.call(completed, chapters.length);
        return;
      }

      final bytes = await _fetchVideoBytes(video.url);
      if (bytes != null) {
        await fs.writeBytes(
          fs.join(taskDir, '${_pad(i + 1)}.mp4'),
          bytes,
        );
      }
      completed++;
      onProgress?.call(completed, chapters.length);
    });

    return taskDir;
  }

  Future<Uint8List?> _fetchVideoBytes(String url) async {
    try {
      final bytes = await HttpFetcher.instance.getBytes(url);
      return bytes.isEmpty ? null : Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  /// 判断是否为直链视频（mp4/mkv/avi 等扩展名或 type=mp4）。
  bool _isDirectVideo(String url, String? type) {
    final lower = url.toLowerCase();
    const directExts = ['.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.ts'];
    if (directExts.any((e) => lower.contains(e))) return true;
    if (type == null) return true; // 无 type 默认尝试下载
    final t = type.toLowerCase();
    return t == 'mp4' || t == 'video' || t == 'direct';
  }

  /// 判断是否为 HLS(m3u8) / DASH(mpd) 流。
  bool _isHlsOrDash(String url, String? type) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') || lower.contains('.mpd')) return true;
    final t = type?.toLowerCase();
    return t == 'm3u8' || t == 'hls' || t == 'dash' || t == 'mpd';
  }

  static String _pad(int n, [int width = 3]) =>
      n.toString().padLeft(width, '0');
}
