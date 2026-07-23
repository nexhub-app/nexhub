/// 章节正文解析：依据书源 `ruleContent` 解析章节正文，支持规则替换、
/// fallback 选择器探测、广告清理与 HTML 标签剥离。
library;

import 'package:html/parser.dart' as html_parser;

import '../model/book_source.dart';
import '../model/xiaoshuo_book.dart';
import '../model/xiaoshuo_book_chapter.dart';
import '../analyze/analyze_rule.dart';

class BookContent {
  // 预编译正则
  static final _brRegex = RegExp(r'<br\s*/?\s*>', caseSensitive: false);
  static final _pOpenRegex = RegExp(r'<p[^>]*>');
  static final _pCloseRegex = RegExp(r'</p>');
  static final _htmlTagRegex = RegExp(r'<[^>]*>');
  // CSS flex `order` 乱序反爬检测：匹配带 style="...order:N..." 的 <p> 段落。
  static final _cssOrderPRegex = RegExp(
    r'<p[^>]*\bstyle="[^"]*\border:\s*(\d+)[^"]*"[^>]*>([\s\S]*?)</p>',
    caseSensitive: false,
  );
  static final _crlfRegex = RegExp(r'\r\n');
  static final _crRegex = RegExp(r'\r');
  static final _whitespaceRegex = RegExp(r'[ \t]+');

  // 内容选择器列表（静态常量）
  static const _contentSelectors = [
    '#content', '.chapter-content', '.read-content', '#chaptercontent',
    '.novel-content', '.content', '#BookText', '#booktext',
    '.text-content', '#content-body', '.book-content', '.article-content',
    '#chapter-content', '.chapter_text', '#txt', '.readtext',
    '.bookreadercontent', '#BookContent', '.BookContent',
    '.content-body', '#readcontent', '.nr_nr', '#nr1',
    '.readcontent', '#content_1', '#content_2', '#content1',
    '.chaptercontent', '.novelcontent', '#novelcontent',
    '.read_content', '#read_content', '.book_content',
    '#book_content', '.article-content', '#article-content',
    '.article_content', '.chapter_content', '#chapter_content',
    '.chaptertext', '#txtcontent', '.txt-content', '#txt-content',
    '.read-content', '#read-content', '.readcontent',
    '#readcontent', '.text-content', '#text-content',
    '.booktext', '#booktext', '.book-text', '#book-text',
    '.bookreader-content', '#bookreader-content',
    '.article', '#article', '.post-content', '#post-content',
    '.entry-content', '#entry-content', '.story-content',
    '#story-content', '.novel-content', '#novel-content',
    '.chapterbody', '#chapterbody', '.text-body', '#text-body',
    'div[id*="content"]', 'div[class*="content"]',
    'div[id*="Content"]', 'div[class*="Content"]',
    'div[id*="chapter"]', 'div[class*="chapter"]',
    'div[id*="Chapter"]', 'div[class*="Chapter"]',
    'div[id*="text"]', 'div[class*="text"]',
    'div[id*="Text"]', 'div[class*="Text"]',
    'div[id*="read"]', 'div[class*="read"]',
    'div[id*="Read"]', 'div[class*="Read"]',
    'div[id*="novel"]', 'div[class*="novel"]',
    'div[id*="book"]', 'div[class*="book"]',
    'main', 'article', 'section',
    '.main-content', '#main-content',
    '.page-content', '#page-content',
    '.post', '.entry', '.single-post',
  ];

  // 广告清理选择器
  static const _adSelectors = [
    'script', 'style', 'ins', 'iframe',
    '.ad', '.ads', '.adv', '.advert',
    '[id*="ad"]', '[class*="ad"]',
  ];

  // 合并后的广告选择器（预编译，单次 DOM 遍历使用）
  static final _adSelectorCombined = _adSelectors.join(',');

  // 跳过模式（预编译）
  static final _skipPatterns = [
    RegExp(r'^(首页|主页|书库|书架|排行|榜单|分类|搜索|登录|注册)'),
    RegExp(r'^(返回|回到顶部|返回顶部)'),
    RegExp(r'^(广告|推广|点击|注册|下载|APP|微信|QQ)'),
    RegExp(r'^(Copyright|ICP|备案)'),
    RegExp(r'^\d+$'),
    RegExp(r'^(>>|<<|>|<|下一页|上一页|更多)$'),
  ];

