/// 下载处理器抽象（文档 §10.1）。
///
/// 每种源类型（漫画 / 小说 / 媒体）有自己的处理器，
/// 负责拉取内容、打包、写入本地文件，并报告进度。
library;

import 'download_task.dart';

/// 处理器进度回调。
typedef DownloadProgressCallback = void Function(
    int downloadedChapters, int totalChapters);

/// 下载处理器接口。
abstract class DownloadHandler {
  /// 执行下载。
  ///
  /// [task] 任务元数据；[onProgress] 每完成一个章节/分片时调用。
  /// 返回最终产物路径。
  Future<String> download(
    DownloadTask task, {
    DownloadProgressCallback? onProgress,
  });
}

/// 有界并发池：最多 [concurrency] 个任务并行执行，全部完成后返回。
///
/// 适用于以「单元（图片 / 章节）」为粒度的并行拉取——配合按索引写入，
/// 即可在并行执行下依然保持结果有序。
Future<void> runPool<T>(
  int concurrency,
  List<T> items,
  Future<void> Function(T) task,
) async {
  if (concurrency < 1) concurrency = 1;
  if (items.isEmpty) return;
  final queue = List<T>.from(items);
  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final item = queue.removeLast();
      await task(item);
    }
  }

  final count = concurrency < items.length ? concurrency : items.length;
  final workers = <Future<void>>[for (var i = 0; i < count; i++) worker()];
  await Future.wait(workers);
}
