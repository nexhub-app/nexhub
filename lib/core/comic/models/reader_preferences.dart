/// 阅读器偏好模型（漫画 / 小说共用）。
///
/// 仅承载「阅读模式 / 方向 / 背景 / 点击区域布局 / 双击缩放」等设置，
/// 颜色以索引形式引用 [ReaderTokens] 预设，绝不在此硬编码 [Color]（治理规则）。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/reader_tokens.dart';

/// 漫画 5 种阅读模式（文档 7.1 最终态，移除旧 double）。
enum ReadingMode {
  singleLTR,
  singleRTL,
  singleVertical,
  webtoon,
  webtoonWithGap;

  /// 是否为连续纵向滚动（webtoon / webtoonWithGap）。
  bool get isWebtoon =>
      this == ReadingMode.webtoon || this == ReadingMode.webtoonWithGap;

  /// 是否为单页翻页（横向/竖向）。
  bool get isPaged => !isWebtoon;

  String l10nKey() => switch (this) {
        ReadingMode.singleLTR => 'readerModeSingleLTR',
        ReadingMode.singleRTL => 'readerModeSingleRTL',
        ReadingMode.singleVertical => 'readerModeSingleVertical',
        ReadingMode.webtoon => 'readerModeWebtoon',
        ReadingMode.webtoonWithGap => 'readerModeWebtoonWithGap',
      };
}

/// 屏幕方向（文档 7.2，替代旧 lockLandscape:bool）。
enum ScreenOrientation {
  defaultMode,
  followSystem,
  portrait,
  landscape,
  lockPortrait,
  lockLandscape,
  reversePortrait;

  String l10nKey() => switch (this) {
        ScreenOrientation.defaultMode => 'readerOrientationDefault',
        ScreenOrientation.followSystem => 'readerOrientationSystem',
        ScreenOrientation.portrait => 'readerOrientationPortrait',
        ScreenOrientation.landscape => 'readerOrientationLandscape',
        ScreenOrientation.lockPortrait => 'readerOrientationLockPortrait',
        ScreenOrientation.lockLandscape => 'readerOrientationLockLandscape',
        ScreenOrientation.reversePortrait => 'readerOrientationReversePortrait',
      };
}

/// 阅读器背景（黑 / 灰 / 白 / 自动）。
enum ReaderBackgroundColor {
  black,
  gray,
  white,
  auto;

  /// 解析为实际颜色索引（auto 回退到白色，由外部结合 brightness 处理）。
  int toPresetIndex() => switch (this) {
        ReaderBackgroundColor.black => 0,
        ReaderBackgroundColor.gray => 1,
        ReaderBackgroundColor.white => 2,
        ReaderBackgroundColor.auto => 2,
      };

  static ReaderBackgroundColor fromIndex(int index) => switch (index) {
        0 => ReaderBackgroundColor.black,
        1 => ReaderBackgroundColor.gray,
        _ => ReaderBackgroundColor.white,
      };

  String l10nKey() => switch (this) {
        ReaderBackgroundColor.black => 'readerBgBlack',
        ReaderBackgroundColor.gray => 'readerBgGray',
        ReaderBackgroundColor.white => 'readerBgWhite',
        ReaderBackgroundColor.auto => 'readerBgAuto',
      };
}

/// 点击区域布局（文档 7.3）。
///
/// 历史上曾有 `defaultLayout`（左 45% prev / 中 10% toggle / 右 45% next），
/// 其几何已并入新的 `leftRight` 布局；`lShape` 成为新的默认布局
/// （用户决策：最终 5 布局 = L形(默认)/kindle/两侧/左右/关闭）。
/// 故枚举只有 5 个值；任何旧数据里 `defaultLayout` 字符串在 [ReaderPreferences.fromJson]
/// 会回退到 `lShape`。
enum ReaderTapZoneLayout {
  /// L 形（默认）：左上=上一页，右下=下一页，其余=切换控件。
  lShape,

  /// 左右：左 45% = 上一页，右 45% = 下一页，中间 10% 条 = 切换控件。
  leftRight,

