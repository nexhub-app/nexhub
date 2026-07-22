/// 小说阅读器偏好（文档 8.3）。
///
/// 承载字号 / 行距 / 段距 / 边距 / 背景预设索引 / 自定义背景色 /
/// 强调色 / 阴影色 / 翻页动画 / 页眉页脚槽位 / 繁简转换模式 /
/// 自动翻页间隔 / 自定义字体。颜色以索引或十六进制值表示，
/// 由 [resolveBackgroundColor] 统一解析，不在外部硬编码。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../comic/models/reader_preferences.dart'
    show
        PrefsBackend,
        ReaderTapZoneLayout,
        SharedPrefsBackend,
        TapZoneInvert;
import '../theme/reader_tokens.dart';
import 'novel_page_animation.dart';

/// copyWith 哨兵：区分「未传 fontFamily」与「显式传 null」（系统字体）。
class _NovelPrefsFontFamilySentinel {
  const _NovelPrefsFontFamilySentinel();
}

const _NovelPrefsFontFamilySentinel _kNovelPrefsFontFamilySentinel =
    _NovelPrefsFontFamilySentinel();

/// copyWith 哨兵：用于可空的颜色字段（customBgColor / customTextColor /
/// shadowColor / emphasisColor），区分「未传入」与「显式传 null（清除）」。
/// 修复旧版 `x ?? this.x` 无法把颜色清回 null 的问题——例如点击预设背景时
/// 需要真正清除 customBgColor，否则预设不生效。
const Object _kNovelPrefsColorUnset = Object();

/// copyWith 哨兵：用于可空的字体文件路径字段（customFontPath /
/// titleCustomFontPath），区分「未传入」与「显式传 null（清除文件）」。
const Object _kNovelPrefsPathUnset = Object();

/// 页眉 / 页脚槽位内容类型（文档 8.3，6 种）。
enum NovelHeaderFooterContent {
  none,
  time,
  battery,
  chapterTitle,
  bookName,
  pageNumber,
  progressPercent,
  pageAndProgress,
  timeAndBattery;

  static NovelHeaderFooterContent fromString(String? raw) {
    return switch (raw) {
      'time' => time,
      'battery' => battery,
      'chapterTitle' => chapterTitle,
      'bookName' => bookName,
      'pageNumber' => pageNumber,
      'progressPercent' => progressPercent,
      'pageAndProgress' => pageAndProgress,
      'timeAndBattery' => timeAndBattery,
      _ => none,
    };
  }

  String l10nKey() => switch (this) {
        NovelHeaderFooterContent.none => 'novelHfNone',
        NovelHeaderFooterContent.time => 'novelHfTime',
        NovelHeaderFooterContent.battery => 'novelHfBattery',
        NovelHeaderFooterContent.chapterTitle => 'novelHfChapterTitle',
        NovelHeaderFooterContent.bookName => 'novelHfBookName',
        NovelHeaderFooterContent.pageNumber => 'novelHfPageNumber',
        NovelHeaderFooterContent.progressPercent => 'novelHfProgressPercent',
        NovelHeaderFooterContent.pageAndProgress => 'novelHfPageAndProgress',
        NovelHeaderFooterContent.timeAndBattery => 'novelHfTimeAndBattery',
      };
}

/// 章节大标题对齐方式（#7）。hidden = 不显示标题。
enum NovelTitleAlign {
  left,
  center,
  right,
  hidden;

  static NovelTitleAlign fromString(String? raw) {
    return switch (raw) {
      'center' => center,
      'right' => right,
      'hidden' => hidden,
      _ => left,
    };
  }

  String l10nKey() => switch (this) {
        NovelTitleAlign.left => 'novelTitleAlignLeft',
        NovelTitleAlign.center => 'novelTitleAlignCenter',
        NovelTitleAlign.right => 'novelTitleAlignRight',
        NovelTitleAlign.hidden => 'novelTitleAlignHidden',
      };
}

/// 底部工具栏可选工具项（小说阅读器，最多展示 6 个）。
enum NovelBottomTool {
  toc,
  prevChapter,
  nextChapter,
  nightMode,
  autoPage,
  settings,
  bookmark,
  bookmarkList,
  search,
  tts;

  /// 默认 6 槽顺序（与基准截图一致）。
  static const List<NovelBottomTool> defaults = <NovelBottomTool>[
    NovelBottomTool.toc,
    NovelBottomTool.prevChapter,
    NovelBottomTool.nightMode,
    NovelBottomTool.autoPage,
    NovelBottomTool.settings,
    NovelBottomTool.bookmark,
  ];

  /// 从字符串反序列化（无效值返回 null）。
  static NovelBottomTool? fromString(String? raw) {
    if (raw == null) return null;
    for (final v in NovelBottomTool.values) {
      if (v.name == raw) return v;
    }
    return null;
  }

  String l10nKey() => switch (this) {
        NovelBottomTool.toc => 'toolToc',
        NovelBottomTool.prevChapter => 'toolPrevChapter',
        NovelBottomTool.nextChapter => 'toolNextChapter',
        NovelBottomTool.nightMode => 'toolNightMode',
        NovelBottomTool.autoPage => 'toolAutoPage',
        NovelBottomTool.settings => 'toolSettings',
        NovelBottomTool.bookmark => 'toolBookmark',
        NovelBottomTool.bookmarkList => 'toolBookmarkList',
        NovelBottomTool.search => 'toolSearch',
        NovelBottomTool.tts => 'toolTts',
      };
}

