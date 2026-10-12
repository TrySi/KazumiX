import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/bangumi_offline_cover_cache.dart';

class BangumiOfflineCacheRepository {
  BangumiOfflineCacheRepository({
    Box<String>? box,
    BangumiOfflineCoverCache? coverCache,
  }) : _box = box ?? GStorage.bangumiCache,
       _coverCache = coverCache ?? BangumiOfflineCoverCache.instance;

  final Box<String> _box;
  final BangumiOfflineCoverCache _coverCache;

  bool isFresh(String key, Duration maxAge, {DateTime? now}) {
    final encoded = _box.get(key);
    if (encoded == null) return false;
    try {
      final value = jsonDecode(encoded);
      if (value is! Map || value['savedAt'] is! int) return false;
      final savedAt = DateTime.fromMillisecondsSinceEpoch(value['savedAt']);
      final age = (now ?? DateTime.now()).difference(savedAt);
      return !age.isNegative && age <= maxAge;
    } catch (_) {
      return false;
    }
  }

  String? _read(String key) => _box.get(key);

  List<BangumiItem>? readSubjects(String key) => _decodeSubjects(_read(key));

  Future<void> writeSubjects(String key, Iterable<BangumiItem> items) async {
    final snapshot = items.toList(growable: false);
    if (snapshot.isEmpty) return;
    final covers = _offlineCovers(readSubjects(key));
    await _write(key, [
      for (final item in snapshot)
        _keepOfflineCover(item, covers).toCacheJson(),
    ]);
  }

  BangumiItem? readSubject(int id) {
    final subjects = _decodeSubjects(_read('subject:$id'));
    return subjects == null || subjects.isEmpty ? null : subjects.first;
  }

  Future<void> writeSubject(BangumiItem item) async {
    final cover = readSubject(item.id)?.offlineCover;
    final stored = cover == null
        ? item
        : _keepOfflineCover(item, {item.id: cover});
    await _write('subject:${item.id}', [stored.toCacheJson()]);
  }

  List<List<BangumiItem>>? readCalendar(String key) {
    final raw = _decode(_read(key));
    if (raw is! List) return null;
    return [
      for (final day in raw)
        if (day is List) _decodeSubjectList(day) else <BangumiItem>[],
    ];
  }

  Future<void> writeCalendar(
    String key,
    Iterable<Iterable<BangumiItem>> calendar, {
    bool preserveFreshness = false,
  }) async {
    final previous = readCalendar(key);
    final covers = _offlineCovers([
      for (final day in previous ?? const <List<BangumiItem>>[]) ...day,
    ]);
    final snapshot = [
      for (final day in calendar)
        [for (final item in day) _keepOfflineCover(item, covers).toCacheJson()],
    ];
    if (snapshot.every((day) => day.isEmpty)) return;
    await _write(key, snapshot, keepSavedAt: preserveFreshness);
  }

  List<EpisodeInfo>? readEpisodes(int bangumiId) {
    final raw = _decode(_read('episodes:$bangumiId'));
    if (raw is! List) return null;
    try {
      return [
        for (final value in raw)
          if (value is Map)
            EpisodeInfo.fromJson(Map<String, dynamic>.from(value)),
      ];
    } catch (error) {
      KazumiLogger().w(
        'BangumiOfflineCache: failed to decode episodes for $bangumiId',
        error: error,
      );
      return null;
    }
  }

  Future<void> writeEpisodes(int bangumiId, Iterable<EpisodeInfo> episodes) {
    return _write('episodes:$bangumiId', [
      for (final episode in episodes)
        {
          'id': episode.id,
          'sort': episode.episode,
          'type': episode.type,
          'name': episode.name,
          'name_cn': episode.nameCn,
          'airdate': episode.airDate?.toIso8601String(),
        },
    ]);
  }

  Future<void> retainOfflineScope({
    required Set<int> subjectIds,
    required Set<String> calendarKeys,
  }) async {
    for (final key in _box.keys.toList()) {
      if (key is! String) continue;
      final isCalendar =
          key == 'calendar:current-week' || key.startsWith('calendar:season:');
      if (isCalendar && !calendarKeys.contains(key)) {
        await _box.delete(key);
        continue;
      }

      final match = RegExp(r'^(?:subject|episodes):(\d+)$').firstMatch(key);
      if (match != null && !subjectIds.contains(int.parse(match.group(1)!))) {
        await _box.delete(key);
      }
    }
  }

