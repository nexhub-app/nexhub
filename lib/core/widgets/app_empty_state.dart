import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// 统一空状态。禁止在各 feature 内联 `Column + Icon + Text`。
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String message; // 来自 l10n
  final String? actionLabel; // 来自 l10n
  final VoidCallback? onAction;
  final String? secondaryActionLabel; // 来自 l10n
  final VoidCallback? onSecondaryAction;
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 64, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: AppTokens.spaceLg),
            Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AppTokens.spaceLg),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
            if (secondaryActionLabel != null && onSecondaryAction != null) ...<Widget>[
              const SizedBox(height: AppTokens.spaceSm),
              OutlinedButton(
                onPressed: onSecondaryAction,
                child: Text(secondaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
