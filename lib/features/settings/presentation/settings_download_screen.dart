/// 下载管理设置页 —— 新版设计，所有设置持久化到 SharedPreferences。
///
/// 包含：下载列表/已下载入口、最大下载数、线程数、路径、下载器类型、格式设置。
/// 项 12/13：下载器选择 / 漫画格式 / 小说格式改为弹窗选择，移除子页入口。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/download/download_format_preferences.dart';
import '../../../core/download/download_manager.dart';
import '../../../core/download/download_settings.dart';
import '../../../core/download/download_task.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../downloads/presentation/download_list_screen.dart';
import '../../downloads/presentation/downloaded_content_screen.dart';

/// 下载管理主页面。
class SettingsDownloadScreen extends StatelessWidget {
  const SettingsDownloadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.downloadManagementTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        children: <Widget>[
          // ── 下载列表 ──
          _DownloadSectionHeader(label: l10n.downloadListTab),
          AppListTile(
            leading: const Icon(Icons.download),
            title: Text(l10n.downloadListTitle),
            subtitle: Text(l10n.downloads),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DownloadListScreen(),
              ),
            ),
          ),
          AppListTile(
            leading: const Icon(Icons.download_done_outlined),
            title: Text(l10n.downloadedContent),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DownloadedContentScreen(),
              ),
            ),
          ),

          // ── 下载设置 ──
          const SizedBox(height: AppTokens.spaceXl),
          _DownloadSectionHeader(label: l10n.downloadSettingsTitle),

          // 最大同时下载数
          _MaxConcurrentSetting(),

          // 线程数
          _ThreadCountSetting(),

          // 下载路径
          _DownloadPathSetting(),

          // 下载器类型（项 12：弹窗选择）
          _DownloaderTypeSetting(),

          // 仅 WiFi 下载（需求 4：开关）
          _WifiOnlySetting(),

          // 漫画格式（项 13：弹窗选择）
          _ComicFormatSetting(),

          // 小说格式（项 13：弹窗选择）
          _NovelFormatSetting(),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// 可复用组件 —— 禁止复制粘贴重复实现
// ════════════════════════════════════════════════════════════════════════════════

class _DownloadSectionHeader extends StatelessWidget {
  final String label;
  const _DownloadSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 最大同时下载数设置项（持久化）。
class _MaxConcurrentSetting extends StatefulWidget {
  @override
  State<_MaxConcurrentSetting> createState() =>
      _MaxConcurrentSettingState();
}

class _MaxConcurrentSettingState extends State<_MaxConcurrentSetting> {
  int _value = 3;
  final DownloadSettingsStore _store = DownloadSettingsStore();

  @override
  void initState() {
    super.initState();
    _store.load().then((s) {
      if (mounted) setState(() => _value = s.maxConcurrent);
    });
  }

