/// 搜索规则：书源 `ruleSearch` 段，定义搜索结果列表的解析规则。
library;

class SearchRule {
  String? bookList;
  String? bookName;
  String? bookAuthor;
  String? bookUrl;
  String? bookCoverUrl;
  String? bookKind;
  String? bookLastChapter;
  String? checkKeyWord;

  SearchRule({
    this.bookList,
    this.bookName,
    this.bookAuthor,
    this.bookUrl,
    this.bookCoverUrl,
    this.bookKind,
    this.bookLastChapter,
    this.checkKeyWord,
  });

  factory SearchRule.fromJson(Map<String, dynamic> json) {
    return SearchRule(
      bookList: json['bookList'] as String?,
      bookName: json['bookName'] as String?,
      bookAuthor: json['bookAuthor'] as String?,
      bookUrl: json['bookUrl'] as String?,
      bookCoverUrl: json['bookCoverUrl'] as String?,
      bookKind: json['bookKind'] as String?,
      bookLastChapter: json['bookLastChapter'] as String?,
      checkKeyWord: json['checkKeyWord'] as String?,
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
        if (checkKeyWord != null) 'checkKeyWord': checkKeyWord,
      };
}
