/// RSSHub 路由推荐共享数据。
///
/// 抽取自 `rss_add_subscription_screen.dart`，供浏览页与各模块添加页共用。
/// 所有 path 均为 RSSHub 真实路由（占位参数以 `:param` 表示，
/// 参考 https://docs.rsshub.app/zh/routes ）。
library;

import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../models/plugin_config.dart';

/// RSSHub 路由推荐项数据模型。
class RssHubRouteItem {
  final String label;
  final String path;
  const RssHubRouteItem({required this.label, required this.path});
}

/// Return recommended RSSHub routes based on module type.
///
/// Label 文案走 l10n（中英同步），需传入 [AppLocalizations]。
/// 传入 [type] 为 null（或未知模块）时返回所有模块的全局路由。
List<RssHubRouteItem> routesForType(SourceType? type, AppLocalizations l10n) {
  switch (type) {
    case SourceType.novelSource:
      return <RssHubRouteItem>[
        RssHubRouteItem(label: l10n.rsshubRouteQidian, path: '/qidian/free/:type?'),
        RssHubRouteItem(label: l10n.rsshubRouteJjwxc, path: '/jjwxc/book/:id'),
        RssHubRouteItem(label: l10n.rsshubRouteDoubanBooks, path: '/douban/book/rank/:type?'),
        RssHubRouteItem(label: l10n.rsshubRouteLinovelib, path: '/linovelib/novel/:id'),
        RssHubRouteItem(label: l10n.rsshubRouteSfacg, path: '/sfacg/novel/chapter/:id'),
      ];
    case SourceType.animeSource:
      return <RssHubRouteItem>[
        RssHubRouteItem(label: l10n.rsshubRouteBilibiliBangumi, path: '/bilibili/bangumi/media/:mediaid'),
        RssHubRouteItem(label: l10n.rsshubRouteBilibiliUserVideo, path: '/bilibili/user/video/:uid'),
        RssHubRouteItem(label: l10n.rsshubRouteBilibiliRanking, path: '/bilibili/partion/ranking/:tid/:days?'),
        RssHubRouteItem(label: l10n.rsshubRouteYoutubeChannel, path: '/youtube/channel/:id'),
        RssHubRouteItem(label: l10n.rsshubRouteTwitterUser, path: '/twitter/user/:id'),
      ];
    case SourceType.mangaSource:
      return <RssHubRouteItem>[
        RssHubRouteItem(label: l10n.rsshubRouteBilibiliMangaUpdate, path: '/bilibili/manga/update/:comicid'),
        RssHubRouteItem(label: l10n.rsshubRouteDmzj, path: '/dmzj/news/:category?'),
        RssHubRouteItem(label: l10n.rsshubRouteJmcomic, path: '/18comic/:category?/:time?/:order?/:keyword?'),
      ];
    default:
      return <RssHubRouteItem>[
        RssHubRouteItem(label: l10n.rsshubRouteQidian, path: '/qidian/free/:type?'),
        RssHubRouteItem(label: l10n.rsshubRouteJjwxc, path: '/jjwxc/book/:id'),
        RssHubRouteItem(label: l10n.rsshubRouteDoubanBooks, path: '/douban/book/rank/:type?'),
        RssHubRouteItem(label: l10n.rsshubRouteLinovelib, path: '/linovelib/novel/:id'),
        RssHubRouteItem(label: l10n.rsshubRouteSfacg, path: '/sfacg/novel/chapter/:id'),
        RssHubRouteItem(label: l10n.rsshubRouteBilibiliBangumi, path: '/bilibili/bangumi/media/:mediaid'),
        RssHubRouteItem(label: l10n.rsshubRouteBilibiliUserVideo, path: '/bilibili/user/video/:uid'),
        RssHubRouteItem(label: l10n.rsshubRouteBilibiliRanking, path: '/bilibili/partion/ranking/:tid/:days?'),
        RssHubRouteItem(label: l10n.rsshubRouteYoutubeChannel, path: '/youtube/channel/:id'),
        RssHubRouteItem(label: l10n.rsshubRouteTwitterUser, path: '/twitter/user/:id'),
        RssHubRouteItem(label: l10n.rsshubRouteBilibiliMangaUpdate, path: '/bilibili/manga/update/:comicid'),
        RssHubRouteItem(label: l10n.rsshubRouteDmzj, path: '/dmzj/news/:category?'),
        RssHubRouteItem(label: l10n.rsshubRouteJmcomic, path: '/18comic/:category?/:time?/:order?/:keyword?'),
      ];
  }
}
