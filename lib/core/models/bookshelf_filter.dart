/// 书架筛选状态（文档 §10.2 + 雷区 18）。
///
/// 三模块书架共用，描述"排序 + 分类 + 状态 + 进度"四段筛选。
/// 不可变值对象，通过 [copyWith] 修改；[isDefault] 用于判断是否显示"已筛选"角标。
library;

/// 排序方式。
enum BookshelfSort {
  /// 按时间倒序（收藏时间 / 浏览时间 / 完成时间）。
  recent,

  /// 按标题字母升序。
  title,
}

/// 进度筛选语义。
enum BookshelfProgress {
  /// 在看（收藏夹中存在于历史记录里的条目）。
  reading,

  /// 未看（收藏夹中尚未出现在历史记录里的条目）。
  notStarted,
}

/// 书架筛选状态。
class BookshelfFilter {
  final BookshelfSort sort;

  /// 状态筛选：null = 全部；否则按 [FavoriteEntry.status] / [HistoryEntry.status]
  /// 原值匹配（如 "连载中" / "已完结"）。
  final String? status;

  /// 分类筛选：null = 全部分类；否则按 [FavoriteEntry.category] /
  /// [HistoryEntry.category] 原值匹配。
  final String? category;

  /// 进度筛选：null = 全部进度；否则按 [BookshelfProgress] 语义过滤。
  /// 仅对收藏/本地子段有意义，历史子段自动全过。
  final BookshelfProgress? progress;

  const BookshelfFilter({
    this.sort = BookshelfSort.recent,
    this.status,
    this.category,
    this.progress,
  });

  /// 是否为默认状态（无任何筛选/排序覆盖）。
  bool get isDefault =>
      sort == BookshelfSort.recent &&
      status == null &&
      category == null &&
      progress == null;

  BookshelfFilter copyWith({
    BookshelfSort? sort,
    Object? status = _sentinel,
    Object? category = _sentinel,
    Object? progress = _sentinel,
  }) =>
      BookshelfFilter(
        sort: sort ?? this.sort,
        status: identical(status, _sentinel)
            ? this.status
            : status as String?,
        category: identical(category, _sentinel)
            ? this.category
            : category as String?,
        progress: identical(progress, _sentinel)
            ? this.progress
            : progress as BookshelfProgress?,
      );

  /// 重置为默认状态。
  BookshelfFilter reset() => const BookshelfFilter();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookshelfFilter &&
          other.sort == sort &&
          other.status == status &&
          other.category == category &&
          other.progress == progress);

  @override
  int get hashCode => Object.hash(sort, status, category, progress);
}

/// 用于区分"未传参"与"显式传 null"的哨兵对象。
const Object _sentinel = Object();
