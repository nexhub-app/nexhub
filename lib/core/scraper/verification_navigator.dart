/// Common verification navigation helper.
///
/// Concentrates the "catch VerificationRequiredException /
/// WebViewExtractionRequest -> jump to verification screen -> sync cookie ->
/// retry" flow into one place, so the online list / detail / browse pages do
/// not duplicate it.
///
/// Architecture: this file lives in `core/` and MUST NOT import `features/`.
/// The actual screen navigation is injected by the caller via [VerifyCallback]
/// (the features layer provides the implementation).
library;

import 'package:flutter/widgets.dart';

import '../resolver/webview_resolver.dart';
import 'verification_detector.dart';

/// Verification navigation callback injected by the features layer.
///
/// Returns `true` when the user finished verification/extraction and the
/// original request should be retried; `false` when cancelled or not
/// applicable. Cookie sync is handled inside the injected implementation
/// (the verification screen already syncs cookies to HttpFetcher).
typedef VerifyCallback = Future<bool> Function(
  BuildContext context,
  Object error, {
  void Function(String extractedUrl)? onExtracted,
  void Function(String renderedHtml)? onRenderedHtml,
});

/// Common verification navigator.
///
/// Pure dispatcher: it does not know how to open the verification screen
/// (that would require importing features from core). Instead the caller
/// injects a [VerifyCallback]. This keeps the architecture boundary intact
/// while still collapsing the catch/retry boilerplate into one helper.
class VerificationNavigator {
  VerificationNavigator._();

  /// Returns `true` if [error] is a verification-related exception that the
  /// navigator knows how to handle.
  static bool isVerificationError(Object error) =>
      error is VerificationRequiredException ||
      error is WebViewRequiredException ||
      error is WebViewExtractionRequest ||
      error is WebViewHtmlRequest;

  /// Handles a verification exception and retries exactly once.
  ///
  /// When [error] is a verification exception and [verifyHandler] is provided,
  /// this calls [verifyHandler] to jump to the verification screen (cookie sync
  /// is done inside the handler), then calls [retry] exactly once.
  ///
  /// Returns `true` when:
  /// - verification succeeded and [retry] completed without throwing. The
  ///   caller may clear its error state (the retry callback is expected to
  ///   clear it on success).
  /// - verification succeeded but [retry] threw. [onErrorText] has been
  ///   invoked with the retry error text, so the caller MUST NOT overwrite
  ///   the error state.
  ///
  /// Returns `false` when:
  /// - [error] is not a verification exception, or [verifyHandler] is null.
  ///   The caller sets the original `e.toString()` (or a localized message).
  /// - the [BuildContext] is no longer mounted.
  /// - the user cancelled verification. The caller sets a localized
  ///   "verification required" message.
  static Future<bool> handleVerificationAndRetry(
    BuildContext context,
    Object error,
    Future<void> Function() retry, {
    VerifyCallback? verifyHandler,
    void Function(String errorText)? onErrorText,
    void Function(String extractedUrl)? onExtracted,
    void Function(String renderedHtml)? onRenderedHtml,
  }) async {
    if (!isVerificationError(error) || verifyHandler == null) {
      return false;
    }
    if (!context.mounted) {
      return false;
    }
    try {
      final verified = await verifyHandler(
        context,
        error,
        onExtracted: onExtracted,
        onRenderedHtml: onRenderedHtml,
      );
      if (!verified) {
        return false;
      }
      await retry();
      return true;
    } on Object catch (e) {
      if (onErrorText != null) {
        onErrorText(e.toString());
      }
      // Already set the error text via the callback: signal "handled" so the
      // caller does not overwrite the localized message with e.toString().
      return true;
    }
  }
}
