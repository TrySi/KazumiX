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
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/repositories/bangumi_offline_cache_repository.dart';
import 'package:kazumi/services/logging/logger.dart';

enum _OfflineLayout { cards, list }

enum _OfflineSort {
  recent('最近下载'),
  title('番剧名称'),
  downloaded('已下载最多');

  const _OfflineSort(this.label);
  final String label;
}

/// A show aggregated across download records (sources): one entry per bangumi,
/// with its cover and every downloaded episode keeping its owning record.
class _OfflineShow {
  _OfflineShow({
    required this.bangumiId,
    required this.bangumiName,
    required this.coverSource,
    required this.latestTime,
    required this.episodes,
  });

  final int bangumiId;
  final String bangumiName;
  final String coverSource;
  final DateTime latestTime;
  final List<_OfflineEpisode> episodes;

  int get completedCount => episodes
      .where((e) => e.episode.status == DownloadStatus.completed)
      .length;

  int get activeCount => episodes.where((e) {
        final status = e.episode.status;
        return status == DownloadStatus.downloading ||
            status == DownloadStatus.resolving ||
            status == DownloadStatus.pending;
      }).length;
}

class _OfflineEpisode {
  _OfflineEpisode({required this.record, required this.episode});

  final DownloadRecord record;
  final DownloadEpisode episode;
}

class OfflinePage extends StatefulWidget {
  const OfflinePage({super.key, required this.controller});

  final DownloadController controller;

  @override
  State<OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends State<OfflinePage> {
  DownloadController get downloadController => widget.controller;

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  _OfflineLayout _layout = _OfflineLayout.cards;
  _OfflineSort _sort = _OfflineSort.recent;

  @override
  void initState() {
    super.initState();
    downloadController.refreshRecords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<_OfflineShow> _buildShows() {
    final byBangumi = <int, List<DownloadRecord>>{};
    for (final record in downloadController.records) {
      byBangumi.putIfAbsent(record.bangumiId, () => []).add(record);
    }

    final shows = <_OfflineShow>[];
    byBangumi.forEach((bangumiId, records) {
      final episodes = <_OfflineEpisode>[];
      var latestTime = DateTime(0);
      for (final record in records) {
        if (record.createdAt.isAfter(latestTime)) latestTime = record.createdAt;
        for (final episode in record.episodes.values) {
          episodes.add(_OfflineEpisode(record: record, episode: episode));
        }
      }
      episodes.sort(
        (a, b) => a.episode.episodeNumber.compareTo(b.episode.episodeNumber),
      );
      final first = records.first;
      shows.add(
        _OfflineShow(
          bangumiId: bangumiId,
          bangumiName: first.bangumiName,
          coverSource: first.coverSource,
          latestTime: latestTime,
          episodes: episodes,
        ),
      );
    });
    return shows;
  }

  List<_OfflineShow> _filter(List<_OfflineShow> shows) {
    final terms = _query.trim().toLowerCase().split(RegExp(r'\s+'));
    final result = shows
        .where((show) => terms.every(show.bangumiName.toLowerCase().contains))
        .toList();
    result.sort((a, b) {
      final comparison = switch (_sort) {
        _OfflineSort.recent => b.latestTime.compareTo(a.latestTime),
        _OfflineSort.title => a.bangumiName.toLowerCase().compareTo(
              b.bangumiName.toLowerCase(),
            ),
        _OfflineSort.downloaded =>
          b.completedCount.compareTo(a.completedCount),
      };
      if (comparison != 0) return comparison;
      return a.bangumiName.toLowerCase().compareTo(
            b.bangumiName.toLowerCase(),
          );
    });
    return result;
  }

  void _openEpisodes(_OfflineShow show) {
    showAdaptiveBottomSheet<void>(
      context: context,
      builder: (context) => _OfflineEpisodeSheet(
        show: show,
        onPlay: _playEpisode,
      ),
    );
  }

  void _playEpisode(_OfflineEpisode entry) {
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

    final downloadedEpisodes = downloadController.getCompletedEpisodes(
      record.bangumiId,
      record.pluginName,
    );

    context.pushNamed(
      '/video/',
      arguments: OfflineVideoPlaybackArgs(
        bangumiItem: bangumiItem,
        pluginName: record.pluginName,
        episodeNumber: episode.episodeNumber,
        road: episode.road,
        downloadedEpisodes: downloadedEpisodes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        needTopOffset: false,
        toolbarHeight: 72,
        title: Text(
          '本地',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Observer(
          builder: (context) {
            final shows = _filter(_buildShows());
            return LayoutBuilder(builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final width = constraints.maxWidth.clamp(0.0, 1560.0);
              final inset =
                  (constraints.maxWidth - width) / 2 + (compact ? 16.0 : 32.0);
              final contentWidth = constraints.maxWidth - inset * 2;
              return CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, 8, inset, 12),
                    sliver: SliverToBoxAdapter(
                      child: _header(compact: compact),
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
                      sliver: _layout == _OfflineLayout.cards
                          ? _grid(shows, contentWidth)
                          : _list(shows),
                    ),
                ],
              );
            });
          },
        ),
      ),
    );
  }

  Widget _header({required bool compact}) {
    return Row(
      children: [
        Expanded(child: _searchBar()),
        const SizedBox(width: 12),
        _sortMenu(showLabel: !compact),
        const SizedBox(width: 8),
        _layoutSwitch(),
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
                  foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
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
        for (final layout in _OfflineLayout.values)
          IconButton.filledTonal(
            tooltip: layout == _OfflineLayout.cards ? '卡片布局' : '列表布局',
            isSelected: _layout == layout,
            onPressed: () => setState(() => _layout = layout),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
              visualDensity: VisualDensity.standard,
              backgroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? colors.secondaryContainer
                      : colors.surfaceContainerLow),
              foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant),
            ),
            icon: Icon(
              layout == _OfflineLayout.list
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
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
    final columns = portrait
        ? 3
        : ((contentWidth + spacing) / (minWidth + spacing)).floor().clamp(1, 6);
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
        onOpen: () => _openEpisodes(shows[index]),
      ),
    );
  }

  Widget _list(List<_OfflineShow> shows) {
    return SliverList.builder(
      itemCount: shows.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _OfflineListTile(
          key: ValueKey('offline-${shows[index].bangumiId}'),
          show: shows[index],
          onOpen: () => _openEpisodes(shows[index]),
        ),
      ),
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

class _OfflinePosterCard extends StatelessWidget {
  const _OfflinePosterCard({
    super.key,
    required this.show,
    required this.onOpen,
  });

  final _OfflineShow show;
  final VoidCallback onOpen;

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
    final completed = show.completedCount;
    final active = show.activeCount;
    final status = active > 0
        ? '已下载 $completed 集 · 下载中 $active 集'
        : '已下载 $completed 集';

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: '${show.bangumiName}，$status',
        child: InkWell(
          onTap: onOpen,
          child: Column(
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
        ),
      ),
    );
  }
}

