/// 小说文本分页器（文档 8.2）。
///
/// 完全采用 legado `ChapterProvider` 的渲染算法（用户指定三步，**不含**
/// `textBottomJustify` 底部对齐，末页保留自然排版）：
///
/// 1. **StaticLayout 按宽度折行（重要）**：用 [TextPainter]（等价 Android
///    `StaticLayout`）以 `maxWidth` 为约束把段落拆成适配宽度的视觉行
///    （[TextPainter.computeLineMetrics]），**不是按段落整段装箱**——这是排版
///    与 legado 一致的关键：各页顶到页底、行数一致、段落可跨页断行。
/// 2. **逐字符列(TextColumn)定位**：每行记录每个字符的 x 坐标
///    （[NovelLine.charLefts]，由 [TextPainter.getBoxesForSelection] 复用段落级
///    [TextPainter] 一次算出），等价 legado 的 `TextColumn` 逐字符定位，
///    供「点哪读哪」精确命中。
/// 3. **可见高度填满 → 翻页**：逐行贪心装入页面，填满 [height] 才翻页。
library;

import 'package:flutter/widgets.dart';

import '../../../core/novel/novel_reader_preferences.dart';
import '../../../core/theme/app_tokens.dart';

/// 单页中的一行文本（legado 式按行分页）。
///
/// 等价 legado `ChapterProvider` 的 **TextColumn**：每个字符的 x 坐标被
/// 记录下来（[charLefts]），供精确点击命中（点哪读到哪）与未来选区使用。
class NovelLine {
  /// 该行文本（首行已含 `　　` 缩进，续行无缩进）。
  final String text;

  /// 所属段落的全局下标（用于 TTS 高亮 / 点击跳转）。
  final int paragraphIndex;

  /// 是否为该段落的首行（仅首行带缩进）。
  final bool isFirstLine;

  /// 是否为该段落的末行（末行后需加段距）。
  final bool isLastLine;

  /// 逐字符列（TextColumn）定位：本行每个字符**左边缘**相对行首的 x 坐标。
  ///
  /// 由 [NovelPaginator._breakParagraph] 用 [TextPainter.getBoxesForSelection]
  /// 复用段落级 [TextPainter] 一次算出（无需额外 layout），与 legado 用
  /// `TextColumn` 记录每个字符位置完全对应。命中测试 [hitTestCharOffset]
  /// 据此把点击 x 映射到精确字符下标。
  ///
  /// 长度一般为字符数；合字/组合字符可能合并为一个 box（不影响中文命中精度）。
  /// 默认空列表（极少数空行未携带，命中回退到段首）。
  final List<double> charLefts;

  const NovelLine({
    required this.text,
    required this.paragraphIndex,
    this.isFirstLine = false,
    this.isLastLine = false,
    this.charLefts = const <double>[],
  });

  /// 把行内某点的水平坐标 [dx]（相对行首左边缘）映射到精确字符下标。
  ///
  /// 等价 legado `TextColumn.getChar(dx)`：取命中字符中心点最近的字符。
  /// 用于「点哪读哪」——点击行内任意位置得到应跳转/朗读的字符位置。
  int hitTestCharOffset(double dx) {
    if (charLefts.isEmpty) return 0;
    if (dx <= charLefts.first) return 0;
    if (dx >= charLefts.last) return charLefts.length - 1;
    for (var i = 0; i < charLefts.length - 1; i++) {
      final mid = (charLefts[i] + charLefts[i + 1]) / 2;
      if (dx < mid) return i;
    }
    return charLefts.length - 1;
  }
}

/// 单页数据：该页包含的视觉行列表。
typedef NovelPage = List<NovelLine>;

/// 分页结果。
class NovelPaginationResult {
  /// 分页后的页面列表（每页为一组视觉行）。
  final List<NovelPage> pages;

  /// 分页时使用的约束尺寸。
  final Size pageSize;

  const NovelPaginationResult({
    required this.pages,
    required this.pageSize,
  });

  /// 是否为空（无内容）。
  bool get isEmpty => pages.isEmpty;
}

/// 文本分页器。
class NovelPaginator {
  NovelPaginator._();

