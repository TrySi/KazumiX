import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/download/download_show_group.dart';

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

DownloadRecord _record(
  int bangumiId,
  String plugin,
  Map<int, int> statuses, {
  DateTime? createdAt,
  String? name,
}) => DownloadRecord(
  bangumiId,
  name ?? '番剧$bangumiId',
  'https://example.com/$bangumiId.jpg',
  plugin,
  {
    for (final entry in statuses.entries)
      entry.key: _episode(entry.key, entry.value),
  },
  createdAt ?? DateTime(2026),
);

void main() {
  test('merges every source of a bangumi into one show', () {
    final shows = groupDownloadsByShow([
      _record(1, 'alpha', {1: DownloadStatus.completed}),
      _record(1, 'beta', {2: DownloadStatus.completed}),
      _record(2, 'alpha', {1: DownloadStatus.completed}),
    ]);

    expect(shows.map((s) => s.bangumiId), [1, 2]);
    final show = shows.first;
    expect(show.records.map((r) => r.pluginName), ['alpha', 'beta']);
    expect(show.entries.map((e) => e.episode.episodeNumber), [1, 2]);
    expect(show.entries.map((e) => e.record.pluginName), ['alpha', 'beta']);
  });

  test('identity comes from the earliest source', () {
    final shows = groupDownloadsByShow([
      // Inserted later, but downloaded first, so it owns the name and cover.
      _record(
        1,
        'beta',
        {1: DownloadStatus.completed},
        createdAt: DateTime(2026, 5),
        name: 'beta 命名',
      ),
      _record(
        1,
        'alpha',
        {1: DownloadStatus.completed},
        createdAt: DateTime(2026, 1),
        name: 'alpha 命名',
      ),
    ]);

    expect(shows.single.bangumiName, 'alpha 命名');
    expect(shows.single.primaryRecord.pluginName, 'alpha');
    expect(shows.single.records.map((r) => r.pluginName), ['alpha', 'beta']);
  });

  test('a duplicated episode is kept per source, earliest source first', () {
    final shows = groupDownloadsByShow([
      _record(1, 'zeta', {
        3: DownloadStatus.completed,
      }, createdAt: DateTime(2026, 6)),
      _record(1, 'alpha', {
        3: DownloadStatus.completed,
      }, createdAt: DateTime(2026, 2)),
    ]);

    // Entries are not deduplicated here: the download page shows one tile per
    // source, and the offline page dedups by taking the first entry.
    final entries = shows.single.entries;
    expect(entries.length, 2);
    expect(entries.map((e) => e.record.pluginName), ['alpha', 'zeta']);
    expect(entries.first.episode.episodeNumber, 3);
  });

  test('latestTime is the newest record timestamp', () {
    final shows = groupDownloadsByShow([
      _record(1, 'alpha', {1: 0}, createdAt: DateTime(2026, 1)),
      _record(1, 'beta', {2: 0}, createdAt: DateTime(2026, 9, 3)),
    ]);

    expect(shows.single.latestTime, DateTime(2026, 9, 3));
  });

  test('keeps every status of an episode, not just completed ones', () {
    final shows = groupDownloadsByShow([
      _record(1, 'alpha', {
        1: DownloadStatus.completed,
        2: DownloadStatus.downloading,
        3: DownloadStatus.failed,
      }),
    ]);

    expect(shows.single.entries.map((e) => e.episode.status), [
      DownloadStatus.completed,
      DownloadStatus.downloading,
      DownloadStatus.failed,
    ]);
  });

  test('no records yields no shows', () {
    expect(groupDownloadsByShow(const []), isEmpty);
  });
}