class _OfflineListTile extends StatelessWidget {
  const _OfflineListTile({
    super.key,
    required this.show,
    required this.onOpen,
  });

  final _OfflineShow show;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final completed = show.completedCount;
    final active = show.activeCount;
    final status = active > 0
        ? '已下载 $completed 集 · 下载中 $active 集'
        : '已下载 $completed 集';

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                height: 120,
                child: _OfflineCover(
                  src: show.coverSource,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      show.bangumiName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
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
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
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
  });

  final int number;
  final String title;
  final _OfflineEpisode? entry;

  bool get downloaded => entry != null;
}

class _OfflineEpisodeSheet extends StatelessWidget {
  const _OfflineEpisodeSheet({required this.show, required this.onPlay});

  final _OfflineShow show;
  final ValueChanged<_OfflineEpisode> onPlay;

  List<_OfflineEpisodeChoice> _buildChoices(List<EpisodeInfo>? cached) {
    final downloadedByNumber = <int, _OfflineEpisode>{};
    final downloadedByName = <String, _OfflineEpisode>{};
    for (final e in show.episodes) {
      if (e.episode.status != DownloadStatus.completed) continue;
      downloadedByNumber[e.episode.episodeNumber] = e;
      final name = e.episode.episodeName.trim();
      if (name.isNotEmpty) downloadedByName[name] = e;
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
      final choices = <_OfflineEpisodeChoice>[];
      final counters = <int, int>{};
      for (final episode in cached) {
        final nameCn = episode.nameCn.trim();
        final name = episode.name.trim();
        final label = nameCn.isNotEmpty ? nameCn : name;

        if (episode.type == 0) {
          // 正片：整数集号显示「第X集」，否则退回标题。
          final n = episode.episode;
          if (n == n.roundToDouble() && n > 0) {
            final number = n.toInt();
            choices.add(
              _OfflineEpisodeChoice(
                number: number,
                title: '第$number集',
                entry: downloadedByNumber[number],
              ),
            );
          } else if (label.isNotEmpty) {
            choices.add(
              _OfflineEpisodeChoice(
                number: 0,
                title: label,
                entry: downloadedByName[nameCn] ?? downloadedByName[name],
              ),
            );
          }
          continue;
        }

        // 非正片：按类型各自顺序编号，格式「SPx nameCn/name」。
        final prefix = switch (episode.type) {
          1 => 'SP',
          2 => 'OP',
          3 => 'ED',
          _ => null,
        };
        if (prefix == null) continue;
        final index = (counters[episode.type] ?? 0) + 1;
        counters[episode.type] = index;
        final title = label.isNotEmpty ? '$prefix$index $label' : '$prefix$index';
        choices.add(
          _OfflineEpisodeChoice(
            number: 0,
            title: title,
            entry: downloadedByName[nameCn] ?? downloadedByName[name],
          ),
        );
      }
      if (choices.isNotEmpty) return choices;
    }

    // 无缓存时，退回只显示已下载完成的集。
    final completed = show.episodes
        .where((e) => e.episode.status == DownloadStatus.completed)
        .toList()
      ..sort(
        (a, b) => a.episode.episodeNumber.compareTo(b.episode.episodeNumber),
      );
    return [
      for (final e in completed)
        _OfflineEpisodeChoice(
          number: e.episode.episodeNumber,
          title: e.episode.episodeName.trim().isNotEmpty
              ? e.episode.episodeName.trim()
              : '第${e.episode.episodeNumber}集',
          entry: e,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cached = BangumiOfflineCacheRepository().readEpisodes(
      show.bangumiId,
    );
    final choices = _buildChoices(cached);
    final downloadedCount = choices.where((c) => c.downloaded).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MaterialBottomSheetHeader(
          title: show.bangumiName,
          description: cached != null && cached.isNotEmpty
              ? '共 ${choices.length} 集 · 已下载 $downloadedCount 集'
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
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
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
    this.onTap,
  });

  final String title;
  final bool downloaded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = downloaded
        ? colorScheme.onSurface
        : colorScheme.outline;

    return AnimatedContainer(
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
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: foregroundColor),
                  ),
                ),
              ),
              if (downloaded)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(
                    Icons.play_circle_rounded,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
