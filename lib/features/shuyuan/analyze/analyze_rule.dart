/// 规则引擎门面：按规则模式（CSS/XPath/JSON/JS/正则）分派到对应解析器，
/// 支持 `##` 正则替换、`@put` 变量、`<js>`/`@js:` 内嵌脚本与 `&&/||/%%` 复合规则。
library;

import 'package:html/dom.dart';
import 'source_rule.dart';
import 'analyze_jsoup.dart';
import 'analyze_xpath.dart';
import 'analyze_json.dart';
import 'analyze_regex.dart';
import 'js_engine.dart';
import '../model/xiaoshuo_book.dart';
import '../model/xiaoshuo_book_chapter.dart';

class AnalyzeRule {
  XiaoshuoBook? book;
  XiaoshuoBookChapter? chapter;
  String? baseUrl;
  String? redirectUrl;
  String? nextChapterUrl;
  dynamic content;
  bool isJson = false;

  AnalyzeByJsoup? _analyzeByJsoup;
  AnalyzeByXPath? _analyzeByXPath;
  AnalyzeByJson? _analyzeByJson;
  JsEngine? _jsEngine;

  final Map<String, String> _variables = {};
  final Map<String, List<SourceRule>> _stringRuleCache = {};

  AnalyzeRule({this.book, this.chapter});

  AnalyzeRule setContent(dynamic newContent, [String? newBaseUrl]) {
    content = newContent;
    if (newContent is! Node) {
      isJson = _isJsonString(newContent?.toString() ?? '');
    } else {
      isJson = false;
    }
    if (newBaseUrl != null) baseUrl = newBaseUrl;
    _analyzeByJsoup = null;
    _analyzeByXPath = null;
    _analyzeByJson = null;
    return this;
  }

  AnalyzeRule setBaseUrl(String? url) {
    if (url != null) baseUrl = url;
    return this;
  }

  String? setRedirectUrl(String url) {
    try {
      redirectUrl = url;
    } catch (_) {}
    return redirectUrl;
  }

  AnalyzeRule setChapter(XiaoshuoBookChapter? ch) {
    chapter = ch;
    return this;
  }

  AnalyzeRule setNextChapterUrl(String? url) {
    nextChapterUrl = url;
    return this;
  }

  void put(String key, String value) {
    _variables[key] = value;
    if (key == 'title' && chapter != null) {
      chapter!.title = value;
    }
  }

  String get(String key) {
    switch (key) {
      case 'bookName':
        return book?.name ?? '';
      case 'title':
        return chapter?.title ?? '';
      default:
        return _variables[key] ?? book?.getVariable(key) ?? chapter?.getVariable(key) ?? '';
    }
  }

  List<String> getStringList(String? ruleStr, {bool isUrl = false}) {
    if (ruleStr == null || ruleStr.isEmpty) return [];
    final ruleList = _splitSourceRuleCache(ruleStr);
    return _getStringListFromRules(ruleList, isUrl: isUrl);
  }

  String getString(String? ruleStr, {bool unescape = true, bool isUrl = false, dynamic mContent}) {
    if (ruleStr == null || ruleStr.isEmpty) return '';
    final ruleList = _splitSourceRuleCache(ruleStr);
    return _getStringFromRules(ruleList, unescape: unescape, isUrl: isUrl, mContent: mContent);
  }

  String getStringFromRules(List<dynamic> ruleList, {bool unescape = true, bool isUrl = false, dynamic mContent}) {
    if (ruleList.isEmpty) return '';
    final sourceRules = ruleList.whereType<SourceRule>().toList();
    return _getStringFromRules(sourceRules, unescape: unescape, isUrl: isUrl, mContent: mContent);
  }

  List<String> getStringListFromRules(List<dynamic> ruleList, {bool isUrl = false}) {
    if (ruleList.isEmpty) return [];
    final sourceRules = ruleList.whereType<SourceRule>().toList();
    return _getStringListFromRules(sourceRules, isUrl: isUrl);
  }

  List<dynamic> getElements(String ruleStr) {
    if (ruleStr.isEmpty) return [];
    final ruleList = splitSourceRule(ruleStr, allInOne: true);
    return _getElementsFromRules(ruleList);
  }

  dynamic getElement(String ruleStr) {
    if (ruleStr.isEmpty) return null;
    var result = content;
    final ruleList = splitSourceRule(ruleStr, allInOne: true);
    if (result != null && ruleList.isNotEmpty) {
      for (final sourceRule in ruleList) {
        _putAll(sourceRule.putMap);
        sourceRule.makeUpRule(result);
        if (result == null) continue;
        final rule = sourceRule.rule;
        if (rule.isNotEmpty) {
          result = _executeRuleElements(result, sourceRule);
        }
        if (result != null && sourceRule.replaceRegex.isNotEmpty) {
          result = _replaceRegex(result.toString(), sourceRule);
        }
      }
    }
    return result;
  }

