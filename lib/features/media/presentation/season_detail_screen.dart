import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/models/episode.dart';
import '../../../core/models/media_item.dart';
import '../../../core/resolver/webview_resolver.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/scraper/verification_detector.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_error_state.dart';
import '../../player/presentation/video_player_screen.dart';
import '../../verification/presentation/webview_verification_screen.dart';

/// 季详情页：展示某季的剧集网格，点击进入 [VideoPlayerScreen]。
///
/// 数据来自源 episodes 路由（以季 ID 作为 {id}）。
/// 顶部返回按钮 + 标题；主体集卡片网格；点击进入播放。
class SeasonDetailScreen extends StatefulWidget {
  /// 当前季（需含 sourceId / id / title）。
  final MediaItem season;

  /// 所属系列（用于播放器标题展示）。
  final MediaItem series;

  const SeasonDetailScreen({
    super.key,
    required this.season,
    required this.series,
  });

  @override
  State<SeasonDetailScreen> createState() => _SeasonDetailScreenState();
}

class _SeasonDetailScreenState extends State<SeasonDetailScreen> {
  late Future<List<Episode>> _episodesFuture;

  /// 验证异常状态（非 null 时显示验证引导 UI）。
  VerificationRequiredException? _verificationError;
  /// 渲染后抽取请求（webview-html 模式）：非 null 时显示「抓取本页渲染内容」引导。
  WebViewHtmlRequest? _htmlCaptureRequest;
  /// 渲染后回灌的整页 HTML（重试抓取时复用源选择器解析）。
  String? _renderedHtml;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repo = context.read<SourceRepository>();
    final service = context.read<MediaApiService>();
    final sid = widget.season.sourceId ?? widget.series.sourceId;
    final id = widget.season.id;
    if (sid == null) {
      _episodesFuture = Future<List<Episode>>.error(
        Exception('item missing source id'),
      );
      return;
    }
    final source = repo.getById(sid);
    if (source == null) {
      _episodesFuture = Future<List<Episode>>.error(
        Exception('source not found: $sid'),
      );
      return;
    }
    final future = service.fetchEpisodes(source, id,
        title: widget.season.title, renderedHtml: _renderedHtml);
    _episodesFuture = future;
    // 监听错误以捕获验证异常；通过 then 转为 Future<void> 避免 catchError
    // 返回类型不匹配的告警。原 future 仍由 FutureBuilder 消费。
    future.then((_) {}).catchError((Object error) {
      if (error is WebViewHtmlRequest && mounted) {
        setState(() => _htmlCaptureRequest = error);
      } else if (error is VerificationRequiredException && mounted) {
        setState(() => _verificationError = error);
      }
    });
  }

  void _retryAfterVerification() {
    setState(() => _verificationError = null);
    _load();
  }

  /// 渲染后抽取完成后回填 HTML 并重试抓取（xgcartoon 等 webview-html 源）。
  Future<void> _retryAfterHtmlCapture(String html) async {
    if (!mounted) return;
    setState(() {
      _htmlCaptureRequest = null;
      _verificationError = null;
      _renderedHtml = html;
    });
    _load();
  }

  void _openEpisode(Episode ep) {
    final sid = widget.season.sourceId ?? widget.series.sourceId;
    if (sid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          title: widget.series.title,
          episode: ep,
          sourceId: sid,
          itemId: widget.season.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final season = widget.season;

    // 渲染后抽取请求 → 显示「抓取本页渲染内容」引导（webview-html 源）。
    if (_htmlCaptureRequest != null) {
      return Scaffold(
        appBar: AppBar(title: Text(season.title)),
        body: AppErrorState(
          message: l10n.captureHint,
          onRetry: () async {
            final outcome = await navigateToHtmlCapture(
              context,
              request: _htmlCaptureRequest!,
            );
            if (outcome?.hasRenderedHtml == true) {
              await _retryAfterHtmlCapture(outcome!.renderedHtml!);
            }
          },
          retryLabel: l10n.captureFromPage,
        ),
      );
    }

    // 验证异常 → 显示验证引导。
    if (_verificationError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(season.title)),
        body: AppErrorState(
          message: l10n.errorVerification,
          onRetry: () async {
            final shouldRetry = await navigateToVerification(
              context,
              url: _verificationError!.url,
              exception: _verificationError,
            );
            if (shouldRetry) _retryAfterVerification();
          },
          retryLabel: l10n.openInBrowser,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(season.title)),
      body: FutureBuilder<List<Episode>>(
        future: _episodesFuture,
        builder: (BuildContext context, AsyncSnapshot<List<Episode>> snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return AppErrorState(
              message: l10n.loadFailed,
              onRetry: _load,
              retryLabel: l10n.retry,
            );
          }
          final episodes = snap.data ?? <Episode>[];
          if (episodes.isEmpty) {
            return AppEmptyState(
              icon: Icons.tv_outlined,
              message: l10n.emptyContent,
            );
          }
          return _buildEpisodeGrid(context, episodes);
        },
      ),
    );
  }

  /// 集卡片网格：紧凑型卡片，显示集标题 + 播放图标。
  Widget _buildEpisodeGrid(BuildContext context, List<Episode> episodes) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        childAspectRatio: 2.0,
        crossAxisSpacing: AppTokens.spaceSm,
        mainAxisSpacing: AppTokens.spaceSm,
      ),
      itemCount: episodes.length,
      itemBuilder: (BuildContext _, int i) {
        final Episode ep = episodes[i];
        return Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openEpisode(ep),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceSm,
                vertical: AppTokens.spaceXs,
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.play_circle_outline,
                      size: 24, color: scheme.primary),
                  const SizedBox(width: AppTokens.spaceXs),
                  Expanded(
                    child: Text(
                      ep.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
