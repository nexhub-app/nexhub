/// RSS 更新检测器（文档 §10.2 + 16.13 RSS 更新通知）。
///
/// 定期轮询已订阅的 RSS 源，对比上次记录的最新条目标题，
/// 检测到新条目时通过 [ChangeNotifier] 驱动 UI 显示未读数 badge，
/// 并通过回调触发应用内通知（SnackBar）。
///
/// 设计说明：
/// - 仅前台轮询（Timer.periodic），不引入 workmanager。
/// - 不依赖 flutter_local_notifications（不支持 Windows），
///   通知方式由调用方决定（应用内 SnackBar / banner / 等）。
/// - 持久化每条 feed 的 lastItemTitle + lastCheckedAt + newCount，
///   key = `rss_feed_states_v1`。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../comic/models/reader_preferences.dart';
import 'rss_feed.dart';
import 'rss_manager.dart';

/// 单条 RSS 订阅源的检测状态。
class RssFeedState {
  /// 最新已记录的条目标题（用于去重对比）。
  final String? lastItemTitle;

  /// 上次检测时间（毫秒时间戳）。
  final int? lastCheckedAt;

  /// 未读新条目数（用户查看后清零）。
  final int newCount;

  const RssFeedState({
    this.lastItemTitle,
    this.lastCheckedAt,
    this.newCount = 0,
  });

  RssFeedState copyWith({
    String? lastItemTitle,
    int? lastCheckedAt,
    int? newCount,
  }) =>
      RssFeedState(
        lastItemTitle: lastItemTitle ?? this.lastItemTitle,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
        newCount: newCount ?? this.newCount,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lastItemTitle': lastItemTitle,
        'lastCheckedAt': lastCheckedAt,
        'newCount': newCount,
      };

  factory RssFeedState.fromJson(Map<String, dynamic> json) => RssFeedState(
        lastItemTitle: json['lastItemTitle'] as String?,
        lastCheckedAt: json['lastCheckedAt'] as int?,
        newCount: json['newCount'] as int? ?? 0,
      );
}

/// 轮询间隔预设。
enum RssUpdateInterval {
  minutes15,
  minutes30,
  hour1,
  hours2,
  hours4;

  Duration get duration => switch (this) {
        RssUpdateInterval.minutes15 => const Duration(minutes: 15),
        RssUpdateInterval.minutes30 => const Duration(minutes: 30),
        RssUpdateInterval.hour1 => const Duration(hours: 1),
        RssUpdateInterval.hours2 => const Duration(hours: 2),
        RssUpdateInterval.hours4 => const Duration(hours: 4),
      };

  String get l10nKey => switch (this) {
        RssUpdateInterval.minutes15 => 'interval15m',
        RssUpdateInterval.minutes30 => 'interval30m',
        RssUpdateInterval.hour1 => 'interval1h',
        RssUpdateInterval.hours2 => 'interval2h',
        RssUpdateInterval.hours4 => 'interval4h',
      };
}

/// RSS 更新检测器——全应用单例（Provider 注入）。
class RssUpdateChecker extends ChangeNotifier {
  RssUpdateChecker({
    required this.rssManager,
    PrefsBackend? backend,
  }) : _backend = backend ?? const SharedPrefsBackend();

  final RssManager rssManager;
  final PrefsBackend _backend;

  static const String _stateKey = 'rss_feed_states_v1';
  static const String _settingsKey = 'rss_update_settings_v1';

  final Map<String, RssFeedState> _states = {};
  bool _enabled = false;
  RssUpdateInterval _interval = RssUpdateInterval.hour1;
  Timer? _timer;

  /// 是否启用更新检测。
  bool get enabled => _enabled;

  /// 当前轮询间隔。
  RssUpdateInterval get interval => _interval;

  /// 所有 feed 的状态（只读）。
  Map<String, RssFeedState> get states => Map.unmodifiable(_states);

  /// 某条 feed 的未读数。
  int newCountFor(String feedId) => _states[feedId]?.newCount ?? 0;

  /// 总未读数（所有 feed 之和）。
  int get totalNewCount =>
      _states.values.fold(0, (sum, s) => sum + s.newCount);

  /// 新条目检测回调（由 UI 层订阅以触发 SnackBar / badge）。
  VoidCallback? onNewItemsDetected;

