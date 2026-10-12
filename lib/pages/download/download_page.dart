import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/download/download_widgets.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/repositories/bangumi_offline_cache_repository.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/utils/format.dart';
import 'package:kazumi/utils/media.dart';

enum _DownloadFilter { downloading, completed }

/// A show aggregated across sources: one card per bangumi, with each episode
/// keeping its own source label.
class _ShowGroup {
  _ShowGroup({
    required this.bangumiId,
    required this.bangumiName,
    required this.coverSource,
    required this.records,
    required this.entries,
  });

  final int bangumiId;
  final String bangumiName;
  final String coverSource;
  final List<DownloadRecord> records;
  final List<_EpisodeEntry> entries;

  String get key => '$bangumiId';
}

class _EpisodeEntry {
  _EpisodeEntry({required this.record, required this.episode});

  final DownloadRecord record;
  final DownloadEpisode episode;
}

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key, required this.controller});

  final DownloadController controller;

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  DownloadController get downloadController => widget.controller;

  // Keep expansion state across controller snapshot replacements.
  final Map<String, bool> _expanded = {};

  _DownloadFilter _filter = _DownloadFilter.downloading;

  @override
  void initState() {
    super.initState();
    downloadController.refreshRecords();
  }

  bool _isExpanded(_ShowGroup group) {
    return _expanded.putIfAbsent(
      group.key,
      () => group.entries.any(
        (e) => e.episode.status != DownloadStatus.completed,
      ),
    );
  }

  /// Episodes that belong to the currently selected filter, so a single show
  /// can appear in both tabs while each tab only lists its own episodes.
  List<_EpisodeEntry> _filteredEntries(_ShowGroup group) {
    return switch (_filter) {
      _DownloadFilter.downloading =>
        group.entries
            .where((e) => e.episode.status != DownloadStatus.completed)
            .toList(),
      _DownloadFilter.completed =>
        group.entries
            .where((e) => e.episode.status == DownloadStatus.completed)
            .toList(),
    };
  }

  bool _matchesFilter(_ShowGroup group) => _filteredEntries(group).isNotEmpty;

  List<_ShowGroup> _buildGroups() {
    final byBangumi = <int, List<DownloadRecord>>{};
    for (final record in downloadController.records) {
      byBangumi.putIfAbsent(record.bangumiId, () => []).add(record);
    }

    final groups = <_ShowGroup>[];
    byBangumi.forEach((bangumiId, records) {
      final entries = <_EpisodeEntry>[];
      for (final record in records) {
        for (final episode in record.episodes.values) {
          entries.add(_EpisodeEntry(record: record, episode: episode));
        }
      }
      entries.sort((a, b) {
        final byEpisode = a.episode.episodeNumber.compareTo(
          b.episode.episodeNumber,
        );
        if (byEpisode != 0) return byEpisode;
        return a.record.pluginName.compareTo(b.record.pluginName);
      });

      final first = records.first;
      groups.add(
        _ShowGroup(
          bangumiId: bangumiId,
          bangumiName: first.bangumiName,
          coverSource: first.coverSource,
          records: records,
          entries: entries,
        ),
      );
    });

    groups.sort((a, b) {
      final aActive = a.entries.any(
        (e) => e.episode.status != DownloadStatus.completed,
      );
      final bActive = b.entries.any(
        (e) => e.episode.status != DownloadStatus.completed,
      );
      if (aActive != bActive) return aActive ? -1 : 1;
      return a.bangumiName.compareTo(b.bangumiName);
    });
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        needTopOffset: false,
        toolbarHeight: 72,
        title: Text(
          '离线',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<_DownloadFilter>(
              segments: const [
                ButtonSegment(
                  value: _DownloadFilter.downloading,
                  label: Text('下载中'),
                  icon: Icon(Icons.downloading_rounded),
                ),
                ButtonSegment(
                  value: _DownloadFilter.completed,
                  label: Text('已下载'),
                  icon: Icon(Icons.check_circle_outline_rounded),
                ),
              ],
              selected: {_filter},
              onSelectionChanged: (selection) {
                setState(() => _filter = selection.first);
              },
            ),
          ),
          Expanded(
            child: Observer(
              builder: (context) {
                final groups = _buildGroups().where(_matchesFilter).toList();
                _expanded.removeWhere(
                  (key, _) => !groups.any((group) => group.key == key),
                );
                if (groups.isEmpty) {
                  return GeneralEmptyState(
                    icon: _filter == _DownloadFilter.downloading
                        ? Icons.download_rounded
                        : Icons.check_circle_outline_rounded,
                    title: _filter == _DownloadFilter.downloading
                        ? '没有进行中的下载'
                        : '还没有已下载的内容',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: _buildShowCard(groups[index]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShowCard(_ShowGroup group) {
    return Observer(
      builder: (context) {
        final entries = _filteredEntries(group);
        final totalCount = entries.length;
        final completedCount = entries
            .where((e) => e.episode.status == DownloadStatus.completed)
            .length;
        final activeCount = entries
            .where(
              (e) =>
                  e.episode.status == DownloadStatus.downloading ||
                  e.episode.status == DownloadStatus.resolving ||
                  e.episode.status == DownloadStatus.pending,
            )
            .length;
        final aggregateProgress = totalCount == 0
            ? 0.0
            : entries.fold<double>(
                    0,
                    (sum, e) =>
                        sum +
                        (e.episode.status == DownloadStatus.completed
                            ? 1.0
                            : e.episode.progressPercent),
                  ) /
                  totalCount;

        var totalSpeed = 0.0;
        for (final e in entries) {
          if (e.episode.status == DownloadStatus.downloading) {
            totalSpeed += downloadController.getSpeed(
              e.record.bangumiId,
              e.record.pluginName,
              e.episode.episodeNumber,
            );
          }
        }
        final expanded = _isExpanded(group);

        return DownloadRecordCard(
          bangumiName: group.bangumiName,
          coverSource: group.coverSource,
          completedCount: completedCount,
          totalCount: totalCount,
          activeCount: activeCount,
          aggregateProgress: aggregateProgress,
          expanded: expanded,
          onToggle: () {
            setState(() => _expanded[group.key] = !expanded);
          },
          onResumeAll: _filter == _DownloadFilter.downloading
              ? () => _resumeAll(group)
              : null,
          onPauseAll: _filter == _DownloadFilter.downloading
              ? () => _pauseAll(group)
              : null,
          onDeleteAll: () => _filter == _DownloadFilter.downloading
              ? _confirmDeleteIncomplete(group)
              : _confirmDeleteCompleted(group),
          totalSpeed: totalSpeed,
          episodeTileBuilder: () {
            return entries.map(_buildEpisodeTile).toList();
          },
        );
      },
    );
  }

  void _resumeAll(_ShowGroup group) {
    for (final record in group.records) {
      downloadController.resumeAllDownloads(
        record.bangumiId,
        record.pluginName,
      );
    }
    KazumiDialog.showToast(message: '已开始恢复下载');
  }

  void _pauseAll(_ShowGroup group) {
    for (final record in group.records) {
      downloadController.pauseDownloads(record.bangumiId, record.pluginName);
    }
    KazumiDialog.showToast(message: '已暂停下载');
  }

  Widget _buildEpisodeTile(_EpisodeEntry entry) {
    final record = entry.record;
    final episode = entry.episode;
    return DownloadEpisodeTile(
      episode: episode,
      title: _titlesFor(record.bangumiId).titleFor(
        episodeNumber: episode.episodeNumber,
        name: episode.episodeName,
      ),
      statusText: _getStatusText(record, episode),
      sourceLabel: record.pluginName,
      actions: _getActionButtons(entry),
      onPlay: episode.status == DownloadStatus.completed
          ? () => _playEpisode(entry)
          : null,
    );
  }

  final Map<int, OfflineEpisodeTitles> _titlesCache = {};

  /// Cached episode titles for a bangumi so downloaded episodes read `第X话`
  /// (main) or `SPx/OPx/EDx <title>` (extras), matching the offline screens.
  OfflineEpisodeTitles _titlesFor(int bangumiId) => _titlesCache.putIfAbsent(
    bangumiId,
    () => OfflineEpisodeTitles.fromCache(
      BangumiOfflineCacheRepository().readEpisodes(bangumiId),
    ),
  );

  String _getStatusText(DownloadRecord record, DownloadEpisode episode) {
    switch (episode.status) {
      case DownloadStatus.completed:
        return '已完成 · ${formatBytes(episode.totalBytes)}';
      case DownloadStatus.downloading:
        final speed = downloadController.getSpeed(
          record.bangumiId,
          record.pluginName,
          episode.episodeNumber,
        );
        final speedText = speed > 0 ? ' · ${formatSpeed(speed)}' : '';
        return '${(episode.progressPercent * 100).toStringAsFixed(0)}% · '
            '${episode.downloadedSegments}/${episode.totalSegments} 分片$speedText';
      case DownloadStatus.failed:
        return episode.errorMessage.isNotEmpty ? episode.errorMessage : '下载失败';
      case DownloadStatus.paused:
        return '已暂停 · ${(episode.progressPercent * 100).toStringAsFixed(0)}%';
      case DownloadStatus.pending:
        return '排队中';
      case DownloadStatus.resolving:
        return '正在解析视频源';
      default:
        return '';
    }
  }

  List<Widget> _getActionButtons(_EpisodeEntry entry) {
    final record = entry.record;
    final episode = entry.episode;
    final colorScheme = Theme.of(context).colorScheme;
    final buttons = <Widget>[];

    switch (episode.status) {
      case DownloadStatus.completed:
        buttons.add(
          IconButton(
            icon: Icon(
              Icons.play_circle_outline,
              size: 20,
              color: colorScheme.primary,
            ),
            onPressed: () => _playEpisode(entry),
            tooltip: '播放',
            visualDensity: VisualDensity.compact,
          ),
        );
        break;
      case DownloadStatus.downloading:
        buttons.add(
          IconButton(
            icon: const Icon(Icons.pause_rounded, size: 20),
            onPressed: () => downloadController.pauseDownload(
              record.bangumiId,
              record.pluginName,
              episode.episodeNumber,
            ),
            tooltip: '暂停',
            visualDensity: VisualDensity.compact,
          ),
        );
        break;
      case DownloadStatus.paused:
        buttons.add(
          IconButton(
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            onPressed: () => downloadController.retryDownload(
              bangumiId: record.bangumiId,
              pluginName: record.pluginName,
              episodeNumber: episode.episodeNumber,
            ),
            tooltip: '继续',
            visualDensity: VisualDensity.compact,
          ),
        );
        break;
      case DownloadStatus.failed:
        buttons.add(
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: () => downloadController.retryDownload(
              bangumiId: record.bangumiId,
              pluginName: record.pluginName,
              episodeNumber: episode.episodeNumber,
            ),
            tooltip: '重试',
            visualDensity: VisualDensity.compact,
          ),
        );
        break;
      case DownloadStatus.pending:
        buttons.add(
          IconButton(
            icon: Icon(
              Icons.priority_high,
              size: 20,
              color: colorScheme.primary,
            ),
            onPressed: () {
              downloadController.priorityDownload(
                bangumiId: record.bangumiId,
                pluginName: record.pluginName,
                episodeNumber: episode.episodeNumber,
              );
              KazumiDialog.showToast(message: '已插队优先下载');
            },
            tooltip: '优先下载',
            visualDensity: VisualDensity.compact,
          ),
        );
        break;
      default:
        break;
    }

    buttons.add(
      IconButton(
        icon: Icon(
          Icons.delete_outline,
          size: 20,
          color: colorScheme.onSurfaceVariant,
        ),
        onPressed: () => _confirmDeleteEpisode(record, episode),
        tooltip: '删除',
        visualDensity: VisualDensity.compact,
      ),
    );

    return buttons;
  }

  void _playEpisode(_EpisodeEntry entry) {
    final record = entry.record;
    final episode = entry.episode;
    final localPath = downloadController.getLocalVideoPath(
      record.bangumiId,
      record.pluginName,
      episode.episodeNumber,
    );
    if (localPath == null) {
      KazumiDialog.showToast(message: '本地文件不存在');
      return;
    }

    final bangumiItem = BangumiItem(
      id: record.bangumiId,
      type: 2,
      name: record.bangumiName,
      nameCn: record.bangumiName,
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: {'large': record.coverSource},
      tags: [],
      alias: [],
      ratingScore: 0.0,
      votes: 0,
      votesCount: [],
      info: '',
    );

    // Mirror the 本地 tab: play the show's downloaded episodes merged across
    // every source, resolving each episode's file from its owning source.
    final completedByNumber = <int, DownloadEpisode>{};
    final episodePlugins = <int, String>{};
    for (final candidate in downloadController.records) {
      if (candidate.bangumiId != record.bangumiId) continue;
      for (final candidateEpisode in candidate.episodes.values) {
        if (candidateEpisode.status != DownloadStatus.completed) continue;
        completedByNumber.putIfAbsent(
          candidateEpisode.episodeNumber,
          () => candidateEpisode,
        );
        episodePlugins.putIfAbsent(
          candidateEpisode.episodeNumber,
          () => candidate.pluginName,
        );
      }
    }
    final downloadedEpisodes = completedByNumber.values.toList()
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));

    context.pushNamed(
      '/video/',
      arguments: OfflineVideoPlaybackArgs(
        bangumiItem: bangumiItem,
        pluginName: record.pluginName,
        episodeNumber: episode.episodeNumber,
        road: episode.road,
        downloadedEpisodes: downloadedEpisodes,
        episodePlugins: episodePlugins,
      ),
    );
  }

  void _confirmDeleteEpisode(DownloadRecord record, DownloadEpisode episode) {
    KazumiDialog.show(
      builder: (context) => AlertDialog(
        title: const Text('删除下载'),
        content: Text(
          '确定要删除「${_titlesFor(record.bangumiId).titleFor(episodeNumber: episode.episodeNumber, name: episode.episodeName)}」的下载文件吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(),
            child: Text(
              '取消',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () async {
              KazumiDialog.dismiss();
              await _deleteDownload(
                () => downloadController.deleteEpisode(
                  record.bangumiId,
                  record.pluginName,
                  episode.episodeNumber,
                ),
              );
            },
            child: Text(
              '删除',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCompleted(_ShowGroup group) {
    KazumiDialog.show(
      builder: (context) => AlertDialog(
        title: const Text('删除已下载的内容'),
        content: Text('确定要删除「${group.bangumiName}」中已下载完成的内容吗？'),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(),
            child: Text(
              '取消',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () async {
              KazumiDialog.dismiss();
              await _deleteDownload(() async {
                for (final record in group.records) {
                  await downloadController.deleteCompletedEpisodes(
                    record.bangumiId,
                    record.pluginName,
                  );
                }
              });
            },
            child: Text(
              '删除',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteIncomplete(_ShowGroup group) {
    KazumiDialog.show(
      builder: (context) => AlertDialog(
        title: const Text('删除未完成的下载'),
        content: Text('确定要删除「${group.bangumiName}」中未完成的下载吗？已下载完成的内容会保留。'),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(),
            child: Text(
              '取消',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () async {
              KazumiDialog.dismiss();
              await _deleteDownload(() async {
                for (final record in group.records) {
                  await downloadController.deleteIncompleteEpisodes(
                    record.bangumiId,
                    record.pluginName,
                  );
                }
              });
            },
            child: Text(
              '删除',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDownload(Future<void> Function() delete) async {
    try {
      await delete();
    } catch (e) {
      KazumiLogger().w('DownloadPage: failed to delete download', error: e);
      if (!mounted) return;
      KazumiDialog.show(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除失败'),
          content: const Text('删除下载文件失败，请稍后重试'),
          actions: [
            TextButton(
              onPressed: () => KazumiDialog.dismiss(context: context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }
}
