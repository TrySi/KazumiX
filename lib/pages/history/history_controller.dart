import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:mobx/mobx.dart';

part 'history_controller.g.dart';

/// One offline watch-state edit, so several can be applied in a single batch.
typedef EpisodeWatchUpdate = ({
  BangumiItem bangumiItem,
  String adapterName,
  int episode,
  String episodeTitle,
  int road,
  bool watched,
});

class HistoryController = _HistoryController with _$HistoryController;

abstract class _HistoryController with Store {
  _HistoryController(this._historyRepository);

  final IHistoryRepository _historyRepository;

  @observable
  ObservableList<History> histories = ObservableList<History>();

  void init() {
    final temp = _historyRepository.getAllHistories();
    histories.clear();
    histories.addAll(temp);
  }

  Future<void> updateHistory(
    PlaybackHistoryIdentity identity,
    Duration progress, {
    Duration duration = Duration.zero,
  }) async {
    await _historyRepository.updateHistory(
      identity: identity,
      progress: progress,
      duration: duration,
    );
    init();
  }

  /// Marks or unmarks a single offline episode as watched, then refreshes the
  /// in-memory list so derived watch states update immediately.
  Future<void> setEpisodeWatched({
    required BangumiItem bangumiItem,
    required String adapterName,
    required int episode,
    required String episodeTitle,
    required int road,
    required bool watched,
  }) async {
    await _historyRepository.setEpisodeWatched(
      bangumiItem: bangumiItem,
      adapterName: adapterName,
      episode: episode,
      episodeTitle: episodeTitle,
      road: road,
      watched: watched,
    );
    init();
  }

  /// Applies several offline watch-state edits and refreshes the in-memory
  /// list once, instead of re-reading the whole history box per episode.
  /// Returns how many edits were actually applied.
  Future<int> setEpisodesWatched(Iterable<EpisodeWatchUpdate> updates) async {
    var applied = 0;
    for (final update in updates) {
      final ok = await _historyRepository.setEpisodeWatched(
        bangumiItem: update.bangumiItem,
        adapterName: update.adapterName,
        episode: update.episode,
        episodeTitle: update.episodeTitle,
        road: update.road,
        watched: update.watched,
      );
      if (ok) applied++;
    }
    init();
    return applied;
  }

  Progress? lastWatching(
    BangumiItem bangumiItem,
    String adapterName, {
    String entryKind = HistoryEntryKind.online,
  }) {
    return _historyRepository.getLastWatchingProgress(
      bangumiItem,
      adapterName,
      entryKind: entryKind,
    );
  }

  Progress? findProgress(
    BangumiItem bangumiItem,
    String adapterName,
    int episode, {
    String entryKind = HistoryEntryKind.online,
  }) {
    return _historyRepository.findProgress(
      bangumiItem,
      adapterName,
      episode,
      entryKind: entryKind,
    );
  }

  Future<void> deleteHistory(History history) async {
    await _historyRepository.deleteHistory(history);
    init();
  }

  Future<void> clearAll() async {
    await _historyRepository.clearAllHistories();
    histories.clear();
  }
}