  /// Kindle：左 35%=上，右 65%=下，上 15% 留空。
  kindle,

  /// 两侧：中上留空、左右=下、中下=上。
  bothSides,

  /// 关闭：整屏点击=切换控件，无翻页热区。
  off;

  String l10nKey() => switch (this) {
        ReaderTapZoneLayout.lShape => 'readerTapLShape',
        ReaderTapZoneLayout.leftRight => 'readerTapLeftRight',
        ReaderTapZoneLayout.kindle => 'readerTapKindle',
        ReaderTapZoneLayout.bothSides => 'readerTapBothSides',
        ReaderTapZoneLayout.off => 'readerTapOff',
      };
}

/// 点击区域方向反转（16.5 表「点击分区 5 布局 + 反色」）。
///
/// 在 [ReaderTapZoneLayout] 选定的布局之上，对 prev/next 命中再做一层方向
/// 反转，适配左撇子或特殊阅读习惯。竖向 webtoon 模式下 `leftRight` 不生效
/// （条漫本就是上下滚动），`upDown` 反转滚动方向。
enum TapZoneInvert {
  /// 不反转。
  none,

  /// 左右反转：prev ↔ next 互换（竖向模式不生效）。
  leftRight,

  /// 上下反转：仅对竖向滚动（webtoon）生效，反向滚动。
  upDown,

  /// 全反转：左右 + 上下都反转。
  all;

  String l10nKey() => switch (this) {
        TapZoneInvert.none => 'readerTapInvertNone',
        TapZoneInvert.leftRight => 'readerTapInvertLeftRight',
        TapZoneInvert.upDown => 'readerTapInvertUpDown',
        TapZoneInvert.all => 'readerTapInvertAll',
      };
}

/// 翻页闪光颜色（漫画阅读器「翻页闪光」设置）。
enum ReaderFlashColor {
  /// 黑屏闪。
  black,

  /// 白屏闪。
  white,

  /// 先黑后白（两段连续闪）。
  blackWhite;

  String l10nKey() => switch (this) {
        ReaderFlashColor.black => 'readerFlashBlack',
        ReaderFlashColor.white => 'readerFlashWhite',
        ReaderFlashColor.blackWhite => 'readerFlashBlackWhite',
      };
}

/// 初始缩放（漫画阅读器「初始缩放」设置）。
enum ReaderInitialZoom {
  /// 适配宽度：图片宽度撑满屏幕宽度（长条漫画常用）。
  fitWidth,

  /// 适配高度：图片高度撑满屏幕高度（单页漫画常用）。
  fitHeight,

  /// 原始大小：按图片真实像素 1:1 显示。
  original;

  String l10nKey() => switch (this) {
        ReaderInitialZoom.fitWidth => 'readerZoomFitWidth',
        ReaderInitialZoom.fitHeight => 'readerZoomFitHeight',
        ReaderInitialZoom.original => 'readerZoomOriginal',
      };
}

/// 解析初始缩放（容错：非法字符串回退 fitWidth）。
ReaderInitialZoom _parseInitialZoom(Object? raw) {
  if (raw is String) {
    return ReaderInitialZoom.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ReaderInitialZoom.fitWidth,
    );
  }
  return ReaderInitialZoom.fitWidth;
}

/// 解析闪光颜色（容错：非法字符串回退黑）。
ReaderFlashColor _parseFlashColor(Object? raw) {
  if (raw is String) {
    return ReaderFlashColor.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => ReaderFlashColor.black,
    );
  }
  return ReaderFlashColor.black;
}

/// 阅读器偏好（按作品持久化）。
class ReaderPreferences {
  final ReadingMode readingMode;
  final bool doubleTapZoom;
  final ScreenOrientation orientation;
  final ReaderBackgroundColor background;
  final ReaderTapZoneLayout tapZoneLayout;
  final TapZoneInvert tapZoneInvert;
  final double minScale;
  final double maxScale;

