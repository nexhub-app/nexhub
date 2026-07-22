import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/js_context.dart';
import 'package:nexhub/core/utils/crypto_utils.dart';

/// Unit tests for the JS sandbox bridge (Task M1.4).
///
/// Covers the crypto / image / storage / utils / http extensions added to
/// [DartJsHostBridge] and [CryptoUtils]. HTTP network methods are excluded
/// (they require live network); URL scheme validation is tested instead.
void main() {
  group('CryptoUtils.sha', () {
    test('sha1 of "abc" matches NIST test vector', () {
      expect(
        CryptoUtils.sha1Hex('abc'),
        'a9993e364706816aba3e25717850c26c9cd0d89d',
      );
    });

    test('sha256 of "abc" matches NIST test vector', () {
      expect(
        CryptoUtils.sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('sha512 of "abc" matches NIST test vector', () {
      expect(
        CryptoUtils.sha512Hex('abc'),
        'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a'
        '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f',
      );
    });
  });

  group('CryptoUtils.hmac', () {
    test('HMAC-SHA256 matches RFC 4231 test case 2', () {
      expect(
        CryptoUtils.hmacHex('Jefe', 'what do ya want for nothing?'),
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );
    });

    test('HMAC-SHA1 produces a 40-char hex string and differs from SHA256', () {
      final h1 = CryptoUtils.hmacHex('key', 'data', algorithm: 'sha1');
      final h256 = CryptoUtils.hmacHex('key', 'data', algorithm: 'sha256');
      expect(h1.length, 40);
      expect(h256.length, 64);
      expect(h1, isNot(equals(h256)));
    });
  });

  group('CryptoUtils.hex', () {
    test('hexEncode([0xFF, 0x00]) returns "ff00"', () {
      expect(CryptoUtils.hexEncode(<int>[0xFF, 0x00]), 'ff00');
    });

    test('hexDecode("ff00") returns [255, 0]', () {
      expect(CryptoUtils.hexDecode('ff00'), <int>[255, 0]);
    });

    test('hexEncode then hexDecode round-trips arbitrary bytes', () {
      const bytes = <int>[0, 1, 127, 128, 255, 10, 200];
      expect(CryptoUtils.hexDecode(CryptoUtils.hexEncode(bytes)), bytes);
    });

    test('hexDecode throws on odd-length string', () {
      expect(() => CryptoUtils.hexDecode('abc'), throwsA(isA<FormatException>()));
    });
  });

  group('CryptoUtils AES round-trips', () {
    // AES-128 key (16 bytes) and IV (16 bytes).
    final key = utf8.encode('1234567890abcdef');
    final iv = utf8.encode('abcdef0123456789');
    const plain = 'Hello, AES World!';

    test('AES-CBC encrypt then decrypt restores plaintext', () {
      final cipher = CryptoUtils.aesCbcEncrypt(
        utf8.encode(plain),
        key: key,
        iv: iv,
      );
      final decrypted = CryptoUtils.aesCbcDecrypt(cipher, key: key, iv: iv);
      expect(decrypted, plain);
    });

    test('AES-ECB encrypt then decrypt restores plaintext', () {
      final cipher = CryptoUtils.aesEcbEncrypt(utf8.encode(plain), key: key);
      final plainBytes = CryptoUtils.aesEcbDecrypt(cipher, key: key);
      expect(utf8.decode(plainBytes), plain);
    });

    test('AES-CFB encrypt then decrypt restores plaintext', () {
      final cipher = CryptoUtils.aesCfbEncrypt(
        utf8.encode(plain),
        key: key,
        iv: iv,
      );
      final plainBytes = CryptoUtils.aesCfbDecrypt(cipher, key: key, iv: iv);
      expect(utf8.decode(plainBytes), plain);
    });

    test('AES-OFB encrypt then decrypt restores plaintext', () {
      final cipher = CryptoUtils.aesOfbProcess(
        utf8.encode(plain),
        key: key,
        iv: iv,
      );
      final plainBytes = CryptoUtils.aesOfbProcess(cipher, key: key, iv: iv);
      expect(utf8.decode(plainBytes), plain);
    });

    test('AES key length validation rejects invalid key', () {
      expect(
        () => CryptoUtils.aesCbcEncrypt(
          utf8.encode(plain),
          key: <int>[1, 2, 3],
          iv: iv,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('DartJsHostBridge crypto', () {
    final bridge = DartJsHostBridge(_source);

    test('sha256 via bridge matches CryptoUtils', () {
      expect(bridge.sha256('abc'), CryptoUtils.sha256Hex('abc'));
    });

    test('aesDecrypt alias equals aesCbc decrypt', () {
      final key = base64.encode(utf8.encode('1234567890abcdef'));
      final iv = base64.encode(utf8.encode('abcdef0123456789'));
      const plain = 'Bridge AES test';
      final cipher = bridge.aesCbc(key, base64.encode(utf8.encode(plain)), iv,
          encrypt: true);
      final decrypted = bridge.aesDecrypt(cipher, key, iv);
      expect(decrypted, plain);
    });

    test('hexEncode/hexDecode via bridge', () {
      expect(bridge.hexEncode(<int>[0xAB, 0xCD]), 'abcd');
      expect(bridge.hexDecode('abcd'), <int>[0xAB, 0xCD]);
    });
  });

  group('DartJsHostBridge storage', () {
    test('set then get returns value; remove then get returns null', () {
      final bridge = DartJsHostBridge(_sourceWithId('storage-test-1'));
      bridge.storageSet('k', 'v');
      expect(bridge.storageGet('k'), 'v');
      bridge.storageRemove('k');
      expect(bridge.storageGet('k'), isNull);
    });

    test('storage is namespaced by sourceId (isolated between sources)', () {
      final bridgeA = DartJsHostBridge(_sourceWithId('storage-src-a'));
      final bridgeB = DartJsHostBridge(_sourceWithId('storage-src-b'));
      bridgeA.storageSet('token', 'aaa');
      bridgeB.storageSet('token', 'bbb');
      expect(bridgeA.storageGet('token'), 'aaa');
      expect(bridgeB.storageGet('token'), 'bbb');
    });
  });

  group('DartJsHostBridge image', () {
    final bridge = DartJsHostBridge(_source);

    test('isValidImageUrl rejects ad keywords and accepts valid URLs', () {
      expect(bridge.isValidImageUrl('https://x.com/ad/banner.gif'), isFalse);
      expect(bridge.isValidImageUrl('https://x.com/1x1.png'), isFalse);
      expect(bridge.isValidImageUrl('https://example.com/image1.jpg'), isTrue);
    });

    test('extractLazyImagesFromHtml recovers data-src', () {
      const html = '<img src="placeholder.jpg" data-src="real.jpg">';
      expect(bridge.extractLazyImagesFromHtml(html), <String>['real.jpg']);
    });

    test('filterImages drops ads and duplicates', () {
      final urls = <String>[
        'https://x.com/ad/banner.gif',
        'https://x.com/1.jpg',
        'https://x.com/1.jpg',
      ];
      expect(bridge.filterImages(urls), <String>['https://x.com/1.jpg']);
    });

    test('getPageUrls completes relative URLs against baseUrl', () {
      const html = '<img data-src="/img/1.jpg">';
      final urls = bridge.getPageUrls(html, <String, dynamic>{
        'mode': 'list',
        'src': 'data-src',
      });
      expect(urls, <String>['https://example.com/img/1.jpg']);
    });
  });

  group('DartJsHostBridge utils', () {
    test('setTimeout completes within reasonable time', () async {
      final bridge = DartJsHostBridge(_source);
      final sw = Stopwatch()..start();
      await bridge.utilsSetTimeout(100);
      sw.stop();
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(90));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('setTimeout caps at 10 seconds', () async {
      final bridge = DartJsHostBridge(_source);
      final sw = Stopwatch()..start();
      await bridge.utilsSetTimeout(999999);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(11000));
    });
  });

  group('DartJsHostBridge http scheme validation', () {
    test('httpFetch rejects non-http scheme', () {
      final bridge = DartJsHostBridge(_source);
      expect(
        () => bridge.httpFetch('file:///etc/passwd'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('httpPut rejects non-http scheme', () {
      final bridge = DartJsHostBridge(_source);
      expect(
        () => bridge.httpPut('ftp://x/y', 'body'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('httpDelete rejects non-http scheme', () {
      final bridge = DartJsHostBridge(_source);
      expect(
        () => bridge.httpDelete('javascript:alert(1)'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

/// Minimal source config for bridge tests.
PluginConfig get _source => PluginConfig.fromJson(<String, dynamic>{
      'id': 'test-bridge',
      'name': 'Test Bridge',
      'type': 'mangaSource',
      'site': {'baseUrl': 'https://example.com'},
      'parser': {'type': 'script', 'script': ''},
      'routes': <String, dynamic>{},
    });

/// Source config with a custom id (for storage isolation tests).
PluginConfig _sourceWithId(String id) => PluginConfig.fromJson(<String, dynamic>{
      'id': id,
      'name': 'Test',
      'type': 'mangaSource',
      'site': {'baseUrl': 'https://example.com'},
      'parser': {'type': 'script', 'script': ''},
      'routes': <String, dynamic>{},
    });
