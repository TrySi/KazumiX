import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/proxy_aware_image_cache_manager.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Keeps bangumi covers on disk so the offline info cache can render them
/// without a network connection.
///
/// Covers live next to the app data instead of the image cache, which is
/// bounded and can be cleared by the user. Each subject owns one file named
/// after its id; the extension is dropped because the decoders sniff the
/// format from the bytes.
class BangumiOfflineCoverCache {
  BangumiOfflineCoverCache._internal()
    : _applicationSupportDirectory = getApplicationSupportDirectory,
      _fetchImage = _fetchThroughImageCache;

  @visibleForTesting
  BangumiOfflineCoverCache.forTesting({
    required Future<Directory> Function() applicationSupportDirectory,
    required Future<File> Function(String url) fetchImage,
  }) : _applicationSupportDirectory = applicationSupportDirectory,
       _fetchImage = fetchImage;

  static final BangumiOfflineCoverCache instance =
      BangumiOfflineCoverCache._internal();

  static const String directoryName = 'bangumi_covers';

  /// Covers are small, but the scope can span four seasons; keep the on-disk
  /// footprint bounded so a large collection cannot grow without limit.
  static const int _maxTotalBytes = 256 * 1024 * 1024;

  final Future<Directory> Function() _applicationSupportDirectory;
  final Future<File> Function(String url) _fetchImage;
  final Map<int, Future<String?>> _storeInFlight = {};
  Directory? _resolvedDirectory;

  /// Stores the cover of [subjectId] and returns its local `file://` URI, or
  /// null when the cover could not be cached. Repeated calls reuse the file on
  /// disk and concurrent calls share a single download.
  Future<String?> store(int subjectId, String remoteUrl) {
    if (remoteUrl.isEmpty) return Future.value(null);
    if (isLocalCover(remoteUrl)) return Future.value(remoteUrl);
    final inFlight = _storeInFlight[subjectId];
    if (inFlight != null) return inFlight;
    final pending = _store(subjectId, remoteUrl);
    _storeInFlight[subjectId] = pending;
    return pending.whenComplete(() => _storeInFlight.remove(subjectId));
  }

  /// Whether [url] already points at a local cover instead of the network.
  static bool isLocalCover(String url) => Uri.tryParse(url)?.scheme == 'file';

  /// Whether the local cover recorded in an offline snapshot still exists.
  static bool localCoverExists(String url) {
    if (!isLocalCover(url)) return false;
    try {
      return File.fromUri(Uri.parse(url)).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Rebuilds a recorded `file://` cover URI after the app data container moved
  /// (iOS update). Returns the URI in the current container when the file moved
  /// along, otherwise null so the snapshot falls back to the remote URL.
  Future<String?> rebaseRecordedUri(String recordedUri) async {
    if (!isLocalCover(recordedUri)) return recordedUri;
    final subjectId = path.basename(Uri.parse(recordedUri).path);
    if (subjectId.isEmpty) return null;
    final directory = await _coverDirectory();
    final file = File(path.join(directory.path, subjectId));
    return file.existsSync() ? file.uri.toString() : null;
  }

  /// Deletes covers of subjects that are no longer part of the offline scope,
  /// then trims the remaining files, oldest first, so the directory stays
  /// under [_maxTotalBytes].
  Future<void> prune(Set<int> subjectIds) async {
    try {
      final directory = await _coverDirectory();
      final keep = {for (final id in subjectIds) '$id'};
      final keptFiles = <File>[];
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        if (!keep.contains(path.basename(entity.path))) {
          await _safeDelete(entity);
          continue;
        }
        keptFiles.add(entity);
      }

      final sorted = [...keptFiles]
        ..sort((a, b) => _modifiedAt(a).compareTo(_modifiedAt(b)));
      var total = 0;
      for (final file in sorted) {
        total += await _size(file);
      }
      for (final file in sorted) {
        if (total <= _maxTotalBytes) break;
        final size = await _size(file);
        await _safeDelete(file);
        total -= size;
      }
    } catch (error, stackTrace) {
      KazumiLogger().w(
        'BangumiOfflineCover: failed to prune offline covers',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _safeDelete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // The file may be open in a decoder; it is retried on the next sync.
    }
  }

  Future<int> _size(File file) async {
    try {
      return await file.length();
    } on FileSystemException {
      return 0;
    }
  }

  DateTime _modifiedAt(File file) {
    try {
      return file.statSync().modified;
    } on FileSystemException {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<String?> _store(int subjectId, String remoteUrl) async {
    try {
      final directory = await _coverDirectory();
      final cover = File(path.join(directory.path, '$subjectId'));
      if (await cover.exists()) return cover.uri.toString();
      final downloaded = await _fetchImage(remoteUrl);
      if (!await downloaded.exists()) return null;
      // Copy next to the target first so an interrupted write cannot leave a
      // half written cover behind.
      final temporary = File('${cover.path}.tmp');
      await downloaded.copy(temporary.path);
      await _replace(temporary, cover);
      return cover.uri.toString();
    } catch (error, stackTrace) {
      KazumiLogger().w(
        'BangumiOfflineCover: failed to cache the cover of subject $subjectId',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _replace(File temporary, File cover) async {
    try {
      await temporary.rename(cover.path);
    } on FileSystemException {
      // Windows refuses to rename onto an existing file.
      if (await cover.exists()) await cover.delete();
      await temporary.rename(cover.path);
    }
  }

  Future<Directory> _coverDirectory() async {
    final resolved = _resolvedDirectory;
    if (resolved != null) return resolved;
    final support = await _applicationSupportDirectory();
    final directory = Directory(path.join(support.path, directoryName));
    await directory.create(recursive: true);
    return _resolvedDirectory = directory;
  }

  /// Reuses whatever the shared image cache already holds, so the proxy, ECH
  /// and mirror settings of the image pipeline apply to offline covers too.
  static Future<File> _fetchThroughImageCache(String url) {
    return ProxyAwareImageCacheManager.instance.getSingleFile(url);
  }
}
