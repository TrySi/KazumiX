import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/repositories/bangumi_offline_cache_repository.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/bangumi_offline_cover_cache.dart';
import 'package:kazumi/utils/anime_season.dart';

class BangumiOfflineSyncService {
  BangumiOfflineSyncService._();

  static final instance = BangumiOfflineSyncService._();

  static const _currentWeekTtl = Duration(hours: 6);
  static const _currentSeasonTtl = Duration(hours: 12);
  static const _previousSeasonTtl = Duration(days: 7);
  static const _subjectTtl = Duration(days: 7);
  static const _currentEpisodesTtl = Duration(hours: 12);
  static const _previousEpisodesTtl = Duration(days: 7);
  static const _coverFetchWorkers = 2;
  static const _coverFetchInterval = Duration(milliseconds: 300);

  /// Metadata requests stop after this many consecutive subject failures, so a
  /// broken `api.bgm.tv` / DNS state is not hammered on every foreground event.
  static const _maxConsecutiveFailures = 3;

  /// How long the circuit stays open before the sync is allowed to retry.
  static const _circuitCooldown = Duration(minutes: 30);

  /// Box key persisting the circuit state so a relaunch does not immediately
  /// resume hammering a still-broken endpoint.
  static const _circuitStateKey = 'meta:sync-circuit';

  final _cache = BangumiOfflineCacheRepository();
  final _coverCache = BangumiOfflineCoverCache.instance;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _started = false;
  bool _syncing = false;
  bool _circuitLoaded = false;
  int _consecutiveFailures = 0;
  DateTime? _circuitOpenedAt;