  /// 初始化：加载持久化状态 + 设置 + 若启用则启动定时器。
  Future<void> init() async {
    await _loadStates();
    await _loadSettings();
    if (_enabled) _startTimer();
    notifyListeners();
  }

  /// 设置启用状态。
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (value) {
      _startTimer();
    } else {
      _stopTimer();
    }
    await _saveSettings();
    notifyListeners();
  }

  /// 设置轮询间隔。
  Future<void> setInterval(RssUpdateInterval value) async {
    _interval = value;
    if (_enabled) {
      _stopTimer();
      _startTimer();
    }
    await _saveSettings();
    notifyListeners();
  }

  /// 标记某条 feed 的未读数清零（用户查看后调用）。
  Future<void> markRead(String feedId) async {
    final s = _states[feedId];
    if (s == null || s.newCount == 0) return;
    _states[feedId] = s.copyWith(newCount: 0);
    await _saveStates();
    notifyListeners();
  }

  /// 立即执行一次检测（忽略定时器）。
  Future<void> checkAllFeeds() async {
    for (final feed in rssManager.feeds) {
      await _checkFeed(feed);
    }
    await _saveStates();
    notifyListeners();
  }

  /// 检测单条 feed 的新条目。
  ///
  /// 对比当前最新条目标题与上次记录的 lastItemTitle，
  /// 若不同则计算新条目数（直到遇到 lastItemTitle 为止）。
  Future<void> _checkFeed(RssFeed feed) async {
    try {
      final parsed = await rssManager.fetchFeed(feed);
      final items = parsed.items;
      if (items.isEmpty) return;

      final currentLatest = items.first.title;
      final prevState = _states[feed.id];
      final lastKnown = prevState?.lastItemTitle;

      // 首次记录：不报新条目，仅记录当前最新
      if (lastKnown == null) {
        _states[feed.id] = RssFeedState(
          lastItemTitle: currentLatest,
          lastCheckedAt: DateTime.now().millisecondsSinceEpoch,
          newCount: 0,
        );
        return;
      }

      // 最新标题相同：无新条目
      if (currentLatest == lastKnown) {
        _states[feed.id] = prevState!.copyWith(
          lastCheckedAt: DateTime.now().millisecondsSinceEpoch,
        );
        return;
      }

      // 计算新条目数：从最新开始往后找，直到遇到 lastKnown 或列表结束
      int newCount = 0;
      for (final item in items) {
        if (item.title == lastKnown) break;
        newCount++;
      }

      // 若 lastKnown 不在当前列表中（可能被源清理），视为全部新条目
      if (newCount == items.length) {
        newCount = items.length;
      }

      final prevNewCount = prevState?.newCount ?? 0;
      _states[feed.id] = RssFeedState(
        lastItemTitle: currentLatest,
        lastCheckedAt: DateTime.now().millisecondsSinceEpoch,
        newCount: prevNewCount + newCount,
      );

      if (newCount > 0) {
        onNewItemsDetected?.call();
      }
    } catch (_) {
      // 网络错误等忽略，下次再试
    }
  }

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(_interval.duration, (_) => checkAllFeeds());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _loadStates() async {
    final raw = await _backend.get(_stateKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _states.clear();
      for (final entry in map.entries) {
        _states[entry.key] =
            RssFeedState.fromJson(entry.value as Map<String, dynamic>);
      }
    } catch (_) {
      // 损坏数据忽略
    }
  }

  Future<void> _saveStates() async {
    final map = <String, dynamic>{};
    for (final entry in _states.entries) {
      map[entry.key] = entry.value.toJson();
    }
    await _backend.set(_stateKey, jsonEncode(map));
  }

  Future<void> _loadSettings() async {
    final raw = await _backend.get(_settingsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _enabled = map['enabled'] as bool? ?? false;
      final intervalIndex = map['interval'] as int? ?? 2;
      _interval = RssUpdateInterval.values
          .elementAtOrNull(intervalIndex) ??
          RssUpdateInterval.hour1;
    } catch (_) {
      // 损坏数据忽略
    }
  }

  Future<void> _saveSettings() async {
    final map = <String, dynamic>{
      'enabled': _enabled,
      'interval': _interval.index,
    };
    await _backend.set(_settingsKey, jsonEncode(map));
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}
