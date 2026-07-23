/// 书籍详情解析：依据书源 `ruleBookInfo` 解析书名/作者/简介/封面/目录 URL 等字段。
library;

import '../model/book_source.dart';
import '../model/xiaoshuo_book.dart';
import '../analyze/analyze_rule.dart';

class BookInfo {
  static void analyzeBookInfo({
    required XiaoshuoBookSource bookSource,
    required XiaoshuoBook book,
    required String baseUrl,
    required String? redirectUrl,
    required String body,
    bool canReName = true,
  }) {
    final bookInfoRule = bookSource.getBookInfoRule();
    final analyzeRule = AnalyzeRule(book: book)
      ..setContent(body, redirectUrl ?? baseUrl)
      ..setBaseUrl(baseUrl)
      ..setRedirectUrl(redirectUrl ?? baseUrl);

    if (bookInfoRule.init != null && bookInfoRule.init!.isNotEmpty) {
      try {
        final initContent = analyzeRule.getElement(bookInfoRule.init!);
        if (initContent != null) {
          analyzeRule.setContent(initContent);
        }
      } catch (_) {}
    }

    final canReNameFlag = canReName && (bookInfoRule.canReName?.isEmpty ?? true);

    if (bookInfoRule.name != null && bookInfoRule.name!.isNotEmpty) {
      try {
        final name = _formatBookName(analyzeRule.getString(bookInfoRule.name!));
        if (name.isNotEmpty && (canReNameFlag || book.name.isEmpty)) {
          book.name = name;
        }
      } catch (_) {}
    }

    if (bookInfoRule.author != null && bookInfoRule.author!.isNotEmpty) {
      try {
        final author = _formatBookAuthor(analyzeRule.getString(bookInfoRule.author!));
        if (author.isNotEmpty && (canReNameFlag || book.author.isEmpty)) {
          book.author = author;
        }
      } catch (_) {}
    }

    if (bookInfoRule.kind != null && bookInfoRule.kind!.isNotEmpty) {
      try {
        final kinds = analyzeRule.getStringList(bookInfoRule.kind!);
        if (kinds.isNotEmpty) {
          book.kind = kinds.join(',');
          if (book.kind!.length > 1000) book.kind = book.kind!.substring(0, 1000);
        }
      } catch (_) {}
    }

    if (bookInfoRule.lastChapter != null && bookInfoRule.lastChapter!.isNotEmpty) {
      try {
        final lastChapter = analyzeRule.getString(bookInfoRule.lastChapter!);
        if (lastChapter.isNotEmpty) {
          book.lastChapter = lastChapter;
        }
      } catch (_) {}
    }

    if (bookInfoRule.intro != null && bookInfoRule.intro!.isNotEmpty) {
      try {
        final intro = analyzeRule.getString(bookInfoRule.intro!);
        if (intro.isNotEmpty) {
          book.intro = intro.length > 5000 ? intro.substring(0, 5000) : intro;
        }
      } catch (_) {}
    }

    if (bookInfoRule.bookStatus != null && bookInfoRule.bookStatus!.isNotEmpty) {
      try {
        final bookStatus = analyzeRule.getString(bookInfoRule.bookStatus!);
        if (bookStatus.isNotEmpty) {
          book.bookStatus = bookStatus;
        }
      } catch (_) {}
    }

    if (bookInfoRule.updateTime != null && bookInfoRule.updateTime!.isNotEmpty) {
      try {
        final updateTime = analyzeRule.getString(bookInfoRule.updateTime!);
        if (updateTime.isNotEmpty) {
          book.updateTime = updateTime;
        }
      } catch (_) {}
    }

    if (bookInfoRule.recommendations != null &&
        bookInfoRule.recommendations!.isNotEmpty) {
      try {
        final recommendations =
            analyzeRule.getStringList(bookInfoRule.recommendations!);
        if (recommendations.isNotEmpty) {
          book.recommendations = recommendations
              .where((s) => s.trim().isNotEmpty)
              .map((s) => s.trim())
              .toList();
        }
      } catch (_) {}
    }

    if (bookInfoRule.coverUrl != null && bookInfoRule.coverUrl!.isNotEmpty) {
      try {
        final coverUrl = analyzeRule.getString(bookInfoRule.coverUrl!, isUrl: true);
        if (coverUrl.isNotEmpty) {
          book.coverUrl = coverUrl;
        }
      } catch (_) {}
    }

    if (bookInfoRule.tocUrl != null && bookInfoRule.tocUrl!.isNotEmpty) {
      try {
        final tocUrl = analyzeRule.getString(bookInfoRule.tocUrl!, isUrl: true);
        if (tocUrl.isNotEmpty) {
          book.tocUrl = tocUrl;
        }
      } catch (_) {}
    }

    if (book.tocUrl == null || book.tocUrl!.isEmpty) {
      book.tocUrl = redirectUrl ?? baseUrl;
    }
  }

  static String _formatBookName(String name) {
    if (name.isEmpty) return name;
    return name
        .replaceAll(RegExp(r'[【［【\[\(（]([^【［【\[\(（]*?)[】］】\]\)）]'), '')
        .replaceAll(RegExp(r'^\s*[\-_—–]+'), '')
        .replaceAll(RegExp(r'[\-_—–]+\s*$'), '')
        .trim();
  }

  static String _formatBookAuthor(String author) {
    if (author.isEmpty) return author;
    return author
        // 去除 "作者:" / "作者：" 前缀（与 book_list.formatBookAuthor 一致，
        // 用字面序列匹配而非字符类 [作者：]，后者只删首字"作"）
        .replaceAll(RegExp(r'^\s*作\s*者\s*[:：]\s*'), '')
        .replaceAll(RegExp(r'^\s*[\-_—–]+'), '')
        .replaceAll(RegExp(r'[\-_—–]+\s*$'), '')
        .trim();
  }
}
