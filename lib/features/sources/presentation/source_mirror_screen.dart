library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/scraper/http_fetcher.dart';
import '../../../core/services/config_loader.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_list_tile.dart';

/// 镜像管理页：列出源的可用镜像，支持测速与切换。
class SourceMirrorScreen extends StatefulWidget {
  final PluginConfig source;
  const SourceMirrorScreen({super.key, required this.source});

  @override
  State<SourceMirrorScreen> createState() => _SourceMirrorScreenState();
}

class _SourceMirrorScreenState extends State<SourceMirrorScreen> {
  late String _activeBaseUrl;
  final Map<String, int> _speeds = <String, int>{};
  final Set<String> _testing = <String>{};
  final Set<String> _failed = <String>{};

  @override
  void initState() {
    super.initState();
    _activeBaseUrl = ConfigLoader.instance.getActiveMirror(widget.source);
  }

  Future<void> _testSpeed(String baseUrl) async {
    if (_testing.contains(baseUrl)) return;
    setState(() {
      _testing.add(baseUrl);
      _failed.remove(baseUrl);
    });
    final stopwatch = Stopwatch()..start();
    try {
      await HttpFetcher.instance.getHtml(baseUrl);
      if (mounted) setState(() => _speeds[baseUrl] = stopwatch.elapsedMilliseconds);
    } catch (_) {
      if (mounted) setState(() => _failed.add(baseUrl));
    } finally {
      stopwatch.stop();
      if (mounted) setState(() => _testing.remove(baseUrl));
    }
  }

  void _select(String baseUrl) {
    ConfigLoader.instance.setActiveMirror(widget.source.id, baseUrl);
    setState(() => _activeBaseUrl = baseUrl);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).mirrorSwitched)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final mirrors = widget.source.site.mirrors;
    return Scaffold(
      appBar: AppBar(title: Text(widget.source.name)),
      body: mirrors.isEmpty
          ? AppEmptyState(icon: Icons.dns, message: l10n.mirrorNoMirrors)
          : ListView(
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              children: <Widget>[
                ...mirrors.map((m) {
                  final speed = _speeds[m.baseUrl];
                  final testing = _testing.contains(m.baseUrl);
                  final failed = _failed.contains(m.baseUrl);
                  return AppListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      child: Text(
                        m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                    ),
                    title: Text(m.name),
                    subtitle: Text(
                      m.domain,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (testing)
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          )
                        else if (failed)
                          Icon(Icons.error_outline,
                              color: scheme.error, size: 16)
                        else if (speed != null)
                          Text(
                            l10n.mirrorTestResultMs(speed),
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        else
                          const SizedBox.shrink(),
                        AppIconButton(
                          icon: Icons.speed,
                          tooltip: l10n.mirrorTest,
                          onPressed: () => _testSpeed(m.baseUrl),
                        ),
                        Radio<String>(
                          value: m.baseUrl,
                          groupValue: _activeBaseUrl,
                          onChanged: (_) => _select(m.baseUrl),
                        ),
                      ],
                    ),
                    onTap: () => _select(m.baseUrl),
                  );
                }),
                const SizedBox(height: AppTokens.spaceLg),
                Container(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.lock,
                          size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(
                        child: Text(
                          l10n.mirrorStealthLocked,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
