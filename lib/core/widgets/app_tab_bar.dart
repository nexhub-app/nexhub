import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// 顶部 Tab 项定义（图标 + 文字，文字来自 l10n）。
class AppTabItem {
  final IconData icon;
  final String label; // 来自 l10n
  const AppTabItem({required this.icon, required this.label});
}

/// 顶部 TabBar 唯一真源：图标在上、文字在下、选中下划线指示器。
class AppTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<AppTabItem> items;
  const AppTabBar({
    super.key,
    required this.controller,
    required this.items,
  });

  @override
  Size get preferredSize => const Size.fromHeight(AppTokens.tabBarHeight);

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return TabBar(
      controller: controller,
      dividerColor: scheme.outlineVariant,
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: scheme.primary, width: 2),
        insets: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
      ),
      tabs: items
          .map((AppTabItem e) => Tab(icon: Icon(e.icon), text: e.label))
          .toList(),
    );
  }
}
