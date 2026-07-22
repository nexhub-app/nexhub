import 'package:flutter/material.dart';

/// 统一图标按钮。tooltip 必须来自 l10n。
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip; // 来自 l10n
  final VoidCallback? onPressed;
  final bool filled;
  final Color? color;
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.filled = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return IconButton.filledTonal(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon),
      );
    }
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      color: color,
      icon: Icon(icon),
    );
  }
}
