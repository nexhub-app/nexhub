/// CSS / Jsoup 风格规则解析器：支持 `@` 链式选择器、`@text/@html/@owntext` 取值方法、
/// 索引过滤（`.0`、`.0:5`、`[-1,0:2]`）、`tag./class./id.` 前缀及 `&&/||/%%` 复合规则。
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'rule_analyzer.dart';
import 'source_rule.dart';

class AnalyzeByJsoup {
  dynamic content;
  final Element _element;

  AnalyzeByJsoup(this.content) : _element = _parse(content);

  static Element _parse(dynamic doc) {
    if (doc is Element) return doc;
    if (doc is Document) return doc.documentElement!;
    if (doc is String) {
      final document = html_parser.parse(doc);
      return document.documentElement!;
    }
    return html_parser.parse('').documentElement!;
  }

  /// 主入口：获取字符串列表，支持 @ 链式选择器。
  List<String> getStringList(String ruleStr) {
    if (ruleStr.isEmpty) return [];

    final sourceRule = SourceRule(ruleStr);
    final elementsRule = sourceRule.elementsRule;

    if (elementsRule.isEmpty) {
      return [_element.text.trim()];
    }

    final ruleAnalyzer = RuleAnalyzer(elementsRule);
    final ruleStrs = ruleAnalyzer.splitRule(['&&', '||', '%%']);
    final results = <List<String>>[];

    for (final ruleStrX in ruleStrs) {
      final temp = sourceRule.isCss
          ? _getResultLastCss(_element, ruleStrX)
          : _getResultList(ruleStrX);

      if (temp.isNotEmpty) {
        results.add(temp);
        if (ruleAnalyzer.elementsType == '||') break;
      }
    }

    if (results.isEmpty) return [];

    final textS = <String>[];
    if (ruleAnalyzer.elementsType == '%%') {
      for (int i = 0; i < results[0].length; i++) {
        for (final temp in results) {
          if (i < temp.length) {
            textS.add(temp[i]);
          }
        }
      }
    } else {
      for (final temp in results) {
        textS.addAll(temp);
      }
    }

    return textS;
  }

  List<String> _getResultList(String ruleStr) {
    if (ruleStr.isEmpty) return [];

    var elements = <Element>[_element];
    final rule = RuleAnalyzer(ruleStr);
    rule.trim();
    final rules = rule.splitRule(['@']);
    final last = rules.length - 1;

    for (int i = 0; i < last; i++) {
      final r = rules[i].trim();
      final indexMatch = RegExp(r'^(-?\d+)$').firstMatch(r);
      if (indexMatch != null) {
        final index = int.parse(r);
        final len = elements.length;
        if (index >= 0 && index < len) {
          elements = [elements[index]];
        } else if (index < 0 && len >= -index) {
          elements = [elements[len + index]];
        } else {
          elements = [];
        }
      } else {
        final es = <Element>[];
        for (final elt in elements) {
          es.addAll(_getElementsSingle(elt, r));
        }
        elements = es;
      }
    }

    if (elements.isEmpty) return [];
    return _getResultLast(elements, rules[last]);
  }

  /// 按单步规则获取元素，支持 tag./class./id./text. 前缀及索引过滤。
  List<Element> _getElementsSingle(Element temp, String rule) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return [];

    // 纯索引选择器（如 "0"、"-1"）
    final indexMatch = RegExp(r'^(-?\d+)$').firstMatch(trimmed);
    if (indexMatch != null) {
      final index = int.parse(trimmed);
      final children = temp.children;
      if (index >= 0 && index < children.length) {
        return [children[index]];
      } else if (index < 0 && children.length >= -index) {
        return [children[children.length + index]];
      }
      return [];
    }