  /// 将章节正文分页。
  ///
  /// [paragraphs] — 章节正文段落（每段首行已含 `　　` 缩进）。
  /// [constraints] — 可用绘图区域约束。
  /// [prefs] — 阅读器偏好（字号 / 行距 / 段距 / 边距）。
  /// [context] — BuildContext（用于获取文本方向 / MediaQuery）。
  static NovelPaginationResult paginate({
    required List<String> paragraphs,
    required BoxConstraints constraints,
    required NovelReaderPreferences prefs,
    required BuildContext context,
    String? chapterTitle,
    String? bookName,
  }) {
    final width = constraints.maxWidth - prefs.margin * 2;

    // 扣除页眉 + 页脚 + 两个间距开销（与 _NovelPageWidget 中 headerFooterStyle
    // 一致，fontSize 12），否则分页器高估可用高度导致满页内容溢出正文区。
    const chromeSpacing = AppTokens.spaceSm * 2;
    final headerFooterStyle = TextStyle(
      fontSize: 12,
      fontFamily: prefs.customFontPath != null
          ? NovelReaderPreferences.customLoadedFontFamily
          : prefs.fontFamily,
    );
    final chromeTp = TextPainter(
      text: TextSpan(text: 'M', style: headerFooterStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final chromeHeight = chromeTp.height * 2 + chromeSpacing;
    chromeTp.dispose();

    final height = constraints.maxHeight - prefs.margin * 2 - chromeHeight;

    if (width <= 0 || height <= 0 || paragraphs.isEmpty) {
      return const NovelPaginationResult(
        pages: <NovelPage>[],
        pageSize: Size.zero,
      );
    }

    final style = prefs.resolveBodyTextStyle(const Color(0xFF000000));
    final dir = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);

    // 1) 把每个段落拆成视觉行（与正文渲染用同一 TextPainter 布局，
    //    保证断行点与渲染一致；首行自带 `　　` 缩进，续行无缩进）。
    final allLines = <NovelLine>[];
    for (var pi = 0; pi < paragraphs.length; pi++) {
      final para = paragraphs[pi];
      if (para.isEmpty) continue;
      allLines.addAll(_breakParagraph(para, pi, style, width, dir, scaler));
    }
    if (allLines.isEmpty) {
      return const NovelPaginationResult(
        pages: <NovelPage>[],
        pageSize: Size.zero,
      );
    }

    // 2) 精确行高（legado 用 Paint.fontMetrics，我们用 TextPainter.height）。
    //    对中文文本，TextPainter.height 已包含 ascent + descent + 行间距因子，
    //    与渲染引擎实际绘制高度一致。所有正文行等高。
    final measureTp = TextPainter(
      text: TextSpan(text: '中', style: style),
      textDirection: dir,
      textScaler: scaler,
    )..layout(maxWidth: width);
    final lineHeight = measureTp.height;
    measureTp.dispose();

    // 3) 章节大标题仅在第一页顶部预留高度（#7）。
    final bool showTitle = prefs.showChapterTitleInBody &&
        prefs.titleAlign != NovelTitleAlign.hidden &&
        chapterTitle != null &&
        chapterTitle.isNotEmpty;
    var titleReserve = 0.0;
    if (showTitle) {
      final titleStyle = prefs.resolveTitleTextStyle();
      final mainTp = TextPainter(
        text: TextSpan(text: chapterTitle, style: titleStyle),
        textDirection: dir,
        textScaler: scaler,
        textWidthBasis: TextWidthBasis.longestLine,
      )..layout(maxWidth: width);
      var titleHeight = mainTp.height;
      mainTp.dispose();
      if (prefs.titleSegmentMode &&
          bookName != null &&
          bookName.isNotEmpty) {
        final subStyle = titleStyle.copyWith(
          fontSize: (titleStyle.fontSize ?? 18) * prefs.titleSubScale,
          height: prefs.titleSubLineSpacing,
        );
        final subTp = TextPainter(
          text: TextSpan(text: bookName, style: subStyle),
          textDirection: dir,
          textScaler: scaler,
          textWidthBasis: TextWidthBasis.longestLine,
        )..layout(maxWidth: width);
        titleHeight += prefs.titleSegmentSpacing + subTp.height;
        subTp.dispose();
      }
      titleHeight += prefs.titleTopMargin + prefs.titleBottomMargin;
      titleReserve = titleHeight + prefs.paragraphSpacing * 1.5;
    }

    // 4) 逐行贪心装箱 + 寡行控制（legado 式：填满一页才翻页）。
    //
    //    核心逻辑：每行高度统一为 lineHeight；段落末行额外加段距。
    //    当一行装不下当前页时，检查把它推到下一页是否会产生「寡行」
    //    （即下一页开头只有 1~2 行属于同一段落）。若是，则回退到该段落
    //    在当前页的起始位置，把整个段落剩余部分一起推到下一页，
    //    避免「某页顶部出现孤立的一两行」这种视觉不均。
    //
    //    结果：每页顶到页底、各页行数一致、段落可跨页断行、无孤立寡行。
    const int minWidowLines = 3; // 下页同段至少保留此数行才允许在当前行后断页
    final pages = <NovelPage>[];
    var current = <NovelLine>[];
    var used = titleReserve;
    for (var i = 0; i < allLines.length; i++) {
      final line = allLines[i];
      final lineH = lineHeight + (line.isLastLine ? prefs.paragraphSpacing : 0);

      // 当前页已放不下且不是空页 → 考虑翻页
      if (used + lineH > height && current.isNotEmpty) {
        // ── 寡行检测 ──
        // 统计当前行所属段落在「即将推入新页的部分」中有多少行：
        // 从 allLines[i] 开始往后数，直到遇到下一个段落的首行(isFirstLine)或结尾。
        int upcomingLinesOfSamePara = 0;
        for (var j = i; j < allLines.length; j++) {
          upcomingLinesOfSamePara++;
          if (allLines[j].isLastLine) break; // 到了段落末尾
        }

        // 若即将推入新页的同段行数不足阈值 → 会产生寡行！
        // 回退策略：从 current 末尾倒退，找到本段在当前页的起始位置，
        // 把本段已装入的行也一起退出来，整段留给下一页。
        if (upcomingLinesOfSamePara < minWidowLines &&
            upcomingLinesOfSamePara > 0) {
          // 找到当前行所属段落 在 current 中的起始索引
          var paraStartInCurrent = current.length;
          while (paraStartInCurrent > 0 &&
              current[paraStartInCurrent - 1].paragraphIndex == line.paragraphIndex) {
            paraStartInCurrent--;
          }

          // 把本段已装入 current 的行退出来（连同 used 高度一起扣回）
          final deferred = <NovelLine>[];
          while (current.length > paraStartInCurrent) {
            final removed = current.removeLast();
            deferred.insert(0, removed); // 保持顺序
            used -= lineHeight +
                (removed.isLastLine ? prefs.paragraphSpacing : 0);
          }

          // 当前页到此结束（不含被回退的本段行）
          if (current.isNotEmpty) {
            pages.add(current);
          }
          current = deferred;
          used = 0; // 新页重新开始计数
          // 不 continue! 下面会把 line(=deferred 的首行)正常加入 current
        } else {
          // 无寡行风险 → 正常翻页
          pages.add(current);
          current = <NovelLine>[];
          used = 0;
        }
      }

      current.add(line);
      used += lineH;
    }
    if (current.isNotEmpty) {
      pages.add(current);
    }

    return NovelPaginationResult(
      pages: pages,
      pageSize: Size(width, height),
    );
  }

  /// 用与正文渲染一致的 [TextPainter] 把段落拆成适配宽度的视觉行。
  ///
  /// 返回每行一个 [NovelLine]；首行标记 [NovelLine.isFirstLine]，末行标记
  /// [NovelLine.isLastLine]，便于渲染时加段距。段首 `　　` 已含在文本中，
  /// 因此只有首行带缩进，续行无缩进（与 legado 一致）。
  ///
  /// 实现（对应 legado `ChapterProvider`）：
  /// - **StaticLayout 按宽度折行**：[TextPainter] 以 `maxWidth` 布局，用
  ///   [TextPainter.computeLineMetrics] 得到每行的高度，再用
  ///   [TextPainter.getPositionForOffset] 在每行垂直中心、左边缘探测起始字符
  ///   偏移，从而切出整行文本（与渲染断行点完全一致）。
  /// - **逐字符列(TextColumn)定位**：对每行用 [TextPainter.getBoxesForSelection]
  ///   复用同一个段落级 [TextPainter] 一次取出该行所有字符的 [TextBox]，记录每个
  ///   字符左边缘 x 到 [NovelLine.charLefts]，等价 legado `TextColumn` 的逐字符
  ///   坐标，供点击精确命中（点哪读哪）。
  static List<NovelLine> _breakParagraph(
    String para,
    int paraIndex,
    TextStyle style,
    double width,
    TextDirection dir,
    TextScaler scaler,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: para, style: style),
      textDirection: dir,
      textScaler: scaler,
    )..layout(maxWidth: width);

