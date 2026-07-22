import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/resolver/webview_resolver.dart';
import 'package:nexhub/core/scraper/verification_detector.dart';
import 'package:nexhub/core/scraper/verification_navigator.dart';

/// Pumps a minimal widget tree and returns a mounted [BuildContext].
Future<BuildContext> pumpContext(WidgetTester tester) async {
  BuildContext? captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured!;
}

void main() {
  group('VerificationNavigator.isVerificationError', () {
    test('returns true for VerificationRequiredException', () {
      expect(
        VerificationNavigator.isVerificationError(
          const VerificationRequiredException(url: 'https://example.com'),
        ),
        isTrue,
      );
    });

    test('returns true for WebViewRequiredException', () {
      expect(
        VerificationNavigator.isVerificationError(
          const WebViewRequiredException('https://example.com'),
        ),
        isTrue,
      );
    });

    test('returns true for WebViewExtractionRequest', () {
      expect(
        VerificationNavigator.isVerificationError(
          const WebViewExtractionRequest(
            sourceId: 's',
            apiName: 'latest',
            url: 'https://example.com',
            jsExtractor: 'return null;',
          ),
        ),
        isTrue,
      );
    });

    test('returns false for a generic Exception', () {
      expect(
        VerificationNavigator.isVerificationError(Exception('foo')),
        isFalse,
      );
    });

    test('returns false for a StateError', () {
      expect(
        VerificationNavigator.isVerificationError(StateError('bar')),
        isFalse,
      );
    });
  });

  group('VerificationNavigator.handleVerificationAndRetry', () {
    testWidgets(
        'returns false for non-verification error without invoking handler or retry',
        (tester) async {
      final context = await pumpContext(tester);
      var verifyCalls = 0;
      var retryCalls = 0;

      final result = await VerificationNavigator.handleVerificationAndRetry(
        context,
        Exception('not a verification error'),
        () async {
          retryCalls++;
        },
        verifyHandler: (ctx, err, {onExtracted, onRenderedHtml}) async {
          verifyCalls++;
          return true;
        },
      );

      expect(result, isFalse);
      expect(verifyCalls, 0);
      expect(retryCalls, 0);
    });

    testWidgets('returns false and skips retry when verifyHandler is null',
        (tester) async {
      final context = await pumpContext(tester);
      var retryCalls = 0;

      final result = await VerificationNavigator.handleVerificationAndRetry(
        context,
        const VerificationRequiredException(url: 'https://example.com'),
        () async {
          retryCalls++;
        },
      );

      expect(result, isFalse);
      expect(retryCalls, 0);
    });

    testWidgets('retries once after successful verification and returns true',
        (tester) async {
      final context = await pumpContext(tester);
      var retryCalls = 0;

      final result = await VerificationNavigator.handleVerificationAndRetry(
        context,
        const VerificationRequiredException(url: 'https://example.com'),
        () async {
          retryCalls++;
        },
        verifyHandler: (ctx, err, {onExtracted, onRenderedHtml}) async => true,
      );

      expect(result, isTrue);
      expect(retryCalls, 1);
    });

    testWidgets(
        'calls onErrorText with retry error text and returns true when retry throws',
        (tester) async {
      final context = await pumpContext(tester);
      String? capturedError;

      final result = await VerificationNavigator.handleVerificationAndRetry(
        context,
        const VerificationRequiredException(url: 'https://example.com'),
        () async {
          throw Exception('retry boom');
        },
        verifyHandler: (ctx, err, {onExtracted, onRenderedHtml}) async => true,
        onErrorText: (text) {
          capturedError = text;
        },
      );

      expect(result, isTrue);
      expect(capturedError, isNotNull);
      expect(capturedError, contains('retry boom'));
    });

    testWidgets('returns false and skips retry when user cancels verification',
        (tester) async {
      final context = await pumpContext(tester);
      var retryCalls = 0;

      final result = await VerificationNavigator.handleVerificationAndRetry(
        context,
        const WebViewRequiredException('https://example.com'),
        () async {
          retryCalls++;
        },
        verifyHandler: (ctx, err, {onExtracted, onRenderedHtml}) async => false,
      );

      expect(result, isFalse);
      expect(retryCalls, 0);
    });

    testWidgets(
        'captures verifyHandler exception via onErrorText and returns true',
        (tester) async {
      final context = await pumpContext(tester);
      String? capturedError;
      var retryCalls = 0;

      final result = await VerificationNavigator.handleVerificationAndRetry(
        context,
        const VerificationRequiredException(url: 'https://example.com'),
        () async {
          retryCalls++;
        },
        verifyHandler: (ctx, err, {onExtracted, onRenderedHtml}) async {
          throw StateError('verify failed');
        },
        onErrorText: (text) {
          capturedError = text;
        },
      );

      // The implementation wraps both verifyHandler and retry in one try/catch,
      // so a verifyHandler exception is captured the same way as a retry error.
      expect(result, isTrue);
      expect(retryCalls, 0);
      expect(capturedError, isNotNull);
      expect(capturedError, contains('verify failed'));
    });
  });
}
