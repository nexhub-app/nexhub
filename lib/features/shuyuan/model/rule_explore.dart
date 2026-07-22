/// 发现规则：书源 `ruleExplore` 段，定义发现页书列表的解析规则。
library;

class ExploreRule {
  String? bookList;
  String? bookName;
  String? bookAuthor;
  String? bookUrl;
  String? bookCoverUrl;
  String? bookKind;
  String? bookLastChapter;

  ExploreRule({
    this.bookList,
    this.bookName,
    this.bookAuthor,
    this.bookUrl,
    this.bookCoverUrl,
    this.bookKind,
    this.bookLastChapter,
  });

  factory ExploreRule.fromJson(Map<String, dynamic> json) {
    return ExploreRule(
      bookList: json['bookList'] as String?,
      bookName: json['bookName'] as String?,
      bookAuthor: json['bookAuthor'] as String?,
      bookUrl: json['bookUrl'] as String?,
      bookCoverUrl: json['bookCoverUrl'] as String?,
      bookKind: json['bookKind'] as String?,
      bookLastChapter: json['bookLastChapter'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (bookList != null) 'bookList': bookList,
        if (bookName != null) 'bookName': bookName,
        if (bookAuthor != null) 'bookAuthor': bookAuthor,
        if (bookUrl != null) 'bookUrl': bookUrl,
        if (bookCoverUrl != null) 'bookCoverUrl': bookCoverUrl,
        if (bookKind != null) 'bookKind': bookKind,
        if (bookLastChapter != null) 'bookLastChapter': bookLastChapter,
      };
}
