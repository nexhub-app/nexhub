import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import '../models/plugin_config.dart';
import '../theme/app_tokens.dart';
import 'app_card.dart';
import 'app_cover_image.dart';
import 'detail_action_utils.dart';
import 'source_image.dart';

/// 详情页统一骨架：Hero 大图 SliverAppBar + 元信息 chips + 操作行 +
/// 可展开简介 + 进度卡 + 章节/剧集列表 + 相关推荐。
///
/// 各内容模块详情页复用，禁止重复造轮子。
///
/// M16.5 详情页全面增强：改为 [StatefulWidget]，新增 [SliverAppBar] +
/// [FlexibleSpaceBar] Hero 大图 + 渐变遮罩；简介改 [AppCard] 包裹可展开/收起；
/// [RefreshIndicator] 包裹；新增 [appBarActions] / [onRefresh] / [fallbackIcon]。
class ContentDetailShell extends StatefulWidget {
  final String? coverUrl;
  final String title;
  final List<Widget> infoChips;
  final List<Widget> actions;
  final String? description;
  final Widget chaptersList;
  final Widget? recommendations;
  final String? heroTag;

  /// 源配置（用于封面防盗链 headers 注入）。
  final PluginConfig? source;

  /// 最后更新时间。
  final DateTime? updatedAt;

  /// 连载状态文本（如"连载中"/"已完结"），非空时在标题下渲染带图标的状态徽标。
  final String? statusText;

  /// 来源名称（源插件的 source.name），非空时在标题下渲染"来源：xxx"。
  final String? sourceName;

  /// 原站详情页 URL。非空时自动在操作行渲染「在应用内浏览」与
  /// 「在浏览器打开」两个按钮（带文字的 [OutlinedButton.icon] 样式），
  /// 三详情页共用，无需各自实现。
  final String? detailUrl;

  /// 题材标签区。
  final List<Widget>? tags;

  /// 点击封面回调（弹出全屏大图查看器）。
  final VoidCallback? onCoverTap;

  /// 进度卡，渲染在标签区之后、章节列表之前。
  final Widget? progressSection;

  // ─── 新增参数（M16.5）───

  /// SliverAppBar 右侧操作按钮（收藏 / 下载 / 分享 / 刷新 / 删除等）。
  final List<Widget>? appBarActions;

  /// 下拉刷新回调（非 null 时包裹 [RefreshIndicator]）。
  final Future<void> Function()? onRefresh;

  /// 封面为空时 SliverAppBar 背景显示的占位图标。
  final IconData fallbackIcon;

  const ContentDetailShell({
    super.key,
    this.coverUrl,
    required this.title,
    this.infoChips = const <Widget>[],
    this.actions = const <Widget>[],
    this.description,
    required this.chaptersList,
    this.recommendations,
    this.heroTag,
    this.source,
    this.updatedAt,
    this.statusText,
    this.sourceName,
    this.detailUrl,
    this.tags,
    this.onCoverTap,
    this.progressSection,
    this.appBarActions,
    this.onRefresh,
    this.fallbackIcon = Icons.movie_outlined,
  });

  @override
  State<ContentDetailShell> createState() => _ContentDetailShellState();
}

class _ContentDetailShellState extends State<ContentDetailShell> {
  bool _descriptionExpanded = false;

  String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  /// 连载状态 → 图标映射。已完结类走 [Icons.check_circle]，连载中类走
  /// [Icons.autorenew]，其余（停更/暂停）走 [Icons.pause_circle_outline]。
  IconData _statusIcon(String status) {
    final s = status.toLowerCase();
    if (s.contains('完') ||
        s.contains('结') ||
        s.contains('complete') ||
        s.contains('finish') ||
        s.contains('end')) {
      return Icons.check_circle;
    }
    if (s.contains('连载') ||
        s.contains('更新') ||
        s.contains('ongoing') ||
        s.contains('serial') ||
        s.contains('publish')) {
      return Icons.autorenew;
    }
    if (s.contains('停') ||
        s.contains('暂') ||
        s.contains('pause') ||
        s.contains('hiatus')) {
      return Icons.pause_circle_outline;
    }
    return Icons.info_outline;
  }

  /// 连载状态 → 颜色映射。已完结用主色，连载中用绿色系（tertiary），
  /// 停更用警示色。
  Color _statusColor(ColorScheme scheme, String status) {
    final s = status.toLowerCase();
    if (s.contains('完') ||
        s.contains('结') ||
        s.contains('complete') ||
        s.contains('finish') ||
        s.contains('end')) {
      return scheme.primary;
    }
    if (s.contains('停') ||
        s.contains('暂') ||
        s.contains('pause') ||
        s.contains('hiatus')) {
      return scheme.error;
    }
    return scheme.tertiary;
  }

