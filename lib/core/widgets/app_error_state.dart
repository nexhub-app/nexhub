import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// 统一错误状态。
class AppErrorState extends StatelessWidget {
  final String message; // 来自 l10n
  final VoidCallback? onRetry;
  final String? retryLabel; // 来自 l10n（onRetry 不为空时应传入）
  final String? secondaryActionLabel; // 来自 l10n（可选次按钮，如"去验证"）
  final VoidCallback? onSecondaryAction;
  const AppErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel,
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
            Icon(Icons.error_outline, size: 64, color: scheme.error.withValues(alpha: 0.8)),
            const SizedBox(height: AppTokens.spaceLg),
            Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null || onSecondaryAction != null) ...<Widget>[
              const SizedBox(height: AppTokens.spaceLg),
              Wrap(
                spacing: AppTokens.spaceMd,
                runSpacing: AppTokens.spaceSm,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  if (onRetry != null)
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: Text(retryLabel ?? ''),
                    ),
                  if (onSecondaryAction != null)
                    OutlinedButton.icon(
                      onPressed: onSecondaryAction,
                      icon: const Icon(Icons.verified_user_outlined),
                      label: Text(secondaryActionLabel ?? ''),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
