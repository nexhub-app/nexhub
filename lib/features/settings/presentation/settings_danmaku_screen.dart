/// 弹弹play 弹幕配置页面 —— AppId / AppSecret 设置。
library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import '../../../core/settings/danmaku_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';

class SettingsDanmakuScreen extends StatefulWidget {
  const SettingsDanmakuScreen({super.key});

  @override
  State<SettingsDanmakuScreen> createState() => _SettingsDanmakuScreenState();
}

class _SettingsDanmakuScreenState extends State<SettingsDanmakuScreen> {
  final TextEditingController _appIdController = TextEditingController();
  final TextEditingController _appSecretController = TextEditingController();
  final DanmakuConfigStore _store = DanmakuConfigStore();

  bool _obscureSecret = true;
  bool _obscureAppId = true;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _store.load().then((config) {
      if (mounted) {
        _appIdController.text = config.appId;
        _appSecretController.text = config.appSecret;
        setState(() => _configured = config.isConfigured);
      }
    });
  }

  @override
  void dispose() {
    _appIdController.dispose();
    _appSecretController.dispose();
    super.dispose();
  }

  void _save() {
    final appId = _appIdController.text.trim();
    final appSecret = _appSecretController.text.trim();

    if (appId.isEmpty || appSecret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).appIdHint)),
      );
      return;
    }

    // 持久化保存
    _store.save(DanmakuConfig(
      appId: appId,
      appSecret: appSecret,
      enabled: true,
    ));
    setState(() => _configured = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).saveDanmaku)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.danmakuConfigTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        children: <Widget>[
          // ── 凭据配置状态 ──
          AppListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(_configured ? l10n.saveDanmaku : l10n.unconfigured),
            subtitle: Text(_configured ? l10n.configured : l10n.unconfigured),
          ),

          const SizedBox(height: AppTokens.spaceLg),

          // ── AppId ──
          Text(
            l10n.appIdLabel,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          TextField(
            controller: _appIdController,
            obscureText: _obscureAppId,
            decoration: InputDecoration(
              labelText: l10n.appIdLabel,
              hintText: l10n.appIdHint,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.badge_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureAppId ? Icons.visibility_off : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscureAppId = !_obscureAppId),
              ),
            ),
          ),

          const SizedBox(height: AppTokens.spaceMd),

          // ── AppSecret ──
          Text(
            l10n.appSecretLabel,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          TextField(
            controller: _appSecretController,
            obscureText: _obscureSecret,
            decoration: InputDecoration(
              labelText: l10n.appSecretLabel,
              hintText: l10n.appSecretHint,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureSecret ? Icons.visibility_off : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscureSecret = !_obscureSecret),
              ),
            ),
          ),

          const SizedBox(height: AppTokens.spaceXl),

          // ── 保存按钮 ──
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              child: Text(l10n.saveDanmaku),
            ),
          ),

          const SizedBox(height: AppTokens.spaceXl),

          // ── 说明 ──
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.3)),
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            l10n.danmakuDesc,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
