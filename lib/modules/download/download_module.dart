import 'package:hive_ce/hive.dart';

import 'package:kazumi/modules/bangumi/bangumi_item.dart';

part 'download_module.g.dart';

@HiveType(typeId: 7)
class DownloadRecord {
  @HiveField(0)
  int bangumiId;

  @HiveField(1)
  String bangumiName;

  @HiveField(2)
  String bangumiCover;

  @HiveField(3)
  String pluginName;

  @HiveField(4)
  Map<int, DownloadEpisode> episodes;

  @HiveField(5)
  DateTime createdAt;

  @HiveField(6, defaultValue: '')
  String localCoverPath;

  String get key => '${pluginName}_$bangumiId';

  /// Orders records by download recency, then by source name.
  ///
  /// Used wherever the "first" record of a show has to be stable across
  /// rebuilds: it supplies the show's name and cover, and it wins when several
  /// sources downloaded the same episode. Without an explicit order that
  /// winner would follow container iteration order and could change between
  /// the in-memory list and the storage box.
  static int compareBySource(DownloadRecord a, DownloadRecord b) {
    final byRecency = a.createdAt.compareTo(b.createdAt);
    return byRecency != 0 ? byRecency : a.pluginName.compareTo(b.pluginName);
  }

  DownloadRecord(
    this.bangumiId,
    this.bangumiName,
    this.bangumiCover,
    this.pluginName,
    this.episodes,
    this.createdAt, {
    this.localCoverPath = '',
  });

  String get coverSource => localCoverPath.isEmpty
      ? bangumiCover
      : Uri.file(localCoverPath).toString();

  /// Minimal [BangumiItem] for offline playback, built from what a download
  /// record stores. Offline playback only needs the id, the title and the
  /// cover, so the remaining fields stay empty.
  BangumiItem toBangumiItem() => BangumiItem(
    id: bangumiId,
    type: 2,
    name: bangumiName,
    nameCn: bangumiName,
    summary: '',
    airDate: '',
    airWeekday: 0,
    rank: 0,
    images: {'large': coverSource},
    tags: [],
    alias: [],
    ratingScore: 0.0,
    votes: 0,
    votesCount: [],
    info: '',
  );
}

@HiveType(typeId: 8)
class DownloadEpisode {
  @HiveField(0)
  int episodeNumber;

  @HiveField(1)
  String episodeName;

  @HiveField(2)
  int road;

  /// 0=pending 1=resolving 2=downloading 3=completed 4=failed 5=paused
  @HiveField(3)
  int status;

  @HiveField(4)
  double progressPercent;

  @HiveField(5)
  int totalSegments;

  @HiveField(6)
  int downloadedSegments;

  @HiveField(7)
  String localM3u8Path;

  @HiveField(8)
  String downloadDirectory;

  @HiveField(9)
  String networkM3u8Url;

  @HiveField(10)
  DateTime? completedAt;

  @HiveField(11, defaultValue: '')
  String errorMessage;

  @HiveField(12, defaultValue: 0)
  int totalBytes;

  @HiveField(13, defaultValue: '')
  String episodePageUrl;

  /// 缓存的弹幕数据 (JSON 字符串格式)
  @HiveField(14, defaultValue: '')
  String danmakuData;

  /// DanDanPlay 番剧 ID (用于弹幕查询缓存)
  @HiveField(15, defaultValue: 0)
  int danDanBangumiID;

  DownloadEpisode(
    this.episodeNumber,
    this.episodeName,
    this.road,
    this.status,
    this.progressPercent,
    this.totalSegments,
    this.downloadedSegments,
    this.localM3u8Path,
    this.downloadDirectory,
    this.networkM3u8Url,
    this.completedAt,
    this.errorMessage,
    this.totalBytes,
    this.episodePageUrl, {
    this.danmakuData = '',
    this.danDanBangumiID = 0,
  });
}

class DownloadStatus {
  static const int pending = 0;
  static const int resolving = 1;
  static const int downloading = 2;
  static const int completed = 3;
  static const int failed = 4;
  static const int paused = 5;
}
