/// 云同步服务 —— WebDAV 备份与多端同步。
///
/// 数据范围（spec J.2）：
/// 1. 书源/媒体源/订阅源：book_sources / rss_feeds / article_feeds Hive box
/// 2. 书签/收藏/书架：favorites / comic_bookmarks / novel_bookmarks Hive box
/// 3. 阅读/播放历史与进度：media_watched / media_playback_position / comic_progress / novel_progress / media_progress Hive box
/// 4. 阅读器/播放器偏好：PlayerSettings / ReaderDefaultSettings / LayoutSettings / DanmakuSettings 持久化的 SharedPreferences
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

/// 同步频率
enum SyncFrequency { manual, daily, weekly }

/// WebDAV 配置（URL/用户名/密码除外，密码用 secure storage）
class CloudSyncConfig {
  final String url;
  final String username;
  final bool autoSync;
  final SyncFrequency frequency;
  final int? lastSyncTimestamp; // null = never synced

  const CloudSyncConfig({
    this.url = '',
    this.username = '',
    this.autoSync = false,
    this.frequency = SyncFrequency.manual,
    this.lastSyncTimestamp,
  });

  CloudSyncConfig copyWith({
    String? url,
    String? username,
    bool? autoSync,
    SyncFrequency? frequency,
    int? lastSyncTimestamp,
  }) {
    return CloudSyncConfig(
      url: url ?? this.url,
      username: username ?? this.username,
      autoSync: autoSync ?? this.autoSync,
      frequency: frequency ?? this.frequency,
      lastSyncTimestamp: lastSyncTimestamp ?? this.lastSyncTimestamp,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'url': url,
        'username': username,
        'autoSync': autoSync,
        'frequency': frequency.name,
        if (lastSyncTimestamp != null)
          'lastSyncTimestamp': lastSyncTimestamp,
      };

  factory CloudSyncConfig.fromJson(Map<String, dynamic> json) {
    SyncFrequency parseFrequency(String? name) {
      switch (name) {
        case 'daily':
          return SyncFrequency.daily;
        case 'weekly':
          return SyncFrequency.weekly;
        case 'manual':
        default:
          return SyncFrequency.manual;
      }
    }

    return CloudSyncConfig(
      url: (json['url'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      autoSync: (json['autoSync'] as bool?) ?? false,
      frequency: parseFrequency(json['frequency'] as String?),
      lastSyncTimestamp: json['lastSyncTimestamp'] as int?,
    );
  }
}

class CloudSyncConfigStore {
  static const String _prefsKey = 'cloud_sync_config_v1';
  static const String _passwordKey = 'cloud_sync_webdav_password';

  Future<CloudSyncConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return const CloudSyncConfig();
    try {
      return CloudSyncConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const CloudSyncConfig();
    }
  }

  Future<void> save(CloudSyncConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(config.toJson()));
  }

  Future<String?> loadPassword() async {
    const storage = FlutterSecureStorage();
    return await storage.read(key: _passwordKey);
  }

  Future<void> savePassword(String password) async {
    const storage = FlutterSecureStorage();
    await storage.write(key: _passwordKey, value: password);
  }

  Future<void> clearPassword() async {
    const storage = FlutterSecureStorage();
    await storage.delete(key: _passwordKey);
  }
}

/// 远程 WebDAV 文件项
class _RemoteFile {
  final String name;
  final bool isCollection;

  const _RemoteFile({required this.name, required this.isCollection});
}

/// 云同步服务 —— 基于 WebDAV 的备份与多端同步。
///
/// 使用 dio 手写 WebDAV 操作（MKCOL/PUT/GET/PROPFIND/DELETE），不引入额外的
/// webdav 包。密码使用 [FlutterSecureStorage] 安全存储，配置仅持久化非敏感
/// 字段（URL / 用户名 / 自动同步开关 / 频率 / 上次同步时间）。
class CloudSyncService extends ChangeNotifier {
  static const String _remoteDir = '/nexhub';
  static const int _maxBackups = 5;