/// 小说阅读器偏好。
class NovelReaderPreferences {
  /// 从自定义字体文件加载后使用的字族名（运行时通过 FontLoader 注册）。
  static const String customLoadedFontFamily = 'nexhubCustomNovelFont';

  /// 标题自定义字体文件加载后使用的字族名（与正文字体文件相互独立）。
  static const String customLoadedTitleFontFamily =
      'nexhubCustomNovelTitleFont';

  /// 已加载过的自定义字族集合，避免重复 load 报错。
  static final Set<String> _loadedFontFamilies = <String>{};

  /// 从字体文件路径加载并注册字族（.ttf / .otf）。[family] 为注册后的字族名，
  /// 渲染时通过 [customFontPath] / [titleCustomFontPath] 间接引用。
  static Future<void> loadCustomFont(String family, String path) async {
    if (_loadedFontFamilies.contains(family)) return;
    final bytes = await File(path).readAsBytes();
    final loader = FontLoader(family);
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loadedFontFamilies.add(family);
  }

  /// 字号（sp）。
  final double fontSize;

  /// 行距倍率（1.0 = 紧凑, 2.0 = 宽松）。
  final double lineHeight;

  /// 段距（像素）。
  final double paragraphSpacing;

  /// 左右边距（像素）。
  final double margin;

  /// 背景预设索引（引用 [ReaderTokens.bgPresets]）。
  final int bgPresetIndex;

  /// 自定义背景色（ARGB int 值；null 时使用预设）。
  final int? customBgColor;

  /// 强调色（ARGB int 值；null 时使用 [ReaderTokens.emphasisDefault]）。
  final int? emphasisColor;

  /// 正文自定义文字颜色（ARGB int 值；null 时按背景亮度自动取黑/白）。
  final int? customTextColor;

  /// 文字阴影颜色（ARGB int 值；null 时用正文色的半透明）。
  final int? shadowColor;

  /// 字间距（像素；0 = 默认不额外增距）。
  final double letterSpacing;

  /// 正文加粗（可与斜体/下划线共存）。
  final bool fontBold;

  /// 正文斜体（可与加粗/下划线共存）。
  final bool fontItalic;

  /// 正文下划线（可与加粗/斜体共存）。
  final bool fontUnderline;

  /// 是否在正文顶部显示章节大标题（与正文分开排版）。
  final bool showChapterTitleInBody;

  /// 章节标题字号相对正文的倍率（1.0 = 与正文同大）。
  final double titleFontScale;

  /// 章节标题加粗（默认加粗，与正文样式互不影响）。
  final bool titleBold;

  /// 章节标题颜色（ARGB int；null 时跟随强调色）。
  final int? titleColor;

  /// 是否启用文字阴影。
  final bool shadow;

  /// 翻页动画。
  final NovelPageAnimation pageAnimation;

  /// 页眉左侧槽位。
  final NovelHeaderFooterContent headerLeft;

  /// 页眉右侧槽位。
  final NovelHeaderFooterContent headerRight;

  /// 页脚左侧槽位。
  final NovelHeaderFooterContent footerLeft;

  /// 页脚右侧槽位。
  final NovelHeaderFooterContent footerRight;

  /// 繁简转换模式（'none' / 'traditionalToSimplified' /
  /// 'simplifiedToTraditional'）。
  final String chineseConvert;

  /// 自动翻页间隔（秒；0 = 关闭，常用值 3/5/10/15）。
  final int autoPageInterval;

  /// 自定义字体 fontFamily（null = 系统默认，'serif' / 'monospace' 等）。
  final String? fontFamily;

  /// 点击分区方向反转（与漫画共用 [TapZoneInvert] 枚举）。
  final TapZoneInvert tapZoneInvert;

  /// 点击分区布局（FR-4.2，5 布局；与漫画共用 [ReaderTapZoneLayout]）。
  final ReaderTapZoneLayout tapZoneLayout;

  /// 夜间快捷开关：true 时强制使用深灰背景预设（idx=1）+ 浅色文字，
  /// 不影响 [bgPresetIndex] / [customBgColor] 的持久值，切回日间即恢复。
  final bool nightMode;

  /// 底部工具栏槽位（有序，最多 6 个；超出截断）。
  final List<NovelBottomTool> bottomToolbarSlots;

  // ─────────────── #5 朗读设置 ───────────────
  /// 朗读语速（0.5–2.0，1.0 = 正常）。
  final double ttsSpeechRate;

  /// 朗读定时停止（睡眠定时，分钟；0 = 关闭）。
  final int ttsSleepTimer;

  /// 后台朗读开关：true 时应用进入后台仍继续朗读（需配合 AppLifecycle
  /// 监听，见 `NovelTtsController`）；false 时进入后台即暂停。
  final bool ttsBackground;

  // ─────────────── #6 字体 / 颜色 / 阴影 / 下划线 ───────────────
  /// 自定义字体文件路径（.ttf / .otf；null = 不指定，用 [fontFamily]）。
  final String? customFontPath;

  /// 文字阴影模糊半径（像素）。
  final double shadowBlur;

  /// 文字阴影 X 偏移（像素）。
  final double shadowOffsetX;

  /// 文字阴影 Y 偏移（像素）。
  final double shadowOffsetY;

  /// 下划线颜色（ARGB int；null = 跟随正文色）。
  final int? underlineColor;

  /// 下划线是否虚线。
  final bool underlineDashed;

  /// 下划线线宽（像素）。
  final double underlineThickness;

  /// 下划线虚线实段长（像素；仅 [underlineDashed] 时参考）。
  final double underlineDashLength;

  /// 下划线虚线间隙（像素；仅 [underlineDashed] 时参考）。
  final double underlineDashGap;

