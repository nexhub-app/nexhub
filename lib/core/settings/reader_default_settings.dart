/// 阅读器默认设置模型（全局默认值，阅读时可临时覆盖）。
///
/// 持久化到 SharedPreferences（key: `reader_default_settings_v1`），
/// 复用 [PrefsBackend] 抽象以便测试注入。
library;

import 'dart:convert';

import '../comic/models/reader_preferences.dart';
import '../novel/novel_page_animation.dart';
import '../novel/novel_reader_preferences.dart';

/// 解析闪光颜色（容错：非法字符串回退黑）。
/// 注意：reader_preferences.dart 中的同名私有函数对本库不可见，这里本地实现一份。
ReaderFlashColor _parseFlashColor(Object? raw) {
  if (raw is String) {
    return ReaderFlashColor.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ReaderFlashColor.black,
    );
  }
  return ReaderFlashColor.black;
}

/// 阅读器默认方向。
enum ReaderOrientation { horizontal, vertical }

/// 阅读器默认背景色。
enum ReaderDefaultBackground { white, beige, dark }

/// 小说默认翻页动画（项 2）。
enum NovelPageTurnAnimation { fade, cover, slide, simulation, scroll, none }

/// 小说默认背景色（项 2）。
enum NovelBackground { white, cream, darkGray, black }

/// 小说默认简繁转换（项 2）。
enum NovelChineseConversion {
  none,
  traditionalToSimplified,
  simplifiedToTraditional
}

/// 漫画默认阅读方向（项 2）。
enum ComicReadingDirection { ltr, rtl, vertical, webtoon, webtoonWithGap }

/// 漫画默认点击区域布局（项 2，5 选 1）。
enum ComicTapZoneLayout { layout1, layout2, layout3, layout4, layout5 }

/// 漫画默认初始缩放（项 2）。
enum ComicInitialZoom { fitWidth, fitHeight, original }

/// 漫画默认双击缩放倍率（项 2）。
enum ComicDoubleTapZoom { x2, x3 }

/// 漫画默认滚轮方向（项 2）。
enum ComicScrollWheel { natural, inverted }

/// 阅读器默认设置。
class ReaderDefaultSettings {
  final ReadingMode readingMode;
  final ReaderDefaultBackground background;
  final ReaderOrientation orientation;
  final bool tapZoneEnabled;
  final bool doubleTapZoom;
  final bool orientationLock;
  final NovelPageTurnAnimation novelPageTurnAnimation;
  final double novelFontSize;
  final double novelLineHeight;
  final NovelBackground novelBackground;
  final double novelTtsSpeechRate;
  final NovelChineseConversion novelChineseConversion;
  final ComicReadingDirection comicReadingDirection;
  final ComicTapZoneLayout comicTapZoneLayout;
  final double comicSideMargin;
  final bool comicFlashEnabled;
  final int comicFlashTime;
  final int comicFlashInterval;
  final ReaderFlashColor comicFlashColor;
  final ComicInitialZoom comicInitialZoom;
  final ComicDoubleTapZoom comicDoubleTapZoom;
  final ComicScrollWheel comicScrollWheel;

  /// 漫画：打开阅读器时是否自动进入全屏。
  final bool comicFullscreen;

  /// 漫画：是否显示长按图片菜单。
  final bool comicShowLongPressMenu;

  /// 漫画：图片灰度滤镜开关。
  final bool comicGrayscale;

  /// 漫画：锁定防止缩小（缩到小于适配宽时回弹到适配宽）。
  final bool comicPreventShrink;

  /// 漫画：章节切换时显示过渡标题卡。
  final bool comicChapterTransition;

  // ── 小说补充（来自小说阅读面板，项 1）──
  final double novelParagraphSpacing;
  final double novelMargin;
  final bool novelShadow;
  final int novelBgPresetIndex;
  final TapZoneInvert novelTapZoneInvert;
  final NovelPageAnimation novelPageAnimation;

  // ── 漫画补充（来自漫画阅读面板，项 1）──
  final double comicFilterBrightness;
  final double comicFilterContrast;
  final double comicFilterColorTemp;
  final bool comicFilterInverted;
  final TapZoneInvert comicTapZoneInvert;

