import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/resolver/m3u8_ad_filter.dart';
import 'package:nexhub/core/resolver/m3u8_parser.dart';

/// filterAds / M3u8AdFilter 单元测试（M2.3.6）。
///
/// 覆盖场景：无广告、URL 关键词广告、时长过短广告、discontinuity 短组广告、
/// 全广告保底回退、禁用规则、playlist 字符串版过滤。
void main() {
  group('filterAds - 无广告', () {
    test('全部正常分片原样保留', () {
      final segments = [
        const M3u8Segment(url: 'https://cdn.com/main1.ts', duration: 10.0),
        const M3u8Segment(url: 'https://cdn.com/main2.ts', duration: 10.0),
        const M3u8Segment(url: 'https://cdn.com/main3.ts', duration: 10.0),
      ];
      final filtered = filterAds(segments);
      expect(filtered, hasLength(3));
      expect(filtered.map((s) => s.url).toList(), [
        'https://cdn.com/main1.ts',
        'https://cdn.com/main2.ts',
        'https://cdn.com/main3.ts',
      ]);
    });

    test('单个分片直接返回', () {
      final segments = [
        const M3u8Segment(url: 'https://cdn.com/only.ts', duration: 10.0),
      ];
      expect(filterAds(segments), hasLength(1));
    });
  });

  group('filterAds - URL 关键词广告', () {
    test('URL 含 ad/advert 关键词的分片被移除', () {
      final segments = [
        const M3u8Segment(url: 'https://cdn.com/main1.ts', duration: 10.0),
        const M3u8Segment(url: 'https://cdn.com/ad/clip1.ts', duration: 10.0),
        const M3u8Segment(url: 'https://cdn.com/advertclip.ts', duration: 10.0),
        const M3u8Segment(url: 'https://cdn.com/main2.ts', duration: 10.0),
      ];
      final filtered = filterAds(segments);
      expect(filtered, hasLength(2));
      expect(filtered.every((s) => !s.url.contains('ad')), isTrue);
    });

    test('自定义关键词生效', () {
      final segments = [
        const M3u8Segment(url: 'https://cdn.com/sponsor1.ts', duration: 10.0),
        const M3u8Segment(url: 'https://cdn.com/main.ts', duration: 10.0),
      ];
      final filtered = filterAds(
        segments,
        rules: const AdFilterRules(
          adKeywords: ['sponsor'],
          minSegmentDuration: 0,
          useDiscontinuity: false,
        ),
      );
      expect(filtered, hasLength(1));
      expect(filtered.single.url, 'https://cdn.com/main.ts');
    });
  });

  group('filterAds - 时长过短广告', () {
    test('时长低于阈值的分片被移除', () {
      final segments = [
        const M3u8Segment(url: 'https://cdn.com/main1.ts', duration: 10.0),
        const M3u8Segment(url: 'https://cdn.com/short1.ts', duration: 0.2),
        const M3u8Segment(url: 'https://cdn.com/short2.ts', duration: 0.1),
        const M3u8Segment(url: 'https://cdn.com/main2.ts', duration: 10.0),
      ];
      final filtered = filterAds(segments);
      expect(filtered, hasLength(2));
      expect(filtered.every((s) => s.duration > 0.5), isTrue);
    });
  });

  group('filterAds - discontinuity 短组广告', () {
    test('discontinuity 标记间的短时长组被整体移除', () {
      // 用 parseM3u8 解析带 discontinuity 的 playlist，得到带组索引的 segments。
      const content = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
main1.ts
#EXTINF:10.0,
main2.ts
#EXTINF:10.0,
main3.ts
#EXT-X-DISCONTINUITY
#EXTINF:1.0,
clip1.ts
#EXTINF:1.0,
clip2.ts
#EXTINF:1.0,
clip3.ts
#EXT-X-DISCONTINUITY
#EXTINF:10.0,
main4.ts
#EXTINF:10.0,
main5.ts
#EXT-X-ENDLIST
''';
      final parsed = parseM3u8(content, baseUrl: 'https://cdn.com/');
      expect(parsed.segments, hasLength(8));

      final filtered = filterAds(parsed.segments);
      // 广告组（3 个 1s 分片）被移除，保留 5 个正片。
      expect(filtered, hasLength(5));
      expect(filtered.every((s) => s.duration == 10.0), isTrue);
      expect(filtered.any((s) => s.url.contains('clip')), isFalse);
    });
  });

  group('filterAds - 全广告保底回退', () {
    test('全部为关键词广告时回退原始列表', () {
      final segments = [
        const M3u8Segment(url: 'https://cdn.com/ad1.ts', duration: 10.0),
        const M3u8Segment(url: 'https://cdn.com/ad2.ts', duration: 10.0),
        const M3u8Segment(url: 'https://cdn.com/advert3.ts', duration: 10.0),
      ];
      final filtered = filterAds(segments);
      // 全部被标为广告，保底比例触发，返回原始列表。
      expect(filtered, hasLength(3));
      expect(filtered, equals(segments));
    });

    test('过滤后不足保底比例时回退原始列表', () {
      // 4 个分片，3 个含 ad 关键词；保留 1 个，1/4=0.25 < 0.5，回退。
      final segments = [
        const M3u8Segment(url: 'https://cdn.com/main.ts', duration: 10.0),
        const M3u8Segment(url: 'https://cdn.com/ad1.ts', duration: 10.0),
        const M3u8Segment(url: 'https://cdn.com/ad2.ts', duration: 10.0),
        const M3u8Segment(url: 'https://cdn.com/advert3.ts', duration: 10.0),
      ];
      final filtered = filterAds(segments);
      expect(filtered, hasLength(4));
    });
  });

  group('filterAds - 禁用规则', () {
    test('AdFilterRules.disabled 不过滤任何分片', () {
      final segments = [
        const M3u8Segment(url: 'https://cdn.com/ad.ts', duration: 0.1),
        const M3u8Segment(url: 'https://cdn.com/main.ts', duration: 10.0),
      ];
      final filtered = filterAds(segments, rules: AdFilterRules.disabled);
      expect(filtered, hasLength(2));
    });
  });

  group('M3u8AdFilter.filter - playlist 字符串版', () {
    test('移除广告组并保留 header 标签', () {
      const content = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
main1.ts
#EXTINF:10.0,
main2.ts
#EXT-X-DISCONTINUITY
#EXTINF:1.0,
ad1.ts
#EXTINF:1.0,
ad2.ts
#EXT-X-DISCONTINUITY
#EXTINF:10.0,
main3.ts
#EXT-X-ENDLIST
''';
      final filtered = M3u8AdFilter.filter(content);
      expect(filtered, contains('#EXTM3U'));
      expect(filtered, contains('#EXT-X-TARGETDURATION:10'));
      expect(filtered, contains('main1.ts'));
      expect(filtered, contains('main2.ts'));
      expect(filtered, contains('main3.ts'));
      expect(filtered, contains('#EXT-X-ENDLIST'));
      // 广告分片被移除。
      expect(filtered, isNot(contains('ad1.ts')));
      expect(filtered, isNot(contains('ad2.ts')));
    });

    test('filterToSegments 返回过滤后的绝对 URL 列表', () {
      const content = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
main1.ts
#EXT-X-DISCONTINUITY
#EXTINF:1.0,
ad1.ts
#EXT-X-DISCONTINUITY
#EXTINF:10.0,
main2.ts
#EXT-X-ENDLIST
''';
      final urls = M3u8AdFilter.filterToSegments(content,
          baseUrl: 'https://cdn.com/stream/');
      expect(urls, hasLength(2));
      expect(urls, contains('https://cdn.com/stream/main1.ts'));
      expect(urls, contains('https://cdn.com/stream/main2.ts'));
      expect(urls.any((u) => u.contains('ad1')), isFalse);
    });

    test('空 playlist 原样返回', () {
      const content = '#EXTM3U\n#EXT-X-ENDLIST\n';
      expect(M3u8AdFilter.filter(content), isNotEmpty);
    });
  });
}
