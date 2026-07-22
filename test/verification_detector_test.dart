import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/scraper/verification_detector.dart';

void main() {
  group('VerificationDetector', () {
    test('401 / 403 always require verification', () {
      expect(
        VerificationDetector.isVerificationRequired(statusCode: 401, body: 'x'),
        isTrue,
      );
      expect(
        VerificationDetector.isVerificationRequired(statusCode: 403, body: 'x'),
        isTrue,
      );
    });

    test('503 with Cloudflare challenge feature requires verification', () {
      const body = '<html><body>cf-ray: 123</body></html>';
      expect(
        VerificationDetector.isVerificationRequired(statusCode: 503, body: body),
        isTrue,
      );
    });

    test('200 with __cf_chl challenge feature requires verification', () {
      const body = 'please wait <div class="__cf_chl"></div>';
      expect(
        VerificationDetector.isVerificationRequired(statusCode: 200, body: body),
        isTrue,
      );
    });

    test('fsdm02 slider guard page requires verification', () {
      const body = '<script src="/_guard/slide.js"></script>';
      expect(
        VerificationDetector.isVerificationRequired(statusCode: 200, body: body),
        isTrue,
      );
    });

    test('normal 200 page does not require verification', () {
      const body = '<html><body>hello world</body></html>';
      expect(
        VerificationDetector.isVerificationRequired(statusCode: 200, body: body),
        isFalse,
      );
    });

    test('503 without challenge feature does not require verification', () {
      const body = '<html><body>service unavailable</body></html>';
      expect(
        VerificationDetector.isVerificationRequired(statusCode: 503, body: body),
        isFalse,
      );
    });

    // ---- WAF「拦截应答」检测（cycani / girigirilove: 200 + body="closed"）----

    test('200 with body exactly "closed" requires verification (Edge WAF)', () {
      expect(
        VerificationDetector.isVerificationRequired(
            statusCode: 200, body: 'closed'),
        isTrue,
      );
    });

    test('body "closed" with surrounding whitespace/case still matches', () {
      expect(
        VerificationDetector.isVerificationRequired(
            statusCode: 200, body: '  CLOSED\n'),
        isTrue,
      );
    });

    test('normal content containing the word "closed" is NOT verification', () {
      // 关键防误伤：正常页面里出现 closed 一词不能触发验证死循环。
      const body =
          '<html><body><span class="status">已完结 closed</span></body></html>';
      expect(
        VerificationDetector.isVerificationRequired(statusCode: 200, body: body),
        isFalse,
      );
    });

    test('short non-JSON body + Edge WAF Server header requires verification',
        () {
      expect(
        VerificationDetector.isVerificationRequired(
          statusCode: 200,
          body: 'denied',
          headers: {'Server': 'Edge/1.1.18'},
        ),
        isTrue,
      );
    });

    test('valid JSON body + Edge Server header is NOT verification', () {
      // 同一 WAF 放行后返回的正常大 JSON 不能被误判。
      const body =
          '{"code":1,"msg":"数据列表","page":1,"list":[{"vod_id":1,"vod_name":"x"}]}';
      expect(
        VerificationDetector.isVerificationRequired(
          statusCode: 200,
          body: body,
          headers: {'server': 'Edge/1.1.18'},
        ),
        isFalse,
      );
    });
  });
}
