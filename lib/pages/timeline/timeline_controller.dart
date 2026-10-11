import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/utils/anime_season.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/bangumi_offline_cache_repository.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:mobx/mobx.dart';

part 'timeline_controller.g.dart';

enum TimelineSort { popularity, rating, defaultOrder }

class TimelineController = _TimelineController with _$TimelineController;

abstract class _TimelineController with Store {
  _TimelineController(this._collectRepository);

  final ICollectRepository _collectRepository;
  final _offlineCache = BangumiOfflineCacheRepository();

  @observable
  ObservableList<List<BangumiItem>> bangumiCalendar =
      ObservableList<List<BangumiItem>>();

  @readonly
  DateTime _selectedDate = DateTime.now();

  @observable
  bool isLoading = false;

  @observable
  bool isTimeOut = false;

  @observable
  late bool notShowAbandonedBangumis = _collectRepository
      .getTimelineNotShowAbandonedBangumis();

  @observable
  late bool notShowWatchedBangumis = _collectRepository
      .getTimelineNotShowWatchedBangumis();

  @observable
  late bool onlyShowWatchingBangumis = _collectRepository
      .getTimelineOnlyShowWatchingBangumis();

  @readonly
  TimelineSort _sort = TimelineSort.popularity;

  bool get _bangumiMirrorEnabled =>
      BangumiAcceleration.current == BangumiAcceleration.mirror;

