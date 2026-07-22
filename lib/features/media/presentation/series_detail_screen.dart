import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_cover_image.dart';
import '../../../core/widgets/app_empty_state.dart';
import 'season_detail_screen.dart';

/// 系列详情页：展示该系列下所有季的卡片网格，点击进入 [SeasonDetailScreen]。
///
/// 数据来自 [MediaItem.seasons]，由源 detail 路由解析填充。
/// 顶部返回按钮 + 标题；主体季卡片网格；点击进入集列表。
class SeriesDetailScreen extends StatelessWidget {
  /// 系列条目（应包含非空 [MediaItem.seasons]）。
  final MediaItem series;

  const SeriesDetailScreen({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<MediaItem> seasons = series.seasons ?? <MediaItem>[];
    final PluginConfig? source =
        context.read<SourceRepository>().getById(series.sourceId ?? '');

    return Scaffold(
      appBar: AppBar(title: Text(series.title)),
      body: seasons.isEmpty
          ? AppEmptyState(icon: Icons.tv_off_outlined, message: l10n.emptyContent)
          : GridView.builder(
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.52,
                crossAxisSpacing: AppTokens.spaceMd,
                mainAxisSpacing: AppTokens.spaceMd,
              ),
              itemCount: seasons.length,
              itemBuilder: (BuildContext _, int i) => _SeasonCard(
                  season: seasons[i], series: series, source: source),
            ),
    );
  }
}

/// 单个季卡片：封面 + 标题 + 集数角标，点击进入季详情。
class _SeasonCard extends StatelessWidget {
  final MediaItem season;
  final MediaItem series;
  final PluginConfig? source;

  const _SeasonCard({
    required this.season,
    required this.series,
    this.source,
  });

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SeasonDetailScreen(season: season, series: series),
        ),
      ),
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: AppCoverImage(
                    coverUrl: season.coverUrl,
                    source: source,
                  ),
                ),
                if (season.episodeCount != null)
                  Positioned(
                    left: AppTokens.spaceXs,
                    bottom: AppTokens.spaceXs,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.spaceXs,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                      ),
                      child: Text(
                        l10n.episodeCount(season.episodeCount!),
                        style: TextStyle(color: scheme.onPrimary, fontSize: 10),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            season.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
