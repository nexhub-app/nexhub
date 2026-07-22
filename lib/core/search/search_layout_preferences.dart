/// 搜索布局偏好（文档 §10.2 SearchLayoutPreferences）。
///
/// 持久化网格/列表切换状态，按 [SourceType] 模块隔离。
/// key = 'search_layout_{sourceType}'（如 search_layout_animeSource）。
library;

import 'dart:convert';

import '../comic/models/reader_preferences.dart';
import '../models/plugin_config.dart';

class SearchLayoutPreferences {
  final bool isGrid;

  const SearchLayoutPreferences({this.isGrid = true});

  const SearchLayoutPreferences.defaults() : isGrid = true;

  SearchLayoutPreferences copyWith({bool? isGrid}) =>
      SearchLayoutPreferences(isGrid: isGrid ?? this.isGrid);

  Map<String, dynamic> toJson() => <String, dynamic>{'isGrid': isGrid};

  factory SearchLayoutPreferences.fromJson(Map<String, dynamic> json) =>
      SearchLayoutPreferences(
        isGrid: json['isGrid'] as bool? ?? true,
      );

  String toJsonString() => jsonEncode(toJson());

  static SearchLayoutPreferences fromJsonString(String raw) =>
      SearchLayoutPreferences.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
}

class SearchLayoutPreferencesStore {
  SearchLayoutPreferencesStore({
    PrefsBackend? backend,
    SourceType? sourceType,
  })  : _backend = backend ?? const SharedPrefsBackend(),
        // 全模块统一一份布局设置（用户选择）：忽略 sourceType，恒定全局 key，
        // 切一次网格/列表，小说/媒体/漫画三模块搜索页同步生效。
        _key = 'search_layout_settings';

  final PrefsBackend _backend;
  final String _key;

  Future<SearchLayoutPreferences> load() async {
    final raw = await _backend.get(_key);
    if (raw == null) return const SearchLayoutPreferences.defaults();
    try {
      return SearchLayoutPreferences.fromJsonString(raw);
    } catch (_) {
      return const SearchLayoutPreferences.defaults();
    }
  }

  Future<void> save(SearchLayoutPreferences prefs) async {
    await _backend.set(_key, prefs.toJsonString());
  }
}
