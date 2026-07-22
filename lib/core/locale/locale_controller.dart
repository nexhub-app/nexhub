/// Locale preference notifier persisted to the Hive `settings` box.
///
/// Stores the user's interface language choice ('zh' / 'en' / 'system').
/// Persisted as a plain String under the key `app_locale`.
library;

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

/// User-selectable interface language options.
enum LocaleOption { system, chinese, english }

/// Provider-backed notifier persisting the locale choice to the Hive
/// `settings` box (key = `app_locale`).
///
/// [effectiveLocale] returns null for [LocaleOption.system] so that Flutter /
/// MaterialApp falls back to the platform locale.
class LocaleController extends ChangeNotifier {
  LocaleController() {
    _load();
  }

  // 默认中文：应用面向中文用户，且「跟随系统」在英文区域（如英文 Windows）
  // 会回落到英文，导致界面“未汉化”。默认中文可保证首屏即中文，
  // 用户仍可在 设置→语言 切换为 英文 / 跟随系统。
  LocaleOption _option = LocaleOption.chinese;

  LocaleOption get option => _option;

  /// Returns the effective [Locale] to feed into MaterialApp.locale.
  ///
  /// Returns null for [LocaleOption.system] so MaterialApp resolves the
  /// locale from the platform.
  Locale? get effectiveLocale {
    switch (_option) {
      case LocaleOption.system:
        return null;
      case LocaleOption.chinese:
        return const Locale('zh');
      case LocaleOption.english:
        return const Locale('en');
    }
  }

  static const _boxName = 'settings';
  static const _key = 'app_locale';

  void _load() {
    try {
      // Guard: the settings box is opened in main() before runApp, but be
      // defensive in case this notifier is constructed earlier in tests.
      if (!Hive.isBoxOpen(_boxName)) return;
      final box = Hive.box(_boxName);
      final raw = box.get(_key);
      if (raw is String) {
        _option = _parseOption(raw);
      }
    } catch (_) {
      // Keep default on error.
    }
  }

  Future<void> load() async {
    _load();
  }

  Future<void> setOption(LocaleOption option) async {
    if (_option == option) return;
    _option = option;
    notifyListeners();
    try {
      if (!Hive.isBoxOpen(_boxName)) return;
      final box = Hive.box(_boxName);
      await box.put(_key, _serializeOption(option));
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  static String _serializeOption(LocaleOption option) {
    switch (option) {
      case LocaleOption.system:
        return 'system';
      case LocaleOption.chinese:
        return 'zh';
      case LocaleOption.english:
        return 'en';
    }
  }

  static LocaleOption _parseOption(String raw) {
    switch (raw) {
      case 'zh':
        return LocaleOption.chinese;
      case 'en':
        return LocaleOption.english;
      case 'system':
      default:
        return LocaleOption.system;
    }
  }
}
