import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import '../models/plugin_config.dart';
import '../search/search_history_store.dart';
import '../theme/app_tokens.dart';
import 'app_icon_button.dart';
import 'search_suggestions.dart';
import 'layout_picker_button.dart';

/// 搜索布局切换（网格 / 列表）。
class SearchLayoutToggle extends StatelessWidget {
  final bool isGrid;
  final ValueChanged<bool> onChanged;
  final String gridTooltip; // 来自 l10n
  final String listTooltip; // 来自 l10n
  const SearchLayoutToggle({
    super.key,
    required this.isGrid,
    required this.onChanged,
    required this.gridTooltip,
    required this.listTooltip,
  });

  @override
  Widget build(BuildContext context) => AppIconButton(
        icon: isGrid ? Icons.grid_view : Icons.view_list,
        tooltip: isGrid ? gridTooltip : listTooltip,
        onPressed: () => onChanged(!isGrid),
      );
}

/// 模块搜索页骨架（各内容模块共用的搜索 + 布局切换 + 结果区）。
///
/// 当搜索框聚焦且查询为空时，显示搜索历史与热门搜索建议面板；
/// 否则显示外部传入的 [results]。回车提交时记录搜索历史。
class ModuleSearchScreen extends StatefulWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final String hint; // 来自 l10n
  final bool isGrid;
  final ValueChanged<bool> onLayoutChanged;
  final Widget results;
  final String? title; // 来自 l10n
  final String gridTooltip; // 来自 l10n
  final String listTooltip; // 来自 l10n
  final String? leadingTooltip; // 来自 l10n
  final VoidCallback? onLeading;

  /// Module type used to isolate search history and hot keywords.
  final SourceType sourceType;

  /// 搜索框与结果区之间的自定义头部（如聚合/单源切换、源选择条、字段筛选胶囊）。
  final Widget? header;

  /// AppBar 右侧布局按钮（如与书架一致的 [LayoutPickerButton]）。
  /// 传入时优先于内置的 [SearchLayoutToggle]，保证各入口布局按钮一致。
  final Widget? layoutButton;

  const ModuleSearchScreen({
    super.key,
    required this.searchController,
    required this.onQueryChanged,
    required this.hint,
    required this.isGrid,
    required this.onLayoutChanged,
    required this.results,
    this.title,
    required this.gridTooltip,
    required this.listTooltip,
    this.leadingTooltip,
    this.onLeading,
    required this.sourceType,
    this.header,
    this.layoutButton,
  });

  @override
  State<ModuleSearchScreen> createState() => _ModuleSearchScreenState();
}

class _ModuleSearchScreenState extends State<ModuleSearchScreen> {
  late final FocusNode _focusNode;
  late final SearchHistoryStore _historyStore;

  @override
  void initState() {
    super.initState();
    _historyStore = SearchHistoryStore(widget.sourceType);
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
    widget.searchController.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_handleTextChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  void _handleTextChanged() {
    // Rebuild to refresh the clear-suffix visibility and suggestions toggle.
    if (mounted) setState(() {});
  }

  bool get _showSuggestions =>
      _focusNode.hasFocus && widget.searchController.text.isEmpty;

  void _onSubmitted(String query) {
    final String trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      // Record only on submit (enter key), per spec.
      _historyStore.add(trimmed);
    }
    widget.onQueryChanged(query);
  }

  void _onKeywordTap(String keyword) {
    widget.searchController.text = keyword;
    widget.onQueryChanged(keyword);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: AppIconButton(
          icon: Icons.arrow_back,
          tooltip: widget.leadingTooltip ?? l10n.back,
          onPressed: widget.onLeading ?? () => Navigator.maybePop(context),
        ),
        title: widget.title != null ? Text(widget.title!) : null,
        actions: <Widget>[
          // 优先使用外部传入的布局按钮（如与书架一致的 LayoutPickerButton）；
          // 否则在无 header 时回退到内置的网格/列表小图标切换。
          if (widget.layoutButton != null)
            widget.layoutButton!
          else if (widget.header == null)
            SearchLayoutToggle(
              isGrid: widget.isGrid,
              onChanged: widget.onLayoutChanged,
              gridTooltip: widget.gridTooltip,
              listTooltip: widget.listTooltip,
            ),
          const SizedBox(width: AppTokens.spaceSm),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 搜索栏放在 body 顶部，避免 AppBar.bottom 导致的视觉异常
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceLg,
              vertical: AppTokens.spaceSm,
            ),
            child: TextField(
              controller: widget.searchController,
              focusNode: _focusNode,
              autofocus: widget.searchController.text.isEmpty,
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: widget.searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          widget.searchController.clear();
                          widget.onQueryChanged('');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                filled: true,
              ),
              onChanged: widget.onQueryChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: _onSubmitted,
            ),
          ),
          if (widget.header != null) widget.header!,
          Expanded(
            child: _showSuggestions
                ? SearchSuggestions(
                    sourceType: widget.sourceType,
                    historyStore: _historyStore,
                    onKeywordTap: _onKeywordTap,
                  )
                : widget.results,
          ),
        ],
      ),
    );
  }
}