  // ─────────────── #7 标题显示 / 字体 / 分段 ───────────────
  /// 章节标题对齐方式（左 / 中 / 右）。
  final NovelTitleAlign titleAlign;

  /// 标题自定义字体 fontFamily（null = 跟随正文 [fontFamily]）。
  final String? titleFontFamily;

  /// 标题自定义字体文件路径（.ttf / .otf；null = 不指定，用 [titleFontFamily]）。
  final String? titleCustomFontPath;

  /// 标题分段模式：开启后标题分「主行(章名) + 次行(书名)」两行显示。
  final bool titleSegmentMode;

  /// 分段模式下次行字号相对主行的倍率。
  final double titleSubScale;

  /// 分段模式下主行与次行的间距（像素）。
  final double titleSegmentSpacing;

  /// 分段模式下次行的行距倍率。
  final double titleSubLineSpacing;

  /// 标题区上边距（像素）。
  final double titleTopMargin;

  /// 标题区下边距（像素）。
  final double titleBottomMargin;

  // ─────────────── #8 页眉 / 页脚 ───────────────
  /// 页眉中间槽位。
  final NovelHeaderFooterContent headerCenter;

  /// 页脚中间槽位。
  final NovelHeaderFooterContent footerCenter;

  /// 页眉页脚文字颜色（ARGB int；null = 跟随正文色）。
  final int? headerFooterColor;

  /// 页眉页脚左右边距（像素）。
  final double headerFooterMargin;

  const NovelReaderPreferences({
    this.fontSize = 18.0,
    this.lineHeight = 1.8,
    this.paragraphSpacing = 16.0,
    this.margin = 24.0,
    this.bgPresetIndex = 2,
    this.customBgColor,
    this.emphasisColor,
    this.customTextColor,
    this.shadowColor,
    this.letterSpacing = 0.0,
    this.fontBold = false,
    this.fontItalic = false,
    this.fontUnderline = false,
    this.showChapterTitleInBody = true,
    this.titleFontScale = 1.5,
    this.titleBold = true,
    this.titleColor,
    this.shadow = false,
    this.pageAnimation = NovelPageAnimation.slide,
    this.headerLeft = NovelHeaderFooterContent.bookName,
    this.headerRight = NovelHeaderFooterContent.time,
    this.footerLeft = NovelHeaderFooterContent.chapterTitle,
    this.footerRight = NovelHeaderFooterContent.pageNumber,
    this.chineseConvert = 'none',
    this.autoPageInterval = 0,
    this.fontFamily,
    this.tapZoneInvert = TapZoneInvert.none,
    this.tapZoneLayout = ReaderTapZoneLayout.lShape,
    this.nightMode = false,
    this.bottomToolbarSlots = NovelBottomTool.defaults,
    // #5 朗读
    this.ttsSpeechRate = 1.0,
    this.ttsSleepTimer = 0,
    this.ttsBackground = false,
    // #6 字体/阴影/下划线
    this.customFontPath,
    this.shadowBlur = 0.5,
    this.shadowOffsetX = 0.5,
    this.shadowOffsetY = 0.5,
    this.underlineColor,
    this.underlineDashed = false,
    this.underlineThickness = 1.0,
    this.underlineDashLength = 4.0,
    this.underlineDashGap = 2.0,
    // #7 标题
    this.titleAlign = NovelTitleAlign.left,
    this.titleFontFamily,
    this.titleCustomFontPath,
    this.titleSegmentMode = false,
    this.titleSubScale = 0.8,
    this.titleSegmentSpacing = 8.0,
    this.titleSubLineSpacing = 1.3,
    this.titleTopMargin = 0.0,
    this.titleBottomMargin = 0.0,
    // #8 页眉页脚
    this.headerCenter = NovelHeaderFooterContent.none,
    this.footerCenter = NovelHeaderFooterContent.none,
    this.headerFooterColor,
    this.headerFooterMargin = 12.0,
  });

