/// 章节目录解析：依据书源 `ruleToc` 解析章节列表（标题、URL、卷/VIP/付费标记）。
library;

import '../model/book_source.dart';
import '../model/xiaoshuo_book.dart';
import '../model/xiaoshuo_book_chapter.dart';
import '../analyze/analyze_rule.dart';

class BookChapterList {
  static List<XiaoshuoBookChapter> analyzeChapterList({
    required XiaoshuoBookSource bookSource,
    required XiaoshuoBook book,
    required String baseUrl,
    required String? redirectUrl,
    required String body,
  }) {
    final tocRule = bookSource.getTocRule();
    final analyzeRule = AnalyzeRule(book: book)
      ..setContent(body, redirectUrl ?? baseUrl)
      ..setBaseUrl(baseUrl)
      ..setRedirectUrl(redirectUrl ?? baseUrl);

    final chapters = <XiaoshuoBookChapter>[];
    // URL 去重：避免目录页中"最新章节预览"等栏与正式列表重复收录同一章节，
    // 也防止跨书链接被错误计入。通用能力，仅按绝对 URL 去重，不影响正常多章节。
    final seenUrls = <String>{};

    var listRule = tocRule.chapterList ?? '';
    var reverse = false;
    if (listRule.startsWith('-')) {
      reverse = true;
      listRule = listRule.substring(1);
    }
    if (listRule.startsWith('+')) {
      listRule = listRule.substring(1);
    }

    if (listRule.isEmpty) return chapters;

    try {
      var elements = analyzeRule.getElements(listRule);

      if (elements.isEmpty) return chapters;

      // 排除选择器：在进入逐条解析前，先剔除落在"最新章节预览"/"推荐"等
      // 非正文容器内的元素。比 [chapterScope] URL 前缀过滤更彻底——这些元素
      // 根本不会进入后续的标题提取/URL去重/垃圾标题过滤流程。
      if (tocRule.excludeSelector != null &&
          tocRule.excludeSelector!.isNotEmpty) {
        try {
          final excluded = analyzeRule.getElements(tocRule.excludeSelector!);
          if (excluded.isNotEmpty) {
            // 收集被排除容器及其所有后代元素（O(n*m)，但目录页元素通常 < 500）
            final excludedSet = <dynamic>{};
            for (final ex in excluded) {
              excludedSet.add(ex);
              // queryAll('*') 获取所有后代
              final descendants = ex.querySelectorAll('*');
              for (final d in descendants) {
                excludedSet.add(d);
              }
            }
            if (excludedSet.isNotEmpty) {
              elements = elements
                  .where((el) => !excludedSet.contains(el))
                  .toList();
            }
          }
        } catch (_) {
          // 排除选择器解析失败时不影响主流程（降级为不过滤）
        }
      }

      final ruleName = analyzeRule.splitSourceRule(tocRule.chapterName ?? '');
      final ruleUrl = analyzeRule.splitSourceRule(tocRule.chapterUrl ?? '');
      final ruleIsVolume = analyzeRule.splitSourceRule(tocRule.isVolume ?? '');
      final ruleIsVip = analyzeRule.splitSourceRule(tocRule.isVip ?? '');
      final ruleIsPay = analyzeRule.splitSourceRule(tocRule.isPay ?? '');
      final ruleUpdateTime = analyzeRule.splitSourceRule(tocRule.updateTime ?? '');

      for (int i = 0; i < elements.length; i++) {
        analyzeRule.setContent(elements[i]);
        analyzeRule.setBaseUrl(redirectUrl ?? baseUrl);

        final bookChapter = XiaoshuoBookChapter(
          bookUrl: book.bookUrl,
          url: '',
        );

        try {
          if (ruleName.isNotEmpty) {
            bookChapter.title = analyzeRule.getStringFromRules(ruleName);
          }
        } catch (_) {}

        try {
          if (ruleUrl.isNotEmpty) {
            bookChapter.url = analyzeRule.getStringFromRules(ruleUrl, isUrl: true);
          }
          // 规则提取失败或返回空时，尝试用 @href 作为后备
          if (bookChapter.url.isEmpty) {
            bookChapter.url = analyzeRule.getString('@href', isUrl: true);
          }
        } catch (_) {
          try {
            bookChapter.url = analyzeRule.getString('@href', isUrl: true);
          } catch (_) {}
        }

        if (bookChapter.url.isEmpty) {
          // 章节 URL 为空时跳过该章节，不使用 baseUrl（TOC URL）作为回退，
          // 否则会请求目录页而非章节页导致解析失败。
          continue;
        }

        // 跨书过滤（源可配置 ruleToc.chapterScope = "bookDir"）：
        // 某些站点（如笔趣阁移动站）的目录页混入了"最新章节预览"等栏，
        // 其中包含指向【其他书籍】的章节链接。仅当章节 URL 与目录页同属一个
        // 书籍目录（前缀一致，含结尾斜杠以区分 book_123 与 book_1234567）时
        // 才保留，剔除跨书链接。此为通用引擎能力，仅在源显式开启时生效，
        // 不影响其他源。
        //
        // 同时兼容绝对 URL（https://...）与相对路径（/book_N/...）两种格式：
        // getStringFromRules(isUrl:true) 通常会解析为绝对 URL，但某些解析路径
        // 可能返回相对路径，需双重校验。
        if (tocRule.chapterScope == 'bookDir' && baseUrl.isNotEmpty) {
          final prefix = _bookDirPrefix(baseUrl);
          if (prefix != null) {
            final absPrefix = '$prefix/';
            // 绝对 URL 前缀匹配
            if (bookChapter.url.startsWith(absPrefix)) {
              // 同一书 → 保留
            } else {
              // 相对路径兜底：从 baseUrl 和 chapterUrl 分别提取 /book_N 段比较
              final relMatch = _isSameBookDir(baseUrl, bookChapter.url);
              if (!relMatch) continue;
            }
          }
        }

        try {
          if (ruleIsVolume.isNotEmpty) {
            final isVolume = analyzeRule.getStringFromRules(ruleIsVolume);
            if (isVolume.toLowerCase() == 'true' || isVolume == '1') {
              bookChapter.isVolume = true;
            }
          }
        } catch (_) {}

        try {
          if (ruleIsVip.isNotEmpty) {
            final isVip = analyzeRule.getStringFromRules(ruleIsVip);
            if (isVip.toLowerCase() == 'true' || isVip == '1') {
              bookChapter.isVip = true;
            }
          }
        } catch (_) {}

        try {
          if (ruleIsPay.isNotEmpty) {
            final isPay = analyzeRule.getStringFromRules(ruleIsPay);
            if (isPay.toLowerCase() == 'true' || isPay == '1') {
              bookChapter.isPay = true;
            }
          }
        } catch (_) {}

        try {
          if (ruleUpdateTime.isNotEmpty) {
            bookChapter.tag = analyzeRule.getStringFromRules(ruleUpdateTime);
          }
        } catch (_) {}

        if (bookChapter.title.isNotEmpty) {
          if (!_isJunkChapterTitle(bookChapter.title) &&
              seenUrls.add(bookChapter.url)) {
            chapters.add(bookChapter);
          }
        }
      }
    } catch (_) {}

    if (reverse) {
      final reversed = chapters.reversed.toList();
      chapters.clear();
      chapters.addAll(reversed);
    }

    for (int i = 0; i < chapters.length; i++) {
      chapters[i].index = i;
    }

    return chapters;
  }