  // 广告关键词
  static const _adKeywords = [
    '广告', '推广', '点击', '注册', '登录', '充值',
    '微信', 'QQ', '群', '公众号', '小程序',
    '兴趣部', '全本小说', '免费阅读', '最新章节',
  ];

  // 整行广告关键词（仅用于"短行"匹配，避免误删正文中含常见词如"点击/微信"的段落）。
  static const int _adLineMaxLength = 40;
  static const List<String> _adLineKeywords = <String>[
    '广告', '推广', '充值', '兴趣部', '全本小说',
    '免费阅读', '最新章节', '请收藏', '手机阅读', '下载APP',
    '全文阅读', '笔趣阁', 'app下载', '安卓版',
  ];

  // 内容 fallback 选择器：当书源规则未命中或结果为空时尝试
  static const _fallbackSelectors = [
    '#content',
    '.chapter-content',
    '.read-content',
    '#chaptercontent',
    '.novel-content',
    '.content',
    '#BookText',
    '#booktext',
    '.text-content',
    '#content-body',
    '.book-content',
    '.article-content',
    '#chapter-content',
    '#readcontent',
    '.readcontent',
    '#txt',
    '.txt-content',
    '#txt-content',
    '.post-content',
    '#post-content',
    '.entry-content',
    '#entry-content',
    'article',
    'main',
  ];

  static String analyzeContent({
    required XiaoshuoBookSource bookSource,
    required XiaoshuoBook book,
    required XiaoshuoBookChapter bookChapter,
    required String baseUrl,
    required String? redirectUrl,
    required String body,
    String? nextChapterUrl,
  }) {
    final contentRule = bookSource.getContentRule();
    final analyzeRule = AnalyzeRule(book: book, chapter: bookChapter)
      ..setContent(body, redirectUrl ?? baseUrl)
      ..setBaseUrl(baseUrl)
      ..setRedirectUrl(redirectUrl ?? baseUrl);

    String content = '';

    if (contentRule.content != null && contentRule.content!.isNotEmpty) {
      content = _getContent(analyzeRule, contentRule.content!);
    }

    // 如果 primary selector 未命中或结果为空，尝试 fallback selector 列表
    if (content.trim().isEmpty) {
      content = _tryFallbackSelectors(analyzeRule);
    }

    if (content.trim().isEmpty) {
      content = _extractGenericContent(body);
    }

    // 通用反爬：还原 CSS flex `order` 乱序段落（详见 _reorderCssOrderParagraphs）。
    // 必须在 HTML 剥离(_formatContent)之前，此时 content 仍含 <p style="order:N"> 标签。
    content = _reorderCssOrderParagraphs(content);

    // 若抽取结果是 HTML（如 @html），在应用 replaceRegex 前先把 <br>/<p> 边界
    // 规整为换行，使 line-anchored 的 replaceRegex 能按行匹配导航/广告文本，
    // 表现与 @textNodes 抽取后的纯文本一致（笔趣阁多页一致性修复）。
    // 必须在 _reorderCssOrderParagraphs 之后，避免破坏 order 乱序还原所需的 <p> 标签。
    if (content.contains('<')) {
      content = content
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '\n');
    }

    if (contentRule.replaceRegex != null && contentRule.replaceRegex!.isNotEmpty) {
      // 参考 xiaoshuo 原版 BookContent.kt：先 trim 每行，再直接应用正则替换规则
      content = content.split('\n').map((line) => line.trim()).join('\n');
      final replaceRegex = contentRule.replaceRegex!;
      final parts = replaceRegex.split('##');
      final pattern = parts[0];
      final replacement = parts.length >= 2 ? parts.sublist(1).join('##') : '';
      try {
        // multiLine: true 让 ^...$ 锚点支持每行边界匹配，而非仅整个字符串首尾
        content = content.replaceAll(RegExp(pattern, multiLine: true), replacement);
      } catch (_) {}
    }

    if (contentRule.title != null && contentRule.title!.isNotEmpty) {
      try {
        final title = analyzeRule.getString(contentRule.title!);
        if (title.isNotEmpty) {
          bookChapter.title = title;
        }
      } catch (_) {}
    }

