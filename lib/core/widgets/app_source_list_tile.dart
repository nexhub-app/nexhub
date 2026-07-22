import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'app_icon_button.dart';

/// 源列表项（源管理页专用）。统一布局：名称 + 地址 + 状态标签 + 操作按钮。
class AppSourceListTile extends StatelessWidget {
  final String name;
  final String? url;
  final bool enabled;
  final bool deprecated;
  final String deprecatedLabel;
  final String healthyLabel;
  final String disabledLabel;
  final String mirrorSettingsTooltip;
  final VoidCallback? onTap;
  final VoidCallback? onMirrorSettings;
  final ValueChanged<bool>? onToggle;

  const AppSourceListTile({
    super.key,
    required this.name,
    this.url,
    this.enabled = true,
    this.deprecated = false,
    required this.deprecatedLabel,
    required this.healthyLabel,
    required this.disabledLabel,
    required this.mirrorSettingsTooltip,
    this.onTap,
    this.onMirrorSettings,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    Widget statusChip() {
      if (deprecated) {
        return Chip(
          label: Text(deprecatedLabel,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 11)),
          backgroundColor: scheme.errorContainer,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        );
      }
      if (!enabled) {
        return Chip(
          label: Text(disabledLabel,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
          backgroundColor: scheme.surfaceVariant,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        );
      }
      return Chip(
        label: Text(healthyLabel,
            style: TextStyle(color: Colors.green, fontSize: 11)),
        backgroundColor: Colors.green.withValues(alpha: 0.1),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
      );
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
      ),
      title: Text(name),
      subtitle: url != null
          ? Text(url!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          statusChip(),
          if (onMirrorSettings != null)
            Padding(
              padding: const EdgeInsets.only(left: AppTokens.spaceSm),
              child: AppIconButton(
                icon: Icons.settings_ethernet,
                tooltip: mirrorSettingsTooltip,
                onPressed: onMirrorSettings,
              ),
            ),
          if (onToggle != null)
            Padding(
              padding: const EdgeInsets.only(left: AppTokens.spaceSm),
              child: Switch(
                value: enabled,
                onChanged: onToggle,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
    );
  }
}
