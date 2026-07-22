/// Tests for [HistoryEntry] field passthrough to [MediaItem] and JSON
/// backward compatibility (F3 defect 3: history gray screen root cause).
///
/// Verifies that `detailUrl` / `coverUrl` / `sourceId` survive the
/// `HistoryEntry -> MediaItem` conversion so [ContentDetailScreen] can
/// open the detail page without re-fetching, and that old persisted JSON
/// (missing the newer fields) deserializes without throwing.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:nexhub/core/history/history_manager.dart';
import 'package:nexhub/core/models/media_item.dart';
import 'package:nexhub/core/models/plugin_config.dart';

void main() {
  group('HistoryEntry -> MediaItem field passthrough', () {
    test('toMediaItem preserves detailUrl, coverUrl and sourceId', () {
      const entry = HistoryEntry(
        id: 'anime-1',
        title: 'Test Anime',
        coverUrl: 'https://example.com/cover.jpg',
        sourceId: 'src-1',
        sourceType: SourceType.animeSource,
        detailUrl: 'https://example.com/detail/anime-1',
        viewedAt: 1000,
      );
      final item = entry.toMediaItem();

      expect(item.id, 'anime-1');
      expect(item.title, 'Test Anime');
      expect(item.detailUrl, 'https://example.com/detail/anime-1');
      expect(item.coverUrl, 'https://example.com/cover.jpg');
      expect(item.sourceId, 'src-1');
      expect(item.sourceType, SourceType.animeSource);
    });

    test('toMediaItem preserves category as tags and status', () {
      const entry = HistoryEntry(
        id: 'novel-1',
        title: 'Test Novel',
        sourceType: SourceType.novelSource,
        viewedAt: 2000,
        category: 'Fantasy',
        status: 'Ongoing',
      );
      final item = entry.toMediaItem();

      expect(item.tags, <String>['Fantasy']);
      expect(item.status, 'Ongoing');
    });

    test('toMediaItem with null optional fields yields nulls', () {
      const entry = HistoryEntry(
        id: 'manga-1',
        title: 'Test Manga',
        sourceType: SourceType.mangaSource,
        viewedAt: 3000,
      );
      final item = entry.toMediaItem();

      expect(item.detailUrl, isNull);
      expect(item.coverUrl, isNull);
      expect(item.sourceId, isNull);
      expect(item.tags, isNull);
      expect(item.status, isNull);
    });

    test('fromMediaItem then toMediaItem round-trips core fields', () {
      const original = MediaItem(
        id: 'anime-2',
        title: 'Round Trip',
        coverUrl: 'https://example.com/c.jpg',
        sourceId: 'src-2',
        sourceType: SourceType.animeSource,
        detailUrl: 'https://example.com/d/anime-2',
        tags: <String>['Action'],
        status: 'Completed',
      );
      final entry = HistoryEntry.fromMediaItem(original, lastChapter: 'EP1');
      final back = entry.toMediaItem();

      expect(back.id, original.id);
      expect(back.title, original.title);
      expect(back.detailUrl, original.detailUrl);
      expect(back.coverUrl, original.coverUrl);
      expect(back.sourceId, original.sourceId);
      expect(back.sourceType, original.sourceType);
      expect(back.status, original.status);
    });
  });

  group('HistoryEntry.fromJson backward compat', () {
    test('old JSON without detailUrl/coverUrl yields null fields', () {
      final entry = HistoryEntry.fromJson(const <String, dynamic>{
        'id': 'old-1',
        'title': 'Old Entry',
        'sourceType': 'animeSource',
        'sourceId': 'src-old',
        'viewedAt': 5000,
      });

      expect(entry.id, 'old-1');
      expect(entry.title, 'Old Entry');
      expect(entry.sourceType, SourceType.animeSource);
      expect(entry.sourceId, 'src-old');
      expect(entry.detailUrl, isNull);
      expect(entry.coverUrl, isNull);
      expect(entry.viewedAt, 5000);
    });

    test('old JSON without sourceId yields null sourceId', () {
      final entry = HistoryEntry.fromJson(const <String, dynamic>{
        'id': 'old-2',
        'title': 'No Source',
        'sourceType': 'mangaSource',
        'viewedAt': 6000,
      });

      expect(entry.sourceId, isNull);
      expect(entry.detailUrl, isNull);
      expect(entry.coverUrl, isNull);
    });

    test('missing sourceType falls back to animeSource', () {
      final entry = HistoryEntry.fromJson(const <String, dynamic>{
        'id': 'old-3',
        'title': 'No Type',
        'viewedAt': 7000,
      });

      expect(entry.sourceType, SourceType.animeSource);
    });

    test('does not throw on minimal JSON', () {
      expect(
        () => HistoryEntry.fromJson(const <String, dynamic>{}),
        returnsNormally,
      );
    });
  });

  group('HistoryEntry.toJson round-trip', () {
    test('all fields survive serialize then deserialize', () {
      const original = HistoryEntry(
        id: 'rt-1',
        title: 'Round Trip Full',
        coverUrl: 'https://example.com/cover.png',
        sourceId: 'src-rt',
        sourceType: SourceType.novelSource,
        detailUrl: 'https://example.com/detail/rt-1',
        viewedAt: 9000,
        lastChapter: 'Chapter 5',
        category: 'Sci-Fi',
        status: 'Ongoing',
      );
      final json = original.toJson();
      final restored = HistoryEntry.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.coverUrl, original.coverUrl);
      expect(restored.sourceId, original.sourceId);
      expect(restored.sourceType, original.sourceType);
      expect(restored.detailUrl, original.detailUrl);
      expect(restored.viewedAt, original.viewedAt);
      expect(restored.lastChapter, original.lastChapter);
      expect(restored.category, original.category);
      expect(restored.status, original.status);
    });

    test('toJson includes detailUrl and coverUrl keys', () {
      const entry = HistoryEntry(
        id: 'keys-1',
        title: 'Keys',
        coverUrl: 'https://example.com/k.jpg',
        sourceId: 'src-k',
        sourceType: SourceType.animeSource,
        detailUrl: 'https://example.com/d/k',
        viewedAt: 10000,
      );
      final json = entry.toJson();

      expect(json.containsKey('detailUrl'), isTrue);
      expect(json.containsKey('coverUrl'), isTrue);
      expect(json['detailUrl'], 'https://example.com/d/k');
      expect(json['coverUrl'], 'https://example.com/k.jpg');
    });

    test('null optional fields survive round-trip as null', () {
      const original = HistoryEntry(
        id: 'nulls-1',
        title: 'Nulls',
        sourceType: SourceType.mangaSource,
        viewedAt: 11000,
      );
      final restored = HistoryEntry.fromJson(original.toJson());

      expect(restored.detailUrl, isNull);
      expect(restored.coverUrl, isNull);
      expect(restored.sourceId, isNull);
      expect(restored.lastChapter, isNull);
      expect(restored.category, isNull);
      expect(restored.status, isNull);
    });
  });
}
