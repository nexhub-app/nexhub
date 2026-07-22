/// HTML / CSS selector + XPath engine utilities.
///
/// Shared by BuiltinResolver and js_context. XPath is powered by
/// `xpath_selector_html_parser` and supports the full V2 spec function set:
/// `//tag`, `//tag[@attr]`, `//tag[@attr='v']`, `//tag[contains(@attr,'v')]`,
/// `//tag/@attr`, `//tag/text()`, `following-sibling::tag`,
/// top-level `substring-before(...)` / `substring-after(...)` and their
/// nested combinations (e.g. pms_fsdm `id` selector).
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xpath_selector/xpath_selector.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

class HtmlUtils {
  HtmlUtils._();

  static Document parse(String html) => html_parser.parse(html);

  /// Returns matching elements (for per-field extraction by the parser).
  ///
  /// XPath selectors (e.g. `div[@class='item']`, `//div[@class='list']/a`)
  /// are routed to the XPath engine; CSS selectors use `querySelectorAll`.
  static List<Element> elements(String html, String selector) {
    final doc = parse(html);
    if (isXPath(selector)) return _xpathElements(doc, selector);
    return doc.querySelectorAll(selector);
  }

  static String? query(String html, String selector) {
    final doc = parse(html);
    if (isXPath(selector)) return _xpathQuery(doc, selector);
    return doc.querySelector(selector)?.text.trim();
  }