  NovelReaderPreferences copyWith({
    double? fontSize,
    double? lineHeight,
    double? paragraphSpacing,
    double? margin,
    int? bgPresetIndex,
    Object? customBgColor = _kNovelPrefsColorUnset,
    Object? emphasisColor = _kNovelPrefsColorUnset,
    Object? customTextColor = _kNovelPrefsColorUnset,
    Object? shadowColor = _kNovelPrefsColorUnset,
    double? letterSpacing,
    bool? fontBold,
    bool? fontItalic,
    bool? fontUnderline,
    bool? showChapterTitleInBody,
    double? titleFontScale,
    bool? titleBold,
    Object? titleColor = _kNovelPrefsColorUnset,
    bool? shadow,
    NovelPageAnimation? pageAnimation,
    NovelHeaderFooterContent? headerLeft,
    NovelHeaderFooterContent? headerRight,
    NovelHeaderFooterContent? footerLeft,
    NovelHeaderFooterContent? footerRight,
    String? chineseConvert,
    int? autoPageInterval,
    Object? fontFamily = _kNovelPrefsFontFamilySentinel,
    TapZoneInvert? tapZoneInvert,
    ReaderTapZoneLayout? tapZoneLayout,
    bool? nightMode,
    List<NovelBottomTool>? bottomToolbarSlots,
    // #5 朗读
    double? ttsSpeechRate,
    int? ttsSleepTimer,
    bool? ttsBackground,
    // #6 字体/阴影/下划线
    Object? customFontPath = _kNovelPrefsPathUnset,
    double? shadowBlur,
    double? shadowOffsetX,
    double? shadowOffsetY,
    Object? underlineColor = _kNovelPrefsColorUnset,
    bool? underlineDashed,
    double? underlineThickness,
    double? underlineDashLength,
    double? underlineDashGap,
    // #7 标题
    NovelTitleAlign? titleAlign,
    Object? titleFontFamily = _kNovelPrefsFontFamilySentinel,
    Object? titleCustomFontPath = _kNovelPrefsPathUnset,
    bool? titleSegmentMode,
    double? titleSubScale,
    double? titleSegmentSpacing,
    double? titleSubLineSpacing,
    double? titleTopMargin,
    double? titleBottomMargin,
    // #8 页眉页脚
    NovelHeaderFooterContent? headerCenter,
    NovelHeaderFooterContent? footerCenter,
    Object? headerFooterColor = _kNovelPrefsColorUnset,
    double? headerFooterMargin,
  }) {
    return NovelReaderPreferences(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      margin: margin ?? this.margin,
      bgPresetIndex: bgPresetIndex ?? this.bgPresetIndex,
      customBgColor: identical(customBgColor, _kNovelPrefsColorUnset)
          ? this.customBgColor
          : customBgColor as int?,
      emphasisColor: identical(emphasisColor, _kNovelPrefsColorUnset)
          ? this.emphasisColor
          : emphasisColor as int?,
      customTextColor: identical(customTextColor, _kNovelPrefsColorUnset)
          ? this.customTextColor
          : customTextColor as int?,
      shadowColor: identical(shadowColor, _kNovelPrefsColorUnset)
          ? this.shadowColor
          : shadowColor as int?,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      fontBold: fontBold ?? this.fontBold,
      fontItalic: fontItalic ?? this.fontItalic,
      fontUnderline: fontUnderline ?? this.fontUnderline,
      showChapterTitleInBody:
          showChapterTitleInBody ?? this.showChapterTitleInBody,
      titleFontScale: titleFontScale ?? this.titleFontScale,
      titleBold: titleBold ?? this.titleBold,
      titleColor: identical(titleColor, _kNovelPrefsColorUnset)
          ? this.titleColor
          : titleColor as int?,
      shadow: shadow ?? this.shadow,
      pageAnimation: pageAnimation ?? this.pageAnimation,
      headerLeft: headerLeft ?? this.headerLeft,
      headerRight: headerRight ?? this.headerRight,
      footerLeft: footerLeft ?? this.footerLeft,
      footerRight: footerRight ?? this.footerRight,
      chineseConvert: chineseConvert ?? this.chineseConvert,
      autoPageInterval: autoPageInterval ?? this.autoPageInterval,
      // 用哨兵区分「未传入」与「显式传入 null」。
      fontFamily: identical(fontFamily, _kNovelPrefsFontFamilySentinel)
          ? this.fontFamily
          : fontFamily as String?,
      tapZoneInvert: tapZoneInvert ?? this.tapZoneInvert,
      tapZoneLayout: tapZoneLayout ?? this.tapZoneLayout,
      nightMode: nightMode ?? this.nightMode,
      bottomToolbarSlots:
          bottomToolbarSlots ?? this.bottomToolbarSlots,
      // #5 朗读
      ttsSpeechRate: ttsSpeechRate ?? this.ttsSpeechRate,
      ttsSleepTimer: ttsSleepTimer ?? this.ttsSleepTimer,
      ttsBackground: ttsBackground ?? this.ttsBackground,
      // #6 字体/阴影/下划线
      customFontPath: identical(customFontPath, _kNovelPrefsPathUnset)
          ? this.customFontPath
          : customFontPath as String?,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      shadowOffsetX: shadowOffsetX ?? this.shadowOffsetX,
      shadowOffsetY: shadowOffsetY ?? this.shadowOffsetY,
      underlineColor: identical(underlineColor, _kNovelPrefsColorUnset)
          ? this.underlineColor
          : underlineColor as int?,
      underlineDashed: underlineDashed ?? this.underlineDashed,
      underlineThickness: underlineThickness ?? this.underlineThickness,
      underlineDashLength: underlineDashLength ?? this.underlineDashLength,
      underlineDashGap: underlineDashGap ?? this.underlineDashGap,
      // #7 标题
      titleAlign: titleAlign ?? this.titleAlign,
      titleFontFamily: identical(titleFontFamily, _kNovelPrefsFontFamilySentinel)
          ? this.titleFontFamily
          : titleFontFamily as String?,
      titleCustomFontPath:
          identical(titleCustomFontPath, _kNovelPrefsPathUnset)
              ? this.titleCustomFontPath
              : titleCustomFontPath as String?,
      titleSegmentMode: titleSegmentMode ?? this.titleSegmentMode,
      titleSubScale: titleSubScale ?? this.titleSubScale,
      titleSegmentSpacing: titleSegmentSpacing ?? this.titleSegmentSpacing,
      titleSubLineSpacing: titleSubLineSpacing ?? this.titleSubLineSpacing,
      titleTopMargin: titleTopMargin ?? this.titleTopMargin,
      titleBottomMargin: titleBottomMargin ?? this.titleBottomMargin,
      // #8 页眉页脚
      headerCenter: headerCenter ?? this.headerCenter,
      footerCenter: footerCenter ?? this.footerCenter,
      headerFooterColor: identical(headerFooterColor, _kNovelPrefsColorUnset)
          ? this.headerFooterColor
          : headerFooterColor as int?,
      headerFooterMargin: headerFooterMargin ?? this.headerFooterMargin,
    );
  }

