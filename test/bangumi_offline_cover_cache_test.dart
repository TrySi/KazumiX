import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/sync/bangumi_offline_cover_cache.dart';
import 'package:path/path.dart' as path;

void main() {
  const coverUrl = 'https://example.test/cover.jpg';
  late Directory support;
  late Directory downloads;
  var downloadCount = 0;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('kazumi_covers_support');
    downloads = await Directory.systemTemp.createTemp('kazumi_covers_fetch');
    downloadCount = 0;
  });

  tearDown(() async {
    for (final directory in [support, downloads]) {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  /// Stands in for the shared image cache: every fetch produces a file next to
  /// the test scratch space and is counted.
  BangumiOfflineCoverCache buildCache() {
    return BangumiOfflineCoverCache.forTesting(
      applicationSupportDirectory: () async => support,
      fetchImage: (url) async {
        downloadCount++;
        final file = File(path.join(downloads.path, 'download-$downloadCount'));
        await file.writeAsBytes(_coverBytes);
        return file;
      },
    );
  }

  test('stores a cover once and reuses the file afterwards', () async {
    final cache = buildCache();

    final cover = await cache.store(42, coverUrl);

    expect(cover, isNotNull);
    expect(Uri.parse(cover!).scheme, 'file');
    expect(File.fromUri(Uri.parse(cover)).existsSync(), isTrue);
    expect(BangumiOfflineCoverCache.localCoverExists(cover), isTrue);
    expect(BangumiOfflineCoverCache.isLocalCover(cover), isTrue);
    expect(downloadCount, 1);

    expect(await cache.store(42, coverUrl), cover);
    expect(downloadCount, 1);
  });

  test('skips empty urls and covers that are already local', () async {
    final cache = buildCache();

    expect(await cache.store(7, ''), isNull);

    final cover = await cache.store(7, coverUrl);
    expect(await cache.store(7, cover!), cover);
    expect(downloadCount, 1);
  });

  test('shares one download between concurrent callers', () async {
    var started = 0;
    final cache = BangumiOfflineCoverCache.forTesting(
      applicationSupportDirectory: () async => support,
      fetchImage: (url) async {
        started++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final file = File(path.join(downloads.path, 'concurrent-$started'));
        await file.writeAsBytes(_coverBytes);
        return file;
      },
    );

    final covers = await Future.wait([
      cache.store(11, coverUrl),
      cache.store(11, coverUrl),
    ]);

    expect(started, 1);
    expect(covers.first, covers.last);
  });

  test('reports a failure instead of caching an unusable cover', () async {
    final cache = BangumiOfflineCoverCache.forTesting(
      applicationSupportDirectory: () async => support,
      fetchImage: (_) async => throw const SocketException('offline'),
    );

    expect(await cache.store(9, coverUrl), isNull);
    expect(BangumiOfflineCoverCache.isLocalCover(coverUrl), isFalse);
    expect(BangumiOfflineCoverCache.localCoverExists(coverUrl), isFalse);
  });

  test('prunes covers that left the offline scope', () async {
    final cache = buildCache();
    final kept = await cache.store(42, coverUrl);
    await cache.store(43, coverUrl);
    final directory = Directory(
      path.join(support.path, BangumiOfflineCoverCache.directoryName),
    );
    final interrupted = File(path.join(directory.path, '44.tmp'));
    await interrupted.writeAsBytes(_coverBytes);

    await cache.prune({42});

    expect(BangumiOfflineCoverCache.localCoverExists(kept!), isTrue);
    expect(File(path.join(directory.path, '43')).existsSync(), isFalse);
    expect(interrupted.existsSync(), isFalse);
  });

  test('rebases a recorded cover URI after the container moved', () async {
    final cache = buildCache();
    final cover = await cache.store(42, coverUrl);

    // Simulate a URI recorded against the previous app data container.
    final oldFile = File(path.join(support.path, 'old', '42'));
    final rebased = await cache.rebaseRecordedUri(oldFile.uri.toString());

    expect(rebased, cover);
    expect(rebased, isNot(oldFile.uri.toString()));
  });
}

const List<int> _coverBytes = [137, 80, 78, 71];