  /// 漫画：裁边（去除图片四周留白）。
  final bool comicCropEdge;

  /// 漫画：显示页码。
  final bool comicShowPageNumber;

  /// 漫画：进度条在右侧竖向显示。
  final bool comicProgressBarOnRight;

  /// 漫画：屏幕常亮（阻止息屏）。
  final bool comicKeepScreenOn;

  /// 漫画：页面旋转时强制横屏。
  final bool comicRotateLandscape;

  /// 漫画：双页拆分。
  final bool comicSplitDoublePage;

  /// 漫画：滤镜饱和度（范围 -1.0~1.0，0.0 为不变）。
  final double comicFilterSaturation;

  /// 漫画：滤镜色相旋转（范围 -1.0~1.0，0.0 为不变）。
  final double comicFilterHue;

  const ReaderDefaultSettings({
    this.readingMode = ReadingMode.singleLTR,
    this.background = ReaderDefaultBackground.white,
    this.orientation = ReaderOrientation.horizontal,
    this.tapZoneEnabled = true,
    this.doubleTapZoom = true,
    this.orientationLock = false,
    this.novelPageTurnAnimation = NovelPageTurnAnimation.fade,
    this.novelFontSize = 18.0,
    this.novelLineHeight = 1.5,
    this.novelBackground = NovelBackground.white,
    this.novelTtsSpeechRate = 1.0,
    this.novelChineseConversion = NovelChineseConversion.none,
    this.comicReadingDirection = ComicReadingDirection.ltr,
    this.comicTapZoneLayout = ComicTapZoneLayout.layout1,
    this.comicSideMargin = 0.0,
    this.comicFlashEnabled = false,
    this.comicFlashTime = 120,
    this.comicFlashInterval = 0,
    this.comicFlashColor = ReaderFlashColor.black,
    this.comicInitialZoom = ComicInitialZoom.fitWidth,
    this.comicDoubleTapZoom = ComicDoubleTapZoom.x2,
    this.comicScrollWheel = ComicScrollWheel.natural,
    this.comicFullscreen = true,
    this.comicShowLongPressMenu = true,
    this.comicGrayscale = false,
    this.comicPreventShrink = false,
    this.comicChapterTransition = false,
    this.novelParagraphSpacing = 16.0,
    this.novelMargin = 24.0,
    this.novelShadow = false,
    this.novelBgPresetIndex = 2,
    this.novelTapZoneInvert = TapZoneInvert.none,
    this.novelPageAnimation = NovelPageAnimation.slide,
    this.comicFilterBrightness = 0.0,
    this.comicFilterContrast = 0.0,
    this.comicFilterColorTemp = 0.0,
    this.comicFilterInverted = false,
    this.comicTapZoneInvert = TapZoneInvert.none,
    this.comicCropEdge = false,
    this.comicShowPageNumber = true,
    this.comicProgressBarOnRight = true,
    this.comicKeepScreenOn = false,
    this.comicRotateLandscape = false,
    this.comicSplitDoublePage = false,
    this.comicFilterSaturation = 0.0,
    this.comicFilterHue = 0.0,
  });

