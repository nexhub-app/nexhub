/// 小说文本分页器（文档 8.2）。
///
/// 根据屏幕尺寸、字号、行距、段距、边距等偏好，将章节正文（段落列表）
/// 分割为可逐页翻阅的页面。使用 [TextPainter] 精确测量每段高度，
/// 贪心装入每页直到溢出。
library;

import 'package:flutter/widgets.dart';

import '../../../core/novel/novel_reader_preferences.dart';

/// 单页数据：该页包含的段落索引列表。
typedef NovelPage = List<int>;

/// 分页结果。
class NovelPaginationResult {
  /// 分页后的页面列表（每页为一组段落索引）。
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

  /// 将段落列表分页。
  ///
  /// [paragraphs] — 章节正文段落。
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
    final height = constraints.maxHeight - prefs.margin * 2;

    if (width <= 0 || height <= 0 || paragraphs.isEmpty) {
      return const NovelPaginationResult(
        pages: <NovelPage>[],
        pageSize: Size.zero,
      );
    }

    // 用与正文渲染完全一致的样式测量（含字体 / 加粗 / 斜体 / 字距），
    // 否则粗体或衬线体会因测量偏小导致末行被裁。颜色不影响排版。
    final style = prefs.resolveBodyTextStyle(const Color(0xFF000000));

    final pages = <NovelPage>[];
    var current = <int>[];
    var usedHeight = 0.0;

    // 章节大标题渲染在第一页顶部，需把其高度算进第一页起始占用，
    // 否则标题会与正文重叠 / 末行被裁。仅影响第一页。
    // hidden 对齐等同不显示标题（#7）。
    final bool showTitle = prefs.showChapterTitleInBody &&
        prefs.titleAlign != NovelTitleAlign.hidden &&
        chapterTitle != null &&
        chapterTitle.isNotEmpty;
    if (showTitle) {
      final titleStyle = prefs.resolveTitleTextStyle();
      final mainTp = TextPainter(
        text: TextSpan(text: chapterTitle, style: titleStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        textWidthBasis: TextWidthBasis.longestLine,
      )..layout(maxWidth: width);
      double titleHeight = mainTp.height;
      mainTp.dispose();
      // 分段模式（#7）：主行(章名) + 次行(书名) 两行，需累加次行高度。
      if (prefs.titleSegmentMode &&
          bookName != null &&
          bookName.isNotEmpty) {
        final subStyle = titleStyle.copyWith(
          fontSize: (titleStyle.fontSize ?? 18) * prefs.titleSubScale,
          height: prefs.titleSubLineSpacing,
        );
        final subTp = TextPainter(
          text: TextSpan(text: bookName, style: subStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          textWidthBasis: TextWidthBasis.longestLine,
        )..layout(maxWidth: width);
        titleHeight += prefs.titleSegmentSpacing + subTp.height;
        subTp.dispose();
      }
      titleHeight += prefs.titleTopMargin + prefs.titleBottomMargin;
      // 标题块 + 标题与正文间距（1.5 段距）。
      usedHeight = titleHeight + prefs.paragraphSpacing * 1.5;
    }

    for (var i = 0; i < paragraphs.length; i++) {
      final para = paragraphs[i];
      if (para.isEmpty) continue;

      final tp = TextPainter(
        text: TextSpan(text: para, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        textWidthBasis: TextWidthBasis.longestLine,
      )..layout(maxWidth: width);

      final paraHeight = tp.height + prefs.paragraphSpacing;
      tp.dispose();

      // 段落本身比一页还高：强制独占一页。
      if (paraHeight > height && current.isEmpty) {
        pages.add(<int>[i]);
        current = <int>[];
        usedHeight = 0;
        continue;
      }

      if (usedHeight + paraHeight > height && current.isNotEmpty) {
        pages.add(current);
        current = <int>[i];
        usedHeight = paraHeight;
      } else {
        current.add(i);
        usedHeight += paraHeight;
      }
    }

    if (current.isNotEmpty) {
      pages.add(current);
    }

    return NovelPaginationResult(
      pages: pages,
      pageSize: Size(width, height),
    );
  }
}
