/// WebBook 门面：对外暴露搜索/发现/详情/目录/正文五类 API，
/// 内部组合 [AnalyzeUrl]（URL 模板与抓取）+ 静态分析器（BookList/BookInfo/
/// BookChapterList/BookContent）执行规则解析。
///
/// 与旧版相比，移除了 NovelResolverRegistry/BuiltinNovelResolver 间接层，
/// 直接基于 XiaoshuoHttp/AnalyzeUrl + 静态分析方法实现，便于在新项目架构下复用。
library;

import '../analyze/analyze_url.dart';
import '../model/book_source.dart';
import '../model/search_book.dart';
import '../model/xiaoshuo_book.dart';
import '../model/xiaoshuo_book_chapter.dart';
import 'book_chapter_list.dart';
import 'book_content.dart';
import 'book_info.dart';
import 'book_list.dart';
import 'web_book_types.dart';

export 'web_book_types.dart';

class WebBook {
  /// 搜索书籍：按 `source.searchUrl` 模板抓取并通过 `ruleSearch` 解析。
  Future<List<SearchBook>> searchBook({
    required XiaoshuoBookSource source,
    required String key,
    int page = 1,
  }) async {
    final searchUrl = source.searchUrl;
    if (searchUrl == null || searchUrl.isEmpty) {
      throw Exception('书源未配置 searchUrl');
    }

    final analyzeUrl = AnalyzeUrl(
      url: searchUrl,
      baseUrl: source.bookSourceUrl,
      source: source,
      key: key,
      page: page,
    );

    final body = await analyzeUrl.getStrResponse();
    if (body.isEmpty) return <SearchBook>[];

    return BookList.analyzeBookList(
      bookSource: source,
      baseUrl: analyzeUrl.url,
      body: body,
      isSearch: true,
    );
  }

  /// 解析书源的发现分类列表（基于 `exploreUrl` 多级 URL 字符串）。
  List<ExploreCategory> getExploreCategories(XiaoshuoBookSource source) {
    final exploreUrl = source.exploreUrl;
    if (exploreUrl == null || exploreUrl.isEmpty) {
      return <ExploreCategory>[];
    }

    // JSON 数组格式的 exploreUrl
    if (exploreUrl.trim().startsWith('[')) {
      final result = _parseRawJsonArray(exploreUrl);
      if (result.isNotEmpty) {
        final entries = parseMultiLevelUrls(result);
        return entries
            .map((e) => ExploreCategory(
                  name: e.name.isNotEmpty ? e.name : e.url,
                  url: e.url,
                ))
            .toList();
      }
    }

    final urlEntries = parseMultiLevelUrls(exploreUrl);
    return urlEntries
        .map((e) => ExploreCategory(
              name: e.name.isNotEmpty ? e.name : e.url,
              url: e.url,
            ))
        .toList();
  }

  /// 抓取发现页（按分类 URL 列表逐个请求并合并结果）。
  Future<List<XiaoshuoBook>> exploreBook({
    required XiaoshuoBookSource source,
    int page = 1,
  }) async {
    final exploreUrl = source.exploreUrl;
    if (exploreUrl == null || exploreUrl.isEmpty) {
      throw Exception('书源未配置 exploreUrl');
    }

    var urlEntries = parseMultiLevelUrls(exploreUrl);
    if (urlEntries.isEmpty) {
      final trimmed = exploreUrl.trim();
      if (trimmed.isNotEmpty) {
        urlEntries = [UrlEntry(name: '', url: trimmed)];
      }
    }
    if (urlEntries.isEmpty) {
      throw Exception('无法解析书源分类，请检查书源配置');
    }

    final allBooks = <XiaoshuoBook>[];
    for (final entry in urlEntries) {
      try {
        final books = await exploreCategory(
          source: source,
          categoryUrl: entry.url,
          page: page,
        );
        for (final book in books) {
          // 发现页分类名附加到 intro 以便展示来源分类
          if (entry.name.isNotEmpty) {
            book.intro = entry.name;
          }
          allBooks.add(book);
        }
      } catch (_) {
        continue;
      }
    }
    return allBooks;
  }

  /// 抓取指定分类 URL 的书籍列表。
  Future<List<XiaoshuoBook>> exploreCategory({
    required XiaoshuoBookSource source,
    required String categoryUrl,
    int page = 1,
  }) async {
    final analyzeUrl = AnalyzeUrl(
      url: categoryUrl,
      baseUrl: source.bookSourceUrl,
      source: source,
      page: page,
    );

    final body = await analyzeUrl.getStrResponse();
    if (body.isEmpty) return <XiaoshuoBook>[];

    BookList.setCurrentCategoryName('');

    final searchBooks = BookList.analyzeBookList(
      bookSource: source,
      baseUrl: analyzeUrl.url,
      body: body,
      isSearch: false,
    );

    return searchBooks
        .map((sb) => XiaoshuoBook(
              bookUrl: sb.bookUrl,
              name: sb.name,
              author: sb.author,
              coverUrl: sb.coverUrl,
              kind: sb.kind,
              lastChapter: sb.lastChapter,
              type: sb.type,
            ))
        .toList();
  }

