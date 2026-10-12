import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/services/sync/collect_backup_service.dart';

BangumiItem _item(int id, String name) => BangumiItem(
      id: id,
      type: 2,
      name: name,
      nameCn: '$name 中文',
      summary: '简介 $id',
      airDate: '2024-04-01',
      airWeekday: 1,
      rank: 100,
      images: {'large': 'https://example.com/$id.jpg'},
      tags: [],
      alias: ['别名 $id'],
      ratingScore: 8.5,
      votes: 1234,
      votesCount: const [0, 10, 20, 30, 40, 50, 60, 70, 80, 90],
      info: '信息 $id',
    );

void main() {
  final service = CollectBackupService.instance;

  group('CollectBackupService', () {
    test('round-trips collectibles with type, time and metadata', () {
      final items = [
        CollectedBangumi(
          _item(1, 'Bangumi One'),
          DateTime.fromMillisecondsSinceEpoch(1700000000000),
          CollectType.watching.value,
        ),
        CollectedBangumi(
          _item(2, 'Bangumi Two'),
          DateTime.fromMillisecondsSinceEpoch(1700000001000),
          CollectType.watched.value,
        ),
      ];

      final parsed = service.decode(service.encode(items));

      expect(parsed.skipped, 0);
      expect(parsed.items.length, 2);

      final first = parsed.items[0];
      expect(first.bangumiItem.id, 1);
      expect(first.bangumiItem.nameCn, 'Bangumi One 中文');
      expect(first.bangumiItem.alias, ['别名 1']);
      expect(first.bangumiItem.ratingScore, 8.5);
      expect(first.type, CollectType.watching.value);
      expect(first.time.millisecondsSinceEpoch, 1700000000000);

      expect(parsed.items[1].type, CollectType.watched.value);
    });

    test('accepts a bare list payload', () {
      final payload = jsonEncode([
        {
          'type': 1,
          'time': 1700000000000,
          'subject': _item(5, 'Only').toCacheJson(),
        },
      ]);
      final parsed = service.decode(payload);
      expect(parsed.items.length, 1);
      expect(parsed.items.single.bangumiItem.id, 5);
    });

    test('skips malformed entries but keeps valid ones', () {
      final payload = jsonEncode({
        'kind': CollectBackupService.kind,
        'items': [
          {
            'type': 1,
            'time': 1700000000000,
            'subject': _item(7, 'Valid').toCacheJson(),
          },
          {'type': 1, 'time': 1700000000000},
          'not-a-map',
          {
            'type': 1,
            'time': 1700000000000,
            'subject': _item(0, 'Bad').toCacheJson(),
          },
        ],
      });
      final parsed = service.decode(payload);
      expect(parsed.items.length, 1);
      expect(parsed.items.single.bangumiItem.id, 7);
      expect(parsed.skipped, 3);
    });

    test('rejects unrelated JSON documents', () {
      expect(
        () => service.decode('{"kind":"other","items":[]}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects invalid JSON', () {
      expect(
        () => service.decode('not json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a document without items', () {
      expect(
        () => service.decode('{"kind":"${CollectBackupService.kind}"}'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
