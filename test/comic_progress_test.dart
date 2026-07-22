import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/comic/comic_progress_manager.dart';
import 'package:nexhub/core/comic/models/reader_preferences.dart';

/// 返回非法 JSON 的后端，验证损坏数据降级。
class _BadBackend implements PrefsBackend {
  @override
  Future<String?> get(String key) async => 'not-json';
  @override
  Future<void> set(String key, String value) async {}
}

void main() {
  test('save then get progress', () async {
    final m = ComicProgressManager(backend: InMemoryBackend());
    expect(await m.get('c'), isNull);
    await m.save('c', 'ch1', 3, 2);
    final p = await m.get('c');
    expect(p?.chapterId, 'ch1');
    expect(p?.currentPage, 3);
    expect(p?.chapterIndex, 2);
  });

  test('clear removes progress', () async {
    final m = ComicProgressManager(backend: InMemoryBackend());
    await m.save('c', 'ch1', 1, 0);
    await m.clear('c');
    expect(await m.get('c'), isNull);
  });

  test('corrupt backend value falls back to null', () async {
    final m = ComicProgressManager(backend: _BadBackend());
    expect(await m.get('c'), isNull);
  });
}