  /// 获取书籍详情：抓取 `bookUrl` 并通过 `ruleBookInfo` 解析。
  Future<XiaoshuoBook> getBookInfo({
    required XiaoshuoBookSource source,
    required String bookUrl,
  }) async {
    final analyzeUrl = AnalyzeUrl(
      url: bookUrl,
      baseUrl: source.bookSourceUrl,
      source: source,
    );

    final body = await analyzeUrl.getStrResponse();

    final book = XiaoshuoBook(bookUrl: bookUrl, name: '');
    BookInfo.analyzeBookInfo(
      bookSource: source,
      book: book,
      baseUrl: analyzeUrl.url,
      redirectUrl: analyzeUrl.url,
      body: body,
    );
    return book;
  }

  /// 获取章节目录：根据书籍的 `tocUrl`（缺省时回退到 `bookUrl`）抓取并解析。
  Future<List<XiaoshuoBookChapter>> getChapterList({
    required XiaoshuoBookSource source,
    required XiaoshuoBook book,
  }) async {
    final tocUrl = (book.tocUrl != null && book.tocUrl!.isNotEmpty)
        ? book.tocUrl!
        : book.bookUrl;
    final analyzeUrl = AnalyzeUrl(
      url: tocUrl,
      baseUrl: source.bookSourceUrl,
      source: source,
    );

    final body = await analyzeUrl.getStrResponse();

    return BookChapterList.analyzeChapterList(
      bookSource: source,
      book: book,
      baseUrl: analyzeUrl.url,
      redirectUrl: analyzeUrl.url,
      body: body,
    );
  }

  /// 获取章节正文：抓取 `chapterUrl` 并通过 `ruleContent` 解析。
  Future<BookContentResult> getContent({
    required XiaoshuoBookSource source,
    required String chapterUrl,
    XiaoshuoBook? originalBook,
  }) async {
    final analyzeUrl = AnalyzeUrl(
      url: chapterUrl,
      baseUrl: source.bookSourceUrl,
      source: source,
    );

    final body = await analyzeUrl.getStrResponse();
    if (body.isEmpty) {
      return BookContentResult(content: '', error: '正文为空');
    }

    final chapter = XiaoshuoBookChapter(bookUrl: '', url: chapterUrl);
    final content = BookContent.analyzeContent(
      bookSource: source,
      book: originalBook ?? XiaoshuoBook(bookUrl: '', name: ''),
      bookChapter: chapter,
      baseUrl: analyzeUrl.url,
      redirectUrl: analyzeUrl.url,
      body: body,
    );

    if (content.isEmpty) {
      return BookContentResult(content: '', error: '解析失败');
    }
    return BookContentResult(content: content);
  }

  /// 兼容旧调用：从详情页取封面 URL。
  Future<String?> fetchCoverFromDetail({
    required XiaoshuoBookSource source,
    required String bookUrl,
  }) async {
    if (bookUrl.isEmpty || !bookUrl.startsWith('http')) return null;
    try {
      final book = await getBookInfo(source: source, bookUrl: bookUrl);
      final coverUrl = book.coverUrl;
      if (coverUrl != null && coverUrl.isNotEmpty) {
        return coverUrl;
      }
    } catch (_) {}
    return null;
  }

  /// 解析 JSON 数组形式的 exploreUrl：返回 `名称::URL` 多行字符串。
  static String _parseRawJsonArray(String jsonStr) {
    final entries = <String>[];
    final seen = <String>{};

    final objPattern = RegExp(
        '\\{\\s*["\'](?:title|name)["\']\\s*:\\s*["\']([^"\']+)["\']\\s*,\\s*["\']url["\']\\s*:\\s*["\']([^"\']+)["\']');
    for (final match in objPattern.allMatches(jsonStr)) {
      final title = match.group(1) ?? '';
      final url = match.group(2) ?? '';
      if (title.isNotEmpty && url.isNotEmpty && !_isCodeKeyword(title)) {
        final entry = '$title::$url';
        if (!seen.contains(entry)) {
          seen.add(entry);
          entries.add(entry);
        }
      }
    }

    final objPatternReverse = RegExp(
        '\\{\\s*["\']url["\']\\s*:\\s*["\']([^"\']+)["\']\\s*,\\s*["\'](?:title|name)["\']\\s*:\\s*["\']([^"\']+)["\']');
    for (final match in objPatternReverse.allMatches(jsonStr)) {
      final url = match.group(1) ?? '';
      final title = match.group(2) ?? '';
      if (title.isNotEmpty && url.isNotEmpty && !_isCodeKeyword(title)) {
        final entry = '$title::$url';
        if (!seen.contains(entry)) {
          seen.add(entry);
          entries.add(entry);
        }
      }
    }

    if (entries.isNotEmpty) {
      return entries.join('\n');
    }
    return '';
  }

  static bool _isCodeKeyword(String s) {
    const keywords = [
      'function', 'var ', 'let ', 'const ', 'push', 'result',
      'return', 'typeof', 'undefined', 'JSON', 'String',
      'Number', 'Boolean', 'Array', 'Object', 'this', 'new',
      'if', 'else', 'for', 'while', 'do', 'switch', 'case',
      'try', 'catch', 'finally', 'throw', 'class', 'extends',
      'import', 'export', 'default', 'async', 'await',
    ];
    final lower = s.toLowerCase();
    for (final keyword in keywords) {
      if (lower.contains(keyword.toLowerCase())) return true;
    }
    return false;
  }
}
