/// 在线源浏览页 —— 在线 Tab 的入口。
///
/// 展示当前模块所有已配置的源列表（图标 + 名称 + 地址 + 状态），
/// 点击某个源后进入该源的分类/内容浏览页（[OnlineContentListScreen]）。
///
/// 解决「无法浏览在线的源」的问题：用户可在此页直观地看到并选择要浏览的源。
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/models/plugin_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/detail_action_utils.dart';
import '../../../core/services/source_repository.dart';

class OnlineSourceBrowserScreen extends StatelessWidget {
  /// 当前模块过滤类型
  final SourceType sourceType;
  final IconData emptyIcon;
  /// 点击某个源时的回调
  final void Function(PluginConfig source) onSourceTap;
  final VoidCallback? onAddSource;
  final VoidCallback? onEnableRecommended;

  const OnlineSourceBrowserScreen({
    super.key,
    required this.sourceType,
    this.emptyIcon = Icons.language_outlined,
    required this.onSourceTap,
    this.onAddSource,
    this.onEnableRecommended,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final repo = context.watch<SourceRepository>();
    final sources = repo.byType(sourceType);

    if (sources.isEmpty) {
      return AppEmptyState(
        icon: emptyIcon,
        message: l10n.emptySources,
        actionLabel: onEnableRecommended != null
            ? l10n.enableRecommendedSources
            : l10n.addSource,
        onAction: onEnableRecommended ?? onAddSource,
        secondaryActionLabel:
            onEnableRecommended != null ? l10n.addSource : null,
        onSecondaryAction: onEnableRecommended != null ? onAddSource : null,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      itemCount: sources.length,
      itemBuilder: (context, i) {
        final source = sources[i];
        return AppCard(
          onTap: () => _openSource(context, source),
          padding: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg,
              vertical: AppTokens.spaceXs,
            ),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _sourceColor(source.type, scheme).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              ),
              child: Icon(
                _sourceIcon(source.type),
                color: _sourceColor(source.type, scheme),
                size: 22,
              ),
            ),
            title: Text(
              source.name,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceXs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    source.site.baseUrl,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppTokens.spaceXs),
                  _buildStatusChip(source, scheme, l10n),
                ],
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: l10n.openSourceWebsite,
              onPressed: () =>
                  openInAppBrowser(context, source.site.baseUrl),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(PluginConfig source, ColorScheme scheme, AppLocalizations l10n) {
    if (!source.isEnabled) {
      return Chip(
        label: Text(l10n.deprecated, style: TextStyle(fontSize: 11, color: scheme.error)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      );
    }
    if (source.isDeprecated) {
      return Chip(
        label: Text(l10n.deprecated, style: TextStyle(fontSize: 11, color: scheme.error)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      );
    }
    return Chip(
      label: Text(l10n.sourceHealthy, style: const TextStyle(fontSize: 11, color: Colors.green)),
      backgroundColor: Colors.green.withValues(alpha: 0.1),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
    );
  }

  void _openSource(BuildContext context, PluginConfig source) {
    onSourceTap(source);
  }

  static Color _sourceColor(SourceType type, ColorScheme scheme) {
    if (type == SourceType.novelSource) return scheme.primary;
    if (type == SourceType.animeSource) return scheme.tertiary;
    return scheme.secondary; // mangaSource
  }

  static IconData _sourceIcon(SourceType type) {
    if (type == SourceType.novelSource) return Icons.menu_book_outlined;
    if (type == SourceType.animeSource) return Icons.movie_outlined;
    return Icons.auto_stories_outlined; // mangaSource
  }
}
