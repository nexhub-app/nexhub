/// 设置页面 —— 新版分组列表样式。
///
/// 分组：
/// - 下载管理
/// - 工具（网页爬取 / 订阅管理 / RSSHub Instance / 弹弹play 弹幕）
/// - 插件
/// - 数据（导入/导出）
library;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../../../core/locale/locale_controller.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/app_segmented_tabs.dart';
import '../../../core/widgets/layout_picker_dialog.dart';
import '../../home/presentation/browse_web_scrape_screen.dart';
import '../../sources/presentation/source_manager_screen.dart';
import './settings_download_screen.dart';
import './settings_rsshub_screen.dart';
import './settings_rss_notifications_screen.dart';
import './settings_danmaku_screen.dart';
import './settings_danmaku_display_screen.dart';
import './settings_player_screen.dart';
import './settings_novel_reader_screen.dart';
import './settings_comic_reader_screen.dart';
import './settings_import_export_screen.dart';
import './settings_cloud_sync_screen.dart';
import './about_screen.dart';
import '../../../core/settings/general_settings.dart';
import './widgets/settings_widgets.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/services/cloud_sync_service.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:intl/intl.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _openColorPicker(
      BuildContext context, ThemeController c, AppLocalizations l10n) {
    Color pickerColor = c.seed;
    showDialog(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(l10n.customColor),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (Color color) => pickerColor = color,
            enableAlpha: false,
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          OutlinedButton(
            onPressed: () {
              c.setSeed(AppTokens.seedYouthfulPrimary);
              Navigator.pop(ctx);
            },
            child: Text(l10n.restoreDefault),
          ),
          FilledButton(
            onPressed: () {
              c.setSeed(pickerColor);
              Navigator.pop(ctx);
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<void> _enableRecommended(
      BuildContext context, AppLocalizations l10n) async {
    final count =
        await context.read<SourceRepository>().enableRecommendedSources();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.recommendedSourcesEnabled(count))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeController controller = context.watch<ThemeController>();
    final LocaleController localeController = context.watch<LocaleController>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        children: <Widget>[
          // ── 外观 ──
          _SettingsGroupHeader(label: l10n.themeTitle),
          AppSegmentedTabs<ThemeMode>(
            selected: <ThemeMode>{controller.mode},
            onSelectionChanged: (Set<ThemeMode> s) =>
                controller.setMode(s.first),
            segments: <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(
                  value: ThemeMode.light, label: Text(l10n.themeLight),
                  icon: const Icon(Icons.light_mode)),
              ButtonSegment<ThemeMode>(
                  value: ThemeMode.dark, label: Text(l10n.themeDark),
                  icon: const Icon(Icons.dark_mode)),
              ButtonSegment<ThemeMode>(
                  value: ThemeMode.system, label: Text(l10n.themeSystem),
                  icon: const Icon(Icons.brightness_auto)),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          AppListTile(
            leading: const Icon(Icons.auto_awesome),
            title: Text(l10n.useMonet),
            trailing: Switch(
              value: controller.useMonet,
              onChanged: (_) => controller.setUseMonet(!controller.useMonet),
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          _SettingsGroupHeader(label: l10n.presetColor),
          Wrap(
            spacing: AppTokens.spaceSm,
            children: AppTokens.presetSeeds.map((Color color) {
              final bool selected =
                  !controller.useMonet && controller.seed == color;
              return ChoiceChip(
                label: const SizedBox.shrink(),
                avatar:
                    CircleAvatar(backgroundColor: color, radius: 12),
                selected: selected,
                onSelected: (_) => controller.setSeed(color),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          AppListTile(
            leading: const Icon(Icons.color_lens),
            title: Text(l10n.customColor),
            trailing:
                CircleAvatar(backgroundColor: controller.seed, radius: 14),
            onTap: () => _openColorPicker(context, controller, l10n),
          ),

          // ── 语言 ──
          const SizedBox(height: AppTokens.spaceXl),
          _SettingsGroupHeader(label: l10n.settingsGroupLanguage),
          AppSegmentedTabs<LocaleOption>(
            selected: <LocaleOption>{localeController.option},
            onSelectionChanged: (Set<LocaleOption> s) =>
                localeController.setOption(s.first),
            segments: <ButtonSegment<LocaleOption>>[
              ButtonSegment<LocaleOption>(
                  value: LocaleOption.system,
                  label: Text(l10n.languageFollowSystem),
                  icon: const Icon(Icons.brightness_auto)),
              ButtonSegment<LocaleOption>(
                  value: LocaleOption.chinese,
                  label: Text(l10n.languageChinese),
                  icon: const Icon(Icons.translate)),
              ButtonSegment<LocaleOption>(
                  value: LocaleOption.english,
                  label: Text(l10n.languageEnglish),
                  icon: const Icon(Icons.language)),
            ],
          ),

          // ── 通用 ──
          const SizedBox(height: AppTokens.spaceXl),
          _SettingsGroupHeader(label: l10n.generalSettingsGroup),
          const _GeneralSettingsCard(),

          // ── 播放与阅读 ──
          const SizedBox(height: AppTokens.spaceXl),
          _SettingsGroupHeader(label: l10n.settingsGroupPlayback),
          AppListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: Text(l10n.playerSettingsTitle),
            subtitle: Text(l10n.playerSettingsDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsPlayerScreen(),
              ),
            ),
          ),
          AppListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(l10n.novelReaderSettingsTitle),
            subtitle: Text(l10n.novelReaderSettingsDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsNovelReaderScreen(),
              ),
            ),
          ),
          AppListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: Text(l10n.comicReaderSettingsTitle),
            subtitle: Text(l10n.comicReaderSettingsDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsComicReaderScreen(),
              ),
            ),
          ),
          AppListTile(
            leading: const Icon(Icons.view_quilt_outlined),
            title: Text(l10n.layoutSettings),
            subtitle: Text(l10n.layoutSettingsDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLayoutPickerDialog(context),
          ),
          AppListTile(
            leading: const Icon(Icons.comment),
            title: Text(l10n.danmakuSettings),
            subtitle: Text(l10n.danmakuSettingsDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsDanmakuScreen(),
              ),
            ),
          ),
          AppListTile(
            leading: const Icon(Icons.subtitles_outlined),
            title: Text(l10n.danmakuDisplaySettingsTitle),
            subtitle: Text(l10n.danmakuDisplaySettingsDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsDanmakuDisplayScreen(),
              ),
            ),
          ),

          // ── 内容源 ──
          const SizedBox(height: AppTokens.spaceXl),
          _SettingsGroupHeader(label: l10n.settingsGroupContentSources),
          AppListTile(
            leading: const Icon(Icons.rss_feed),
            title: Text(l10n.sourceManagementTitle),
            subtitle: Text(l10n.subscriptionManagementDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SourceManagerScreen(),
              ),
            ),
          ),
          AppListTile(
            leading: const Icon(Icons.travel_explore),
            title: Text(l10n.webScrapeSetting),
            subtitle: Text(l10n.webScrapeSettingSameAsBrowse),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BrowseWebScrapeScreen(),
              ),
            ),
          ),

          // ── 订阅与通知 ──
          const SizedBox(height: AppTokens.spaceXl),
          _SettingsGroupHeader(label: l10n.settingsGroupSubscriptions),
          AppListTile(
            leading: const Icon(Icons.rss_feed_outlined),
            title: Text(l10n.rsshubInstance),
            subtitle: Text(l10n.rsshubInstanceDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsRssHubScreen(),
              ),
            ),
          ),
          AppListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(l10n.rssNotifications),
            subtitle: Text(l10n.rssNotificationsDesc),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsRssNotificationsScreen(),
              ),
            ),
          ),

          // ── 下载与数据 ──
          const SizedBox(height: AppTokens.spaceXl),
          _SettingsGroupHeader(label: l10n.settingsGroupDownloadsData),
          AppListTile(
            leading: const Icon(Icons.download),
            title: Text(l10n.downloadManagementTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsDownloadScreen(),
              ),
            ),
          ),
          AppListTile(
            leading: const Icon(Icons.swap_vert),
            title: Text(l10n.dataImportExport),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsImportExportScreen(),
              ),
            ),
          ),
          _CloudSyncTile(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsCloudSyncScreen(),
              ),
            ),
          ),

          // ── 关于 ──
          const SizedBox(height: AppTokens.spaceXl),
          _SettingsGroupHeader(label: l10n.aboutAppTitle),

          const SizedBox(height: AppTokens.spaceLg),
          AppListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(l10n.clearCache),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              HttpFetcher.instance.clearCookies();
              PaintingBinding.instance.imageCache.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.cacheCleared)),
              );
            },
          ),

          const SizedBox(height: AppTokens.spaceLg),
          AppListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.aboutApp),
            subtitle: Text(l10n.aboutDescription),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AboutScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 可复用组件：设置分组标题 —— 禁止复制粘贴重复实现
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsGroupHeader extends StatelessWidget {
  final String label;
  const _SettingsGroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 云同步列表项 —— 订阅 [CloudSyncService] 动态显示上次同步状态。
///
/// 显示规则：
/// - 未配置 WebDAV URL：显示「未配置，点击设置」
/// - 已配置但从未同步：显示「尚未同步」
/// - 已同步：显示「上次同步：{时间}」(yyyy-MM-dd HH:mm)
class _CloudSyncTile extends StatelessWidget {
  final VoidCallback onTap;

  const _CloudSyncTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Consumer<CloudSyncService>(
      builder: (context, service, _) {
        final config = service.config;
        return AnimatedBuilder(
          animation: GeneralSettingsStore.instance,
          builder: (_, __) {
            String subtitle;
            if (config.url.isEmpty) {
              subtitle = l10n.cloudSyncNotConfigured;
            } else if (config.lastSyncTimestamp == null) {
              subtitle = l10n.cloudSyncNeverSynced;
            } else {
              final dt = DateTime.fromMillisecondsSinceEpoch(
                config.lastSyncTimestamp!,
              );
              final formatted =
                  GeneralSettingsStore.instance.settings.dateFormat.format(
                dt,
                withTime: true,
              );
              subtitle = l10n.cloudSyncLastSyncTime(formatted);
            }
            return AppListTile(
              leading: const Icon(Icons.cloud_sync),
              title: Text(l10n.cloudSync),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: onTap,
            );
          },
        );
      },
    );
  }
}

