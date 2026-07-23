/// 布局设置按钮 —— 全局统一入口（书架/已下载/浏览/搜索/设置页共用）。
///
/// 点击后直接弹出底部富布局弹窗 [showLayoutPickerDialog]，
/// 内含预览 + 网格/列表切换 + 滑块 + 显示选项。
library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';

import 'layout_picker_dialog.dart';

/// 布局设置按钮 —— 点击直接打开底部布局弹窗。
class LayoutPickerButton extends StatelessWidget {
  /// 自定义打开弹窗后的回调（默认调用 [showLayoutPickerDialog]）。
  final Future<void> Function(BuildContext)? onOpenSettings;

  const LayoutPickerButton({super.key, this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      icon: const Icon(Icons.view_module),
      tooltip: l10n.layoutOpenSettings,
      onPressed: () async {
        if (onOpenSettings != null) {
          await onOpenSettings!(context);
        } else {
          await showLayoutPickerDialog(context);
        }
      },
    );
  }
}
