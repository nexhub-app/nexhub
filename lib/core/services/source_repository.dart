import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/plugin_config.dart';
import '../../features/shuyuan/shuyuan_adapter.dart';
import '../../features/shuyuan/shuyuan_source_service.dart';

/// 已加载的源仓库（内存级，持久化到 Hive 在 Phase 6 实现）。
///
/// 负责：
/// - 从 assets 加载内置源 JSON
/// - 按类型过滤
/// - 向上层提供 activeSources / getById
/// - 作为单一真源被 MediaApiService / 各模块浏览页消费
///
/// 继承 [ChangeNotifier]：启用/禁用/隐藏等状态变更后通知 UI 刷新。
class SourceRepository extends ChangeNotifier {
  final List<PluginConfig> _configs;
  final List<PluginConfig> _imported = <PluginConfig>[];

  SourceRepository(this._configs);

  List<PluginConfig> get all =>
      <PluginConfig>[..._configs, ..._imported];

  List<PluginConfig> get importedSources =>
      List<PluginConfig>.unmodifiable(_imported);

  /// 活跃源（已启用 + 未弃用 + 未隐藏）。
  List<PluginConfig> get activeSources =>
      all.where((c) => c.isEnabled && !c.isDeprecated && !c.isHidden).toList();

  List<PluginConfig> byType(SourceType type) =>
      activeSources.where((c) => c.type == type).toList();