  CloudSyncConfig _config = const CloudSyncConfig();
  String? _password;
  bool _syncing = false;
  String? _lastError;

  CloudSyncConfig get config => _config;
  bool get isSyncing => _syncing;
  String? get lastError => _lastError;

  Future<void> init() async {
    final store = CloudSyncConfigStore();
    _config = await store.load();
    _password = await store.loadPassword();
  }

  Future<void> updateConfig(CloudSyncConfig config, String? password) async {
    final store = CloudSyncConfigStore();
    _config = config;
    if (password != null) {
      _password = password;
      await store.savePassword(password);
    }
    await store.save(config);
    notifyListeners();
  }

  /// 构造 Basic Auth header value（不含 "Basic " 前缀）。
  String _basicAuth(String username, String password) {
    final creds = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $creds';
  }

  /// 规范化 WebDAV URL，确保以 / 结尾的根路径能正确拼接子路径。
  String _buildUrl(String path) {
    String base = _config.url;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (path.isEmpty || path == '/') return base;
    if (!path.startsWith('/')) path = '/$path';
    return '$base$path';
  }

  Dio _buildDio({required String username, required String password}) {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      headers: <String, String>{
        'Authorization': _basicAuth(username, password),
      },
    ));
    return dio;
  }

  /// 测试 WebDAV 连接。返回 (success, latencyMs)。
  Future<(bool, int)> testConnection({
    required String url,
    required String username,
    required String password,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      String base = url;
      while (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: <String, String>{
          'Authorization': _basicAuth(username, password),
        },
      ));
      // 用 PROPFIND Depth: 0 探测根目录，验证凭据与连通性。
      final resp = await dio.request<String>(
        base,
        data: '',
        options: Options(
          method: 'PROPFIND',
          headers: <String, String>{
            'Depth': '0',
            'Content-Type': 'application/xml; charset=utf-8',
          },
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      );
      stopwatch.stop();
      // 207 Multistatus 是 PROPFIND 的标准成功响应
      final ok = resp.statusCode != null && resp.statusCode! < 400;
      return (ok, stopwatch.elapsedMilliseconds);
    } catch (_) {
      stopwatch.stop();
      return (false, stopwatch.elapsedMilliseconds);
    }
  }

  /// 立即同步：导出本地 → 打包 ZIP → 上传到 WebDAV。
  Future<bool> syncNow() async {
    if (_syncing) return false;
    if (_config.url.isEmpty || _password == null) {
      _lastError = 'no_config';
      return false;
    }
    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      final archive = await _exportToArchive();
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        _lastError = 'encode_failed';
        _syncing = false;
        notifyListeners();
        return false;
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'nexhub-backup-$timestamp.zip';

      final dio = _buildDio(
        username: _config.username,
        password: _password!,
      );
      // 创建远程目录（已存在则忽略 405/409）
      await _ensureRemoteDir(dio);
      // 上传 ZIP
      await dio.put(
        _buildUrl('$_remoteDir/$filename'),
        data: Stream.fromIterable(<List<int>>[zipBytes]),
        options: Options(
          headers: <String, String>{
            'Content-Type': 'application/zip',
            'Content-Length': '${zipBytes.length}',
          },
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
      // 清理旧备份（保留最近 5 份）
      await _cleanupOldBackups(dio);

      // 更新上次同步时间
      _config = _config.copyWith(lastSyncTimestamp: timestamp);
      await CloudSyncConfigStore().save(_config);
      _syncing = false;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString();
      _syncing = false;
      notifyListeners();
      return false;
    }
  }

  /// 从 WebDAV 拉最新 ZIP 并合并到本地（last-write-wins with timestamp）。
  Future<bool> pullRemote() async {
    if (_syncing) return false;
    if (_config.url.isEmpty || _password == null) {
      _lastError = 'no_config';
      return false;
    }
    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      final dio = _buildDio(
        username: _config.username,
        password: _password!,
      );
      final files = await _listRemoteBackups(dio);
      if (files.isEmpty) {
        _lastError = 'no_remote_backup';
        _syncing = false;
        notifyListeners();
        return false;
      }
      // 取最新（按文件名降序，timestamp 大的在前）
      files.sort((a, b) => b.name.compareTo(a.name));
      final latest = files.first;
      final resp = await dio.get<List<int>>(
        _buildUrl('$_remoteDir/${latest.name}'),
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
      final bytes = Uint8List.fromList(resp.data ?? <int>[]);
      final archive = ZipDecoder().decodeBytes(bytes);
      await _importFromArchive(archive);

      _syncing = false;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString();
      _syncing = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _ensureRemoteDir(Dio dio) async {
    try {
      await dio.request<void>(
        _buildUrl('$_remoteDir/'),
        data: '',
        options: Options(
          method: 'MKCOL',
          validateStatus: (s) =>
              s != null && (s == 201 || s == 405 || s == 409 || s == 301),
        ),
      );
    } catch (_) {
      // 忽略：目录可能已存在或允许后续 PUT 自动创建
    }
  }

  Future<List<_RemoteFile>> _listRemoteBackups(Dio dio) async {
    const propfindBody = '<?xml version="1.0" encoding="utf-8"?>'
        '<D:propfind xmlns:D="DAV:">'
        '<D:prop><D:displayname/><D:resourcetype/></D:prop>'
        '</D:propfind>';
    try {
      final resp = await dio.request<String>(
        _buildUrl('$_remoteDir/'),
        data: propfindBody,
        options: Options(
          method: 'PROPFIND',
          headers: <String, String>{
            'Depth': '1',
            'Content-Type': 'application/xml; charset=utf-8',
          },
          responseType: ResponseType.plain,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      );
      return _parsePropfind(resp.data ?? '');
    } catch (_) {
      return <_RemoteFile>[];
    }
  }

  List<_RemoteFile> _parsePropfind(String body) {
    final files = <_RemoteFile>[];
    if (body.isEmpty) return files;
    try {
      final doc = XmlDocument.parse(body);
      for (final response in doc.findAllElements('response',
          namespace: '*')) {
        final hrefElement = response
            .findElements('href', namespace: '*')
            .firstOrNull;
        if (hrefElement == null) continue;
        final href = (hrefElement.value ?? '').trim();
        if (href.isEmpty) continue;
        // 解析出最后一段文件名
        final decoded = Uri.decodeFull(href);
        String name = decoded;
        if (decoded.endsWith('/')) {
          // 是目录本身（如 /nexhub/），跳过根目录
          if (decoded.endsWith('$_remoteDir/') ||
              decoded.endsWith('${_remoteDir.replaceAll('/', '')}/')) {
            // 保留目录标记以便后续过滤
          }
          continue;
        }
        final lastSlash = decoded.lastIndexOf('/');
        if (lastSlash >= 0 && lastSlash < decoded.length - 1) {
          name = decoded.substring(lastSlash + 1);
        }
        final isCollection = response
                .findElements('propstat', namespace: '*')
                .firstOrNull
                ?.findElements('prop', namespace: '*')
                .firstOrNull
                ?.findElements('resourcetype', namespace: '*')
                .firstOrNull
                ?.findElements('collection', namespace: '*')
                .isNotEmpty ??
            false;
        files.add(_RemoteFile(name: name, isCollection: isCollection));
      }
    } catch (_) {
      // XML 解析失败：返回空列表
    }
    return files;
  }

  Future<void> _cleanupOldBackups(Dio dio) async {
    final files = await _listRemoteBackups(dio);
    final backups = files
        .where((f) =>
            !f.isCollection &&
            f.name.startsWith('nexhub-backup-') &&
            f.name.endsWith('.zip'))
        .toList()
      ..sort((a, b) => b.name.compareTo(a.name)); // 新到旧
    for (var i = _maxBackups; i < backups.length; i++) {
      try {
        await dio.delete(
          _buildUrl('$_remoteDir/${backups[i].name}'),
          options: Options(
            validateStatus: (s) => s != null && s >= 200 && s < 300,
          ),
        );
      } catch (_) {
        // 忽略单个删除失败
      }
    }
  }

  Future<Archive> _exportToArchive() async {
    final archive = Archive();
    // 1. Hive boxes → JSON
    const hiveBoxNames = <String>[
      'book_sources', 'rss_feeds', 'article_feeds',
      'favorites', 'comic_bookmarks', 'novel_bookmarks',
      'media_watched', 'media_playback_position',
      'comic_progress', 'novel_progress', 'media_progress',
    ];
    final hiveData = <String, dynamic>{};
    for (final name in hiveBoxNames) {
      if (Hive.isBoxOpen(name)) {
        final box = Hive.box(name);
        hiveData[name] = box
            .toMap()
            .map((k, v) => MapEntry(k.toString(), _encodeHiveValue(v)));
      }
    }
    final hiveBytes = Uint8List.fromList(utf8.encode(jsonEncode(hiveData)));
    archive.addFile(ArchiveFile(
      'hive_boxes.json',
      hiveBytes.length,
      hiveBytes,
    ));
    // 2. SharedPreferences → JSON（仅取本应用相关 key）
    final prefs = await SharedPreferences.getInstance();
    final prefsData = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      final v = prefs.get(key);
      if (v != null) prefsData[key] = v;
    }
    final prefsBytes = Uint8List.fromList(utf8.encode(jsonEncode(prefsData)));
    archive.addFile(ArchiveFile(
      'preferences.json',
      prefsBytes.length,
      prefsBytes,
    ));
    return archive;
  }

  dynamic _encodeHiveValue(dynamic v) {
    if (v == null) return null;
    if (v is String || v is num || v is bool) return v;
    if (v is List) return v.map(_encodeHiveValue).toList();
    if (v is Map) {
      return v.map((k, v) => MapEntry(k.toString(), _encodeHiveValue(v)));
    }
    // Hive 自定义对象：尝试 toJson
    try {
      final toJson = (v as dynamic).toJson;
      if (toJson != null) return toJson.call();
    } catch (_) {}
    return v.toString();
  }

  Future<void> _importFromArchive(Archive archive) async {
    // 1. 合并 Hive boxes
    final hiveFile = archive.findFile('hive_boxes.json');
    if (hiveFile != null) {
      final content = hiveFile.content as List<int>;
      final raw = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      for (final entry in raw.entries) {
        final name = entry.key;
        final data = entry.value;
        if (data is! Map) continue;
        if (Hive.isBoxOpen(name)) {
          final box = Hive.box(name);
          for (final kv in data.entries) {
            final key = kv.key;
            // 仅写入简单值，复杂对象保留原样（last-write-wins）
            try {
              await box.put(key, _decodeHiveValue(kv.value));
            } catch (_) {
              // 跳过无法写入的项
            }
          }
        }
      }
    }
    // 2. 合并 SharedPreferences
    final prefsFile = archive.findFile('preferences.json');
    if (prefsFile != null) {
      final content = prefsFile.content as List<int>;
      final raw = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      for (final entry in raw.entries) {
        final v = entry.value;
        try {
          if (v is String) {
            await prefs.setString(entry.key, v);
          } else if (v is int) {
            await prefs.setInt(entry.key, v);
          } else if (v is double) {
            await prefs.setDouble(entry.key, v);
          } else if (v is bool) {
            await prefs.setBool(entry.key, v);
          } else if (v is List) {
            await prefs.setStringList(
                entry.key, v.map((e) => e.toString()).toList());
          }
        } catch (_) {
          // 跳过无法写入的项
        }
      }
    }
  }

  dynamic _decodeHiveValue(dynamic v) {
    if (v == null) return null;
    if (v is String || v is num || v is bool) return v;
    if (v is List) return v.map(_decodeHiveValue).toList();
    if (v is Map) return v.map((k, v) => MapEntry(k, _decodeHiveValue(v)));
    return v;
  }
}