  /// 以 [base] 为全局默认，仅用本对象中「用户自定义过的字段」覆盖。
  NovelReaderPreferences mergedWith(NovelReaderPreferences base) {
    const def = NovelReaderPreferences();
    return NovelReaderPreferences(
      fontSize: identical(fontSize, def.fontSize) ? base.fontSize : fontSize,
      lineHeight:
          identical(lineHeight, def.lineHeight) ? base.lineHeight : lineHeight,
      paragraphSpacing: identical(paragraphSpacing, def.paragraphSpacing)
          ? base.paragraphSpacing
          : paragraphSpacing,
      margin: identical(margin, def.margin) ? base.margin : margin,
      bgPresetIndex: identical(bgPresetIndex, def.bgPresetIndex)
          ? base.bgPresetIndex
          : bgPresetIndex,
      customBgColor: identical(customBgColor, def.customBgColor)
          ? base.customBgColor
          : customBgColor,
      emphasisColor: identical(emphasisColor, def.emphasisColor)
          ? base.emphasisColor
          : emphasisColor,
      customTextColor: identical(customTextColor, def.customTextColor)
          ? base.customTextColor
          : customTextColor,
      shadowColor: identical(shadowColor, def.shadowColor)
          ? base.shadowColor
          : shadowColor,
      letterSpacing: identical(letterSpacing, def.letterSpacing)
          ? base.letterSpacing
          : letterSpacing,
      fontBold: identical(fontBold, def.fontBold) ? base.fontBold : fontBold,
      fontItalic:
          identical(fontItalic, def.fontItalic) ? base.fontItalic : fontItalic,
      fontUnderline: identical(fontUnderline, def.fontUnderline)
          ? base.fontUnderline
          : fontUnderline,
      showChapterTitleInBody:
          identical(showChapterTitleInBody, def.showChapterTitleInBody)
              ? base.showChapterTitleInBody
              : showChapterTitleInBody,
      titleFontScale: identical(titleFontScale, def.titleFontScale)
          ? base.titleFontScale
          : titleFontScale,
      titleBold:
          identical(titleBold, def.titleBold) ? base.titleBold : titleBold,
      titleColor: identical(titleColor, def.titleColor)
          ? base.titleColor
          : titleColor,
      shadow: identical(shadow, def.shadow) ? base.shadow : shadow,
      pageAnimation: identical(pageAnimation, def.pageAnimation)
          ? base.pageAnimation
          : pageAnimation,
      headerLeft:
          identical(headerLeft, def.headerLeft) ? base.headerLeft : headerLeft,
      headerRight: identical(headerRight, def.headerRight)
          ? base.headerRight
          : headerRight,
      footerLeft:
          identical(footerLeft, def.footerLeft) ? base.footerLeft : footerLeft,
      footerRight: identical(footerRight, def.footerRight)
          ? base.footerRight
          : footerRight,
      chineseConvert: identical(chineseConvert, def.chineseConvert)
          ? base.chineseConvert
          : chineseConvert,
      autoPageInterval: identical(autoPageInterval, def.autoPageInterval)
          ? base.autoPageInterval
          : autoPageInterval,
      fontFamily: fontFamily ?? base.fontFamily,
      tapZoneInvert: identical(tapZoneInvert, def.tapZoneInvert)
          ? base.tapZoneInvert
          : tapZoneInvert,
      tapZoneLayout: identical(tapZoneLayout, def.tapZoneLayout)
          ? base.tapZoneLayout
          : tapZoneLayout,
      nightMode: identical(nightMode, def.nightMode)
          ? base.nightMode
          : nightMode,
      bottomToolbarSlots:
          listEquals(bottomToolbarSlots, def.bottomToolbarSlots)
              ? base.bottomToolbarSlots
              : bottomToolbarSlots,
      // #5 朗读
      ttsSpeechRate: identical(ttsSpeechRate, def.ttsSpeechRate)
          ? base.ttsSpeechRate
          : ttsSpeechRate,
      ttsSleepTimer: identical(ttsSleepTimer, def.ttsSleepTimer)
          ? base.ttsSleepTimer
          : ttsSleepTimer,
      ttsBackground: identical(ttsBackground, def.ttsBackground)
          ? base.ttsBackground
          : ttsBackground,
      // #6 字体/阴影/下划线
      customFontPath: identical(customFontPath, def.customFontPath)
          ? base.customFontPath
          : customFontPath,
      shadowBlur:
          identical(shadowBlur, def.shadowBlur) ? base.shadowBlur : shadowBlur,
      shadowOffsetX: identical(shadowOffsetX, def.shadowOffsetX)
          ? base.shadowOffsetX
          : shadowOffsetX,
      shadowOffsetY: identical(shadowOffsetY, def.shadowOffsetY)
          ? base.shadowOffsetY
          : shadowOffsetY,
      underlineColor: identical(underlineColor, def.underlineColor)
          ? base.underlineColor
          : underlineColor,
      underlineDashed: identical(underlineDashed, def.underlineDashed)
          ? base.underlineDashed
          : underlineDashed,
      underlineThickness: identical(underlineThickness, def.underlineThickness)
          ? base.underlineThickness
          : underlineThickness,
      underlineDashLength: identical(underlineDashLength, def.underlineDashLength)
          ? base.underlineDashLength
          : underlineDashLength,
      underlineDashGap: identical(underlineDashGap, def.underlineDashGap)
          ? base.underlineDashGap
          : underlineDashGap,
      // #7 标题
      titleAlign:
          identical(titleAlign, def.titleAlign) ? base.titleAlign : titleAlign,
      titleFontFamily: identical(titleFontFamily, def.titleFontFamily)
          ? base.titleFontFamily
          : titleFontFamily,
      titleCustomFontPath: identical(titleCustomFontPath, def.titleCustomFontPath)
          ? base.titleCustomFontPath
          : titleCustomFontPath,
      titleSegmentMode: identical(titleSegmentMode, def.titleSegmentMode)
          ? base.titleSegmentMode
          : titleSegmentMode,
      titleSubScale: identical(titleSubScale, def.titleSubScale)
          ? base.titleSubScale
          : titleSubScale,
      titleSegmentSpacing: identical(titleSegmentSpacing, def.titleSegmentSpacing)
          ? base.titleSegmentSpacing
          : titleSegmentSpacing,
      titleSubLineSpacing: identical(titleSubLineSpacing, def.titleSubLineSpacing)
          ? base.titleSubLineSpacing
          : titleSubLineSpacing,
      titleTopMargin: identical(titleTopMargin, def.titleTopMargin)
          ? base.titleTopMargin
          : titleTopMargin,
      titleBottomMargin: identical(titleBottomMargin, def.titleBottomMargin)
          ? base.titleBottomMargin
          : titleBottomMargin,
      // #8 页眉页脚
      headerCenter: identical(headerCenter, def.headerCenter)
          ? base.headerCenter
          : headerCenter,
      footerCenter: identical(footerCenter, def.footerCenter)
          ? base.footerCenter
          : footerCenter,
      headerFooterColor: identical(headerFooterColor, def.headerFooterColor)
          ? base.headerFooterColor
          : headerFooterColor,
      headerFooterMargin: identical(headerFooterMargin, def.headerFooterMargin)
          ? base.headerFooterMargin
          : headerFooterMargin,
    );
  }

