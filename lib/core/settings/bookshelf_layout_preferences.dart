/// 书架布局偏好模型（网格/列表 + 密度）。
///
/// 持久化到 SharedPreferences（key: `bookshelf_layout_v1`），
/// 复用 [PrefsBackend] 抽象以便测试注入。
library;

import 'dart:convert';

import '../comic/models/reader_preferences.dart';

/// 书架布局模式。
enum BookshelfLayoutMode { grid, list }

/// 网格密度。
enum GridDensity { compact, standard, comfortable }

/// 书架布局偏好。
class BookshelfLayoutPreferences {
  final BookshelfLayoutMode layoutMode;
  final GridDensity gridDensity;

  const BookshelfLayoutPreferences({
    this.layoutMode = BookshelfLayoutMode.grid,
    this.gridDensity = GridDensity.standard,
  });

  BookshelfLayoutPreferences copyWith({
    BookshelfLayoutMode? layoutMode,
    GridDensity? gridDensity,
  }) =>
      BookshelfLayoutPreferences(
        layoutMode: layoutMode ?? this.layoutMode,
        gridDensity: gridDensity ?? this.gridDensity,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'layoutMode': layoutMode.name,
        'gridDensity': gridDensity.name,
      };

  factory BookshelfLayoutPreferences.fromJson(Map<String, dynamic> json) {
    BookshelfLayoutMode mode = BookshelfLayoutMode.grid;
    if (json['layoutMode'] is String) {
      mode = BookshelfLayoutMode.values.firstWhere(
        (e) => e.name == json['layoutMode'],
        orElse: () => BookshelfLayoutMode.grid,
      );
    }
    GridDensity density = GridDensity.standard;
    if (json['gridDensity'] is String) {
      density = GridDensity.values.firstWhere(
        (e) => e.name == json['gridDensity'],
        orElse: () => GridDensity.standard,
      );
    }
    return BookshelfLayoutPreferences(
      layoutMode: mode,
      gridDensity: density,
    );
  }
}

/// 书架布局偏好持久化存储（key: `bookshelf_layout_v1`）。
class BookshelfLayoutPreferencesStore {
  static const String _key = 'bookshelf_layout_v1';

  final PrefsBackend _backend;

  BookshelfLayoutPreferencesStore({PrefsBackend? backend})
      : _backend = backend ?? const SharedPrefsBackend();

  Future<BookshelfLayoutPreferences> load() async {
    final raw = await _backend.get(_key);
    if (raw == null || raw.isEmpty) return const BookshelfLayoutPreferences();
    try {
      return BookshelfLayoutPreferences.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return const BookshelfLayoutPreferences();
    }
  }

  Future<void> save(BookshelfLayoutPreferences prefs) async {
    await _backend.set(_key, jsonEncode(prefs.toJson()));
  }
}
