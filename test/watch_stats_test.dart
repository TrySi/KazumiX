import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/my/watch_stats.dart';

DownloadEpisode _episode(int number, int status) => DownloadEpisode(
  number,
  '第$number话',
  0,
  status,
  1,
  1,
  1,
  '/video/$number.mp4',
  '/dir/$number',
  '',
  status == DownloadStatus.completed ? DateTime(2026) : null,
  '',
  42,
  '',
);

DownloadRecord _record(int bangumiId, String plugin, Map<int, int> statuses) =>
    DownloadRecord(
      bangumiId,
      '番剧$bangumiId',
      'https://example.com/$bangumiId.jpg',
      plugin,
      {
        for (final entry in statuses.entries)
          entry.key: _episode(entry.key, entry.value),
      },
      DateTime(2026),
    );

void main() {
  test('counts an episode downloaded from several sources once', () {
    final stats = WatchStats.from(
      histories: const [],
      downloadRecords: [
        _record(1, 'alpha', {
          1: DownloadStatus.completed,
          2: DownloadStatus.downloading,
        }),
        _record(1, 'beta', {
          1: DownloadStatus.completed,
          3: DownloadStatus.completed,
        }),
      ],
    );

    // Episode 1 exists in both sources but is one downloaded episode.
    expect(stats.completedCount, 2);
    expect(stats.downloadingCount, 1);
    // Tasks are still counted per source (2 + 2).
    expect(stats.downloadTaskCount, 4);
  });

  test('a finished copy outranks a failed one for the same episode', () {
    final stats = WatchStats.from(
      histories: const [],
      downloadRecords: [
        _record(1, 'alpha', {1: DownloadStatus.failed}),
        _record(1, 'beta', {1: DownloadStatus.completed}),
      ],
    );

    expect(stats.completedCount, 1);
    expect(stats.failedCount, 0);
  });

  test('falls back to the least broken state when nothing finished', () {
    final stats = WatchStats.from(
      histories: const [],
      downloadRecords: [
        _record(1, 'alpha', {1: DownloadStatus.failed}),
        _record(1, 'beta', {1: DownloadStatus.paused}),
      ],
    );

    expect(stats.completedCount, 0);
    expect(stats.pausedCount, 1);
    expect(stats.failedCount, 0);
  });

  test('the same episode number in different bangumis stays distinct', () {
    final stats = WatchStats.from(
      histories: const [],
      downloadRecords: [
        _record(1, 'alpha', {1: DownloadStatus.completed}),
        _record(2, 'alpha', {1: DownloadStatus.completed}),
      ],
    );

    expect(stats.completedCount, 2);
  });
}