    // 带索引的特殊选择器（如 "tag.div.0"、"class.name.-1"）
    // 参考原版：'':' 分隔索引，'.' 表示选择，'!' 表示排除
    for (final prefix in ['children', 'tag.', 'class.', 'id.', 'text.']) {
      if (trimmed.startsWith(prefix)) {
        List<Element> elements;
        String remaining = '';

        if (prefix == 'children') {
          elements = temp.children;
          remaining = trimmed.substring(8).trim(); // "children" 之后
        } else {
          final afterPrefix = trimmed.substring(prefix.length);
          final sepMatch = RegExp(r'[.!:]').firstMatch(afterPrefix);
          if (sepMatch != null) {
            final sepIndex = sepMatch.start;
            final value = afterPrefix.substring(0, sepIndex);
            remaining = afterPrefix.substring(sepIndex);

            switch (prefix) {
              case 'tag.':
                elements = temp.getElementsByTagName(value);
                break;
              case 'class.':
                elements = temp.getElementsByClassName(value);
                break;
              case 'id.':
                final found = temp.querySelector('#$value');
                elements = found != null ? [found] : [];
                break;
              case 'text.':
                elements = temp.children.where((e) => e.text.contains(value)).toList();
                break;
              default:
                elements = [];
            }
          } else {
            final value = afterPrefix;
            switch (prefix) {
              case 'tag.':
                elements = temp.getElementsByTagName(value);
                break;
              case 'class.':
                elements = temp.getElementsByClassName(value);
                break;
              case 'id.':
                final found = temp.querySelector('#$value');
                elements = found != null ? [found] : [];
                break;
              case 'text.':
                elements = temp.children.where((e) => e.text.contains(value)).toList();
                break;
              default:
                elements = [];
            }
            remaining = '';
          }
        }

        if (remaining.isNotEmpty && elements.isNotEmpty) {
          elements = _applyIndexFilter(elements, remaining);
        }
        return elements;
      }
    }

