/// 弹幕字体大小预设（项 6）。
enum DanmakuFontSize { small, medium, large }

/// 弹幕滚动速度预设（项 6）。
enum DanmakuScrollSpeed { slow, medium, fast }

/// 弹幕显示区域预设（项 6）。
enum DanmakuDisplayArea { quarter, half, full }

/// 弹幕同屏数量上限预设（项 6）。
enum DanmakuMaxOnScreen { ten, twenty, fifty, hundred }

/// 弹幕设置模型。
class DanmakuSettings {
  const DanmakuSettings({
    this.filterKeywords = const <String>[],
    this.timeOffset = 0,
    this.area = 0.5,
    this.duration = 8,
    this.lineHeight = 1.2,
    this.hideTop = false,
    this.hideBottom = false,
    this.hideScroll = false,
    this.followPlaybackSpeed = false,
    this.fontSize = 16.0,
    this.opacity = 1.0,
    this.fontSizePreset = DanmakuFontSize.medium,
    this.scrollSpeed = DanmakuScrollSpeed.medium,
    this.displayArea = DanmakuDisplayArea.full,
    this.maxOnScreen = DanmakuMaxOnScreen.fifty,
    this.showOnTop = true,
    this.showOnBottom = true,
    this.showFull = true,
    this.blockedKeywords = '',
  });

  /// 关键词过滤（支持正则）。
  final List<String> filterKeywords;

  /// 时间偏移（秒）。
  final double timeOffset;

  /// 显示区域 0.1-1.0。
  final double area;

  /// 持续时间（秒）。
  final double duration;

  /// 行高。
  final double lineHeight;

  /// 隐藏顶部。
  final bool hideTop;

  /// 隐藏底部。
  final bool hideBottom;

  /// 隐藏滚动。
  final bool hideScroll;

  /// 跟随倍速。
  final bool followPlaybackSpeed;

  /// 字体大小（12-28）。
  final double fontSize;

  /// 不透明度（0.1-1.0）。
  final double opacity;

  /// 字体大小预设（项 6，小/中/大）。
  final DanmakuFontSize fontSizePreset;

  /// 滚动速度预设（项 6）。
  final DanmakuScrollSpeed scrollSpeed;

  /// 显示区域预设（项 6，1/4 / 半屏 / 全屏）。
  final DanmakuDisplayArea displayArea;

  /// 同屏数量上限预设（项 6）。
  final DanmakuMaxOnScreen maxOnScreen;

  /// 顶部显示开关（项 6，默认 true）。
  final bool showOnTop;

  /// 底部显示开关（项 6，默认 true）。
  final bool showOnBottom;

  /// 全屏显示开关（项 6，默认 true）。
  final bool showFull;

  /// 屏蔽关键词多行文本（项 6）。
  final String blockedKeywords;

  DanmakuSettings copyWith({
    List<String>? filterKeywords,
    double? timeOffset,
    double? area,
    double? duration,
    double? lineHeight,
    bool? hideTop,
    bool? hideBottom,
    bool? hideScroll,
    bool? followPlaybackSpeed,
    double? fontSize,
    double? opacity,
    DanmakuFontSize? fontSizePreset,
    DanmakuScrollSpeed? scrollSpeed,
    DanmakuDisplayArea? displayArea,
    DanmakuMaxOnScreen? maxOnScreen,
    bool? showOnTop,
    bool? showOnBottom,
    bool? showFull,
    String? blockedKeywords,
  }) =>
      DanmakuSettings(
        filterKeywords: filterKeywords ?? this.filterKeywords,
        timeOffset: timeOffset ?? this.timeOffset,
        area: area ?? this.area,
        duration: duration ?? this.duration,
        lineHeight: lineHeight ?? this.lineHeight,
        hideTop: hideTop ?? this.hideTop,
        hideBottom: hideBottom ?? this.hideBottom,
        hideScroll: hideScroll ?? this.hideScroll,
        followPlaybackSpeed: followPlaybackSpeed ?? this.followPlaybackSpeed,
        fontSize: fontSize ?? this.fontSize,
        opacity: opacity ?? this.opacity,
        fontSizePreset: fontSizePreset ?? this.fontSizePreset,
        scrollSpeed: scrollSpeed ?? this.scrollSpeed,
        displayArea: displayArea ?? this.displayArea,
        maxOnScreen: maxOnScreen ?? this.maxOnScreen,
        showOnTop: showOnTop ?? this.showOnTop,
        showOnBottom: showOnBottom ?? this.showOnBottom,
        showFull: showFull ?? this.showFull,
        blockedKeywords: blockedKeywords ?? this.blockedKeywords,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'filterKeywords': filterKeywords,
        'timeOffset': timeOffset,
        'area': area,
        'duration': duration,
        'lineHeight': lineHeight,
        'hideTop': hideTop,
        'hideBottom': hideBottom,
        'hideScroll': hideScroll,
        'followPlaybackSpeed': followPlaybackSpeed,
        'fontSize': fontSize,
        'opacity': opacity,
        'fontSizePreset': fontSizePreset.name,
        'scrollSpeed': scrollSpeed.name,
        'displayArea': displayArea.name,
        'maxOnScreen': maxOnScreen.name,
        'showOnTop': showOnTop,
        'showOnBottom': showOnBottom,
        'showFull': showFull,
        'blockedKeywords': blockedKeywords,
      };

