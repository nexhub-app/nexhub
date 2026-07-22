import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// 统一加载指示器。
class AppLoadingIndicator extends StatelessWidget {
  final String? message; // 来自 l10n
  final bool center;
  const AppLoadingIndicator({
    super.key,
    this.message,
    this.center = true,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget child = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CircularProgressIndicator(color: scheme.primary),
        if (message != null) ...<Widget>[
          const SizedBox(height: AppTokens.spaceMd),
          Text(message!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
    return center ? Center(child: child) : child;
  }
}
