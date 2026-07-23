/// 目录规则：书源 `ruleToc` 段，定义章节列表的解析规则。
library;

class TocRule {
  String? preUpdateJs;
  String? chapterList;
  String? chapterName;
  String? chapterUrl;
  String? formatJs;
  String? isVolume;
  String? isVip;
  String? isPay;
  String? updateTime;
  String? nextTocUrl;
  /// 跨书过滤开关（源可配置，默认关闭）。
  /// - 'bookDir'：仅保留与目录页同属一个书籍目录（父目录一致）的章节链接，
  ///   剔除目录页中"最新章节预览"等栏里指向【其他书籍】的跨书链接。
  /// 该字段对所有未声明的源无副作用（保持 null/非 'bookDir' 时行为不变）。
  String? chapterScope;
  /// 排除选择器：匹配的 DOM 容器及其所有后代元素将从章节列表解析中剔除。
  ///
  /// 用于在**选择器层面**排斥"最新章节预览"/"推荐"/"新书发布"等非正文区域，
  /// 比 [chapterScope] 更彻底——这些区域的元素根本不会进入后续过滤流程。
  /// 典型值：`[class*="latest"]`, `#latest-chapters`, `.book-recommend` 等。
  /// 多个选择器用逗号分隔（标准 CSS 选择器语法）。
  String? excludeSelector;

  TocRule({
    this.preUpdateJs,
    this.chapterList,
    this.chapterName,
    this.chapterUrl,
    this.formatJs,
    this.isVolume,
    this.isVip,
    this.isPay,
    this.updateTime,
    this.nextTocUrl,
    this.chapterScope,
    this.excludeSelector,
  });

  factory TocRule.fromJson(Map<String, dynamic> json) {
    return TocRule(
      preUpdateJs: json['preUpdateJs'] as String?,
      chapterList: json['chapterList'] as String?,
      chapterName: json['chapterName'] as String?,
      chapterUrl: json['chapterUrl'] as String?,
      formatJs: json['formatJs'] as String?,
      isVolume: json['isVolume'] as String?,
      isVip: json['isVip'] as String?,
      isPay: json['isPay'] as String?,
      updateTime: json['updateTime'] as String?,
      nextTocUrl: json['nextTocUrl'] as String?,
      chapterScope: json['chapterScope'] as String?,
      excludeSelector: json['excludeSelector'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (preUpdateJs != null) 'preUpdateJs': preUpdateJs,
        if (chapterList != null) 'chapterList': chapterList,
        if (chapterName != null) 'chapterName': chapterName,
        if (chapterUrl != null) 'chapterUrl': chapterUrl,
        if (formatJs != null) 'formatJs': formatJs,
        if (isVolume != null) 'isVolume': isVolume,
        if (isVip != null) 'isVip': isVip,
        if (isPay != null) 'isPay': isPay,
        if (updateTime != null) 'updateTime': updateTime,
        if (nextTocUrl != null) 'nextTocUrl': nextTocUrl,
        if (chapterScope != null) 'chapterScope': chapterScope,
        if (excludeSelector != null) 'excludeSelector': excludeSelector,
      };
}