    // 内容清洗：先 HTML 剥离 + 按段分行(_formatContent)，再按"段"去除广告行，
    // 避免正文被当成一整块文本而整章误删（历史"内容不完整"根因）。
    content = _formatContent(content);
    content = _cleanContentAds(content);

    // 添加段落缩进（在 _formatContent 之后，避免被 trim 移除）。
    // 幂等处理：先去掉行首可能存在的全角/半角缩进，再统一加一个全角空格，
    // 避免源 HTML 已带首行缩进时与引擎缩进叠加，导致「同一章不同子页
    // 缩进不一致 / 双倍缩进」的排版跳变（笔趣阁 #nr1@html 多页一致性修复）。
    if (contentRule.replaceRegex != null && contentRule.replaceRegex!.isNotEmpty && content.isNotEmpty) {
      content = content.split('\n').map((line) {
        final stripped = line.replaceFirst(RegExp(r'^[　\s]+'), '');
        return '　　$stripped';
      }).join('\n');
    }

    return content;
  }

  static String _getContent(AnalyzeRule analyzeRule, String contentRule) {
    try {
      return analyzeRule.getString(contentRule, unescape: false);
    } catch (_) {
      return '';
    }
  }

  /// fallback selector 探测
  static String _tryFallbackSelectors(AnalyzeRule analyzeRule) {
    for (final selector in _fallbackSelectors) {
      try {
        final value = analyzeRule.getString(selector, unescape: false);
        if (value.trim().isNotEmpty) {
          return value;
        }
      } catch (_) {}
    }
    return '';
  }

  /// 内容广告清理：按行匹配广告关键词与跳过模式
  static String _cleanContentAds(String content) {
    if (content.isEmpty) return content;

    final lines = content.split('\n');
    final cleaned = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 跳过导航 / 版权等整行模式（始终移除）。
      bool isAd = false;
      for (final pattern in _skipPatterns) {
        if (pattern.hasMatch(trimmed)) {
          isAd = true;
          break;
        }
      }
      if (isAd) continue;

      // 仅对"短行"做广告关键词匹配，避免正文中出现"点击/微信"等常见词被整段误删。
      if (trimmed.length <= _adLineMaxLength) {
        for (final keyword in _adLineKeywords) {
          if (trimmed.contains(keyword)) {
            isAd = true;
            break;
          }
        }
      }
      if (isAd) continue;

      cleaned.add(trimmed);
    }
    return cleaned.join('\n');
  }

  /// 还原 CSS flex `order` 乱序反爬。
  ///
  /// 部分站点（如 PTCMS 系）把正文 `<p>` 在 HTML 源码中打乱顺序，再给每个
  /// 段落设 `style="order:N"`，容器用 `display:flex;flex-direction:column`，
  /// 让浏览器在**视觉上**按 order 升序重排。直接抽取文本会得到乱序正文。
  ///
  /// 本方法是**通用能力**：仅当检测到 3 个以上带 `order:N` 的 `<p>` 段落时
  /// 才触发，按 order 升序重排后重新拼成 `<p>...</p>`，交给 [_formatContent]
  /// 继续剥离标签。对不含该模式的普通站点零副作用（直接原样返回）。
  /// 不依赖任何具体站点/域名，符合"源即插件、引擎只做通用处理"的架构。
  static String _reorderCssOrderParagraphs(String htmlContent) {
    if (htmlContent.isEmpty || !htmlContent.contains('order:')) {
      return htmlContent;
    }
    final matches = _cssOrderPRegex.allMatches(htmlContent).toList();
    if (matches.length < 3) return htmlContent; // 未命中乱序模式，原样返回
    final items = <MapEntry<int, String>>[];
    for (final m in matches) {
      final order = int.tryParse(m.group(1) ?? '');
      if (order == null) continue;
      items.add(MapEntry(order, m.group(2) ?? ''));
    }
    if (items.length < 3) return htmlContent;
    items.sort((a, b) => a.key.compareTo(b.key));
    return items.map((e) => '<p>${e.value}</p>').join('\n');
  }

  static String _formatContent(String content) {
    if (content.isEmpty) return content;

    // Convert <br> tags to newlines before stripping HTML
    content = content.replaceAll(_brRegex, '\n');
    content = content.replaceAll(_pOpenRegex, '\n');
    content = content.replaceAll(_pCloseRegex, '\n');

    // 剥离 HTML 标签
    content = content.replaceAll(_htmlTagRegex, '');

    // 解码 HTML 实体
    content = content
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');

    // Normalize line endings: remove \r\n and \r
    content = content.replaceAll(_crlfRegex, '\n').replaceAll(_crRegex, '\n');

    // Normalize horizontal whitespace (tabs and multiple spaces -> single space)
    content = content.replaceAll(_whitespaceRegex, ' ');

    // Trim each line and drop empty lines
    final lines = content.split('\n');
    final cleanedLines = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        cleanedLines.add(trimmed);
      }
    }
    return cleanedLines.join('\n');
  }

  static String _extractGenericContent(String body) {
    final document = html_parser.parse(body);

    // 一次性移除所有广告元素，避免重复操作
    _removeAdsFromDocument(document);

    String bestContent = '';
    double bestScore = 0.0;

    // 优先使用高质量选择器（前 20 个覆盖 90% 的场景）
    final prioritySelectors = _contentSelectors.take(20);

    for (final selector in prioritySelectors) {
      try {
        final el = document.querySelector(selector);
        if (el != null) {
          var text = el.text.trim();
          if (text.isNotEmpty) {
            final score = _calculateContentScoreFast(text);
            if (score > bestScore) {
              bestScore = score;
              bestContent = text;
              // 高质量内容立即返回，不继续遍历剩余 CSS 选择器
              if (bestScore >= 0.7) return bestContent;
            }
          }
        }
      } catch (_) {}
    }

    // 如果最佳内容质量不达标，尝试从 body 直接提取
    if (bestContent.isEmpty || bestScore < 0.2) {
      final bodyEl = document.querySelector('body');
      if (bodyEl != null) {
        var bodyText = _cleanBodyContent(bodyEl.text.trim());
        if (bodyText.length > bestContent.length) {
          bestContent = bodyText;
        }
      }
    }

    return bestContent;
  }

  /// DOM 广告移除
  static void _removeAdsFromDocument(dynamic document) {
    try {
      final ads = document.querySelectorAll(_adSelectorCombined);
      for (final ad in ads) {
        ad.remove();
      }
    } catch (_) {}
  }

  /// 内容评分：综合长度、中文密度、广告关键词命中
  static double _calculateContentScoreFast(String text) {
    if (text.isEmpty) return 0.0;

    final length = text.length;

    // 长度评分（权重更高）
    double lengthScore = 0.0;
    if (length >= 500) {
      lengthScore = 1.0;
    } else if (length >= 300) {
      lengthScore = 0.8;
    } else if (length >= 150) {
      lengthScore = 0.6;
    } else if (length >= 80) {
      lengthScore = 0.4;
    } else {
      lengthScore = 0.1;
    }

    // 简单的文本密度检查（使用字符串操作替代正则）
    int chineseCount = 0;
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 0x4e00 && code <= 0x9fa5) {
        chineseCount++;
      }
    }
    final density = chineseCount / length;
    double densityScore = 0.0;
    if (density >= 0.4) {
      densityScore = 1.0;
    } else if (density >= 0.25) {
      densityScore = 0.7;
    } else if (density >= 0.15) {
      densityScore = 0.4;
    } else {
      densityScore = 0.2;
    }

    // 简化的广告检测（只查前 100 个字符）
    final preview = text.length > 100 ? text.substring(0, 100) : text;
    int adCount = 0;
    for (final keyword in _adKeywords) {
      if (preview.contains(keyword)) {
        adCount++;
      }
    }
    double adScore = 1.0;
    if (adCount > 3) {
      adScore = 0.3;
    } else if (adCount > 1) {
      adScore = 0.7;
    }

    // 综合评分（简化算法）
    return (lengthScore * 0.5 + densityScore * 0.3 + adScore * 0.2).clamp(0.0, 1.0);
  }

  /// body 文本清洗
  static String _cleanBodyContent(String text) {
    final lines = text.split('\n');
    final cleanedLines = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // 仅按跳过模式过滤；保留短行（如对话"啊。""……"），避免正文残缺。
      bool shouldSkip = false;
      for (final pattern in _skipPatterns) {
        if (pattern.hasMatch(trimmed)) {
          shouldSkip = true;
          break;
        }
      }
      if (!shouldSkip) {
        cleanedLines.add(trimmed);
      }
    }
    return cleanedLines.join('\n');
  }
}
