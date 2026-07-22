/// 调试记录本：把脚本解析每一步发生了什么记下来，供 UI 在列表为空时显示，
/// 方便不懂技术的用户直接截图发给开发者（无需 adb/logcat）。
library;

class ParseDiagnostics {
  /// 最近一次脚本解析的源 ID（用于判断诊断信息是否属于当前正在看的源）。
  static String? lastSourceId;

  /// 最近一次脚本解析的详细日志（多行）。
  static String? lastLog;

  /// 追加一行诊断。
  static void log(String sourceId, String line) {
    lastSourceId = sourceId;
    final ts = DateTime.now().toLocal().toString().substring(11, 19);
    lastLog = '${lastLog ?? ''}[$ts] $line\n';
    // 限制长度，避免无限增长
    if ((lastLog?.length ?? 0) > 2000) {
      lastLog = lastLog!.substring(lastLog!.length - 2000);
    }
  }

  /// 清空（切换源时调用，避免显示上一个源的旧信息）。
  static void clear() {
    lastSourceId = null;
    lastLog = null;
  }
}
