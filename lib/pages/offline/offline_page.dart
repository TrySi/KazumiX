import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/collect/collect_layout.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/download/download_show_group.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/repositories/bangumi_offline_cache_repository.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/media.dart';

enum _OfflineSort {
  recentWatch('最近观看'),
  recent('最近下载'),
  title('番剧名称'),
  downloaded('已下载最多');

  const _OfflineSort(this.label);
  final String label;
}

/// Per-episode watch state for offline (local) playback, derived from the
/// offline history entries of a show.
enum _EpisodeWatchState {
  unwatched('未看过'),
  partial('观看中'),
  completed('已看完');

  const _EpisodeWatchState(this.label);
  final String label;
}

/// A show aggregated across download records (sources): one entry per bangumi,
/// with its cover and every downloaded episode keeping its owning record.
class _OfflineShow {
  factory _OfflineShow(ShowDownloads downloads, {DateTime? lastWatchTime}) {
    final derived = _deriveDownloads(downloads.entries);
    // [downloads.entries] is ordered by episode number and the map keeps the
    // first entry of each number, so its values already come out in that order.
    // Re-sorting would only be a place for an unstable sort to creep back in.
    final downloaded = derived.completed.values
        .map((entry) => entry.episode)
        .toList();
    return _OfflineShow._(
      downloads: downloads,
      lastWatchTime: lastWatchTime,
      completedByNumber: derived.completed,
      downloadedEpisodes: downloaded,
      activeCount: derived.active.length,
    );
  }

  _OfflineShow._({
    required this.downloads,
    required this.completedByNumber,
    required this.downloadedEpisodes,
    required this.activeCount,
    this.lastWatchTime,
  });

  /// The show's downloads, merged across sources.
  final ShowDownloads downloads;

  int get bangumiId => downloads.bangumiId;
  String get bangumiName => downloads.bangumiName;
  String get coverSource => downloads.coverSource;
  DateTime get latestTime => downloads.latestTime;

  /// Every downloaded episode of every source, keeping its owning record.
  List<DownloadEntry> get episodes => downloads.entries;

  /// The record supplying the show's identity (name and cover) when several
  /// sources downloaded the same bangumi.
  DownloadRecord get primaryRecord => downloads.primaryRecord;

  /// Most recent watch time of this show across all history entries.
  final DateTime? lastWatchTime;

  /// Downloaded episodes by episode number, earliest source winning. Every
  /// derived count below comes from here, so a show is scanned exactly once.
  final Map<int, DownloadEntry> completedByNumber;

  /// [completedByNumber] sorted by episode number, for playback.
  final List<DownloadEpisode> downloadedEpisodes;

  /// Distinct episode numbers still downloading or queued. Counted per episode
  /// so it reads the same way as [completedCount], even when the same episode
  /// is queued from several sources.
  final int activeCount;

  /// Distinct downloaded episode numbers.
  int get completedCount => completedByNumber.length;

  /// Card subtitle. Both counts are distinct episode numbers, so a show that
  /// is downloaded from several sources is not counted twice.
  String get downloadStatusLabel => activeCount > 0
      ? '已下载 $completedCount 集 · 下载中 $activeCount 集'
      : '已下载 $completedCount 集';

  /// Splits [episodes] into the two states the cards report, in one pass.
  static ({Map<int, DownloadEntry> completed, Set<int> active})
  _deriveDownloads(List<DownloadEntry> episodes) {
    final completed = <int, DownloadEntry>{};
    final active = <int>{};
    for (final entry in episodes) {
      final number = entry.episode.episodeNumber;
      switch (entry.episode.status) {
        case DownloadStatus.completed:
          completed.putIfAbsent(number, () => entry);
        case DownloadStatus.downloading:
        case DownloadStatus.resolving:
        case DownloadStatus.pending:
          active.add(number);
      }
    }
    return (completed: completed, active: active);
  }
}

class OfflinePage extends StatefulWidget {
  const OfflinePage({super.key, required this.controller});

  final DownloadController controller;

