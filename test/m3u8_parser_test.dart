import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/resolver/m3u8_parser.dart';

/// parseM3u8 / M3u8Parser 单元测试（M2.3.6）。
///
/// 覆盖场景：master playlist、简单 media playlist、带广告（discontinuity）、
/// 相对 URL 解析、data URI 嵌套、resolveUrl 静态方法。
void main() {
  group('parseM3u8 顶层函数', () {
    test('master playlist 解析出清晰度变体列表', () {
      const content = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=720x480,CODECS="avc1.42e00a,mp4a.40.2"
low.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2560000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
mid.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=7680000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
hd.m3u8
''';
      final result = parseM3u8(content,
          baseUrl: 'https://cdn.example.com/playlist/master.m3u8');

      expect(result.isMaster, isTrue);
      expect(result.variants, hasLength(3));

      final low = result.variants[0];
      expect(low.bandwidth, 1280000);
      expect(low.resolution, '720x480');
      expect(low.codecs, 'avc1.42e00a,mp4a.40.2');
      expect(low.url, 'https://cdn.example.com/playlist/low.m3u8');

      final hd = result.variants[2];
      expect(hd.bandwidth, 7680000);
      expect(hd.resolution, '1920x1080');
      expect(hd.url, 'https://cdn.example.com/playlist/hd.m3u8');
    });

    test('简单 media playlist 解析出分片列表', () {
      const content = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
seg1.ts
#EXTINF:9.5,
seg2.ts
#EXTINF:8.0,
seg3.ts
#EXT-X-ENDLIST
''';
      final result = parseM3u8(content,
          baseUrl: 'https://cdn.example.com/stream/');

      expect(result.isMedia, isTrue);
      expect(result.isMaster, isFalse);
      expect(result.segments, hasLength(3));

      final first = result.segments.first;
      expect(first.url, 'https://cdn.example.com/stream/seg1.ts');
      expect(first.duration, 10.0);
      expect(first.discontinuityGroup, 0);

      expect(result.segments[1].duration, 9.5);
      expect(result.segments[2].url, 'https://cdn.example.com/stream/seg3.ts');
    });

    test('带广告（discontinuity）的 playlist 分组索引正确', () {
      // 正片组（30s）→ 广告组（3s）→ 正片组（30s）。
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
ad1.ts
#EXTINF:1.0,
ad2.ts
#EXTINF:1.0,
ad3.ts
#EXT-X-DISCONTINUITY
#EXTINF:10.0,
main4.ts
#EXTINF:10.0,
main5.ts
#EXT-X-ENDLIST
''';
      final result = parseM3u8(content, baseUrl: 'https://cdn.example.com/');

      expect(result.segments, hasLength(8));
      // 正片组 = group 0
      expect(result.segments[0].discontinuityGroup, 0);
      expect(result.segments[2].discontinuityGroup, 0);
      // 广告组 = group 1
      expect(result.segments[3].discontinuityGroup, 1);
      expect(result.segments[5].discontinuityGroup, 1);
      // 第二段正片 = group 2
      expect(result.segments[6].discontinuityGroup, 2);
      expect(result.segments[7].discontinuityGroup, 2);
    });

    test('空内容返回空结果', () {
      final result = parseM3u8('');
      expect(result.variants, isEmpty);
      expect(result.segments, isEmpty);
      expect(result.isMaster, isFalse);
      expect(result.isMedia, isFalse);
    });
  });

  group('M3u8Parser.parseMaster', () {
    test('解析变体属性并基于 baseUrl 解析绝对 URL', () {
      const content = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360
sub/360p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720
sub/720p.m3u8
''';
      final result = M3u8Parser.parseMaster(content,
          baseUrl: 'https://video.example.com/master.m3u8');
      expect(result.isMaster, isTrue);
      expect(result.variants, hasLength(2));
      expect(result.variants[0].url,
          'https://video.example.com/sub/360p.m3u8');
      expect(result.variants[0].resolution, '640x360');
      expect(result.variants[1].bandwidth, 3000000);
    });

    test('无 BANDWIDTH 属性时回退为 0', () {
      const content = '''
#EXTM3U
#EXT-X-STREAM-INF:RESOLUTION=640x360
a.m3u8
''';
      final result = M3u8Parser.parseMaster(content);
      expect(result.variants.single.bandwidth, 0);
    });
  });

  group('M3u8Parser.parseMedia', () {
    test('解析 #EXT-X-KEY 加密信息', () {
      const content = '''
#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="https://drm.example.com/key.bin",IV=0x1234567890abcdef1234567890abcdef
#EXTINF:10.0,
seg1.ts
#EXT-X-ENDLIST
''';
      final result = M3u8Parser.parseMedia(content);
      expect(result.segments, hasLength(1));
      final key = result.segments.first.keyInfo;
      expect(key, isNotNull);
      expect(key!.method, 'AES-128');
      expect(key.uri, 'https://drm.example.com/key.bin');
      expect(key.iv, '0x1234567890abcdef1234567890abcdef');
    });

    test('解析 #EXTINF 标题', () {
      const content = '''
#EXTM3U
#EXTINF:5.5,Episode Title
seg.ts
#EXT-X-ENDLIST
''';
      final result = M3u8Parser.parseMedia(content);
      expect(result.segments.single.title, 'Episode Title');
      expect(result.segments.single.duration, 5.5);
    });
  });

  group('M3u8Parser.resolveUrl', () {
    test('绝对 http(s) URL 原样返回', () {
      expect(
        M3u8Parser.resolveUrl(
            'https://a.com/x.ts', 'https://b.com/playlist.m3u8'),
        'https://a.com/x.ts',
      );
    });

    test('data URI 原样返回', () {
      const data = 'data:application/vnd.apple.mpegurl;base64,AAAA';
      expect(M3u8Parser.resolveUrl(data, 'https://b.com/m.m3u8'), data);
    });

    test('相对 URL 基于 baseUrl 目录解析', () {
      expect(
        M3u8Parser.resolveUrl('seg.ts', 'https://b.com/stream/playlist.m3u8'),
        'https://b.com/stream/seg.ts',
      );
    });

    test('无 baseUrl 时原样返回', () {
      expect(M3u8Parser.resolveUrl('seg.ts', null), 'seg.ts');
    });
  });

  group('嵌套 data URI', () {
    test('data URI 内嵌的 media playlist 被递归展开', () {
      // 构造一个 data URI，其内容为含两个分片的 media playlist。
      const inner = '#EXTM3U\n#EXTINF:5.0,\ninner1.ts\n#EXTINF:6.0,\ninner2.ts\n#EXT-X-ENDLIST';
      final encoded = Uri.dataFromString(inner,
              mimeType: 'application/vnd.apple.mpegurl')
          .toString();
      final content = '#EXTM3U\n#EXTINF:1.0,\n$encoded\n#EXT-X-ENDLIST';

      final result = M3u8Parser.parse(content);
      // 嵌套 playlist 展开后应得到 inner 的两个分片。
      expect(result.segments, hasLength(2));
      expect(result.segments[0].url, 'inner1.ts');
      expect(result.segments[0].duration, 5.0);
      expect(result.segments[1].duration, 6.0);
    });
  });
}
