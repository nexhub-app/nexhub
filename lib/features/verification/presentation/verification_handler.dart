/// Shared verification handler used by the online list pages.
///
/// Bridges the core [VerificationNavigator] (which cannot import features)
/// with the existing [WebViewVerificationScreen] navigation helpers. Cookie
/// sync is already performed inside the verification screen, so this callback
/// only decides whether the original request should be retried.
library;

import 'package:flutter/widgets.dart';

import '../../../core/resolver/webview_resolver.dart';
import '../../../core/scraper/verification_detector.dart';
import 'webview_verification_screen.dart';

/// Routes a verification exception to the proper verification screen.
///
/// - [WebViewExtractionRequest]: opens the embedded JS extraction view. When
///   an address is extracted or the user explicitly requests a retry, returns
///   `true`.
/// - [VerificationRequiredException]: opens the manual verification view.
///   Returns `true` when the user reports verification done.
/// - [WebViewRequiredException]: same as above, using the exception url.
///
/// Returns `false` when the user cancels or [error] is not a verification
/// exception handled here.
Future<bool> handleVerificationRequest(
  BuildContext context,
  Object error, {
  void Function(String extractedUrl)? onExtracted,
  void Function(String renderedHtml)? onRenderedHtml,
}) async {
  if (error is WebViewHtmlRequest) {
    final outcome = await navigateToHtmlCapture(context, request: error);
    if (outcome == null) return false;
    // 把渲染后的整页 HTML 回灌给调用方，用于复用源选择器解析
    // （修复「列表由 JS 动态渲染、静态抓取为空」）。
    if (outcome.hasRenderedHtml && outcome.renderedHtml != null) {
      onRenderedHtml?.call(outcome.renderedHtml!);
    }
    // 取回渲染 HTML 或用户显式「已完成验证」都触发重试：重试路径会带上
    // 回灌的 renderedHtml 用既有选择器解析。
    return outcome.shouldRetry || outcome.hasRenderedHtml;
  }
  if (error is WebViewExtractionRequest) {
    final outcome = await navigateToExtraction(context, request: error);
    if (outcome == null) return false;
    // 把抽取到的真实地址回灌给调用方，用于复用源选择器解析
    // （修复「浏览器能打开网页，但列表解析不到内容」）。
    if (outcome.hasExtractedUrl && outcome.extractedUrl != null) {
      onExtracted?.call(outcome.extractedUrl!);
    }
    // An extracted address or an explicit "done" both warrant a retry: the
    // original fetch path will pick up the synced cookies / use the new
    // session established inside the webview.
    return outcome.shouldRetry || outcome.hasExtractedUrl;
  }
  if (error is VerificationRequiredException) {
    return navigateToVerification(
      context,
      url: error.url,
      exception: error,
    );
  }
  if (error is WebViewRequiredException) {
    return navigateToVerification(context, url: error.url);
  }
  return false;
}
