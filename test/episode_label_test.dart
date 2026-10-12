import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/utils/media.dart';

EpisodeInfo _episode(
  num number,
  int type, {
  String name = '',
  String nameCn = '',
}) => EpisodeInfo(
  id: number.toInt(),
  episode: number,
  type: type,
  name: name,
  nameCn: nameCn,
);

void main() {
  group('formatEpisodeLabel', () {
    test('normalizes bare numbers and 集/话 markers to 第X话', () {
      expect(formatEpisodeLabel('1'), '第1话');
      expect(formatEpisodeLabel('01'), '第1话');
      expect(formatEpisodeLabel('12'), '第12话');
      expect(formatEpisodeLabel('第1集'), '第1话');
      expect(formatEpisodeLabel('第1话'), '第1话');
      expect(formatEpisodeLabel('第 3 集'), '第3话');
    });

    test('keeps descriptive titles but normalizes the 集 marker', () {
      expect(formatEpisodeLabel('第1集 开端'), '第1话 开端');
      expect(formatEpisodeLabel('第1话 开端'), '第1话 开端');
      expect(formatEpisodeLabel('特别篇'), '特别篇');
    });

    test('leaves labels without a number untouched', () {
      expect(formatEpisodeLabel('OVA'), 'OVA');
      expect(formatEpisodeLabel(''), '');
    });
  });

  group('offlineEpisodeSlots', () {
    test('numbers extras per type in the order they appear', () {
      final slots = offlineEpisodeSlots([
        _episode(1, 0, nameCn: '第一话'),
        _episode(0, 1, name: 'SP one'),
        _episode(0, 2, name: 'OP one'),
        _episode(0, 1, name: 'SP two'),
        _episode(0, 3, name: 'ED one'),
      ]);

      expect(slots.map((s) => s.title), [
        '第1话',
        'SP1 SP one',
        'OP1 OP one',
        'SP2 SP two',
        'ED1 ED one',
      ]);
      expect(slots.map((s) => s.episodeNumber), [1, 0, 0, 0, 0]);
      expect(slots.map((s) => s.isExtra), [false, true, true, true, true]);
    });

    test('prefers the localized name for an extra title', () {
      final slots = offlineEpisodeSlots([
        _episode(0, 1, name: 'Special', nameCn: '特别篇'),
      ]);

      expect(slots.single.title, 'SP1 特别篇');
      expect(slots.single.nameCn, '特别篇');
      expect(slots.single.name, 'Special');
    });

    test('keeps an unnumbered main episode as a titled slot', () {
      final slots = offlineEpisodeSlots([
        _episode(1, 0, nameCn: '第一话'),
        _episode(0, 0, nameCn: '总集篇'),
      ]);

      expect(slots.map((s) => s.title), ['第1话', '总集篇']);
      expect(slots.last.episodeNumber, 0);
      expect(slots.last.isExtra, isFalse);
    });

    test('skips unnamed entries and unknown extra types', () {
      final slots = offlineEpisodeSlots([
        _episode(0, 0),
        _episode(0, 4, name: 'trailer'),
      ]);

      expect(slots, isEmpty);
    });

    test('an empty or missing cache yields no slots', () {
      expect(offlineEpisodeSlots(null), isEmpty);
      expect(offlineEpisodeSlots(const []), isEmpty);
    });
  });

  group('OfflineEpisodeTitles', () {
    test('resolves extras by name and main episodes by number', () {
      final titles = OfflineEpisodeTitles.fromCache([
        _episode(1, 0, nameCn: '第一话'),
        _episode(0, 1, name: 'Special', nameCn: '特别篇'),
      ]);

      expect(titles.titleFor(episodeNumber: 1), '第1话');
      expect(titles.titleFor(episodeNumber: 0, name: '特别篇'), 'SP1 特别篇');
      expect(titles.titleFor(episodeNumber: 0, name: 'Special'), 'SP1 特别篇');
      // Unknown labels still get the 话 marker normalized.
      expect(titles.titleFor(episodeNumber: 0, name: '第2集'), '第2话');
    });

    test('shares its numbering with the offline slots', () {
      final cached = [_episode(0, 1, name: 'a'), _episode(0, 1, name: 'b')];

      final slots = offlineEpisodeSlots(cached);
      final titles = OfflineEpisodeTitles.fromCache(cached);

      expect(slots.map((s) => s.title), ['SP1 a', 'SP2 b']);
      expect(titles.titleFor(episodeNumber: 0, name: 'b'), slots.last.title);
    });
  });
}
