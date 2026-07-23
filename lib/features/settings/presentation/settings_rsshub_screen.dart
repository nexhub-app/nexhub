/// RSSHub 设置页 —— 实例选择、自定义实例配置（多条管理 + 测试连接 + 删除）、故障排除。
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:nexhub/generated/app_localizations.dart';
import '../../../core/settings/rsshub_config.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_list_tile.dart';
import '../../../core/widgets/app_card.dart';

/// 预置的 RSSHub 实例列表。
class _PresetInstance {
  final String name;
  final String url;
  final bool isOfficial;

  const _PresetInstance({
    required this.name,
    required this.url,
    this.isOfficial = false,
  });
}

const List<_PresetInstance> _kPresetInstances = <_PresetInstance>[
  _PresetInstance(
    name: 'RSSHub (Official)',
    url: 'https://rsshub.app',
    isOfficial: true,
  ),
  _PresetInstance(
    name: 'RSSHub (rssforever)',
    url: 'https://rsshub.rssforever.com',
  ),
  _PresetInstance(
    name: 'RSSHub (moeyy)',
    url: 'https://rsshub.moeyy.cn',
  ),
  _PresetInstance(
    name: 'RSSHub (slarker)',
    url: 'https://hub.slarker.me',
  ),
  _PresetInstance(
    name: 'RSSHub (pseudoyu)',
    url: 'https://rsshub.pseudoyu.com',
  ),
];

class SettingsRssHubScreen extends StatefulWidget {
  const SettingsRssHubScreen({super.key});

  @override
  State<SettingsRssHubScreen> createState() => _SettingsRssHubScreenState();
}

class _SettingsRssHubScreenState extends State<SettingsRssHubScreen> {
  String? _selectedPresetUrl; // 当前选择的预置实例
  String _currentUrl = ''; // 当前生效的实例地址
  final List<String> _customInstances = <String>[]; // 自定义实例列表
  final TextEditingController _newCustomController = TextEditingController();
  final RssHubConfigStore _store = RssHubConfigStore();

  /// 测试连接状态：url -> 状态
  /// - "testing"：测试中
  /// - int：成功，值为延迟毫秒数
  /// - false：失败
  final Map<String, dynamic> _testStatus = <String, dynamic>{};
  bool _testingAll = false; // 一键测速进行中

  @override
  void initState() {
    super.initState();
    _store.load().then((config) {
      if (!mounted) return;
      setState(() {
        _customInstances.addAll(config.customInstances);
        // 旧数据迁移：若 useCustom 且 instanceUrl 不在 customInstances 中，补入
        if (config.useCustom &&
            config.instanceUrl.isNotEmpty &&
            !_customInstances.contains(config.instanceUrl)) {
          _customInstances.add(config.instanceUrl);
        }
        _currentUrl = config.instanceUrl.isNotEmpty
            ? config.instanceUrl
            : _kPresetInstances.first.url;
        _selectedPresetUrl =
            config.useCustom ? null : (_currentUrl.isNotEmpty ? _currentUrl : _kPresetInstances.first.url);
      });
    });
  }

  @override
  void dispose() {
    _newCustomController.dispose();
    super.dispose();
  }

  /// 持久化保存当前选择。
  Future<void> _persist() async {
    await _store.save(RssHubConfig(
      instanceUrl: _currentUrl,
      useCustom: _selectedPresetUrl == null,
      customInstances: _customInstances,
    ));
  }

