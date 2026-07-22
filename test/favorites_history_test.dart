import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/comic/models/reader_preferences.dart';
import 'package:nexhub/core/favorites/favorites_manager.dart';
import 'package:nexhub/core/history/history_manager.dart';
import 'package:nexhub/core/models/media_item.dart';
import 'package:nexhub/core/models/plugin_config.dart';

void main() {
  group('FavoritesManager', () {
    late InMemoryBackend backend;
    late FavoritesManager manager;

    setUp(() {
      backend = InMemoryBackend();
      manager = FavoritesManager(backend: backend);
    });

    test('toggleFavorite adds and removes', () async {
      const item = MediaItem(
        id: 'novel_1',
        title: 'Test Novel',
        sourceType: SourceType.novelSource,
        author: 'Author',
      );

      expect(manager.isFavorite('novel_1', SourceType.novelSource), false);
      expect(manager.favoritesFor(SourceType.novelSource), isEmpty);

      await manager.toggleFavorite(item);
      expect(manager.isFavorite('novel_1', SourceType.novelSource), true);
      expect(manager.favoritesFor(SourceType.novelSource).length, 1);

      await manager.toggleFavorite(item);
      expect(manager.isFavorite('novel_1', SourceType.novelSource), false);
      expect(manager.favoritesFor(SourceType.novelSource), isEmpty);
    });

    test('favorites are isolated by SourceType', () async {
      await manager.toggleFavorite(const MediaItem(
        id: 'novel_1',
        title: 'Novel',
        sourceType: SourceType.novelSource,
      ));
      await manager.toggleFavorite(const MediaItem(
        id: 'comic_1',
        title: 'Comic',
        sourceType: SourceType.mangaSource,
      ));

      expect(manager.favoritesFor(SourceType.novelSource).length, 1);
      expect(manager.favoritesFor(SourceType.mangaSource).length, 1);
      expect(manager.favoritesFor(SourceType.animeSource), isEmpty);
    });

    test('persistence survives re-init', () async {
      await manager.toggleFavorite(const MediaItem(
        id: 'novel_1',
        title: 'Novel',
        sourceType: SourceType.novelSource,
      ));

      final manager2 = FavoritesManager(backend: backend);
      await manager2.init();
      expect(manager2.favoritesFor(SourceType.novelSource).length, 1);
      expect(manager2.isFavorite('novel_1', SourceType.novelSource), true);
    });

    test('removeFavorite removes by id', () async {
      await manager.toggleFavorite(const MediaItem(
        id: 'novel_1',
        title: 'Novel',
        sourceType: SourceType.novelSource,
      ));
      await manager.removeFavorite('novel_1', SourceType.novelSource);
      expect(manager.favoritesFor(SourceType.novelSource), isEmpty);
    });
  });

  group('HistoryManager', () {
    late InMemoryBackend backend;
    late HistoryManager manager;

    setUp(() {
      backend = InMemoryBackend();
      manager = HistoryManager(backend: backend, maxPerModule: 3);
    });

    test('addHistory adds entry', () async {
      await manager.addHistory(const MediaItem(
        id: 'novel_1',
        title: 'Novel',
        sourceType: SourceType.novelSource,
      ));

      final history = manager.historyFor(SourceType.novelSource);
      expect(history.length, 1);
      expect(history.first.id, 'novel_1');
    });

    test('history is deduplicated by id', () async {
      await manager.addHistory(const MediaItem(
        id: 'novel_1',
        title: 'Novel',
        sourceType: SourceType.novelSource,
      ));
      await manager.addHistory(const MediaItem(
        id: 'novel_1',
        title: 'Novel Updated',
        sourceType: SourceType.novelSource,
      ));

      final history = manager.historyFor(SourceType.novelSource);
      expect(history.length, 1);
      expect(history.first.title, 'Novel Updated');
    });

    test('maxPerModule evicts oldest', () async {
      for (var i = 0; i < 5; i++) {
        await manager.addHistory(MediaItem(
          id: 'novel_$i',
          title: 'Novel $i',
          sourceType: SourceType.novelSource,
        ));
      }

      final history = manager.historyFor(SourceType.novelSource);
      expect(history.length, 3); // maxPerModule = 3
    });

    test('clearHistory clears by module', () async {
      await manager.addHistory(const MediaItem(
        id: 'novel_1',
        title: 'Novel',
        sourceType: SourceType.novelSource,
      ));
      await manager.addHistory(const MediaItem(
        id: 'comic_1',
        title: 'Comic',
        sourceType: SourceType.mangaSource,
      ));

      await manager.clearHistory(SourceType.novelSource);
      expect(manager.historyFor(SourceType.novelSource), isEmpty);
      expect(manager.historyFor(SourceType.mangaSource).length, 1);
    });

    test('persistence survives re-init', () async {
      await manager.addHistory(const MediaItem(
        id: 'novel_1',
        title: 'Novel',
        sourceType: SourceType.novelSource,
        author: 'Author',
      ));

      final manager2 = HistoryManager(backend: backend);
      await manager2.init();
      expect(manager2.historyFor(SourceType.novelSource).length, 1);
    });

    test('history is isolated by SourceType', () async {
      await manager.addHistory(const MediaItem(
        id: 'novel_1',
        title: 'Novel',
        sourceType: SourceType.novelSource,
      ));
      await manager.addHistory(const MediaItem(
        id: 'comic_1',
        title: 'Comic',
        sourceType: SourceType.mangaSource,
      ));

      expect(manager.historyFor(SourceType.novelSource).length, 1);
      expect(manager.historyFor(SourceType.mangaSource).length, 1);
      expect(manager.historyFor(SourceType.animeSource), isEmpty);
    });

    test('explicit sourceType overrides null item.sourceType (no mixing)',
        () async {
      // 模拟脚本解析器等漏设 sourceType 的 item（item.sourceType == null）。
      const nullTypeItem = MediaItem(id: 'x_1', title: 'X');

      // 小说详情页强制传入 novelSource —— 不应被静默回退到 animeSource。
      await manager.addHistory(nullTypeItem,
          sourceType: SourceType.novelSource);

      expect(manager.historyFor(SourceType.novelSource).length, 1);
      expect(manager.historyFor(SourceType.animeSource), isEmpty);
      expect(
        manager.historyFor(SourceType.novelSource).first.sourceType,
        SourceType.novelSource,
      );

      // 动漫详情页强制传入 animeSource。
      await manager.addHistory(nullTypeItem,
          sourceType: SourceType.animeSource);
      expect(manager.historyFor(SourceType.animeSource).length, 1);
    });
  });
}
