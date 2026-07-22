import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/danmaku/danmaku_source.dart';
import '../../../core/theme/app_tokens.dart';

/// 弹幕源选择面板（底部弹出 Sheet）。
///
/// 提供四选一：弹弹play / bilibili / 自定义 URL / 关闭。
/// 切换后通过 [onChanged] 通知调用方重新加载弹幕；
/// 当选择「自定义 URL」并通过 [onCustomUrl] 回传 URL 字符串。
class DanmakuSourceSheet extends StatefulWidget {
  const DanmakuSourceSheet({
    super.key,
    required this.currentSource,
    required this.onChanged,
    this.currentCustomUrl = '',
    this.onCustomUrl,
  });

  /// 当前选中的弹幕源。
  final DanmakuSourceType currentSource;

  /// 切换弹幕源后的回调。
  final ValueChanged<DanmakuSourceType> onChanged;

  /// 当前自定义 URL（用于回显 TextField）。
  final String currentCustomUrl;

  /// 自定义 URL 提交回调（用户点击确认时触发）。
  final ValueChanged<String>? onCustomUrl;

  /// 以 modal bottom sheet 形式展示。
  static Future<void> show(
    BuildContext context, {
    required DanmakuSourceType currentSource,
    required ValueChanged<DanmakuSourceType> onChanged,
    String currentCustomUrl = '',
    ValueChanged<String>? onCustomUrl,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusLg),
        ),
      ),
      builder: (BuildContext context) => DanmakuSourceSheet(
        currentSource: currentSource,
        onChanged: onChanged,
        currentCustomUrl: currentCustomUrl,
        onCustomUrl: onCustomUrl,
      ),
    );
  }

  @override
  State<DanmakuSourceSheet> createState() => _DanmakuSourceSheetState();
}

class _DanmakuSourceSheetState extends State<DanmakuSourceSheet> {
  late final TextEditingController _urlController;
  late DanmakuSourceType _selected;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.currentCustomUrl);
    _selected = widget.currentSource;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _select(DanmakuSourceType next) {
    setState(() => _selected = next);
    widget.onChanged(next);
    if (next != DanmakuSourceType.customUrl) {
      Navigator.of(context).maybePop();
    }
  }

  /// #6 A4-#6: 提交自定义 URL。
  void _submitCustomUrl() {
    final url = _urlController.text.trim();
    widget.onCustomUrl?.call(url);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            left: 0,
            right: 0,
            top: 0,
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _header(context, l10n, theme),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceLg,
                  vertical: AppTokens.spaceXs,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.danmakuSourceHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              _optionTile(
                context: context,
                l10n: l10n,
                theme: theme,
                source: DanmakuSourceType.dandanplay,
                icon: Icons.cloud_outlined,
                title: l10n.danmakuSourceDandanplay,
                description: l10n.danmakuSourceDandanplayDesc,
              ),
              _optionTile(
                context: context,
                l10n: l10n,
                theme: theme,
                source: DanmakuSourceType.bilibili,
                icon: Icons.live_tv_outlined,
                title: l10n.danmakuSourceBilibili,
                description: l10n.danmakuSourceBilibiliDesc,
              ),
              // #6 A4-#6: 自定义 URL 选项
              _optionTile(
                context: context,
                l10n: l10n,
                theme: theme,
                source: DanmakuSourceType.customUrl,
                icon: Icons.link_outlined,
                title: l10n.danmakuCustomUrl,
                description: l10n.danmakuCustomUrlDesc,
              ),
              // 当选中 customUrl 时显示 URL 输入框
              if (_selected == DanmakuSourceType.customUrl)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceLg,
                    vertical: AppTokens.spaceXs,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: l10n.danmakuCustomUrlHint,
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.url,
                          onSubmitted: (_) => _submitCustomUrl(),
                        ),
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                      FilledButton(
                        onPressed: _submitCustomUrl,
                        child: Text(l10n.confirm),
                      ),
                    ],
                  ),
                ),
              _optionTile(
                context: context,
                l10n: l10n,
                theme: theme,
                source: DanmakuSourceType.off,
                icon: Icons.comments_disabled_outlined,
                title: l10n.danmakuSourceOff,
                description: l10n.danmakuSourceOffDesc,
              ),
              const SizedBox(height: AppTokens.spaceMd),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.spaceMd,
        AppTokens.spaceSm,
        AppTokens.spaceSm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              l10n.danmakuSourceTitle,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.close,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _optionTile({
    required BuildContext context,
    required AppLocalizations l10n,
    required ThemeData theme,
    required DanmakuSourceType source,
    required IconData icon,
    required String title,
    required String description,
  }) {
    return RadioListTile<DanmakuSourceType>(
      value: source,
      groupValue: _selected,
      onChanged: (DanmakuSourceType? next) {
        if (next != null) _select(next);
      },
      secondary: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title),
      subtitle: Text(
        description,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLg,
        vertical: AppTokens.spaceXs,
      ),
    );
  }
}
