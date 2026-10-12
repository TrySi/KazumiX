import 'dart:convert';

import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_module.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/services/logging/logger.dart';

/// Result of parsing a collect backup payload.
class CollectBackupParseResult {
  const CollectBackupParseResult({required this.items, this.skipped = 0});

  /// Successfully parsed collectibles.
  final List<CollectedBangumi> items;

  /// Entries that were malformed and skipped.
  final int skipped;
}

/// Encodes and decodes the 追番 (collect) library as a portable JSON document,
/// so a user can back it up to a local file and restore it on any device.
class CollectBackupService {
  CollectBackupService._();

  static final CollectBackupService instance = CollectBackupService._();

  /// Identifies Kazumi collect backups and guards against unrelated JSON.
  static const String kind = 'kazumi.collect';
  static const int version = 1;

  /// Suggested file name for an export.
  String suggestedFileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'kazumi-collect-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}.json';
  }

  /// Serializes [items] into a pretty-printed JSON backup document.
  String encode(Iterable<CollectedBangumi> items) {
    final snapshot = items.toList(growable: false);
    final document = <String, dynamic>{
      'kind': kind,
      'version': version,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'count': snapshot.length,
      'items': [
        for (final entry in snapshot)
          {
            'type': entry.type,
            'time': entry.time.millisecondsSinceEpoch,
            'subject': entry.bangumiItem.toCacheJson(),
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  /// Parses a backup payload produced by [encode].
  ///
  /// Accepts the wrapped document as well as a bare list of items. Throws
  /// [FormatException] when the payload is not a recognizable backup.
  CollectBackupParseResult decode(String content) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (error) {
      throw const FormatException('文件不是有效的 JSON');
    }

    final List<dynamic> rawItems;
    if (decoded is List) {
      rawItems = decoded;
    } else if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final kindValue = map['kind'];
      if (kindValue != null && kindValue != kind) {
        throw const FormatException('不是 Kazumi 追番备份文件');
      }
      final items = map['items'];
      if (items is! List) {
        throw const FormatException('备份文件缺少追番数据');
      }
      rawItems = items;
    } else {
      throw const FormatException('备份文件格式无法识别');
    }

    final result = <CollectedBangumi>[];
    var skipped = 0;
    for (final raw in rawItems) {
      final parsed = _decodeItem(raw);
      if (parsed == null) {
        skipped++;
      } else {
        result.add(parsed);
      }
    }
    if (result.isEmpty && skipped > 0) {
      throw const FormatException('备份文件没有可导入的追番');
    }
    return CollectBackupParseResult(items: result, skipped: skipped);
  }

  CollectedBangumi? _decodeItem(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final subject = map['subject'];
    if (subject is! Map) return null;
    try {
      final item = BangumiItem.fromJson(Map<String, dynamic>.from(subject));
      if (item.id <= 0) return null;
      final type = (map['type'] as num?)?.toInt() ?? CollectType.watching.value;
      final timeMs = (map['time'] as num?)?.toInt() ?? 0;
      final time = timeMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(timeMs)
          : DateTime.now();
      return CollectedBangumi(item, time, type);
    } catch (error) {
      KazumiLogger().w(
        'CollectBackup: failed to decode a collectible entry',
        error: error,
      );
      return null;
    }
  }
}