  List<SourceRule> _splitSourceRuleCache(String ruleStr) {
    return _stringRuleCache.putIfAbsent(ruleStr, () => splitSourceRule(ruleStr));
  }

  List<SourceRule> splitSourceRule(String? ruleStr, {bool allInOne = false}) {
    if (ruleStr == null || ruleStr.isEmpty) return [];
    final ruleList = <SourceRule>[];
    Mode mMode = Mode.defaultMode;
    var start = 0;

    if (allInOne && ruleStr.startsWith(': ')) {
      mMode = Mode.regex;
      start = 1;
    }

    // 不再预分割 &&，让 AnalyzeByJsoup 内部处理 &&/||/%%
    final trimmed = ruleStr.substring(start).trim();
    if (trimmed.isEmpty) return [];

    // 处理 JS 模式
    final jsPattern = RegExp(r'<js>([\w\W]*?)</js>|@js:([\w\W]*)', caseSensitive: false);
    final matches = jsPattern.allMatches(trimmed).toList();

    if (matches.isEmpty) {
      ruleList.add(SourceRule(trimmed, mMode, isJson));
    } else {
      var segStart = 0;
      for (final match in matches) {
        if (match.start > segStart) {
          final tmp = trimmed.substring(segStart, match.start).trim();
          if (tmp.isNotEmpty) {
            ruleList.add(SourceRule(tmp, mMode, isJson));
          }
        }
        final jsContent = match.group(2) ?? match.group(1) ?? '';
        ruleList.add(SourceRule(jsContent, Mode.js, isJson));
        segStart = match.end;
      }
      if (trimmed.length > segStart) {
        final tmp = trimmed.substring(segStart).trim();
        if (tmp.isNotEmpty) {
          ruleList.add(SourceRule(tmp, mMode, isJson));
        }
      }
    }

    return ruleList;
  }

  String _getStringFromRules(List<SourceRule> ruleList, {bool unescape = true, bool isUrl = false, dynamic mContent}) {
    if (ruleList.isEmpty) return '';
    var result = mContent ?? content;
    if (result != null && ruleList.isNotEmpty) {
      if (result is Map) {
        final sourceRule = ruleList.first;
        _putAll(sourceRule.putMap);
        sourceRule.makeUpRule(result);
        result = sourceRule.getParamSize() > 1
            ? sourceRule.rule
            : result[sourceRule.rule]?.toString();
        if (result != null && sourceRule.replaceRegex.isNotEmpty) {
          result = _replaceRegex(result.toString(), sourceRule);
        }
      } else {
        for (final sourceRule in ruleList) {
          _putAll(sourceRule.putMap);
          sourceRule.makeUpRule(result);
          if (result == null) continue;
          final rule = sourceRule.rule;
          if (rule.isNotEmpty) {
            result = _executeRule(result, sourceRule, isUrl: isUrl);
          }
          if (result != null && sourceRule.replaceRegex.isNotEmpty) {
            result = _replaceRegex(result.toString(), sourceRule);
          }
        }
      }
    }
    result ??= '';
    var resultStr = result.toString();
    if (unescape && resultStr.contains('&')) {
      resultStr = _unescapeHtml(resultStr);
    }
    if (isUrl) {
      if (resultStr.trim().isEmpty) {
        return baseUrl ?? '';
      }
      return _getAbsoluteUrl(resultStr);
    }
    return resultStr;
  }

  List<String> _getStringListFromRules(List<SourceRule> ruleList, {bool isUrl = false}) {
    if (ruleList.isEmpty) return [];
    var result = content;
    if (content != null && ruleList.isNotEmpty) {
      result = content;
      if (result is Map) {
        final sourceRule = ruleList.first;
        _putAll(sourceRule.putMap);
        sourceRule.makeUpRule(result);
        result = sourceRule.getParamSize() > 1
            ? sourceRule.rule
            : result[sourceRule.rule];
        if (result != null && sourceRule.replaceRegex.isNotEmpty) {
          if (result is List) {
            result = result.map((o) => _replaceRegex(o.toString(), sourceRule)).toList();
          } else {
            result = _replaceRegex(result.toString(), sourceRule);
          }
        }
      } else {
        for (final sourceRule in ruleList) {
          _putAll(sourceRule.putMap);
          sourceRule.makeUpRule(result);
          if (result == null) continue;
          final rule = sourceRule.rule;
          if (rule.isNotEmpty) {
            result = _executeRule(result, sourceRule, isUrl: isUrl);
          }
          if (result != null && sourceRule.replaceRegex.isNotEmpty) {
            if (result is List) {
              final newList = <String>[];
              for (final item in result) {
                newList.add(_replaceRegex(item.toString(), sourceRule));
              }
              result = newList;
            } else {
              result = _replaceRegex(result.toString(), sourceRule);
            }
          }
        }
      }
    }
    if (result == null) return [];
    if (result is String) {
      return result.split('\n').where((s) => s.isNotEmpty).toList();
    }
    if (result is List) {
      return result.map((e) => e.toString()).toList();
    }
    return [result.toString()];
  }

