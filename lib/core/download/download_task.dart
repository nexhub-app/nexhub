/// 下载任务模型与状态枚举（文档 §10.1）。
library;

import 'dart:convert';

import '../models/plugin_config.dart';

/// 下载状态机：pending → downloading → completed / failed / paused / cancelled。
enum DownloadStatus {
  pending,
  downloading,
  completed,
  failed,
  paused,
  cancelled,
  waitingForWifi;

  static DownloadStatus fromString(String? raw) {
    return switch (raw) {
      'pending' => pending,
      'downloading' => downloading,
      'completed' => completed,
      'failed' => failed,
      'paused' => paused,
      'cancelled' => cancelled,
      'waitingForWifi' => waitingForWifi,
      _ => pending,
    };
  }

  String get label => switch (this) {
        pending => 'pending',
        downloading => 'downloading',
        completed => 'completed',
        failed => 'failed',
      paused => 'paused',
      cancelled => 'cancelled',
      waitingForWifi => 'waitingForWifi',
      };
}

/// 下载格式（漫画 CBZ / 散图文件夹 / 单页 JPG / 单页 PNG，小说 EPUB / TXT）。
enum DownloadFormat {
  cbz,
  folder,
  epub,
  txt,
  video,
  jpg,
  png;

  static DownloadFormat? fromString(String? raw) {
    return switch (raw) {
      'cbz' => cbz,
      'folder' => folder,
      'epub' => epub,
      'txt' => txt,
      'video' => video,
      'jpg' => jpg,
      'png' => png,
      _ => null,
    };
  }

  String get label => name;
}

/// 下载任务——记录一次离线缓存请求的完整元数据。
///
/// 按 spec §10.1：`coverUrl` 非 final（下载完成后可更新为本地路径）；
/// `localPath` 指向最终产物（.cbz / .epub / .txt / 视频文件 / 散图文件夹）。
class DownloadTask {
  final String id;
  final String title;
  final String? coverUrl;

  /// 源类型（comic / novel / media），决定使用哪个 handler。
  final SourceType sourceType;

  /// 源 ID（用于追溯解析器）。
  final String? sourceId;

  /// 内容 ID（MediaItem.id）。
  final String contentId;

  /// 下载格式。
  final DownloadFormat format;

  /// 章节范围（标题列表，用于显示和范围选择）。
  final List<String> chapterTitles;

  /// 总章节数。
  final int totalChapters;

  /// 已完成章节数。
  final int downloadedChapters;

  /// 当前状态。
  final DownloadStatus status;

  /// 错误信息（failed 时）。
  final String? error;

  /// 本地产物路径（completed 时有值）。
  final String? localPath;

  /// 创建时间戳（毫秒）。
  final int createdAt;

  /// 完成时间戳（毫秒）。
  final int? completedAt;

  /// 封面本地路径（持久化后，coverUrl 可能为本地文件路径）。
  final String? localCoverPath;

  /// Whether this task has been archived (file kept on disk, hidden from main list).
  final bool archived;

  /// Archival timestamp (ms). null when not archived.
  final int? archivedAt;

  const DownloadTask({
    required this.id,
    required this.title,
    required this.sourceType,
    required this.contentId,
    required this.format,
    this.coverUrl,
    this.sourceId,
    this.chapterTitles = const <String>[],
    this.totalChapters = 0,
    this.downloadedChapters = 0,
    this.status = DownloadStatus.pending,
    this.error,
    this.localPath,
    required this.createdAt,
    this.completedAt,
    this.localCoverPath,
    this.archived = false,
    this.archivedAt,
  });

  /// 进度（0.0 ~ 1.0）。
  double get progress =>
      totalChapters > 0 ? (downloadedChapters / totalChapters).clamp(0.0, 1.0) : 0.0;

  /// 是否已完成（用于已下载内容页过滤）。
  bool get isCompleted => status == DownloadStatus.completed;

  /// Whether the task has been archived (files kept on disk, restorable).
  bool get isArchived => archived;

  /// 是否为活跃任务（用于下载列表页过滤，排除 completed）。
  bool get isActive =>
      status == DownloadStatus.pending ||
      status == DownloadStatus.downloading ||
      status == DownloadStatus.paused ||
      status == DownloadStatus.waitingForWifi;

  DownloadTask copyWith({
    String? title,
    String? coverUrl,
    DownloadStatus? status,
    int? downloadedChapters,
    int? totalChapters,
    String? error,
    String? localPath,
    int? completedAt,
    String? localCoverPath,
    List<String>? chapterTitles,
    bool? archived,
    int? archivedAt,
  }) =>
      DownloadTask(
        id: id,
        title: title ?? this.title,
        sourceType: sourceType,
        contentId: contentId,
        format: format,
        coverUrl: coverUrl ?? this.coverUrl,
        sourceId: sourceId,
        chapterTitles: chapterTitles ?? this.chapterTitles,
        totalChapters: totalChapters ?? this.totalChapters,
        downloadedChapters: downloadedChapters ?? this.downloadedChapters,
        status: status ?? this.status,
        error: error ?? this.error,
        localPath: localPath ?? this.localPath,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
        localCoverPath: localCoverPath ?? this.localCoverPath,
        archived: archived ?? this.archived,
        archivedAt: archivedAt ?? this.archivedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'coverUrl': coverUrl,
        'sourceType': sourceType.apiName,
        'sourceId': sourceId,
        'contentId': contentId,
        'format': format.label,
        'chapterTitles': chapterTitles,
        'totalChapters': totalChapters,
        'downloadedChapters': downloadedChapters,
        'status': status.label,
        'error': error,
        'localPath': localPath,
        'createdAt': createdAt,
        'completedAt': completedAt,
        'localCoverPath': localCoverPath,
        'archived': archived,
        'archivedAt': archivedAt,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        coverUrl: json['coverUrl'] as String?,
        sourceType: SourceType.parse(json['sourceType'] as String?) ??
            SourceType.animeSource,
        sourceId: json['sourceId'] as String?,
        contentId: json['contentId'] as String? ?? '',
        format: DownloadFormat.fromString(json['format'] as String?) ??
            DownloadFormat.video,
        chapterTitles: (json['chapterTitles'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const <String>[],
        totalChapters: json['totalChapters'] as int? ?? 0,
        downloadedChapters: json['downloadedChapters'] as int? ?? 0,
        status: DownloadStatus.fromString(json['status'] as String?),
        error: json['error'] as String?,
        localPath: json['localPath'] as String?,
        createdAt: json['createdAt'] as int? ?? 0,
        completedAt: json['completedAt'] as int?,
        localCoverPath: json['localCoverPath'] as String?,
        archived: json['archived'] as bool? ?? false,
        archivedAt: json['archivedAt'] as int?,
      );

  String toJsonString() => jsonEncode(toJson());

  static DownloadTask fromJsonString(String raw) =>
      DownloadTask.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