  ReaderDefaultSettings copyWith({
    ReadingMode? readingMode,
    ReaderDefaultBackground? background,
    ReaderOrientation? orientation,
    bool? tapZoneEnabled,
    bool? doubleTapZoom,
    bool? orientationLock,
    NovelPageTurnAnimation? novelPageTurnAnimation,
    double? novelFontSize,
    double? novelLineHeight,
    NovelBackground? novelBackground,
    double? novelTtsSpeechRate,
    NovelChineseConversion? novelChineseConversion,
    ComicReadingDirection? comicReadingDirection,
    ComicTapZoneLayout? comicTapZoneLayout,
    double? comicSideMargin,
    bool? comicFlashEnabled,
    int? comicFlashTime,
    int? comicFlashInterval,
    ReaderFlashColor? comicFlashColor,
    ComicInitialZoom? comicInitialZoom,
    ComicDoubleTapZoom? comicDoubleTapZoom,
    ComicScrollWheel? comicScrollWheel,
    bool? comicFullscreen,
    bool? comicShowLongPressMenu,
    bool? comicGrayscale,
    bool? comicPreventShrink,
    bool? comicChapterTransition,
    double? novelParagraphSpacing,
    double? novelMargin,
    bool? novelShadow,
    int? novelBgPresetIndex,
    TapZoneInvert? novelTapZoneInvert,
    NovelPageAnimation? novelPageAnimation,
    double? comicFilterBrightness,
    double? comicFilterContrast,
    double? comicFilterColorTemp,
    bool? comicFilterInverted,
    TapZoneInvert? comicTapZoneInvert,
    bool? comicCropEdge,
    bool? comicShowPageNumber,
    bool? comicProgressBarOnRight,
    bool? comicKeepScreenOn,
    bool? comicRotateLandscape,
    bool? comicSplitDoublePage,
    double? comicFilterSaturation,
    double? comicFilterHue,
  }) =>
      ReaderDefaultSettings(
        readingMode: readingMode ?? this.readingMode,
        background: background ?? this.background,
        orientation: orientation ?? this.orientation,
        tapZoneEnabled: tapZoneEnabled ?? this.tapZoneEnabled,
        doubleTapZoom: doubleTapZoom ?? this.doubleTapZoom,
        orientationLock: orientationLock ?? this.orientationLock,
        novelPageTurnAnimation:
            novelPageTurnAnimation ?? this.novelPageTurnAnimation,
        novelFontSize: novelFontSize ?? this.novelFontSize,
        novelLineHeight: novelLineHeight ?? this.novelLineHeight,
        novelBackground: novelBackground ?? this.novelBackground,
        novelTtsSpeechRate: novelTtsSpeechRate ?? this.novelTtsSpeechRate,
        novelChineseConversion:
            novelChineseConversion ?? this.novelChineseConversion,
        comicReadingDirection:
            comicReadingDirection ?? this.comicReadingDirection,
        comicTapZoneLayout: comicTapZoneLayout ?? this.comicTapZoneLayout,
        comicSideMargin: comicSideMargin ?? this.comicSideMargin,
        comicFlashEnabled: comicFlashEnabled ?? this.comicFlashEnabled,
        comicFlashTime: comicFlashTime ?? this.comicFlashTime,
        comicFlashInterval: comicFlashInterval ?? this.comicFlashInterval,
        comicFlashColor: comicFlashColor ?? this.comicFlashColor,
        comicInitialZoom: comicInitialZoom ?? this.comicInitialZoom,
        comicDoubleTapZoom: comicDoubleTapZoom ?? this.comicDoubleTapZoom,
        comicScrollWheel: comicScrollWheel ?? this.comicScrollWheel,
        comicFullscreen: comicFullscreen ?? this.comicFullscreen,
        comicShowLongPressMenu:
            comicShowLongPressMenu ?? this.comicShowLongPressMenu,
        comicGrayscale: comicGrayscale ?? this.comicGrayscale,
        comicPreventShrink: comicPreventShrink ?? this.comicPreventShrink,
        comicChapterTransition:
            comicChapterTransition ?? this.comicChapterTransition,
        novelParagraphSpacing:
            novelParagraphSpacing ?? this.novelParagraphSpacing,
        novelMargin: novelMargin ?? this.novelMargin,
        novelShadow: novelShadow ?? this.novelShadow,
        novelBgPresetIndex:
            novelBgPresetIndex ?? this.novelBgPresetIndex,
        novelTapZoneInvert:
            novelTapZoneInvert ?? this.novelTapZoneInvert,
        novelPageAnimation: novelPageAnimation ?? this.novelPageAnimation,
        comicFilterBrightness:
            comicFilterBrightness ?? this.comicFilterBrightness,
        comicFilterContrast:
            comicFilterContrast ?? this.comicFilterContrast,
        comicFilterColorTemp:
            comicFilterColorTemp ?? this.comicFilterColorTemp,
        comicFilterInverted:
            comicFilterInverted ?? this.comicFilterInverted,
        comicTapZoneInvert:
            comicTapZoneInvert ?? this.comicTapZoneInvert,
        comicCropEdge: comicCropEdge ?? this.comicCropEdge,
        comicShowPageNumber: comicShowPageNumber ?? this.comicShowPageNumber,
        comicProgressBarOnRight:
            comicProgressBarOnRight ?? this.comicProgressBarOnRight,
        comicKeepScreenOn: comicKeepScreenOn ?? this.comicKeepScreenOn,
        comicRotateLandscape:
            comicRotateLandscape ?? this.comicRotateLandscape,
        comicSplitDoublePage:
            comicSplitDoublePage ?? this.comicSplitDoublePage,
        comicFilterSaturation:
            comicFilterSaturation ?? this.comicFilterSaturation,
        comicFilterHue: comicFilterHue ?? this.comicFilterHue,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'readingMode': readingMode.name,
        'background': background.name,
        'orientation': orientation.name,
        'tapZoneEnabled': tapZoneEnabled,
        'doubleTapZoom': doubleTapZoom,
        'orientationLock': orientationLock,
        'novelPageTurnAnimation': novelPageTurnAnimation.name,
        'novelFontSize': novelFontSize,
        'novelLineHeight': novelLineHeight,
        'novelBackground': novelBackground.name,
        'novelTtsSpeechRate': novelTtsSpeechRate,
        'novelChineseConversion': novelChineseConversion.name,
        'comicReadingDirection': comicReadingDirection.name,
        'comicTapZoneLayout': comicTapZoneLayout.name,
        'comicSideMargin': comicSideMargin,
        'comicFlashEnabled': comicFlashEnabled,
        'comicFlashTime': comicFlashTime,
        'comicFlashInterval': comicFlashInterval,
        'comicFlashColor': comicFlashColor.name,
        'comicInitialZoom': comicInitialZoom.name,
        'comicDoubleTapZoom': comicDoubleTapZoom.name,
        'comicScrollWheel': comicScrollWheel.name,
        'comicFullscreen': comicFullscreen,
        'comicShowLongPressMenu': comicShowLongPressMenu,
        'comicGrayscale': comicGrayscale,
        'comicPreventShrink': comicPreventShrink,
        'comicChapterTransition': comicChapterTransition,
        'novelParagraphSpacing': novelParagraphSpacing,
        'novelMargin': novelMargin,
        'novelShadow': novelShadow,
        'novelBgPresetIndex': novelBgPresetIndex,
        'novelTapZoneInvert': novelTapZoneInvert.name,
        'novelPageAnimation': novelPageAnimation.name,
        'comicFilterBrightness': comicFilterBrightness,
        'comicFilterContrast': comicFilterContrast,
        'comicFilterColorTemp': comicFilterColorTemp,
        'comicFilterInverted': comicFilterInverted,
        'comicTapZoneInvert': comicTapZoneInvert.name,
        'comicCropEdge': comicCropEdge,
        'comicShowPageNumber': comicShowPageNumber,
        'comicProgressBarOnRight': comicProgressBarOnRight,
        'comicKeepScreenOn': comicKeepScreenOn,
        'comicRotateLandscape': comicRotateLandscape,
        'comicSplitDoublePage': comicSplitDoublePage,
        'comicFilterSaturation': comicFilterSaturation,
        'comicFilterHue': comicFilterHue,
      };

