/// Image cleaning utilities for the built-in resolver's `images` route.
///
/// Implements NexHub V2 spec section 16.2: lazy-load (`data-src`) recovery,
/// ad / placeholder / tracker filtering, dedup, format guessing, absolute URL
/// completion and paged URL extraction. Pure functional, no Flutter widget
/// dependencies, safe to call inside an isolate.
library;

import 'package:html/dom.dart';

import '../utils/html_utils.dart';

/// Rules for [ImageExtractor.filterImages]. Defaults encode the V2 spec ad
/// blocklist and the set of image formats kept by default.
class ImageFilterRules {
  /// Lowercase substrings that mark a URL as non-content (ad / tracker /
  /// placeholder / ui chrome). A URL containing any of these is dropped.
  final List<String> excludeKeywords;

  /// Lowercase extensions kept by [ImageExtractor.filterImages] when a URL's
  /// extension is recognisable. URLs with no determinable extension are kept
  /// (conservative: do not lose data on extension-less CDN URLs).
  final List<String> allowedFormats;

  /// When true, duplicate URLs are removed while preserving first-seen order.
  final bool deduplicate;

  const ImageFilterRules({
    this.excludeKeywords = const [
      'ad',
      'advert',
      'banner',
      'tracker',
      'pixel',
      'placeholder',
      'logo',
      'icon',
      'spacer',
      'blank',
      '1x1',
    ],
    this.allowedFormats = const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
    this.deduplicate = true,
  });
}

/// Stateless image cleaning toolkit. Mirrors the [HtmlUtils] style: a private
/// constructor + static methods only.
class ImageExtractor {
  ImageExtractor._();

  /// Lazy-load attribute priority: real URL first, `src` last. Used when no
  /// explicit attribute is requested.
  static const List<String> _lazyAttrs = [
    'data-src',
    'data-original',
    'data-lazy-src',
    'data-url',
    'src',
  ];

  /// Ad / placeholder / tracker keyword blocklist shared with
  /// [isValidImageUrl]. Case-insensitive substring match.
  static const List<String> _adKeywords = [
    'ad',
    'advert',
    'banner',
    'tracker',
    'pixel',
    'placeholder',
    'logo',
    'icon',
    'spacer',
    'blank',
    '1x1',
  ];

  /// Extracts real image URLs from [html], resolving lazy-load attributes
  /// (`data-src` / `data-original` / `data-lazy-src`) before falling back to
  /// `src`.
  ///
  /// [selector] may be a plain CSS selector (`img`, `.page img`) or a
  /// `css@attr` composite (`img@data-src`) to force a single attribute. When
  /// omitted, every `<img>` is matched.
  ///
  /// Returns the RAW URL list (no absolute completion): empty and `data:`
  /// URLs are dropped, order is preserved, no dedup. Call [toAbsolute] /
  /// [filterImages] afterwards when feeding the resolver's `images` route.
  static List<String> extractLazyImagesFromHtml(String html, {String? selector}) {
    var css = selector?.trim() ?? 'img';
    String? attr;
    final at = css.indexOf('@');
    if (at >= 0) {
      attr = css.substring(at + 1).trim();
      css = css.substring(0, at).trim();
      if (css.isEmpty) css = 'img';
    }
    return _extractFromHtml(html, css: css, attr: attr);
  }

