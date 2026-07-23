/// WebBook 门面：对外暴露搜索/发现/详情/目录/正文五类 API，
/// 内部组合 [AnalyzeUrl]（URL 模板与抓取）+ 静态分析器（BookList/BookInfo/
/// BookChapterList/BookContent）执行规则解析。
///
/// 与旧版相比，移除了 NovelResolverRegistry/BuiltinNovelResolver 间接层，
/// 直接基于 XiaoshuoHttp/AnalyzeUrl + 静态分析方法实现，便于在新项目架构下复用。
library;

import '../analyze/analyze_rule.dart';
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
  ///
  /// **目录分页跟随**：部分站点（如笔趣阁移动站）将章节目录拆成多页
  /// （`/book_N/`、`/book_N/index_2.html`…）。若书源声明了
  /// `ruleToc.nextTocUrl`，本方法会沿"下一页"链接继续抓取后续目录页，
  /// 合并全部章节。带访问去重与最大页数上限（默认 200 页），杜绝死循环。
  ///
  /// **渐进式分批回调 [onBatch]**：超长书（如诡秘之主 1416 章）目录可达 70+ 页，
  /// 串行抓完需多次网络请求。为避免调用方整页被阻塞，本方法在解析完**首页**
  /// 后立即通过 [onBatch] 回传首批章节，之后每抓完一页目录再回传该页增量；
  /// 最终仍返回合并后的完整列表（供调用方做最终校正）。上层据此可实现
  /// "首屏快显前若干章 + 底部加载中 + 后台续抓"的体验。每个批次的章节
  /// [XiaoshuoBookChapter.index] 已被重编号为**全局连续序号**（0 起），便于
  /// 上层按 id 去重合并。
  Future<List<XiaoshuoBookChapter>> getChapterList({
    required XiaoshuoBookSource source,
    required XiaoshuoBook book,
    void Function(List<XiaoshuoBookChapter>)? onBatch,
  }) async {
    final tocRule = source.getTocRule();
    final tocUrl = (book.tocUrl != null && book.tocUrl!.isNotEmpty)
        ? book.tocUrl!
        : book.bookUrl;
    final analyzeUrl = AnalyzeUrl(
      url: tocUrl,
      baseUrl: source.bookSourceUrl,
      source: source,
    );

    final body = await analyzeUrl.getStrResponse();
    if (body.isEmpty) return <XiaoshuoBookChapter>[];

    final allChapters = BookChapterList.analyzeChapterList(
      bookSource: source,
      book: book,
      baseUrl: analyzeUrl.url,
      redirectUrl: analyzeUrl.url,
      body: body,
    );

    // 首页批次：先回传已解析的首页章节，让上层即时渲染（无需等后续分页）。
    if (allChapters.isNotEmpty) {
      for (var i = 0; i < allChapters.length; i++) {
        allChapters[i].index = i;
      }
      onBatch?.call(List<XiaoshuoBookChapter>.from(allChapters));
    }

    // 目录分页跟随：若声明了 nextTocUrl 且当前页有"下一页"链接，继续抓取。
    final nextTocRule = tocRule.nextTocUrl;
    if (nextTocRule != null && nextTocRule.isNotEmpty && allChapters.isNotEmpty) {
      final visited = <String>{analyzeUrl.url};
      var currentUrl = analyzeUrl.url;
      var currentBody = body;
      // 目录分页上限：部分超长书（如诡秘之主 1416 章）目录可达 70+ 页。
      // 已有 visited 去重防死循环，上限仅作安全阀。原 20 对长书严重不足（只能
      // 解析约 400 章），提升到 200 覆盖 4000 章以内的任何书籍。
      const maxTocPages = 200;

      for (var i = 0; i < maxTocPages; i++) {
        final nextUrl = _extractNextTocUrl(currentBody, currentUrl, nextTocRule);
        if (nextUrl.isEmpty || visited.contains(nextUrl)) break;
        visited.add(nextUrl);

        final pageAnalyze = AnalyzeUrl(
          url: nextUrl,
          baseUrl: source.bookSourceUrl,
          source: source,
        );
        final pageBody = await pageAnalyze.getStrResponse();
        if (pageBody.isEmpty) break;

        final pageChapters = BookChapterList.analyzeChapterList(
          bookSource: source,
          book: book,
          baseUrl: pageAnalyze.url,
          redirectUrl: pageAnalyze.url,
          body: pageBody,
        );
        if (pageChapters.isEmpty) break;

        // 本页增量批次：以全局连续序号重编号后再回传，避免与已回传批次的
        // index（Episode.id）冲突导致上层合并时覆盖。
        final startIdx = allChapters.length;
        for (var i = 0; i < pageChapters.length; i++) {
          pageChapters[i].index = startIdx + i;
        }
        allChapters.addAll(pageChapters);
        onBatch?.call(List<XiaoshuoBookChapter>.from(pageChapters));
        currentUrl = pageAnalyze.url;
        currentBody = pageBody;
      }

      // 兜底重编号（增量批次已保证连续，此处仅为安全网）。
      for (var i = 0; i < allChapters.length; i++) {
        allChapters[i].index = i;
      }
    }

    return allChapters;
  }

  /// 获取章节正文：抓取 `chapterUrl` 并通过 `ruleContent` 解析。
  ///
  /// **正文分页跟随**：许多站点把单章正文拆成多页（`xxx.html`、`xxx_2.html`…）。
  /// 若书源声明了 `ruleContent.nextContentUrl`，本方法会沿"下一页"链接继续抓取
  /// 并拼接，直到没有下一页为止。为避免误把"下一章"链接当成"下一页"（二者在
  /// 部分站点的最后一页共用同一元素），仅当下一页 URL 与当前页属于**同一章**
  /// （目录相同、去掉 `_N` 分页后缀后的文件名相同）时才继续跟随；并带访问去重
  /// 与最大页数上限，杜绝死循环。此为通用引擎能力，对所有分页书源生效。
  Future<BookContentResult> getContent({
    required XiaoshuoBookSource source,
    required String chapterUrl,
    XiaoshuoBook? originalBook,
  }) async {
    final contentRule = source.getContentRule();
    final book = originalBook ?? XiaoshuoBook(bookUrl: '', name: '');

    final firstAnalyze = AnalyzeUrl(
      url: chapterUrl,
      baseUrl: source.bookSourceUrl,
      source: source,
    );

    final firstBody = await firstAnalyze.getStrResponse();
    if (firstBody.isEmpty) {
      return BookContentResult(content: '', error: '正文为空');
    }

    final buffer = StringBuffer();
    final firstContent = BookContent.analyzeContent(
      bookSource: source,
      book: book,
      bookChapter: XiaoshuoBookChapter(bookUrl: '', url: chapterUrl),
      baseUrl: firstAnalyze.url,
      redirectUrl: firstAnalyze.url,
      body: firstBody,
    );
    buffer.write(firstContent);

    final nextRule = contentRule.nextContentUrl;
    if (nextRule != null && nextRule.isNotEmpty) {
      // 章节根：起始 chapterUrl 即为本章第 1 页，同章后续页必为
      // `<根>_<数字>` / `<根>-<数字>` / `<根>/<数字>` 形式（见 _isNextPageOfChapter）。
      final chapterRoot = _chapterRootOf(firstAnalyze.url);
      final visited = <String>{chapterUrl, firstAnalyze.url};
      var currentUrl = firstAnalyze.url;
      var currentBody = firstBody;
      const maxPages = 30;
      for (var i = 0; i < maxPages; i++) {
        final nextUrl =
            _extractNextContentUrl(currentBody, currentUrl, nextRule);
        if (nextUrl.isEmpty || visited.contains(nextUrl)) break;
        if (!_isNextPageOfChapter(chapterRoot, nextUrl)) break;
        visited.add(nextUrl);

        final pageAnalyze = AnalyzeUrl(
          url: nextUrl,
          baseUrl: source.bookSourceUrl,
          source: source,
        );
        final pageBody = await pageAnalyze.getStrResponse();
        if (pageBody.isEmpty) break;

        final pageContent = BookContent.analyzeContent(
          bookSource: source,
          book: book,
          bookChapter: XiaoshuoBookChapter(bookUrl: '', url: nextUrl),
          baseUrl: pageAnalyze.url,
          redirectUrl: pageAnalyze.url,
          body: pageBody,
        );
        if (pageContent.trim().isEmpty) break;

        buffer.write('\n');
        buffer.write(pageContent);
        currentUrl = pageAnalyze.url;
        currentBody = pageBody;
      }
    }

    final content = buffer.toString();
    if (content.trim().isEmpty) {
      return BookContentResult(content: '', error: '解析失败');
    }

    // 最终统一格式化：确保多页拼接后的输出完全一致，消除"同章不同页排版不同"。
    // 每页已独立做过缩进/清洗（analyzeContent 内），但各页 HTML 结构可能略有差异
    // （如页1用<br>分段、页2用<p>分段），导致微小残留不一致。
    // 此处做最终归一化：统一缩进、统一空行、统一行尾空白。
    final normalized = _normalizeMultiPageContent(content);
    return BookContentResult(content: normalized);
  }

  /// 多页正文最终归一化：拆行 → 去首尾空白 → 过滤纯空行 → 幂等去缩进 + 统一加缩进 → 重拼。
  ///
  /// 消除"同一章内翻页排版不一致"的最后一道防线：无论各子页原始 HTML 结构
  /// 差异如何（<br> vs <p>、有无源码缩进、空行数量），最终输出均为：
  /// 每非空行恰好一个全角缩进（　　）+ 纯文本内容，行间单换行分隔。
  ///
  /// **幂等保证**：先移除行首可能存在的全角/半角缩进（兼容子页已被
  /// [book_content] 加过缩进的场景），再统一加一个全角空格，确保最终
  /// 缩进恰好为 2 全角宽（　　），不会叠加。
  static String _normalizeMultiPageContent(String raw) {
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) {
          // 幂等：先去掉已有的任何前导缩进（全角/半角空格/tab），再统一加
          final stripped = line.replaceFirst(RegExp(r'^[　\s\t]+'), '');
          return '　　$stripped';
        })
        .join('\n');
  }

  /// 从当前页正文中提取"下一页"绝对 URL；无下一页时返回空串。
  String _extractNextContentUrl(String body, String baseUrl, String rule) {
    try {
      final analyzeRule = AnalyzeRule()
        ..setContent(body, baseUrl)
        ..setBaseUrl(baseUrl)
        ..setRedirectUrl(baseUrl);
      final url = analyzeRule.getString(rule, isUrl: true).trim();
      // isUrl 规则命中为空时会回退返回 baseUrl，视为"无下一页"。
      if (url.isEmpty || url == baseUrl) return '';
      return url;
    } catch (_) {
      return '';
    }
  }

  /// 从当前目录页中提取"下一页"绝对 URL；无下一页时返回空串。
  ///
  /// 逻辑与 [_extractNextContentUrl] 一致，但语义上用于目录分页跟随。
  String _extractNextTocUrl(String body, String baseUrl, String rule) {
    try {
      final analyzeRule = AnalyzeRule()
        ..setContent(body, baseUrl)
        ..setBaseUrl(baseUrl)
        ..setRedirectUrl(baseUrl);
      final url = analyzeRule.getString(rule, isUrl: true).trim();
      if (url.isEmpty || url == baseUrl) return '';
      return url;
    } catch (_) {
      return '';
    }
  }

  /// 计算章节根：host + path（去扩展名）。作为「本章第 1 页」的唯一标识。
  ///
  /// 起始 chapterUrl 一定是本章第 1 页（来自目录），因此其去扩展名后的
  /// host+path 即章节根 X；同章后续页的 URL 必然是 `X` 追加 `_N`/`-N`/`/N`。
  String _chapterRootOf(String url) {
    try {
      final u = Uri.parse(url);
      var path = u.path;
      final dot = path.lastIndexOf('.');
      final slash = path.lastIndexOf('/');
      if (dot > slash) path = path.substring(0, dot); // 去扩展名
      return '${u.host}$path';
    } catch (_) {
      return url;
    }
  }

  /// 判断 [nextUrl] 是否为章节根 [chapterRoot] 的「后续分页」。
  ///
  /// 仅当 nextUrl 去扩展名后 == `chapterRoot` 追加 `[-_/]<数字>`（可叠加多级，
  /// 如第 3 页 `X_2_3` 或 `X_3`）时为真。这样既能命中 `X.html→X_2.html`
  /// 的真实分页，又能可靠拒绝「下一章」——即使下一章的 URL 尾号只差 1
  /// （如 `..._3574.html`→`..._3573.html`），因为它不是 `X` 的前缀扩展。
  /// 通用规则，不含任何站点/域名硬编码。
  bool _isNextPageOfChapter(String chapterRoot, String nextUrl) {
    try {
      final u = Uri.parse(nextUrl);
      var path = u.path;
      final dot = path.lastIndexOf('.');
      final slash = path.lastIndexOf('/');
      if (dot > slash) path = path.substring(0, dot);
      final next = '${u.host}$path';
      if (next == chapterRoot) return false; // 同一页，避免自循环
      final esc = RegExp.escape(chapterRoot);
      return RegExp('^$esc([-_/]\\d+)+\$').hasMatch(next);
    } catch (_) {
      return false;
    }
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