    final metrics = tp.computeLineMetrics();
    if (metrics.isEmpty) {
      tp.dispose();
      return <NovelLine>[];
    }

    // 逐行探测起始字符偏移：在每行垂直中心、左边缘 x=0 处取位置。
    final starts = <int>[];
    var top = 0.0;
    for (var i = 0; i < metrics.length; i++) {
      final y = top + metrics[i].height / 2;
      starts.add(tp.getPositionForOffset(Offset(0, y)).offset);
      top += metrics[i].height;
    }

    final lines = <NovelLine>[];
    for (var i = 0; i < metrics.length; i++) {
      final s = starts[i];
      final e = i + 1 < metrics.length ? starts[i + 1] : para.length;
      if (s >= e) continue;

      // 逐字符列(TextColumn)定位：复用本段落 tp 取该行字符 box，记录每个
      // 字符左边缘相对行首的 x（legado TextColumn 逐字符坐标）。
      final boxes = tp.getBoxesForSelection(TextSelection(
        baseOffset: s,
        extentOffset: e,
      ));
      final charLefts = <double>[for (final b in boxes) b.left];

      lines.add(NovelLine(
        text: para.substring(s, e),
        paragraphIndex: paraIndex,
        isFirstLine: i == 0,
        isLastLine: i == metrics.length - 1,
        charLefts: charLefts,
      ));
    }
    tp.dispose();
    return lines;
  }
}
