/// 网页爬取服务（浏览页 → 网页爬取）。
///
/// 基于统一 [HttpFetcher] 拉取 HTML，再用 [HtmlUtils] 按模式抽取内容。
/// 设计目标：把「抓取 + 解析」与 UI 隔离，使 browse_web_scrape_screen 只负责展示。
library;

import '../utils/html_utils.dart';
import 'http_fetcher.dart';

/// 爬取模式：影响抽取策略与结果展示形态。
enum ScrapeMode {
  general,
  novel,
  comic,
  video,
  article;
}

/// 通用链接条目（供 general 模式展示）。
class ScrapeLink {
  final String text;
  final String url;
  const ScrapeLink({required this.text, required this.url});
}

/// 爬取结果：按模式填充不同字段，UI 按需渲染。
class ScrapeResult {
  final String url;
  final String? pageTitle;
  final List<String> paragraphs;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final List<ScrapeLink> links;

  const ScrapeResult({
    required this.url,
    this.pageTitle,
    this.paragraphs = const <String>[],
    this.imageUrls = const <String>[],
    this.videoUrls = const <String>[],
    this.links = const <ScrapeLink>[],
  });

  bool get isEmpty =>
      pageTitle == null &&
      paragraphs.isEmpty &&
      imageUrls.isEmpty &&
      videoUrls.isEmpty &&
      links.isEmpty;
}

/// 网页爬取服务——全应用单例。
class WebScrapeService {
  WebScrapeService._();

  static final WebScrapeService instance = WebScrapeService._();

  /// 抓取 [url] 并按 [mode] 抽取内容。
  ///
  /// 相对地址会自动基于 [url] 解析为绝对地址。命中验证特征时抛出
  /// [VerificationRequiredException]（由调用方决定重试或跳转验证页）。
  Future<ScrapeResult> scrape(String url, ScrapeMode mode) async {
    final html = await HttpFetcher.instance.getHtml(url);
    final base = Uri.tryParse(url);
    String? absolutize(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      final uri = Uri.tryParse(raw);
      if (uri == null) return null;
      final resolved = base != null ? base.resolveUri(uri) : uri;
      return resolved.toString();
    }

    final pageTitle = HtmlUtils.query(html, 'title');

    switch (mode) {
      case ScrapeMode.general:
        final links = HtmlUtils.elements(html, 'a')
            .map((e) => ScrapeLink(
                  text: e.text.trim(),
                  url: absolutize(e.attributes['href']) ?? '',
                ))
            .where((l) => l.url.isNotEmpty)
            .toList();
        return ScrapeResult(url: url, pageTitle: pageTitle, links: links);

      case ScrapeMode.novel:
      case ScrapeMode.article:
        final paragraphs = HtmlUtils.queryAll(html, 'p')
            .where((s) => s.trim().length > 1)
            .toList();
        final imageUrls = mode == ScrapeMode.article
            ? _extractImages(html)
                .map((s) => absolutize(s))
                .where((s) => s != null)
                .cast<String>()
                .toList()
            : const <String>[];
        return ScrapeResult(
          url: url,
          pageTitle: pageTitle,
          paragraphs: paragraphs,
          imageUrls: imageUrls,
        );

      case ScrapeMode.comic:
        final imageUrls = _extractImages(html)
            .map((s) => absolutize(s))
            .where((s) => s != null)
            .cast<String>()
            .toList();
        return ScrapeResult(url: url, pageTitle: pageTitle, imageUrls: imageUrls);

      case ScrapeMode.video:
        final videoUrls = _extractVideos(html)
            .map((s) => absolutize(s))
            .where((s) => s != null)
            .cast<String>()
            .toList();
        return ScrapeResult(url: url, pageTitle: pageTitle, videoUrls: videoUrls);
    }
  }

  List<String> _extractImages(String html) => HtmlUtils.elements(html, 'img')
      .map((e) =>
          e.attributes['src'] ??
          e.attributes['data-src'] ??
          e.attributes['data-original'] ??
          '')
      .where((s) => s.isNotEmpty)
      .toList();

  List<String> _extractVideos(String html) {
    final list = <String>[];
    for (final e in HtmlUtils.elements(html, 'video')) {
      final src = e.attributes['src'];
      if (src != null && src.isNotEmpty) list.add(src);
    }
    for (final e in HtmlUtils.elements(html, 'video source')) {
      final src = e.attributes['src'];
      if (src != null && src.isNotEmpty) list.add(src);
    }
    for (final e in HtmlUtils.elements(html, 'iframe')) {
      final src = e.attributes['src'];
      if (src != null && src.isNotEmpty) list.add(src);
    }
    return list;
  }
}
