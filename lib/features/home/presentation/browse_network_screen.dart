import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/download/download_settings.dart';
import '../../../core/local/local_content_manager.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../../../core/scraper/verification_detector.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/html_utils.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/app_url_input_bar.dart';
import '../../../features/verification/presentation/webview_verification_screen.dart';
import 'local_media_viewer.dart';

/// 网络文件浏览（浏览页占位功能之一）。
///
/// 输入 HTTP 文件服务器地址，解析目录页 `<a>` 链接，支持进入子目录、返回上级、
/// 按扩展名打开视频 / 图片，其余类型在外部浏览器打开。长按文件进入多选模式，
/// 可批量下载到本地下载目录。
class BrowseNetworkScreen extends StatefulWidget {
  const BrowseNetworkScreen({super.key});

  @override
  State<BrowseNetworkScreen> createState() => _BrowseNetworkScreenState();
}

class _NetEntry {
  final String name;
  final String url;
  final bool isDir;
  final LocalMediaKind? kind;
  const _NetEntry({required this.name, required this.url, required this.isDir, this.kind});
}

class _BrowseNetworkScreenState extends State<BrowseNetworkScreen> {
  final TextEditingController _urlCtl = TextEditingController();
  String _currentUrl = '';
  List<_NetEntry> _entries = const <_NetEntry>[];
  final List<String> _history = <String>[];
  bool _loading = false;
  String? _error;

  // 多选模式状态
  bool _selectionMode = false;
  final Set<int> _selectedIndices = <int>{};

  // 下载状态
  final Set<String> _downloadingUrls = <String>{};
  final Set<String> _downloadedUrls = <String>{};

  @override
  void dispose() {
    _urlCtl.dispose();
    super.dispose();
  }

  Uri get _uri => Uri.parse(_currentUrl);

  List<String> get _pathSegs =>
      _uri.path.split('/').where((s) => s.isNotEmpty).toList();

  Future<void> _connect(String rawUrl) async {
    var url = rawUrl.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
    if (!url.endsWith('/')) url = '$url/';
    if (!_history.contains(url)) _history.insert(0, url);
    await _load(url);
  }

