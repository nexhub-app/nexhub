import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexhub/core/models/plugin_config.dart';

void main() {
  group('Built-in source JSONs', () {
    final dir = Directory('plugins/builtin');

    test('all .json files parse and validate', () {
      // 共创模式：公开仓库不内置/打包任何预备源，源由用户自行导入或在社区共享。
      // 因此本地未放置源 JSON 时，本测试自动跳过（不视为失败）。
      if (!dir.existsSync()) {
        return markTestSkipped(
            'plugins/builtin 不存在：公开仓库不内置源，跳过校验。');
      }
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();

      if (files.isEmpty) {
        return markTestSkipped(
            'plugins/builtin 下无 .json：未放置内置源，跳过校验。');
      }

      for (final file in files) {
        final raw = file.readAsStringSync();
        final config = PluginConfig.fromJsonString(raw);
        final errors = config.validate();
        expect(errors, isEmpty,
            reason: '${file.path} validation failed: $errors');
        expect(config.id, isNotEmpty);
        expect(config.site.baseUrl, startsWith('http'));
      }
    });
  });
}
