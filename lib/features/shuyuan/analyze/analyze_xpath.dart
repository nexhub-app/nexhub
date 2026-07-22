/// XPath 规则解析器：支持 `/@attr`、`/text()`、`//tag`、`/path/to` 等表达式。
library;

import 'package:xml/xml.dart';
import 'package:html/parser.dart' as html_parser;

class AnalyzeByXPath {
  dynamic content;

  AnalyzeByXPath(this.content);

  XmlDocument get _document {
    if (content is XmlDocument) return content as XmlDocument;
    if (content is XmlElement) {
      return XmlDocument.parse((content as XmlElement).toXmlString());
    }
    if (content is String) {
      try {
        return XmlDocument.parse(content as String);
      } catch (_) {
        final htmlDoc = html_parser.parse(content as String);
        return XmlDocument.parse(htmlDoc.outerHtml);
      }
    }
    return XmlDocument.parse('<root/>');
  }

  static (String, String?) _splitRule(String rule) {
    // 结尾的 /@attribute 形式
    final attrMatch = RegExp(r'/@(\w+)$').firstMatch(rule);
    if (attrMatch != null) {
      final selector = rule.substring(0, attrMatch.start);
      return (selector, attrMatch.group(1));
    }

    // 结尾的 /text() 形式
    if (rule.endsWith('/text()')) {
      return (rule.substring(0, rule.length - 7), null);
    }

    return (rule, null);
  }

  String getString(String rule) {
    if (rule.isEmpty) return '';
    try {
      final doc = _document;
      final (xpathExpr, attrName) = _splitRule(rule);
      final elements = _queryXPath(doc, xpathExpr);
      if (elements.isEmpty) return '';
      if (attrName != null) {
        return elements.first.getAttribute(attrName) ?? '';
      }
      return elements.first.innerText.trim();
    } catch (_) {
      return '';
    }
  }

  List<String> getStringList(String rule) {
    if (rule.isEmpty) return [];
    try {
      final doc = _document;
      final (xpathExpr, attrName) = _splitRule(rule);
      final elements = _queryXPath(doc, xpathExpr);
      if (attrName != null) {
        return elements.map((e) => e.getAttribute(attrName) ?? '').where((s) => s.isNotEmpty).toList();
      }
      return elements.map((e) => e.innerText.trim()).where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  List<dynamic> getElements(String rule) {
    if (rule.isEmpty) return [];
    try {
      final doc = _document;
      final (xpathExpr, _) = _splitRule(rule);
      return _queryXPath(doc, xpathExpr).cast<dynamic>();
    } catch (_) {
      return [];
    }
  }

  List<XmlElement> _queryXPath(dynamic node, String xpath) {
    if (xpath.startsWith('//')) {
      final name = xpath.substring(2).trim();
      return _deepSearch(node, name);
    }
    if (xpath.startsWith('/')) {
      final parts = xpath.substring(1).split('/').where((s) => s.isNotEmpty).toList();
      return _navigatePath(node, parts);
    }
    return _deepSearch(node, xpath);
  }

  List<XmlElement> _deepSearch(dynamic node, String name) {
    final results = <XmlElement>[];
    if (node is XmlElement) {
      if (name == '*' || node.name.local == name) {
        results.add(node);
      }
      for (final child in node.childElements) {
        results.addAll(_deepSearch(child, name));
      }
    } else if (node is XmlDocument) {
      for (final child in node.childElements) {
        results.addAll(_deepSearch(child, name));
      }
    }
    return results;
  }

  List<XmlElement> _navigatePath(dynamic node, List<String> parts) {
    if (parts.isEmpty) return [];
    final name = parts.first;
    final remaining = parts.skip(1).toList();

    List<XmlElement> current;
    if (node is XmlDocument) {
      current = node.childElements.where((e) => name == '*' || e.name.local == name).toList();
    } else if (node is XmlElement) {
      current = node.childElements.where((e) => name == '*' || e.name.local == name).toList();
    } else {
      return [];
    }

    if (remaining.isEmpty) return current;

    final results = <XmlElement>[];
    for (final el in current) {
      results.addAll(_navigatePath(el, remaining));
    }
    return results;
  }
}
