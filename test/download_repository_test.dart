import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

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
  late Directory directory;
  late PathProviderPlatform originalPathProvider;
  late DownloadRepository repository;

  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_download_test_');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
    repository = DownloadRepository();
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPathProvider;
    await directory.delete(recursive: true);
  });

  setUp(() async {
    await GStorage.downloads.clear();
  });

  group('getCompletedEpisodesAcrossSources', () {
    test('merges every source, deduplicated and sorted by episode', () async {
      await GStorage.downloads.put(
        'alpha_1',
        _record(1, 'alpha', {
          1: DownloadStatus.completed,
          3: DownloadStatus.completed,
          5: DownloadStatus.downloading,
        }),
      );
      await GStorage.downloads.put(
        'beta_1',
        _record(1, 'beta', {
          2: DownloadStatus.completed,
          3: DownloadStatus.completed,
          4: DownloadStatus.completed,
        }),
      );

      final plugins = <int, String>{};
      final episodes = repository.getCompletedEpisodesAcrossSources(
        1,
        pluginByNumber: plugins,
      );

      expect(episodes.map((e) => e.episodeNumber), [1, 2, 3, 4]);
      // Episode 3 exists in both sources; the first one wins.
      expect(plugins[1], 'alpha');
      expect(plugins[2], 'beta');
      expect(plugins[3], 'alpha');
      expect(plugins[4], 'beta');
    });

    test('ignores other bangumis and unfinished episodes', () async {
      await GStorage.downloads.put(
        'alpha_1',
        _record(1, 'alpha', {1: DownloadStatus.completed}),
      );
      await GStorage.downloads.put(
        'alpha_2',
        _record(2, 'alpha', {1: DownloadStatus.completed}),
      );
      await GStorage.downloads.put(
        'beta_1',
        _record(1, 'beta', {
          2: DownloadStatus.paused,
          3: DownloadStatus.failed,
          4: DownloadStatus.pending,
        }),
      );

      final episodes = repository.getCompletedEpisodesAcrossSources(1);

      expect(episodes.map((e) => e.episodeNumber), [1]);
    });

    test('returns an empty list when nothing is downloaded', () {
      expect(repository.getCompletedEpisodesAcrossSources(999), isEmpty);
    });
  });

  group('DownloadRecord.toBangumiItem', () {
    test('carries the identity and cover used by offline playback', () {
      final record = _record(7, 'alpha', {1: DownloadStatus.completed});

      final item = record.toBangumiItem();

      expect(item.id, 7);
      expect(item.nameCn, '番剧7');
      expect(item.images['large'], 'https://example.com/7.jpg');
    });

    test('prefers the local cover when one was downloaded', () {
      final record = DownloadRecord(
        7,
        '番剧7',
        'https://example.com/7.jpg',
        'alpha',
        {1: _episode(1, DownloadStatus.completed)},
        DateTime(2026),
        localCoverPath: '/covers/7.jpg',
      );

      expect(record.toBangumiItem().images['large'], record.coverSource);
      expect(record.coverSource, contains('/covers/7.jpg'));
    });
  });
}