  PluginConfig? getById(String id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 从 assets 加载 `plugins/builtin/` 下所有 .json 源。
  static Future<SourceRepository> loadBuiltins() async {
    const manifestKey = 'AssetManifest.json';
    final manifest = await rootBundle.loadString(manifestKey);
    final Map<String, dynamic> map =
        jsonDecode(manifest) as Map<String, dynamic>;
    final paths = map.keys
        .where((p) => p.startsWith('plugins/builtin/') && p.endsWith('.json'))
        .toList();
    debugPrint('[SourceRepository] discovered ${paths.length} builtin source '
        'assets: $paths');

    final configs = <PluginConfig>[];
    for (final path in paths) {
      try {
        final rawRaw = await rootBundle.loadString(path);
        // B6: 去除 UTF-8 BOM。rootBundle.loadString 内部用 utf8.decode，不会自动
        // 剥离 BOM，带 BOM 的源会被解析成 "\uFEFF{...}" 而导致 JSON 解析失败。
        // 这是旧版「源损坏」的根因之一，这里加一道熔丝，带 BOM 也能正常加载。
        final raw =
            rawRaw.startsWith('\uFEFF') ? rawRaw.substring(1) : rawRaw;
        final config = _parseSource(raw, path);
        if (config != null) configs.add(config);
      } on Object catch (e) {
        // 单个源损坏不影响整体启动；记录日志便于排查。
        debugPrint('[SourceRepository] $path failed to load: $e');
      }
    }
    debugPrint('[SourceRepository] loaded ${configs.length} builtin sources '
        '(${configs.where((c) => c.isEnabled).length} enabled)');
    return SourceRepository(configs);
  }

  /// 解析单个源 JSON 为 [PluginConfig]，返回 null 表示应跳过。
  ///
  /// - 含 `bookSourceName` 且缺 `type` → 视为 Legado 书源，转 [PluginConfig]
  ///   （B7：golden 小说源即 Legado 格式，旧版直接 `PluginConfig.fromJson`
  ///   会因缺 type 抛异常被丢弃，导致小说源全部失效）。
  /// - 否则按 [PluginConfig] 解析；`validate()` 失败则跳过并记录。
  static PluginConfig? _parseSource(String raw, String path) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } on Object {
      debugPrint('[SourceRepository] $path is not valid JSON, skipped');
      return null;
    }
    // B7: Legado 书源识别。
    if (json['bookSourceName'] != null && !json.containsKey('type')) {
      try {
        final shuyuan = ShuyuanSource.fromJson(json);
        final config = ShuyuanAdapter.toPluginConfig(shuyuan);
        debugPrint('[SourceRepository] $path loaded as Legado book source: '
            '${config.name}');
        return config;
      } on Object catch (e) {
        debugPrint('[SourceRepository] $path Legado parse failed: $e');
        return null;
      }
    }
    final config = PluginConfig.fromJsonString(raw);
    final errors = config.validate();
    if (errors.isEmpty) return config;
    debugPrint('[SourceRepository] $path validation failed: $errors');
    return null;
  }

  /// 测试注入用。
  factory SourceRepository.fromJsonList(List<Map<String, dynamic>> list) {
    final configs = list.map(PluginConfig.fromJson).toList();
    return SourceRepository(configs);
  }

  static const String _importedKey = 'imported_sources_v1';
  static const String _stateOverridesKey = 'source_state_overrides_v1';

  /// 源状态覆盖（启用/隐藏），持久化到 SharedPreferences。
  /// key = sourceId, value = {enabled: bool, isHidden: bool}
  final Map<String, Map<String, dynamic>> _stateOverrides = {};

  /// 添加用户导入的源。
  ///
  /// **版本覆盖规则**（与「源即插件」迭代工作流一致）：
  /// - 同名（id 相同）导入源按 `version` 决策：
  ///   - 新版本 **≥** 已安装版本 → 替换（高版本升级 / 同版本重新导入以应用编辑）；
  ///   - 新版本 **<** 已安装版本 → 跳过，**不覆盖**（防止误装旧版把新源冲掉）。
  /// - 内置源（_configs）不可被导入覆盖。
  /// 源作者发新版只需把 JSON 里的 `version` 调大，用户重新导入即自动升级。
  void addSource(PluginConfig config) {
    if (_configs.any((c) => c.id == config.id)) {
      return; // 内置源不可被导入覆盖
    }
    final idx = _imported.indexWhere((c) => c.id == config.id);
    if (idx >= 0) {
      final existing = _imported[idx];
      if (config.version < existing.version) {
        debugPrint('[SourceRepository] skip import ${config.id}: '
            'v${config.version} < installed v${existing.version}');
        return; // 低版本不覆盖高版本
      }
      _imported[idx] = config; // 高版本或同版本 → 替换
      // 保留用户此前对该源设置的状态覆盖（启用/隐藏）。
      final override = _stateOverrides[config.id];
      if (override != null) {
        _applyOverride(
          config.id,
          enabled: override['enabled'] as bool?,
          isHidden: override['isHidden'] as bool?,
        );
      }
    } else {
      _imported.add(config);
    }
    _persistImported();
    notifyListeners();
  }

  /// Export user-imported sources as a JSON-serializable list.
  List<Map<String, dynamic>> exportToJson() =>
      _imported.map((c) => c.toJson()).toList();

  /// 更新已导入源的 name/baseUrl 字段（编辑对话框入口）。
  /// 内置源不可编辑（返回 false）；仅更新 _imported 中的条目并持久化。
  bool updateSource(String id, {String? name, String? baseUrl}) {
    final idx = _imported.indexWhere((c) => c.id == id);
    if (idx < 0) return false;
    final old = _imported[idx];
    final newSite = SiteConfig(
      domain: old.site.domain,
      baseUrl: baseUrl ?? old.site.baseUrl,
      userAgent: old.site.userAgent,
      cookies: old.site.cookies,
      headers: old.site.headers,
      mirrors: old.site.mirrors,
    );
    _imported[idx] = PluginConfig(
      id: old.id,
      name: name ?? old.name,
      type: old.type,
      responseType: old.responseType,
      useWebview: old.useWebview,
      site: newSite,
      parser: old.parser,
      routes: old.routes,
      selectors: old.selectors,
      category: old.category,
      stealthMode: old.stealthMode,
      antiHotlinking: old.antiHotlinking,
      webviewConfig: old.webviewConfig,
      deprecated: old.deprecated,
      enabled: old.enabled,
      enabledExplore: old.enabledExplore,
      isHidden: old.isHidden,
      migrationMessage: old.migrationMessage,
      engine: old.engine,
      version: old.version,
    );
    _persistImported();
    notifyListeners();
    return true;
  }

  /// 删除已导入的源（删除确认入口）。内置源不可删除（返回 false）。
  bool removeSource(String id) {
    final idx = _imported.indexWhere((c) => c.id == id);
    if (idx < 0) return false;
    _imported.removeAt(idx);
    _stateOverrides.remove(id);
    _persistImported();
    _persistStateOverrides();
    notifyListeners();
    return true;
  }

  /// Import sources from a parsed JSON list (merge, dedup by id via addSource).
  void importFromList(List<dynamic> items) {
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      addSource(PluginConfig.fromJson(item));
    }
  }

  /// 启动时从持久化层加载用户导入的源 + 状态覆盖。
  Future<void> loadImported() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_importedKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final e in list) {
          _imported.add(PluginConfig.fromJson(e as Map<String, dynamic>));
        }
      } catch (_) {
        // 损坏数据忽略
      }
    }

    // 加载状态覆盖并应用到内存中的源
    final stateRaw = prefs.getString(_stateOverridesKey);
    if (stateRaw != null) {
      try {
        final map = jsonDecode(stateRaw) as Map<String, dynamic>;
        _stateOverrides.addAll(
          map.map((k, v) => MapEntry(k, v as Map<String, dynamic>)),
        );
        _applyStateOverrides();
      } catch (_) {
        // 损坏数据忽略
      }
    }
    notifyListeners();
  }

  /// 将状态覆盖应用到内存中的源（替换 _configs / _imported 中的条目）。
  void _applyStateOverrides() {
    for (final entry in _stateOverrides.entries) {
      final id = entry.key;
      final state = entry.value;
      final enabled = state['enabled'] as bool?;
      final isHidden = state['isHidden'] as bool?;
      _applyOverride(id, enabled: enabled, isHidden: isHidden);
    }
  }

  void _applyOverride(
    String id, {
    bool? enabled,
    bool? isHidden,
  }) {
    void replaceIn(List<PluginConfig> list) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id == id) {
          list[i] = list[i].copyWith(
            enabled: enabled,
            isHidden: isHidden,
          );
          break;
        }
      }
    }

    replaceIn(_configs);
    replaceIn(_imported);
  }

  /// 设置源的启用/禁用状态。
  Future<void> setEnabled(String id, bool enabled) async {
    _applyOverride(id, enabled: enabled);
    _stateOverrides[id] = <String, dynamic>{
      ..._stateOverrides[id] ?? <String, dynamic>{},
      'enabled': enabled,
    };
    await _persistStateOverrides();
    notifyListeners();
  }

  /// 设置源的隐藏/显示状态。
  Future<void> setHidden(String id, bool hidden) async {
    _applyOverride(id, isHidden: hidden);
    _stateOverrides[id] = <String, dynamic>{
      ..._stateOverrides[id] ?? <String, dynamic>{},
      'isHidden': hidden,
    };
    await _persistStateOverrides();
    notifyListeners();
  }

  /// 一键启用推荐源：启用所有未弃用、非演示的内置源，返回本次新启用的数量。
  ///
  /// 推荐源 = 内置源中未标记 deprecated 且 id 不含 `example` 的源。
  /// 已启用的保持启用；覆盖写入持久化并通知 UI 刷新。
  Future<int> enableRecommendedSources() async {
    final targets = _configs.where(
      (c) => !c.isDeprecated && !c.id.toLowerCase().contains('example'),
    );
    var enabledCount = 0;
    for (final c in targets) {
      if (!c.isEnabled) {
        _applyOverride(c.id, enabled: true);
        enabledCount++;
      }
      _stateOverrides[c.id] = <String, dynamic>{
        ..._stateOverrides[c.id] ?? <String, dynamic>{},
        'enabled': true,
      };
    }
    if (enabledCount > 0) {
      await _persistStateOverrides();
      notifyListeners();
    }
    return enabledCount;
  }

  Future<void> _persistImported() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _imported.map((c) => c.toJson()).toList();
    await prefs.setString(_importedKey, jsonEncode(list));
  }

  Future<void> _persistStateOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateOverridesKey, jsonEncode(_stateOverrides));
  }
}