  Future<void> _load(String url) async {
    setState(() {
      _currentUrl = url;
      _loading = true;
      _error = null;
    });
    try {
      final html = await HttpFetcher.instance.getHtml(url);
      final entries = _parse(html, url);
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } on VerificationRequiredException catch (e) {
      if (!mounted) return;
      final ok = await navigateToVerification(context, url: url, exception: e);
      if (ok && mounted) {
        _load(url);
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<_NetEntry> _parse(String html, String baseUrl) {
    final base = Uri.parse(baseUrl);
    final list = <_NetEntry>[];
    for (final a in HtmlUtils.elements(html, 'a')) {
      final href = a.attributes['href'];
      if (href == null || href == '../' || href == './') continue;
      final abs = base.resolve(href).toString();
      final name = a.text.trim();
      final isDir = href.endsWith('/') || !href.contains('.');
      list.add(_NetEntry(
        name: name.isEmpty ? abs : name,
        url: abs,
        isDir: isDir,
        kind: isDir ? null : classifyByPath(abs),
      ));
    }
    list.sort((x, y) {
      if (x.isDir != y.isDir) return x.isDir ? -1 : 1;
      return x.name.toLowerCase().compareTo(y.name.toLowerCase());
    });
    return list;
  }

  void _enterDir(_NetEntry dir) {
    final url = dir.url.endsWith('/') ? dir.url : '${dir.url}/';
    _load(url);
  }

  void _goUp() {
    final segs = _pathSegs;
    if (segs.isEmpty) return;
    _load(_urlUpTo(segs.length - 1));
  }

  String _urlUpTo(int k) {
    final segs = _pathSegs.take(k).join('/');
    return '${_uri.scheme}://${_uri.authority}/$segs/';
  }

  void _tapSegment(int k) => _load(_urlUpTo(k));

  Future<void> _openFile(_NetEntry e) async {
    if (e.kind == null || e.kind == LocalMediaKind.text) {
      await _launch(e.url);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalMediaViewer(
          title: e.name,
          kind: e.kind!,
          uri: e.url,
          gallery: e.kind == LocalMediaKind.images ? <String>[e.url] : null,
        ),
      ),
    );
  }

  Future<void> _launch(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).loadFailed)),
        );
      }
    }
  }

  IconData _iconFor(_NetEntry e) {
    if (e.isDir) return Icons.folder_outlined;
    return switch (e.kind) {
      LocalMediaKind.video => Icons.movie_outlined,
      LocalMediaKind.images => Icons.image_outlined,
      LocalMediaKind.text => Icons.description_outlined,
      null => Icons.insert_drive_file_outlined,
    };
  }

  // ── 多选模式 ──

  void _enterSelection(int i) {
    setState(() {
      _selectionMode = true;
      _selectedIndices
        ..clear()
        ..add(i);
    });
  }

  void _toggleSelection(int i) {
    setState(() {
      if (_selectedIndices.contains(i)) {
        _selectedIndices.remove(i);
        if (_selectedIndices.isEmpty) _selectionMode = false;
      } else {
        _selectedIndices.add(i);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIndices.clear();
    });
  }

  void _selectAllFiles() {
    setState(() {
      _selectedIndices
        ..clear()
        ..addAll(List<int>.generate(_entries.length, (i) => i)
            .where((i) => !_entries[i].isDir));
    });
  }

  /// 打开第一个选中的文件（多选时只打开一个，避免一次性弹多个页面）。
  Future<void> _openSelected() async {
    if (_selectedIndices.isEmpty) return;
    final firstIndex = _selectedIndices.reduce((a, b) => a < b ? a : b);
    final e = _entries[firstIndex];
    await _openFile(e);
  }

  /// 下载所有选中的文件到本地下载目录。
  ///
  /// 使用 Dio 流式下载；进度通过 SnackBar 反馈；下载目录来自 [DownloadSettingsStore]。
  Future<void> _downloadSelected() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final selected = _selectedIndices
        .map((i) => _entries[i])
        .where((e) => !e.isDir)
        .toList();
    if (selected.isEmpty) return;

    final settings = await DownloadSettingsStore().load();
    final basePath = settings.downloadPath;
    final baseDir = Directory(basePath);
    if (!baseDir.existsSync()) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.browseNetworkDownloadPathMissing)),
      );
      return;
    }

    setState(() {
      for (final e in selected) {
        _downloadingUrls.add(e.url);
      }
    });

    messenger.showSnackBar(
      SnackBar(content: Text(l10n.browseNetworkDownloadStarted(selected.length))),
    );

    final dio = Dio();
    int successCount = 0;
    for (final e in selected) {
      try {
        final savePath = p.join(basePath, e.name);
        await dio.download(e.url, savePath);
        successCount++;
        if (mounted) {
          setState(() {
            _downloadingUrls.remove(e.url);
            _downloadedUrls.add(e.url);
          });
        }
      } on Object {
        if (mounted) {
          setState(() => _downloadingUrls.remove(e.url));
        }
      }
    }

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: successCount > 0
            ? Text(l10n.browseNetworkDownloadDone(successCount))
            : Text(l10n.browseNetworkDownloadFailed),
      ),
    );
    if (successCount > 0) _exitSelection();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectionMode
            ? l10n.browseNetworkSelectedCount(_selectedIndices.length)
            : l10n.browseNetworkTitle),
        actions: <Widget>[
          if (_selectionMode) ...<Widget>[
            AppIconButton(
              icon: Icons.select_all_outlined,
              tooltip: l10n.selectAll,
              onPressed: _selectAllFiles,
            ),
            AppIconButton(
              icon: Icons.close,
              tooltip: l10n.cancel,
              onPressed: _exitSelection,
            ),
          ],
        ],
      ),
      body: Column(
        children: <Widget>[
          if (!_selectionMode) ...<Widget>[
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              child: AppUrlInputBar(
                controller: _urlCtl,
                hintText: l10n.browseNetworkUrlHint,
                isLoading: _loading,
                submitLabel: l10n.browseNetworkConnect,
                onSubmit: _connect,
              ),
            ),
            if (_currentUrl.isNotEmpty) _buildBreadcrumb(l10n),
            if (_currentUrl.isEmpty && _history.isNotEmpty) _buildHistory(l10n),
          ],
          Expanded(child: _buildBody(l10n)),
        ],
      ),
      // 多选模式底部菜单（打开 + 下载）
      bottomNavigationBar: _selectionMode
          ? BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: _selectedIndices.isEmpty ? null : _openSelected,
                    icon: const Icon(Icons.open_in_new),
                    label: Text(l10n.browseNetworkOpenSelected),
                  ),
                  TextButton.icon(
                    onPressed: _selectedIndices.isEmpty ? null : _downloadSelected,
                    icon: const Icon(Icons.download_outlined),
                    label: Text(l10n.browseNetworkDownloadSelected),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildBreadcrumb(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
      child: Row(
        children: <Widget>[
          AppIconButton(
            icon: Icons.arrow_upward,
            tooltip: l10n.browseNetworkParentDir,
            onPressed: _goUp,
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  _crumbChip(l10n, _uri.authority, 0),
                  for (int i = 0; i < _pathSegs.length; i++)
                    _crumbChip(l10n, _pathSegs[i], i + 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _crumbChip(AppLocalizations l10n, String label, int index) => InkWell(
        onTap: () => _tapSegment(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceXs),
          child: Chip(label: Text(label)),
        ),
      );

  Widget _buildHistory(AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.browseNetworkHistory, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              spacing: AppTokens.spaceSm,
              children: _history
                  .map((u) => ActionChip(
                        label: Text(u),
                        onPressed: () => _connect(u),
                      ))
                  .toList(),
            ),
          ],
        ),
      );

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return AppErrorState(
        message: l10n.loadFailed,
        onRetry: () => _load(_currentUrl),
        retryLabel: l10n.retry,
      );
    }
    if (_currentUrl.isEmpty) {
      return AppEmptyState(icon: Icons.cloud_outlined, message: l10n.browseNetworkUrlHint);
    }
    if (_entries.isEmpty) {
      return AppEmptyState(icon: Icons.folder_open_outlined, message: l10n.browseNetworkEmpty);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final e = _entries[i];
        final isSelected = _selectedIndices.contains(i);
        final isDownloading = _downloadingUrls.contains(e.url);
        final isDownloaded = _downloadedUrls.contains(e.url);

        // 多选模式：点击切换选中，trailing 为 Checkbox（目录禁用）
        if (_selectionMode) {
          return AppListTile(
            leading: Icon(_iconFor(e)),
            title: Text(e.name),
            trailing: e.isDir
                ? const Icon(Icons.folder_outlined, color: Colors.transparent)
                : Checkbox(
                    value: isSelected,
                    onChanged: (v) => _toggleSelection(i),
                  ),
            selected: isSelected,
            onTap: e.isDir ? null : () => _toggleSelection(i),
          );
        }

        // 普通模式：长按进入多选；点击进入目录或打开文件
        Widget? trailing;
        if (e.isDir) {
          trailing = const Icon(Icons.chevron_right);
        } else if (isDownloading) {
          trailing = const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        } else if (isDownloaded) {
          trailing = Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 20);
        }

        return AppListTile(
          leading: Icon(_iconFor(e)),
          title: Text(e.name),
          trailing: trailing,
          onTap: () => e.isDir ? _enterDir(e) : _openFile(e),
          onLongPress: e.isDir ? null : () => _enterSelection(i),
        );
      },
    );
  }
}