  factory ReaderDefaultSettings.fromJson(Map<String, dynamic> json) {
    ReadingMode mode = ReadingMode.singleLTR;
    if (json['readingMode'] is String) {
      mode = ReadingMode.values.firstWhere(
        (e) => e.name == json['readingMode'],
        orElse: () => ReadingMode.singleLTR,
      );
    }
    ReaderDefaultBackground bg = ReaderDefaultBackground.white;
    if (json['background'] is String) {
      bg = ReaderDefaultBackground.values.firstWhere(
        (e) => e.name == json['background'],
        orElse: () => ReaderDefaultBackground.white,
      );
    }
    ReaderOrientation orient = ReaderOrientation.horizontal;
    if (json['orientation'] is String) {
      orient = ReaderOrientation.values.firstWhere(
        (e) => e.name == json['orientation'],
        orElse: () => ReaderOrientation.horizontal,
      );
    }
    NovelPageTurnAnimation pageTurn = NovelPageTurnAnimation.fade;
    if (json['novelPageTurnAnimation'] is String) {
      pageTurn = NovelPageTurnAnimation.values.firstWhere(
        (e) => e.name == json['novelPageTurnAnimation'],
        orElse: () => NovelPageTurnAnimation.fade,
      );
    }
    NovelBackground novelBg = NovelBackground.white;
    if (json['novelBackground'] is String) {
      novelBg = NovelBackground.values.firstWhere(
        (e) => e.name == json['novelBackground'],
        orElse: () => NovelBackground.white,
      );
    }
    NovelChineseConversion chineseConv = NovelChineseConversion.none;
    if (json['novelChineseConversion'] is String) {
      chineseConv = NovelChineseConversion.values.firstWhere(
        (e) => e.name == json['novelChineseConversion'],
        orElse: () => NovelChineseConversion.none,
      );
    }
    ComicReadingDirection comicDir = ComicReadingDirection.ltr;
    if (json['comicReadingDirection'] is String) {
      comicDir = ComicReadingDirection.values.firstWhere(
        (e) => e.name == json['comicReadingDirection'],
        orElse: () => ComicReadingDirection.ltr,
      );
    }
    ComicTapZoneLayout comicTap = ComicTapZoneLayout.layout1;
    if (json['comicTapZoneLayout'] is String) {
      comicTap = ComicTapZoneLayout.values.firstWhere(
        (e) => e.name == json['comicTapZoneLayout'],
        orElse: () => ComicTapZoneLayout.layout1,
      );
    }
    ComicInitialZoom comicZoom = ComicInitialZoom.fitWidth;
    if (json['comicInitialZoom'] is String) {
      comicZoom = ComicInitialZoom.values.firstWhere(
        (e) => e.name == json['comicInitialZoom'],
        orElse: () => ComicInitialZoom.fitWidth,
      );
    }
    ComicDoubleTapZoom comicDoubleTap = ComicDoubleTapZoom.x2;
    if (json['comicDoubleTapZoom'] is String) {
      comicDoubleTap = ComicDoubleTapZoom.values.firstWhere(
        (e) => e.name == json['comicDoubleTapZoom'],
        orElse: () => ComicDoubleTapZoom.x2,
      );
    }
    ComicScrollWheel comicWheel = ComicScrollWheel.natural;
    if (json['comicScrollWheel'] is String) {
      comicWheel = ComicScrollWheel.values.firstWhere(
        (e) => e.name == json['comicScrollWheel'],
        orElse: () => ComicScrollWheel.natural,
      );
    }
    TapZoneInvert novelInvert = TapZoneInvert.none;
    if (json['novelTapZoneInvert'] is String) {
      novelInvert = TapZoneInvert.values.firstWhere(
        (e) => e.name == json['novelTapZoneInvert'],
        orElse: () => TapZoneInvert.none,
      );
    }
    NovelPageAnimation novelAnim = NovelPageAnimation.slide;
    if (json['novelPageAnimation'] is String) {
      novelAnim = NovelPageAnimation.values.firstWhere(
        (e) => e.name == json['novelPageAnimation'],
        orElse: () => NovelPageAnimation.slide,
      );
    }
    TapZoneInvert comicInvert = TapZoneInvert.none;
    if (json['comicTapZoneInvert'] is String) {
      comicInvert = TapZoneInvert.values.firstWhere(
        (e) => e.name == json['comicTapZoneInvert'],
        orElse: () => TapZoneInvert.none,
      );
    }
    return ReaderDefaultSettings(
      readingMode: mode,
      background: bg,
      orientation: orient,
      tapZoneEnabled: json['tapZoneEnabled'] as bool? ?? true,
      doubleTapZoom: json['doubleTapZoom'] as bool? ?? true,
      orientationLock: json['orientationLock'] as bool? ?? false,
      novelPageTurnAnimation: pageTurn,
      novelFontSize:
          (json['novelFontSize'] as num?)?.toDouble() ?? 18.0,
      novelLineHeight:
          (json['novelLineHeight'] as num?)?.toDouble() ?? 1.5,
      novelBackground: novelBg,
      novelTtsSpeechRate:
          (json['novelTtsSpeechRate'] as num?)?.toDouble() ?? 1.0,
      novelChineseConversion: chineseConv,
      comicReadingDirection: comicDir,
      comicTapZoneLayout: comicTap,
      comicSideMargin: (json['comicSideMargin'] as num?)?.toDouble() ?? 0.0,
      comicFlashEnabled: json['comicFlashEnabled'] as bool? ?? false,
      comicFlashTime: (json['comicFlashTime'] as num?)?.toInt() ?? 120,
      comicFlashInterval: (json['comicFlashInterval'] as num?)?.toInt() ?? 0,
      comicFlashColor: _parseFlashColor(json['comicFlashColor']),
      comicInitialZoom: comicZoom,
      comicDoubleTapZoom: comicDoubleTap,
      comicScrollWheel: comicWheel,
      comicFullscreen: json['comicFullscreen'] as bool? ?? true,
      comicShowLongPressMenu:
          json['comicShowLongPressMenu'] as bool? ?? true,
      comicGrayscale: json['comicGrayscale'] as bool? ?? false,
      comicPreventShrink: json['comicPreventShrink'] as bool? ?? false,
      comicChapterTransition:
          json['comicChapterTransition'] as bool? ?? false,
      novelParagraphSpacing:
          (json['novelParagraphSpacing'] as num?)?.toDouble() ?? 16.0,
      novelMargin: (json['novelMargin'] as num?)?.toDouble() ?? 24.0,
      novelShadow: json['novelShadow'] as bool? ?? false,
      novelBgPresetIndex: json['novelBgPresetIndex'] as int? ?? 2,
      novelTapZoneInvert: novelInvert,
      novelPageAnimation: novelAnim,
      comicFilterBrightness:
          (json['comicFilterBrightness'] as num?)?.toDouble() ?? 0.0,
      comicFilterContrast:
          (json['comicFilterContrast'] as num?)?.toDouble() ?? 0.0,
      comicFilterColorTemp:
          (json['comicFilterColorTemp'] as num?)?.toDouble() ?? 0.0,
      comicFilterInverted: json['comicFilterInverted'] as bool? ?? false,
      comicTapZoneInvert: comicInvert,
      comicCropEdge: json['comicCropEdge'] as bool? ?? false,
      comicShowPageNumber: json['comicShowPageNumber'] as bool? ?? true,
      comicProgressBarOnRight:
          json['comicProgressBarOnRight'] as bool? ?? true,
      comicKeepScreenOn: json['comicKeepScreenOn'] as bool? ?? false,
      comicRotateLandscape: json['comicRotateLandscape'] as bool? ?? false,
      comicSplitDoublePage: json['comicSplitDoublePage'] as bool? ?? false,
      comicFilterSaturation:
          (json['comicFilterSaturation'] as num?)?.toDouble() ?? 0.0,
      comicFilterHue: (json['comicFilterHue'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // ── 桥接：把全局默认映射为漫画运行时偏好（让设置页默认值在打开漫画时生效）──
  // 5 个 ComicTapZoneLayout 与 5 个 ReaderTapZoneLayout 一一对应
  // （历史上 layout1 曾对应已废弃的 defaultLayout，现已并入 lShape）。
  static const Map<ComicTapZoneLayout, ReaderTapZoneLayout>
      _comicTapZoneMap = <ComicTapZoneLayout, ReaderTapZoneLayout>{
    ComicTapZoneLayout.layout1: ReaderTapZoneLayout.lShape,
    ComicTapZoneLayout.layout2: ReaderTapZoneLayout.leftRight,
    ComicTapZoneLayout.layout3: ReaderTapZoneLayout.kindle,
    ComicTapZoneLayout.layout4: ReaderTapZoneLayout.bothSides,
    ComicTapZoneLayout.layout5: ReaderTapZoneLayout.off,
  };

  static const Map<ReaderDefaultBackground, ReaderBackgroundColor>
      _bgMap = <ReaderDefaultBackground, ReaderBackgroundColor>{
    ReaderDefaultBackground.white: ReaderBackgroundColor.white,
    ReaderDefaultBackground.beige: ReaderBackgroundColor.gray,
    ReaderDefaultBackground.dark: ReaderBackgroundColor.black,
  };

  static const Map<ComicInitialZoom, ReaderInitialZoom> _comicZoomMap =
      <ComicInitialZoom, ReaderInitialZoom>{
    ComicInitialZoom.fitWidth: ReaderInitialZoom.fitWidth,
    ComicInitialZoom.fitHeight: ReaderInitialZoom.fitHeight,
    ComicInitialZoom.original: ReaderInitialZoom.original,
  };

  static const Map<ComicDoubleTapZoom, double> _comicDoubleTapMap =
      <ComicDoubleTapZoom, double>{
    ComicDoubleTapZoom.x2: 2.0,
    ComicDoubleTapZoom.x3: 3.0,
  };

  static const Map<ComicScrollWheel, bool> _comicWheelMap =
      <ComicScrollWheel, bool>{
    ComicScrollWheel.natural: false,
    ComicScrollWheel.inverted: true,
  };

  ReaderPreferences toReaderPreferences() {
    return ReaderPreferences(
      readingMode: readingMode,
      doubleTapZoom: doubleTapZoom,
      orientation: orientation == ReaderOrientation.vertical
          ? ScreenOrientation.portrait
          : ScreenOrientation.landscape,
      background: _bgMap[background] ?? ReaderBackgroundColor.black,
      tapZoneLayout: _comicTapZoneMap[comicTapZoneLayout] ??
          ReaderTapZoneLayout.lShape,
      tapZoneInvert: comicTapZoneInvert,
      minScale: 1.0,
      maxScale: 4.0,
      filterBrightness: comicFilterBrightness,
      filterContrast: comicFilterContrast,
      filterColorTemp: comicFilterColorTemp,
      filterInverted: comicFilterInverted,
      sideMargin: comicSideMargin,
      flashEnabled: comicFlashEnabled,
      flashTime: comicFlashTime,
      flashInterval: comicFlashInterval,
      flashColor: comicFlashColor,
      initialZoom: _comicZoomMap[comicInitialZoom] ?? ReaderInitialZoom.fitWidth,
      doubleTapZoomScale: _comicDoubleTapMap[comicDoubleTapZoom] ?? 2.0,
      scrollWheelInverted: _comicWheelMap[comicScrollWheel] ?? false,
      fullscreen: comicFullscreen,
      showLongPressMenu: comicShowLongPressMenu,
      filterGrayscale: comicGrayscale,
      preventShrink: comicPreventShrink,
      showChapterTransition: comicChapterTransition,
      cropEdge: comicCropEdge,
      showPageNumber: comicShowPageNumber,
      progressBarOnRight: comicProgressBarOnRight,
      keepScreenOn: comicKeepScreenOn,
      rotateLandscape: comicRotateLandscape,
      splitDoublePage: comicSplitDoublePage,
      filterSaturation: comicFilterSaturation,
      filterHue: comicFilterHue,
    );
  }

  // ── 桥接：把全局默认映射为小说运行时偏好 ──
  NovelReaderPreferences toNovelReaderPreferences() {
    return NovelReaderPreferences(
      fontSize: novelFontSize,
      lineHeight: novelLineHeight,
      paragraphSpacing: novelParagraphSpacing,
      margin: novelMargin,
      bgPresetIndex: novelBgPresetIndex,
      shadow: novelShadow,
      pageAnimation: novelPageAnimation,
      chineseConvert: novelChineseConversion.name,
      tapZoneInvert: novelTapZoneInvert,
    );
  }
}

/// 阅读器默认设置持久化存储（key: `reader_default_settings_v1`）。
class ReaderDefaultSettingsStore {
  static const String _key = 'reader_default_settings_v1';

  final PrefsBackend _backend;

  ReaderDefaultSettingsStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  Future<ReaderDefaultSettings> load() async {
    final raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) return const ReaderDefaultSettings();
    try {
      return ReaderDefaultSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return const ReaderDefaultSettings();
    }
  }

  Future<void> save(ReaderDefaultSettings settings) async {
    await _backend.set(_key, jsonEncode(settings.toJson()));
  }
}
