/// Search suggestions shown when the search field is focused and empty.
///
/// Renders two vertically stacked sections: recent search history (chips,
/// clearable via a confirm dialog) and built-in hot search keywords
/// (chips). Tapping any chip invokes [onKeywordTap].
library;

import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../models/plugin_config.dart';
import '../search/hot_search_keywords.dart';
import '../search/search_history_store.dart';
import '../theme/app_tokens.dart';

/// A focus-triggered suggestions panel with history + hot keywords.
class SearchSuggestions extends StatefulWidget {
  final SourceType sourceType;
  final SearchHistoryStore historyStore;

  /// Called when the user taps a history or hot keyword chip.
  final ValueChanged<String> onKeywordTap;

  const SearchSuggestions({
    super.key,
    required this.sourceType,
    required this.historyStore,
    required this.onKeywordTap,
  });

  @override
  State<SearchSuggestions> createState() => _SearchSuggestionsState();
}

class _SearchSuggestionsState extends State<SearchSuggestions> {
  Future<List<String>>? _historyFuture;
  Future<List<String>>? _hotFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = widget.historyStore.load();
    _hotFuture = HotSearchKeywords.forModule(widget.sourceType);
  }

  Future<void> _confirmClear() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        content: Text(l10n.clearSearchHistoryConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.historyStore.clear();
      if (mounted) {
        setState(() {
          _historyFuture = widget.historyStore.load();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final TextStyle? titleStyle = theme.textTheme.titleSmall;
    final TextStyle? hintStyle = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLg,
        vertical: AppTokens.spaceMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // --- Search history section ---
          FutureBuilder<List<String>>(
            future: _historyFuture,
            builder: (BuildContext context, AsyncSnapshot<List<String>> snapshot) {
              final List<String> history = snapshot.data ?? const <String>[];
              final bool loading =
                  snapshot.connectionState != ConnectionState.done;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(l10n.searchHistoryTitle, style: titleStyle),
                      ),
                      if (history.isNotEmpty)
                        TextButton.icon(
                          onPressed: _confirmClear,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: Text(l10n.clearSearchHistory),
                        ),
                    ],
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (history.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTokens.spaceSm,
                      ),
                      child: Text(l10n.noSearchHistory, style: hintStyle),
                    )
                  else
                    _ChipWrap(
                      keywords: history,
                      onTap: widget.onKeywordTap,
                    ),
                ],
              );
            },
          ),
          const Divider(height: AppTokens.spaceLg * 2),
          // --- Hot search section ---
          Text(l10n.hotSearch, style: titleStyle),
          FutureBuilder<List<String>>(
            future: _hotFuture,
            builder:
                (BuildContext context, AsyncSnapshot<List<String>> snapshot) {
              final List<String> keywords =
                  snapshot.data ?? const <String>[];
              final bool loading =
                  snapshot.connectionState != ConnectionState.done;
              if (loading) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
                  child: SizedBox(
                    height: 24,
                    width: 24,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              if (keywords.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppTokens.spaceSm,
                  ),
                  child: Text(l10n.noHotSearch, style: hintStyle),
                );
              }
              return _ChipWrap(keywords: keywords, onTap: widget.onKeywordTap);
            },
          ),
        ],
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.keywords, required this.onTap});

  final List<String> keywords;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
        child: Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceSm,
          children: keywords
              .map(
                (String k) => ActionChip(
                  label: Text(k),
                  onPressed: () => onTap(k),
                ),
              )
              .toList(growable: false),
        ),
      );
}