  /// 解析背景色（自定义优先，否则取预设）。
  ///
  /// 夜间快捷开关（[nightMode]）：开启时不再强制单一深灰，而是在**所选**
  /// 预设 / 自定义背景基础上压暗（[ReaderTokens.nightDarkenFactor]），
  /// 既护眼又保留各预设差异（修复「夜间模式下所有预设背景看起来同色」）。
  /// 不影响 [bgPresetIndex] / [customBgColor] 的持久值，切回日间即恢复。
  ///
  /// 自定义背景色 [customBgColor] 优先级次之：用户明确指定颜色时尊重其选择
  /// （同样会在夜间压暗）。否则按 [bgPresetIndex] 取预设。
  Color resolveBackgroundColor(bool isDark) {
    final Color base = customBgColor != null
        ? Color(customBgColor!)
        : ReaderTokens.bgPresets[bgPresetIndex.clamp(0, ReaderTokens.bgPresets.length - 1)];
    if (nightMode) {
      return Color.lerp(base, Colors.black, ReaderTokens.nightDarkenFactor) ?? base;
    }
    return base;
  }

  /// 解析强调色。
  Color resolveEmphasisColor() {
    if (emphasisColor != null) return Color(emphasisColor!);
    return ReaderTokens.emphasisDefault;
  }

  /// 正文文字颜色（[customTextColor] 优先；否则按背景亮度自动取黑/白）。
  Color resolveTextColor(Color bg) {
    if (customTextColor != null) return Color(customTextColor!);
    return bg.computeLuminance() > 0.5
        ? const Color(0xFF1A1A1A)
        : const Color(0xFFE0E0E0);
  }

  /// 文字阴影颜色（[shadowColor] 优先；否则用正文色的半透明）。
  Color resolveShadowColor(Color textColor) {
    if (shadowColor != null) return Color(shadowColor!);
    return textColor.withValues(alpha: 0.3);
  }

  /// 构建正文 [TextStyle]，统一应用字号 / 行距 / 字距 / 字体 / 加粗 / 斜体 /
  /// 下划线 / 颜色 / 阴影。paged 与 scroll 两种渲染共用，确保所有字体样式
  /// 真实生效且可共存。[autoTextColor] 为按背景亮度推导的默认色，
  /// [customTextColor] 非空时覆盖。
  ///
  /// 注意：当 [fontUnderline] && [underlineDashed] 同时开启时，本样式不设
  /// `TextDecoration.underline`，由上层 `_NovelPageWidget` 用 `CustomPaint`
  /// 按 [underlineDashLength] / [underlineDashGap] 自定义绘制虚线
  /// （原生 `TextDecorationStyle.dashed` 不支持自定义段长/间隙）。
  TextStyle resolveBodyTextStyle(Color autoTextColor) {
    final Color color =
        customTextColor != null ? Color(customTextColor!) : autoTextColor;
    final bool hasUnderline = fontUnderline;
    // 虚线下划线交由 CustomPaint 绘制，原生 decoration 仅处理 solid 实线。
    final bool nativeUnderline = hasUnderline && !underlineDashed;
    return TextStyle(
      fontSize: fontSize,
      height: lineHeight,
      color: color,
      fontFamily: customFontPath != null ? customLoadedFontFamily : fontFamily,
      fontWeight: fontBold ? FontWeight.bold : null,
      fontStyle: fontItalic ? FontStyle.italic : null,
      decoration: nativeUnderline ? TextDecoration.underline : null,
      decorationColor: nativeUnderline && underlineColor != null
          ? Color(underlineColor!)
          : null,
      decorationStyle: null,
      decorationThickness: nativeUnderline ? underlineThickness : null,
      letterSpacing: letterSpacing == 0 ? null : letterSpacing,
      shadows: shadow
          ? <Shadow>[
              Shadow(
                color: resolveShadowColor(color),
                offset: Offset(shadowOffsetX, shadowOffsetY),
                blurRadius: shadowBlur,
              ),
            ]
          : null,
    );
  }