    // 默认按 CSS 选择器处理
    try {
      return temp.querySelectorAll(trimmed);
    } catch (_) {
      return [];
    }
  }

  /// 索引过滤：支持 .0、.-1、.0:5、.0:5:2、!0、[0,1,2]、[-1,0:2]
  List<Element> _applyIndexFilter(List<Element> elements, String indexStr) {
    final trimmed = indexStr.trim();
    if (trimmed.isEmpty || elements.isEmpty) return elements;

    bool exclude = false;
    String parseStr = trimmed;

    if (parseStr.startsWith('!')) {
      exclude = true;
      parseStr = parseStr.substring(1).trim();
    }

    if (parseStr.startsWith('[') && parseStr.endsWith(']')) {
      parseStr = parseStr.substring(1, parseStr.length - 1);
    } else if (parseStr.startsWith('.')) {
      parseStr = parseStr.substring(1);
    } else if (parseStr.startsWith(':')) {
      parseStr = parseStr.substring(1);
    }

    if (parseStr.isEmpty) return elements;

    final indices = <int>{};
    bool hasValidIndex = false;
    final parts = parseStr.split(',');

    for (final part in parts) {
      final p = part.trim();
      if (p.isEmpty) continue;

      // 区间（start:end 或 start:end:step）
      if (p.contains(':')) {
        final rangeParts = p.split(':');
        int? start;
        int? end;
        var step = 1;

        if (rangeParts.isNotEmpty && rangeParts[0].isNotEmpty) {
          start = int.tryParse(rangeParts[0]);
        }
        if (rangeParts.length > 1 && rangeParts[1].isNotEmpty) {
          end = int.tryParse(rangeParts[1]);
        }
        if (rangeParts.length > 2 && rangeParts[2].isNotEmpty) {
          step = int.tryParse(rangeParts[2]) ?? 1;
        }

        final len = elements.length;
        start = start ?? 0;
        end = end ?? (len - 1);

        if (start < 0) start += len;
        if (end < 0) end += len;
        start = start.clamp(0, len - 1);
        end = end.clamp(0, len - 1);

        if (step == 0) step = 1;

        if (end > start) {
          for (int i = start; i <= end; i += step) {
            indices.add(i);
            hasValidIndex = true;
          }
        } else {
          for (int i = start; i >= end; i -= step) {
            indices.add(i);
            hasValidIndex = true;
          }
        }
      } else {
        final idx = int.tryParse(p);
        if (idx != null) {
          final len = elements.length;
          if (idx >= 0 && idx < len) {
            indices.add(idx);
            hasValidIndex = true;
          } else if (idx < 0 && len >= -idx) {
            indices.add(idx + len);
            hasValidIndex = true;
          }
        }
      }
    }

    // 未解析到有效索引时返回原列表（可能是格式无效）
    if (!hasValidIndex) return elements;

    if (exclude) {
      final result = <Element>[];
      for (int i = 0; i < elements.length; i++) {
        if (!indices.contains(i)) {
          result.add(elements[i]);
        }
      }
      return result;
    } else {
      final sortedIndices = indices.toList()..sort();
      return sortedIndices.map((i) => elements[i]).toList();
    }
  }

  /// 按最后一步方法获取结果（text/html/owntext/属性名 等）。
  List<String> _getResultLast(List<Element> elements, String method) {
    final result = <String>[];
    final lowerMethod = method.toLowerCase();

    switch (lowerMethod) {
      case 'text':
        for (final el in elements) {
          final text = el.text.trim();
          if (text.isNotEmpty) result.add(text);
        }
        break;
      case 'textnodes':
        for (final el in elements) {
          final nodes = el.nodes
              .whereType<Text>()
              .map((n) => (n).text.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (nodes.isNotEmpty) result.add(nodes.join('\n'));
        }
        break;
      case 'owntext':
        for (final el in elements) {
          final text = el.nodes
              .whereType<Text>()
              .map((n) => n.text.trim())
              .where((s) => s.isNotEmpty)
              .join(' ')
              .trim();
          if (text.isNotEmpty) result.add(text);
        }
        break;
      case 'html':
        for (final el in elements) {
          final clone = el.clone(true);
          clone.querySelectorAll('script').forEach((e) => e.remove());
          clone.querySelectorAll('style').forEach((e) => e.remove());
          final html = clone.innerHtml;
          if (html.isNotEmpty) result.add(html);
        }
        break;
      case 'all':
        for (final el in elements) {
          result.add(el.outerHtml);
        }
        break;
      default:
        // 属性提取
        for (final el in elements) {
          final attr = el.attributes[method] ?? '';
          if (attr.isNotEmpty && !result.contains(attr)) result.add(attr);
        }
        break;
    }
    return result;
  }

  /// CSS 规则带结尾 @ 取值方法。
  List<String> _getResultLastCss(Element element, String ruleStr) {
    final lastAt = ruleStr.lastIndexOf('@');
    if (lastAt < 0) {
      final elements = element.querySelectorAll(ruleStr);
      return elements.map((e) => e.text.trim()).where((s) => s.isNotEmpty).toList();
    }
    final selector = ruleStr.substring(0, lastAt).trim();
    final extractMethod = ruleStr.substring(lastAt + 1).trim();
    final elements = element.querySelectorAll(selector);
    return _getResultLast(elements, extractMethod);
  }

  /// 获取单个字符串（多结果以换行拼接）。
  String getString(String ruleStr) {
    final list = getStringList(ruleStr);
    if (list.isEmpty) return '';
    if (list.length == 1) return list.first;
    return list.join('\n');
  }

  /// 仅取首个字符串（用于 URL 提取）。
  String getString0(String ruleStr) {
    final list = getStringList(ruleStr);
    return list.isEmpty ? '' : list.first;
  }

  /// 获取元素列表（非字符串）。
  List<dynamic> getElements(String ruleStr) {
    if (ruleStr.isEmpty) return [];

    final sourceRule = SourceRule(ruleStr);
    final elementsRule = sourceRule.elementsRule;

    if (elementsRule.isEmpty) return [_element];

    final ruleAnalyzer = RuleAnalyzer(elementsRule);
    final ruleStrs = ruleAnalyzer.splitRule(['&&', '||', '%%']);
    final elementsList = <List<Element>>[];

    for (final ruleStrX in ruleStrs) {
      final elements = sourceRule.isCss
          ? _getElementsCss(_element, ruleStrX)
          : _getElementsNonCss(ruleStrX);

      if (elements.isNotEmpty) {
        elementsList.add(elements);
        if (ruleAnalyzer.elementsType == '||') break;
      }
    }

    if (elementsList.isEmpty) return [];

    final result = <Element>[];
    if (ruleAnalyzer.elementsType == '%%') {
      for (int i = 0; i < elementsList[0].length; i++) {
        for (final elements in elementsList) {
          if (i < elements.length) {
            result.add(elements[i]);
          }
        }
      }
    } else {
      for (final elements in elementsList) {
        result.addAll(elements);
      }
    }

    return result;
  }

  List<Element> _getElementsCss(Element element, String ruleStr) {
    final lastAt = ruleStr.lastIndexOf('@');
    if (lastAt >= 0) {
      return element.querySelectorAll(ruleStr.substring(0, lastAt).trim());
    }
    return element.querySelectorAll(ruleStr);
  }

  List<Element> _getElementsNonCss(String ruleStr) {
    if (ruleStr.isEmpty) return [];

    var elements = <Element>[_element];
    final rule = RuleAnalyzer(ruleStr);
    rule.trim();
    final rules = rule.splitRule(['@']);

    for (final r in rules) {
      final es = <Element>[];
      for (final elt in elements) {
        es.addAll(_getElementsSingle(elt, r));
      }
      elements = es;
    }

    return elements;
  }

  dynamic getObject(String rule) {
    if (rule.isEmpty) return null;

    final list = getStringList(rule);
    if (list.isEmpty) return null;
    if (list.length == 1) return list.first;

    try {
      final elements = getElements(rule);
      if (elements.isEmpty) return null;
      final el = elements.first;
      if (el is Element) {
        return {
          'text': el.text.trim(),
          'html': el.innerHtml,
          ...el.attributes,
        };
      }
      return el;
    } catch (_) {
      return list.first;
    }
  }
}
