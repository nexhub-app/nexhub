import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';

import '../../../core/models/episode.dart';
import '../../../core/scraper/media_api_service.dart';
import '../../../core/models/plugin_config.dart';
import '../../../core/theme/app_tokens.dart';

/// 书内搜索结果项。
class InBookSearchResult {
  final int chapterIndex;
  final String chapterTitle;
  final String snippet;
  final int charIndex;

  const InBookSearchResult({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.snippet,
    required this.charIndex,
  });
}

/// 书内搜索模式。
enum InBookSearchScope {
  /// 仅当前章节。
  currentChapter,
  /// 全书。
  wholeBook,
}

/// 书内搜索底部抽屉。
///
/// 支持「全书 / 单章」ChoiceChip 切换，输入关键字后逐章拉取正文并匹配，
/// 结果列表点击跳转到对应章节。
Future<InBookSearchResult?> showNovelInBookSearchSheet({
  required BuildContext context,
  required List<Episode> chapters,
  required int currentChapterIndex,
  required MediaApiService service,
  required PluginConfig? source,
  required String novelId,
}) {
  return showModalBottomSheet<InBookSearchResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _InBookSearchSheet(
      chapters: chapters,
      currentChapterIndex: currentChapterIndex,
      service: service,
      source: source,
      novelId: novelId,
    ),
  );
}

class _InBookSearchSheet extends StatefulWidget {
  const _InBookSearchSheet({
    required this.chapters,
    required this.currentChapterIndex,
    required this.service,
    required this.source,
    required this.novelId,
  });

  final List<Episode> chapters;
  final int currentChapterIndex;
  final MediaApiService service;
  final PluginConfig? source;
  final String novelId;

  @override
  State<_InBookSearchSheet> createState() => _InBookSearchSheetState();
}

class _InBookSearchSheetState extends State<_InBookSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  InBookSearchScope _scope = InBookSearchScope.currentChapter;
  List<InBookSearchResult> _results = const <InBookSearchResult>[];
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty || widget.source == null) return;
    setState(() {
      _searching = true;
      _results = const <InBookSearchResult>[];
    });
    try {
      final results = <InBookSearchResult>[];
      final chapterIndices = _scope == InBookSearchScope.currentChapter
          ? <int>[widget.currentChapterIndex]
          : List<int>.generate(widget.chapters.length, (i) => i);
      for (final ci in chapterIndices) {
        if (ci >= widget.chapters.length) continue;
        final chapter = widget.chapters[ci];
        try {
          final content = await widget.service.fetchNovelContent(
            widget.source!,
            novelId: widget.novelId,
            chapterUrl: chapter.url,
          );
          final paragraphs = content;
          for (final para in paragraphs) {
            final idx = para.indexOf(keyword);
            if (idx >= 0) {
              final start = (idx - 20).clamp(0, para.length);
              final end = (idx + keyword.length + 20).clamp(0, para.length);
              results.add(InBookSearchResult(
                chapterIndex: ci,
                chapterTitle: chapter.title,
                snippet: '${start > 0 ? '...' : ''}${para.substring(start, end)}${end < para.length ? '...' : ''}',
                charIndex: idx,
              ));
            }
          }
        } on Object {
          // 跳过拉取失败的章节。
        }
      }
      if (mounted) setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: l10n.searchInBook,
                            prefixIcon: const Icon(Icons.search),
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _search(),
                        ),
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                      FilledButton(
                        onPressed: _searching ? null : _search,
                        child: Text(l10n.search),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  Wrap(
                    spacing: AppTokens.spaceSm,
                    children: <Widget>[
                      ChoiceChip(
                        label: Text(l10n.currentChapter),
                        selected:
                            _scope == InBookSearchScope.currentChapter,
                        onSelected: (_) => setState(() => _scope =
                            InBookSearchScope.currentChapter),
                      ),
                      ChoiceChip(
                        label: Text(l10n.wholeBook),
                        selected: _scope == InBookSearchScope.wholeBook,
                        onSelected: (_) => setState(() =>
                            _scope = InBookSearchScope.wholeBook),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(child: Text(l10n.noSearchResults))
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, indent: AppTokens.spaceMd),
                          itemBuilder: (_, i) {
                            final r = _results[i];
                            return ListTile(
                              title: Text(
                                '${l10n.chapterN(r.chapterIndex + 1)} · ${r.chapterTitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                r.snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.of(context).pop(r),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
