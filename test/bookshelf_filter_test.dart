/// Tests for [BookshelfFilter] value object and data model field expansion
/// (P5.1 书架筛选实装 — 方案乙：全段筛选).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:nexhub/core/favorites/favorites_manager.dart';
import 'package:nexhub/core/history/history_manager.dart';
import 'package:nexhub/core/models/bookshelf_filter.dart';
import 'package:nexhub/core/models/media_item.dart';
import 'package:nexhub/core/models/plugin_config.dart';

void main() {
  group('BookshelfFilter', () {
    test('default constructor yields recent sort with no filters', () {
      const filter = BookshelfFilter();
      expect(filter.sort, BookshelfSort.recent);
      expect(filter.status, isNull);
      expect(filter.category, isNull);
      expect(filter.progress, isNull);
      expect(filter.isDefault, isTrue);
    });

    test('isDefault false when sort is title', () {
      const filter = BookshelfFilter(sort: BookshelfSort.title);
      expect(filter.isDefault, isFalse);
    });

    test('isDefault false when status set', () {
      const filter = BookshelfFilter(status: '连载中');
      expect(filter.isDefault, isFalse);
    });

    test('isDefault false when category set', () {
      const filter = BookshelfFilter(category: '动画');
      expect(filter.isDefault, isFalse);
    });

    test('isDefault false when progress set', () {
      const filter =
          BookshelfFilter(progress: BookshelfProgress.reading);
      expect(filter.isDefault, isFalse);
    });

    test('copyWith sort changes sort only', () {
      const original = BookshelfFilter(
          status: '连载中', category: '动画');
      final updated = original.copyWith(sort: BookshelfSort.title);
      expect(updated.sort, BookshelfSort.title);
      expect(updated.status, '连载中');
      expect(updated.category, '动画');
    });

    test('copyWith status null clears status', () {
      const original = BookshelfFilter(status: '连载中');
      final updated = original.copyWith(status: null);
      expect(updated.status, isNull);
      expect(updated.sort, BookshelfSort.recent);
    });

    test('copyWith category null clears category', () {
      const original = BookshelfFilter(category: '动画');
      final updated = original.copyWith(category: null);
      expect(updated.category, isNull);
    });

    test('copyWith progress null clears progress', () {
      const original =
          BookshelfFilter(progress: BookshelfProgress.reading);
      final updated = original.copyWith(progress: null);
      expect(updated.progress, isNull);
    });

    test('copyWith with no args returns equivalent copy', () {
      const original = BookshelfFilter(
        sort: BookshelfSort.title,
        status: '已完结',
        category: '漫画',
        progress: BookshelfProgress.notStarted,
      );
      final copy = original.copyWith();
      expect(copy, original);
    });

    test('reset returns default filter', () {
      const original = BookshelfFilter(
        sort: BookshelfSort.title,
        status: '已完结',
        category: '漫画',
        progress: BookshelfProgress.notStarted,
      );
      final reset = original.reset();
      expect(reset.isDefault, isTrue);
      expect(reset.sort, BookshelfSort.recent);
    });

    test('equality holds for same values', () {
      const a = BookshelfFilter(
        sort: BookshelfSort.title,
        status: '连载中',
        category: '动画',
      );
      const b = BookshelfFilter(
        sort: BookshelfSort.title,
        status: '连载中',
        category: '动画',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('equality fails for different values', () {
      const a = BookshelfFilter(status: '连载中');
      const b = BookshelfFilter(status: '已完结');
      expect(a == b, isFalse);
    });
  });

  group('FavoriteEntry category/status expansion', () {
    test('fromMediaItem populates category from first tag', () {
      final item = MediaItem(
        id: '1',
        title: 'Test',
        sourceType: SourceType.animeSource,
        tags: const <String>['动画', '日常'],
        status: '连载中',
      );
      final entry = FavoriteEntry.fromMediaItem(item);
      expect(entry.category, '动画');
      expect(entry.status, '连载中');
    });

    test('fromMediaItem with empty tags yields null category', () {
      final item = MediaItem(
        id: '1',
        title: 'Test',
        sourceType: SourceType.animeSource,
        tags: const <String>[],
      );
      final entry = FavoriteEntry.fromMediaItem(item);
      expect(entry.category, isNull);
      expect(entry.status, isNull);
    });

    test('fromMediaItem with null tags yields null category', () {
      final item = MediaItem(
        id: '1',
        title: 'Test',
        sourceType: SourceType.animeSource,
      );
      final entry = FavoriteEntry.fromMediaItem(item);
      expect(entry.category, isNull);
    });

    test('toJson includes category and status', () {
      const entry = FavoriteEntry(
        id: '1',
        title: 'Test',
        sourceType: SourceType.animeSource,
        favoritedAt: 1000,
        category: '动画',
        status: '连载中',
      );
      final json = entry.toJson();
      expect(json['category'], '动画');
      expect(json['status'], '连载中');
    });

    test('fromJson reads category and status', () {
      final entry = FavoriteEntry.fromJson(const <String, dynamic>{
        'id': '1',
        'title': 'Test',
        'sourceType': 'anime',
        'favoritedAt': 1000,
        'category': '漫画',
        'status': '已完结',
      });
      expect(entry.category, '漫画');
      expect(entry.status, '已完结');
    });

    test('fromJson backward compat: missing category/status yield null', () {
      final entry = FavoriteEntry.fromJson(const <String, dynamic>{
        'id': '1',
        'title': 'Test',
        'sourceType': 'anime',
        'favoritedAt': 1000,
      });
      expect(entry.category, isNull);
      expect(entry.status, isNull);
    });

    test('toJson/fromJson round-trip preserves new fields', () {
      const original = FavoriteEntry(
        id: '1',
        title: 'Test',
        sourceType: SourceType.animeSource,
        favoritedAt: 1000,
        category: '动画',
        status: '连载中',
      );
      final roundTrip = FavoriteEntry.fromJson(original.toJson());
      expect(roundTrip.category, original.category);
      expect(roundTrip.status, original.status);
      expect(roundTrip.id, original.id);
    });

    test('toMediaItem carries category as tags and status', () {
      const entry = FavoriteEntry(
        id: '1',
        title: 'Test',
        sourceType: SourceType.animeSource,
        favoritedAt: 1000,
        category: '动画',
        status: '连载中',
      );
      final item = entry.toMediaItem();
      expect(item.tags, <String>['动画']);
      expect(item.status, '连载中');
    });
  });

  group('HistoryEntry category/status expansion', () {
    test('fromMediaItem populates category from first tag', () {
      final item = MediaItem(
        id: '1',
        title: 'Novel',
        sourceType: SourceType.novelSource,
        tags: const <String>['玄幻'],
        status: '已完结',
      );
      final entry = HistoryEntry.fromMediaItem(item, lastChapter: '第1章');
      expect(entry.category, '玄幻');
      expect(entry.status, '已完结');
      expect(entry.lastChapter, '第1章');
    });

    test('toJson includes category and status', () {
      const entry = HistoryEntry(
        id: '1',
        title: 'Test',
        sourceType: SourceType.novelSource,
        viewedAt: 2000,
        category: '玄幻',
        status: '连载中',
      );
      final json = entry.toJson();
      expect(json['category'], '玄幻');
      expect(json['status'], '连载中');
    });

    test('fromJson reads category and status', () {
      final entry = HistoryEntry.fromJson(const <String, dynamic>{
        'id': '1',
        'title': 'Test',
        'sourceType': 'novel',
        'viewedAt': 2000,
        'category': '都市',
        'status': '已完结',
      });
      expect(entry.category, '都市');
      expect(entry.status, '已完结');
    });

    test('fromJson backward compat: missing category/status yield null', () {
      final entry = HistoryEntry.fromJson(const <String, dynamic>{
        'id': '1',
        'title': 'Test',
        'sourceType': 'novel',
        'viewedAt': 2000,
      });
      expect(entry.category, isNull);
      expect(entry.status, isNull);
    });

    test('toJson/fromJson round-trip preserves new fields', () {
      const original = HistoryEntry(
        id: '1',
        title: 'Test',
        sourceType: SourceType.novelSource,
        viewedAt: 2000,
        category: '玄幻',
        status: '连载中',
        lastChapter: '第5章',
      );
      final roundTrip = HistoryEntry.fromJson(original.toJson());
      expect(roundTrip.category, original.category);
      expect(roundTrip.status, original.status);
      expect(roundTrip.lastChapter, original.lastChapter);
    });
  });
}
