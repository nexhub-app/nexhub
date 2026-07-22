import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// 统一卡片容器（token 圆角 + 阴影）。点击态可选。
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget content = Container(
      padding: padding ?? const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        boxShadow: AppShadows.card(scheme),
      ),
      child: child,
    );
    return onTap != null
        ? Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              child: content,
            ),
          )
        : content;
  }
}