  /// 图片滤镜：亮度 / 对比度 / 色温，范围 -1.0~1.0，0.0 为不变。
  /// 用 4x5 颜色矩阵实时合成，见 reader_image_filter.dart。
  final double filterBrightness;
  final double filterContrast;
  final double filterColorTemp;

  /// 图片滤镜：饱和度，范围 -1.0~1.0，0.0 为不变；-1 退化为灰度。
  final double filterSaturation;

  /// 图片滤镜：色相旋转，范围 -1.0~1.0，映射到 -180°~180°；0.0 为不变。
  final double filterHue;

  /// 图片反色滤镜（雷区 11）：用 `ColorFilter.mode(Colors.white, BlendMode.difference)`
  /// 实现，避免 matrix 方案在桌面端变全黑的 bug。true 时叠加反色层。
  final bool filterInverted;

  /// 裁边（去除漫画图四周留白，简单版用 BoxFit.cover/居中裁切）。
  final bool cropEdge;

  /// 显示页码（底栏页码 indicator 开关）。
  final bool showPageNumber;

  /// 进度条在右侧竖向显示（false 时改为底部横向）。
  final bool progressBarOnRight;

  /// 屏幕常亮（wakelock_plus：true 时阻止息屏）。
  final bool keepScreenOn;

  /// 单页旋转时强制横屏（与图片旋转 quarterTurns 解耦）。
  final bool rotateLandscape;

  /// 双页拆分（占位字段，精细拼页逻辑属 P2）。
  final bool splitDoublePage;

  /// 左右留白（页面左右内边距），取值范围 0.0~0.5，表示占屏幕宽度的比例。
  /// 0 = 无边距；渲染时在图片左右各加 sideMargin * 屏宽 的留白。
  final double sideMargin;

  /// 翻页闪光开关（翻页时屏幕闪一下，缓解长条 / 翻页的视觉跳变）。
  final bool flashEnabled;

  /// 闪光时长（毫秒），仅 [flashEnabled] 时生效。
  final int flashTime;

  /// 闪光延迟（毫秒）：翻页后延迟多久才闪（0 = 立即）。
  final int flashInterval;

  /// 闪光颜色（黑 / 白 / 黑→白）。
  final ReaderFlashColor flashColor;

  /// 初始缩放（fitWidth / fitHeight / original）。
  final ReaderInitialZoom initialZoom;

  /// 打开阅读器时是否自动进入全屏（沉浸式隐藏系统栏）。
  final bool fullscreen;

  /// 是否显示长按图片弹出的菜单（设为封面 / 复制图片等）。
  final bool showLongPressMenu;

  /// 图片灰度滤镜：去色显示，适合彩色漫画转黑白阅读。
  final bool filterGrayscale;

  /// 是否锁定「防止缩小」：缩放到小于适配宽度时回弹到适配宽度（仍可放大）。
  final bool preventShrink;

  /// 是否在章节切换时显示「章节过渡标题卡」。
  final bool showChapterTransition;

  /// 双击缩放的目标倍率（2.0 / 3.0）。
  final double doubleTapZoomScale;

  /// 滚轮缩放方向是否反转（false = 上滚放大；true = 上滚缩小，类天然反向滚动）。
  final bool scrollWheelInverted;

  const ReaderPreferences({
    this.readingMode = ReadingMode.singleLTR,
    this.doubleTapZoom = true,
    this.orientation = ScreenOrientation.defaultMode,
    this.background = ReaderBackgroundColor.black,
    this.tapZoneLayout = ReaderTapZoneLayout.lShape,
    this.tapZoneInvert = TapZoneInvert.none,
    this.minScale = 1.0,
    this.maxScale = 4.0,
    this.filterBrightness = 0.0,
    this.filterContrast = 0.0,
    this.filterColorTemp = 0.0,
    this.filterSaturation = 0.0,
    this.filterHue = 0.0,
    this.filterInverted = false,
    this.cropEdge = false,
    this.showPageNumber = true,
    this.progressBarOnRight = true,
    this.keepScreenOn = false,
    this.rotateLandscape = false,
    this.splitDoublePage = false,
    this.sideMargin = 0.0,
    this.flashEnabled = false,
    this.flashTime = 120,
    this.flashInterval = 0,
    this.flashColor = ReaderFlashColor.black,
    this.initialZoom = ReaderInitialZoom.fitWidth,
    this.fullscreen = true,
    this.showLongPressMenu = true,
    this.filterGrayscale = false,
    this.preventShrink = false,
    this.showChapterTransition = false,
    this.doubleTapZoomScale = 2.0,
    this.scrollWheelInverted = false,
  });

