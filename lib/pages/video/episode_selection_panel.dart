import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/compact_source_selector.dart';
import 'package:kazumi/modules/download/download_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/utils/media.dart';

class EpisodeSelectionPanel extends StatefulWidget {
  const EpisodeSelectionPanel({
    super.key,
    required this.title,
    required this.roads,
    required this.selectedRoad,
    required this.selectedEpisode,
    required this.onEpisodeSelected,
    required this.downloads,
    this.onDownload,
    this.isOffline = false,
    this.isPlaying = false,
    this.disableAnimations = false,
    this.pluginName = '',
    this.roadFormats = const {},
    this.roadQuality = const {},
    this.sourceLatency,
  });

  final String title;
  final List<Road> roads;
  final int selectedRoad;
  final int selectedEpisode;
  final void Function(int episode, int road) onEpisodeSelected;
  final ValueChanged<int>? onDownload;
  final Map<String, DownloadEpisode> downloads;
  final bool isOffline;
  final bool isPlaying;
  final bool disableAnimations;

  /// Source plugin name; shown inline for online playback.
  final String pluginName;

  /// Per-road media format (MP4/HLS).
  final Map<int, String?> roadFormats;

  /// Per-road quality label (resolution / bitrate).
  final Map<int, String?> roadQuality;

  /// Latency of resolving the source's chapter list.
  final Duration? sourceLatency;

  @override
  EpisodeSelectionPanelState createState() => EpisodeSelectionPanelState();
}

class EpisodeSelectionPanelState extends State<EpisodeSelectionPanel> {
  final _scrollController = ScrollController();
  late final _observerController = ListObserverController(
    controller: _scrollController,
  )..cacheJumpIndexOffset = false;
  late int _visibleRoad = widget.selectedRoad;

  bool get _canLocate =>
      widget.selectedRoad >= 0 &&
      widget.selectedRoad < widget.roads.length &&
      widget.selectedEpisode > 0 &&
      widget.selectedEpisode <= widget.roads[widget.selectedRoad].data.length;

  double get _toolbarHeight =>
      math.max(56, MediaQuery.textScalerOf(context).scale(20) + 8);