  @override
  State<OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends State<OfflinePage>
    with TickerProviderStateMixin {
  DownloadController get downloadController => widget.controller;
  final HistoryController historyController = inject<HistoryController>();
  final CollectController collectController = inject<CollectController>();

  /// Watch-progress filter options; the first (null) means "all".
  static const List<_EpisodeWatchState?> _watchFilters = [
    null,
    _EpisodeWatchState.unwatched,
    _EpisodeWatchState.partial,
    _EpisodeWatchState.completed,
  ];

  /// Collect-status filter options; the first (null) means "all".
  static const List<CollectType?> _collectFilters = [
    null,
    CollectType.watching,
    CollectType.planToWatch,
    CollectType.watched,
    CollectType.onHold,
    CollectType.abandoned,
  ];

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  late CollectLayout _layout;
  _OfflineSort _sort = _OfflineSort.recentWatch;
  bool _searchExpanded = false;
  _EpisodeWatchState? _progressFilter;
  CollectType? _collectFilter;
  bool _selecting = false;
  final Set<int> _selectedIds = {};
  late final TabController _progressTab = TabController(
    length: _watchFilters.length,
    vsync: this,
  )..addListener(_onProgressTabChanged);
  late final TabController _collectTab = TabController(
    length: _collectFilters.length,
    vsync: this,
  )..addListener(_onCollectTabChanged);

  @override
  void initState() {
    super.initState();
    _layout = CollectLayout.fromValue(
      GStorage.getSetting(SettingsKeys.defaultCollectLayout),
    );
    downloadController.refreshRecords();
    // The history list is only filled on init; load it so per-episode watch
    // states are available without visiting the history page first.
    historyController.init();
    collectController.loadCollectibles();
  }

  @override
  void dispose() {
    _progressTab.dispose();
    _collectTab.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onProgressTabChanged() {
    if (_progressTab.indexIsChanging) return;
    final next = _watchFilters[_progressTab.index];
    if (next == _progressFilter) return;
    setState(() => _progressFilter = next);
  }

  void _onCollectTabChanged() {
    if (_collectTab.indexIsChanging) return;
    final next = _collectFilters[_collectTab.index];
    if (next == _collectFilter) return;
    setState(() => _collectFilter = next);
  }

  void _enterSelecting() {
    setState(() {
      _selecting = true;
      _selectedIds.clear();
    });
  }

  void _exitSelecting() {
    if (!_selecting) return;
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(int bangumiId) {
    setState(() {
      if (!_selectedIds.add(bangumiId)) {
        _selectedIds.remove(bangumiId);
      }
    });
  }

  /// BangumiItem for a downloaded show: the collected item when present,
  /// otherwise a minimal item built from the download record.

  List<_OfflineShow> _buildShows() {
    // Latest watch time per bangumi, merged across online/offline histories.
    final watchTimes = <int, DateTime>{};
    for (final history in historyController.histories) {
      final id = history.bangumiItem.id;
      final previous = watchTimes[id];
      if (previous == null || history.lastWatchTime.isAfter(previous)) {
        watchTimes[id] = history.lastWatchTime;
      }
    }

    return [
      for (final downloads in groupDownloadsByShow(downloadController.records))
        _OfflineShow(downloads, lastWatchTime: watchTimes[downloads.bangumiId]),
    ];
  }

  /// Orders [a] relative to [b] for the "recently watched" sort: shows with a
  /// watch record come first (newest first), unwatched shows fall back to
  /// download recency.
  int _compareWatch(_OfflineShow a, _OfflineShow b) {
    final ta = a.lastWatchTime;
    final tb = b.lastWatchTime;
    if (ta != null && tb != null) return tb.compareTo(ta);
    if (ta != null) return -1;
    if (tb != null) return 1;
    return b.latestTime.compareTo(a.latestTime);
  }

  List<_OfflineShow> _filter(
    List<_OfflineShow> shows,
    Map<int, CollectType> collectTypes,
    Map<int, Map<int, _EpisodeWatchState>> watchStatesByShow,
  ) {
    final terms = _query.trim().toLowerCase().split(RegExp(r'\s+'));
    final result = shows.where((show) {
      if (!terms.every(show.bangumiName.toLowerCase().contains)) {
        return false;
      }
      if (_collectFilter != null &&
          (collectTypes[show.bangumiId] ?? CollectType.none) !=
              _collectFilter) {
        return false;
      }
      if (_progressFilter != null) {
        final states = watchStatesByShow[show.bangumiId] ?? const {};
        if (_overallWatchState(show, states) != _progressFilter) {
          return false;
        }
      }
      return true;
    }).toList();
    result.sort((a, b) {
      final comparison = switch (_sort) {
        _OfflineSort.recentWatch => _compareWatch(a, b),
        _OfflineSort.recent => b.latestTime.compareTo(a.latestTime),
        _OfflineSort.title => a.bangumiName.toLowerCase().compareTo(
          b.bangumiName.toLowerCase(),
        ),
        _OfflineSort.downloaded => b.completedCount.compareTo(a.completedCount),
      };
      if (comparison != 0) return comparison;
      return a.bangumiName.toLowerCase().compareTo(b.bangumiName.toLowerCase());
    });
    return result;
  }

  /// Groups the offline history entries by bangumi in a single pass, so
  /// deriving the watch states of every show costs O(histories) in total
  /// instead of re-scanning the list once per show.
  Map<int, List<History>> _offlineHistoriesByBangumi() {
    final grouped = <int, List<History>>{};
    for (final history in historyController.histories) {
      if (HistoryEntryKind.normalize(history.entryKind) !=
          HistoryEntryKind.offline) {
        continue;
      }
      grouped.putIfAbsent(history.bangumiItem.id, () => []).add(history);
    }
    return grouped;
  }

  /// Derives the per-episode watch state from a show's offline history
  /// entries, merging every source by the newest update.
  Map<int, _EpisodeWatchState> _watchStatesFrom(List<History>? histories) {
    if (histories == null || histories.isEmpty) return const {};
    final latest = <int, ({Progress progress, int updatedAt})>{};
    for (final history in histories) {
      history.progresses.forEach((episode, progress) {
        final updatedAt = progress.effectiveUpdatedAtMs(history.lastWatchTime);
        final current = latest[episode];
        if (current == null || updatedAt >= current.updatedAt) {
          latest[episode] = (progress: progress, updatedAt: updatedAt);
        }
      });
    }
    return {
      for (final entry in latest.entries)
        entry.key: entry.value.progress.completed
            ? _EpisodeWatchState.completed
            : entry.value.progress.progress > Duration.zero
            ? _EpisodeWatchState.partial
            : _EpisodeWatchState.unwatched,
    };
  }

  /// Opens a bottom sheet (matching the download picker) so the user can
  /// choose which downloaded episodes are watched; writes back to history.
  Future<void> _editWatchStates(_OfflineShow show) async {
    // 隐身模式 (SettingsKeys.privateMode) 下 history 写入被静默跳过，此时打开
    // 编辑器只会让用户改完后拿到「0/N 集写入失败」的误导提示。
    if (GStorage.getSetting<bool>(SettingsKeys.privateMode)) {
      KazumiDialog.showToast(message: '隐身模式已开启，不记录观看状态');
      return;
    }
    final episodes = show.completedByNumber;
    final numbers = episodes.keys.toList()..sort();
    if (numbers.isEmpty) return;
    final states = _watchStatesFrom(
      _offlineHistoriesByBangumi()[show.bangumiId],
    );

    final picked = await showAdaptiveBottomSheet<Set<int>>(
      context: context,
      builder: (context) => _WatchStateEditorSheet(
        showName: show.bangumiName,
        numbers: numbers,
        episodes: episodes,
        states: states,
        titles: OfflineEpisodeTitles.fromCache(
          BangumiOfflineCacheRepository().readEpisodes(show.bangumiId),
        ),
      ),
    );
    if (picked == null) return;

    final bangumiItem = _bangumiItemFor(show);
    final updates = <EpisodeWatchUpdate>[];
    for (final n in numbers) {
      final wasWatched = states[n] == _EpisodeWatchState.completed;
      final shouldWatch = picked.contains(n);
      if (wasWatched == shouldWatch) continue;
      final entry = episodes[n]!;
      updates.add((
        bangumiItem: bangumiItem,
        adapterName: entry.record.pluginName,
        episode: n,
        episodeTitle: entry.episode.episodeName,
        road: entry.episode.road,
        watched: shouldWatch,
      ));
    }
    if (updates.isEmpty) return;
    // One batch: the controller refreshes the history list once, and reports
    // how many writes really landed instead of assuming they all did.
    final changed = await historyController.setEpisodesWatched(updates);
    if (!mounted) return;
    setState(() {});
    KazumiDialog.showToast(
      message: changed == updates.length
          ? '已更新 $changed 集的观看状态'
          : '已更新 $changed/${updates.length} 集，其余写入失败',
    );
  }

  /// Confirms and deletes every downloaded episode of the selected shows,
  /// across all sources. Files, records and the cached cover are removed.
  Future<void> _deleteSelected(List<_OfflineShow> shows) async {
    final selected = shows
        .where((show) => _selectedIds.contains(show.bangumiId))
        .toList();
    if (selected.isEmpty) return;
    final confirmed = await KazumiDialog.show<bool>(
      builder: (context) => AlertDialog(
        title: const Text('删除下载'),
        content: Text('确定要删除选中的 ${selected.length} 部番剧的全部下载文件吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              '删除',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    var deleted = 0;
    var failed = 0;
    for (final show in selected) {
      final plugins = <String>{
        for (final e in show.episodes) e.record.pluginName,
      };
      var showDeleted = true;
      for (final pluginName in plugins) {
        try {
          await downloadController.deleteRecord(show.bangumiId, pluginName);
        } catch (error, stackTrace) {
          // Keep going: one broken record must not leave the rest behind, and
          // the selection state still has to be released below.
          showDeleted = false;
          KazumiLogger().e(
            'OfflinePage: 删除下载失败 '
            'bangumiId=${show.bangumiId} plugin=$pluginName',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      if (showDeleted) {
        deleted++;
      } else {
        failed++;
      }
    }
    if (!mounted) return;
    downloadController.refreshRecords();
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
    KazumiDialog.showToast(
      message: failed == 0
          ? '已删除 $deleted 部番剧的下载'
          : '已删除 $deleted 部，$failed 部失败',
    );
  }

  /// Minimal item carrying the show's identity for history lookups (the
  /// history key only uses the bangumi id).
  BangumiItem _bangumiItemFor(_OfflineShow show) =>
      show.primaryRecord.toBangumiItem();

  void _openEpisodes(_OfflineShow show) {
    showAdaptiveBottomSheet<void>(
      context: context,
      builder: (context) => _OfflineEpisodeSheet(
        show: show,
        watchStates: _watchStatesFrom(
          _offlineHistoriesByBangumi()[show.bangumiId],
        ),
        onPlay: (entry) => _playEpisode(show, entry),
      ),
    );
  }

  void _playEpisode(_OfflineShow show, DownloadEntry entry) {
    final record = entry.record;
    final episode = entry.episode;
    final localPath = downloadController.getLocalVideoPath(
      record.bangumiId,
      record.pluginName,
      episode.episodeNumber,
    );
    if (localPath == null) {
      KazumiLogger().e(
        'OfflinePage: 本地文件不存在 '
        'bangumiId=${record.bangumiId} plugin=${record.pluginName} '
        'episode=${episode.episodeNumber}',
      );
      KazumiDialog.showToast(message: '本地文件不存在');
      return;
    }

    final bangumiItem = record.toBangumiItem();

    context.pushNamed(
      '/video/',
      arguments: OfflineVideoPlaybackArgs(
        bangumiItem: bangumiItem,
        pluginName: record.pluginName,
        episodeNumber: episode.episodeNumber,
        road: episode.road,
        // Include every downloaded episode of the show, across all sources,
        // so the player's episode list is not limited to one source.
        downloadedEpisodes: show.downloadedEpisodes,
        episodePlugins: {
          for (final entry in show.completedByNumber.entries)
            entry.key: entry.value.record.pluginName,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        // Touch collectibles so status changes trigger a rebuild.
        final collectibles = collectController.collectibles;
        final collectTypes = <int, CollectType>{
          for (final entry in collectibles)
            entry.bangumiItem.id: CollectType.fromValue(entry.type),
        };
        // Derive watch states for every show before filtering, grouping the
        // offline histories in a single pass so the cost stays linear in the
        // number of history entries rather than per show.
        final allShows = _buildShows();
        final offlineHistories = _offlineHistoriesByBangumi();
        final watchStatesByShow = <int, Map<int, _EpisodeWatchState>>{
          for (final show in allShows)
            show.bangumiId: _watchStatesFrom(offlineHistories[show.bangumiId]),
        };
        final shows = _filter(allShows, collectTypes, watchStatesByShow);
        return Scaffold(
          appBar: SysAppBar(
            needTopOffset: false,
            toolbarHeight: 72,
            title: Text(
              _selecting ? '已选 ${_selectedIds.length} 部' : '本地',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _selecting
                    ? StateActionButton.tonal(
                        text: '取消',
                        onPressed: _exitSelecting,
                        icon: Icons.close_rounded,
                      )
                    : Tooltip(
                        message: '批量删除下载',
                        child: StateActionButton.tonal(
                          text: '删除',
                          onPressed: shows.isEmpty ? null : _enterSelecting,
                          icon: Icons.delete_outline_rounded,
                        ),
                      ),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 600;
                final width = constraints.maxWidth.clamp(0.0, 1560.0);
                final inset =
                    (constraints.maxWidth - width) / 2 +
                    (compact ? 16.0 : 32.0);
                final contentWidth = constraints.maxWidth - inset * 2;
                return CustomScrollView(
                  // Keep off the PrimaryScrollController so overlays (menus)
                  // can own it without a multiple-ScrollPosition conflict.
                  primary: false,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(inset, 8, inset, 12),
                      sliver: SliverToBoxAdapter(
                        child: _header(compact: compact, count: shows.length),
                      ),
                    ),
                    if (shows.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _emptyState(),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          inset,
                          0,
                          inset,
                          24 + MediaQuery.paddingOf(context).bottom,
                        ),
                        sliver: _layout == CollectLayout.cards
                            ? _grid(shows, contentWidth)
                            : _list(
                                shows,
                                contentWidth,
                                collectTypes,
                                watchStatesByShow,
                              ),
                      ),
                  ],
                );
              },
            ),
          ),
          bottomNavigationBar: _selecting ? _selectionBar(shows) : null,
        );
      },
    );
  }

  /// Bottom action bar shown while in multi-select mode.
  Widget _selectionBar(List<_OfflineShow> shows) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final allSelected = shows.isNotEmpty && _selectedIds.length == shows.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: shows.isEmpty
                  ? null
                  : () => setState(() {
                      if (allSelected) {
                        _selectedIds.clear();
                      } else {
                        _selectedIds
                          ..clear()
                          ..addAll(shows.map((show) => show.bangumiId));
                      }
                    }),
              // Reserve the widest label to keep the button width stable.
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Opacity(opacity: 0, child: Text('取消全选')),
                  Text(allSelected ? '取消全选' : '全选'),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: colors.errorContainer,
                  foregroundColor: colors.onErrorContainer,
                ),
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () => _deleteSelected(shows),
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(
                  _selectedIds.isEmpty ? '选择番剧' : '删除 ${_selectedIds.length} 部',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header({required bool compact, required int count}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterTabs(
          controller: _progressTab,
          labels: [for (final state in _watchFilters) state?.label ?? '全部'],
        ),
        const SizedBox(height: 4),
        _FilterTabs(
          controller: _collectTab,
          labels: [for (final type in _collectFilters) type?.label ?? '全部'],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (!compact)
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: _searchBar(),
                  ),
                ),
              )
            else
              Expanded(
                child: Text(
                  '$count 部',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(width: 12),
            _sortMenu(showLabel: !compact),
            if (compact)
              IconButton(
                tooltip: _searchExpanded ? '收起搜索' : '搜索离线内容',
                isSelected: _searchExpanded,
                selectedIcon: const Icon(Icons.search_off_rounded),
                icon: const Icon(Icons.search_rounded),
                onPressed: () => setState(() {
                  _searchExpanded = !_searchExpanded;
                  if (!_searchExpanded) {
                    _searchController.clear();
                    _query = '';
                  }
                }),
              ),
            const SizedBox(width: 8),
            _layoutSwitch(),
          ],
        ),
        if (compact && _searchExpanded) ...[
          const SizedBox(height: 8),
          _searchBar(),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _searchBar() => Semantics(
    label: '搜索离线内容',
    child: SearchBar(
      controller: _searchController,
      focusNode: _searchFocus,
      hintText: '搜索离线内容',
      leading: const Icon(Icons.search_rounded, size: 22),
      trailing: [
        if (_query.isNotEmpty)
          IconButton(
            tooltip: '清除搜索',
            onPressed: () {
              _searchController.clear();
              setState(() => _query = '');
            },
            icon: const Icon(Icons.close_rounded),
          ),
      ],
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(
        Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16),
      ),
      constraints: const BoxConstraints(minHeight: 48),
      onChanged: (value) => setState(() => _query = value),
      onSubmitted: (_) => _searchFocus.unfocus(),
    ),
  );

  Widget _sortMenu({required bool showLabel}) {
    return KazumiMenuButton(
      menuChildren: [
        for (final sort in _OfflineSort.values)
          KazumiMenuItem(
            selected: _sort == sort,
            onPressed: () => setState(() => _sort = sort),
            label: sort.label,
          ),
      ],
      builder: (context, toggle) => Tooltip(
        message: '排序：${_sort.label}',
        child: showLabel
            ? TextButton.icon(
                onPressed: toggle,
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.sort_rounded, size: 20),
                label: Text(_sort.label),
              )
            : IconButton(
                onPressed: toggle,
                icon: const Icon(Icons.sort_rounded),
              ),
      ),
    );
  }

  Widget _layoutSwitch() {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        for (final layout in [CollectLayout.cards, CollectLayout.list])
          Semantics(
            selected: _layout == layout,
            inMutuallyExclusiveGroup: true,
            child: IconButton.filledTonal(
              tooltip: '${layout.label}布局',
              isSelected: _layout == layout,
              onPressed: () => setState(() => _layout = layout),
              style: ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                visualDensity: VisualDensity.standard,
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? colors.secondaryContainer
                      : colors.surfaceContainerLow,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                ),
                shape: WidgetStateProperty.resolveWith(
                  (states) => RoundedRectangleBorder(
                    borderRadius: states.contains(WidgetState.pressed)
                        ? BorderRadius.circular(12)
                        : states.contains(WidgetState.selected)
                        ? BorderRadius.circular(24)
                        : BorderRadiusDirectional.horizontal(
                            start: Radius.circular(
                              layout == CollectLayout.cards ? 24 : 8,
                            ),
                            end: Radius.circular(
                              layout == CollectLayout.list ? 24 : 8,
                            ),
                          ),
                  ),
                ),
                animationDuration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
              ),
              icon: Icon(
                layout == CollectLayout.list
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded,
              ),
            ),
          ),
      ],
    );
  }

