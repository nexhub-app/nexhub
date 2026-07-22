import 'package:cast/cast.dart';

/// 真实 Chromecast 投屏服务（基于纯 Dart 的 cast 包，无需 Google Cast SDK）。
///
/// 流程：发现设备 -> 建立会话 -> 启动媒体接收器(CC1AD845) -> 发送 LOAD 播放视频地址。
/// 全程 try/catch 降级，避免投屏异常影响本地播放。
class CastService {
  CastSession? _session;
  CastDevice? _device;

  bool get isCasting => _session != null;
  String? get deviceName => _device?.name;

  /// 发现局域网内的 Chromecast 设备。
  Future<List<CastDevice>> discover() => CastDiscoveryService().search();

  /// 连接设备并投屏播放指定视频地址。
  Future<void> connectAndPlay(
    CastDevice device,
    String url, {
    String title = '',
  }) async {
    final CastSession session =
        await CastSessionManager().startSession(device);
    _session = session;
    _device = device;

    var messageIndex = 0;
    session.messageStream.listen((_) {
      messageIndex += 1;
      // 接收器就绪后（收到第 2 条状态消息）再发送 LOAD。
      if (messageIndex == 2) {
        Future<void>.delayed(const Duration(seconds: 2)).then((_) {
          _sendLoad(session, url, title);
        });
      }
    });
    session.stateStream.listen((_) {});

    session.sendMessage(CastSession.kNamespaceReceiver, <String, String>{
      'type': 'LAUNCH',
      'appId': 'CC1AD845',
    });
  }

  void _sendLoad(CastSession session, String url, String title) {
    try {
      session.sendMessage(CastSession.kNamespaceMedia, <String, dynamic>{
        'type': 'LOAD',
        'autoPlay': true,
        'currentTime': 0,
        'media': <String, dynamic>{
          'contentId': url,
          'contentType': _contentTypeForUrl(url),
          'streamType': 'BUFFERED',
          'metadata': <String, dynamic>{
            'type': 0,
            'metadataType': 0,
            'title': title,
          },
        },
      });
    } on Object {
      // 发送失败静默忽略。
    }
  }

  String _contentTypeForUrl(String url) {
    final String lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return 'application/vnd.apple.mpegurl';
    if (lower.contains('.mpd')) return 'application/dash+xml';
    if (lower.contains('.webm')) return 'video/webm';
    if (lower.contains('.mp3') ||
        lower.contains('.m4a') ||
        lower.contains('.aac')) {
      return 'audio/mp4';
    }
    return 'video/mp4';
  }

  /// 断开投屏。
  ///
  /// 用 dynamic 调用 endSession 以兼容不同版本（方法名可能不同），
  /// 失败时静默忽略，不影响本地播放。
  Future<void> disconnect() async {
    final CastSession? session = _session;
    _session = null;
    _device = null;
    if (session == null) return;
    try {
      await (session as dynamic).endSession();
    } on Object {
      // 某些版本无 endSession，忽略。
    }
  }
}
