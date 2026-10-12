import 'package:kazumi/modules/download/download_module.dart';

/// One downloaded episode, keeping the record (source) that owns it.
///
/// A show can be downloaded from several sources, and the same episode number
/// can exist in more than one record, so the owner has to travel with the
/// episode: playback resolves the local file through it.
class DownloadEntry {
  const DownloadEntry({required this.record, required this.episode});

  final DownloadRecord record;
  final DownloadEpisode episode;
}

/// A bangumi's downloads aggregated across every source that has any.
///
/// Both lists are ordered by [DownloadRecord.compareBySource], so the show's
/// name and cover and the source that wins a duplicated episode stay stable
/// across rebuilds instead of following container iteration order.
class ShowDownloads {
  const ShowDownloads({
    required this.primaryRecord,
    required this.records,
    required this.entries,
    required this.latestTime,
  });

  /// Supplies the show's identity (name and cover) and wins a duplicated
  /// episode when several sources downloaded the same bangumi.
  final DownloadRecord primaryRecord;

  /// Every record contributing to this show, ordered by source.
  final List<DownloadRecord> records;

  /// Every downloaded episode of every source, ordered by episode number.
  final List<DownloadEntry> entries;

  /// Newest [DownloadRecord.createdAt] across [records].
  final DateTime latestTime;

  String get key => '$bangumiId';
  int get bangumiId => primaryRecord.bangumiId;
  String get bangumiName => primaryRecord.bangumiName;
  String get coverSource => primaryRecord.coverSource;
}

/// Groups [records] into one [ShowDownloads] per bangumi.
///
/// The bangumis keep the order they were first seen in; callers apply their own
/// sort, because the download and offline pages order shows differently.
List<ShowDownloads> groupDownloadsByShow(Iterable<DownloadRecord> records) {
  final byBangumi = <int, List<DownloadRecord>>{};
  for (final record in records) {
    byBangumi.putIfAbsent(record.bangumiId, () => []).add(record);
  }

  final shows = <ShowDownloads>[];
  for (final group in byBangumi.values) {
    group.sort(DownloadRecord.compareBySource);

    final entries = <DownloadEntry>[];
    var latestTime = DateTime(0);
    for (final record in group) {
      if (record.createdAt.isAfter(latestTime)) latestTime = record.createdAt;
      for (final episode in record.episodes.values) {
        entries.add(DownloadEntry(record: record, episode: episode));
      }
    }
    entries.sort((a, b) {
      final byNumber = a.episode.episodeNumber.compareTo(
        b.episode.episodeNumber,
      );
      if (byNumber != 0) return byNumber;
      // List.sort is not stable and the first source to carry an episode wins
      // downstream, so the tie is broken explicitly.
      return DownloadRecord.compareBySource(a.record, b.record);
    });

    shows.add(
      ShowDownloads(
        primaryRecord: group.first,
        records: group,
        entries: entries,
        latestTime: latestTime,
      ),
    );
  }
  return shows;
}
