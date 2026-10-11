import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/utils/media.dart';

class RoadEpisodeMatch {
  const RoadEpisodeMatch({
    required this.roadIndex,
    required this.episodeIndex,
    required this.pageUrl,
    required this.title,
  });

  final int roadIndex;
  final int episodeIndex;
  final String pageUrl;
  final String title;
}

List<EpisodeInfo> releasedMainEpisodes(
  Iterable<EpisodeInfo> episodes, {
  DateTime? now,
}) {
  final currentTime = now ?? DateTime.now();
  final released = episodes.where((episode) {
    return episode.type == 0 &&
        episode.episode > 0 &&
        episode.episode == episode.episode.roundToDouble() &&
        (episode.airDate == null || !episode.airDate!.isAfter(currentTime));
  }).toList();
  released.sort((first, second) => first.episode.compareTo(second.episode));
  return released;
}

Map<int, RoadEpisodeMatch> matchRoadEpisodes(
  Iterable<EpisodeInfo> episodes, {
  required Road road,
  int roadIndex = 0,
}) {
  final expectedNumbers = {
    for (final episode in episodes)
      if (episode.episode > 0 &&
          episode.episode == episode.episode.roundToDouble())
        episode.episode.toInt(),
  };
  final matches = <int, RoadEpisodeMatch>{};
  final itemCount = road.data.length < road.identifier.length
      ? road.data.length
      : road.identifier.length;

  for (
    var roadEpisodeIndex = 0;
    roadEpisodeIndex < itemCount;
    roadEpisodeIndex++
  ) {
    final title = road.identifier[roadEpisodeIndex];
    final episodeNumber = extractEpisodeNumber(title);
    if (!expectedNumbers.contains(episodeNumber) ||
        road.data[roadEpisodeIndex].isEmpty) {
      continue;
    }
    matches.putIfAbsent(
      episodeNumber,
      () => RoadEpisodeMatch(
        roadIndex: roadIndex,
        episodeIndex: roadEpisodeIndex + 1,
        pageUrl: road.data[roadEpisodeIndex],
        title: title,
      ),
    );
  }
  return matches;
}