  /// 判断章节标题是否为"垃圾条目"（导航/翻页/公告/跨书预览等非正文章节）。
  ///
  /// 部分站点（如笔趣阁移动站）的目录页混合了"最新章节预览"区、翻页链接
  /// 和真正的章节列表。CSS 选择器难以精确区分时，用标题文本过滤掉
  /// 明显非章节的条目：翻页(下一页/上一页)、导航(首页/目录/书架)、
  /// 公告类(新书已发/番外发布/通知)、跨书预览(含《其他书名》的标题)。
  ///
  /// 此为**通用引擎能力**，不依赖任何具体站点，符合架构约束。
  static bool _isJunkChapterTitle(String title) {
    final t = title.trim();
    if (t.isEmpty) return true;

    // 翻页 / 导航
    if (t == '下一页' || t == '上一页' || t == '首页' || t == '目录' ||
        t == '书架' || t == '返回' || t == '返回书页') {
      return true;
    }

    // 公告 / 非章节内容
    if (t == '新书已发' || t.contains('新番外发布') ||
        t.contains('通知') || t == '更多') {
      return true;
    }

    // 跨书预览：标题含《书名》格式的通常为"最新章节预览"栏的跨书链接
    // （如 "12月1日《诡秘之主》新番外发布"、"《一个普通人的日常》最新"）
    if (RegExp(r'《[^》]+》').hasMatch(t)) {
      return true;
    }

    // 纯数字或 "第X页"
    if (RegExp(r'^第\d+页$').hasMatch(t)) return true;

    // 过短且不含中文章节特征（如 "第X章"/"第X卷"/"序章"）
    if (t.length <= 3 &&
        !RegExp(r'^第[一二三四五六七八九十百千0-9]+[章卷集部篇话]').hasMatch(t)) {
      return true;
    }

    return false;
  }

