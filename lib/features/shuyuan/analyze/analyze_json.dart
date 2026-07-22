/// JSON 规则解析器：支持 `$.a.b`、`$["key"]`、`$[index]` 等 JSONPath 风格取值。
library;

import 'dart:convert';

class AnalyzeByJson {
  dynamic content;

  AnalyzeByJson(this.content);

  dynamic get _jsonData {
    if (content is String) {
      try {
        return json.decode(content as String);
      } catch (_) {
        return null;
      }
    }
    return content;
  }

  String getString(String rule) {
    if (rule.isEmpty) return '';
    final result = _resolvePath(rule);
    if (result == null) return '';
    if (result is List) {
      return result.map((e) => e.toString()).join('\n');
    }
    return result.toString();
  }

  List<String> getStringList(String rule) {
    if (rule.isEmpty) return [];
    final result = _resolvePath(rule);
    if (result == null) return [];
    if (result is List) {
      return result.map((e) => e.toString()).toList();
    }
    return [result.toString()];
  }

  List<dynamic> getList(String rule) {
    if (rule.isEmpty) return [];
    final result = _resolvePath(rule);
    if (result == null) return [];
    if (result is List) return result;
    return [result];
  }

  dynamic getObject(String rule) {
    if (rule.isEmpty) return null;
    return _resolvePath(rule);
  }

  dynamic _resolvePath(String path) {
    final data = _jsonData;
    if (data == null) return null;

    if (path.startsWith('\$.')) {
      final parts = path.substring(2).split('.');
      return _navigate(data, parts);
    }

    if (path.startsWith('\$[')) {
      final key = path.substring(2, path.length - 1).replaceAll('"', '').replaceAll("'", '');
      if (data is Map) return data[key];
      if (data is List) {
        final index = int.tryParse(key);
        if (index != null && index < data.length) return data[index];
      }
      return null;
    }

    if (data is Map) return data[path];
    return null;
  }

  dynamic _navigate(dynamic current, List<String> parts) {
    for (final part in parts) {
      if (current == null) return null;

      final arrayMatch = RegExp(r'^([^\[]+)\[(\d+|\*)\]$').firstMatch(part);
      if (arrayMatch != null) {
        final key = arrayMatch.group(1)!;
        final index = arrayMatch.group(2)!;

        if (current is Map) {
          current = current[key];
        }

        if (current is List) {
          if (index == '*') {
            return current;
          }
          final i = int.tryParse(index) ?? 0;
          if (i < current.length) {
            current = current[i];
          } else {
            return null;
          }
        }
      } else {
        if (current is Map) {
          current = current[part];
        } else if (current is List) {
          final index = int.tryParse(part);
          if (index != null && index < current.length) {
            current = current[index];
          } else {
            return null;
          }
        } else {
          return null;
        }
      }
    }
    return current;
  }
}
