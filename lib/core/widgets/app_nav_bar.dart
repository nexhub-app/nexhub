import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// 应用导航栏统一封装。
///
/// 根据可用宽度自适应：
/// - **移动端**（宽度 < [AppTokens.desktopBreakpoint]）：自定义底导，
///   选中项图标使用 [AnimatedScale] 放大（1.15），背景使用 pill 形状
///   （[AppTokens.radiusFull] 圆角 + `primaryContainer` 填充）。
/// - **桌面端**（宽度 ≥ [AppTokens.desktopBreakpoint]）：使用 Material
///   [NavigationRail]，竖向全高布局，标签始终显示。
///
/// API 保持与原 NavigationBar 封装一致：
/// [selectedIndex] / [onDestinationSelected] / [destinations]。
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  /// 当前选中项索引。
  final int selectedIndex;

  /// 选中项变化回调。
  final ValueChanged<int> onDestinationSelected;

  /// 导航目的地列表（与 [NavigationBar.destinations] 语义一致）。
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    if (width >= AppTokens.desktopBreakpoint) {
      return _buildNavigationRail(context);
    }
    return _buildMobileNavBar(context);
  }

  /// 桌面端：竖向 [NavigationRail]，扩展到全高。
  Widget _buildNavigationRail(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      backgroundColor: colorScheme.surface,
      labelType: NavigationRailLabelType.all,
      destinations: destinations
          .map((NavigationDestination d) => NavigationRailDestination(
                icon: d.icon,
                selectedIcon: d.selectedIcon ?? d.icon,
                label: Text(d.label),
              ))
          .toList(),
    );
  }

  /// 移动端：自定义底导，含 pill + scale 动画。
  Widget _buildMobileNavBar(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      elevation: 2,
      child: SizedBox(
        height: AppTokens.bottomNavHeight,
        child: SafeArea(
          top: false,
          child: Row(
            children: List<Widget>.generate(destinations.length, (int i) {
              return Expanded(
                child: _AppNavItem(
                  destination: destinations[i],
                  selected: i == selectedIndex,
                  onTap: () => onDestinationSelected(i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// 单个导航项 —— 选中时图标 [AnimatedScale] 放大，背景显示 pill。
class _AppNavItem extends StatelessWidget {
  const _AppNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Widget icon = selected && destination.selectedIcon != null
        ? destination.selectedIcon!
        : destination.icon;
    // 选中：onPrimaryContainer；未选中：onSurfaceVariant。
    final Color iconColor = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    final Color labelColor =
        selected ? colorScheme.onSurface : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // pill 背景 + 图标（scale 动画）。
          AnimatedContainer(
            duration: AppTokens.durFast,
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg,
              vertical: AppTokens.spaceXs,
            ),
            decoration: BoxDecoration(
              color: selected ? colorScheme.primaryContainer : Colors.transparent,
              borderRadius:
                  BorderRadius.circular(AppTokens.radiusFull),
            ),
            child: AnimatedScale(
              scale: selected ? 1.15 : 1.0,
              duration: AppTokens.durFast,
              curve: Curves.easeInOut,
              child: IconTheme.merge(
                data: IconThemeData(color: iconColor, size: 24),
                child: icon,
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          AnimatedDefaultTextStyle(
            duration: AppTokens.durFast,
            style: TextStyle(
              fontSize: 12,
              color: labelColor,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
            child: Text(destination.label),
          ),
        ],
      ),
    );
  }
}
