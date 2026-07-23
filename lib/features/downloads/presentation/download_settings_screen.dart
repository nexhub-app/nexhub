/// 下载格式设置页（文档 §10.1 / §12）。
///
/// 漫画格式：CBZ（打包）/ 散图文件夹
/// 小说格式：EPUB / TXT
library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/download/download_manager.dart';
import '../../../core/download/download_task.dart';
import '../../../core/theme/app_tokens.dart';

/// 下载格式设置页。
class DownloadSettingsScreen extends StatelessWidget {
  const DownloadSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final manager = context.watch<DownloadManager>();
    final prefs = manager.formatPrefs;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.downloadSettings)),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        children: <Widget>[
          // ── 漫画格式 ──
          _SectionHeader(
            icon: Icons.auto_stories,
            title: l10n.comicDownloadFormat,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _FormatOption(
            label: l10n.formatCbz,
            subtitle: l10n.formatCbzSubtitle,
            selected: prefs.comicFormat == DownloadFormat.cbz,
            onTap: () => manager.setFormatPrefs(
              prefs.copyWith(comicFormat: DownloadFormat.cbz),
            ),
          ),
          _FormatOption(
            label: l10n.formatFolder,
            subtitle: l10n.formatFolderSubtitle,
            selected: prefs.comicFormat == DownloadFormat.folder,
            onTap: () => manager.setFormatPrefs(
              prefs.copyWith(comicFormat: DownloadFormat.folder),
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),

          // ── 小说格式 ──
          _SectionHeader(
            icon: Icons.menu_book,
            title: l10n.novelDownloadFormat,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _FormatOption(
            label: l10n.formatEpub,
            subtitle: l10n.formatEpubSubtitle,
            selected: prefs.novelFormat == DownloadFormat.epub,
            onTap: () => manager.setFormatPrefs(
              prefs.copyWith(novelFormat: DownloadFormat.epub),
            ),
          ),
          _FormatOption(
            label: l10n.formatTxt,
            subtitle: l10n.formatTxtSubtitle,
            selected: prefs.novelFormat == DownloadFormat.txt,
            onTap: () => manager.setFormatPrefs(
              prefs.copyWith(novelFormat: DownloadFormat.txt),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: AppTokens.spaceSm),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.primary,
              ),
        ),
      ],
    );
  }
}

class _FormatOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _FormatOption({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primaryContainer : null,
      child: ListTile(
        onTap: onTap,
        title: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: selected
            ? Icon(Icons.check_circle, color: scheme.primary)
            : Icon(Icons.radio_button_unchecked,
                color: scheme.outline),
      ),
    );
  }
}