  void _selectRoad(int road) {
    if (_visibleRoad == road) return;
    setState(() => _visibleRoad = road);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  String _roadName(int index) => index >= 0 && index < widget.roads.length
      ? (widget.roads[index].name.trim().isEmpty
            ? '播放线路 ${index + 1}'
            : widget.roads[index].name)
      : '暂无线路';

  /// Label shown on the collapsed selector (and option title): source + line.
  String _roadLabel(int index) {
    final line = _roadName(index);
    if (widget.isOffline) return line;
    return widget.title.trim().isEmpty ? line : '${widget.title} · $line';
  }

  /// Subtitle matching the source sheet's "source + line + info" style.
  String _roadSubtitle(int index) {
    if (widget.isOffline) {
      final count = index >= 0 && index < widget.roads.length
          ? widget.roads[index].data.length
          : 0;
      return '已缓存 · $count 集';
    }
    final count = index >= 0 && index < widget.roads.length
        ? widget.roads[index].data.length
        : 0;
    final parts = <String>[
      if (widget.pluginName.isNotEmpty) widget.pluginName,
      '$count 集',
      if (widget.roadFormats[index] != null) widget.roadFormats[index]!,
      if (widget.roadQuality[index] != null) widget.roadQuality[index]!,
      if (widget.sourceLatency != null)
        '${widget.sourceLatency!.inMilliseconds}ms',
    ];
    return parts.join(' · ');
  }

  Future<void> revealCurrentEpisode() async {
    if (!_canLocate) return;
    setState(() => _visibleRoad = widget.selectedRoad);
    // Wait for the observer to bind the road's sliver after layout.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        !_scrollController.hasClients ||
        !_canLocate ||
        _visibleRoad != widget.selectedRoad) {
      return;
    }

    final index = widget.selectedEpisode - 1;
    final toolbarHeight = _toolbarHeight;
    final item = _observerController.observeItem(index: index);
    if (item != null) {
      final top = item.renderObject
          .localToGlobal(Offset.zero, ancestor: item.viewport)
          .dy;
      if (top >= toolbarHeight &&
          top + item.renderObject.size.height <= item.viewport.size.height) {
        return;
      }
    }
    await _observerController.jumpTo(
      index: index,
      offset: (_) => toolbarHeight,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final road = _visibleRoad >= 0 && _visibleRoad < widget.roads.length
        ? widget.roads[_visibleRoad]
        : null;
    final count = road?.data.length ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        return ListViewObserver(
          controller: _observerController,
          child: Scrollbar(
            controller: _scrollController,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            widget.title.isEmpty ? '剧集列表' : widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        CompactSourceSelector<int>(
                          label: widget.isOffline ? '离线观看' : '播放线路',
                          valueLabel: _roadLabel(_visibleRoad),
                          selectedValue: _visibleRoad,
                          enabled: widget.roads.length > 1,
                          options: [
                            for (var i = 0; i < widget.roads.length; i++)
                              CompactSelectorOption(
                                value: i,
                                title: _roadLabel(i),
                                subtitle: _roadSubtitle(i),
                              ),
                          ],
                          onSelected: _selectRoad,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _EpisodeToolbar(
                    height: _toolbarHeight,
                    color: colors.surface,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              textScaler.scale(14) > 21 ||
                                      constraints.maxWidth < 320
                                  ? '$count 集'
                                  : widget.isOffline
                                  ? '已缓存 · $count 集'
                                  : '全部剧集 · $count 集',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '定位当前集',
                            onPressed: _canLocate ? revealCurrentEpisode : null,
                            icon: const Icon(
                              Icons.my_location_rounded,
                              size: 20,
                            ),
                          ),
                          if (!widget.isOffline)
                            IconButton.filledTonal(
                              tooltip: '缓存剧集',
                              onPressed: count > 0 && widget.onDownload != null
                                  ? () => widget.onDownload!(_visibleRoad)
                                  : null,
                              icon: const Icon(
                                Icons.download_rounded,
                                size: 20,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (count == 0)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: GeneralEmptyState(
                      icon: Icons.video_library_outlined,
                      title: '这条线路暂无剧集',
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      16 + MediaQuery.paddingOf(context).bottom,
                    ),
                    sliver: SliverList.builder(
                      itemCount: count,
                      itemBuilder: (context, index) {
                        final episode = index + 1;
                        final name = formatEpisodeLabel(
                          index < road!.identifier.length
                              ? road.identifier[index]
                              : '',
                        );
                        return _EpisodeRow(
                          key: ValueKey('$_visibleRoad:$episode'),
                          name: name.isEmpty ? '第$episode话' : name,
                          first: index == 0,
                          last: index == count - 1,
                          selected:
                              _visibleRoad == widget.selectedRoad &&
                              episode == widget.selectedEpisode,
                          isPlaying: widget.isPlaying,
                          isOffline: widget.isOffline,
                          download: widget.downloads[road.data[index]],
                          disableAnimations: widget.disableAnimations,
                          onTap: () =>
                              widget.onEpisodeSelected(episode, _visibleRoad),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EpisodeToolbar extends SliverPersistentHeaderDelegate {
  const _EpisodeToolbar({
    required this.height,
    required this.color,
    required this.child,
  });

  final double height;
  final Color color;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      // Fill minExtent even when desktop controls use a smaller touch target.
      SizedBox.expand(
        child: ColoredBox(color: color, child: child),
      );

  @override
  bool shouldRebuild(covariant _EpisodeToolbar oldDelegate) =>
      height != oldDelegate.height ||
      color != oldDelegate.color ||
      child != oldDelegate.child;
}

class _EpisodeRow extends StatefulWidget {
  const _EpisodeRow({
    super.key,
    required this.name,
    required this.first,
    required this.last,
    required this.selected,
    required this.isPlaying,
    required this.isOffline,
    required this.disableAnimations,
    required this.onTap,
    this.download,
  });

  final String name;
  final bool first;
  final bool last;
  final bool selected;
  final bool isPlaying;
  final bool isOffline;
  final bool disableAnimations;
  final VoidCallback onTap;
  final DownloadEpisode? download;

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow>
    with SingleTickerProviderStateMixin {
  late final _press = AnimationController.unbounded(vsync: this);

  bool get _reduceMotion =>
      widget.disableAnimations || MediaQuery.disableAnimationsOf(context);

  void _setPressed(bool pressed) {
    final target = pressed ? 1.0 : 0.0;
    if (_reduceMotion) {
      _press.value = target;
      return;
    }
    _press.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 500, ratio: 0.8),
        _press.value,
        target,
        _press.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = widget.selected ? colors.onPrimary : colors.onSurface;
    final status = widget.isOffline
        ? DownloadStatus.completed
        : widget.download?.status;
    final downloadLabel = switch (status) {
      DownloadStatus.completed => '已缓存',
      DownloadStatus.downloading => '正在缓存',
      DownloadStatus.failed => '缓存失败',
      DownloadStatus.paused => '缓存已暂停',
      DownloadStatus.pending => '等待缓存',
      DownloadStatus.resolving => '正在解析',
      _ => null,
    };
    final playbackLabel = widget.selected
        ? (widget.isPlaying ? '正在播放' : '当前选集')
        : '播放';

    final supportingText = [
      if (widget.selected) playbackLabel,
      if (!widget.isOffline && downloadLabel != null)
        status == DownloadStatus.downloading
            ? '缓存 ${(widget.download!.progressPercent.clamp(0, 1) * 100).round()}%'
            : downloadLabel,
    ].join(' · ');

    return Semantics(
      button: true,
      onTap: widget.onTap,
      selected: widget.selected,
      inMutuallyExclusiveGroup: true,
      label:
          '${widget.name}，$playbackLabel'
          '${downloadLabel == null ? '' : '，$downloadLabel'}',
      child: Tooltip(
        message:
            '${widget.name} · $playbackLabel'
            '${downloadLabel == null ? '' : ' · $downloadLabel'}',
        excludeFromSemantics: true,
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, child) {
            final restShape = widget.selected
                ? BorderRadius.circular(20)
                : BorderRadius.vertical(
                    top: Radius.circular(widget.first ? 20 : 4),
                    bottom: Radius.circular(widget.last ? 20 : 4),
                  );
            final press = _press.value.clamp(0.0, 1.0);
            return Padding(
              padding: EdgeInsets.only(bottom: widget.last ? 0 : 2),
              child: Material(
                animationDuration: _reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                color: widget.selected
                    ? colors.primary
                    : colors.surfaceContainerLow,
                borderRadius: BorderRadius.lerp(
                  restShape,
                  BorderRadius.circular(12),
                  press,
                ),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            );
          },
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: _setPressed,
            excludeFromSemantics: true,
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed) ||
                  states.contains(WidgetState.focused)) {
                return foreground.withValues(alpha: 0.1);
              }
              if (states.contains(WidgetState.hovered)) {
                return foreground.withValues(alpha: 0.08);
              }
              return null;
            }),
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: foreground,
                          fontWeight: widget.selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      if (supportingText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          supportingText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: widget.selected
                                ? foreground
                                : status == DownloadStatus.failed
                                ? colors.error
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
