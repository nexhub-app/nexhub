import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/comic/models/reader_preferences.dart';
import 'package:nexhub/core/download/download_file_system.dart';
import 'package:nexhub/core/download/download_format_preferences.dart';
import 'package:nexhub/core/download/download_manager.dart';
import 'package:nexhub/core/download/download_storage.dart';
import 'package:nexhub/core/download/download_task.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/resolver/resolver_registry.dart';
import 'package:nexhub/core/scraper/media_api_service.dart';
import 'package:nexhub/core/services/source_repository.dart';

void main() {
  group('DownloadTask', () {
    test('JSON round-trip preserves all fields', () {
      const task = DownloadTask(
        id: 'test_001',
        title: 'Test Comic',
        sourceType: SourceType.mangaSource,
        sourceId: 'src1',
        contentId: 'comic123',
        format: DownloadFormat.cbz,
        coverUrl: 'https://example.com/cover.jpg',
        chapterTitles: <String>['Ch1', 'Ch2'],
        totalChapters: 10,
        downloadedChapters: 5,
        status: DownloadStatus.downloading,
        createdAt: 1700000000000,
      );

      final json = task.toJsonString();
      final restored = DownloadTask.fromJsonString(json);

      expect(restored.id, task.id);
      expect(restored.title, task.title);
      expect(restored.sourceType, task.sourceType);
      expect(restored.contentId, task.contentId);
      expect(restored.format, task.format);
      expect(restored.totalChapters, task.totalChapters);
      expect(restored.downloadedChapters, task.downloadedChapters);
      expect(restored.status, task.status);
      expect(restored.chapterTitles, task.chapterTitles);
    });

    test('progress calculates correctly', () {
      const task = DownloadTask(
        id: 't',
        title: 'T',
        sourceType: SourceType.novelSource,
        contentId: 'c',
        format: DownloadFormat.epub,
        totalChapters: 4,
        downloadedChapters: 3,
        createdAt: 0,
      );
      expect(task.progress, 0.75);
    });

    test('isActive and isCompleted flags', () {
      const base = DownloadTask(
        id: 't', title: 'T', sourceType: SourceType.mangaSource,
        contentId: 'c', format: DownloadFormat.cbz, createdAt: 0,
      );

      expect(base.copyWith(status: DownloadStatus.pending).isActive, true);
      expect(base.copyWith(status: DownloadStatus.downloading).isActive, true);
      expect(base.copyWith(status: DownloadStatus.paused).isActive, true);
      expect(base.copyWith(status: DownloadStatus.completed).isActive, false);
      expect(base.copyWith(status: DownloadStatus.completed).isCompleted, true);
      expect(base.copyWith(status: DownloadStatus.failed).isActive, false);
      expect(base.copyWith(status: DownloadStatus.cancelled).isActive, false);
    });
  });

  group('DownloadFormatPreferences', () {
    test('defaults are cbz and epub', () {
      const prefs = DownloadFormatPreferences.defaults();
      expect(prefs.comicFormat, DownloadFormat.cbz);
      expect(prefs.novelFormat, DownloadFormat.epub);
    });

    test('JSON round-trip', () {
      const prefs = DownloadFormatPreferences(
        comicFormat: DownloadFormat.folder,
        novelFormat: DownloadFormat.txt,
      );
      final json = prefs.toJsonString();
      final restored = DownloadFormatPreferences.fromJsonString(json);
      expect(restored.comicFormat, DownloadFormat.folder);
      expect(restored.novelFormat, DownloadFormat.txt);
      expect(restored, prefs);
    });
  });

  group('DownloadStorage', () {
    late InMemoryBackend backend;
    late DownloadStorage storage;

    setUp(() {
      backend = InMemoryBackend();
      storage = DownloadStorage(backend: backend);
    });

    test('loadAll returns empty when no data', () async {
      final tasks = await storage.loadAll();
      expect(tasks, isEmpty);
    });

    test('saveAll and loadAll round-trip', () async {
      final tasks = <DownloadTask>[
        const DownloadTask(
          id: 't1', title: 'Task 1',
          sourceType: SourceType.mangaSource,
          contentId: 'c1', format: DownloadFormat.cbz,
          totalChapters: 5, downloadedChapters: 5,
          status: DownloadStatus.completed,
          createdAt: 1700000000000,
          localPath: '/tmp/t1.cbz',
        ),
        const DownloadTask(
          id: 't2', title: 'Task 2',
          sourceType: SourceType.novelSource,
          contentId: 'c2', format: DownloadFormat.epub,
          totalChapters: 3, downloadedChapters: 1,
          status: DownloadStatus.downloading,
          createdAt: 1700000000001,
        ),
      ];

      await storage.saveAll(tasks);
      final loaded = await storage.loadAll();
      expect(loaded.length, 2);
      expect(loaded[0].id, 't1');
      expect(loaded[0].status, DownloadStatus.completed);
      expect(loaded[1].id, 't2');
      expect(loaded[1].status, DownloadStatus.downloading);
    });

    test('clear empties storage', () async {
      await storage.saveAll(<DownloadTask>[
        const DownloadTask(
          id: 't', title: 'T',
          sourceType: SourceType.mangaSource,
          contentId: 'c', format: DownloadFormat.cbz,
          createdAt: 0,
        ),
      ]);
      await storage.clear();
      final loaded = await storage.loadAll();
      expect(loaded, isEmpty);
    });
  });

  group('DownloadManager clear-records rules', () {
    late InMemoryFileSystem fs;
    late InMemoryBackend backend;
    late DownloadStorage storage;
    late DownloadManager manager;

    setUp(() async {
      fs = InMemoryFileSystem();
      backend = InMemoryBackend();
      storage = DownloadStorage(backend: backend);
      manager = DownloadManager(
        storage: storage,
        fs: fs,
        service: MediaApiService(ResolverRegistry.instance),
        sourceRepo: SourceRepository(<PluginConfig>[]),
      );
      await manager.init();
    });

    test('clearAll(false) recovers orphaned downloads from meta.json',
        () async {
      // Simulate a completed download: write meta.json + product file
      final task = DownloadTask(
        id: 'orphan_1',
        title: 'Orphaned Comic',
        sourceType: SourceType.mangaSource,
        contentId: 'comic_orphan',
        format: DownloadFormat.cbz,
        totalChapters: 5,
        downloadedChapters: 5,
        status: DownloadStatus.completed,
        createdAt: 1700000000000,
        completedAt: 1700000001000,
        localPath: '${fs.basePath}/orphan_1.cbz',
      );

      // Write product file and meta.json
      await fs.writeBytes(
        task.localPath!,
        Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]),
      );
      await fs.writeString(
        fs.join(fs.basePath, '${task.id}.meta.json'),
        task.toJsonString(),
      );

      // Add to manager's task list, then clearAll(false)
      // (simulating: tasks were in storage, then cleared)
      await storage.saveAll(<DownloadTask>[task]);
      await manager.init();
      expect(manager.completedTasks.length, 1);

      // Clear all records (keep files)
      await manager.clearAll(deleteFiles: false);

      // After clearAll(false), orphaned download should be recovered
      expect(manager.completedTasks.length, 1);
      expect(manager.completedTasks.first.id, 'orphan_1');
      expect(manager.activeTasks, isEmpty);
    });

    test('clearAll(true) deletes files and does not recover', () async {
      final task = DownloadTask(
        id: 'del_1',
        title: 'To Delete',
        sourceType: SourceType.novelSource,
        contentId: 'novel_del',
        format: DownloadFormat.epub,
        totalChapters: 3,
        downloadedChapters: 3,
        status: DownloadStatus.completed,
        createdAt: 1700000000000,
        completedAt: 1700000001000,
        localPath: '${fs.basePath}/del_1.epub',
      );

      await fs.writeBytes(
        task.localPath!,
        Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]),
      );
      await fs.writeString(
        fs.join(fs.basePath, '${task.id}.meta.json'),
        task.toJsonString(),
      );

      await storage.saveAll(<DownloadTask>[task]);
      await manager.init();
      expect(manager.completedTasks.length, 1);

      // Clear all records + delete files
      await manager.clearAll(deleteFiles: true);

      // Both pages should be empty
      expect(manager.completedTasks, isEmpty);
      expect(manager.activeTasks, isEmpty);

      // Files should be deleted
      expect(await fs.exists(task.localPath!), false);
      expect(
        await fs.exists(fs.join(fs.basePath, '${task.id}.meta.json')),
        false,
      );
    });

    test('isItemDownloaded checks completed tasks', () async {
      final task = DownloadTask(
        id: 'check_1',
        title: 'Downloaded',
        sourceType: SourceType.mangaSource,
        contentId: 'content_123',
        format: DownloadFormat.cbz,
        totalChapters: 2,
        downloadedChapters: 2,
        status: DownloadStatus.completed,
        createdAt: 0,
        localPath: '${fs.basePath}/check_1.cbz',
      );

      await fs.writeBytes(task.localPath!, Uint8List(4));
      await fs.writeString(
        fs.join(fs.basePath, '${task.id}.meta.json'),
        task.toJsonString(),
      );
      await storage.saveAll(<DownloadTask>[task]);
      await manager.init();

      expect(manager.isItemDownloaded('content_123'), true);
      expect(manager.isItemDownloaded('not_downloaded'), false);
    });

    test('activeTasks filters out completed', () async {
      const active = DownloadTask(
        id: 'a1',
        title: 'Active',
        sourceType: SourceType.mangaSource,
        contentId: 'c_a',
        format: DownloadFormat.cbz,
        totalChapters: 5,
        downloadedChapters: 2,
        status: DownloadStatus.downloading,
        createdAt: 0,
      );
      final completed = DownloadTask(
        id: 'c1',
        title: 'Completed',
        sourceType: SourceType.mangaSource,
        contentId: 'c_c',
        format: DownloadFormat.cbz,
        totalChapters: 5,
        downloadedChapters: 5,
        status: DownloadStatus.completed,
        createdAt: 0,
        localPath: '${fs.basePath}/c1.cbz',
      );

      await fs.writeBytes(completed.localPath!, Uint8List(4));
      await fs.writeString(
        fs.join(fs.basePath, '${completed.id}.meta.json'),
        completed.toJsonString(),
      );
      await storage.saveAll(<DownloadTask>[active, completed]);
      await manager.init();

      expect(manager.activeTasks.length, 1);
      expect(manager.activeTasks.first.id, 'a1');
      expect(manager.completedTasks.length, 1);
      expect(manager.completedTasks.first.id, 'c1');
    });

    test('cancel with deleteFiles=false keeps meta.json', () async {
      const task = DownloadTask(
        id: 'cancel_1',
        title: 'Cancel Me',
        sourceType: SourceType.mangaSource,
        contentId: 'cancel_content',
        format: DownloadFormat.cbz,
        totalChapters: 3,
        downloadedChapters: 1,
        status: DownloadStatus.downloading,
        createdAt: 0,
      );

      await fs.writeString(
        fs.join(fs.basePath, '${task.id}.meta.json'),
        task.toJsonString(),
      );
      await storage.saveAll(<DownloadTask>[task]);
      await manager.init();

      await manager.cancel('cancel_1', deleteFiles: false);

      // meta.json should still exist
      expect(
        await fs.exists(fs.join(fs.basePath, '${task.id}.meta.json')),
        true,
      );
    });

    test('cancel with deleteFiles=true removes meta.json and files', () async {
      final task = DownloadTask(
        id: 'cancel_del',
        title: 'Cancel Delete',
        sourceType: SourceType.mangaSource,
        contentId: 'cancel_del_content',
        format: DownloadFormat.cbz,
        totalChapters: 3,
        downloadedChapters: 3,
        status: DownloadStatus.completed,
        createdAt: 0,
        localPath: '${fs.basePath}/cancel_del.cbz',
      );

      await fs.writeBytes(task.localPath!, Uint8List(4));
      await fs.writeString(
        fs.join(fs.basePath, '${task.id}.meta.json'),
        task.toJsonString(),
      );
      await storage.saveAll(<DownloadTask>[task]);
      await manager.init();

      await manager.cancel('cancel_del', deleteFiles: true);

      expect(await fs.exists(task.localPath!), false);
      expect(
        await fs.exists(fs.join(fs.basePath, '${task.id}.meta.json')),
        false,
      );
    });
  });
}