  /// 滤镜是否为默认值（各轴均为 0 且不反色/不灰度），用于跳过无谓的 ColorFiltered 图层。
  bool get filterIsIdentity =>
      filterBrightness == 0.0 &&
      filterContrast == 0.0 &&
      filterColorTemp == 0.0 &&
      filterSaturation == 0.0 &&
      filterHue == 0.0 &&
      !filterInverted &&
      !filterGrayscale;

  factory ReaderPreferences.fromJson(Map<String, dynamic> json) {
    ReadingMode mode = ReadingMode.singleLTR;
    if (json['readingMode'] is String) {
      mode = ReadingMode.values.firstWhere(
        (e) => e.name == json['readingMode'],
        orElse: () => ReadingMode.singleLTR,
      );
    }
    ScreenOrientation orient = ScreenOrientation.defaultMode;
    if (json['orientation'] is String) {
      orient = ScreenOrientation.values.firstWhere(
        (e) => e.name == json['orientation'],
        orElse: () => ScreenOrientation.defaultMode,
      );
    }
    ReaderBackgroundColor bg = ReaderBackgroundColor.black;
    if (json['background'] is String) {
      bg = ReaderBackgroundColor.values.firstWhere(
        (e) => e.name == json['background'],
        orElse: () => ReaderBackgroundColor.black,
      );
    }
    ReaderTapZoneLayout tap = ReaderTapZoneLayout.lShape;
    if (json['tapZoneLayout'] is String) {
      tap = ReaderTapZoneLayout.values.firstWhere(
        (e) => e.name == json['tapZoneLayout'],
        orElse: () => ReaderTapZoneLayout.lShape,
      );
    }
    TapZoneInvert invert = TapZoneInvert.none;
    if (json['tapZoneInvert'] is String) {
      invert = TapZoneInvert.values.firstWhere(
        (e) => e.name == json['tapZoneInvert'],
        orElse: () => TapZoneInvert.none,
      );
    }
    return ReaderPreferences(
      readingMode: mode,
      doubleTapZoom: json['doubleTapZoom'] as bool? ?? true,
      orientation: orient,
      background: bg,
      tapZoneLayout: tap,
      tapZoneInvert: invert,
      minScale: (json['minScale'] as num?)?.toDouble() ?? 1.0,
      maxScale: (json['maxScale'] as num?)?.toDouble() ?? 4.0,
      filterBrightness:
          (json['filterBrightness'] as num?)?.toDouble() ?? 0.0,
      filterContrast: (json['filterContrast'] as num?)?.toDouble() ?? 0.0,
      filterColorTemp: (json['filterColorTemp'] as num?)?.toDouble() ?? 0.0,
      filterSaturation:
          (json['filterSaturation'] as num?)?.toDouble() ?? 0.0,
      filterHue: (json['filterHue'] as num?)?.toDouble() ?? 0.0,
      filterInverted: json['filterInverted'] as bool? ?? false,
      cropEdge: json['cropEdge'] as bool? ?? false,
      showPageNumber: json['showPageNumber'] as bool? ?? true,
      progressBarOnRight: json['progressBarOnRight'] as bool? ?? true,
      keepScreenOn: json['keepScreenOn'] as bool? ?? false,
      rotateLandscape: json['rotateLandscape'] as bool? ?? false,
      splitDoublePage: json['splitDoublePage'] as bool? ?? false,
      sideMargin: (json['sideMargin'] as num?)?.toDouble() ?? 0.0,
      flashEnabled: json['flashEnabled'] as bool? ?? false,
      flashTime: (json['flashTime'] as num?)?.toInt() ?? 120,
      flashInterval: (json['flashInterval'] as num?)?.toInt() ?? 0,
      flashColor: _parseFlashColor(json['flashColor']),
      initialZoom: _parseInitialZoom(json['initialZoom']),
      fullscreen: json['fullscreen'] as bool? ?? true,
      showLongPressMenu: json['showLongPressMenu'] as bool? ?? true,
      filterGrayscale: json['filterGrayscale'] as bool? ?? false,
      preventShrink: json['preventShrink'] as bool? ?? false,
      showChapterTransition: json['showChapterTransition'] as bool? ?? false,
      doubleTapZoomScale:
          (json['doubleTapZoomScale'] as num?)?.toDouble() ?? 2.0,
      scrollWheelInverted: json['scrollWheelInverted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'readingMode': readingMode.name,
        'doubleTapZoom': doubleTapZoom,
        'orientation': orientation.name,
        'background': background.name,
        'tapZoneLayout': tapZoneLayout.name,
        'tapZoneInvert': tapZoneInvert.name,
        'minScale': minScale,
        'maxScale': maxScale,
        'filterBrightness': filterBrightness,
        'filterContrast': filterContrast,
        'filterColorTemp': filterColorTemp,
        'filterSaturation': filterSaturation,
        'filterHue': filterHue,
        'filterInverted': filterInverted,
        'cropEdge': cropEdge,
        'showPageNumber': showPageNumber,
        'progressBarOnRight': progressBarOnRight,
        'keepScreenOn': keepScreenOn,
        'rotateLandscape': rotateLandscape,
        'splitDoublePage': splitDoublePage,
        'sideMargin': sideMargin,
        'flashEnabled': flashEnabled,
        'flashTime': flashTime,
        'flashInterval': flashInterval,
        'flashColor': flashColor.name,
        'initialZoom': initialZoom.name,
        'fullscreen': fullscreen,
        'showLongPressMenu': showLongPressMenu,
        'filterGrayscale': filterGrayscale,
        'preventShrink': preventShrink,
        'showChapterTransition': showChapterTransition,
        'doubleTapZoomScale': doubleTapZoomScale,
        'scrollWheelInverted': scrollWheelInverted,
      };

  ReaderPreferences copyWith({
    ReadingMode? readingMode,
    bool? doubleTapZoom,
    ScreenOrientation? orientation,
    ReaderBackgroundColor? background,
    ReaderTapZoneLayout? tapZoneLayout,
    TapZoneInvert? tapZoneInvert,
    double? minScale,
    double? maxScale,
    double? filterBrightness,
    double? filterContrast,
    double? filterColorTemp,
    double? filterSaturation,
    double? filterHue,
    bool? filterInverted,
    bool? cropEdge,
    bool? showPageNumber,
    bool? progressBarOnRight,
    bool? keepScreenOn,
    bool? rotateLandscape,
    bool? splitDoublePage,
    double? sideMargin,
    bool? flashEnabled,
    int? flashTime,
    int? flashInterval,
    ReaderFlashColor? flashColor,
    ReaderInitialZoom? initialZoom,
    bool? fullscreen,
    bool? showLongPressMenu,
    bool? filterGrayscale,
    bool? preventShrink,
    bool? showChapterTransition,
    double? doubleTapZoomScale,
    bool? scrollWheelInverted,
  }) =>
      ReaderPreferences(
        readingMode: readingMode ?? this.readingMode,
        doubleTapZoom: doubleTapZoom ?? this.doubleTapZoom,
        orientation: orientation ?? this.orientation,
        background: background ?? this.background,
        tapZoneLayout: tapZoneLayout ?? this.tapZoneLayout,
        tapZoneInvert: tapZoneInvert ?? this.tapZoneInvert,
        minScale: minScale ?? this.minScale,
        maxScale: maxScale ?? this.maxScale,
        filterBrightness: filterBrightness ?? this.filterBrightness,
        filterContrast: filterContrast ?? this.filterContrast,
        filterColorTemp: filterColorTemp ?? this.filterColorTemp,
        filterSaturation: filterSaturation ?? this.filterSaturation,
        filterHue: filterHue ?? this.filterHue,
        filterInverted: filterInverted ?? this.filterInverted,
        cropEdge: cropEdge ?? this.cropEdge,
        showPageNumber: showPageNumber ?? this.showPageNumber,
        progressBarOnRight: progressBarOnRight ?? this.progressBarOnRight,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        rotateLandscape: rotateLandscape ?? this.rotateLandscape,
        splitDoublePage: splitDoublePage ?? this.splitDoublePage,
        sideMargin: sideMargin ?? this.sideMargin,
        flashEnabled: flashEnabled ?? this.flashEnabled,
        flashTime: flashTime ?? this.flashTime,
        flashInterval: flashInterval ?? this.flashInterval,
        flashColor: flashColor ?? this.flashColor,
        initialZoom: initialZoom ?? this.initialZoom,
        fullscreen: fullscreen ?? this.fullscreen,
        showLongPressMenu: showLongPressMenu ?? this.showLongPressMenu,
        filterGrayscale: filterGrayscale ?? this.filterGrayscale,
        preventShrink: preventShrink ?? this.preventShrink,
        showChapterTransition:
            showChapterTransition ?? this.showChapterTransition,
        doubleTapZoomScale: doubleTapZoomScale ?? this.doubleTapZoomScale,
        scrollWheelInverted: scrollWheelInverted ?? this.scrollWheelInverted,
      );

  /// 以 [base] 为全局默认，仅用本对象中「用户自定义过的字段」覆盖。
  ///
  /// 用于：设置页的阅读器默认设置作为 [base]，打开具体作品时读取的
  /// per-work 偏好作为本对象；用户没改过的项回落到全局默认。
  ReaderPreferences mergedWith(ReaderPreferences base) {
    const def = ReaderPreferences();
    return ReaderPreferences(
      readingMode: identical(readingMode, def.readingMode)
          ? base.readingMode
          : readingMode,
      doubleTapZoom: identical(doubleTapZoom, def.doubleTapZoom)
          ? base.doubleTapZoom
          : doubleTapZoom,
      orientation: identical(orientation, def.orientation)
          ? base.orientation
          : orientation,
      background: identical(background, def.background)
          ? base.background
          : background,
      tapZoneLayout: identical(tapZoneLayout, def.tapZoneLayout)
          ? base.tapZoneLayout
          : tapZoneLayout,
      tapZoneInvert: identical(tapZoneInvert, def.tapZoneInvert)
          ? base.tapZoneInvert
          : tapZoneInvert,
      minScale: identical(minScale, def.minScale) ? base.minScale : minScale,
      maxScale: identical(maxScale, def.maxScale) ? base.maxScale : maxScale,
      filterBrightness: identical(filterBrightness, def.filterBrightness)
          ? base.filterBrightness
          : filterBrightness,
      filterContrast: identical(filterContrast, def.filterContrast)
          ? base.filterContrast
          : filterContrast,
      filterColorTemp: identical(filterColorTemp, def.filterColorTemp)
          ? base.filterColorTemp
          : filterColorTemp,
      filterSaturation: identical(filterSaturation, def.filterSaturation)
          ? base.filterSaturation
          : filterSaturation,
      filterHue: identical(filterHue, def.filterHue)
          ? base.filterHue
          : filterHue,
      filterInverted: identical(filterInverted, def.filterInverted)
          ? base.filterInverted
          : filterInverted,
      cropEdge: identical(cropEdge, def.cropEdge) ? base.cropEdge : cropEdge,
      showPageNumber: identical(showPageNumber, def.showPageNumber)
          ? base.showPageNumber
          : showPageNumber,
      progressBarOnRight:
          identical(progressBarOnRight, def.progressBarOnRight)
              ? base.progressBarOnRight
              : progressBarOnRight,
      keepScreenOn: identical(keepScreenOn, def.keepScreenOn)
          ? base.keepScreenOn
          : keepScreenOn,
      rotateLandscape: identical(rotateLandscape, def.rotateLandscape)
          ? base.rotateLandscape
          : rotateLandscape,
      splitDoublePage: identical(splitDoublePage, def.splitDoublePage)
          ? base.splitDoublePage
          : splitDoublePage,
      sideMargin: identical(sideMargin, def.sideMargin)
          ? base.sideMargin
          : sideMargin,
      flashEnabled: identical(flashEnabled, def.flashEnabled)
          ? base.flashEnabled
          : flashEnabled,
      flashTime: identical(flashTime, def.flashTime)
          ? base.flashTime
          : flashTime,
      flashInterval: identical(flashInterval, def.flashInterval)
          ? base.flashInterval
          : flashInterval,
      flashColor: identical(flashColor, def.flashColor)
          ? base.flashColor
          : flashColor,
      initialZoom: identical(initialZoom, def.initialZoom)
          ? base.initialZoom
          : initialZoom,
      fullscreen: identical(fullscreen, def.fullscreen)
          ? base.fullscreen
          : fullscreen,
      showLongPressMenu: identical(showLongPressMenu, def.showLongPressMenu)
          ? base.showLongPressMenu
          : showLongPressMenu,
      filterGrayscale: identical(filterGrayscale, def.filterGrayscale)
          ? base.filterGrayscale
          : filterGrayscale,
      preventShrink: identical(preventShrink, def.preventShrink)
          ? base.preventShrink
          : preventShrink,
      showChapterTransition:
          identical(showChapterTransition, def.showChapterTransition)
              ? base.showChapterTransition
              : showChapterTransition,
      doubleTapZoomScale:
          identical(doubleTapZoomScale, def.doubleTapZoomScale)
              ? base.doubleTapZoomScale
              : doubleTapZoomScale,
      scrollWheelInverted:
          identical(scrollWheelInverted, def.scrollWheelInverted)
              ? base.scrollWheelInverted
              : scrollWheelInverted,
    );
  }

  /// 背景实际颜色（结合深浅色：auto 在浅色主题用白、深色用黑）。
  Color resolveBackgroundColor(bool isDark) {
    if (background == ReaderBackgroundColor.auto) {
      return isDark ? ReaderTokens.bgPresets[0] : ReaderTokens.bgPresets[2];
    }
    return ReaderTokens.bgPresets[background.toPresetIndex()];
  }
}

/// 持久化后端抽象（可注入内存实现用于测试，避免测试依赖原生插件）。
abstract class PrefsBackend {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}

/// 内存后端（测试用）。
class InMemoryBackend implements PrefsBackend {
  final Map<String, String> _store = {};

  @override
  Future<String?> get(String key) async => _store[key];

  @override
  Future<void> set(String key, String value) async => _store[key] = value;
}

/// 基于 shared_preferences 的后端。
class SharedPrefsBackend implements PrefsBackend {
  const SharedPrefsBackend();

  @override
  Future<String?> get(String key) async =>
      (await _prefs()).getString(key);

  @override
  Future<void> set(String key, String value) async =>
      (await _prefs()).setString(key, value);

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();
}

/// 阅读器偏好存储（按 key 隔离，默认持久化到 shared_preferences）。
class ReaderPreferencesStore {
  ReaderPreferencesStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  final PrefsBackend _backend;
  final Map<String, ReaderPreferences> _cache = {};

  static const String _prefix = 'reader_prefs_';

  /// 读取某作品偏好（缺省返回默认）。
  Future<ReaderPreferences> get(String id) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    final raw = await _backend.get('$_prefix$id');
    if (raw == null) return const ReaderPreferences();
    try {
      final prefs = ReaderPreferences.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      _cache[id] = prefs;
      return prefs;
    } on Object {
      return const ReaderPreferences();
    }
  }

  Future<void> save(String id, ReaderPreferences prefs) async {
    _cache[id] = prefs;
    await _backend.set(_prefix + id, jsonEncode(prefs.toJson()));
  }
}
