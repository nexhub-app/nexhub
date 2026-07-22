import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'app_icon_button.dart';

/// 源列表统一项（源管理页复用）。所有可见字符串来自 l10n。
class UnifiedSourceTile extends StatelessWidget {
  final String name;
  final String? url;
  final bool enabled;
  final bool deprecated;
  final bool isHidden;
  final bool useMoreMenu; // 源管理页：把操作收进「更多」菜单（其他页面保持内联）
  final String moreMenuTooltip; // 来自 l10n（「更多操作」）
  final String deprecatedLabel; // 来自 l10n
  final String mirrorSettingsTooltip; // 来自 l10n
  final String hideTooltip; // 来自 l10n
  final String unhideTooltip; // 来自 l10n
  final String editTooltip; // 来自 l10n
  final String deleteTooltip; // 来自 l10n
  final String migrateTooltip; // 来自 l10n
  final VoidCallback? onTap;
  final VoidCallback? onMirrorSettings;
  final VoidCallback? onHide;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onMigrate;
  final ValueChanged<bool>? onToggle;
  const UnifiedSourceTile({
    super.key,
    required this.name,
    this.url,
    this.enabled = true,
    this.deprecated = false,
    this.isHidden = false,
    this.useMoreMenu = false,
    this.moreMenuTooltip = '',
    required this.deprecatedLabel,
    required this.mirrorSettingsTooltip,
    this.hideTooltip = '',
    this.unhideTooltip = '',
    this.editTooltip = '',
    this.deleteTooltip = '',
    this.migrateTooltip = '',
    this.onTap,
    this.onMirrorSettings,
    this.onHide,
    this.onEdit,
    this.onDelete,
    this.onMigrate,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget titleWidget = Text(
      name,
      style: isHidden
          ? TextStyle(color: scheme.onSurfaceVariant)
          : null,
    );
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isHidden
            ? scheme.surfaceContainerHighest
            : scheme.primaryContainer,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: isHidden
                ? scheme.onSurfaceVariant
                : scheme.onPrimaryContainer,
          ),
        ),
      ),
      title: titleWidget,
      subtitle: url != null
          ? Text(url!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant))
          : null,
      trailing: _buildTrailing(scheme),
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
    );
  }

  /// 弃用徽章（两种模式共用）：点击触发迁移提示。
  Widget _deprecatedChip(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.only(right: AppTokens.spaceSm),
        child: InkWell(
          onTap: onMigrate,
          borderRadius: BorderRadius.circular(16),
          child: Chip(
            label: Text(deprecatedLabel,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 11)),
            backgroundColor: scheme.errorContainer,
            visualDensity: VisualDensity.compact,
          ),
        ),
      );

  bool get _hasMenuActions =>
      onMirrorSettings != null ||
      onEdit != null ||
      onDelete != null ||
      onHide != null ||
      onMigrate != null;

  PopupMenuEntry<String> _menuItem(
    String value,
    IconData icon,
    String text,
  ) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20),
            const SizedBox(width: AppTokens.spaceSm),
            Text(text),
          ],
        ),
      );

  List<PopupMenuEntry<String>> _buildMenuItems(BuildContext context) =>
      <PopupMenuEntry<String>>[
        if (onMirrorSettings != null)
          _menuItem('mirror', Icons.settings_ethernet, mirrorSettingsTooltip),
        if (onEdit != null) _menuItem('edit', Icons.edit_outlined, editTooltip),
        if (onDelete != null)
          _menuItem('delete', Icons.delete_outline, deleteTooltip),
        if (onHide != null)
          _menuItem('hide', isHidden ? Icons.visibility : Icons.visibility_off_outlined,
              isHidden ? unhideTooltip : hideTooltip),
        if (onMigrate != null)
          _menuItem('migrate', Icons.upgrade, migrateTooltip),
      ];

  void _onMenuSelected(String value) {
    switch (value) {
      case 'mirror':
        onMirrorSettings?.call();
        break;
      case 'edit':
        onEdit?.call();
        break;
      case 'delete':
        onDelete?.call();
        break;
      case 'hide':
        onHide?.call();
        break;
      case 'migrate':
        onMigrate?.call();
        break;
    }
  }

  /// 右侧操作区。
  /// - [useMoreMenu]=true（源管理页）：开关保留，其余操作收进「更多」菜单；
  /// - 否则：保持原来的内联图标按钮（其他页面复用，行为不变）。
  Widget _buildTrailing(ColorScheme scheme) {
    if (useMoreMenu) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (deprecated) _deprecatedChip(scheme),
          if (onToggle != null) Switch(value: enabled, onChanged: onToggle),
          if (_hasMenuActions)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
              tooltip: moreMenuTooltip,
              itemBuilder: _buildMenuItems,
              onSelected: _onMenuSelected,
            ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (deprecated) _deprecatedChip(scheme),
        if (onEdit != null)
          AppIconButton(
            icon: Icons.edit_outlined,
            tooltip: editTooltip,
            onPressed: onEdit,
          ),
        if (onDelete != null)
          AppIconButton(
            icon: Icons.delete_outline,
            tooltip: deleteTooltip,
            onPressed: onDelete,
          ),
        if (onHide != null)
          AppIconButton(
            icon: isHidden ? Icons.visibility : Icons.visibility_off_outlined,
            tooltip: isHidden ? unhideTooltip : hideTooltip,
            onPressed: onHide,
          ),
        if (onMirrorSettings != null)
          AppIconButton(
            icon: Icons.settings_ethernet,
            tooltip: mirrorSettingsTooltip,
            onPressed: onMirrorSettings,
          ),
        if (onToggle != null) Switch(value: enabled, onChanged: onToggle),
      ],
    );
  }
}
