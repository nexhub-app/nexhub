/// 单条书源规则解析（`@css/@xpath/@json/@js` + `##` 正则替换）。
library;

/// 规则模式：默认（CSS/默认）、XPath、JSON、JS、正则。
enum Mode {
  defaultMode,
  xpath,
  json,
  js,
  regex,
}

class SourceRule {
  String rule = '';
  String elementsRule = '';
  Mode mode;
  String replaceRegex = '';
  String replacement = '';
  bool replaceFirst = false;
  final Map<String, String> putMap = {};

  bool isCss = false;

  SourceRule(String ruleStr, [this.mode = Mode.defaultMode, bool isJson = false]) {
    _init(ruleStr, isJson);
  }

  void _init(String ruleStr, bool isJson) {
    if (mode == Mode.js || mode == Mode.regex) {
      rule = ruleStr;
      elementsRule = ruleStr;
      return;
    }

    if (ruleStr.toLowerCase().startsWith('@css: ')) {
      mode = Mode.defaultMode;
      isCss = true;
      rule = ruleStr.substring(5);
    } else if (ruleStr.toLowerCase().startsWith('@xpath: ')) {
      mode = Mode.xpath;
      rule = ruleStr.substring(7);
    } else if (ruleStr.toLowerCase().startsWith('@json: ')) {
      mode = Mode.json;
      rule = ruleStr.substring(6);
    } else if (ruleStr.toLowerCase().startsWith('@js: ')) {
      mode = Mode.js;
      rule = ruleStr.substring(4);
    } else if (ruleStr.startsWith('@@')) {
      mode = Mode.defaultMode;
      isCss = true;
      rule = ruleStr.substring(2);
    } else if (isJson || ruleStr.startsWith('\$.') || ruleStr.startsWith('\$[')) {
      mode = Mode.json;
      rule = ruleStr;
    } else if (ruleStr.startsWith('/')) {
      mode = Mode.xpath;
      rule = ruleStr;
    } else {
      rule = ruleStr;
      isCss = _looksLikeCss(ruleStr);
    }

    rule = _splitPutRule(rule);
    elementsRule = rule;

    _splitRegex(rule);
  }

  int getParamSize() {
    if (rule.isEmpty) return 0;
    final matches = RegExp(r'\{\{.*?\}\}').allMatches(rule);
    return matches.length;
  }

  bool _looksLikeCss(String rule) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.contains('@')) return false;
    if (trimmed.startsWith('.') || trimmed.startsWith('#') || trimmed.startsWith('[')) return true;
    if (trimmed.contains(':') && !trimmed.startsWith('@')) return true;
    if (RegExp(r'[a-zA-Z][.#]').hasMatch(trimmed)) return true;
    if (RegExp(r'[a-zA-Z]\[').hasMatch(trimmed)) return true;
    return false;
  }

  String _splitPutRule(String ruleStr) {
    final putPattern = RegExp(r'@put:\((\{[^}]+?\})\)', caseSensitive: false);
    var vRuleStr = ruleStr;
    var match = putPattern.firstMatch(vRuleStr);
    while (match != null) {
      vRuleStr = vRuleStr.replaceFirst(match.group(0)!, '');
      final jsonStr = match.group(1)!;
      try {
        final decoded = _parseJsonMap(jsonStr);
        putMap.addAll(decoded);
      } catch (_) {}
      match = putPattern.firstMatch(vRuleStr);
    }
    return vRuleStr;
  }

  void _splitRegex(String ruleStr) {
    final parts = ruleStr.split('##');
    rule = parts[0].trim();
    if (parts.length > 1) replaceRegex = parts[1];
    if (parts.length > 2) replacement = parts[2];
    if (parts.length > 3) replaceFirst = true;
  }

  void makeUpRule(dynamic result) {
    if (rule.contains('##')) {
      final parts = rule.split('##');
      rule = parts[0].trim();
      if (parts.length > 1) replaceRegex = parts[1];
      if (parts.length > 2) replacement = parts[2];
      if (parts.length > 3) replaceFirst = true;
    }
  }

  static Map<String, String> _parseJsonMap(String jsonStr) {
    final result = <String, String>{};
    final inner = jsonStr.trim();
    if (!inner.startsWith('{') || !inner.endsWith('}')) return result;

    final content = inner.substring(1, inner.length - 1);
    final pairs = _splitJsonPairs(content);
    for (final pair in pairs) {
      final colonIndex = pair.indexOf(':');
      if (colonIndex > 0) {
        final key = pair.substring(0, colonIndex).trim().replaceAll('"', '');
        final value = pair.substring(colonIndex + 1).trim().replaceAll('"', '');
        result[key] = value;
      }
    }
    return result;
  }

  static List<String> _splitJsonPairs(String content) {
    final pairs = <String>[];
    int depth = 0;
    int start = 0;
    bool inString = false;

    for (int i = 0; i < content.length; i++) {
      final c = content[i];
      if (c == '"') {
        inString = !inString;
      } else if (!inString) {
        if (c == '{' || c == '[') {
          depth++;
        } else if (c == '}' || c == ']') {
          depth--;
        } else if (c == ',' && depth == 0) {
          pairs.add(content.substring(start, i).trim());
          start = i + 1;
        }
      }
    }
    if (start < content.length) {
      pairs.add(content.substring(start).trim());
    }
    return pairs;
  }
}
