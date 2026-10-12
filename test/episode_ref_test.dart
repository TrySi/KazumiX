import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/roads/road_episode_availability.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/player/controller/player_models.dart';
import 'package:kazumi/pages/video/video_controller.dart';

void main() {
  group('EpisodeRef', () {
    test(
      'online keeps list index for history and parses title for danmaku',
      () {
        final episode = EpisodeRef.online(
          listIndex: 1,
          roadIndex: 0,
          displayTitle: '第13话',
          pageUrl: '/episode/13',
        );

        expect(episode.historyEpisodeNumber, 1);
        expect(episode.danmakuEpisodeNumber, 13);
        expect(episode.sortNumber, 13);
        expect(episode.originalRoadIndex, 0);
        expect(episode.pageUrl, '/episode/13');
      },
    );

    test(
      'online falls back to list index when title has no episode number',
      () {
        final episode = EpisodeRef.online(
          listIndex: 2,
          roadIndex: 1,
          displayTitle: 'OVA',
          pageUrl: '/ova',
        );

        expect(episode.historyEpisodeNumber, 2);
        expect(episode.danmakuEpisodeNumber, 2);
        expect(episode.sortNumber, isNull);
        expect(episode.originalRoadIndex, 1);
      },
    );

    test('offline uses downloaded episode number for history and danmaku', () {
      const episode = EpisodeRef.offline(
        listIndex: 1,
        roadIndex: 0,
        displayTitle: '第13话',
        pageUrl: '/episode/13',
        episodeNumber: 13,
        originalRoadIndex: 2,
      );

      expect(episode.historyEpisodeNumber, 13);
      expect(episode.danmakuEpisodeNumber, 13);
      expect(episode.sortNumber, 13);
      expect(episode.originalRoadIndex, 2);
      expect(episode.listIndex, 1);
      expect(episode.pageUrl, '/episode/13');
    });
  });

  test('PlaybackInitParams carries danmaku episode independently', () {
    const params = PlaybackInitParams(
      videoUrl: 'file:///tmp/video.mp4',
      offset: 0,
      isLocalPlayback: true,
      bangumiId: 1,
      pluginName: 'plugin',
      episode: 1,
      danmakuEpisodeNumber: 13,
      httpHeaders: {},
      adBlockerEnabled: false,
      episodeTitle: '第13话',
      referer: '',
      currentRoad: 0,
    );

    expect(params.episode, 1);
    expect(params.danmakuEpisodeNumber, 13);
  });

  group('OfflineRoadListSnapshot', () {
    test('merges downloaded episodes into a single sorted list', () {
      final snapshot = buildOfflineRoadListSnapshot([
        _episode(2, '第二话', 2),
        _episode(1, '第一话', 0),
        _episode(4, '第四话', 2),
        _episode(3, '第三话', 0),
      ]);

      expect(snapshot.roads.length, 1);
      expect(snapshot.roads[0].data, ['1', '2', '3', '4']);
      expect(snapshot.roads[0].identifier, ['第一话', '第二话', '第三话', '第四话']);
      expect(snapshot.episodesByNumber.keys.toList()..sort(), [1, 2, 3, 4]);
    });

    test('keeps the first source when an episode is downloaded twice', () {
      final snapshot = buildOfflineRoadListSnapshot([
        _episode(1, '第一话 A', 0),
        _episode(1, '第一话 B', 2),
      ]);

      expect(snapshot.roads.length, 1);
      expect(snapshot.roads[0].data, ['1']);
      expect(snapshot.roads[0].identifier, ['第一话 A']);
      expect(snapshot.episodesByNumber[1]!.road, 0);
    });
  });

  group('Road episode availability', () {
    test('filters unreleased and non-main episodes', () {
      final episodes = releasedMainEpisodes([
        _bangumiEpisode(1, airDate: DateTime(2026, 10, 1)),
        _bangumiEpisode(2, airDate: DateTime(2026, 11, 1)),
        _bangumiEpisode(3, type: 1, airDate: DateTime(2026, 9, 1)),
      ], now: DateTime(2026, 10, 11));

      expect(episodes.map((episode) => episode.episode), [1]);
    });

    test('maps only matching aired episodes from a road', () {
      final matches = matchRoadEpisodes(
        [
          _bangumiEpisode(1, airDate: DateTime(2026, 10, 1)),
          _bangumiEpisode(2, airDate: DateTime(2026, 10, 8)),
          _bangumiEpisode(3, airDate: DateTime(2026, 10, 15)),
        ],
        road: Road(
          name: '线路 1',
          data: ['/episode/1', '/episode/3'],
          identifier: ['第1话', '第3话'],
        ),
      );

      expect(matches.keys, [1, 3]);
      expect(matches[3]?.episodeIndex, 2);
      expect(matches[3]?.pageUrl, '/episode/3');
    });
  });
}

EpisodeInfo _bangumiEpisode(
  int episode, {
  int type = 0,
  required DateTime airDate,
}) {
  return EpisodeInfo(
    id: episode,
    episode: episode,
    type: type,
    name: 'Episode $episode',
    nameCn: '第$episode话',
    airDate: airDate,
  );
}

DownloadEpisode _episode(int episodeNumber, String name, int road) {
  return DownloadEpisode(
    episodeNumber,
    name,
    road,
    DownloadStatus.completed,
    1.0,
    0,
    0,
    '',
    '',
    '',
    DateTime(2026),
    '',
    0,
    '/episode/$episodeNumber',
  );
}
