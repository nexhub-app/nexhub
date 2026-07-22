/// 本地导入所需的运行时存储/媒体权限申请。
///
/// 实现 spec F2.C：Android 端在 file_picker 调用前申请 READ_MEDIA_*（13+）
/// 或 READ_EXTERNAL_STORAGE（<=12）；桌面 / iOS / Web 由 file_picker 原生文档选择器
/// 处理，无需运行时权限，直接返回 true。平台判定收敛到 [PlatformService]。
library;

import 'package:permission_handler/permission_handler.dart';

import '../platform/platform_service.dart';

/// 申请本地导入所需的权限。
///
/// 返回 true 表示可继续选文件（已获权限或当前平台无需申请）；
/// 返回 false 表示用户拒绝，调用方应弹 SnackBar `storagePermissionDenied`。
Future<bool> requestLocalImportPermission() async {
  if (!PlatformService.instance.isAndroid) {
    return true;
  }
  // file_picker 在 Android 走 SAF 文档选择器，本身不依赖 READ_MEDIA_* /
  // READ_EXTERNAL_STORAGE 运行时权限；此处仅 best-effort 申请以兼容个别机型，
  // 无论授予与否都放行，避免「点了导入却毫无反应」（修复「无法导入本地内容」）。
  try {
    await Permission.storage.request();
  } catch (_) {
    // 忽略授权异常
  }
  try {
    await Future.wait(<Future<PermissionStatus>>[
      Permission.photos.request(),
      Permission.videos.request(),
      Permission.audio.request(),
    ]);
  } catch (_) {
    // 忽略授权异常
  }
  return true;
}