  Widget _grid(List<_OfflineShow> shows, double contentWidth) {
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final spacing = portrait ? (contentWidth < 600 ? 8.0 : 12.0) : 16.0;
    final scaler = MediaQuery.textScalerOf(context);
    final textScale = (scaler.scale(14) / 14).clamp(1.0, double.infinity);
    final minWidth =
        (contentWidth < 600 ? 136.0 : 172.0) + 32 * (textScale - 1);
    final baseColumns = portrait
        ? 3
        : ((contentWidth + spacing) / (minWidth + spacing)).floor().clamp(1, 6);
    // Fit ~1.5x the columns so each poster renders at about 2/3 the size.
    final columns = (baseColumns * 3 / 2).floor().clamp(1, 12);
    final width = (contentWidth - spacing * (columns - 1)) / columns;
    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: spacing,
        mainAxisSpacing: portrait ? 12 : spacing,
        mainAxisExtent: _OfflinePosterCard.extent(width, scaler),
      ),
      itemCount: shows.length,
      itemBuilder: (context, index) => _OfflinePosterCard(
        key: ValueKey('offline-${shows[index].bangumiId}'),
        show: shows[index],
        selecting: _selecting,
        selected: _selectedIds.contains(shows[index].bangumiId),
        onTap: _selecting
            ? () => _toggleSelected(shows[index].bangumiId)
            : () => _openEpisodes(shows[index]),
      ),
    );
  }

  Widget _list(
    List<_OfflineShow> shows,
    double contentWidth,
    Map<int, CollectType> collectTypes,
    Map<int, Map<int, _EpisodeWatchState>> watchStatesByShow,
  ) {
    const spacing = 12.0;
    final textScale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      double.infinity,
    );
    final minWidth = 300 + 160 * (textScale - 1);
    final preferredWidth = 400 + 160 * (textScale - 1);
    final maxColumns = ((contentWidth + spacing) / (minWidth + spacing))
        .floor()
        .clamp(1, 12);
    final columns = ((contentWidth + spacing) / (preferredWidth + spacing))
        .ceil()
        .clamp(1, maxColumns);

    Widget tile(int index) => IndexedSemantics(
      index: index,
      child: _OfflineListTile(
        key: ValueKey('offline-${shows[index].bangumiId}'),
        show: shows[index],
        collectType: collectTypes[shows[index].bangumiId] ?? CollectType.none,
        watchStates: watchStatesByShow[shows[index].bangumiId] ?? const {},
        selecting: _selecting,
        selected: _selectedIds.contains(shows[index].bangumiId),
        onOpen: () => _openEpisodes(shows[index]),
        onEditProgress: () => _editWatchStates(shows[index]),
        onToggleSelect: () => _toggleSelected(shows[index].bangumiId),
      ),
    );

    return SliverList.builder(
      itemCount: (shows.length + columns - 1) ~/ columns,
      addSemanticIndexes: false,
      itemBuilder: (context, row) {
        final first = row * columns;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: columns == 1
              ? tile(first)
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: spacing,
                    children: [
                      for (var column = 0; column < columns; column++)
                        Expanded(
                          child: first + column < shows.length
                              ? tile(first + column)
                              : const SizedBox(),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _emptyState() {
    final searching = _query.trim().isNotEmpty;
    return GeneralEmptyState(
      icon: searching ? Icons.search_off_rounded : Icons.download_rounded,
      title: searching ? '没有找到匹配的离线内容' : '还没有下载的内容',
    );
  }
}

/// A scrollable pill-tab filter row, styled like the collect page's categories.
class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.controller, required this.labels});

  final TabController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return TabBar(
      controller: controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      dividerHeight: 0,
      indicatorSize: TabBarIndicatorSize.tab,
      indicatorPadding: const EdgeInsets.symmetric(horizontal: 2),
      indicator: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      indicatorAnimation: TabIndicatorAnimation.elastic,
      labelColor: colors.onPrimaryContainer,
      unselectedLabelColor: colors.onSurfaceVariant,
      labelStyle: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelStyle: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      labelPadding: const EdgeInsets.symmetric(horizontal: 2),
      splashBorderRadius: BorderRadius.circular(24),
      tabs: [
        for (final label in labels)
          Tab(
            height: 48,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(label, textAlign: TextAlign.center),
              ),
            ),
          ),
      ],
    );
  }
}