  /// 计算目录页 URL 所属书籍目录前缀（不含结尾斜杠）。
  ///
  /// 例：`https://m.biqubu3.com/book_12345/` 或
  /// `https://m.biqubu3.com/book_12345/index.html`
  /// → `https://m.biqubu3.com/book_12345`。
  /// 调用方比对时追加 "/" 以区分 `book_123` 与 `book_1234567` 这类相邻 ID。
  /// 若无法解析则返回 null（此时不过滤，保持原行为）。
  static String? _bookDirPrefix(String url) {
    try {
      final u = Uri.parse(url);
      var path = u.path;
      if (path.endsWith('/')) path = path.substring(0, path.length - 1);
      final dot = path.lastIndexOf('.');
      final slash = path.lastIndexOf('/');
      // 若路径以文件结尾（如 index.html），取其所在目录
      if (dot > slash) path = path.substring(0, slash);
      if (path.isEmpty) return null;
      return '${u.scheme}://${u.host}$path';
    } catch (_) {
      return null;
    }
  }

  /// 从 URL 中提取 /book_NNNN 段（书籍目录标识），用于跨书过滤的相对路径
  /// 兜底比对。若 URL 中不含 /book_ 数字模式则返回 null（不判定为跨书）。
  ///
  /// 例：`/book_4656/1.html` → `book_4656`
  ///     `/book_4656/`     → `book_4656`
  ///     `https://m.biqubu3.com/book_4656/1.html` → `book_4656`
  ///     `/search.php`    → null
  static String? _extractBookDirSegment(String url) {
    final match = RegExp(r'/book_(\d+)').firstMatch(url);
    return match?.group(0)?.substring(1); // 去掉前导 '/' → "book_4656"
  }

  /// 判断 [baseUrl]（目录页）与 [chapterUrl]（章节链接）是否属于同一书籍目录。
  /// 双重策略：先尝试绝对/相对路径的 /book_N 段比较；都失败则剔除（默认不过滤
  /// 不确定的链接，避免「最新章节预览」等跨书栏目中的非标准 URL 被误放行）。
  static bool _isSameBookDir(String baseUrl, String chapterUrl) {
    final baseSeg = _extractBookDirSegment(baseUrl);
    final chSeg = _extractBookDirSegment(chapterUrl);
    if (baseSeg != null && chSeg != null) return baseSeg == chSeg;
    // 无法从任一 URL 提取 book_N 段 → 剔除（安全侧：宁可少收录也不混入跨书链接）
    return false;
  }
}