  /// 连载状态徽标：图标 + 文本，图标随状态切换。
  Widget _buildStatusBadge(
    ColorScheme scheme,
    TextTheme textTheme,
    String status,
  ) {
    final Color color = _statusColor(scheme, status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_statusIcon(status), size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            status,
            style: textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 操作行：页面自有按钮（续看 / 系列 / 等） + 详情页公用浏览按钮。
  ///
  /// 当 [detailUrl] 非空时自动追加「在应用内浏览」([Icons.travel_explore]) 与
  /// 「在浏览器打开」([Icons.open_in_new]) 两个带文字的 [OutlinedButton.icon]，
  /// 恢复用户习惯的样式，并下沉到骨架层供三详情页复用。
  List<Widget> _buildActionButtons(BuildContext context, AppLocalizations l10n) {
    final List<Widget> buttons = <Widget>[...widget.actions];
    final String? detailUrl = widget.detailUrl;
    if (detailUrl != null &&
        detailUrl.isNotEmpty &&
        !detailUrl.contains('{}')) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => openInAppBrowser(context, detailUrl),
          icon: const Icon(Icons.travel_explore),
          label: Text(l10n.openInAppBrowser),
        ),
      );
      buttons.add(
        OutlinedButton.icon(
          onPressed: () => openInExternalBrowser(context, detailUrl),
          icon: const Icon(Icons.open_in_new),
          label: Text(l10n.openInBrowser),
        ),
      );
    }
    if (buttons.isEmpty) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: AppTokens.spaceMd),
      Wrap(
        spacing: AppTokens.spaceSm,
        runSpacing: AppTokens.spaceSm,
        children: buttons,
      ),
    ];
  }

  /// SliverAppBar 背景全屏封面 + 渐变遮罩。
  Widget _buildHeroBackground(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget fallback = Container(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(widget.fallbackIcon,
            size: 64,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
      ),
    );

    Widget image;
    if (widget.coverUrl != null && widget.coverUrl!.isNotEmpty) {
      final bool isHttp = widget.coverUrl!.startsWith('http://') ||
          widget.coverUrl!.startsWith('https://');
      if (isHttp) {
        image = SourceImage(
          url: widget.coverUrl,
          source: widget.source,
          fit: BoxFit.cover,
          radius: 0,
          placeholder: fallback,
        );
      } else {
        // Local file
        image = Image.file(
          File(widget.coverUrl!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        );
      }
    } else {
      image = fallback;
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        image,
        // 渐变遮罩：顶部透明 → 底部接近 surface 色，确保标题文字可读
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                scheme.surface.withValues(alpha: 0.0),
                scheme.surface.withValues(alpha: 0.35),
                scheme.surface.withValues(alpha: 0.92),
              ],
              stops: const <double>[0.35, 0.65, 1.0],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;

    // 封面缩略图（信息行用）
    final Widget smallCover = AppCoverImage(
      coverUrl: widget.coverUrl,
      source: widget.source,
      title: widget.title,
      width: 110,
      height: 110 / AppTokens.coverAspectRatio,
      heroTag: widget.heroTag,
    );

    final scrollView = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        // ─── Hero SliverAppBar ───
        SliverAppBar(
          pinned: true,
          expandedHeight: 280,
          actions: widget.appBarActions,
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsetsDirectional.only(
              start: AppTokens.spaceMd,
              bottom: AppTokens.spaceMd,
            ),
            title: Text(
              widget.title,
              style: textTheme.titleLarge?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            background: _buildHeroBackground(context),
          ),
        ),

        // ─── 封面行（小封面 + 标题 + chips + 操作按钮）───
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (widget.onCoverTap != null)
                  GestureDetector(onTap: widget.onCoverTap, child: smallCover)
                else
                  smallCover,
                const SizedBox(width: AppTokens.spaceLg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.title,
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // 连载状态徽标（图标随状态切换）
                      if (widget.statusText != null &&
                          widget.statusText!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppTokens.spaceSm),
                        _buildStatusBadge(
                            scheme, textTheme, widget.statusText!),
                      ],
                      // 来源
                      if (widget.sourceName != null &&
                          widget.sourceName!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppTokens.spaceSm),
                        Row(
                          children: <Widget>[
                            Icon(Icons.source_outlined,
                                size: 14, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '${l10n.sourceLabel}: ${widget.sourceName}',
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppTokens.spaceMd),
                      if (widget.infoChips.isNotEmpty)
                        Wrap(
                          spacing: AppTokens.spaceSm,
                          runSpacing: AppTokens.spaceSm,
                          children: widget.infoChips,
                        ),
                      if (widget.updatedAt != null) ...<Widget>[
                        const SizedBox(height: AppTokens.spaceSm),
                        Text(
                          '${l10n.updatedAtLabel} ${_formatDateTime(widget.updatedAt!)}',
                          style: textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                      ..._buildActionButtons(context, l10n),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ─── 简介区（AppCard 包裹，可展开/收起）───
        if (widget.description != null && widget.description!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceLg),
              child: AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        widget.description!,
                        style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                        maxLines: _descriptionExpanded ? null : 4,
                        overflow: _descriptionExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => setState(
                            () => _descriptionExpanded =
                                !_descriptionExpanded,
                          ),
                          child: Text(
                            _descriptionExpanded
                                ? l10n.collapse
                                : l10n.expand,
                            style: textTheme.labelLarge?.copyWith(
                                  color: scheme.primary,
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ─── 标签区 ───
        if (widget.tags != null && widget.tags!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceLg,
                  vertical: AppTokens.spaceSm),
              child: Wrap(
                spacing: AppTokens.spaceSm,
                runSpacing: AppTokens.spaceSm,
                children: widget.tags!,
              ),
            ),
          ),

        // ─── 进度卡 ───
        if (widget.progressSection != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceLg,
                AppTokens.spaceSm,
                AppTokens.spaceLg,
                AppTokens.spaceMd,
              ),
              child: widget.progressSection!,
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: AppTokens.spaceMd)),

        // ─── 章节/剧集列表 ───
        SliverToBoxAdapter(child: widget.chaptersList),

        // ─── 相关推荐 ───
        if (widget.recommendations != null)
          SliverToBoxAdapter(child: widget.recommendations!),
      ],
    );

    // 下拉刷新
    if (widget.onRefresh != null) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh!,
        child: scrollView,
      );
    }
    return scrollView;
  }
}
