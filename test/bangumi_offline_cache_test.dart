import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_tag.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/repositories/bangumi_offline_cache_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  test('BangumiItem cache JSON round trips public metadata', () {
    final item = BangumiItem(
      id: 42,
      type: 2,
      name: 'Example',
      nameCn: '示例番剧',
      summary: '简介',
      airDate: '2026-04-01',
      airWeekday: 3,
      rank: 12,
      images: {'large': 'https://example.test/cover.jpg'},
      tags: [BangumiTag(name: '科幻', count: 3, totalCount: 10)],
      alias: ['别名'],
      ratingScore: 8.6,
      votes: 120,
      votesCount: [1, 2, 3],
      info: '制作信息',
      metaTags: const ['TV'],
    );

    final restored = BangumiItem.fromJson(item.toCacheJson());

    expect(restored.id, item.id);
    expect(restored.name, item.name);
    expect(restored.nameCn, item.nameCn);
    expect(restored.summary, item.summary);
    expect(restored.airDate, item.airDate);
    expect(restored.rank, item.rank);
    expect(restored.images, item.images);
    expect(restored.tags.single.name, '科幻');
    expect(restored.alias, item.alias);
    expect(restored.ratingScore, item.ratingScore);
    expect(restored.votes, item.votes);
    expect(restored.votesCount.take(3), item.votesCount);
    expect(restored.info, item.info);
    expect(restored.metaTags, item.metaTags);
    expect(restored.interest, isNull);
    expect(restored.offlineCover, isNull);
    expect(restored.displayCover, 'https://example.test/cover.jpg');

    final covered = BangumiItem.fromJson(
      item.withOfflineCover('file:///covers/42').toCacheJson(),
    );

    expect(covered.offlineCover, 'file:///covers/42');
    expect(covered.displayCover, 'file:///covers/42');
  });

  test('offline cache stores subjects, calendars, and episodes', () async {
    final box = _MemoryStringBox();
    final cache = BangumiOfflineCacheRepository(box: box);
    final subject = _subject();
    final episode = EpisodeInfo(
      id: 4201,
      episode: 1,
      type: 0,
      name: 'Episode 1',
      nameCn: '第一集',
      airDate: DateTime(2026, 4, 1),
    );

    await cache.writeSubjects('collectibles', [subject]);
    await cache.writeCalendar('calendar:season:2026-04-01', [
      [subject],
      [],
    ]);
    await cache.writeEpisodes(subject.id, [episode]);

    expect(cache.readSubjects('collectibles')!.single.id, subject.id);
    expect(
      cache.readCalendar('calendar:season:2026-04-01')!.first.single.id,
      subject.id,
    );
    expect(cache.readEpisodes(subject.id)!.single.nameCn, '第一集');
    expect(cache.isFresh('collectibles', const Duration(hours: 1)), isTrue);
  });

  test('offline cache keeps local covers across metadata refreshes', () async {
    final box = _MemoryStringBox();
    final cache = BangumiOfflineCacheRepository(box: box);
    final directory = await Directory.systemTemp.createTemp(
      'kazumi_offline_cover',
    );
    addTearDown(() => directory.delete(recursive: true));
    final coverFile = File(path.join(directory.path, '42'));
    await coverFile.writeAsBytes(const [1, 2, 3]);
    final cover = coverFile.uri.toString();

    await cache.writeSubject(_subject()..offlineCover = cover);
    expect(cache.readSubject(42)!.displayCover, cover);

    // A fresh snapshot arrives without the local cover; the stored one wins.
    await cache.writeSubject(_subject());
    expect(cache.readSubject(42)!.offlineCover, cover);

    // Calendar snapshots keep the cover of the subjects they already hold.
    await cache.writeCalendar('calendar:current-week', [
      [_subject()..offlineCover = cover],
    ]);
    await cache.writeCalendar('calendar:current-week', [
      [_subject()],
    ]);
    expect(
      cache.readCalendar('calendar:current-week')!.first.single.offlineCover,
      cover,
    );

    // Covers whose file disappeared fall back to the remote URL.
    await coverFile.delete();
    final restored = cache.readSubject(42)!;

    expect(restored.offlineCover, isNull);
    expect(restored.displayCover, 'https://example.test/cover.jpg');
  });

  test(
    'retains only subjects and calendar keys in the offline scope',
    () async {
      final box = _MemoryStringBox();
      final cache = BangumiOfflineCacheRepository(box: box);
      await cache.writeSubject(_subject());
      await cache.writeSubject(_subject()..id = 99);
      await cache.writeEpisodes(42, []);
      await cache.writeEpisodes(99, []);
      await cache.writeCalendar('calendar:current-week', [
        [_subject()],
      ]);
      await cache.writeCalendar('calendar:season:2026-04-01:2026-07-01', [
        [_subject()],
      ]);
      await cache.writeCalendar('calendar:season:2025-01-01:2025-04-01', [
        [_subject()],
      ]);

      await cache.retainOfflineScope(
        subjectIds: {42},
        calendarKeys: {
          'calendar:current-week',
          'calendar:season:2026-04-01:2026-07-01',
        },
      );

      expect(cache.readSubject(42), isNotNull);
      expect(cache.readSubject(99), isNull);
      expect(cache.readEpisodes(42), isEmpty);
      expect(cache.readEpisodes(99), isNull);
      expect(cache.readCalendar('calendar:current-week'), isNotNull);
      expect(
        cache.readCalendar('calendar:season:2025-01-01:2025-04-01'),
        isNull,
      );
    },
  );
}

BangumiItem _subject() => BangumiItem(
  id: 42,
  type: 2,
  name: 'Example',
  nameCn: '示例番剧',
  summary: '简介',
  airDate: '2026-04-01',
  airWeekday: 3,
  rank: 12,
  images: {'large': 'https://example.test/cover.jpg'},
  tags: [],
  alias: [],
  ratingScore: 8.6,
  votes: 120,
  votesCount: [],
  info: '',
);

class _MemoryStringBox implements Box<String> {
  final Map<dynamic, String> _values = {};

  @override
  Iterable<dynamic> get keys => _values.keys;

  @override
  String? get(dynamic key, {String? defaultValue}) =>
      _values[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(dynamic key) async {
    _values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
