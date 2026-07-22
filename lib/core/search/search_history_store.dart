/// Search history persistence (per SourceType module isolation).
///
/// Stores recent search queries as a JSON-encoded List<String> via
/// [PrefsBackend] (backed by shared_preferences), keyed by
/// 'search_history_{sourceType.name}'. Dedupes, keeps newest on top,
/// capped at 15 entries.
library;

import 'dart:convert';

import '../comic/models/reader_preferences.dart';
import '../models/plugin_config.dart';

/// Per-module search history store.
///
/// Module isolation is achieved by deriving the storage key from
/// [SourceType], so anime / manga / novel histories do not leak across
/// modules.
class SearchHistoryStore {
  SearchHistoryStore(SourceType sourceType, {PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend(),
        moduleKey = 'search_history_${sourceType.name}';

  final PrefsBackend _backend;

  /// Full SharedPreferences key, e.g. 'search_history_animeSource'.
  final String moduleKey;

  /// Maximum number of retained entries (newest first).
  static const int maxEntries = 15;

  /// Loads history (newest first). Returns an empty list on missing or
  /// corrupt data.
  Future<List<String>> load() async {
    final String? raw = await _backend.get(moduleKey);
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } on Object {
      // Corrupt data: ignore and treat as empty.
    }
    return const <String>[];
  }

  /// Adds [query] to history: trims, dedupes (removes existing), prepends
  /// to the top, and caps the list at [maxEntries].
  Future<void> add(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final List<String> current = await load();
    final List<String> updated = <String>[
      trimmed,
      ...current.where((String e) => e != trimmed),
    ].take(maxEntries).toList(growable: false);
    await _backend.set(moduleKey, jsonEncode(updated));
  }

  /// Clears all history for this module.
  Future<void> clear() async {
    await _backend.set(moduleKey, jsonEncode(<String>[]));
  }
}
