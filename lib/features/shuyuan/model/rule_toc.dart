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
      };
}