class _OfflinePosterCard extends StatelessWidget {
  const _OfflinePosterCard({
    super.key,
    required this.show,
    required this.selecting,
    required this.selected,
    required this.onTap,
  });

  final _OfflineShow show;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;

  static const _coverRatio = 0.65;

  static double extent(double width, TextScaler scaler) {
    final titleHeight = (scaler.scale(14) * 2.7).ceilToDouble();
    final statusHeight = (scaler.scale(12) * 1.6).ceilToDouble();
    return width / _coverRatio + 12 + titleHeight + 4 + statusHeight + 12;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = show.downloadStatusLabel;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: selecting || show.completedCount > 0,
        selected: selecting ? selected : null,
        label: '${show.bangumiName}，$status',
        child: InkWell(
          onTap: (selecting || show.completedCount > 0) ? onTap : null,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child: AspectRatio(
                      aspectRatio: _coverRatio,
                      child: _OfflineCover(src: show.coverSource),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            show.bangumiName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (selecting)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _SelectionBadge(selected: selected),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineListTile extends StatelessWidget {
  const _OfflineListTile({
    super.key,
    required this.show,
    required this.collectType,
    required this.watchStates,
    required this.selecting,
    required this.selected,
    required this.onOpen,
    required this.onEditProgress,
    required this.onToggleSelect,
  });

  final _OfflineShow show;
  final CollectType collectType;
  final Map<int, _EpisodeWatchState> watchStates;
  final bool selecting;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onEditProgress;
  final VoidCallback onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = show.downloadStatusLabel;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Isolate taps from the card's own affordance.
          Positioned.fill(
            child: Semantics(
              button: selecting || show.completedCount > 0,
              selected: selecting ? selected : null,
              label: '${show.bangumiName}，$status',
              child: InkWell(
                onTap: selecting
                    ? onToggleSelect
                    : (show.completedCount > 0 ? onOpen : null),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: SizedBox(
                      width: 80,
                      height: 120,
                      child: _OfflineCover(
                        src: show.coverSource,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: IgnorePointer(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 76),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    show.bangumiName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          height: 1.35,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '已下载 ${show.completedCount} 集'
                              ' · ${collectType == CollectType.none ? '未收藏' : collectType.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (!selecting) ...[
                            const SizedBox(width: 8),
                            _OfflineWatchProgressButton(
                              label: _overallWatchState(
                                show,
                                watchStates,
                              ).label,
                              enabled: show.completedCount > 0,
                              onPressed: onEditProgress,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (selecting)
            Positioned(
              top: 8,
              right: 8,
              child: _SelectionBadge(selected: selected),
            ),
        ],
      ),
    );
  }
}

/// Round check indicator used on cards in multi-select mode.
class _SelectionBadge extends StatelessWidget {
  const _SelectionBadge({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primary : colors.surfaceContainerHighest,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: null,
        child: Icon(
          selected ? Icons.check_rounded : Icons.circle_outlined,
          size: 20,
          color: selected ? colors.onPrimary : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Collapses the per-episode states of a show's downloaded episodes into one
/// overall state: 未看过 / 观看中 / 已看完.
_EpisodeWatchState _overallWatchState(
  _OfflineShow show,
  Map<int, _EpisodeWatchState> watchStates,
) {
  final numbers = show.completedByNumber.keys;
  if (numbers.isEmpty) return _EpisodeWatchState.unwatched;

  var completed = 0;
  var touched = 0;
  for (final n in numbers) {
    final state = watchStates[n];
    if (state == _EpisodeWatchState.completed) {
      completed++;
      touched++;
    } else if (state == _EpisodeWatchState.partial) {
      touched++;
    }
  }
  if (completed == numbers.length) return _EpisodeWatchState.completed;
  if (touched == 0) return _EpisodeWatchState.unwatched;
  return _EpisodeWatchState.partial;
}

/// The single button on an offline card. Its label is the show's overall watch
/// state; tapping opens the watch-state editor. Disabled when nothing is
/// downloaded.
class _OfflineWatchProgressButton extends StatelessWidget {
  const _OfflineWatchProgressButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: enabled ? '编辑观看状态' : '暂无可操作的下载',
    child: FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 0),
      ),
      onPressed: enabled ? onPressed : null,
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.expand_more_rounded, size: 18),
      label: Text(label),
    ),
  );
}

/// Bottom sheet (matching the download episode picker) for choosing which
/// downloaded episodes are watched. Returns the selected numbers, or null when
/// dismissed.
class _WatchStateEditorSheet extends StatefulWidget {
  const _WatchStateEditorSheet({
    required this.showName,
    required this.numbers,
    required this.episodes,
    required this.states,
    required this.titles,
  });

  final String showName;
  final List<int> numbers;
  final Map<int, DownloadEntry> episodes;
  final Map<int, _EpisodeWatchState> states;
  final OfflineEpisodeTitles titles;

  @override
  State<_WatchStateEditorSheet> createState() => _WatchStateEditorSheetState();
}

class _WatchStateEditorSheetState extends State<_WatchStateEditorSheet> {
  // Initially the episodes already marked as watched.
  late final Set<int> _selected = {
    for (final n in widget.numbers)
      if (widget.states[n] == _EpisodeWatchState.completed) n,
  };

  bool get _allSelected =>
      _selected.length == widget.numbers.length && widget.numbers.isNotEmpty;

  String _episodeLabel(int number) => widget.titles.titleFor(
    episodeNumber: number,
    name: widget.episodes[number]?.episode.episodeName ?? '',
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MaterialBottomSheetHeader(
          title: '编辑观看状态',
          description:
              '${widget.showName} · '
              '勾选已看完的集数，共 ${widget.numbers.length} 集',
          onClose: () => Navigator.of(context).pop(),
        ),
        Flexible(
          child: GridView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              mainAxisExtent: 56,
            ),
            itemCount: widget.numbers.length,
            itemBuilder: (context, index) {
              final number = widget.numbers[index];
              final selected = _selected.contains(number);
              return _OfflineEpisodeTile(
                title: _episodeLabel(number),
                downloaded: true,
                state: selected
                    ? _EpisodeWatchState.completed
                    : _EpisodeWatchState.unwatched,
                onTap: () => setState(() {
                  if (selected) {
                    _selected.remove(number);
                  } else {
                    _selected.add(number);
                  }
                }),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => setState(() {
                    if (_allSelected) {
                      _selected.clear();
                    } else {
                      _selected
                        ..clear()
                        ..addAll(widget.numbers);
                    }
                  }),
                  // Reserve the widest label to keep the width stable.
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Opacity(opacity: 0, child: Text('取消全选')),
                      Text(_allSelected ? '取消全选' : '全选'),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => Navigator.of(context).pop({..._selected}),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('应用'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OfflineCover extends StatelessWidget {
  const _OfflineCover({required this.src, this.borderRadius});

  final String src;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => NetworkImgLayer(
      src: src,
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      borderRadius: borderRadius,
    ),
  );
}

/// One episode row in the offline picker: either a cached episode number with
/// a title (and optionally a downloaded entry) or a downloaded-only fallback.
class _OfflineEpisodeChoice {
  _OfflineEpisodeChoice({
    required this.number,
    required this.title,
    this.entry,
    this.state = _EpisodeWatchState.unwatched,
  });

  final int number;
  final String title;
  final DownloadEntry? entry;
  final _EpisodeWatchState state;

  bool get downloaded => entry != null;
}

class _OfflineEpisodeSheet extends StatelessWidget {
  const _OfflineEpisodeSheet({
    required this.show,
    required this.watchStates,
    required this.onPlay,
  });

  final _OfflineShow show;
  final Map<int, _EpisodeWatchState> watchStates;
  final ValueChanged<DownloadEntry> onPlay;

  _EpisodeWatchState _stateFor(int number) =>
      watchStates[number] ?? _EpisodeWatchState.unwatched;

  List<_OfflineEpisodeChoice> _buildChoices(List<EpisodeInfo>? cached) {
    // Extras have no number, so they are matched by name instead. The main
    // episodes read the show's deduplicated map, so an episode plays from the
    // same source here as it does from the card and the player.
    final downloadedByName = <String, DownloadEntry>{};
    for (final e in show.episodes) {
      if (e.episode.status != DownloadStatus.completed) continue;
      final name = e.episode.episodeName.trim();
      if (name.isNotEmpty) downloadedByName.putIfAbsent(name, () => e);
    }

    // Prefer the offline-cached episode list so the full episode range is
    // shown even before every episode has been downloaded.
    if (cached == null || cached.isEmpty) {
      KazumiLogger().w(
        'OfflinePage: 离线缓存无集数 bangumiId=${show.bangumiId}，'
        '降级为仅显示已下载集',
      );
    }
    if (cached != null && cached.isNotEmpty) {
      final choices = <_OfflineEpisodeChoice>[
        for (final slot in offlineEpisodeSlots(cached))
          _OfflineEpisodeChoice(
            number: slot.episodeNumber,
            title: slot.title,
            entry: slot.episodeNumber > 0
                ? show.completedByNumber[slot.episodeNumber]
                : downloadedByName[slot.nameCn] ?? downloadedByName[slot.name],
            state: _stateFor(slot.episodeNumber),
          ),
      ];
      if (choices.isNotEmpty) return choices;
    }

    // 无缓存时，退回只显示已下载完成的集。show.episodes 已按集号和来源排好，
    // 再按集号排一次会丢掉来源的先后，同一集的两个来源顺序变得不确定。
    final completed = show.episodes
        .where((e) => e.episode.status == DownloadStatus.completed)
        .toList();
    return [
      for (final e in completed)
        _OfflineEpisodeChoice(
          number: e.episode.episodeNumber,
          title: e.episode.episodeName.trim().isNotEmpty
              ? formatEpisodeLabel(e.episode.episodeName.trim())
              : '第${e.episode.episodeNumber}话',
          entry: e,
          state: _stateFor(e.episode.episodeNumber),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cached = BangumiOfflineCacheRepository().readEpisodes(show.bangumiId);
    final choices = _buildChoices(cached);
    final downloadedCount = choices.where((c) => c.downloaded).length;
    final watchedCount = choices
        .where((c) => c.state == _EpisodeWatchState.completed)
        .length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MaterialBottomSheetHeader(
          title: show.bangumiName,
          description: cached != null && cached.isNotEmpty
              ? '共 ${choices.length} 集 · 已下载 $downloadedCount 集'
                    '${watchedCount > 0 ? ' · 已看完 $watchedCount 集' : ''}'
              : '已下载 $downloadedCount 集',
          onClose: () => Navigator.of(context).pop(),
        ),
        Flexible(
          child: choices.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: GeneralEmptyState(
                    icon: Icons.video_library_outlined,
                    title: '还没有已下载完成的集数',
                  ),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    mainAxisExtent: 56,
                  ),
                  itemCount: choices.length,
                  itemBuilder: (context, index) {
                    final choice = choices[index];
                    return _OfflineEpisodeTile(
                      title: choice.title,
                      downloaded: choice.downloaded,
                      state: choice.state,
                      onTap: choice.downloaded
                          ? () {
                              Navigator.of(context).pop();
                              onPlay(choice.entry!);
                            }
                          : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _OfflineEpisodeTile extends StatelessWidget {
  const _OfflineEpisodeTile({
    required this.title,
    required this.downloaded,
    this.state = _EpisodeWatchState.unwatched,
    this.onTap,
  });

  final String title;
  final bool downloaded;
  final _EpisodeWatchState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = downloaded
        ? colorScheme.onSurface
        : colorScheme.outline;

    final (
      IconData? stateIcon,
      Color? stateColor,
      String stateLabel,
    ) = switch (state) {
      _EpisodeWatchState.completed => (
        Icons.check_circle_rounded,
        downloaded ? colorScheme.primary : colorScheme.outline,
        '已看完',
      ),
      _EpisodeWatchState.partial => (
        Icons.play_circle_outline_rounded,
        downloaded ? colorScheme.primary : colorScheme.outline,
        '观看中',
      ),
      _EpisodeWatchState.unwatched => (null, null, '未看过'),
    };

    return Semantics(
      button: onTap != null,
      label: '$title，$stateLabel',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: foregroundColor),
                    ),
                  ),
                ),
                if (stateIcon != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(stateIcon, size: 14, color: stateColor),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
