/// 章节模型：承载章节 URL、标题、索引及卷/VIP/付费标记。
library;

class XiaoshuoBookChapter {
  String bookUrl;
  String url;
  String title;
  int index;
  bool isVolume;
  bool isVip;
  bool isPay;
  String? tag;
  String? wordCount;
  String? imgUrl;
  String? variable;
  Map<String, String> variableMap = {};

  XiaoshuoBookChapter({
    required this.bookUrl,
    this.url = '',
    this.title = '',
    this.index = 0,
    this.isVolume = false,
    this.isVip = false,
    this.isPay = false,
    this.tag,
    this.wordCount,
    this.imgUrl,
    this.variable,
  });

  factory XiaoshuoBookChapter.fromJson(Map<String, dynamic> json) {
    return XiaoshuoBookChapter(
      bookUrl: json['bookUrl'] as String? ?? '',
      url: json['url'] as String? ?? '',
      title: json['title'] as String? ?? '',
      index: json['index'] as int? ?? 0,
      isVolume: json['isVolume'] as bool? ?? false,
      isVip: json['isVip'] as bool? ?? false,
      isPay: json['isPay'] as bool? ?? false,
      tag: json['tag'] as String?,
      wordCount: json['wordCount'] as String?,
      imgUrl: json['imgUrl'] as String?,
      variable: json['variable'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'bookUrl': bookUrl,
        'url': url,
        'title': title,
        'index': index,
        'isVolume': isVolume,
        'isVip': isVip,
        'isPay': isPay,
        if (tag != null) 'tag': tag,
        if (wordCount != null) 'wordCount': wordCount,
        if (imgUrl != null) 'imgUrl': imgUrl,
        if (variable != null) 'variable': variable,
      };

  String getAbsoluteURL({String? redirectUrl}) {
    if (url.startsWith('http')) return url;
    if (redirectUrl == null || redirectUrl.isEmpty) return url;
    try {
      final base = Uri.parse(redirectUrl);
      return base.resolve(url).toString();
    } catch (_) {
      return url;
    }
  }

  void putVariable(String key, String value) {
    variableMap[key] = value;
  }

  String getVariable(String key) {
    return variableMap[key] ?? '';
  }

  String getDisplayTitle() {
    return title;
  }
}