  /// 测试实例连通性（HEAD 请求，5 秒超时），记录延迟毫秒数（项 10）。
  Future<void> _testConnection(String url) async {
    setState(() => _testStatus[url] = 'testing');
    final stopwatch = Stopwatch()..start();
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        followRedirects: true,
      ));
      final response = await dio.head<dynamic>(url);
      stopwatch.stop();
      final success = response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 400;
      final latency = stopwatch.elapsedMilliseconds;
      setState(() => _testStatus[url] = success ? latency : false);
    } on Object {
      stopwatch.stop();
      setState(() => _testStatus[url] = false);
    }
  }

  /// 一键测速：并发测试所有预置 + 自定义实例（项 8）。
  Future<void> _testAll() async {
    if (_testingAll) return;
    final l10n = AppLocalizations.of(context);
    final urls = <String>[
      ..._kPresetInstances.map((i) => i.url),
      ..._customInstances,
    ];
    if (urls.isEmpty) return;
    setState(() => _testingAll = true);
    await Future.wait(urls.map((u) => _testConnection(u)));
    if (!mounted) return;
    setState(() => _testingAll = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.rsshubTestAllDone(urls.length))),
    );
  }

  /// 添加自定义实例。
  void _addCustomInstance() {
    final url = _newCustomController.text.trim();
    if (url.isEmpty || _customInstances.contains(url)) return;
    setState(() {
      _customInstances.add(url);
      _newCustomController.clear();
    });
    _persist();
  }

  /// 删除自定义实例。
  void _removeCustomInstance(String url) {
    setState(() {
      _customInstances.remove(url);
      _testStatus.remove(url);
      // 若删除的是当前选中实例，回退到第一个预置
      if (_currentUrl == url) {
        _currentUrl = _kPresetInstances.first.url;
        _selectedPresetUrl = _kPresetInstances.first.url;
      }
    });
    _persist();
  }

  /// 选择实例（预置或自定义）。
  void _selectInstance(String url, {bool isCustom = false}) {
    setState(() {
      _currentUrl = url;
      _selectedPresetUrl = isCustom ? null : url;
    });
    _persist();
  }

  /// 恢复默认（清空全部自定义实例，回到官方预置）。
  void _restoreDefault() {
    setState(() {
      _customInstances.clear();
      _testStatus.clear();
      _currentUrl = _kPresetInstances.first.url;
      _selectedPresetUrl = _kPresetInstances.first.url;
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.rsshubSettingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        children: <Widget>[
          // ── 当前实例 ──
          Text(l10n.currentInstance,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  )),
          const SizedBox(height: AppTokens.spaceSm),
          AppCard(
            child: ListTile(
              title: Text(_currentUrl),
              subtitle: Text(_selectedPresetUrl == null
                  ? l10n.customInstance
                  : l10n.presetInstanceOfficial),
            ),
          ),

          // ── 预置实例 ──
          const SizedBox(height: AppTokens.spaceXl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(l10n.presetInstances,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        )),
              ),
              // 一键测速：测试所有预置 + 自定义实例（项 8）
              TextButton.icon(
                onPressed: _testingAll ? null : _testAll,
                icon: _testingAll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.speed),
                label: Text(
                    _testingAll ? l10n.rsshubTestingAll : l10n.rsshubTestAll),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          ..._kPresetInstances.map((instance) => _buildPresetTile(instance)),

          // ── 自定义实例 ──
          const SizedBox(height: AppTokens.spaceXl),
          Text(l10n.customInstance,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  )),
          const SizedBox(height: AppTokens.spaceSm),
          // 添加新自定义实例输入框（统一为带内嵌「+ 添加」按钮的输入框，项 8）
          TextField(
            controller: _newCustomController,
            decoration: InputDecoration(
              hintText: 'https://rsshub.example.com',
              prefixIcon: const Icon(Icons.link),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add),
                tooltip: l10n.add,
                onPressed: _addCustomInstance,
              ),
            ),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _addCustomInstance(),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          // 自定义实例列表
          if (_customInstances.isEmpty)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.spaceMd),
                child: Text(
                  l10n.noCustomInstances,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            )
          else
            ..._customInstances
                .map((url) => _buildCustomTile(url, l10n, scheme)),

          // 自定义实例区域的"恢复默认"按钮
          if (_customInstances.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppTokens.spaceMd),
            OutlinedButton.icon(
              onPressed: _restoreDefault,
              icon: const Icon(Icons.restore),
              label: Text(l10n.restoreDefault),
            ),
          ],

          // ── 故障排除 ──
          const SizedBox(height: AppTokens.spaceXl),
          Text(l10n.rsshubTroubleshoot,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  )),
          const SizedBox(height: AppTokens.spaceSm),
          AppCard(
            child: Text(
              l10n.rsshubTroubleshootHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetTile(_PresetInstance instance) {
    final l10n = AppLocalizations.of(context);
    final isSelected = _selectedPresetUrl == instance.url;
    final status = _testStatus[instance.url];

    return AppListTile(
      leading: CircleAvatar(
        backgroundColor:
            Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
        child: Icon(Icons.rss_feed, size: 18,
            color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(instance.name),
      subtitle: Text(instance.url),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 测试连接按钮
          _buildTestButton(instance.url, status),
          const SizedBox(width: AppTokens.spaceXs),
          if (instance.isOfficial)
            Container(
              margin: const EdgeInsets.only(right: AppTokens.spaceXs),
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l10n.presetInstanceOfficial,
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.primary),
              ),
            ),
          if (isSelected)
            Icon(Icons.check_circle,
                color: Theme.of(context).colorScheme.primary, size: 20)
          else
            Icon(Icons.radio_button_unchecked,
                color: Theme.of(context).colorScheme.outline, size: 20),
        ],
      ),
      onTap: () => _selectInstance(instance.url),
    );
  }

  Widget _buildCustomTile(String url, AppLocalizations l10n, ColorScheme scheme) {
    final isSelected = _currentUrl == url && _selectedPresetUrl == null;
    final status = _testStatus[url];

    return AppListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer.withValues(alpha: 0.5),
        child: Icon(Icons.rss_feed, size: 18, color: scheme.secondary),
      ),
      title: Text(url),
      subtitle: Text(l10n.customInstance),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildTestButton(url, status),
          const SizedBox(width: AppTokens.spaceXs),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 20, color: scheme.error),
            tooltip: l10n.delete,
            onPressed: () => _removeCustomInstance(url),
          ),
          if (isSelected)
            Icon(Icons.check_circle, color: scheme.primary, size: 20)
          else
            Icon(Icons.radio_button_unchecked,
                color: scheme.outline, size: 20),
        ],
      ),
      onTap: () => _selectInstance(url, isCustom: true),
    );
  }

  /// 测试连接按钮 + 延迟显示（项 10）。
  ///
  /// 状态映射：
  /// - "testing" → 进度指示器
  /// - int（延迟 ms）→ 成功图标 + 着色延迟文本（<300 绿 / 300-800 黄 / >800 红）
  /// - false → 失败图标 + 灰色"失败"文本
  /// - null → 未测试图标
  Widget _buildTestButton(String url, dynamic status) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    if (status == 'testing') {
      return const SizedBox(
        width: 20,
        height: 20,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // 延迟文本（成功 / 失败）
    Widget? latencyWidget;
    if (status is int) {
      final latencyColor = status < 300
          ? Colors.green
          : status <= 800
              ? Colors.orange
              : Colors.red;
      latencyWidget = Text(
        l10n.rsshubLatencyMs(status),
        style: TextStyle(
          fontSize: 12,
          color: latencyColor,
          fontWeight: FontWeight.w600,
        ),
      );
    } else if (status == false) {
      latencyWidget = Text(
        l10n.rsshubLatencyFailed,
        style: TextStyle(
          fontSize: 12,
          color: scheme.outline,
        ),
      );
    }

    final iconButton = IconButton(
      icon: Icon(
        status is int
            ? Icons.check_circle_outline
            : status == false
                ? Icons.error_outline
                : Icons.wifi_find_outlined,
        size: 20,
        color: status is int
            ? Colors.green
            : status == false
                ? scheme.error
                : scheme.onSurfaceVariant,
      ),
      tooltip: l10n.testConnection,
      onPressed: () => _testConnection(url),
    );

    if (latencyWidget == null) return iconButton;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        latencyWidget,
        iconButton,
      ],
    );
  }
}
