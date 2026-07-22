/// 下载管理器（文档 §10.1 / §10.3）。
///
/// 核心职责：
/// 1. 管理任务生命周期（addTask / cancel / pause / resume）。
/// 2. 持久化任务列表到 [DownloadStorage]。
/// 3. 每个任务写入 `.meta.json` 到下载目录，用于孤儿恢复。
/// 4. 清除记录精确规则（§10.3）：
///    - `clearAll(false)` → 清存储后立即 `recoverOrphanedDownloads()` 从 meta.json 重建 completed。
///    - `clearAll(true)` → 删文件 + meta.json，不恢复，两页皆空。
/// 5. 下载列表页过滤 completed 只显活跃；已下载内容页只显 completed。
///
/// 使用 [ChangeNotifier] 驱动 UI 更新。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/episode.dart';
import '../models/media_item.dart';
import '../models/plugin_config.dart';
import '../scraper/http_fetcher.dart';
import '../scraper/media_api_service.dart';
import '../services/source_repository.dart';
import 'comic_download_handler.dart';
import 'download_file_system.dart';
import 'download_format_preferences.dart';
import 'download_handler.dart';
import 'download_settings.dart';
import 'download_storage.dart';
import 'download_task.dart';
import 'media_download_handler.dart';
import 'novel_download_handler.dart';

/// 等待队列中的下载项（因达到最大并发而暂存）。
class _QueuedDownload {
  final DownloadTask task;
  final MediaItem item;
  final List<Episode> chapters;

  _QueuedDownload(this.task, this.item, this.chapters);
}

