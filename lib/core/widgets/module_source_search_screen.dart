/// 模块源搜索页（文档 §10.2 搜索统一）。
///
/// 跨全部活跃源搜索，按 [SourceType] 过滤。
/// 小说/媒体/漫画三模块共用，布局偏好与书架/设置页共用 [LayoutSettingsStore] 单例。
/// 输入防抖 300ms，避免每个按键都触发跨源搜索请求。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../../core/models/media_item.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/scraper/verification_navigator.dart';
import '../../../core/settings/layout_settings.dart';
import '../../../core/widgets/layout_picker_button.dart';
import '../../../core/services/source_repository.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_loading_indicator.dart';
import '../../../core/comic/comic_progress_manager.dart';
import '../../../core/history/media_watched_manager.dart';
import '../../../core/novel/novel_progress_manager.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_cover_image.dart';
import '../../../core/widgets/content_card.dart';
import '../../../core/widgets/module_search_screen.dart';
import '../../features/verification/presentation/verification_handler.dart';

/// 搜索范围：聚合（该模块全部源）或单源（指定一个源）。
enum _SearchScope { aggregate, single }

class ModuleSourceSearchScreen extends StatefulWidget {
  final SourceType sourceType;
  final String title;
  final String? initialQuery;
  /// 定向搜索字段（author/tag/actor/director）；null 表示通用关键词搜索。
  final String? searchField;
  /// 直达地址：调用方已取得的真实页面链接（如详情页抓取到的作者/标签落地页），
  /// 非空时进入直达模式，直接用它检索并信任返回结果。
  final String? extractedUrl;
  final void Function(MediaItem item) onItemTap;

  const ModuleSourceSearchScreen({
    super.key,
    required this.sourceType,
    required this.title,
    this.initialQuery,
    this.searchField,
    this.extractedUrl,
    required this.onItemTap,
  });

  @override
  State<ModuleSourceSearchScreen> createState() =>
      _ModuleSourceSearchScreenState();
}