  /// 下划线颜色（[underlineColor] 优先；否则跟随正文色）。
  Color? resolveUnderlineColor(Color textColor) {
    if (underlineColor != null) return Color(underlineColor!);
    return textColor;
  }

  /// 章节标题颜色（[titleColor] 优先；否则用强调色，与正文分开）。
  Color resolveTitleColor() {
    if (titleColor != null) return Color(titleColor!);
    return resolveEmphasisColor();
  }

  /// 构建章节大标题 [TextStyle]，与正文样式独立：字号 = 正文字号 ×
  /// [titleFontScale]，可单独加粗、单独配色，继承字体族与阴影。
  TextStyle resolveTitleTextStyle() {
    return TextStyle(
      fontSize: fontSize * titleFontScale,
      height: 1.3,
      color: resolveTitleColor(),
      fontFamily: titleCustomFontPath != null
          ? customLoadedTitleFontFamily
          : (titleFontFamily ??
              (customFontPath != null
                  ? customLoadedFontFamily
                  : fontFamily)),
      fontWeight: titleBold ? FontWeight.bold : FontWeight.w500,
      letterSpacing: letterSpacing == 0 ? null : letterSpacing,
    );
  }

  /// 序列化为 JSON。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'paragraphSpacing': paragraphSpacing,
        'margin': margin,
        'bgPresetIndex': bgPresetIndex,
        if (customBgColor != null) 'customBgColor': customBgColor,
        if (emphasisColor != null) 'emphasisColor': emphasisColor,
        if (customTextColor != null) 'customTextColor': customTextColor,
        if (shadowColor != null) 'shadowColor': shadowColor,
        'letterSpacing': letterSpacing,
        'fontBold': fontBold,
        'fontItalic': fontItalic,
        'fontUnderline': fontUnderline,
        'showChapterTitleInBody': showChapterTitleInBody,
        'titleFontScale': titleFontScale,
        'titleBold': titleBold,
        if (titleColor != null) 'titleColor': titleColor,
        'shadow': shadow,
        'pageAnimation': pageAnimation.name,
        'headerLeft': headerLeft.name,
        'headerRight': headerRight.name,
        'footerLeft': footerLeft.name,
        'footerRight': footerRight.name,
        'chineseConvert': chineseConvert,
        'autoPageInterval': autoPageInterval,
        if (fontFamily != null) 'fontFamily': fontFamily,
        'tapZoneInvert': tapZoneInvert.name,
        'tapZoneLayout': tapZoneLayout.name,
        'nightMode': nightMode,
        'bottomToolbarSlots':
            bottomToolbarSlots.map((NovelBottomTool t) => t.name).toList(),
        // #5 朗读
        'ttsSpeechRate': ttsSpeechRate,
        'ttsSleepTimer': ttsSleepTimer,
        'ttsBackground': ttsBackground,
        // #6 字体/阴影/下划线
        if (customFontPath != null) 'customFontPath': customFontPath,
        'shadowBlur': shadowBlur,
        'shadowOffsetX': shadowOffsetX,
        'shadowOffsetY': shadowOffsetY,
        if (underlineColor != null) 'underlineColor': underlineColor,
        'underlineDashed': underlineDashed,
        'underlineThickness': underlineThickness,
        'underlineDashLength': underlineDashLength,
        'underlineDashGap': underlineDashGap,
        // #7 标题
        'titleAlign': titleAlign.name,
        if (titleFontFamily != null) 'titleFontFamily': titleFontFamily,
        if (titleCustomFontPath != null)
          'titleCustomFontPath': titleCustomFontPath,
        'titleSegmentMode': titleSegmentMode,
        'titleSubScale': titleSubScale,
        'titleSegmentSpacing': titleSegmentSpacing,
        'titleSubLineSpacing': titleSubLineSpacing,
        'titleTopMargin': titleTopMargin,
        'titleBottomMargin': titleBottomMargin,
        // #8 页眉页脚
        'headerCenter': headerCenter.name,
        'footerCenter': footerCenter.name,
        if (headerFooterColor != null) 'headerFooterColor': headerFooterColor,
        'headerFooterMargin': headerFooterMargin,
      };

  /// 从 JSON 反序列化。
  factory NovelReaderPreferences.fromJson(Map<String, dynamic> json) {
    return NovelReaderPreferences(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.8,
      paragraphSpacing:
          (json['paragraphSpacing'] as num?)?.toDouble() ?? 16.0,
      margin: (json['margin'] as num?)?.toDouble() ?? 24.0,
      bgPresetIndex: json['bgPresetIndex'] as int? ?? 2,
      customBgColor: json['customBgColor'] as int?,
      emphasisColor: json['emphasisColor'] as int?,
      customTextColor: json['customTextColor'] as int?,
      shadowColor: json['shadowColor'] as int?,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0.0,
      fontBold: json['fontBold'] as bool? ?? false,
      fontItalic: json['fontItalic'] as bool? ?? false,
      fontUnderline: json['fontUnderline'] as bool? ?? false,
      showChapterTitleInBody:
          json['showChapterTitleInBody'] as bool? ?? true,
      titleFontScale: (json['titleFontScale'] as num?)?.toDouble() ?? 1.5,
      titleBold: json['titleBold'] as bool? ?? true,
      titleColor: json['titleColor'] as int?,
      shadow: json['shadow'] as bool? ?? false,
      pageAnimation:
          NovelPageAnimation.fromString(json['pageAnimation'] as String?),
      headerLeft: NovelHeaderFooterContent.fromString(
          json['headerLeft'] as String?),
      headerRight: NovelHeaderFooterContent.fromString(
          json['headerRight'] as String?),
      footerLeft: NovelHeaderFooterContent.fromString(
          json['footerLeft'] as String?),
      footerRight: NovelHeaderFooterContent.fromString(
          json['footerRight'] as String?),
      chineseConvert: json['chineseConvert'] as String? ?? 'none',
      autoPageInterval: (json['autoPageInterval'] as num?)?.toInt() ?? 0,
      fontFamily: json['fontFamily'] as String?,
      tapZoneInvert: _parseTapZoneInvert(json['tapZoneInvert']),
      tapZoneLayout: _parseTapZoneLayout(json['tapZoneLayout']),
      nightMode: json['nightMode'] as bool? ?? false,
      bottomToolbarSlots: _parseBottomToolbarSlots(
          json['bottomToolbarSlots']),
      // #5 朗读
      ttsSpeechRate: (json['ttsSpeechRate'] as num?)?.toDouble() ?? 1.0,
      ttsSleepTimer: (json['ttsSleepTimer'] as num?)?.toInt() ?? 0,
      ttsBackground: json['ttsBackground'] as bool? ?? false,
      // #6 字体/阴影/下划线
      customFontPath: json['customFontPath'] as String?,
      shadowBlur: (json['shadowBlur'] as num?)?.toDouble() ?? 0.5,
      shadowOffsetX: (json['shadowOffsetX'] as num?)?.toDouble() ?? 0.5,
      shadowOffsetY: (json['shadowOffsetY'] as num?)?.toDouble() ?? 0.5,
      underlineColor: json['underlineColor'] as int?,
      underlineDashed: json['underlineDashed'] as bool? ?? false,
      underlineThickness:
          (json['underlineThickness'] as num?)?.toDouble() ?? 1.0,
      underlineDashLength:
          (json['underlineDashLength'] as num?)?.toDouble() ?? 4.0,
      underlineDashGap: (json['underlineDashGap'] as num?)?.toDouble() ?? 2.0,
      // #7 标题
      titleAlign: NovelTitleAlign.fromString(json['titleAlign'] as String?),
      titleFontFamily: json['titleFontFamily'] as String?,
      titleCustomFontPath: json['titleCustomFontPath'] as String?,
      titleSegmentMode: json['titleSegmentMode'] as bool? ?? false,
      titleSubScale: (json['titleSubScale'] as num?)?.toDouble() ?? 0.8,
      titleSegmentSpacing:
          (json['titleSegmentSpacing'] as num?)?.toDouble() ?? 8.0,
      titleSubLineSpacing:
          (json['titleSubLineSpacing'] as num?)?.toDouble() ?? 1.3,
      titleTopMargin: (json['titleTopMargin'] as num?)?.toDouble() ?? 0.0,
      titleBottomMargin:
          (json['titleBottomMargin'] as num?)?.toDouble() ?? 0.0,
      // #8 页眉页脚
      headerCenter: NovelHeaderFooterContent.fromString(
          json['headerCenter'] as String?),
      footerCenter: NovelHeaderFooterContent.fromString(
          json['footerCenter'] as String?),
      headerFooterColor: json['headerFooterColor'] as int?,
      headerFooterMargin:
          (json['headerFooterMargin'] as num?)?.toDouble() ?? 12.0,
    );
  }
}

