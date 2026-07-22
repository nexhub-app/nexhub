/// 书源解析器：实现 [SourceResolver]，桥接 PluginConfig →
/// XiaoshuoBookSource → WebBook，让书源能被 MediaApiService
/// 统一调度。
///
/// 触发条件：当 PluginConfig.selectors['xiaoshuo'] 为 Map 时（由
/// [ShuyuanAdapter] 写入），ResolverRegistry.find() 返回本解析器。
///
/// API 映射：
/// - `search`：WebBook.searchBook(key=vars['keyword'])
/// - `explore`/`latest`：WebBook.exploreBook / exploreCategory
/// - `detail`：WebBook.getBookInfo(bookUrl=vars['id'])
/// - `toc`/`chapters`：WebBook.getChapterList(book=by id)
/// - `content`：WebBook.getContent(chapterUrl=vars['url'])
library;

import '../../../core/models/episode.dart';
import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/resolver/source_resolver.dart';
import '../../../core/scraper/verification_detector.dart';
import '../model/book_source.dart';
import '../model/search_book.dart';
import '../model/xiaoshuo_book.dart';
import '../shuyuan_adapter.dart';
import '../web_book/web_book.dart';

class ShuyuanNovelResolver implements SourceResolver {
  ShuyuanNovelResolver();

  final WebBook _webBook = WebBook();

  @override
  Future<dynamic> resolve(
    PluginConfig source,
    String apiName, {
    Map<String, String> vars = const {},
  }) async {
    final shuyuanSource = ShuyuanAdapter.fromPluginConfig(source);
    if (shuyuanSource == null) {
      throw StateError(
        'ShuyuanNovelResolver received a non-shuyuan source: ${source.id}',
      );
    }
    final bookSource = shuyuanSource.toBookSource();

    switch (apiName) {
      case 'search':
        return _handleSearch(source, bookSource, vars);
      case 'explore':
        return _handleExplore(source, bookSource, vars);
      case 'latest':
        return _handleLatest(source, bookSource, vars);
      case 'detail':
        return _handleDetail(source, bookSource, vars);
      case 'toc':
      case 'chapters':
        return _handleChapterList(source, bookSource, vars);
      case 'content':
        return _handleContent(source, bookSource, vars);
      default:
        throw UnsupportedError(
          'ShuyuanNovelResolver does not support apiName: $apiName',
        );
    }
  }

  // ── 搜索 ──
  Future<List<MediaItem>> _handleSearch(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final keyword = vars['keyword'] ?? vars['key'] ?? vars['title'] ?? '';
    if (keyword.isEmpty) return <MediaItem>[];

    final page = int.tryParse(vars['page'] ?? '1') ?? 1;
    final results = await _webBook.searchBook(
      source: bookSource,
      key: keyword,
      page: page,
    );
    return results.map((sb) => _searchBookToMediaItem(sb, source.id)).toList();
  }

  // ── 发现：按分类 URL 抓取 ──
  Future<List<MediaItem>> _handleExplore(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final categoryUrl = vars['category'];
    final page = int.tryParse(vars['page'] ?? '1') ?? 1;

    if (categoryUrl != null && categoryUrl.isNotEmpty) {
      final books = await _webBook.exploreCategory(
        source: bookSource,
        categoryUrl: categoryUrl,
        page: page,
      );
      return books.map((b) => _xiaoshuoBookToMediaItem(b, source.id)).toList();
    }

    // 没指定分类时，走全量发现页
    final books = await _webBook.exploreBook(source: bookSource, page: page);
    return books.map((b) => _xiaoshuoBookToMediaItem(b, source.id)).toList();
  }

  // ── latest：等同 explore（发现页） ──
  Future<List<MediaItem>> _handleLatest(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    return _handleExplore(source, bookSource, vars);
  }

  // ── 详情 ──
  Future<MediaItem> _handleDetail(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final id = vars['id'] ?? vars['detailUrl'] ?? '';
    if (id.isEmpty) {
      throw ArgumentError('detail requires vars["id"]');
    }
    final book = await _webBook.getBookInfo(source: bookSource, bookUrl: id);
    return _xiaoshuoBookToMediaItem(book, source.id);
  }

  // ── 章节列表 ──
  Future<List<Episode>> _handleChapterList(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final id = vars['id'] ?? vars['detailUrl'] ?? '';
    if (id.isEmpty) {
      throw ArgumentError('chapters requires vars["id"]');
    }
    // WebBook.getChapterList 需要 XiaoshuoBook 来获取 tocUrl；用 bookUrl=id 构造。
    final book = XiaoshuoBook(bookUrl: id, name: '');
    final chapters = await _webBook.getChapterList(
      source: bookSource,
      book: book,
    );
    return chapters
        .map((c) => Episode(
              id: '${c.index}',
              title: c.title,
              url: c.url,
            ))
        .toList();
  }

  // ── 正文 ──
  Future<List<String>> _handleContent(
    PluginConfig source,
    XiaoshuoBookSource bookSource,
    Map<String, String> vars,
  ) async {
    final chapterUrl = vars['url'] ?? vars['chapter'] ?? '';
    if (chapterUrl.isEmpty) {
      throw ArgumentError('content requires vars["url"]');
    }
    final result = await _webBook.getContent(
      source: bookSource,
      chapterUrl: chapterUrl,
    );
    if (result.error != null && result.content.isEmpty) {
      throw SourceResolveException(
        sourceId: source.id,
        apiName: 'content',
        message: result.error ?? 'resolve error',
      );
    }
    // 段落列表：按换行切分，过滤空行
    return result.content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  // ── 模型转换 ──
  MediaItem _searchBookToMediaItem(SearchBook sb, String sourceId) {
    return MediaItem(
      id: sb.bookUrl,
      title: sb.name,
      coverUrl: sb.coverUrl,
      detailUrl: sb.bookUrl,
      sourceId: sourceId,
      sourceType: SourceType.novelSource,
      author: sb.author.isNotEmpty ? sb.author : null,
      tags: sb.kind?.split(',').where((s) => s.isNotEmpty).toList(),
    );
  }

  MediaItem _xiaoshuoBookToMediaItem(XiaoshuoBook book, String sourceId) {
    return MediaItem(
      id: book.bookUrl,
      title: book.name,
      coverUrl: book.coverUrl,
      detailUrl: book.bookUrl,
      sourceId: sourceId,
      sourceType: SourceType.novelSource,
      author: book.author.isNotEmpty ? book.author : null,
      description: book.intro,
      status: book.bookStatus,
      tags: book.kind?.split(',').where((s) => s.isNotEmpty).toList(),
    );
  }
}
