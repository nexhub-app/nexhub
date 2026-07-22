/// 视频播放后端抽象。
///
/// 定义硬件解码、音频通道与画面比例等后端可调能力的统一接口，
/// 具体实现由 [MediaKitBackend]（基于 media_kit / mpv）提供。
abstract class VideoPlayerBackend {
  /// 设置硬件解码模式：auto/sw/hw/hw+。
  ///
  /// 默认实现抛出 [UnsupportedError]，子类按需覆写。
  Future<void> setHwdec(String mode) async {
    throw UnsupportedError('setHwdec is not supported by this backend');
  }

  /// 设置音频通道：auto/stereo/mono。
  ///
  /// 默认实现抛出 [UnsupportedError]，子类按需覆写。
  Future<void> setAudioChannel(String channel) async {
    throw UnsupportedError('setAudioChannel is not supported by this backend');
  }

  /// 设置画面比例：default/4:3/16:9/fill。
  ///
  /// 默认实现抛出 [UnsupportedError]，子类按需覆写。
  Future<void> setAspectRatio(String ratio) async {
    throw UnsupportedError('setAspectRatio is not supported by this backend');
  }

  /// 当前解码模式。
  String get currentHwdec;

  /// 当前音频通道。
  String get currentAudioChannel;

  /// 当前画面比例。
  String get currentAspectRatio;
}
