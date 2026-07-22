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
      final elements = analyzeRule.getElements(listRule);

      if (elements.isEmpty) return chapters;

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
          chapters.add(bookChapter);
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
}
