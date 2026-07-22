/// 正文规则：书源 `ruleContent` 段，定义章节正文的解析与净化规则。
library;

class ContentRule {
  String? content;
  String? subContent;
  String? title;
  String? nextContentUrl;
  String? webJs;
  String? sourceRegex;
  String? replaceRegex;
  String? imageStyle;
  String? imageDecode;
  String? payAction;
  String? callBackJs;

  ContentRule({
    this.content,
    this.subContent,
    this.title,
    this.nextContentUrl,
    this.webJs,
    this.sourceRegex,
    this.replaceRegex,
    this.imageStyle,
    this.imageDecode,
    this.payAction,
    this.callBackJs,
  });

  factory ContentRule.fromJson(Map<String, dynamic> json) {
    return ContentRule(
      content: json['content'] as String?,
      subContent: json['subContent'] as String?,
      title: json['title'] as String?,
      nextContentUrl: json['nextContentUrl'] as String?,
      webJs: json['webJs'] as String?,
      sourceRegex: json['sourceRegex'] as String?,
      replaceRegex: json['replaceRegex'] as String?,
      imageStyle: json['imageStyle'] as String?,
      imageDecode: json['imageDecode'] as String?,
      payAction: json['payAction'] as String?,
      callBackJs: json['callBackJs'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (content != null) 'content': content,
        if (subContent != null) 'subContent': subContent,
        if (title != null) 'title': title,
        if (nextContentUrl != null) 'nextContentUrl': nextContentUrl,
        if (webJs != null) 'webJs': webJs,
        if (sourceRegex != null) 'sourceRegex': sourceRegex,
        if (replaceRegex != null) 'replaceRegex': replaceRegex,
        if (imageStyle != null) 'imageStyle': imageStyle,
        if (imageDecode != null) 'imageDecode': imageDecode,
        if (payAction != null) 'payAction': payAction,
        if (callBackJs != null) 'callBackJs': callBackJs,
      };
}