  List<dynamic> _getElementsFromRules(List<SourceRule> ruleList) {
    if (ruleList.isEmpty) return [];
    var result = content;

    for (final sourceRule in ruleList) {
      _putAll(sourceRule.putMap);
      result = _executeRuleElements(result, sourceRule);
      if (result == null) continue;
    }

    if (result == null) return [];
    if (result is List) return result;
    return [];
  }

  dynamic _executeRule(dynamic result, SourceRule sourceRule, {bool isUrl = false}) {
    final rule = sourceRule.rule;

    switch (sourceRule.mode) {
      case Mode.js:
        return _evalJs(rule, result);
      case Mode.regex:
        return rule;
      case Mode.json:
        final analyzer = _getJsonAnalyzer(result);
        return analyzer.getString(rule);
      case Mode.xpath:
        final analyzer = _getXPathAnalyzer(result);
        return analyzer.getString(rule);
      case Mode.defaultMode:
        final analyzer = _getJsoupAnalyzer(result);
        if (isUrl) {
          return analyzer.getString0(rule);
        }
        return analyzer.getString(rule);
    }
  }

  dynamic _executeRuleElements(dynamic result, SourceRule sourceRule) {
    final rule = sourceRule.rule;

    switch (sourceRule.mode) {
      case Mode.js:
        final jsResult = _evalJs(rule, result);
        if (jsResult is List) return jsResult;
        return [];
      case Mode.regex:
        if (result is String) {
          return AnalyzeByRegex.getElements(result, rule);
        }
        return [];
      case Mode.json:
        final analyzer = _getJsonAnalyzer(result);
        return analyzer.getList(rule);
      case Mode.xpath:
        final analyzer = _getXPathAnalyzer(result);
        return analyzer.getElements(rule);
      case Mode.defaultMode:
        final analyzer = _getJsoupAnalyzer(result);
        return analyzer.getElements(rule);
    }
  }

  AnalyzeByJsoup _getJsoupAnalyzer(dynamic content) {
    if (_analyzeByJsoup == null || _analyzeByJsoup!.content != content) {
      _analyzeByJsoup = AnalyzeByJsoup(content);
    }
    return _analyzeByJsoup!;
  }

  AnalyzeByXPath _getXPathAnalyzer(dynamic content) {
    if (_analyzeByXPath == null || _analyzeByXPath!.content != content) {
      _analyzeByXPath = AnalyzeByXPath(content);
    }
    return _analyzeByXPath!;
  }

  AnalyzeByJson _getJsonAnalyzer(dynamic content) {
    if (_analyzeByJson == null || _analyzeByJson!.content != content) {
      _analyzeByJson = AnalyzeByJson(content);
    }
    return _analyzeByJson!;
  }

  String _evalJs(String jsStr, dynamic result) {
    try {
      _jsEngine ??= JsEngine();
      final bindings = <String, dynamic>{
        'java': this,
        'result': result,
        'baseUrl': baseUrl ?? '',
        'src': content?.toString() ?? '',
        'title': chapter?.title ?? '',
      };
      return _jsEngine!.eval(jsStr, bindings: bindings);
    } catch (_) {
      return '';
    }
  }

  String evalJs(String jsStr, dynamic result) {
    return _evalJs(jsStr, result);
  }

  String _replaceRegex(String result, SourceRule sourceRule) {
    if (sourceRule.replaceRegex.isEmpty) return result;
    try {
      final regex = RegExp(sourceRule.replaceRegex);
      if (sourceRule.replaceFirst) {
        return result.replaceFirst(regex, sourceRule.replacement);
      }
      return result.replaceAll(regex, sourceRule.replacement);
    } catch (_) {
      try {
        if (sourceRule.replaceFirst) {
          final index = result.indexOf(sourceRule.replaceRegex);
          if (index >= 0) {
            return result.substring(0, index) +
                sourceRule.replacement +
                result.substring(index + sourceRule.replaceRegex.length);
          }
          return '';
        }
        return result.replaceAll(sourceRule.replaceRegex, sourceRule.replacement);
      } catch (_) {
        return result;
      }
    }
  }

  String _getAbsoluteUrl(String url) {
    if (url.isEmpty) return baseUrl ?? '';
    if (url.startsWith('http')) return url;
    if (baseUrl == null || baseUrl!.isEmpty) return url;
    try {
      final base = Uri.parse(baseUrl!);
      return base.resolve(url).toString();
    } catch (_) {
      return url;
    }
  }

  String _unescapeHtml(String str) {
    return str
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  bool _isJsonString(String str) {
    final trimmed = str.trim();
    return (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'));
  }

  void _putAll(Map<String, String> map) {
    for (final entry in map.entries) {
      put(entry.key, getString(entry.value));
    }
  }
}
