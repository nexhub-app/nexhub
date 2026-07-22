// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hive_adapters.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class HiveMediaItemAdapter extends TypeAdapter<HiveMediaItem> {
  @override
  final int typeId = 0;

  @override
  HiveMediaItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveMediaItem(
      id: fields[0] as String,
      title: fields[1] as String,
      coverUrl: fields[2] as String?,
      detailUrl: fields[3] as String?,
      sourceId: fields[4] as String?,
      sourceType: fields[5] as String?,
      description: fields[6] as String?,
      author: fields[7] as String?,
      director: fields[8] as String?,
      actors: fields[9] as String?,
      year: fields[10] as String?,
      tags: (fields[11] as List?)?.cast<String>(),
      status: fields[12] as String?,
      updatedAt: fields[13] as int?,
      extra: (fields[14] as Map?)?.cast<String, dynamic>(),
      wordCount: fields[15] as String?,
      authorUrl: fields[16] as String?,
      tagUrls: (fields[17] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, HiveMediaItem obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.coverUrl)
      ..writeByte(3)
      ..write(obj.detailUrl)
      ..writeByte(4)
      ..write(obj.sourceId)
      ..writeByte(5)
      ..write(obj.sourceType)
      ..writeByte(6)
      ..write(obj.description)
      ..writeByte(7)
      ..write(obj.author)
      ..writeByte(8)
      ..write(obj.director)
      ..writeByte(9)
      ..write(obj.actors)
      ..writeByte(10)
      ..write(obj.year)
      ..writeByte(11)
      ..write(obj.tags)
      ..writeByte(12)
      ..write(obj.status)
      ..writeByte(13)
      ..write(obj.updatedAt)
      ..writeByte(14)
      ..write(obj.extra)
      ..writeByte(15)
      ..write(obj.wordCount)
      ..writeByte(16)
      ..write(obj.authorUrl)
      ..writeByte(17)
      ..write(obj.tagUrls);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveMediaItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HiveEpisodeAdapter extends TypeAdapter<HiveEpisode> {
  @override
  final int typeId = 1;

  @override
  HiveEpisode read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveEpisode(
      id: fields[0] as String,
      title: fields[1] as String,
      url: fields[2] as String,
      lineName: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, HiveEpisode obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.url)
      ..writeByte(3)
      ..write(obj.lineName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveEpisodeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HivePluginConfigAdapter extends TypeAdapter<HivePluginConfig> {
  @override
  final int typeId = 2;

  @override
  HivePluginConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HivePluginConfig(
      id: fields[0] as String,
      name: fields[1] as String,
      type: fields[2] as String,
      responseType: fields[3] as String?,
      useWebview: fields[4] as bool,
      site: (fields[5] as Map).cast<String, dynamic>(),
      parser: (fields[6] as Map).cast<String, dynamic>(),
      routes: (fields[7] as Map).cast<String, dynamic>(),
      selectors: (fields[8] as Map?)?.cast<String, dynamic>(),
      category: (fields[9] as Map?)?.cast<String, dynamic>(),
      stealthMode: fields[10] as bool,
      antiHotlinking: (fields[11] as Map?)?.cast<String, dynamic>(),
      webviewConfig: (fields[12] as Map?)?.cast<String, dynamic>(),
      deprecated: fields[13] as bool,
      enabled: fields[14] as bool,
      enabledExplore: fields[15] as bool,
      migrationMessage: fields[16] as String?,
      engine: fields[17] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, HivePluginConfig obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.responseType)
      ..writeByte(4)
      ..write(obj.useWebview)
      ..writeByte(5)
      ..write(obj.site)
      ..writeByte(6)
      ..write(obj.parser)
      ..writeByte(7)
      ..write(obj.routes)
      ..writeByte(8)
      ..write(obj.selectors)
      ..writeByte(9)
      ..write(obj.category)
      ..writeByte(10)
      ..write(obj.stealthMode)
      ..writeByte(11)
      ..write(obj.antiHotlinking)
      ..writeByte(12)
      ..write(obj.webviewConfig)
      ..writeByte(13)
      ..write(obj.deprecated)
      ..writeByte(14)
      ..write(obj.enabled)
      ..writeByte(15)
      ..write(obj.enabledExplore)
      ..writeByte(16)
      ..write(obj.migrationMessage)
      ..writeByte(17)
      ..write(obj.engine);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HivePluginConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HiveReadingProgressAdapter extends TypeAdapter<HiveReadingProgress> {
  @override
  final int typeId = 3;

  @override
  HiveReadingProgress read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveReadingProgress(
      itemId: fields[0] as String,
      chapterId: fields[1] as String?,
      currentPage: fields[2] as int,
      lastReadChapterIndex: fields[3] as int?,
      totalChapters: fields[4] as int?,
      updatedAt: fields[5] as int,
    );
  }

  @override
  void write(BinaryWriter writer, HiveReadingProgress obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.itemId)
      ..writeByte(1)
      ..write(obj.chapterId)
      ..writeByte(2)
      ..write(obj.currentPage)
      ..writeByte(3)
      ..write(obj.lastReadChapterIndex)
      ..writeByte(4)
      ..write(obj.totalChapters)
      ..writeByte(5)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveReadingProgressAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HiveFavoriteAdapter extends TypeAdapter<HiveFavorite> {
  @override
  final int typeId = 4;

  @override
  HiveFavorite read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveFavorite(
      itemId: fields[0] as String,
      type: fields[1] as String,
      title: fields[2] as String,
      coverUrl: fields[3] as String?,
      sourceId: fields[4] as String?,
      dateAdded: fields[5] as int,
      lastReadAt: fields[6] as int?,
      extra: (fields[7] as Map?)?.cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, HiveFavorite obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.itemId)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.coverUrl)
      ..writeByte(4)
      ..write(obj.sourceId)
      ..writeByte(5)
      ..write(obj.dateAdded)
      ..writeByte(6)
      ..write(obj.lastReadAt)
      ..writeByte(7)
      ..write(obj.extra);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveFavoriteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HiveDownloadTaskAdapter extends TypeAdapter<HiveDownloadTask> {
  @override
  final int typeId = 5;

  @override
  HiveDownloadTask read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveDownloadTask(
      id: fields[0] as String,
      type: fields[1] as String,
      itemId: fields[2] as String,
      title: fields[3] as String,
      coverUrl: fields[4] as String?,
      sourceId: fields[5] as String?,
      localPath: fields[6] as String?,
      status: fields[7] as int,
      progress: fields[8] as int,
      totalSize: fields[9] as int,
      downloadedSize: fields[10] as int,
      chapters: (fields[11] as List).cast<String>(),
      dateAdded: fields[12] as int,
      completedAt: fields[13] as int?,
      extra: (fields[14] as Map?)?.cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, HiveDownloadTask obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.itemId)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.coverUrl)
      ..writeByte(5)
      ..write(obj.sourceId)
      ..writeByte(6)
      ..write(obj.localPath)
      ..writeByte(7)
      ..write(obj.status)
      ..writeByte(8)
      ..write(obj.progress)
      ..writeByte(9)
      ..write(obj.totalSize)
      ..writeByte(10)
      ..write(obj.downloadedSize)
      ..writeByte(11)
      ..write(obj.chapters)
      ..writeByte(12)
      ..write(obj.dateAdded)
      ..writeByte(13)
      ..write(obj.completedAt)
      ..writeByte(14)
      ..write(obj.extra);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveDownloadTaskAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HiveDanmakuCacheAdapter extends TypeAdapter<HiveDanmakuCache> {
  @override
  final int typeId = 6;

  @override
  HiveDanmakuCache read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveDanmakuCache(
      key: fields[0] as String,
      content: fields[1] as String,
      cachedAt: fields[2] as int,
      ttl: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, HiveDanmakuCache obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.key)
      ..writeByte(1)
      ..write(obj.content)
      ..writeByte(2)
      ..write(obj.cachedAt)
      ..writeByte(3)
      ..write(obj.ttl);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveDanmakuCacheAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HiveRssFeedAdapter extends TypeAdapter<HiveRssFeed> {
  @override
  final int typeId = 7;

  @override
  HiveRssFeed read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveRssFeed(
      id: fields[0] as String,
      title: fields[1] as String,
      url: fields[2] as String,
      iconUrl: fields[3] as String?,
      enabled: fields[4] as bool,
      dateAdded: fields[5] as int,
      lastUpdated: fields[6] as int?,
      unreadCount: fields[7] as int?,
      extra: (fields[8] as Map?)?.cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, HiveRssFeed obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.url)
      ..writeByte(3)
      ..write(obj.iconUrl)
      ..writeByte(4)
      ..write(obj.enabled)
      ..writeByte(5)
      ..write(obj.dateAdded)
      ..writeByte(6)
      ..write(obj.lastUpdated)
      ..writeByte(7)
      ..write(obj.unreadCount)
      ..writeByte(8)
      ..write(obj.extra);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveRssFeedAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class HiveSettingsAdapter extends TypeAdapter<HiveSettings> {
  @override
  final int typeId = 8;

  @override
  HiveSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HiveSettings(
      key: fields[0] as String,
      value: fields[1] as dynamic,
      updatedAt: fields[2] as int,
    );
  }

  @override
  void write(BinaryWriter writer, HiveSettings obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.key)
      ..writeByte(1)
      ..write(obj.value)
      ..writeByte(2)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiveSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
