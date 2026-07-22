/// Built-in sample hot search keywords per module.
///
/// Keyword data lives in `assets/builtin/hot_search_keywords.json` so that
/// no CJK literals are embedded in Dart source. Replace with a remote feed
/// later without changing call sites.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/plugin_config.dart';

/// Hot keyword lookup grouped by [SourceType], loaded from a JSON asset.
class HotSearchKeywords {
  const HotSearchKeywords._();

  static const String _assetPath = 'assets/builtin/hot_search_keywords.json';

  static Map<String, List<String>>? _cache;

  /// Returns the hot keyword list for [type] (empty if unknown).
  ///
  /// The asset is loaded once and cached for subsequent calls.
  static Future<List<String>> forModule(SourceType type) async {
    final Map<String, List<String>>? cache = _cache;
    if (cache == null) {
      final String json = await rootBundle.loadString(_assetPath);
      final Map<String, dynamic> data =
          jsonDecode(json) as Map<String, dynamic>;
      _cache = data.map(
        (String k, dynamic v) =>
            MapEntry<String, List<String>>(k, List<String>.from(v as List)),
      );
    }
    return _cache![type.name] ?? const <String>[];
  }
}