  static DanmakuSettings fromJson(Map<String, dynamic> json) {
    final keywords = json['filterKeywords'];
    DanmakuFontSize fontSizePreset = DanmakuFontSize.medium;
    if (json['fontSizePreset'] is String) {
      fontSizePreset = DanmakuFontSize.values.firstWhere(
        (e) => e.name == json['fontSizePreset'],
        orElse: () => DanmakuFontSize.medium,
      );
    }
    DanmakuScrollSpeed scrollSpeed = DanmakuScrollSpeed.medium;
    if (json['scrollSpeed'] is String) {
      scrollSpeed = DanmakuScrollSpeed.values.firstWhere(
        (e) => e.name == json['scrollSpeed'],
        orElse: () => DanmakuScrollSpeed.medium,
      );
    }
    DanmakuDisplayArea displayArea = DanmakuDisplayArea.full;
    if (json['displayArea'] is String) {
      displayArea = DanmakuDisplayArea.values.firstWhere(
        (e) => e.name == json['displayArea'],
        orElse: () => DanmakuDisplayArea.full,
      );
    }
    DanmakuMaxOnScreen maxOnScreen = DanmakuMaxOnScreen.fifty;
    if (json['maxOnScreen'] is String) {
      maxOnScreen = DanmakuMaxOnScreen.values.firstWhere(
        (e) => e.name == json['maxOnScreen'],
        orElse: () => DanmakuMaxOnScreen.fifty,
      );
    }
    return DanmakuSettings(
      filterKeywords: keywords is List
          ? keywords.whereType<String>().toList(growable: false)
          : const <String>[],
      timeOffset: (json['timeOffset'] as num?)?.toDouble() ?? 0,
      area: (json['area'] as num?)?.toDouble() ?? 0.5,
      duration: (json['duration'] as num?)?.toDouble() ?? 8,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.2,
      hideTop: json['hideTop'] as bool? ?? false,
      hideBottom: json['hideBottom'] as bool? ?? false,
      hideScroll: json['hideScroll'] as bool? ?? false,
      followPlaybackSpeed: json['followPlaybackSpeed'] as bool? ?? false,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      fontSizePreset: fontSizePreset,
      scrollSpeed: scrollSpeed,
      displayArea: displayArea,
      maxOnScreen: maxOnScreen,
      showOnTop: json['showOnTop'] as bool? ?? true,
      showOnBottom: json['showOnBottom'] as bool? ?? true,
      showFull: json['showFull'] as bool? ?? true,
      blockedKeywords: json['blockedKeywords'] as String? ?? '',
    );
  }

  /// 实际持续时间（跟随倍速时 duration / playbackSpeed）。
  double effectiveDuration(double playbackSpeed) {
    if (followPlaybackSpeed && playbackSpeed > 0) {
      return duration / playbackSpeed;
    }
    return duration;
  }

  /// 过滤弹幕（关键词 + 正则）。
  ///
  /// 返回 true 表示该弹幕应被过滤掉。
  bool shouldFilter(String text) {
    for (final keyword in filterKeywords) {
      if (keyword.isEmpty) continue;
      try {
        final regex = RegExp(keyword);
        if (regex.hasMatch(text)) return true;
      } on Object {
        if (text.contains(keyword)) return true;
      }
    }
    return false;
  }
}
