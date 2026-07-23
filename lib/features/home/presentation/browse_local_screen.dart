import 'dart:io' show File, FileSystemException;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/local/import_permission.dart';
import '../../../core/local/local_content_manager.dart';
import '../../../core/models/episode.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_segmented_tabs.dart';
import '../../manga/presentation/comic_reader_screen.dart';
import '../../novel/presentation/novel_reader_screen.dart';
import '../../player/presentation/video_player_screen.dart';
import 'local_media_viewer.dart';

/// 本地文件筛选维度（区别于 SourceType，语义更贴合本地媒体）。
enum _LocalFilter { all, novel, comic, video }

/// 本地文件浏览（浏览页占位功能之一）。
///
/// 通过 file_picker 选取文件 / 文件夹，按扩展名分类为小说 / 漫画 / 视频，
/// 点击进入 [LocalMediaViewer] 播放或阅读。筛选态、加载态、空态统一处理。
class BrowseLocalScreen extends StatefulWidget {
  const BrowseLocalScreen({super.key});

  @override
  State<BrowseLocalScreen> createState() => _BrowseLocalScreenState();
}

class _BrowseLocalScreenState extends State<BrowseLocalScreen> {
  final List<_LocalFile> _files = <_LocalFile>[];
  _LocalFilter _filter = _LocalFilter.all;
  bool _scanning = false;

  /// 本地文件封面缓存（路径 → 封面图绝对路径），由 [_addFile] 异步填充。
  final Map<String, String?> _covers = <String, String?>{};

  List<_LocalFile> get _filtered {
    if (_filter == _LocalFilter.all) return _files;
    final target = switch (_filter) {
      _LocalFilter.novel => LocalMediaKind.text,
      _LocalFilter.comic => LocalMediaKind.images,
      _LocalFilter.video => LocalMediaKind.video,
      _LocalFilter.all => LocalMediaKind.text,
    };
    return _files.where((f) => f.kind == target).toList();
  }

