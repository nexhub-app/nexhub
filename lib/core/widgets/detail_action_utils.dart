/// 详情页共享操作工具（M16.2-16.4 详情页对账）。
///
/// 提供"系统分享 / 外部浏览器打开 / 应用内浏览"三个共享操作的统一实现，
/// 供 [ContentDetailScreen] / [ComicDetailScreen] / [NovelDetailScreen] 复用，
/// 避免三处重复实现。
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/browser/presentation/http_browser_screen.dart';
import '../models/episode.dart';

/// 系统分享：弹出系统分享面板分享标题 + URL。
///
/// URL 为空时仅分享标题。失败时回退到 SnackBar 提示。
Future<void> shareContent(
  BuildContext context,
  String title,
  String? url,
) async {
  final l10n = AppLocalizations.of(context);
  final text = url != null && url.isNotEmpty ? '$title\n$url' : title;
  try {
    await Share.share(text);
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.shareFailed)),
      );
    }
  }
}

/// 用系统外部浏览器打开 URL。
///
/// 使用 [url_launcher] 的 [LaunchMode.externalApplication]。
Future<void> openInExternalBrowser(
  BuildContext context,
  String url,
) async {
  final l10n = AppLocalizations.of(context);
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.openInBrowserFailed)),
      );
    }
  }
}

/// 用应用内内置浏览器（[HttpBrowserScreen]）打开 URL。
///
/// 内置浏览器基于 [InAppWebView]，可同步 Cookie 回 [HttpFetcher]，
/// 适合需要保留会话的场景（如源站登录态）。
void openInAppBrowser(BuildContext context, String url) {
  if (url.isEmpty || url.contains('{}')) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => HttpBrowserScreen(initialUrl: url),
    ),
  );
}

/// 将 "作者A, 作者B / 作者C" 这类多值字段拆成独立条目。
///
/// 用于把多位作者 / 导演 / 主演拆成多个可点击 chip，而不是塞进同一个框。
/// 分隔符：逗号（中英文）、顿号、斜杠、竖线、分号，分隔符后的空白会被忽略，
/// 因此 "A, B" 与 "A、B" 都能正确拆分，而 "Tom Hanks" 这类含空格的名字
/// 不会因空格被误拆。
List<String> splitMultiValue(String? raw) {
  if (raw == null || raw.isEmpty) return const <String>[];
  return raw
      .split(RegExp(r'[,，、/|;；]\s*'))
      .map((String e) => e.trim())
      .where((String e) => e.isNotEmpty)
      .toList();
}

/// 取剧集 / 章节列表中最新的 [Episode.updatedAt]。
///
/// 当源 detail 选择器没有声明 updatedAt 时，用最新一集/章的更新时间作为
/// 内容更新时间回退，让「更新时间」在更多源上显示，而不是只有显式提供
/// 内容级 updatedAt 的源才显示。
DateTime? latestEpisodeUpdatedAt(List<Episode> episodes) {
  DateTime? latest;
  for (final ep in episodes) {
    final dt = ep.updatedAt;
    if (dt == null) continue;
    if (latest == null || dt.isAfter(latest)) {
      latest = dt;
    }
  }
  return latest;
}