  static List<String> queryAll(String html, String selector) {
    final doc = parse(html);
    if (isXPath(selector)) return _xpathQueryAll(doc, selector);
    return doc
        .querySelectorAll(selector)
        .map((e) => e.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static String? queryAttr(String html, String selector, String attr) {
    final doc = parse(html);
    if (isXPath(selector)) return _xpathAttr(doc, selector, attr);
    return doc.querySelector(selector)?.attributes[attr];
  }

  /// Returns the **inner HTML** of the first element matched by [selector].
  /// Used by `context.dom.queryHtml` (golden Legado/novel scripts) to grab a
  /// markup fragment (e.g. the novel-content `<div>`) for later cleaning.
  /// Unlike [query] (which returns trimmed text), this preserves the markup.
  static String? queryHtml(String html, String selector) {
    final doc = parse(html);
    final Element? el;
    if (isXPath(selector)) {
      final nodes = _xpathElements(doc, selector);
      el = nodes.isEmpty ? null : nodes.first;
    } else {
      el = doc.querySelector(selector);
    }
    return el?.innerHtml;
  }

  /// Strips noise nodes (`script`/`style`/`ins`/`iframe`/`noscript`/`head`/
  /// `link`/`meta`/`svg`) and comments from [html], returning the cleaned
  /// inner HTML. Used by `context.content.clean` (golden novel content
  /// scripts) to sanitise chapter bodies before display.
  static String clean(String html) {
    final doc = parse(html);
    doc
        .querySelectorAll(
            'script, style, ins, iframe, noscript, head, link, meta, svg')
        .forEach((e) => e.remove());
    _removeComments(doc);
    final body = doc.body;
    return body?.innerHtml ?? doc.documentElement?.innerHtml ?? '';
  }

  static void _removeComments(Node node) {
    final comments = node.nodes.whereType<Comment>().toList();
    for (final c in comments) {
      c.remove();
    }
    for (final child in node.nodes.whereType<Element>()) {
      _removeComments(child);
    }
  }

  /// Parses `a@href` / `img@data-src` style composite selectors:
  /// the CSS part matches an element, then `@attr` is read; without `@` the
  /// text is returned. XPath selectors are routed to [query]/[queryAttr].
  static String? queryAttrExpr(String html, String expr) {
    final atIndex = expr.indexOf('@');
    if (atIndex < 0) return query(html, expr);
    final css = expr.substring(0, atIndex).trim();
    final attr = expr.substring(atIndex + 1).trim();
    return queryAttr(html, css, attr);
  }

  // ---- XPath branch ----

  /// A selector is treated as XPath when it begins with an XPath path prefix
  /// (`//`, `/`, `./`, `.//`), a top-level XPath string function
  /// (`substring-before(` / `substring-after(`), or contains an XPath
  /// attribute predicate (`[@attr]` / `[@attr='val']`). CSS selectors never
  /// use `[@`, so CSS routing is unaffected.
  static bool isXPath(String selector) {
    final s = selector.trim();
    if (s.startsWith('//') ||
        s.startsWith('./') ||
        s.startsWith('.//') ||
        s.startsWith('/')) {
      return true;
    }
    if (s.startsWith('substring-before(') || s.startsWith('substring-after(')) {
      return true;
    }
    // XPath attribute predicate: tag[@attr] or tag[@attr='val'].
    // CSS uses [attr] without @, so [@ is a safe XPath signal.
    return s.contains('[@');
  }

  /// Normalises a relative XPath so the engine (which requires a leading `/`
  /// or `//`) can evaluate it against the document root. `./a/@href` becomes
  /// `//a/@href` and `.//img/@data-src` becomes `//img/@data-src`. Paths
  /// without a leading slash (e.g. `div[@class='item']`) are prefixed with
  /// `//` for descendant search. Absolute paths are returned unchanged.
  static String _normalizePath(String path) {
    var p = path.trim();
    if (p.startsWith('./')) {
      p = p.substring(1); // drop the leading dot → /...
    }
    if (p.startsWith('//')) {
      // already absolute descendant search
    } else if (p.startsWith('/')) {
      p = '/$p'; // /a -> //a (descendant search from document root)
    } else {
      // No leading / (e.g. div[@class='item']): prepend // for descendant
      // search from the root node.
      p = '//$p';
    }
    return p;
  }

  /// Rewrites bare existence predicates `[@name]` into a form the engine
  /// supports. xpath_selector has no native attribute-existence predicate, so
  /// `[@name]` becomes `[@name!='__nexhub_absent__']`: a missing attribute
  /// yields a null left operand (no match), while any present value differs
  /// from the sentinel (match). Predicates like `[@name='v']` or
  /// `[contains(@x,'y')]` are left untouched.
  static String _rewriteExistence(String selector) {
    return selector.replaceAllMapped(
      RegExp(r'\[@([\w:.-]+)\]'),
      (m) => "[@${m.group(1)}!='__nexhub_absent__']",
    );
  }

  static XPathResult<Node> _exec(Document doc, String selector) {
    final root = doc.documentElement;
    if (root == null) {
      return XPathResult<Node>(const <XPathNode<Node>>[], const <String?>[]);
    }
    try {
      return HtmlXPath.node(root)
          .query(_rewriteExistence(_normalizePath(selector)));
    } on FormatException catch (e) {
      // xpath_selector 3.0.2 不支持节点集谓语（如 `a[.//img]`、`a[x and .//y]`），
      // 会在 _multipleCompare 抛 FormatException。单个源的个别选择器不兼容时
      // 静默降级为空，避免整个列表解析崩溃（表现为「网站源解析不到内容」）。
      print('[HtmlUtils] xpath 选择器不支持，已降级为空: $selector ($e)');
      return XPathResult<Node>(const <XPathNode<Node>>[], const <String?>[]);
    } on UnsupportedError catch (e) {
      print('[HtmlUtils] xpath 谓语不支持，已降级为空: $selector ($e)');
      return XPathResult<Node>(const <XPathNode<Node>>[], const <String?>[]);
    }
  }

  /// Evaluates an XPath [selector] that returns element nodes (used by
  /// [elements] for list/item extraction). Top-level string functions
  /// (`substring-before` / `substring-after`) return strings, not elements,
  /// so they yield an empty list here. Non-element nodes (attributes, text)
  /// are filtered out.
  static List<Element> _xpathElements(Document doc, String selector) {
    if (selector.startsWith('substring-before(') ||
        selector.startsWith('substring-after(')) {
      return const <Element>[];
    }
    final result = _exec(doc, selector);
    return <Element>[
      for (final n in result.nodes)
        if (n.node is Element) n.node as Element,
    ];
  }

  /// Evaluates a top-level `substring-before(X, 'sep')` or
  /// `substring-after(X, 'sep')` expression, recursing into nested string
  /// functions. `X` may itself be a string function or an XPath path. Returns
  /// `null` when [expr] is not a recognised top-level string function.
  static String? _evalStringExpr(Document doc, String expr) {
    final e = expr.trim();
    final before = RegExp(
      r"""^substring-before\((.*),\s*['"]([^'"]*)['"]\)$""",
    ).firstMatch(e);
    if (before != null) {
      final inner = before.group(1)!;
      final sep = before.group(2)!;
      final value = _evalStringOrPath(doc, inner);
      if (value == null) return null;
      final idx = value.indexOf(sep);
      return idx >= 0 ? value.substring(0, idx) : '';
    }
    final after = RegExp(
      r"""^substring-after\((.*),\s*['"]([^'"]*)['"]\)$""",
    ).firstMatch(e);
    if (after != null) {
      final inner = after.group(1)!;
      final sep = after.group(2)!;
      final value = _evalStringOrPath(doc, inner);
      if (value == null) return null;
      final idx = value.indexOf(sep);
      return idx >= 0 ? value.substring(idx + sep.length) : '';
    }
    return null;
  }

  /// Resolves an expression that is either a nested string function or an
  /// XPath path, returning its string value.
  static String? _evalStringOrPath(Document doc, String expr) {
    final str = _evalStringExpr(doc, expr);
    if (str != null) return str;
    return _evalPathString(doc, expr);
  }

  /// Resolves an XPath path to a single string: attribute value for `/@attr`,
  /// text for `/text()`, or the element text otherwise.
  static String? _evalPathString(Document doc, String path) {
    final result = _exec(doc, path);
    if (result.attrs.isNotEmpty) {
      // Attribute / text() query: parseAttr populated attrs.
      return result.attr;
    }
    final node = result.node?.node;
    if (node is Element) return node.text.trim();
    return null;
  }

  static String? _xpathQuery(Document doc, String selector) {
    final str = _evalStringExpr(doc, selector);
    if (str != null) return str.isEmpty ? null : str;
    final result = _exec(doc, selector);
    if (result.attrs.isNotEmpty) {
      final a = result.attr;
      return (a != null && a.isNotEmpty) ? a : null;
    }
    final node = result.node?.node;
    if (node is Element) {
      final t = node.text.trim();
      return t.isEmpty ? null : t;
    }
    return null;
  }

  static List<String> _xpathQueryAll(Document doc, String selector) {
    final str = _evalStringExpr(doc, selector);
    if (str != null) {
      return str.isEmpty ? const <String>[] : <String>[str];
    }
    final result = _exec(doc, selector);
    if (result.attrs.isNotEmpty) {
      return result.attrs
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return result.nodes.map((n) {
      final node = n.node;
      if (node is Element) return node.text.trim();
      return node.toString().trim();
    }).where((s) => s.isNotEmpty).toList();
  }

  /// Reads [attr] from the first element matched by the XPath [selector]. A
  /// trailing `/@xxx` on the selector is stripped so the separate [attr]
  /// argument takes precedence (preserving the previous contract).
  static String? _xpathAttr(Document doc, String selector, String attr) {
    var xpath = selector.trim();
    final trailingAttr = RegExp(r'/@[\w:.-]+$').firstMatch(xpath);
    if (trailingAttr != null) {
      xpath = xpath.substring(0, trailingAttr.start);
    }
    final result = _exec(doc, xpath);
    for (final n in result.nodes) {
      final node = n.node;
      if (node is Element) {
        final v = node.attributes[attr];
        if (v != null && v.isNotEmpty) return v;
      }
    }
    return null;
  }
}