  Future<void> _save(int value) async {
    final current = await _store.load();
    await _store.save(current.copyWith(maxConcurrent: value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppListTile(
      leading: const Icon(Icons.sync),
      title: Text(l10n.maxConcurrentDownloads),
      subtitle: Text('$_value'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: _value > 1
                ? () {
                    setState(() => _value--);
                    _save(_value);
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: _value < 10
                ? () {
                    setState(() => _value++);
                    _save(_value);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// 线程数设置项（持久化）。
class _ThreadCountSetting extends StatefulWidget {
  @override
  State<_ThreadCountSetting> createState() => _ThreadCountSettingState();
}

class _ThreadCountSettingState extends State<_ThreadCountSetting> {
  int _value = 4;
  final DownloadSettingsStore _store = DownloadSettingsStore();

  @override
  void initState() {
    super.initState();
    _store.load().then((s) {
      if (mounted) setState(() => _value = s.threadCount);
    });
  }

  Future<void> _save(int value) async {
    final current = await _store.load();
    await _store.save(current.copyWith(threadCount: value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppListTile(
      leading: const Icon(Icons.layers),
      title: Text(l10n.threadCount),
      subtitle: Text('$_value'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: _value > 1
                ? () {
                    setState(() => _value--);
                    _save(_value);
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: _value < 16
                ? () {
                    setState(() => _value++);
                    _save(_value);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// 下载路径设置项（持久化 + 目录选择器）。
class _DownloadPathSetting extends StatefulWidget {
  @override
  State<_DownloadPathSetting> createState() => _DownloadPathSettingState();
}

class _DownloadPathSettingState extends State<_DownloadPathSetting> {
  String _path = 'D:/Downloads';
  final DownloadSettingsStore _store = DownloadSettingsStore();

  @override
  void initState() {
    super.initState();
    _store.load().then((s) {
      if (mounted) setState(() => _path = s.downloadPath);
    });
  }

  Future<void> _pickPath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      initialDirectory: _path,
    );
    if (result != null && mounted) {
      setState(() => _path = result);
      final current = await _store.load();
      await _store.save(current.copyWith(downloadPath: result));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(l10n.downloadPath),
      subtitle: Text(_path),
      trailing: const Icon(Icons.chevron_right),
      onTap: _pickPath,
    );
  }
}

/// 下载器类型设置项（项 12：弹窗选择，持久化）。
class _DownloaderTypeSetting extends StatefulWidget {
  @override
  State<_DownloaderTypeSetting> createState() =>
      _DownloaderTypeSettingState();
}

class _DownloaderTypeSettingState extends State<_DownloaderTypeSetting> {
  DownloaderType _type = DownloaderType.internal;
  final DownloadSettingsStore _store = DownloadSettingsStore();

  @override
  void initState() {
    super.initState();
    _store.load().then((s) {
      if (mounted) setState(() => _type = s.downloaderType);
    });
  }

  Future<void> _save(DownloaderType type) async {
    final current = await _store.load();
    await _store.save(current.copyWith(downloaderType: type));
  }

  String _label(AppLocalizations l10n) => switch (_type) {
        DownloaderType.internal => l10n.downloaderInternal,
        DownloaderType.external => l10n.downloaderExternal,
      };

  Future<void> _showDialog(AppLocalizations l10n) async {
    final selected = await showDialog<DownloaderType>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.downloaderSelectTitle),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, DownloaderType.internal),
            child: Row(
              children: <Widget>[
                Icon(
                  _type == DownloaderType.internal
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _type == DownloaderType.internal
                      ? Theme.of(ctx).colorScheme.primary
                      : Theme.of(ctx).colorScheme.outline,
                ),
                const SizedBox(width: AppTokens.spaceSm),
                const Icon(Icons.system_update, size: 20),
                const SizedBox(width: AppTokens.spaceXs),
                Text(l10n.downloaderInternal),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, DownloaderType.external),
            child: Row(
              children: <Widget>[
                Icon(
                  _type == DownloaderType.external
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _type == DownloaderType.external
                      ? Theme.of(ctx).colorScheme.primary
                      : Theme.of(ctx).colorScheme.outline,
                ),
                const SizedBox(width: AppTokens.spaceSm),
                const Icon(Icons.open_in_new, size: 20),
                const SizedBox(width: AppTokens.spaceXs),
                Text(l10n.downloaderExternal),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _type = selected);
    await _save(selected);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_label(l10n))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppListTile(
      leading: const Icon(Icons.cloud_download),
      title: Text(l10n.downloaderType),
      subtitle: Text(_label(l10n)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showDialog(l10n),
    );
  }
}

/// 仅 WiFi 下载开关（持久化）。
///
/// 开启后由 [DownloadManager] 在启动下载前检查网络，
/// 未连接 WiFi 时任务挂起并等待网络恢复。
class _WifiOnlySetting extends StatefulWidget {
  @override
  State<_WifiOnlySetting> createState() => _WifiOnlySettingState();
}

class _WifiOnlySettingState extends State<_WifiOnlySetting> {
  bool _value = false;
  final DownloadSettingsStore _store = DownloadSettingsStore();

  @override
  void initState() {
    super.initState();
    _store.load().then((s) {
      if (mounted) setState(() => _value = s.wifiOnly);
    });
  }

  Future<void> _save(bool value) async {
    final current = await _store.load();
    await _store.save(current.copyWith(wifiOnly: value));
    // 立即让下载管理器读取新设置，使开关即时生效。
    try {
      context.read<DownloadManager>().reloadSettings();
    } on Object {
      // 管理器缺失时忽略，下次启动会重新读取。
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppListTile(
      leading: const Icon(Icons.wifi),
      title: Text(l10n.downloadWifiOnly),
      subtitle: Text(l10n.downloadWifiOnlyHint),
      trailing: Switch(
        value: _value,
        onChanged: (v) {
          setState(() => _value = v);
          _save(v);
        },
      ),
    );
  }
}

/// 漫画格式设置项（项 13：BottomSheet 选择，持久化）。
class _ComicFormatSetting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = context.watch<DownloadManager>().formatPrefs;

    String subtitle(DownloadFormat f) => switch (f) {
          DownloadFormat.cbz => l10n.comicFormatCbz,
          DownloadFormat.jpg => l10n.comicFormatJpg,
          DownloadFormat.png => l10n.comicFormatPng,
          DownloadFormat.folder => l10n.formatFolder,
          _ => l10n.comicFormatCbz,
        };

    return AppListTile(
      leading: const Icon(Icons.auto_stories),
      title: Text(l10n.comicFormatSelectTitle),
      subtitle: Text(subtitle(prefs.comicFormat)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showSheet(context, prefs, l10n),
    );
  }

  Future<void> _showSheet(
    BuildContext context,
    DownloadFormatPreferences prefs,
    AppLocalizations l10n,
  ) async {
    final manager = context.read<DownloadManager>();
    final scheme = Theme.of(context).colorScheme;

    Widget option(DownloadFormat fmt, String label, IconData icon) {
      final selected = prefs.comicFormat == fmt;
      return ListTile(
        leading: Icon(icon, color: selected ? scheme.primary : null),
        title: Text(label,
            style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? scheme.primary : null)),
        trailing: selected
            ? Icon(Icons.check_circle, color: scheme.primary)
            : Icon(Icons.radio_button_unchecked, color: scheme.outline),
        onTap: () {
          manager.setFormatPrefs(
            prefs.copyWith(comicFormat: fmt),
          );
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(label)),
          );
        },
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              child: Text(
                l10n.comicFormatSelectTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            option(DownloadFormat.jpg, l10n.comicFormatJpg, Icons.image),
            option(DownloadFormat.png, l10n.comicFormatPng, Icons.photo),
            option(DownloadFormat.cbz, l10n.comicFormatCbz, Icons.archive),
            const SizedBox(height: AppTokens.spaceSm),
          ],
        ),
      ),
    );
  }
}

/// 小说格式设置项（项 13：BottomSheet 选择，持久化）。
class _NovelFormatSetting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = context.watch<DownloadManager>().formatPrefs;

    String subtitle(DownloadFormat f) => switch (f) {
          DownloadFormat.epub => l10n.novelFormatEpub,
          DownloadFormat.txt => l10n.novelFormatTxt,
          _ => l10n.novelFormatEpub,
        };

    return AppListTile(
      leading: const Icon(Icons.menu_book),
      title: Text(l10n.novelFormatSelectTitle),
      subtitle: Text(subtitle(prefs.novelFormat)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showSheet(context, prefs, l10n),
    );
  }

  Future<void> _showSheet(
    BuildContext context,
    DownloadFormatPreferences prefs,
    AppLocalizations l10n,
  ) async {
    final manager = context.read<DownloadManager>();
    final scheme = Theme.of(context).colorScheme;

    Widget option(DownloadFormat fmt, String label, IconData icon) {
      final selected = prefs.novelFormat == fmt;
      return ListTile(
        leading: Icon(icon, color: selected ? scheme.primary : null),
        title: Text(label,
            style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? scheme.primary : null)),
        trailing: selected
            ? Icon(Icons.check_circle, color: scheme.primary)
            : Icon(Icons.radio_button_unchecked, color: scheme.outline),
        onTap: () {
          manager.setFormatPrefs(
            prefs.copyWith(novelFormat: fmt),
          );
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(label)),
          );
        },
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              child: Text(
                l10n.novelFormatSelectTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            option(DownloadFormat.txt, l10n.novelFormatTxt, Icons.description),
            option(DownloadFormat.epub, l10n.novelFormatEpub, Icons.book),
            const SizedBox(height: AppTokens.spaceSm),
          ],
        ),
      ),
    );
  }
}