/// 下载管理器——全应用单例（Provider 注入）。
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.storage,
    required this.fs,
    required this.service,
    required this.sourceRepo,
    DownloadFormatPreferences? formatPrefs,
    DownloadSettings? settings,
  })  : _formatPrefs = formatPrefs ?? const DownloadFormatPreferences.defaults(),
        _settings = settings ?? const DownloadSettings.defaults();

  final DownloadStorage storage;
  final DownloadFileSystem fs;
  final MediaApiService service;
  final SourceRepository sourceRepo;
  DownloadFormatPreferences _formatPrefs;

  DownloadFormatPreferences get formatPrefs => _formatPrefs;

  /// 下载设置（最大并发 / 线程数 / 路径 / 下载器类型），来自 [DownloadSettingsStore]。
  DownloadSettings _settings;

  /// 当前生效的下载设置。
  DownloadSettings get settings => _settings;

  /// 正在执行中的下载数量（受 maxConcurrent 约束）。
  int _running = 0;

  /// 因达到最大并发而等待的下载队列。
  final List<_QueuedDownload> _pending = <_QueuedDownload>[];

  /// 因未连接 WiFi 而挂起的下载队列（仅 WiFi 模式下使用）。
  final List<_QueuedDownload> _waitingForWifi = <_QueuedDownload>[];

  /// 暂停令牌：记录用户在下载过程中点击暂停的任务 ID。
  /// [_executeDownload] 完成时会检查此集合，若任务被暂停则保持 paused 状态。
  final Map<String, bool> _pauseTokens = <String, bool>{};

  /// 网络变化订阅（仅 WiFi 模式下监听，用于恢复挂起任务）。
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// 内存任务列表。
  final List<DownloadTask> _tasks = [];

  /// 全部任务（只读视图）。
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  /// 活跃任务（下载列表页使用，排除 completed）。
  List<DownloadTask> get activeTasks =>
      _tasks.where((t) => t.isActive).toList();

  /// 已完成任务（已下载内容页使用，排除已归档）。
  List<DownloadTask> get completedTasks =>
      _tasks.where((t) => t.isCompleted && !t.archived).toList();

  /// 已归档任务（归档 Tab 使用）。
  List<DownloadTask> get archivedTasks =>
      _tasks.where((t) => t.archived).toList();

  /// 是否已下载（详情页按钮状态）。
  bool isItemDownloaded(String contentId) =>
      _tasks.any((t) => t.contentId == contentId && t.isCompleted);

  /// 初始化：从存储加载 + 恢复孤立记录。
  Future<void> init() async {
    _tasks.clear();
    _tasks.addAll(await storage.loadAll());
    _migrateLegacyCancelledToArchived();
    await recoverOrphanedDownloads();
    await _recoverLegacyOrphanedFolders();
    await _loadSettings();
    _registerConnectivityListener();
    notifyListeners();
  }

  /// 注册网络变化监听：仅 WiFi 模式下，WiFi 恢复后自动重启挂起任务。
  void _registerConnectivityListener() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        if (results.contains(ConnectivityResult.wifi)) {
          _resumeWaitingForWifi();
        }
      },
    );
  }

  /// 将因无 WiFi 挂起的任务移回等待队列并重新调度。
  void _resumeWaitingForWifi() {
    if (_waitingForWifi.isEmpty) return;
    _pending.addAll(_waitingForWifi);
    _waitingForWifi.clear();
    _pumpQueue();
  }

  /// 当前是否连接 WiFi。
  Future<bool> _isWifiConnected() async {
    final List<ConnectivityResult> results =
        await Connectivity().checkConnectivity();
    return results.contains(ConnectivityResult.wifi);
  }

  /// 重新加载下载设置（设置页切换「仅 WiFi」后调用，使改动立即生效）。
  ///
  /// 若关闭仅 WiFi，立即重启此前因无 WiFi 挂起的任务。
  Future<void> reloadSettings() async {
    await _loadSettings();
    if (!_settings.wifiOnly && _waitingForWifi.isNotEmpty) {
      _resumeWaitingForWifi();
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    super.dispose();
  }

  /// 向后兼容：将旧的 status==cancelled 且保留 localPath 的任务迁移为 archived=true。
  ///
  /// 旧版本"仅删记录"会把 completed 任务标记为 cancelled 但保留 localPath，
  /// 新版本语义改为 archived=true + status=completed。
  void _migrateLegacyCancelledToArchived() {
    bool changed = false;
    for (var i = 0; i < _tasks.length; i++) {
      final t = _tasks[i];
      if (t.status == DownloadStatus.cancelled && t.localPath != null) {
        _tasks[i] = t.copyWith(
          status: DownloadStatus.completed,
          archived: true,
          archivedAt: t.completedAt ??
              DateTime.now().millisecondsSinceEpoch,
        );
        changed = true;
      }
    }
    // 持久化由 init() 后续 _persist 调用保证；此处仅修改内存。
    if (changed) {
      // ignore: unawaited_futures
      _persist();
    }
  }

  /// 添加下载任务并启动下载。
  ///
  /// [item] 内容项；[chapters] 章节列表；[chapterIndices] 要下载的章节索引
  /// （null = 全部）。
  Future<DownloadTask> addTask({
    required MediaItem item,
    required List<Episode> chapters,
    List<int>? chapterIndices,
  }) async {
    final sourceType = item.sourceType ?? SourceType.animeSource;
    final format = _resolveFormat(sourceType);
    final selectedChapters = chapterIndices == null
        ? chapters
        : chapterIndices.map((i) => chapters[i]).toList();

    final now = DateTime.now().millisecondsSinceEpoch;
    final task = DownloadTask(
      id: '${item.sourceId ?? 'local'}_${item.id}_$now',
      title: item.title,
      coverUrl: item.coverUrl,
      sourceType: sourceType,
      sourceId: item.sourceId,
      contentId: item.id,
      format: format,
      chapterTitles: selectedChapters.map((c) => c.title).toList(),
      totalChapters: selectedChapters.length,
      downloadedChapters: 0,
      status: DownloadStatus.pending,
      createdAt: now,
    );

    _tasks.add(task);
    await _persist();
    await _writeMetaJson(task);
    notifyListeners();

    // 按下载设置调度（受最大同时下载数限制）
    await _loadSettings();
    _scheduleDownload(task, item, selectedChapters);

    return task;
  }

  /// 取消下载。
  ///
  /// [deleteFiles] = true 同时删除磁盘文件 + meta.json；
  /// false 仅从存储移除，保留 meta.json（可恢复）。
  Future<void> cancel(String taskId, {bool deleteFiles = false}) async {
    // 同时从等待队列移除（若尚未开始执行）
    _pending.removeWhere((q) => q.task.id == taskId);

    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;

    final task = _tasks[idx];
    _tasks[idx] = task.copyWith(status: DownloadStatus.cancelled);

    if (deleteFiles) {
      await _deleteTaskFiles(task);
    }

    // 从活跃列表移除（保留 completed 供历史查看）
    if (!task.isCompleted) {
      _tasks.removeAt(idx);
    }
    await _persist();
    notifyListeners();
  }

  /// 暂停下载（旧入口，保留以兼容既有调用）。
  Future<void> pause(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    _tasks[idx] = _tasks[idx].copyWith(status: DownloadStatus.paused);
    await _persist();
    notifyListeners();
  }

  /// 暂停下载任务（项 5）。
  ///
  /// MVP 语义：取消当前下载但保留已下载分片/文件，标记为 `paused`。
  /// 仅对 status == downloading 的任务生效，其他状态不做任何操作。
  ///
  /// 引擎无原生取消能力时，下载 Future 仍会在后台跑完；当其完成时，
  /// [_executeDownload] 会检查 [_pauseTokens] 并保持 `paused` 状态（保留产物文件），
  /// 用户随后可通过 [resumeTask] 将其标记为 completed（若文件已落盘）或重新下载。
  Future<void> pauseTask(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = _tasks[idx];
    if (task.status != DownloadStatus.downloading) return;
    _pauseTokens[taskId] = true;
    _tasks[idx] = task.copyWith(status: DownloadStatus.paused);
    await _persist();
    notifyListeners();
  }

  /// 恢复下载任务（项 5）。
  ///
  /// MVP 语义：从断点续传或重新开始。仅对 status == paused 的任务生效。
  /// 若暂停期间下载已在后台完成（localPath 存在），直接标记为 completed；
  /// 否则标记为 downloading，让在途下载继续或等待重试。
  Future<void> resumeTask(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = _tasks[idx];
    if (task.status != DownloadStatus.paused) return;
    _pauseTokens.remove(taskId);

    // 若下载已在暂停期间完成（localPath 文件存在），直接标记为 completed。
    if (task.localPath != null && await fs.exists(task.localPath!)) {
      _tasks[idx] = task.copyWith(
        status: DownloadStatus.completed,
        downloadedChapters: task.totalChapters,
        completedAt: task.completedAt ??
            DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      _tasks[idx] = task.copyWith(status: DownloadStatus.downloading);
    }
    await _persist();
    notifyListeners();
  }

  /// 重试失败的任务（项 5）。
  ///
  /// 重新从源拉取详情与章节，重置为 pending 并重新调度下载。
  /// 仅对 status == failed 的任务生效；其余状态（含 paused）不处理。
  /// 网络/源异常时仍标记回 failed 并记录错误，不做破坏性操作。
  Future<void> retryTask(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = _tasks[idx];
    if (task.status != DownloadStatus.failed) return;
    if (task.sourceId == null || task.contentId == null) {
      _updateTask(taskId,
          status: DownloadStatus.failed, error: 'Missing source/content id');
      return;
    }

    final source = sourceRepo.getById(task.sourceId!);
    if (source == null) {
      _updateTask(taskId,
          status: DownloadStatus.failed, error: 'Source not found');
      return;
    }

    try {
      final item = await service.fetchDetail(source, task.contentId!);
      final chapters = await _fetchChaptersForRetry(source, item, task.sourceType);
      _tasks[idx] = task.copyWith(
        status: DownloadStatus.pending,
        error: null,
        downloadedChapters: 0,
      );
      await _persist();
      notifyListeners();
      _scheduleDownload(_tasks[idx], item, chapters);
    } catch (e) {
      _updateTask(taskId,
          status: DownloadStatus.failed, error: e.toString());
    }
  }

  /// 按任务类型拉取章节列表（重试专用）。
  Future<List<Episode>> _fetchChaptersForRetry(
    PluginConfig source,
    MediaItem item,
    SourceType sourceType,
  ) async {
    switch (sourceType) {
      case SourceType.novelSource:
        return service.fetchNovelChapters(source, item.id);
      case SourceType.mangaSource:
        return service.fetchChapters(source, item.id);
      default:
        return service.fetchEpisodes(source, item.id);
    }
  }

  /// 归档已完成任务——从已下载列表隐藏，但保留磁盘文件可随时恢复。
  ///
  /// 仅对 status==completed 的任务生效。
  Future<void> archive(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = _tasks[idx];
    if (task.status != DownloadStatus.completed) return;
    _tasks[idx] = task.copyWith(
      archived: true,
      archivedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _persist();
    notifyListeners();
  }

  /// 恢复归档任务——重新出现在已下载列表。
  Future<void> unarchive(String taskId) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    final task = _tasks[idx];
    if (!task.archived) return;
    _tasks[idx] = task.copyWith(
      archived: false,
      archivedAt: null,
      status: DownloadStatus.completed,
    );
    await _persist();
    notifyListeners();
  }

  /// 清除全部记录（§10.3）。
  ///
  /// [deleteFiles] = false → 清存储后立即 `recoverOrphanedDownloads()`，
  ///   已下载内容页从 meta.json 重建 completed，立即可见。
  /// [deleteFiles] = true → 删文件 + meta.json，不恢复，两页皆空。
  Future<void> clearAll({required bool deleteFiles}) async {
    if (deleteFiles) {
      // 删除所有任务的磁盘文件 + meta.json
      for (final task in _tasks) {
        await _deleteTaskFiles(task);
      }
      _tasks.clear();
      await storage.clear();
    } else {
      // 仅清存储中的任务记录，不删文件
      _tasks.clear();
      await storage.clear();
      // 立即从 meta.json 恢复 completed 任务
      await recoverOrphanedDownloads();
      // 恢复遗留孤立文件夹（无 meta.json 的旧数据）
      await _recoverLegacyOrphanedFolders();
    }
    notifyListeners();
  }

  /// 从 `.meta.json` 恢复孤立下载记录。
  ///
  /// 扫描下载目录下所有 `*.meta.json` 文件，
  /// 验证 `localPath` 文件存在 → 标记为 completed 重建到任务列表。
  Future<void> recoverOrphanedDownloads() async {
    final files = await fs.listFiles(fs.basePath);
    for (final filename in files) {
      if (!filename.endsWith('.meta.json')) continue;

      final metaPath = fs.join(fs.basePath, filename);
      try {
        final raw = await fs.readString(metaPath);
        final task = DownloadTask.fromJsonString(raw);

        // 避免重复添加
        if (_tasks.any((t) => t.id == task.id)) continue;

        // 验证产物文件是否存在
        if (task.localPath != null && await fs.exists(task.localPath!)) {
          _tasks.add(task.copyWith(
            status: DownloadStatus.completed,
            completedAt: task.completedAt ??
                DateTime.now().millisecondsSinceEpoch,
          ));
        }
      } catch (_) {
        // 损坏的 meta.json 跳过
      }
    }
  }

  /// 恢复遗留孤立文件夹/文件（无 .meta.json 的旧数据）。
  ///
  /// 扫描下载目录，对没有对应 .meta.json 的产物文件：
  /// 1. 按扩展名推断类型（.cbz→comic / .epub→novel / .txt→novel / 视频→media）。
  /// 2. 清理标题中的时间戳后缀（如 `Title_1700000000000` → `Title`）。
  /// 3. 查找同目录 `cover.jpg` / `folder.jpg` 作为 coverUrl。
  /// 4. 创建 completed DownloadTask 并写入 meta.json（后续可正常恢复）。
  Future<void> _recoverLegacyOrphanedFolders() async {
    final files = await fs.listFiles(fs.basePath);

    for (final filename in files) {
      // 跳过 meta.json 和封面图片
      if (filename.endsWith('.meta.json')) continue;
      if (filename.endsWith('.jpg') || filename.endsWith('.png')) continue;

      final filePath = fs.join(fs.basePath, filename);

      // 检查是否已有对应 meta.json（已被 recoverOrphanedDownloads 处理）
      final knownIds = _tasks.map((t) => t.id).toSet();
      final knownPaths = _tasks
          .where((t) => t.localPath != null)
          .map((t) => t.localPath!)
          .toSet();
      if (knownPaths.contains(filePath)) continue;

      // 推断类型和格式
      final inferred = _inferFromFilename(filename);
      if (inferred == null) continue;

      // 检查是否是已知的 task ID（避免重复）
      final taskId = _inferTaskId(filename);
      if (knownIds.contains(taskId)) continue;

      // 清理标题
      final cleanTitle = _cleanTitleTimestamp(inferred.$2);

      // 查找封面
      String? coverUrl;
      final coverPath = fs.join(fs.basePath, '$taskId.jpg');
      if (await fs.exists(coverPath)) {
        coverUrl = coverPath;
      } else {
        // 查找 folder.jpg / cover.jpg
        final folderCover = fs.join(fs.basePath, 'folder.jpg');
        if (await fs.exists(folderCover)) {
          coverUrl = folderCover;
        }
      }

      // 创建恢复任务
      final now = DateTime.now().millisecondsSinceEpoch;
      final task = DownloadTask(
        id: taskId,
        title: cleanTitle,
        sourceType: inferred.$1,
        contentId: taskId,
        format: inferred.$3,
        totalChapters: 1,
        downloadedChapters: 1,
        status: DownloadStatus.completed,
        createdAt: now,
        completedAt: now,
        localPath: filePath,
        coverUrl: coverUrl,
        localCoverPath: coverUrl,
      );

      _tasks.add(task);
      await _writeMetaJson(task);
    }

    if (_tasks.isNotEmpty) {
      await _persist();
    }
  }

  /// 从文件名推断 (SourceType, 原始标题, DownloadFormat)。
  (SourceType, String, DownloadFormat)? _inferFromFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.cbz')) {
      return (SourceType.mangaSource, _stripExt(filename), DownloadFormat.cbz);
    }
    if (lower.endsWith('.epub')) {
      return (SourceType.novelSource, _stripExt(filename), DownloadFormat.epub);
    }
    if (lower.endsWith('.txt')) {
      return (SourceType.novelSource, _stripExt(filename), DownloadFormat.txt);
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov')) {
      return (SourceType.animeSource, _stripExt(filename), DownloadFormat.video);
    }
    return null;
  }

  /// 移除文件扩展名。
  String _stripExt(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot > 0 ? filename.substring(0, dot) : filename;
  }

  /// 从文件名推断 task ID（取扩展名前的部分）。
  String _inferTaskId(String filename) => _stripExt(filename);

  /// 清理标题中的时间戳后缀（如 `Title_1700000000000` → `Title`）。
  String _cleanTitleTimestamp(String title) {
    return title.replaceAll(RegExp(r'_\d{10,}$'), '').trim();
  }

  /// 更新格式偏好。
  Future<void> setFormatPrefs(DownloadFormatPreferences prefs) async {
    _formatPrefs = prefs;
    final store = DownloadFormatPreferencesStore();
    await store.save(prefs);
    notifyListeners();
  }

  // ── 内部方法 ──────────────────────────────────────────

  DownloadFormat _resolveFormat(SourceType type) {
    return switch (type) {
      SourceType.mangaSource => _formatPrefs.comicFormat,
      SourceType.novelSource => _formatPrefs.novelFormat,
      SourceType.animeSource => DownloadFormat.video,
    };
  }

  // ── 下载调度（受最大同时下载数约束） ──────────────────────────

  /// 从持久化存储重新加载下载设置（供本次及后续调度使用）。
  Future<void> _loadSettings() async {
    try {
      _settings = await DownloadSettingsStore().load();
    } catch (_) {
      // 读取失败则保持现有设置（默认或上次成功值）
    }
  }

  /// 按最大并发限制调度一次下载：立即执行或入队等待。
  void _scheduleDownload(
    DownloadTask task,
    MediaItem item,
    List<Episode> chapters,
  ) {
    if (_running < _settings.maxConcurrent) {
      _startDownload(task, item, chapters);
    } else {
      _pending.add(_QueuedDownload(task, item, chapters));
      notifyListeners();
    }
  }

  /// 启动一次实际下载，完成后从队列补充下一个。
  ///
  /// 仅 WiFi 模式：若未连接 WiFi，任务挂起到 [_waitingForWifi]，
  /// 待网络恢复后由 [_resumeWaitingForWifi] 重新调度；不占用并发额度。
  Future<void> _startDownload(
    DownloadTask task,
    MediaItem item,
    List<Episode> chapters,
  ) async {
    _running++;
    if (_settings.wifiOnly && !await _isWifiConnected()) {
      _running--;
      _updateTask(task.id, status: DownloadStatus.waitingForWifi);
      _waitingForWifi.add(_QueuedDownload(task, item, chapters));
      notifyListeners();
      return;
    }
    _updateTask(task.id, status: DownloadStatus.downloading);
    try {
      await _executeDownload(task, item, chapters);
    } finally {
      _running--;
      _pumpQueue();
    }
  }

  /// 从等待队列取出下一个下载（若并发额度允许）。
  void _pumpQueue() {
    while (_pending.isNotEmpty && _running < _settings.maxConcurrent) {
      final next = _pending.removeAt(0);
      _startDownload(next.task, next.item, next.chapters);
    }
    if (_pending.isNotEmpty) notifyListeners();
  }

  Future<void> _executeDownload(
    DownloadTask task,
    MediaItem item,
    List<Episode> chapters,
  ) async {
    try {
      final source = item.sourceId != null
          ? sourceRepo.getById(item.sourceId!)
          : null;

      if (source == null) {
        _updateTask(task.id,
            status: DownloadStatus.failed, error: 'Source not found');
        return;
      }

      final handler = _createHandler(task, source, item.title, item.author,
          chapters);

      final localPath = await handler.download(
        task,
        onProgress: (downloaded, total) {
          _updateTask(task.id,
              downloadedChapters: downloaded, totalChapters: total);
        },
      );

      // 保存封面
      String? localCoverPath;
      if (item.coverUrl != null && item.coverUrl!.startsWith('http')) {
        localCoverPath = await _saveCoverImage(task.id, item.coverUrl!);
      }

      // 暂停检查：若用户在下载过程中暂停，保留已下载文件但状态保持 paused。
      if (_pauseTokens[task.id] == true) {
        _pauseTokens.remove(task.id);
        final pausedTask = task.copyWith(
          status: DownloadStatus.paused,
          downloadedChapters: task.totalChapters,
          localPath: localPath,
          completedAt: DateTime.now().millisecondsSinceEpoch,
          localCoverPath: localCoverPath,
          coverUrl: localCoverPath ?? item.coverUrl,
        );
        _updateTaskRaw(pausedTask);
        await _writeMetaJson(pausedTask);
        await _persist();
        notifyListeners();
        return;
      }

      final completed = task.copyWith(
        status: DownloadStatus.completed,
        downloadedChapters: task.totalChapters,
        localPath: localPath,
        completedAt: DateTime.now().millisecondsSinceEpoch,
        localCoverPath: localCoverPath,
        coverUrl: localCoverPath ?? item.coverUrl,
      );

      _updateTaskRaw(completed);
      await _writeMetaJson(completed);
      await _persist();
      notifyListeners();
    } catch (e) {
      _updateTask(task.id,
          status: DownloadStatus.failed, error: e.toString());
    }
  }

  DownloadHandler _createHandler(
    DownloadTask task,
    PluginConfig source,
    String title,
    String? author,
    List<Episode> chapters,
  ) {
    switch (task.sourceType) {
      case SourceType.mangaSource:
        return ComicDownloadHandler(
          service: service,
          fs: fs,
          source: source,
          comicId: task.contentId,
          chapters: chapters,
          format: task.format,
          concurrency: _settings.threadCount,
        );
      case SourceType.novelSource:
        return NovelDownloadHandler(
          service: service,
          fs: fs,
          source: source,
          novelId: task.contentId,
          chapters: chapters,
          format: task.format,
          bookTitle: title,
          author: author,
          concurrency: _settings.threadCount,
        );
      case SourceType.animeSource:
        return MediaDownloadHandler(
          service: service,
          fs: fs,
          source: source,
          contentId: task.contentId,
          chapters: chapters,
          concurrency: _settings.threadCount,
        );
    }
  }

  Future<String?> _saveCoverImage(String taskId, String url) async {
    try {
      final bytes = await HttpFetcher.instance.getBytes(url);
      if (bytes.isEmpty) return null;
      final coverPath = fs.join(fs.basePath, '$taskId.jpg');
      await fs.writeBytes(coverPath, Uint8List.fromList(bytes));
      return coverPath;
    } catch (_) {
      return null;
    }
  }

  void _updateTask(
    String taskId, {
    DownloadStatus? status,
    int? downloadedChapters,
    int? totalChapters,
    String? error,
  }) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;
    _tasks[idx] = _tasks[idx].copyWith(
      status: status,
      downloadedChapters: downloadedChapters,
      totalChapters: totalChapters,
      error: error,
    );
    notifyListeners();
  }

  void _updateTaskRaw(DownloadTask updated) {
    final idx = _tasks.indexWhere((t) => t.id == updated.id);
    if (idx >= 0) {
      _tasks[idx] = updated;
    }
  }

  Future<void> _persist() async {
    await storage.saveAll(_tasks);
  }

  Future<void> _writeMetaJson(DownloadTask task) async {
    final metaPath = fs.join(fs.basePath, '${task.id}.meta.json');
    await fs.writeString(metaPath, task.toJsonString());
  }

  Future<void> _deleteTaskFiles(DownloadTask task) async {
    // 删除 meta.json
    final metaPath = fs.join(fs.basePath, '${task.id}.meta.json');
    if (await fs.exists(metaPath)) {
      await fs.delete(metaPath);
    }
    // 删除产物文件
    if (task.localPath != null && await fs.exists(task.localPath!)) {
      await fs.delete(task.localPath!);
    }
    // 删除封面
    if (task.localCoverPath != null &&
        await fs.exists(task.localCoverPath!)) {
      await fs.delete(task.localCoverPath!);
    }
    // 删除任务目录（散图模式）
    final taskDir = fs.join(fs.basePath, task.id);
    if (await fs.exists(taskDir)) {
      await fs.delete(taskDir);
    }
  }
}