/// 通用设置卡：启动界面 + 日期格式。
class _GeneralSettingsCard extends StatefulWidget {
  const _GeneralSettingsCard();

  @override
  State<_GeneralSettingsCard> createState() => _GeneralSettingsCardState();
}

class _GeneralSettingsCardState extends State<_GeneralSettingsCard> {
  late GeneralSettings _s;

  @override
  void initState() {
    super.initState();
    final store = GeneralSettingsStore.instance;
    _s = store.settings;
    // 若单例尚未完成首次加载，加载完成后用已存储值刷新选中态，
    // 避免初始读取到默认值导致选中项显示错位。
    if (!store.loaded) {
      store.load().then((s) {
        if (mounted) setState(() => _s = s);
      });
    }
  }

  void _update(GeneralSettings next) {
    setState(() => _s = next);
    GeneralSettingsStore.instance.save(next);
  }

  String _launchLabel(AppLocalizations l10n, LaunchTab t) => switch (t) {
        LaunchTab.browse => l10n.navBrowse,
        LaunchTab.novel => l10n.navNovel,
        LaunchTab.media => l10n.navMedia,
        LaunchTab.comic => l10n.navComic,
        LaunchTab.settings => l10n.navSettings,
      };

  String _dateFormatLabel(AppLocalizations l10n, AppDateFormat d) =>
      switch (d) {
        AppDateFormat.defaultFormat => l10n.dateFormatDefault,
        AppDateFormat.mmddyy => l10n.dateFormatMmDdYy,
        AppDateFormat.ddmmyy => l10n.dateFormatDdMmYy,
        AppDateFormat.yyyymmdd => l10n.dateFormatYyyyMmDd,
        AppDateFormat.ddmmmyyyy => l10n.dateFormatDdMmmYyyy,
        AppDateFormat.mmmdd => l10n.dateFormatMmmDd,
        AppDateFormat.yyyyOnly => l10n.dateFormatYyyy,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsCard(
      title: null,
      backgroundColor: Colors.transparent,
      children: <Widget>[
        SettingsChoiceChips<LaunchTab>(
          title: l10n.launchScreenTitle,
          selected: _s.launchTab,
          onSelected: (v) => _update(_s.copyWith(launchTab: v)),
          options: LaunchTab.values
              .map((t) => SettingsChoiceChipData<LaunchTab>(
                    value: t,
                    label: _launchLabel(l10n, t),
                  ))
              .toList(),
        ),
        SettingsChoiceChips<AppDateFormat>(
          title: l10n.dateFormatTitle,
          selected: _s.dateFormat,
          onSelected: (v) => _update(_s.copyWith(dateFormat: v)),
          options: AppDateFormat.values
              .map((d) => SettingsChoiceChipData<AppDateFormat>(
                    value: d,
                    label: _dateFormatLabel(l10n, d),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
