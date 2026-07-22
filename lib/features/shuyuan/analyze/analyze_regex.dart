/// 正则规则解析器：从内容中按正则提取字符串/元素列表。
library;

class AnalyzeByRegex {
  static String getString(String content, String rule) {
    if (rule.isEmpty || content.isEmpty) return '';
    try {
      final regex = RegExp(rule, dotAll: true);
      final match = regex.firstMatch(content);
      if (match != null) {
        if (match.groupCount > 0) {
          return match.group(1) ?? match.group(0) ?? '';
        }
        return match.group(0) ?? '';
      }
    } catch (_) {}
    return '';
  }

  static List<String> getStringList(String content, String rule) {
    if (rule.isEmpty || content.isEmpty) return [];
    final results = <String>[];
    try {
      final regex = RegExp(rule, dotAll: true);
      for (final match in regex.allMatches(content)) {
        if (match.groupCount > 0) {
          final group = match.group(1);
          if (group != null && group.isNotEmpty) {
            results.add(group);
          }
        } else {
          final group = match.group(0);
          if (group != null && group.isNotEmpty) {
            results.add(group);
          }
        }
      }
    } catch (_) {}
    return results;
  }

  static String? getElement(String content, String rule) {
    final rules = rule.split('&&').where((r) => r.trim().isNotEmpty).toList();
    final sList = _getElementsByRules(content, rules);
    return sList.isEmpty ? null : sList.first;
  }

  static List<String> getElements(String content, String rule) {
    final rules = rule.split('&&').where((r) => r.trim().isNotEmpty).toList();
    return _getElementsByRules(content, rules);
  }

  static List<String> _getElementsByRules(String content, List<String> rules) {
    final resultList = <String>[];
    for (final r in rules) {
      try {
        final regex = RegExp(r, dotAll: true);
        for (final match in regex.allMatches(content)) {
          for (int i = 0; i <= match.groupCount; i++) {
            final group = match.group(i);
            if (group != null) {
              resultList.add(group);
            }
          }
        }
      } catch (_) {}
    }
    return resultList;
  }
}