  void start() {
    if (_started) return;
    _started = true;
    if (Platform.isIOS) {
      unawaited(_cache.rebaseOfflineCovers());
    }
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) {
        if (results.any((result) => result != ConnectivityResult.none)) {
          unawaited(syncIfOnline());
        }
      },
      onError: (Object error) {
        KazumiLogger().w(
          'BangumiOfflineSync: connectivity listener failed',
          error: error,
        );
      },
    );
    unawaited(syncIfOnline());
  }

  Future<void> stop() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _started = false;
  }

  Future<void> syncIfOnline() async {
    if (_syncing) return;
    _syncing = true;
    try {
      _loadCircuitState();
      if (_isCircuitOpen()) {
        KazumiLogger().i(
          'BangumiOfflineSync: metadata sync paused after repeated failures',
        );
        return;
      }
      final connections = await Connectivity().checkConnectivity();
      if (connections.every((result) => result == ConnectivityResult.none)) {
        return;
      }

      final now = DateTime.now();
      final subjects = <int, BangumiItem>{};
      final downloadedIds = <int>{};
      final collectedIds = <int>{};
      final retainedCalendarKeys = <String>{'calendar:current-week'};

      // 1. Downloaded shows take precedence and are always kept in scope.
      for (final record in GStorage.downloads.values) {
        downloadedIds.add(record.bangumiId);
        subjects.putIfAbsent(
          record.bangumiId,
          () => _itemFromDownloadRecord(record),
        );
      }

      // 2. Collected shows.
      for (final collectible in GStorage.collectibles.values) {
        final item = collectible.bangumiItem;
        collectedIds.add(item.id);
        subjects.putIfAbsent(item.id, () => item);
        if (_cache.readSubject(item.id) == null) {
          await _cache.writeSubject(item);
        }
      }

      final currentWeek = await _syncCurrentWeek(now);
      _addSubjects(subjects, currentWeek);

      final currentQuarter = _quarterStart(now);
      final currentSeasonIds = <int>{};
      for (var offset = 0; offset < 4; offset++) {
        final season = DateTime(
          currentQuarter.year,
          currentQuarter.month - offset * 3,
        );
        final dateRange = AnimeSeason(season).toSeasonStartAndEnd();
        final key = 'calendar:season:${dateRange[0]}:${dateRange[1]}';
        retainedCalendarKeys.add(key);
        final isCurrent = offset == 0;
        final items = await _syncSeason(
          key: key,
          dateRange: dateRange,
          isCurrent: isCurrent,
          now: now,
        );
        _addSubjects(subjects, items);
        if (isCurrent) {
          for (final day in items) {
            currentSeasonIds.addAll(day.map((item) => item.id));
          }
        }
      }

      final ordered = _orderSubjects(
        subjects.values.toList(),
        downloadedIds: downloadedIds,
        collectedIds: collectedIds,
        currentSeasonIds: currentSeasonIds,
      );
      await _syncSubjects(ordered, currentSeasonIds);
      await _cache.retainOfflineScope(
        subjectIds: subjects.keys.toSet(),
        calendarKeys: retainedCalendarKeys,
      );
      await _coverCache.prune(subjects.keys.toSet());
    } catch (error, stackTrace) {
      KazumiLogger().w(
        'BangumiOfflineSync: background metadata sync failed',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _syncing = false;
    }
  }

  DateTime _quarterStart(DateTime date) {
    final firstMonth = ((date.month - 1) ~/ 3) * 3 + 1;
    return DateTime(date.year, firstMonth);
  }

  BangumiItem _itemFromDownloadRecord(DownloadRecord record) {
    return BangumiItem(
      id: record.bangumiId,
      type: 2,
      name: record.bangumiName,
      nameCn: record.bangumiName,
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: {'large': record.bangumiCover},
      tags: [],
      alias: [],
      ratingScore: 0.0,
      votes: 0,
      votesCount: [],
      info: '',
    );
  }

  /// Orders subjects so the most relevant are synced first: downloaded shows,
  /// then collected shows, then current-season shows, then older seasons.
  List<BangumiItem> _orderSubjects(
    List<BangumiItem> subjects, {
    required Set<int> downloadedIds,
    required Set<int> collectedIds,
    required Set<int> currentSeasonIds,
  }) {
    int rank(int id) {
      if (downloadedIds.contains(id)) return 0;
      if (collectedIds.contains(id)) return 1;
      if (currentSeasonIds.contains(id)) return 2;
      return 3;
    }

    final ordered = subjects.toList();
    ordered.sort((a, b) {
      final byRank = rank(a.id).compareTo(rank(b.id));
      if (byRank != 0) return byRank;
      return a.id.compareTo(b.id);
    });
    return ordered;
  }

  void _loadCircuitState() {
    if (_circuitLoaded) return;
    _circuitLoaded = true;
    try {
      final raw = GStorage.bangumiCache.get(_circuitStateKey);
      if (raw == null) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      _consecutiveFailures = (data['failures'] as num?)?.toInt() ?? 0;
      final openedAt = (data['openedAt'] as num?)?.toInt();
      _circuitOpenedAt = openedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(openedAt);
    } catch (error) {
      KazumiLogger().w(
        'BangumiOfflineSync: failed to read circuit state',
        error: error,
      );
    }
  }

  void _persistCircuitState() {
    try {
      GStorage.bangumiCache.put(
        _circuitStateKey,
        jsonEncode({
          'failures': _consecutiveFailures,
          'openedAt': _circuitOpenedAt?.millisecondsSinceEpoch,
        }),
      );
    } catch (error) {
      KazumiLogger().w(
        'BangumiOfflineSync: failed to persist circuit state',
        error: error,
      );
    }
  }

  /// Whether the circuit is open. An open circuit self-heals after the cooldown
  /// so a recovered endpoint is eventually tried again.
  bool _isCircuitOpen() {
    final openedAt = _circuitOpenedAt;
    if (openedAt == null) return false;
    if (DateTime.now().difference(openedAt) >= _circuitCooldown) {
      _circuitOpenedAt = null;
      _consecutiveFailures = 0;
      _persistCircuitState();
      return false;
    }
    return true;
  }

  void _recordFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      _circuitOpenedAt = DateTime.now();
      _consecutiveFailures = 0;
      KazumiLogger().w(
        'BangumiOfflineSync: opening circuit after $_maxConsecutiveFailures '
        'consecutive failures',
      );
    }
    _persistCircuitState();
  }

  /// Opens the circuit immediately for a connectivity/timeout failure, which
  /// is unlikely to recover by retrying the remaining subjects right now.
  void _openCircuit() {
    _circuitOpenedAt = DateTime.now();
    _consecutiveFailures = 0;
    KazumiLogger().w(
      'BangumiOfflineSync: opening circuit on connectivity failure',
    );
    _persistCircuitState();
  }

  void _recordSuccess() {
    if (_consecutiveFailures == 0) return;
    _consecutiveFailures = 0;
    _persistCircuitState();
  }

  Future<List<List<BangumiItem>>> _syncCurrentWeek(DateTime now) async {
    const key = 'calendar:current-week';
    final cached = _cache.readCalendar(key);
    if (_cache.isFresh(key, _currentWeekTtl, now: now)) {
      return _cacheCovers(key, cached ?? []);
    }

    final fresh = await BangumiApi.getCalendar();
    if (fresh.any((day) => day.isNotEmpty)) {
      await _cache.writeCalendar(key, fresh);
      return _cacheCovers(key, fresh);
    }
    return cached ?? [];
  }

  Future<List<List<BangumiItem>>> _syncSeason({
    required String key,
    required List<String> dateRange,
    required bool isCurrent,
    required DateTime now,
  }) async {
    final cached = _cache.readCalendar(key);
    final ttl = isCurrent ? _currentSeasonTtl : _previousSeasonTtl;
    if (_cache.isFresh(key, ttl, now: now)) {
      return _cacheCovers(key, cached ?? []);
    }

    final fresh = BangumiAcceleration.current == BangumiAcceleration.mirror
        ? await BangumiApi.getBangumiMirrorSeasonCalendar(dateRange)
        : await BangumiApi.getCalendarBySearch(dateRange, 100, 0);
    if (fresh.any((day) => day.isNotEmpty)) {
      await _cache.writeCalendar(key, fresh);
      return _cacheCovers(key, fresh);
    }
    return cached ?? [];
  }

  void _addSubjects(
    Map<int, BangumiItem> target,
    Iterable<Iterable<BangumiItem>> calendar,
  ) {
    for (final day in calendar) {
      for (final item in day) {
        target.putIfAbsent(item.id, () => item);
      }
    }
  }

  Future<void> _syncSubjects(
    List<BangumiItem> subjects,
    Set<int> currentSeasonIds,
  ) async {
    var nextIndex = 0;

    Future<void> worker() async {
      while (!_isCircuitOpen()) {
        final index = nextIndex++;
        if (index >= subjects.length) return;
        final subject = subjects[index];
        try {
          await _syncSubject(subject, currentSeasonIds.contains(subject.id));
        } catch (error) {
          if (error is NetworkException && error.isConnectivityFailure) {
            _openCircuit();
          } else {
            _recordFailure();
          }
          KazumiLogger().w(
            'BangumiOfflineSync: failed to sync subject ${subject.id}',
            error: error,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    final workers = math.min(2, subjects.length);
    await Future.wait(List.generate(workers, (_) => worker()));
  }

  Future<bool> _syncSubject(BangumiItem subject, bool isCurrentSeason) async {
    final now = DateTime.now();
    final subjectKey = 'subject:${subject.id}';
    if (!_cache.isFresh(subjectKey, _subjectTtl, now: now)) {
      final freshSubject = await BangumiApi.getBangumiInfoByID(
        subject.id,
        rethrowNetworkError: true,
      );
      if (freshSubject == null) {
        _recordFailure();
        return false;
      }
      await _cache.writeSubject(freshSubject);
      _recordSuccess();
    }

    await _ensureSubjectCover(subject.id);

    final episodeKey = 'episodes:${subject.id}';
    final episodeTtl = isCurrentSeason
        ? _currentEpisodesTtl
        : _previousEpisodesTtl;
    if (!_cache.isFresh(episodeKey, episodeTtl, now: now)) {
      final episodes = await BangumiApi.getBangumiEpisodesByID(
        subject.id,
        rethrowNetworkError: true,
      );
      if (episodes.isNotEmpty) await _cache.writeEpisodes(subject.id, episodes);
    }
    return true;
  }

  /// Stores the covers of [calendar] and rewrites the snapshot when at least
  /// one cover was added, so the offline data itself is never delayed by a slow
  /// download. Subjects whose cover is already on disk are left untouched.
  Future<List<List<BangumiItem>>> _cacheCovers(
    String key,
    List<List<BangumiItem>> calendar,
  ) async {
    final subjects = [for (final day in calendar) ...day];
    final covered = List<BangumiItem?>.filled(subjects.length, null);
    var nextIndex = 0;
    var changed = false;

    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= subjects.length) return;
        final subject = subjects[index];
        final item = await _withOfflineCover(subject);
        covered[index] = item;
        if (!identical(item, subject)) changed = true;
        await Future<void>.delayed(_coverFetchInterval);
      }
    }

    final workers = math.min(_coverFetchWorkers, subjects.length);
    await Future.wait(List.generate(workers, (_) => worker()));
    if (!changed) return calendar;

    final localized = <List<BangumiItem>>[];
    var cursor = 0;
    for (final day in calendar) {
      final items = <BangumiItem>[];
      for (var i = 0; i < day.length; i++) {
        items.add(covered[cursor++]!);
      }
      localized.add(items);
    }
    await _cache.writeCalendar(key, localized);
    return localized;
  }

  /// Caches the cover of a subject that already has an offline snapshot.
  Future<void> _ensureSubjectCover(int subjectId) async {
    final stored = _cache.readSubject(subjectId);
    if (stored == null) return;
    final covered = await _withOfflineCover(stored);
    if (identical(covered, stored)) return;
    await _cache.writeSubject(covered);
  }

  /// Returns [subject] with the cover stored locally, or the same instance when
  /// it already is.
  Future<BangumiItem> _withOfflineCover(BangumiItem subject) async {
    final existing = subject.offlineCover;
    if (existing != null &&
        BangumiOfflineCoverCache.localCoverExists(existing)) {
      return subject;
    }
    final cover = await _coverCache.store(
      subject.id,
      subject.images['large'] ?? '',
    );
    return cover == null ? subject : subject.withOfflineCover(cover);
  }
}
