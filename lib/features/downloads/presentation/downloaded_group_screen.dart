import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/download/download_manager.dart';
import '../../../core/download/download_task.dart';
import '../../../core/local/local_content_manager.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_cover_image.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../home/presentation/local_media_viewer.dart';

/// 已下载内容分组详情（下载页 → 点击已完成项）。
///
/// 展示封面与元信息，逐章列出并可打开本地产物。根据 [DownloadFormat]
/// 映射到 [LocalMediaKind] 复用 [LocalMediaViewer]，避免重复造轮子。
class DownloadedGroupScreen extends StatelessWidget {
  final DownloadTask task;
  const DownloadedGroupScreen({super.key, required this.task});

  LocalMediaKind _kindFor(DownloadFormat f) => switch (f) {
        DownloadFormat.cbz => LocalMediaKind.images,
        DownloadFormat.folder => LocalMediaKind.images,
        DownloadFormat.jpg => LocalMediaKind.images,
        DownloadFormat.png => LocalMediaKind.images,
        DownloadFormat.epub => LocalMediaKind.text,
        DownloadFormat.txt => LocalMediaKind.text,
        DownloadFormat.video => LocalMediaKind.video,
      };

  /// 视频格式按集命名（001.mp4 / 002.mp4 …），其他格式直接用产物路径。
  ///
  /// 回退策略（仅 video）：若构造的 `${localPath}/001.mp4` 不存在，
  /// 扫描 `localPath` 目录下首个视频文件作为回退（避免单集路径变化导致打不开）。
  String _pathForChapter(DownloadTask task, int index) {
    if (task.format == DownloadFormat.video && task.localPath != null) {
      final padded = (index + 1).toString().padLeft(3, '0');
      final expected = '${task.localPath}/$padded.mp4';
      final f = File(expected);
      if (f.existsSync()) return expected;
      // 回退：扫描目录下首个视频文件
      final fallback = _findVideoFile(task.localPath!);
      if (fallback != null) return fallback;
    }
    return task.localPath!;
  }

  /// 扫描目录下首个视频文件（按文件名排序），无则返回 null。
  String? _findVideoFile(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return null;
    const videoExts = <String>[
      '.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v', '.flv',
    ];
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) {
            final lower = f.path.toLowerCase();
            return videoExts.any((ext) => lower.endsWith(ext));
          })
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      return files.isEmpty ? null : files.first.path;
    } catch (_) {
      return null;
    }
  }

  String _pathForFirstChapter(DownloadTask task) => _pathForChapter(task, 0);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final chapters = task.chapterTitles;
    final hasFile = task.localPath != null && task.localPath!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          AppIconButton(
            icon: Icons.delete_outline,
            tooltip: l10n.delete,
            onPressed: () => _confirmDelete(context, l10n),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 110,
                    child: AppCoverImage(coverUrl: task.coverUrl, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: AppTokens.spaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(task.title, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: AppTokens.spaceSm),
                        Text(
                          '${l10n.downloadedGroupChapters}：${chapters.length}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: AppTokens.spaceXs),
                        Text(
                          '${l10n.downloadedGroupFormat}：${task.format.label}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        if (!hasFile) ...<Widget>[
                          const SizedBox(height: AppTokens.spaceXs),
                          Text(
                            l10n.downloadedGroupFileMissing,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.error,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasFile)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
                child: FilledButton.icon(
                  onPressed: () => _open(context, _pathForFirstChapter(task)),
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: Text(l10n.downloadedGroupOpen),
                ),
              ),
            ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final title = chapters[i];
                return AppListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.primary,
                    child: Text('${i + 1}'),
                  ),
                  title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: hasFile
                      ? AppIconButton(
                          icon: Icons.open_in_new_outlined,
                          tooltip: l10n.downloadedGroupOpen,
                          onPressed: () => _open(context, _pathForChapter(task, i)),
                        )
                      : null,
                );
              },
              childCount: chapters.length,
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, String path) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalMediaViewer(
          title: task.title,
          kind: _kindFor(task.format),
          uri: path,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AppLocalizations l10n) async {
    final manager = context.read<DownloadManager>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.downloadedGroupDeleteConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteRecordAndFile),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await manager.cancel(task.id, deleteFiles: true);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}
