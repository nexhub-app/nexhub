import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';
import 'package:nexhub/core/services/source_repository.dart';

void main() {
  group('SourceRepository', () {
    final repo = SourceRepository.fromJsonList(<Map<String, dynamic>>[
      {
        'id': 'pms_test',
        'name': 'Test Media',
        'type': 'animeSource',
        'site': {
          'domain': 'https://example.com',
          'baseUrl': 'https://example.com',
        },
        'parser': {'type': 'builtin'},
        'routes': {
          'latest': {'url': '/api.php/provide/vod/?ac=list'},
        },
        'enabled': true,
      },
      {
        'id': 'manga_test',
        'name': 'Test Manga',
        'type': 'mangaSource',
        'site': {
          'domain': 'https://m.example.com',
          'baseUrl': 'https://m.example.com',
        },
        'parser': {'type': 'builtin'},
        'routes': {},
        'enabled': false,
      },
    ]);

    test('byType filters active sources', () {
      expect(repo.byType(SourceType.animeSource), hasLength(1));
      expect(repo.byType(SourceType.mangaSource), isEmpty);
    });

    test('getById returns matching config', () {
      expect(repo.getById('pms_test')?.name, 'Test Media');
      expect(repo.getById('missing'), isNull);
    });

    test('activeSources excludes disabled', () {
      expect(repo.activeSources, hasLength(1));
    });
  });
}