  Future<void> _pickFiles() async {
    final granted = await requestLocalImportPermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).storagePermissionDenied)),
      );
      return;
    }
    setState(() => _scanning = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result != null && mounted) {
        for (final f in result.files) {
          if (f.path == null) {
            if (!mounted) continue;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context).pickFileNoPath)),
            );
            continue;
          }
          final kind = classifyByPath(f.path!);
          if (kind == null) {
            if (!mounted) continue;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context).unrecognizedFile(f.name))),
            );
            continue;
          }
          _addFile(_LocalFile(
            path: f.path!,
            name: f.name,
            kind: kind,
          ));
        }
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).importFailed(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pickFolder() async {
    final granted = await requestLocalImportPermission();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).storagePermissionDenied)),
      );
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || !mounted) return;
    // Android SAF 返回 content:// tree URI，dart:io 无法列举，直接给出明确提示。
    if (isAndroidSafUri(dir)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).folderPickUnsupportedSaf)),
      );
      return;
    }
    setState(() => _scanning = true);
    try {
      final kind = classifyFolderByContent(dir);
      if (kind == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).emptyFolder)),
        );
        return;
      }
      _addFile(_LocalFile(
        path: dir,
        name: dir.split(RegExp(r'[/\\]')).last,
        kind: kind,
      ));
      setState(() {});
    } on FileSystemException catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).folderScanFailed)),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _addFile(_LocalFile file) {
    if (_files.any((f) => f.path == file.path)) return;
    _files.add(file);
    // 异步计算封面（取第一张图片并落盘），完成后刷新网格显示封面。
    computeLocalCover(file.path, file.kind).then((cover) {
      if (!mounted) return;
      setState(() => _covers[file.path] = cover);
    });
  }

  /// 网格单元：有封面则铺满封面图 + 底部标题，否则回退图标 + 标题。
  Widget _buildLocalTile(ColorScheme scheme, _LocalFile file) {
    final cover = _covers[file.path];
    if (cover != null) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.file(File(cover), fit: BoxFit.cover),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.all(AppTokens.spaceXs),
              child: Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(_iconFor(file.kind), size: 36, color: scheme.primary),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            file.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  IconData _iconFor(LocalMediaKind kind) => switch (kind) {
        LocalMediaKind.video => Icons.movie_outlined,
        LocalMediaKind.images => Icons.auto_stories_outlined,
        LocalMediaKind.text => Icons.menu_book_outlined,
      };

  /// 按 [file.kind] 与扩展名分流到专用阅读器或兜底 [LocalMediaViewer]（Task O4.B.4）。
  ///
  /// - 漫画 .cbz/.zip → [ComicReaderScreen]（本地模式，解压取图）
  /// - 漫画 .cbr/.rar / 单图 / 目录 → [LocalMediaViewer]（O4.A 已处理不支持提示）
  /// - 视频 → [VideoPlayerScreen]（本地模式，直接打开）
  /// - 小说 .txt → [NovelReaderScreen]（本地模式，读取文本）
  /// - 小说 .epub/.umd/.mobi/.fb2/.azw3 → [LocalMediaViewer]（O4.A 已处理不支持提示）
  void _openFile(_LocalFile file) {
    final lower = file.path.toLowerCase();
    switch (file.kind) {
      case LocalMediaKind.images:
        // 仅 .cbz/.zip 走专用阅读器（可解压）；.cbr/.rar/单图/目录走兜底。
        if (lower.endsWith('.cbz') || lower.endsWith('.zip')) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ComicReaderScreen(
                comicId: 'local_${file.path.hashCode}',
                title: file.name,
                sourceId: '',
                chapters: const <Episode>[],
                localCbzPath: file.path,
              ),
            ),
          );
          return;
        }
        _openLocalMediaViewer(file);
      case LocalMediaKind.video:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoPlayerScreen(
              title: file.name,
              episode: Episode(id: 'local', title: file.name, url: file.path),
              sourceId: '',
              itemId: 'local_${file.path.hashCode}',
              localUri: file.path,
            ),
          ),
        );
      case LocalMediaKind.text:
        // 仅 .txt 走专用阅读器；.epub/.umd/.mobi/.fb2/.azw3 走兜底（不支持）。
        if (lower.endsWith('.txt')) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => NovelReaderScreen(
                novelId: 'local_${file.path.hashCode}',
                title: file.name,
                sourceId: '',
                chapters: const <Episode>[],
                localTextPath: file.path,
              ),
            ),
          );
          return;
        }
        _openLocalMediaViewer(file);
    }
  }

  /// 兜底：打开 [LocalMediaViewer]（保持 O4.A 既有行为）。
  void _openLocalMediaViewer(_LocalFile file) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalMediaViewer(
          title: file.name,
          kind: file.kind,
          uri: file.path,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.browseLocalTitle),
        actions: <Widget>[
          AppIconButton(
            icon: Icons.folder_outlined,
            tooltip: l10n.browseLocalSelectFolder,
            onPressed: _pickFolder,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning ? null : _pickFiles,
        icon: _scanning
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.file_open_outlined),
        label: Text(l10n.browseLocalScan),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: AppSegmentedTabs<_LocalFilter>(
              selected: <_LocalFilter>{_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
              segments: <ButtonSegment<_LocalFilter>>[
                ButtonSegment<_LocalFilter>(value: _LocalFilter.all, label: Text(l10n.browseLocalFileTypeAll)),
                ButtonSegment<_LocalFilter>(value: _LocalFilter.novel, label: Text(l10n.browseLocalFileTypeNovel)),
                ButtonSegment<_LocalFilter>(value: _LocalFilter.comic, label: Text(l10n.browseLocalFileTypeComic)),
                ButtonSegment<_LocalFilter>(value: _LocalFilter.video, label: Text(l10n.browseLocalFileTypeVideo)),
              ],
            ),
          ),
          Expanded(
            child: _files.isEmpty
                ? AppEmptyState(icon: Icons.folder_open_outlined, message: l10n.browseLocalEmpty)
                : GridView.builder(
                    padding: const EdgeInsets.all(AppTokens.spaceLg),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: AppTokens.spaceMd,
                      crossAxisSpacing: AppTokens.spaceMd,
                      mainAxisExtent: 120,
                    ),
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) {
                      final file = _filtered[i];
                      return Card(
                        elevation: 0,
                        color: scheme.surfaceContainerHighest,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _openFile(file),
                          child: _buildLocalTile(scheme, file),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LocalFile {
  final String path;
  final String name;
  final LocalMediaKind kind;
  const _LocalFile({required this.path, required this.name, required this.kind});
}
