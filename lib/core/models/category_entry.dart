/// 动态分类项（MacCMS `ac=list` 的 `class` 字段）。
library;

class CategoryEntry {
  final String id;
  final String title;

  const CategoryEntry({required this.id, required this.title});

  factory CategoryEntry.fromJson(Map<String, dynamic> json) => CategoryEntry(
        id: json['id']?.toString() ?? json['type_id']?.toString() ?? '',
        title: json['title']?.toString() ??
            json['type_name']?.toString() ??
            '',
      );
}