  @action
  Future<void> loadSeason(DateTime date) async {
    if (isLoading) return;
    _selectedDate = date;
    final currentSeason = isSameSeason(date, DateTime.now());
    final dateRange = currentSeason
        ? null
        : AnimeSeason(date).toSeasonStartAndEnd();
    final cacheKey = currentSeason
        ? 'calendar:current-week'
        : _seasonCacheAllowed(date)
        ? 'calendar:season:${dateRange![0]}:${dateRange[1]}'
        : null;
    final cached = cacheKey == null
        ? null
        : _offlineCache.readCalendar(cacheKey);
    final cacheTtl = currentSeason
        ? const Duration(hours: 6)
        : dateRange == null
        ? const Duration(hours: 6)
        : _seasonCacheAllowed(date)
        ? _quarterDistance(date) == 0
              ? const Duration(hours: 12)
              : const Duration(days: 7)
        : Duration.zero;
    final hasFreshCache =
        cacheKey != null && _offlineCache.isFresh(cacheKey, cacheTtl);
    bangumiCalendar
      ..clear()
      ..addAll(cached ?? const []);
    isTimeOut = bangumiCalendar.every((day) => day.isEmpty);
    if (hasFreshCache && !isTimeOut) {
      changeSort(_sort);
      return;
    }
    isLoading = true;

    try {
      if (currentSeason) {
        final fresh = await BangumiApi.getCalendar();
        if (fresh.any((day) => day.isNotEmpty)) {
          bangumiCalendar
            ..clear()
            ..addAll(fresh);
        }
      } else {
        await _getSchedulesBySeason(date);
      }
      if (bangumiCalendar.any((day) => day.isNotEmpty)) {
        if (cacheKey != null) {
          await _offlineCache.writeCalendar(cacheKey, bangumiCalendar);
        }
      }
      isTimeOut = bangumiCalendar.every((day) => day.isEmpty);
      if (!isTimeOut) changeSort(_sort);
    } catch (error, stackTrace) {
      isTimeOut = bangumiCalendar.every((day) => day.isEmpty);
      KazumiLogger().e(
        'Timeline: loading season failed',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      isLoading = false;
    }
  }

  bool _seasonCacheAllowed(DateTime date) {
    final distance = _quarterDistance(date);
    return distance >= 0 && distance < 4;
  }

  int _quarterDistance(DateTime date) {
    final now = DateTime.now();
    final currentMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    final selectedMonth = ((date.month - 1) ~/ 3) * 3 + 1;
    return (now.year - date.year) * 4 + (currentMonth - selectedMonth) ~/ 3;
  }

  @action
  Future<void> _getSchedulesBySeason(DateTime date) async {
    final dateRange = AnimeSeason(date).toSeasonStartAndEnd();
    if (_bangumiMirrorEnabled) {
      final fresh = await BangumiApi.getBangumiMirrorSeasonCalendar(dateRange);
      if (fresh.any((day) => day.isNotEmpty)) {
        bangumiCalendar
          ..clear()
          ..addAll(fresh);
      }
      return;
    }

    const pageCount = 4;
    const limit = 20;
    final resBangumiCalendar = List.generate(7, (_) => <BangumiItem>[]);
    for (var page = 0; page < pageCount; page++) {
      final newList = await BangumiApi.getCalendarBySearch(
        dateRange,
        limit,
        page * limit,
        rethrowNetworkError: true,
      );
      if (newList.every((day) => day.isEmpty)) {
        // No more results; a connectivity failure would have thrown instead.
        break;
      }
      for (int i = 0; i < resBangumiCalendar.length; ++i) {
        resBangumiCalendar[i].addAll(newList[i]);
      }
    }
    if (resBangumiCalendar.any((day) => day.isNotEmpty)) {
      bangumiCalendar
        ..clear()
        ..addAll(resBangumiCalendar);
    }
  }

  @action
  void changeSort(TimelineSort sort) {
    _sort = sort;
    final Comparator<BangumiItem> compare = switch (sort) {
      TimelineSort.popularity => (a, b) => b.votes.compareTo(a.votes),
      TimelineSort.rating => (a, b) => b.ratingScore.compareTo(a.ratingScore),
      TimelineSort.defaultOrder => (a, b) => a.id.compareTo(b.id),
    };
    final resBangumiCalendar = bangumiCalendar.toList();
    for (final dayList in resBangumiCalendar) {
      dayList.sort(compare);
    }
    bangumiCalendar.clear();
    bangumiCalendar.addAll(resBangumiCalendar);
  }

  @action
  Future<void> setNotShowAbandonedBangumis(bool value) async {
    notShowAbandonedBangumis = value;
    await _collectRepository.updateTimelineNotShowAbandonedBangumis(value);
  }

  @action
  Future<void> setNotShowWatchedBangumis(bool value) async {
    notShowWatchedBangumis = value;
    await _collectRepository.updateTimelineNotShowWatchedBangumis(value);
  }

  @action
  Future<void> setOnlyShowWatchingBangumis(bool value) async {
    onlyShowWatchingBangumis = value;
    await _collectRepository.updateTimelineOnlyShowWatchingBangumis(value);
  }

  Set<int> loadWatchingBangumiIds() {
    return _collectRepository.getBangumiIdsByType(CollectType.watching);
  }

  int get activeFilterCount => [
    onlyShowWatchingBangumis,
    notShowWatchedBangumis,
    notShowAbandonedBangumis,
  ].where((enabled) => enabled).length;

  List<List<BangumiItem>> filterCalendar(Set<int> watchingIds) {
    final abandonedIds = notShowAbandonedBangumis
        ? _collectRepository.getBangumiIdsByType(CollectType.abandoned)
        : <int>{};
    final watchedIds = notShowWatchedBangumis
        ? _collectRepository.getBangumiIdsByType(CollectType.watched)
        : <int>{};
    final onlyWatching = onlyShowWatchingBangumis;
    return List.generate(7, (day) {
      if (day >= bangumiCalendar.length) return <BangumiItem>[];
      return bangumiCalendar[day]
          .where(
            (item) =>
                !abandonedIds.contains(item.id) &&
                !watchedIds.contains(item.id) &&
                (!onlyWatching || watchingIds.contains(item.id)),
          )
          .toList();
    });
  }

  @action
  Future<void> clearFilters() async {
    await Future.wait([
      setNotShowAbandonedBangumis(false),
      setNotShowWatchedBangumis(false),
      setOnlyShowWatchingBangumis(false),
    ]);
  }
}
