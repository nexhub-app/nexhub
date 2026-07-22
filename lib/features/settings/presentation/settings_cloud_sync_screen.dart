/// 云同步设置页 —— WebDAV 备份与多端同步配置。
///
/// 提供以下功能：
/// 1. WebDAV URL / 用户名 / 密码配置（密码用 secure storage 安全存储）
/// 2. 测试连接（显示延迟，按颜色分级：绿 <300ms / 橙 300-800ms / 红 >800ms）
/// 3. 自动同步开关与频率选择（手动 / 每日 / 每周）
/// 4. 立即同步按钮
/// 5. 显示上次同步时间
/// 6. 保留本地导入/导出入口作为兜底
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import '../../../core/settings/general_settings.dart';
import 'package:provider/provider.dart';

import '../../../core/services/cloud_sync_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import './settings_import_export_screen.dart';

class SettingsCloudSyncScreen extends StatefulWidget {
  const SettingsCloudSyncScreen({super.key});

  @override
  State<SettingsCloudSyncScreen> createState() =>
      _SettingsCloudSyncScreenState();
}

class _SettingsCloudSyncScreenState extends State<SettingsCloudSyncScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  final TextEditingController _passwordController = TextEditingController();
  bool _testing = false;
  bool _saving = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<CloudSyncService>().config;
    _urlController = TextEditingController(text: config.url);
    _usernameController = TextEditingController(text: config.username);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Color _latencyColor(int ms) {
    if (ms < 300) return Colors.green;
    if (ms < 800) return Colors.orange;
    return Colors.red;
  }

  Future<void> _testConnection(AppLocalizations l10n) async {
    final service = context.read<CloudSyncService>();
    final url = _urlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    // 若用户未输入新密码，使用已存储的密码
    final effectivePassword = password.isNotEmpty
        ? password
        : (await CloudSyncConfigStore().loadPassword()) ?? '';
    if (url.isEmpty || username.isEmpty || effectivePassword.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.cloudSyncConnectionFailed)),
        );
      }
      return;
    }
    setState(() => _testing = true);
    final (success, ms) = await service.testConnection(
      url: url,
      username: username,
      password: effectivePassword,
    );
    if (!mounted) return;
    setState(() => _testing = false);
    final messenger = ScaffoldMessenger.of(context);
    if (success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.cloudSyncConnectionSuccess(ms),
            style: TextStyle(color: _latencyColor(ms)),
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.cloudSyncConnectionFailed)),
      );
    }
  }

  Future<void> _saveConfig(AppLocalizations l10n) async {
    final service = context.read<CloudSyncService>();
    final url = _urlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    setState(() => _saving = true);
    final newConfig = service.config.copyWith(
      url: url,
      username: username,
    );
    // 密码为空则不更新密码
    await service.updateConfig(newConfig, password.isNotEmpty ? password : null);
    _passwordController.clear();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.save)),
    );
  }

  Future<void> _syncNow(AppLocalizations l10n) async {
    final service = context.read<CloudSyncService>();
    setState(() => _syncing = true);
    final ok = await service.syncNow();
    if (!mounted) return;
    setState(() => _syncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? l10n.cloudSyncSyncSuccess : l10n.cloudSyncSyncFailed)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final service = context.watch<CloudSyncService>();
    final config = service.config;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.cloudSync)),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        children: <Widget>[
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: l10n.cloudSyncWebdavUrl,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: AppTokens.spaceMd),
          TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: l10n.cloudSyncWebdavUsername,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.person),
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          TextField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: l10n.cloudSyncWebdavPassword,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock),
            ),
            obscureText: true,
          ),
          const SizedBox(height: AppTokens.spaceMd),
          FilledButton.icon(
            onPressed: _testing ? null : () => _testConnection(l10n),
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find),
            label: Text(l10n.cloudSyncTestConnection),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _saveConfig(l10n),
            icon: const Icon(Icons.save),
            label: Text(l10n.cloudSyncSaveConfig),
          ),
          const SizedBox(height: AppTokens.spaceLg),
          SwitchListTile(
            title: Text(l10n.cloudSyncAutoSync),
            value: config.autoSync,
            onChanged: (v) async {
              await service.updateConfig(
                config.copyWith(autoSync: v),
                null,
              );
            },
          ),
          const SizedBox(height: AppTokens.spaceSm),
          SegmentedButton<SyncFrequency>(
            segments: <ButtonSegment<SyncFrequency>>[
              ButtonSegment<SyncFrequency>(
                value: SyncFrequency.manual,
                label: Text(l10n.cloudSyncSyncFrequencyManual),
              ),
              ButtonSegment<SyncFrequency>(
                value: SyncFrequency.daily,
                label: Text(l10n.cloudSyncSyncFrequencyDaily),
              ),
              ButtonSegment<SyncFrequency>(
                value: SyncFrequency.weekly,
                label: Text(l10n.cloudSyncSyncFrequencyWeekly),
              ),
            ],
            selected: <SyncFrequency>{config.frequency},
            onSelectionChanged: config.autoSync
                ? (Set<SyncFrequency> selection) async {
                    final f = selection.first;
                    await service.updateConfig(
                      config.copyWith(frequency: f),
                      null,
                    );
                  }
                : null,
          ),
          const SizedBox(height: AppTokens.spaceLg),
          FilledButton.icon(
            onPressed: (_syncing || service.isSyncing)
                ? null
                : () => _syncNow(l10n),
            icon: (_syncing || service.isSyncing)
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_sync),
            label: Text(l10n.cloudSyncSyncNow),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          _LastSyncText(config: config),
          const SizedBox(height: AppTokens.spaceXl),
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
        ],
      ),
    );
  }
}

class _LastSyncText extends StatelessWidget {
  final CloudSyncConfig config;

  const _LastSyncText({required this.config});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: GeneralSettingsStore.instance,
      builder: (context, _) {
        String text;
        if (config.lastSyncTimestamp == null) {
          text = l10n.cloudSyncNeverSynced;
        } else {
          final dt = DateTime.fromMillisecondsSinceEpoch(
            config.lastSyncTimestamp!,
          );
          final formatted =
              GeneralSettingsStore.instance.settings.dateFormat.format(
            dt,
            withTime: true,
          );
          text = l10n.cloudSyncLastSyncTime(formatted);
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceSm),
          child: Text(
            text,
            style: theme.textTheme.bodyMedium,
          ),
        );
      },
    );
  }
}
