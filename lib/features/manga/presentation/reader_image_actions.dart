import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';
// flutter_cache_manager 是 cached_network_image 的传递依赖，此处直接使用
// 其 DefaultCacheManager 以获取图片缓存文件，无需新增 pubspec 依赖。
// ignore: depend_on_referenced_packages
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../core/favorites/favorites_manager.dart';
import '../../../core/models/plugin_config.dart';

/// 长按漫画图片时弹出的「设为封面 / 保存 / 分享」菜单。
///
/// 设为封面：将图片 URL 复制到剪贴板并提示用户去详情页粘贴（简易方案，
/// 完整方案需持久化到 ComicBookmarkManager，后续按需扩展）。
/// 保存：从 [DefaultCacheManager] 取出图片（缓存未命中则触发下载，携带
/// 防盗链 headers），复制到应用文档目录的 `reader_images/` 子目录。
/// 分享：`share_plus` 未在 pubspec 中声明依赖，回退为将图片本地路径
/// 复制到剪贴板，由用户自行粘贴到目标应用。
Future<void> showReaderImageActions({
  required BuildContext context,
  required String url,
  PluginConfig? source,
  required String comicId,
  required SourceType sourceType,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final ColorScheme scheme = Theme.of(context).colorScheme;

  await showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: Icon(Icons.image_outlined, color: scheme.primary),
            title: Text(l10n.setAsCover),
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(_setAsCover(context, url, comicId, sourceType));
            },
          ),
          ListTile(
            leading: Icon(Icons.copy_outlined, color: scheme.primary),
            title: Text(l10n.copyImage),
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(_copyImage(context, url, source));
            },
          ),
          ListTile(
            leading: Icon(Icons.download_outlined, color: scheme.primary),
            title: Text(l10n.saveImage),
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(_saveImage(context, url, source));
            },
          ),
          ListTile(
            leading: Icon(Icons.share_outlined, color: scheme.primary),
            title: Text(l10n.shareImage),
            onTap: () {
              Navigator.of(ctx).pop();
              unawaited(_shareImage(context, url, source));
            },
          ),
          ListTile(
            leading:
                Icon(Icons.close, color: scheme.onSurfaceVariant),
            title: Text(l10n.cancel),
            onTap: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    ),
  );
}

/// 将当前页图片真正设为书架封面：调用 [FavoritesManager.updateCover] 持久化。
Future<void> _setAsCover(
  BuildContext context,
  String url,
  String comicId,
  SourceType sourceType,
) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  try {
    final fav = context.read<FavoritesManager>();
    final ok = await fav.updateCover(comicId, sourceType, url);
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? l10n.coverUpdated : l10n.coverUpdateFailed)),
    );
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(l10n.coverUpdateFailed)));
  }
}

/// 复制图片二进制到系统剪贴板（跨平台真复制，依赖 super_clipboard）。
///
/// [SystemClipboard] 不可用时（部分平台 / 测试环境）回退为复制本地路径。
Future<void> _copyImage(
  BuildContext context,
  String url,
  PluginConfig? source,
) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final File? file = await _resolveImageFile(url, source);
  if (file == null) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.imageLoadFailed)));
    return;
  }
  try {
    final Uint8List bytes = await file.readAsBytes();
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      // 平台不支持剪贴板图片：回退为复制本地路径。
      await Clipboard.setData(ClipboardData(text: file.path));
      messenger.showSnackBar(SnackBar(content: Text(l10n.imagePathCopied)));
      return;
    }
    final item = DataWriterItem();
    final ext = _pickExt(url).toLowerCase();
    if (ext == '.jpg' || ext == '.jpeg') {
      item.add(Formats.jpeg(bytes));
    } else {
      item.add(Formats.png(bytes));
    }
    await clipboard.write(<DataWriterItem>[item]);
    messenger.showSnackBar(SnackBar(content: Text(l10n.copyImageSuccess)));
  } on Object {
    // 复制失败：回退为复制本地路径，保证菜单项「有反应」。
    await Clipboard.setData(ClipboardData(text: file.path));
    messenger.showSnackBar(SnackBar(content: Text(l10n.copyImageFailed)));
  }
}

/// 构造与 [SourceImage] 一致的防盗链 headers。
Map<String, String>? _buildHeaders(PluginConfig? source) {
  final AntiHotlinkingConfig? ah = source?.antiHotlinking;
  final SiteConfig? site = source?.site;
  final Map<String, String>? ahHeaders = ah?.headers;
  final Map<String, String>? siteHeaders = site?.headers;
  final String? referer = ah?.referer;
  final String? ua = site?.userAgent;
  final String? cookies = site?.cookies;
  final bool hasFields = (siteHeaders != null && siteHeaders.isNotEmpty) ||
      (ahHeaders != null && ahHeaders.isNotEmpty) ||
      (referer != null && referer.isNotEmpty) ||
      (ua != null && ua.isNotEmpty) ||
      (cookies != null && cookies.isNotEmpty);
  if (!hasFields) return null;
  final Map<String, String> m = <String, String>{};
  if (ahHeaders != null) m.addAll(ahHeaders);
  if (siteHeaders != null) m.addAll(siteHeaders);
  if (referer != null && referer.isNotEmpty) {
    m['Referer'] = referer;
  }
  if (ua != null && ua.isNotEmpty) {
    m['User-Agent'] = ua;
  }
  if (cookies != null && cookies.isNotEmpty) {
    m['Cookie'] = cookies;
  }
  return m;
}

/// 解析图片本地文件：HTTP URL 走缓存管理器（必要时下载），本地路径直接返回。
Future<File?> _resolveImageFile(String url, PluginConfig? source) async {
  if (url.startsWith('http://') || url.startsWith('https://')) {
    try {
      return await DefaultCacheManager()
          .getSingleFile(url, headers: _buildHeaders(source));
    } on Object {
      return null;
    }
  }
  final File f = File(url);
  return await f.exists() ? f : null;
}

/// 取 URL 路径中的扩展名，缺省回退到 .jpg。
String _pickExt(String url) {
  final String ext = p.extension(url.split('?').first).toLowerCase();
  if (ext.isEmpty) return '.jpg';
  return ext;
}

Future<void> _saveImage(
  BuildContext context,
  String url,
  PluginConfig? source,
) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final File? file = await _resolveImageFile(url, source);
  if (file == null) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.imageLoadFailed)));
    return;
  }
  try {
    final Directory dir = await getApplicationDocumentsDirectory();
    final String name =
        '${DateTime.now().millisecondsSinceEpoch}${_pickExt(url)}';
    final String dest = p.join(dir.path, 'reader_images', name);
    await Directory(p.dirname(dest)).create(recursive: true);
    await file.copy(dest);
    messenger.showSnackBar(SnackBar(content: Text(l10n.imageSavedTo(dest))));
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(l10n.imageSaveFailed)));
  }
}

Future<void> _shareImage(
  BuildContext context,
  String url,
  PluginConfig? source,
) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final File? file = await _resolveImageFile(url, source);
  if (file == null) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.imageLoadFailed)));
    return;
  }
  // share_plus 未引入依赖，回退为复制本地路径到剪贴板。
  await Clipboard.setData(ClipboardData(text: file.path));
  messenger.showSnackBar(SnackBar(content: Text(l10n.imagePathCopied)));
}