class _ModuleSourceSearchScreenState extends State<ModuleSourceSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _grid = true;
  bool _loading = false;
  List<MediaItem> _results = const <MediaItem>[];
  String? _extractedUrl;
  Timer? _debounce;

  /// 搜索范围：聚合全部源 / 单源。
  _SearchScope _scope = _SearchScope.aggregate;
  /// 单源模式下选中的源 id（null 表示未选）。
  String? _selectedSourceId;
  /// 进度计算缓存（按 "id#list" / "id#showProgress" 维度），避免列表/网格重复计算。
  final Map<String, Future<double?>> _progressFutures =
      <String, Future<double?>>{};
  /// 当前字段筛选（null=关键词；tags/author/director/actors/title）。
  String? _searchField;
  /// 单源模式但未选源时的提示标记。
  bool _needSource = false;

  @override
  void initState() {
    super.initState();
    // 与书架/设置页共用同一 LayoutSettingsStore 单例，布局全局统一。
    _grid = LayoutSettingsStore.instance.settings.layoutMode == LayoutMode.grid;
    LayoutSettingsStore.instance.addListener(_onLayoutStoreChanged);
    _searchField = widget.searchField;
    // 直达模式：调用方已提供真实页面地址（如详情页抓取到的作者/标签落地页），
    // 直接带入搜索，跳过关键词输入与客户端收窄（服务端已按该页过滤）。
    _extractedUrl = widget.extractedUrl;
    final String? q = widget.initialQuery;
    if (q != null && q.isNotEmpty) {
      _controller.text = q;
      _doSearch(q);
    }
  }

  /// 订阅全局布局单例：书架/设置页或本页弹窗改动布局时，即时刷新网格/列表。
  void _onLayoutStoreChanged() {
    if (mounted) {
      setState(() {
        _grid = LayoutSettingsStore.instance.settings.layoutMode == LayoutMode.grid;
      });
    }
  }

  @override
  void dispose() {
    LayoutSettingsStore.instance.removeListener(_onLayoutStoreChanged);
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _doSearch(String query) async {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      if (mounted) {
        setState(() {
          _results = const <MediaItem>[];
          _loading = false;
          _needSource = false;
        });
      }
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      // 单源模式但未选源：提示选择，不发起请求。
      if (_scope == _SearchScope.single && _selectedSourceId == null) {
        if (mounted) {
          setState(() {
            _results = const <MediaItem>[];
            _loading = false;
            _needSource = true;
          });
        }
        return;
      }
      setState(() {
        _loading = true;
        _needSource = false;
      });

      try {
        final sourceRepo = context.read<SourceRepository>();
        final mediaService = context.read<MediaApiService>();
        var sources = sourceRepo.byType(widget.sourceType);
        if (_scope == _SearchScope.single && _selectedSourceId != null) {
          sources = sources.where((s) => s.id == _selectedSourceId).toList();
        }

        final allResults = <MediaItem>[];
        for (final source in sources) {
          // 仅在调用方未提供直达地址时重置；否则保留 widget.extractedUrl 贯穿整个循环。
          if (widget.extractedUrl == null) _extractedUrl = null;
          String? renderedHtml;
          // 字段路由选择：选了字段时，按候选路由名依次探测该源声明了哪个源端字段
          // 路由（同时兼容两套命名：searchByAuthor / authorSearch 等，方便社区源自由
          // 命名而无需改应用）。命中则走源端字段检索（服务端已按字段过滤，直接采用）；
          // 都未命中则回退通用 search，并在下方做客户端按字段收窄。
          final searchField = _searchField;
          final List<String> routeCandidates = searchField == null
              ? const <String>['search']
              : _routeKeysForField(searchField);
          String routeKey = 'search';
          bool usedFieldRoute = false;
          if (searchField != null) {
            for (final cand in routeCandidates) {
              if (source.routes.containsKey(cand)) {
                routeKey = cand;
                usedFieldRoute = cand != 'search';
                break;
              }
            }
          }
          // 直达模式：调用方已给真实页面地址，强制走该源的字段路由（如
          // authorSearch / tagSearch），并信任其返回结果、跳过客户端收窄。
          if (_extractedUrl != null && _extractedUrl!.isNotEmpty) {
            final fieldRouteCandidates = searchField != null
                ? _routeKeysForField(searchField)
                : const <String>['search'];
            for (final cand in fieldRouteCandidates) {
              if (source.routes.containsKey(cand)) {
                routeKey = cand;
                break;
              }
            }
            usedFieldRoute = true;
          }
          try {
            final items = await mediaService.fetchApiResults(
              source,
              routeKey,
              extractedUrl: _extractedUrl,
              renderedHtml: renderedHtml,
              vars: <String, String>{
                'keyword': trimmed,
                'page': '1',
              },
            );
            // 走了源端字段路由（如 authorSearch / tagSearch）时，服务端已按字段
            // 检索，直接采用返回结果；仅当回退到通用 search 时才在客户端按字段收窄，
            // 且收窄为空则回退原关键词结果（非破坏性），避免"检索无结果"的错觉。
            final List<MediaItem> effective;
            if (_searchField != null && !usedFieldRoute) {
              final filtered = items
                  .where((it) => it.matchesQuery(trimmed, field: _searchField))
                  .toList();
              effective = filtered.isEmpty ? items : filtered;
            } else {
              effective = items;
            }
            allResults.addAll(effective);
          } catch (e) {
            // 验证异常：跳验证后重试该源
            if (VerificationNavigator.isVerificationError(e)) {
              if (!mounted) return;
              final handled =
                  await VerificationNavigator.handleVerificationAndRetry(
                context,
                e,
                () async {
                  final retryItems = await mediaService.fetchApiResults(
                    source,
                    routeKey,
                    extractedUrl: _extractedUrl,
                    renderedHtml: renderedHtml,
                    vars: <String, String>{
                      'keyword': trimmed,
                      'page': '1',
                    },
                  );
                  final List<MediaItem> retryEffective;
                  if (_searchField != null && !usedFieldRoute) {
                    final retryFiltered = retryItems
                        .where((it) =>
                            it.matchesQuery(trimmed, field: _searchField))
                        .toList();
                    retryEffective =
                        retryFiltered.isEmpty ? retryItems : retryFiltered;
                  } else {
                    retryEffective = retryItems;
                  }
                  allResults.addAll(retryEffective);
                },
                verifyHandler: handleVerificationRequest,
                onExtracted: (url) => _extractedUrl = url,
                onRenderedHtml: (html) => renderedHtml = html,
              );
              if (!handled && mounted) {
                setState(() => _loading = false);
                return;
              }
            }
            // 单个源失败不影响其他源
          }
        }

        // 字段路由由源端完成匹配；回退 search 的源已在循环内做客户端字段收窄，
        // 此处不再二次过滤，避免把"源端已正确匹配"的结果误清空。

        if (mounted) {
          setState(() {
            _results = allResults;
            _loading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  /// 搜索字段 → 源端路由键映射。
  ///
  /// 源若声明了对应 `searchByXxx` 路由，搜索页/详情页就会直接调用它，
  /// 实现真正的源端按字段检索（而非仅客户端过滤）。未知字段回退通用 `search`。
  // 每个字段返回一组候选源端路由名（按优先级）。同时兼容两套命名习惯：
  // 规范名 searchByXxx 与社区常见的 xxxSearch，方便不同来源的源无需改应用即可命中。
  static List<String> _routeKeysForField(String field) {
    switch (field) {
      case 'author':
        return const <String>['searchByAuthor', 'authorSearch'];
      case 'tags':
        return const <String>['searchByTag', 'tagSearch'];
      case 'director':
        return const <String>['searchByDirector', 'directorSearch'];
      case 'actors':
        return const <String>['searchByActor', 'actorSearch'];
      case 'title':
        return const <String>['searchByWork', 'workSearch'];
      default:
        return const <String>['search'];
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // 布局切换已移入 header 区域（显眼分段按钮），AppBar 不再放图标。
    return ModuleSearchScreen(
      title: widget.title,
      searchController: _controller,
      onQueryChanged: _doSearch,
      hint: l10n.search,
      isGrid: _grid,
      onLayoutChanged: (v) {
        setState(() => _grid = v);
      },
      gridTooltip: l10n.gridView,
      listTooltip: l10n.listView,
      layoutButton: const LayoutPickerButton(),
      results: _buildResults(context, l10n),
      sourceType: widget.sourceType,
      header: _buildHeader(context, l10n),
    );
  }

  /// 搜索页头部：四行左对齐控件（与搜索框 padding 一致）。
  ///
  /// 行1：[ 网格 | 列表 ] 布局切换（替代原 AppBar 小图标，更显眼完整）
  /// 行2：[ 聚合全部源 | 单源 ] 搜索范围
  /// 行3：（仅单源）源选择条
  /// 行4：字段筛选胶囊(全部/标签/作者/导演/主演/作品)
  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    final sourceRepo = context.read<SourceRepository>();
    final sources = sourceRepo.byType(widget.sourceType);

    return Padding(
      // 与搜索框的 EdgeInsets.symmetric(horizontal: spaceLg) 完全对齐
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── 第1行：聚合 / 单源（布局切换已移至 AppBar，与书架一致）──
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<_SearchScope>(
              segments: <ButtonSegment<_SearchScope>>[
                ButtonSegment<_SearchScope>(
                  value: _SearchScope.aggregate,
                  label: Text(l10n.searchAggregate),
                ),
                ButtonSegment<_SearchScope>(
                  value: _SearchScope.single,
                  label: Text(l10n.searchSingle),
                ),
              ],
              selected: <_SearchScope>{_scope},
              onSelectionChanged: (Set<_SearchScope> sel) {
                setState(() => _scope = sel.first);
                _doSearch(_controller.text);
              },
              showSelectedIcon: false,
            ),
          ),

          // ── 第3行：（仅单源时）源选择条 ──
          if (_scope == _SearchScope.single) ...<Widget>[
            const SizedBox(height: AppTokens.spaceSm),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: sources.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppTokens.spaceXs),
                itemBuilder: (_, i) {
                  final s = sources[i];
                  final selected = _selectedSourceId == s.id;
                  return ChoiceChip(
                    label: Text(s.name),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _selectedSourceId =
                          selected ? null : s.id);
                      _doSearch(_controller.text);
                    },
                  );
                },
              ),
            ),
          ],

          // ── 第4行：字段筛选胶囊（按模块类型显示对应字段）──
          // 小说/漫画：标签 + 作者（无导演/主演概念）
          // 媒体（影视）：标签 + 导演 + 主演（无"作者"概念）
          const SizedBox(height: AppTokens.spaceSm),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _fieldEntries(l10n).length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: AppTokens.spaceXs),
              itemBuilder: (_, i) {
                final entry = _fieldEntries(l10n)[i];
                return _fieldPill(entry.$1, entry.$2);
              },
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
        ],
      ),
    );
  }

  Widget _fieldPill(String label, String? field) {
    final selected = _searchField == field;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _searchField = field);
        _doSearch(_controller.text);
      },
    );
  }

  /// 按模块类型返回字段筛选胶囊列表。
  ///
  /// - 小说/漫画：全部 / 标签 / 作者 / 作品（无导演/主演概念）
  /// - 媒体（影视）：全部 / 标签 / 导演 / 主演 / 作品（无"作者"概念）
  List<(String, String?)> _fieldEntries(AppLocalizations l10n) {
    // 基础项：全部 + 标签 + 作品
    final base = <(String, String?)>[
      (l10n.allLabel, null),
      (l10n.tagLabel, 'tags'),
    ];
    switch (widget.sourceType) {
      case SourceType.novelSource:
      case SourceType.mangaSource:
        return <(String, String?)>[
          ...base,
          (l10n.searchFieldAuthor, 'author'),
          (l10n.searchFieldWork, 'title'),
        ];
      case SourceType.animeSource:
        return <(String, String?)>[
          ...base,
          (l10n.searchFieldDirector, 'director'),
          (l10n.searchFieldActor, 'actors'),
          (l10n.searchFieldWork, 'title'),
        ];
    }
  }

  Widget _buildResults(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: AppLoadingIndicator());
    }

    if (_needSource) {
      return AppEmptyState(icon: Icons.source, message: l10n.searchSelectSource);
    }

    if (_results.isEmpty) {
      return AppEmptyState(icon: Icons.search, message: l10n.emptySearch);
    }

    if (_grid) {
      return _buildGrid(context);
    }
    return _buildList(context);
  }

  Widget _buildGrid(BuildContext context) {
    final layout = LayoutSettingsStore.instance.settings;
    final cross = layout.gridColumns;
    final spacing = layout.gridSpacing;
    final width = MediaQuery.of(context).size.width;
    final itemW =
        (width - AppTokens.spaceLg * 2 - spacing * (cross - 1)) / cross;

    // 文本区高度：标题(可多行) + 作者 + 进度条 + 来源 + 间距，避免裁切/溢出。
    // 网格间距/圆角/字号/标题行数/作者/进度均同步跟随全局布局设置。
    final double textH =
        (layout.showTitle ? layout.titleMaxLines * (layout.titleFontSize + 6) : 0.0) +
        (layout.showAuthor ? 18.0 : 0.0) +
        (layout.showProgress && layout.progressDisplay == ProgressDisplayMode.bar
            ? 9.0
            : 0.0) +
        14.0 + // 来源(meta) 通常存在
        12.0; // 间距

    return GridView.builder(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cross,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: itemW / (itemW / AppTokens.coverAspectRatio + textH),
      ),
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final item = _results[i];
        final source =
            context.read<SourceRepository>().getById(item.sourceId ?? '');
        final String progKey = '${item.id}#${layout.showProgress}';
        final future = _progressFutures.putIfAbsent(
          progKey,
          () => layout.showProgress
              ? _computeProgress(item)
              : Future<double?>.value(null),
        );
        return FutureBuilder<double?>(
          future: future,
          builder: (ctx, snap) => ContentCard(
            coverUrl: item.coverUrl,
            source: source,
            title: item.title,
            subtitle: item.author,
            meta: source?.name,
            progress: snap.data,
            width: itemW,
            heroTag: 'search-${item.id}',
            onTap: () => widget.onItemTap(item),
          ),
        );
      },
    );
  }

  Widget _buildList(BuildContext context) {
    final layout = LayoutSettingsStore.instance.settings;
    final isCompact = layout.listStyle == ListLayoutStyle.compact;
    return ListView.separated(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppTokens.spaceMd),
      itemBuilder: (_, i) {
        final item = _results[i];
        final source =
            context.read<SourceRepository>().getById(item.sourceId ?? '');
        return AppCard(
          onTap: () => widget.onItemTap(item),
          padding: EdgeInsets.zero,
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
              vertical: isCompact ? AppTokens.spaceXs : AppTokens.spaceSm,
            ),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(layout.coverRadius.toDouble()),
              child: SizedBox(
                width: isCompact ? 40 : 56,
                height: isCompact ? 56 : 78,
                child: AppCoverImage(
                  coverUrl: item.coverUrl,
                  source: source,
                  title: item.title,
                  width: isCompact ? 40 : 56,
                  height: isCompact ? 56 : 78,
                  heroTag: 'search-${item.id}-list',
                  radius: layout.coverRadius,
                ),
              ),
            ),
            title: layout.showTitle
                ? Text(
                    item.title,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontSize: layout.titleFontSize),
                    maxLines: layout.titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            subtitle: layout.showAuthor
                ? Text(
                    <String?>[
                      item.author,
                      source?.name,
                    ].where((s) => s != null && s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  )
                : null,
            trailing: layout.showProgress
                ? FutureBuilder<double?>(
                    future: _progressFutures.putIfAbsent(
                      '${item.id}#list',
                      () => _computeProgress(item),
                    ),
                    builder: (ctx, snap) {
                      final double? p = snap.data;
                      if (p == null || p <= 0) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        '${(p * 100).round()}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      );
                    },
                  )
                : const Icon(Icons.chevron_right),
            onTap: () => widget.onItemTap(item),
          ),
        );
      },
    );
  }

  /// 计算某内容的进度值（0.0..1.0），供列表/网格「显示进度」开关使用。
  ///
  /// 与 online_content_list_screen 逻辑一致：影视用已看集数比例，小说/漫画用
  /// 已读章节占比；未缓存总章数时以极小进度标记「已开始」。
  Future<double?> _computeProgress(MediaItem item) async {
    final SourceType? type = item.sourceType;
    if (type == SourceType.animeSource) {
      try {
        final watchedMgr = context.read<MediaWatchedManager>();
        final watched = watchedMgr.watchedCount(item.id);
        if (watched > 0 &&
            item.episodeCount != null &&
            item.episodeCount! > 0) {
          return (watched / item.episodeCount!).clamp(0.0, 1.0);
        }
      } on Object {/* 忽略 */}
    }
    if (type == SourceType.novelSource) {
      try {
        final p = await NovelProgressManager().get(item.id);
        if (p != null) {
          if (p.totalChapters != null && p.totalChapters! > 0) {
            return ((p.chapterIndex + 1) / p.totalChapters!)
                .clamp(0.0, 1.0);
          }
          if (p.chapterIndex > 0) return 0.02;
        }
      } on Object {/* 忽略 */}
    }
    if (type == SourceType.mangaSource) {
      try {
        final p = await ComicProgressManager().get(item.id);
        if (p != null) {
          if (p.totalChapters != null && p.totalChapters! > 0) {
            return ((p.chapterIndex + 1) / p.totalChapters!)
                .clamp(0.0, 1.0);
          }
          if (p.chapterIndex > 0) return 0.02;
        }
      } on Object {/* 忽略 */}
    }
    return null;
  }
}
