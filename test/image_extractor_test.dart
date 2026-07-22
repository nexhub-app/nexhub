import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/resolver/image_extractor.dart';

/// Unit tests for ImageExtractor (NexHub V2 spec section 16.2):
/// lazy-load recovery, ad filtering, format guessing, dedup, abs URL
/// completion and paged URL extraction.
void main() {
  group('extractLazyImagesFromHtml', () {
    test('prefers data-src over src placeholder', () {
      const html = '<img src="placeholder.jpg" data-src="real1.jpg">';
      final urls = ImageExtractor.extractLazyImagesFromHtml(html);
      expect(urls, <String>['real1.jpg']);
    });

    test('falls back to src when no lazy attribute is present', () {
      const html =
          '<img src="p1.jpg" data-src="r1.jpg"><img src="r2.jpg">';
      final urls = ImageExtractor.extractLazyImagesFromHtml(html);
      expect(urls, <String>['r1.jpg', 'r2.jpg']);
    });

    test('css@attr selector forces a single attribute', () {
      const html =
          '<img src="a.jpg" data-original="b.jpg" data-src="c.jpg">';
      final urls = ImageExtractor.extractLazyImagesFromHtml(
        html,
        selector: 'img@data-original',
      );
      expect(urls, <String>['b.jpg']);
    });

    test('drops data: URLs and keeps real ones', () {
      const html =
          '<img data-src="data:image/png;base64,xxxx"><img data-src="real.jpg">';
      final urls = ImageExtractor.extractLazyImagesFromHtml(html);
      expect(urls, <String>['real.jpg']);
    });
  });

  group('isValidImageUrl', () {
    test('rejects ad / banner / tracker / 1x1 / logo keywords', () {
      expect(ImageExtractor.isValidImageUrl('https://x.com/ad/banner.gif'),
          isFalse);
      expect(ImageExtractor.isValidImageUrl('https://x.com/tracker.gif'),
          isFalse);
      expect(ImageExtractor.isValidImageUrl('https://x.com/1x1.png'), isFalse);
      expect(ImageExtractor.isValidImageUrl('https://x.com/logo.png'), isFalse);
      expect(
          ImageExtractor.isValidImageUrl('https://x.com/placeholder.png'),
          isFalse);
    });

    test('accepts normal URLs and rejects empty / non-http / data:', () {
      expect(
          ImageExtractor.isValidImageUrl('https://example.com/image1.jpg'),
          isTrue);
      expect(ImageExtractor.isValidImageUrl(''), isFalse);
      expect(ImageExtractor.isValidImageUrl('d1.png'), isFalse);
      expect(
          ImageExtractor.isValidImageUrl('data:image/png;base64,xxxx'), isFalse);
      expect(ImageExtractor.isValidImageUrl('ftp://x/y.jpg'), isFalse);
    });
  });

  group('guessFormat', () {
    test('infers from URL path extension (lowercased, query stripped)', () {
      expect(ImageExtractor.guessFormat('https://x/1.jpg'), 'jpg');
      expect(ImageExtractor.guessFormat('https://x/2.PNG'), 'png');
      expect(ImageExtractor.guessFormat('https://x/3'), isNull);
      expect(ImageExtractor.guessFormat('https://x/4.jpg?v=2'), 'jpg');
      expect(ImageExtractor.guessFormat('xxx'), isNull);
    });

    test('infers from bytes magic prefix (jpg/png/gif/webp)', () {
      expect(
        ImageExtractor.guessFormat('any', bytes: <int>[0xFF, 0xD8, 0xFF]),
        'jpg',
      );
      expect(
        ImageExtractor.guessFormat('any', bytes: <int>[0x89, 0x50, 0x4E, 0x47]),
        'png',
      );
      expect(
        ImageExtractor.guessFormat('any', bytes: <int>[0x47, 0x49, 0x46, 0x38]),
        'gif',
      );
      expect(
        ImageExtractor.guessFormat('any', bytes: <int>[0x52, 0x49, 0x46, 0x46]),
        'webp',
      );
      expect(
        ImageExtractor.guessFormat('any', bytes: <int>[0x00, 0x00]),
        isNull,
      );
      // bytes win over a URL without extension
      expect(
        ImageExtractor.guessFormat('https://x/noext',
            bytes: <int>[0xFF, 0xD8, 0xFF, 0xE0]),
        'jpg',
      );
    });
  });

  group('filterImages', () {
    test('drops ads, duplicates and non-allowed formats; keeps valid+unique', () {
      final input = <String>[
        'https://x.com/ad/banner.gif',
        'https://x.com/1.jpg',
        'https://x.com/1.jpg',
        'https://x.com/2.png',
        'https://x.com/page.bmp',
        '',
        'https://x.com/3.webp',
      ];
      expect(
        ImageExtractor.filterImages(input),
        <String>[
          'https://x.com/1.jpg',
          'https://x.com/2.png',
          'https://x.com/3.webp',
        ],
      );
    });

    test('honours custom rules (excludeKeywords, allowedFormats, no dedup)', () {
      final input = <String>[
        'https://x.com/watermark.png',
        'https://x.com/1.jpg',
        'https://x.com/1.jpg',
        'https://x.com/2.png',
      ];
      expect(
        ImageExtractor.filterImages(
          input,
          rules: const ImageFilterRules(
            excludeKeywords: <String>['watermark'],
            allowedFormats: <String>['jpg'],
            deduplicate: false,
          ),
        ),
        <String>['https://x.com/1.jpg', 'https://x.com/1.jpg'],
      );
    });

    test('keeps extensionless absolute URLs (conservative)', () {
      expect(
        ImageExtractor.filterImages(<String>['https://cdn.x.com/image?id=1']),
        <String>['https://cdn.x.com/image?id=1'],
      );
    });
  });

  group('getPageUrls', () {
    test('list mode completes root-relative URLs against baseUrl', () {
      const html = '<img data-src="/img/1.jpg"><img data-src="/img/2.jpg">';
      final urls = ImageExtractor.getPageUrls(
        html,
        <String, dynamic>{
          'mode': 'list',
          'item': 'img',
          'src': 'data-src',
        },
        baseUrl: 'https://example.com',
      );
      expect(urls, <String>[
        'https://example.com/img/1.jpg',
        'https://example.com/img/2.jpg',
      ]);
    });

    test('completes protocol-relative URLs with baseUrl scheme', () {
      const html = '<img data-src="//cdn.example.com/x.jpg">';
      final urls = ImageExtractor.getPageUrls(
        html,
        <String, dynamic>{'mode': 'list', 'src': 'data-src'},
        baseUrl: 'https://example.com',
      );
      expect(urls, <String>['https://cdn.example.com/x.jpg']);
    });

    test('without baseUrl keeps relative URLs unchanged', () {
      const html = '<img data-src="a.jpg">';
      final urls = ImageExtractor.getPageUrls(
        html,
        <String, dynamic>{'mode': 'list'},
        baseUrl: null,
      );
      expect(urls, <String>['a.jpg']);
    });

    test('scroll / clickMore modes extract current-page images like list', () {
      const html = '<img data-src="b.jpg">';
      final scroll = ImageExtractor.getPageUrls(
        html,
        <String, dynamic>{'mode': 'scroll', 'src': 'data-src'},
        baseUrl: 'https://example.com',
      );
      expect(scroll, <String>['https://example.com/b.jpg']);
      final clickMore = ImageExtractor.getPageUrls(
        html,
        <String, dynamic>{'mode': 'clickMore', 'src': 'data-src'},
        baseUrl: 'https://example.com',
      );
      expect(clickMore, <String>['https://example.com/b.jpg']);
    });
  });

  group('toAbsolute', () {
    test('handles absolute / protocol-relative / root-relative / relative', () {
      expect(
        ImageExtractor.toAbsolute('https://h/1.jpg', 'https://example.com'),
        'https://h/1.jpg',
      );
      expect(
        ImageExtractor.toAbsolute('//h/1.jpg', 'https://example.com'),
        'https://h/1.jpg',
      );
      expect(
        ImageExtractor.toAbsolute('/img/1.jpg', 'https://example.com'),
        'https://example.com/img/1.jpg',
      );
      expect(
        ImageExtractor.toAbsolute('img/1.jpg', 'https://example.com'),
        'https://example.com/img/1.jpg',
      );
      expect(
        ImageExtractor.toAbsolute('data:image/png;base64,xx', null),
        'data:image/png;base64,xx',
      );
      expect(ImageExtractor.toAbsolute('//h/1.jpg', null), 'https://h/1.jpg');
    });
  });
}