  /// Returns true when [url] is a plausibly real image URL: non-empty,
  /// `http(s)://` scheme, not a `data:` URL, and free of ad / placeholder /
  /// tracker keywords.
  static bool isValidImageUrl(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    if (lower.startsWith('data:')) return false;
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }
    for (final kw in _adKeywords) {
      if (lower.contains(kw)) return false;
    }
    return true;
  }

  /// Guesses the image format of [url]. When [bytes] is provided and non-empty
  /// the magic-number prefix wins; otherwise the URL path extension is used.
  /// Returns a lowercased extension (`jpg` / `png` / `webp` / `gif` / ...) or
  /// `null` when nothing can be determined.
  static String? guessFormat(String url, {List<int>? bytes}) {
    if (bytes != null && bytes.isNotEmpty) {
      final magic = _magicFormat(bytes);
      if (magic != null) return magic;
    }
    try {
      final path = Uri.parse(url).path;
      final dot = path.lastIndexOf('.');
      if (dot >= 0 && dot < path.length - 1) {
        return path.substring(dot + 1).toLowerCase();
      }
    } catch (_) {
      // Malformed URL: fall through to null.
    }
    return null;
  }

  /// Filters a list of (already absolute) image URLs by [rules] (or the
  /// defaults): drops empty / non-http(s) / `data:` URLs, drops ad / keyword
  /// matches, drops URLs whose recognisable extension is not in
  /// [ImageFilterRules.allowedFormats], and (when [ImageFilterRules.deduplicate]
  /// is true) removes duplicates while preserving first-seen order. URLs with
  /// no determinable extension are kept (conservative).
  static List<String> filterImages(List<String> urls, {ImageFilterRules? rules}) {
    final r = rules ?? const ImageFilterRules();
    final seen = <String>{};
    final out = <String>[];
    for (final raw in urls) {
      if (raw.isEmpty) continue;
      final lower = raw.toLowerCase();
      if (lower.startsWith('data:')) continue;
      if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
        continue;
      }
      var excluded = false;
      for (final kw in r.excludeKeywords) {
        if (kw.isEmpty) continue;
        if (lower.contains(kw.toLowerCase())) {
          excluded = true;
          break;
        }
      }
      if (excluded) continue;
      final fmt = guessFormat(raw);
      if (fmt != null &&
          r.allowedFormats.isNotEmpty &&
          !r.allowedFormats.contains(fmt)) {
        continue;
      }
      if (r.deduplicate && !seen.add(raw)) continue;
      out.add(raw);
    }
    return out;
  }

  /// Produces image URLs for one page according to the source `images`
  /// config. [config] keys:
  /// - `mode` (`list` / `scroll` / `clickMore`, default `list`)
  /// - `item` (CSS selector, default `img`)
  /// - `src` (attribute, e.g. `data-src`)
  ///
  /// URLs are completed against [baseUrl] when provided. For `scroll` /
  /// `clickMore` only the current page's images are returned (chasing the
  /// next page is the caller's job; this is a pure, network-free function).
  static List<String> getPageUrls(
    String html,
    Map<String, dynamic> config, {
    String? baseUrl,
  }) {
    final mode = (config['mode'] as String?) ?? 'list';
    final item = config['item'] as String?;
    final srcAttr = config['src'] as String?;
    // mode is validated for forward compatibility; current-page extraction is
    // identical across modes for a pure function.
    assert(mode == 'list' || mode == 'scroll' || mode == 'clickMore');
    var css = item?.trim() ?? 'img';
    if (css.isEmpty) css = 'img';
    var attr = srcAttr?.trim();
    if (attr != null && attr.isEmpty) attr = null;
    final raw = _extractFromHtml(html, css: css, attr: attr);
    return <String>[for (final u in raw) toAbsolute(u, baseUrl)];
  }

  /// Completes a possibly-relative [url] against [baseUrl]. Handles absolute
  /// (`http(s)://`), protocol-relative (`//host`), root-relative (`/path`) and
  /// relative (`path`) forms. `data:` URLs are returned unchanged. When
  /// [baseUrl] is null/empty, protocol-relative URLs gain `https:` and other
  /// relative URLs are returned unchanged.
  static String toAbsolute(String url, String? baseUrl) {
    return _toAbsolute(url, baseUrl);
  }

  static String _toAbsolute(String url, String? baseUrl) {
    if (url.isEmpty) return url;
    final lower = url.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return url;
    }
    if (lower.startsWith('data:')) return url;
    if (baseUrl == null || baseUrl.isEmpty) {
      if (url.startsWith('//')) return 'https:$url';
      return url;
    }
    try {
      return Uri.parse(baseUrl).resolve(url).toString();
    } catch (_) {
      if (url.startsWith('//')) return 'https:$url';
      return url;
    }
  }

  // ---- internals ----

  static List<String> _extractFromHtml(
    String html, {
    required String css,
    String? attr,
  }) {
    final elements = HtmlUtils.elements(html, css);
    final out = <String>[];
    for (final el in elements) {
      final target = _asImg(el);
      final v = _readAttr(target, attr);
      if (v.isEmpty) continue;
      if (v.toLowerCase().startsWith('data:')) continue;
      out.add(v);
    }
    return out;
  }

  /// Returns [el] when it is already an `<img>`, otherwise the first nested
  /// `<img>` (matches the legacy BuiltinResolver._imageAttr behaviour). Falls
  /// back to [el] itself when no nested `<img>` exists.
  static Element _asImg(Element el) {
    if (el.localName == 'img') return el;
    return el.querySelector('img') ?? el;
  }

  /// Reads [attr] when specified; otherwise tries lazy-load attributes in
  /// priority order, falling back to `src`.
  static String _readAttr(Element el, String? attr) {
    if (attr != null) {
      return el.attributes[attr] ?? '';
    }
    for (final a in _lazyAttrs) {
      final v = el.attributes[a];
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  /// Maps a magic-number prefix to an image format. Returns `null` for
  /// unknown / too-short buffers.
  static String? _magicFormat(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return 'gif';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return 'webp';
    }
    return null;
  }
}
