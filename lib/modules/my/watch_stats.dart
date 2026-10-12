import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/history/history_module.dart';

final class WatchStats {
  const WatchStats({
    this.watchedEpisodeCount = 0,
    this.watchedBangumiCount = 0,
    this.downloadTaskCount = 0,
    this.completedCount = 0,
    this.downloadingCount = 0,
    this.pausedCount = 0,
    this.failedCount = 0,
  });

  final int watchedEpisodeCount;
  final int watchedBangumiCount;
  final int downloadTaskCount;
  final int completedCount;
  final int downloadingCount;
  final int pausedCount;
  final int failedCount;

  @override
  bool operator ==(Object other) =>
      other is WatchStats &&
      other.watchedEpisodeCount == watchedEpisodeCount &&
      other.watchedBangumiCount == watchedBangumiCount &&
      other.downloadTaskCount == downloadTaskCount &&
      other.completedCount == completedCount &&
      other.downloadingCount == downloadingCount &&
      other.pausedCount == pausedCount &&
      other.failedCount == failedCount;

  @override
  int get hashCode => Object.hash(
    watchedEpisodeCount,
    watchedBangumiCount,
    downloadTaskCount,
    completedCount,
    downloadingCount,
    pausedCount,
    failedCount,
  );

  factory WatchStats.from({
    required List<History> histories,
    required List<DownloadRecord> downloadRecords,
  }) {
    // Deduplicate episodes across rules and online/offline histories.
    final watchedEpisodes = <(int, int)>{};
    final watchedBangumiIds = <int>{};
    for (final history in histories) {
      if (history.progresses.isEmpty) continue;
      final bangumiId = history.bangumiItem.id;
      watchedBangumiIds.add(bangumiId);
      for (final episode in history.progresses.keys) {
        watchedEpisodes.add((bangumiId, episode));
      }
    }

    // Deduplicate by (bangumi id, episode number) so an episode downloaded from
    // several sources is counted once, matching the download and offline pages.
    // A finished copy wins over an in-flight or failed one.
    final statusByEpisode = <(int, int), int>{};
    for (final record in downloadRecords) {
      for (final episode in record.episodes.values) {
        final key = (record.bangumiId, episode.episodeNumber);
        final current = statusByEpisode[key];
        if (current == null ||
            _statusRank(episode.status) < _statusRank(current)) {
          statusByEpisode[key] = episode.status;
        }
      }
    }

    var completed = 0;
    var downloading = 0;
    var paused = 0;
    var failed = 0;
    for (final status in statusByEpisode.values) {
      switch (status) {
        case DownloadStatus.completed:
          completed++;
        case DownloadStatus.downloading:
        case DownloadStatus.resolving:
        case DownloadStatus.pending:
          downloading++;
        case DownloadStatus.paused:
          paused++;
        case DownloadStatus.failed:
          failed++;
      }
    }

    return WatchStats(
      watchedEpisodeCount: watchedEpisodes.length,
      watchedBangumiCount: watchedBangumiIds.length,
      // Count every download task, regardless of status.
      downloadTaskCount: downloadRecords.fold(
        0,
        (count, record) => count + record.episodes.length,
      ),
      completedCount: completed,
      downloadingCount: downloading,
      pausedCount: paused,
      failedCount: failed,
    );
  }

  /// Lower is better, so a duplicated episode is reported by its most complete
  /// download: a finished copy outranks an in-flight, paused or failed one.
  static int _statusRank(int status) => switch (status) {
    DownloadStatus.completed => 0,
    DownloadStatus.downloading ||
    DownloadStatus.resolving ||
    DownloadStatus.pending => 1,
    DownloadStatus.paused => 2,
    DownloadStatus.failed => 3,
    _ => 4,
  };
}
