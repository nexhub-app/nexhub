/// JS 沙箱引擎：基于 flutter_js 执行书源内嵌的 `@js` / `<js>` 脚本。
library;

import 'package:flutter_js/flutter_js.dart';

class JsEngine {
  JavascriptRuntime? _runtime;

  JavascriptRuntime get runtime {
    _runtime ??= getJavascriptRuntime();
    return _runtime!;
  }

  String eval(String jsStr, {Map<String, dynamic>? bindings}) {
    try {
      if (bindings != null) {
        for (final entry in bindings.entries) {
          runtime.evaluate('var ${entry.key} = ${_toJsValue(entry.value)};');
        }
      }
      final result = runtime.evaluate(jsStr);
      if (result.isError) {
        return '';
      }
      return result.stringResult;
    } catch (e) {
      return '';
    }
  }

  String evalWithResult(String jsStr, {Map<String, dynamic>? bindings}) {
    try {
      if (bindings != null) {
        for (final entry in bindings.entries) {
          runtime.evaluate('var ${entry.key} = ${_toJsValue(entry.value)};');
        }
      }
      final result = runtime.evaluate(jsStr);
      if (result.isError) {
        return '';
      }
      return result.stringResult;
    } catch (_) {
      return '';
    }
  }

  String _toJsValue(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return '"${_escapeJs(value)}"';
    if (value is num) return value.toString();
    if (value is bool) return value.toString();
    if (value is List) {
      final items = value.map(_toJsValue).join(',');
      return '[$items]';
    }
    if (value is Map) {
      final entries = value.entries.map((e) => '"${_escapeJs(e.key.toString())}":${_toJsValue(e.value)}').join(',');
      return '{$entries}';
    }
    return '"${_escapeJs(value.toString())}"';
  }

  String _escapeJs(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }

  void dispose() {
    _runtime?.dispose();
    _runtime = null;
  }
}