  /// Rewrites recorded cover URIs after the app data container moved (iOS
  /// update). Subjects whose cover file is missing fall back to the remote URL
  /// and are re-downloaded by the next sync.
  Future<void> rebaseOfflineCovers() async {
    for (final key in _box.keys.whereType<String>().toList()) {
      if (key.startsWith('subject:')) {
        final id = int.tryParse(key.substring('subject:'.length));
        if (id == null) continue;
        final subject = readSubject(id);
        if (subject == null) continue;
        final rebased = await _rebaseSubjectCover(subject);
        if (!identical(rebased, subject)) await writeSubject(rebased);
        continue;
      }
      if (key == 'calendar:current-week' ||
          key.startsWith('calendar:season:')) {
        final calendar = readCalendar(key);
        if (calendar == null) continue;
        var changed = false;
        final rebuilt = <List<BangumiItem>>[];
        for (final day in calendar) {
          final items = <BangumiItem>[];
          for (final item in day) {
            final rebased = await _rebaseSubjectCover(item);
            if (!identical(rebased, item)) changed = true;
            items.add(rebased);
          }
          rebuilt.add(items);
        }
        if (changed) await writeCalendar(key, rebuilt);
      }
    }
  }

  Future<BangumiItem> _rebaseSubjectCover(BangumiItem subject) async {
    final cover = subject.offlineCover;
    if (cover == null) return subject;
    final rebased = await _coverCache.rebaseRecordedUri(cover);
    if (rebased == cover) return subject;
    return subject.withOfflineCover(rebased);
  }

  List<BangumiItem>? _decodeSubjects(String? encoded) {
    final raw = _decode(encoded);
    return raw is List ? _decodeSubjectList(raw) : null;
  }

  List<BangumiItem> _decodeSubjectList(List values) {
    final subjects = <BangumiItem>[];
    for (final value in values) {
      if (value is! Map) continue;
      try {
        final subject = BangumiItem.fromJson(Map<String, dynamic>.from(value));
        _dropMissingOfflineCover(subject);
        subjects.add(subject);
      } catch (error) {
        KazumiLogger().w(
          'BangumiOfflineCache: skipped malformed subject snapshot',
          error: error,
        );
      }
    }
    return subjects;
  }

  /// A cover file can be removed outside the app (backup restore, manual clean
  /// up); fall back to the remote URL instead of rendering a broken image.
  void _dropMissingOfflineCover(BangumiItem subject) {
    final cover = subject.offlineCover;
    if (cover != null && !BangumiOfflineCoverCache.localCoverExists(cover)) {
      subject.offlineCover = null;
    }
  }

  Map<int, String> _offlineCovers(Iterable<BangumiItem>? subjects) {
    final covers = <int, String>{};
    for (final subject in subjects ?? const <BangumiItem>[]) {
      final cover = subject.offlineCover;
      if (cover != null) covers[subject.id] = cover;
    }
    return covers;
  }

  /// Fresh snapshots come from the network without a local cover. Keep the one
  /// the background sync downloaded so offline reading keeps working.
  BangumiItem _keepOfflineCover(BangumiItem subject, Map<int, String> covers) {
    final cover = covers[subject.id];
    if (cover == null || subject.offlineCover != null) return subject;
    return subject.withOfflineCover(cover);
  }

  dynamic _decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final value = jsonDecode(encoded);
      if (value is Map && value.containsKey('savedAt')) return value['data'];
      return value;
    } catch (error) {
      KazumiLogger().w(
        'BangumiOfflineCache: invalid snapshot JSON',
        error: error,
      );
      return null;
    }
  }

  Future<void> _write(
    String key,
    Object value, {
    bool keepSavedAt = false,
  }) async {
    try {
      // Reusing the existing timestamp keeps a cover-only rewrite from looking
      // like a fresh fetch to [isFresh].
      final previous = keepSavedAt ? _savedAtOf(key) : null;
      await _box.put(
        key,
        jsonEncode({
          'savedAt': previous ?? DateTime.now().millisecondsSinceEpoch,
          'data': value,
        }),
      );
    } catch (error, stackTrace) {
      KazumiLogger().e(
        'BangumiOfflineCache: failed to persist $key',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  int? _savedAtOf(String key) {
    final encoded = _box.get(key);
    if (encoded == null) return null;
    try {
      final value = jsonDecode(encoded);
      if (value is Map && value['savedAt'] is int) {
        return value['savedAt'] as int;
      }
    } catch (_) {
      // Fall through to a fresh timestamp.
    }
    return null;
  }
}