/// 解析点击分区反转（兼容旧版字符串 'none'/'leftRight'/'all'）。
TapZoneInvert _parseTapZoneInvert(Object? raw) {
  if (raw is String) {
    return TapZoneInvert.values.firstWhere(
      (TapZoneInvert e) => e.name == raw,
      orElse: () => TapZoneInvert.none,
    );
  }
  return TapZoneInvert.none;
}

/// 解析点击分区布局。
ReaderTapZoneLayout _parseTapZoneLayout(Object? raw) {
  if (raw is String) {
    return ReaderTapZoneLayout.values.firstWhere(
      (ReaderTapZoneLayout e) => e.name == raw,
      orElse: () => ReaderTapZoneLayout.lShape,
    );
  }
  return ReaderTapZoneLayout.lShape;
}

/// 解析底部工具栏槽位（无效 / 为空时回退默认）。
List<NovelBottomTool> _parseBottomToolbarSlots(Object? raw) {
  if (raw is List) {
    final parsed = <NovelBottomTool>[];
    for (final item in raw) {
      final t = NovelBottomTool.fromString(item?.toString());
      if (t != null) parsed.add(t);
    }
    if (parsed.isNotEmpty) return parsed;
  }
  return NovelBottomTool.defaults;
}

/// 小说阅读器偏好存储（按 novelId 持久化）。
class NovelReaderPreferencesStore {
  NovelReaderPreferencesStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  final PrefsBackend _backend;
  final Map<String, NovelReaderPreferences> _cache = {};

  static const String _prefix = 'novel_prefs_';

  Future<NovelReaderPreferences> get(String novelId) async {
    final cached = _cache[novelId];
    if (cached != null) return cached;
    final raw = await _backend.get('$_prefix$novelId');
    if (raw == null || raw.isEmpty) return const NovelReaderPreferences();
    try {
      return NovelReaderPreferences.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const NovelReaderPreferences();
    }
  }

  Future<void> save(String novelId, NovelReaderPreferences prefs) async {
    _cache[novelId] = prefs;
    await _backend.set('$_prefix$novelId', jsonEncode(prefs.toJson()));
  }
}
